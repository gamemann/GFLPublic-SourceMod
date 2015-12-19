#include <sourcemod>
#include <sdktools>
#include <GFL-Core>
#undef REQUIRE_PLUGIN
#include <updater>
#include <clientprefs>

//#define DEVELOPDEBUG
#define UPDATE_URL "http://updater.gflclan.com/core.txt"

// Forwars
new Handle:g_hOnUnload;
new Handle:g_hOnLoad;

// ConVars
new Handle:g_hLogging = INVALID_HANDLE;
new Handle:g_hLoggingPath = INVALID_HANDLE;
new Handle:g_hLogPrint = INVALID_HANDLE;
new Handle:g_hAdFlag = INVALID_HANDLE;

new Handle:g_hHostName = INVALID_HANDLE;

// ConVar Values
new bool:g_bLogging;
new String:g_sLoggingPath[PLATFORM_MAX_PATH];
new bool:g_bLogPrint;
new String:g_sAdFlag[32];

new String:g_sHostName[MAX_NAME_LENGTH];

// Other Values
new bool:g_bBadHostName = false;
new bool:g_bFirstHostNameCheck = true;
new Handle:g_hClientCookie;
new bool:g_bAdsDisabled[256];

public APLRes:AskPluginLoad2(Handle:hMyself, bool:bLate, String:sErr[], iErrMax) 
{
	CreateNative("GFLCore_LogMessage", Native_GFLCore_LogMessage);
	CreateNative("GFLCore_CloseHandle", Native_GFLCore_CloseHandle);
	CreateNative("GFLCore_ClientAds", Native_GFLCore_ClientAds);
	
	RegPluginLibrary("GFL-Core");
	
	return APLRes_Success;
}

