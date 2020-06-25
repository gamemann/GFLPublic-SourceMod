#include <sourcemod>
#include <sdktools>
#include <GFL-Core>
#include <GFL-MySQL>
#include <multicolors>
#include <ripext>

#undef REQUIRE_PLUGIN
#include <updater>

#define UPDATE_URL "http://updater.gflclan.com/GFL-UserManagement.txt"
#define PL_VERSION "1.0.0"

// Groups
GroupId g_gidMember;
GroupId g_gidSupporter;
GroupId g_gidVIP;

// ConVars
ConVar g_cvURL = null;
ConVar g_cvEndpoint = null;
ConVar g_cvToken = null;
ConVar g_cvDebug = null;

// ConVar Values
char g_sURL[1024];
char g_sEndpoint[1024];
char g_sToken[64];
bool g_bDebug = false;

// Other
bool g_bGroupsValid;

HTTPClient httpClient;

public Plugin myinfo = 
{
	name = "GFL-UserManagement",
	author = "Roy (Christian Deacon) and N1ckles",
	description = "USer management plugin for Members, Supporters, and VIPs.",
	version = PL_VERSION,
	url = "GFLClan.com"
};

// Core Events
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{	
	return APLRes_Success;
}

public void OnPluginStart()
{
	ForwardConVars();
	
	// Add to updater, if the library exists.
	if (LibraryExists("updater"))
	{
        Updater_AddPlugin(UPDATE_URL)
    }
	
	// Load Translations.
	LoadTranslations("GFL-UserManagement.phrases.txt");
	
	// Add Admin Commands.
	RegAdminCmd("sm_reloadusers", Command_ReloadUsers, ADMFLAG_ROOT);
}

public void OnConfigsExecuted()
{
	// Fetch values
	ForwardValues();
	
	// Hook cv changes
	HookConVarChange(g_cvURL, CVarChanged);
	HookConVarChange(g_cvToken, CVarChanged);
	HookConVarChange(g_cvDebug, CVarChanged);
}

public void OnRebuildAdminCache(AdminCachePart part)
{	
	// Only do something if admins are being rebuild
	if(part != AdminCache_Admins)
	{
		return;
	}
	
	if(g_bDebug)
	{
		GFLCore_LogMessage("usermanagement-debug.log", "[GFL-UserManagement] OnRebuildAdminCache() :: Cache is being rebuilt! Delaying execution to respect SourceBans.");
	}
	
	// Reload users after a second.
	CreateTimer(1.0, Timer_RebuildCache);
}

// ConVars
void ForwardConVars()
{
	g_cvURL = CreateConVar("sm_gflum_url", "something.com", "The Restful API URL.");
	g_cvEndpoint = CreateConVar("sm_gflum_endpoint", "index.php", "The Restful API endpoint. ");
	g_cvToken = CreateConVar("sm_gflum_token", "", "The token to use when accessing the API.");
	g_cvDebug = CreateConVar("sm_gflum_debug", "0", "Logging level increased for debugging.");
	
	AutoExecConfig(true, "GFL-UserManagement");
}

void ForwardValues()
{
	GetConVarString(g_cvURL, g_sURL, sizeof(g_sURL));
	GetConVarString(g_cvEndpoint, g_sEndpoint, sizeof(g_sEndpoint));
	GetConVarString(g_cvToken, g_sToken, sizeof(g_sToken));
	g_bDebug = g_cvDebug.BoolValue;
	
	// Create the httpClient.
	if (httpClient != null)
	{
		delete httpClient;
	}
	
	httpClient = new HTTPClient(g_sURL);
	
	if (g_bDebug)
	{
		GFLCore_LogMessage("usermanagement-debug.log", "[GFL-UserManagement] ForwardValues() :: Made HTTPClient with %s", g_sURL);
	}
}

public void CVarChanged(Handle hCVar, const char[] OldV, const char[] NewV)
{
	if(g_bDebug)
	{
		GFLCore_LogMessage("usermanagement-debug.log", "[GFL-UserManagement] CVarChanged() :: A CVar has been altered.");
	}
	
	// Get values again
	ForwardValues();
}

