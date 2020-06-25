#include <sourcemod>
#include <sdktools>
#include <GFL-Core>
#include <clientprefs>
#include <multicolors>

#undef REQUIRE_PLUGIN
#include <updater>

#define UPDATE_URL "http://updater.gflclan.com/GFL-Core.txt"
#define PL_VERSION "1.0.1"

// Forwars
Handle g_hOnUnload;
Handle g_hOnLoad;

// ConVars
ConVar g_hLogging = null;
ConVar g_hLoggingPath = null;
ConVar g_hLogPrint = null;
ConVar g_hAdFlag = null;

// ConVar Values
bool g_bLogging;
char g_sLoggingPath[PLATFORM_MAX_PATH];
bool g_bLogPrint;
char g_sAdFlag[32];

// Other Values
Handle g_hClientCookie;
bool g_bAdsDisabled[MAXPLAYERS + 1];

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sErr, int iErrMax) 
{
	CreateNative("GFLCore_LogMessage", Native_GFLCore_LogMessage);
	CreateNative("GFLCore_ClientAds", Native_GFLCore_ClientAds);
	
	RegPluginLibrary("GFL-Core");
	
	return APLRes_Success;
}

public void OnLibraryAdded(const char[] sLName) 
{
	if (StrEqual(sLName, "updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
}

public Plugin myinfo = 
{
	name = "GFL-Core",
	author = "Christian Deacon (Roy) and Ariistuujj",
	description = "GFL's plugin core.",
	version = PL_VERSION,
	url = "GFLClan.com & TheDevelopingCommunity.com"
};

public void OnPluginStart() 
{
	Forwards();
	ForwardConVars();
	ForwardCommands();
	
	// Cookies
	g_hClientCookie = RegClientCookie("GFL-DisableAds", "Disables GFL Advertisements and Server Hop Ads", CookieAccess_Protected);
	
	// Translations
	LoadTranslations("GFL-Core.phrases.txt");
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!AreClientCookiesCached(i))
		{
			continue;
		}
		
		OnClientCookiesCached(i);
	}
}

stock void Forwards()
{
	g_hOnUnload = CreateGlobalForward("GFLCore_OnUnload", ET_Event);
	g_hOnLoad = CreateGlobalForward("GFLCore_OnLoad", ET_Event);
}

stock void ForwardConVars() 
{
	g_hLogging = CreateConVar("sm_gflcore_Logging", "1", "Enable logging for GFL's plugins?");
	HookConVarChange(g_hLogging, CVarChanged);
	
	g_hLoggingPath = CreateConVar("sm_gflcore_LoggingPath", "logs/GFL/", "The path starting from SourceMod/ that the logs will be entered in.");
	HookConVarChange(g_hLoggingPath, CVarChanged);	
	
	g_hLogPrint = CreateConVar("sm_gflcore_LogPrint", "1", "If 1, all GFLCore_LogMessage() messages will also be printed to the server console.");
	HookConVarChange(g_hLogPrint, CVarChanged);	
	
	g_hAdFlag = CreateConVar("sm_gflcore_Ad_Flag", "a", "The flag required to disable advertisements.");
	HookConVarChange(g_hAdFlag, CVarChanged);	
	
	AutoExecConfig(true, "GFL-Core");
}

stock void ForwardCommands() 
{
	RegConsoleCmd("sm_disableads", Command_DisableAds);
}

public void OnClientCookiesCached(int iClient)
{
	char sValue[11];
	GetClientCookie(iClient, g_hClientCookie, sValue, sizeof(sValue));
	
	if (StringToInt(sValue) == 0)
	{
		g_bAdsDisabled[iClient] = false;
	}
	else if (StringToInt(sValue) == 1)
	{
		g_bAdsDisabled[iClient] = true;
	}
}

public void OnPluginEnd()
{
	Call_StartForward(g_hOnUnload);
	Call_Finish();
}

public void CVarChanged(Handle hCVar, const char[] sOldV, const char[] sNewV)
{
	ForwardValues();
}

public void OnConfigsExecuted() 
{
	ForwardValues();
	
	/* Call the OnLoad forward. */
	Call_StartForward(g_hOnLoad);
	Call_Finish();
}

stock void ForwardValues() 
{
	g_bLogging = GetConVarBool(g_hLogging);
	GetConVarString(g_hLoggingPath, g_sLoggingPath, sizeof(g_sLoggingPath));
	g_bLogPrint = GetConVarBool(g_hLogPrint);
	GetConVarString(g_hAdFlag, g_sAdFlag, sizeof(g_sAdFlag));
	
	if (g_bLogging)
	{
		GFLCore_LogMessage("", "[GFL-Core] Logging Started...");
	}
}

public Action Command_DisableAds(int iClient, int iArgs)
{
	if (!IsClientInGame(iClient))
	{
		return Plugin_Handled;
	}
	
	if (!HasPermission(iClient, g_sAdFlag))
	{
		CReplyToCommand(iClient, "%t%t", "Tag", "AdsDenyMessage");
	}
	
	if (g_bAdsDisabled[iClient])
	{
		SetClientCookie(iClient, g_hClientCookie, "0");
		g_bAdsDisabled[iClient] = false;
		
		CReplyToCommand(iClient, "%t%t", "Tag", "AdsEnabled");
	}
	else
	{
		SetClientCookie(iClient, g_hClientCookie, "1");
		g_bAdsDisabled[iClient] = true;
		
		CReplyToCommand(iClient, "%t%t", "Tag", "AdsDisabled");
	}
	
	return Plugin_Handled;
	
}

/* NATIVES */
public int Native_GFLCore_LogMessage(Handle hPlugin, int iNumParmas) 
{
	if (g_bLogging) 
	{
		char sMsg[4096], sFileName[PLATFORM_MAX_PATH], sDate[MAX_NAME_LENGTH];
		GetNativeString(1, sFileName, sizeof(sFileName));
		GetNativeString(2, sMsg, sizeof(sMsg));
		
		char sFormattedMsg[4096];
		FormatNativeString(0, 0, 3, sizeof(sFormattedMsg), _, sFormattedMsg, sMsg);
		
		FormatTime(sDate, sizeof(sDate), "%m-%d-%y", GetTime());
		
		char sFile[PLATFORM_MAX_PATH];
		
		if (strlen(sFileName) > 0) 
		{
			strcopy(sFile, sizeof(sFile), sFileName);
		} 
		else 
		{
			Format(sFile, sizeof(sFile), "%s.log", sDate);
		}
		
		char sPath[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s", g_sLoggingPath, sFile);
		Handle hFile = OpenFile(sPath, "a");
		
		if (hFile != null) 
		{
			char sFullMsg[4096], sFullDate[256];
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
			
			delete hFile;
		} 
		else 
		{
			LogError("[GFL-Core]Failed to log message. Cannot open/read/write file.");
			return false;
		}
	}
	
	return true;
}

public int Native_GFLCore_ClientAds(Handle hPlugin, int iNumParmas)
{
	int iClient = GetNativeCell(1);
	
	if (IsClientInGame(iClient))
	{
		if (HasPermission(iClient, "a") && g_bAdsDisabled[iClient])
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
stock bool HasPermission(int iClient, char[] sFlagString) 
{
	if (StrEqual(sFlagString, ""))
	{	
		return true;
	}
	
	AdminId eAdmin = GetUserAdmin(iClient);
	
	if (eAdmin != INVALID_ADMIN_ID)
	{
		int iFlags = ReadFlagString(sFlagString);

		if (CheckAccess(eAdmin, "", iFlags, true))
		{
			return true;
		}
	}

	return false;
}