public OnLibraryAdded(const String:sLName[]) 
{
	if (StrEqual(sLName, "updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
}

public Plugin:myinfo = 
{
	name = "GFL-Core",
	description = "GFL's plugin core.",
	author = "Roy (Christian Deacon)",
	version = PL_VERSION,
	url = "GFLClan.com & TheDevelopingCommunity.com"
};

public OnPluginStart() 
{
	Forwards();
	ForwardConVars();
	ForwardCommands();
	
	// Cookies
	g_hClientCookie = RegClientCookie("GFL-DisableAds", "Disables GFL Advertisements and Server Hop Ads", CookieAccess_Protected);
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if (!AreClientCookiesCached(i))
		{
			continue;
		}
		
		OnClientCookiesCached(i);
	}
}

stock Forwards()
{
	g_hOnUnload = CreateGlobalForward("GFLCore_OnUnload", ET_Event);
	g_hOnLoad = CreateGlobalForward("GFLCore_OnLoad", ET_Event);
}

stock ForwardConVars() 
{
	CreateConVar("GFLCore_version", PL_VERSION, "GFL's Core version.");
	
	g_hLogging = CreateConVar("sm_GFLCore_Logging", "1", "Enable logging for GFL's plugins?");
	HookConVarChange(g_hLogging, CVarChanged);
	
	g_hLoggingPath = CreateConVar("sm_GFLCore_LoggingPath", "logs/GFL/", "The path starting from SourceMod/ that the logs will be entered in.");
	HookConVarChange(g_hLoggingPath, CVarChanged);	
	
	g_hLogPrint = CreateConVar("sm_GFLCore_LogPrint", "1", "If 1, all GFLCore_LogMessage() messages will also be printed to the server console.");
	HookConVarChange(g_hLogPrint, CVarChanged);	
	
	g_hAdFlag = CreateConVar("sm_GFLCore_Ad_Flag", "a", "The flag required to disable advertisements.");
	HookConVarChange(g_hAdFlag, CVarChanged);
	
	g_hHostName = FindConVar("hostname");
	HookConVarChange(g_hHostName, CVarChanged);
	
	AutoExecConfig(true, "GFL-Core");
}

stock ForwardCommands() 
{
	RegConsoleCmd("sm_GFLCore_version", Command_ReturnVersion);
	RegConsoleCmd("sm_disableads", Command_DisableAds);
}

public OnClientCookiesCached(iClient)
{
	decl String:sValue[11];
	GetClientCookie(iClient, g_hClientCookie, sValue, sizeof(sValue));
	
	if (StringToInt(sValue) == 0)
	{
		g_bAdsDisabled[GetClientSerial(iClient)] = false;
	}
	else if (StringToInt(sValue) == 1)
	{
		g_bAdsDisabled[GetClientSerial(iClient)] = true;
	}
}

public OnMapStart()
{
	CreateTimer(5.0, RecheckHostName);
}

public OnPluginEnd()
{
	Call_StartForward(g_hOnUnload);
	Call_Finish();
}

public CVarChanged(Handle:hCVar, const String:sOldV[], const String:sNewV[])
{
	ForwardValues();
	
	if (hCVar == g_hHostName)
	{
		if (!g_bFirstHostNameCheck)
		{
			CheckHostName();
		}
	}
}

stock CheckHostName()
{
	decl String:sHostName[MAX_NAME_LENGTH];
	GetConVarString(g_hHostName, sHostName, sizeof(sHostName));
	
	#if defined DEVELOPDEBUG then
		PrintToServer("[GFL-Core]Checking Host Name (%s)...", sHostName);
	#endif
	
	if (StrContains(sHostName, "gflclan.com", false) == -1)
	{
		#if defined DEVELOPDEBUG then
			PrintToServer("[GFL-Core]Host Name does not contain GFLClan.com...");
		#endif
		g_bBadHostName = true;
		Call_StartForward(g_hOnUnload);
		Call_Finish();
		
		GFLCore_LogMessage("", "[GFL-Core] CheckHostName() :: Host Name Changed :: Does not contain GFLClan.com. All child plugins unloaded.");
	}
	else
	{
		#if defined DEVELOPDEBUG then
			PrintToServer("[GFL-Core]Host Name does contain GFLClan.com...");
		#endif
		
		if (g_bBadHostName || g_bFirstHostNameCheck)
		{
			#if defined DEVELOPDEBUG then
				PrintToServer("[GFL-Core]g_bBadHostName set to true and loading all child plugins...");
			#endif
			g_bBadHostName = false;
			Call_StartForward(g_hOnLoad);
			Call_Finish();
			
			GFLCore_LogMessage("", "[GFL-Core] CheckHostName() :: Host Name Changed :: Does contain GFLClan.com. All child plugins weren't loaded. Loading all child plugins now.");
		}
	}
	
	g_bFirstHostNameCheck = false;
}

public Action:RecheckHostName(Handle:hTimer)
{
	CheckHostName();
}

public OnConfigsExecuted() 
{
	ForwardValues();
}

stock ForwardValues() 
{
	g_bLogging = GetConVarBool(g_hLogging);
	GetConVarString(g_hLoggingPath, g_sLoggingPath, sizeof(g_sLoggingPath));
	GetConVarString(g_hHostName, g_sHostName, sizeof(g_sHostName));
	g_bLogPrint = GetConVarBool(g_hLogPrint);
	GetConVarString(g_hAdFlag, g_sAdFlag, sizeof(g_sAdFlag));
	
	if (g_bLogging)
	{
		GFLCore_LogMessage("", "[GFL-Core] Logging Started...");
	}
}

public Action:Command_ReturnVersion(iClient, iArgs) 
{	
	return Plugin_Handled;
}

public Action:Command_DisableAds(iClient, iArgs)
{
	if (g_bBadHostName || !IsClientInGame(iClient))
	{
		return Plugin_Handled;
	}
	
	if (!HasPermission(iClient, g_sAdFlag))
	{
		ReplyToCommand(iClient, "\x03[GFL-Core]\x02You can only disable advertisements as Supporter+. Donate @ GFLClan.com!");
	}
	
	if (g_bAdsDisabled[GetClientSerial(iClient)])
	{
		SetClientCookie(iClient, g_hClientCookie, "0");
		g_bAdsDisabled[GetClientSerial(iClient)] = false;
		
		ReplyToCommand(iClient, "\x03[GFL-Core]\x02Server advertisements enabled!");
	}
	else
	{
		SetClientCookie(iClient, g_hClientCookie, "1");
		g_bAdsDisabled[GetClientSerial(iClient)] = true;
		
		ReplyToCommand(iClient, "\x03[GFL-Core]\x02Server advertisements disabled!");
	}
	
	return Plugin_Handled;
	
}

/* NATIVES */
public Native_GFLCore_LogMessage(Handle:hPlugin, iNumParmas) 
{
	if (g_bLogging) 
	{
		decl String:sMsg[1024], String:sFileName[PLATFORM_MAX_PATH], String:sDate[MAX_NAME_LENGTH];
		GetNativeString(1, sFileName, sizeof(sFileName));
		GetNativeString(2, sMsg, sizeof(sMsg));
		
		decl String:sFormattedMsg[1024];
		FormatNativeString(0, 0, 3, sizeof(sFormattedMsg), _, sFormattedMsg, sMsg);
		
		FormatTime(sDate, sizeof(sDate), "%m-%d-%y", GetTime());
		
		decl String:sFile[PLATFORM_MAX_PATH];
		
		if (strlen(sFileName) > 0) 
		{
			strcopy(sFile, sizeof(sFile), sFileName);
		} 
		else 
		{
			Format(sFile, sizeof(sFile), "%s.log", sDate);
		}
		
		decl String:sPath[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s", g_sLoggingPath, sFile);
		new Handle:hFile = OpenFile(sPath, "a");
		
		if (hFile != INVALID_HANDLE) 
		{
			decl String:sFullMsg[256], String:sFullDate[256];
			FormatTime(sFullDate, sizeof(sFullDate), "%c", GetTime());
			Format(sFullMsg, sizeof(sFullMsg), "%s [GFL-Core] %s", sFullDate, sFormattedMsg);
			
			if (g_bLogPrint)
			{
				PrintToServer(sFormattedMsg);
			}
			
			if (!WriteFileLine(hFile, sFullMsg)) 
			{
				LogError("[GFL-Core]Failed to write line to log file.");
				return false;
			}
			
			GFLCore_CloseHandle(hFile);
		} 
		else 
		{
			LogError("[GFL-Core]Failed to log message. Cannot open/read/write file.");
			return false;
		}
	}
	
	return true;
}

public Native_GFLCore_CloseHandle(Handle:hPlugin, iNumParmas) 
{
	new Handle:hHndl = Handle:GetNativeCellRef(1);
	SetNativeCellRef(1, 0);
	
	return CloseHandle(hHndl);
}

public Native_GFLCore_ClientAds(Handle:hPlugin, iNumParmas)
{
	new iClient = GetNativeCell(1);
	
	if (IsClientInGame(iClient))
	{
		if (HasPermission(iClient, "a") && g_bAdsDisabled[GetClientSerial(iClient)])
		{
			return false;
		}
		else
		{
			return true;
		}
	}
	else
	{
		return false;
	}
}

// Just a quick function.
stock bool:HasPermission(iClient, const String:flagString[]) 
{
	if (StrEqual(flagString, "")) 
	{
		return true;
	}
	
	new AdminId:admin = GetUserAdmin(iClient);
	
	if (admin != INVALID_ADMIN_ID)
	{
		new count, found, flags = ReadFlagString(flagString);
		for (new i = 0; i <= 20; i++) 
		{
			if (flags & (1<<i)) 
			{
				count++;
				
				if (GetAdminFlag(admin, AdminFlag:i)) 
				{
					found++;
				}
			}
		}

		if (count == found) {
			return true;
		}
	}

	return false;
} 