public Action Timer_RebuildCache(Handle hTimer)
{
	if (g_bDebug)
	{
		GFLCore_LogMessage("usermanagement-debug.log", "[GFL-UserManagement] Timer_RebuildCache() :: Executed...");
	}
	
	LoadUsers();
}

public void OnClientAuthorized(int iClient, const char[] sAuth2)
{
	// Let's load the client.
	LoadUser(iClient);
}

void LoadUser(int iClient)
{	
	// Check if groups are valid.
	if (!g_bGroupsValid)
	{
		return;
	}
	
	// Get their Steam ID 64.
	char sSteamID64[64];
	GetClientAuthId(iClient, AuthId_SteamID64, sSteamID64, sizeof(sSteamID64), true);
	
	// Format the GET string.
	char sGetString[256];
	Format(sGetString, sizeof(sGetString), "%s?steamid=%s", g_sEndpoint, sSteamID64);
	
	// Set authentication header.
	httpClient.SetHeader("Authorization", g_sToken);
	
	// Execute the GET request.
	httpClient.Get(sGetString, PerkJSONReceived, GetClientUserId(iClient));
	
	// Debug.
	if (g_bDebug)
	{
		GFLCore_LogMessage("usermanagement-debug.log", "[GFL-UserManagement] LoadUser() :: Loading %N (%d) (Steam ID: %s) now... Full Endpoint URL is %s. Token = %s.", iClient, iClient, sSteamID64, sGetString, g_sToken);
	}
}

public void PerkJSONReceived(HTTPResponse response, any UserID)
{
	// Receive client ID.
	int iClient = GetClientOfUserId(UserID);
	
	// Get their Steam ID 64.
	char sSteamID64[64];
	GetClientAuthId(iClient, AuthId_SteamID64, sSteamID64, sizeof(sSteamID64), true);
	
	// Check if the response errored out.
	if (response.Status != HTTPStatus_OK)
	{
		// Welp, fuck...
		GFLCore_LogMessage("", "[GFL-UserManagement] PerkJSONReceived() :: Error with GET reqeust (Error code: %d, Steam ID: %s)", response.Status, sSteamID64);
		
		return;
	}
	
	// Check if the JSON response is valid.
	if (response.Data == null)
	{
		// RIP...
		GFLCore_LogMessage("", "[GFL-UserManagement] PerkJSONReceived() :: Data is null. (Steam ID: %s)", sSteamID64);
		
		return;
	}
	
	JSONObject stuff = view_as<JSONObject>(response.Data);
	
	// First, let's check for a custom error.
	int iError = stuff.GetInt("error");
	
	// Check if invalid token.
	if (iError == 401)
	{
		GFLCore_LogMessage("", "[GFL-UserManagement] PerkJSONReceived() :: INVALID TOKEN. PLEASE CONTACT A DIRECTOR. (Steam ID: %s)", sSteamID64);
		
		return;
	}
	
	// Receive the perk.
	int iGroupID = stuff.GetInt("group");
	
	AssignPerks(iClient, iGroupID);
	
	// Debugging...
	if (g_bDebug)
	{
		GFLCore_LogMessage("usermanagement-debug.log", "[GFL-UserManagement] PerkJSONReceived() :: Assigning perks to %N (Steam ID: %s) group ID is %i", iClient, sSteamID64, iGroupID);
	}
}

void AssignPerks(int iClient, int iGroupID)
{
	// Get Steam ID 2.
	char sSteamID2[64];
	GetClientAuthId(iClient, AuthId_Steam2, sSteamID2, sizeof(sSteamID2), true);
	
	// Check if valid group range.
	if (iGroupID < 1 || iGroupID > 3)
	{	
		// What, the fuck...
		GFLCore_LogMessage("", "[GFL-UserManagement] AssignPerks() :: %N (Steam ID: %s) has a group ID (%d) out-of-range. Either doesn't exist or bad range.", iClient, sSteamID2, iGroupID);
		
		return;
	}
	
	// Get the admin.
	AdminId aAdmin = GetUserAdmin(iClient);
	
	// Check if they're an admin already.
	if (aAdmin == INVALID_ADMIN_ID)
	{
		if (g_bDebug)
		{
			GFLCore_LogMessage("usermanagement-debug.log", "[GFL-UserManagement] AssignPerks() :: Admin not built for %N (Steam ID: %s). Building...", iClient, sSteamID2);
		}
		
		aAdmin = CreateAdmin("");
	}
	else
	{
		if (g_bDebug)
		{
			GFLCore_LogMessage("usermanagement-debug.log", "[GFL-UserManagement] AssignPerks() :: Admin already built for %N (Steam ID: %s). Continuing...", iClient, sSteamID2);
		}
	}
	
	// Bind the admin to the Steam ID 2.
	aAdmin.BindIdentity("steam", sSteamID2);
	
	// Check if Member.
	if (iGroupID == 1)
	{
		aAdmin.InheritGroup(g_gidMember);
	}	
	// Check if Supporter.
	else if (iGroupID == 2)
	{
		aAdmin.InheritGroup(g_gidSupporter);
	}	
	// Check if VIP.
	else if (iGroupID == 3)
	{
		aAdmin.InheritGroup(g_gidVIP);
	}
	
	// Debug message FTW!!!
	if (g_bDebug)
	{
		GFLCore_LogMessage("usermanagement-debug.log", "[GFL-UserManagement] AssignPerks() :: Assigned group #%d to %N (%d) (Steam ID: %s).", iGroupID, iClient, iClient, sSteamID2);
	}

	// Run SourceMod-related checks, etc.
	if (IsClientInGame(iClient))
	{
		RunAdminCacheChecks(iClient);
	}
}

void ValidateGroups()
{
	// Debugging...
	if (g_bDebug)
	{
		GFLCore_LogMessage("usermanagement-debug.log", "[GFL-UserManagement] ValidateGroups() :: Executed...");
	}
	
	// Set default to true.
	g_bGroupsValid = true;
	
	// Find the groups firstly.
	g_gidMember = FindAdmGroup("Member");
	g_gidSupporter = FindAdmGroup("Supporter");
	g_gidVIP = FindAdmGroup("VIP");
	
	if (g_gidMember == INVALID_GROUP_ID)
	{
		GFLCore_LogMessage("", "[GFL-UserManagement] ValidateGroups() :: Member group has an invalid group ID. Please make sure the group exists in SourceBans and has at least one flag.");
		g_bGroupsValid = false;
	}	
	
	if (g_gidSupporter == INVALID_GROUP_ID)
	{
		GFLCore_LogMessage("", "[GFL-UserManagement] ValidateGroups() :: Supporter group has an invalid group ID. Please make sure the group exists in SourceBans and has at least one flag.");
		g_bGroupsValid = false;
	}	
	
	if (g_gidVIP == INVALID_GROUP_ID)
	{
		GFLCore_LogMessage("", "[GFL-UserManagement] ValidateGroups() :: VIP group has an invalid group ID. Please make sure the group exists in SourceBans and has at least one flag.");
		g_bGroupsValid = false;
	}
}

void LoadUsers()
{
	// Debugging...
	if (g_bDebug)
	{
		GFLCore_LogMessage("usermanagement-debug.log", "[GFL-UserManagement] LoadUsers() :: Executed...");
	}
	
	// Validate groups.
	ValidateGroups();
	
	// Loop through each user and load them.
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			// Nah....
			continue;
		}
		
		LoadUser(i);
	}
}

public Action Command_ReloadUsers(int iClient, int iArgs)
{
	// Debugging...
	if (g_bDebug)
	{
		GFLCore_LogMessage("usermanagement-debug.log", "[GFL-UserManagement] Command_ReloadUsers() :: Executed by %N...", iClient);
	}
	
	CReplyToCommand(iClient, "%t%t", "UserManagementTag", "ReloadUsersReply");
	
	LoadUsers();
	
	return Plugin_Handled;
}