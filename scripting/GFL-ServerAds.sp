#include <sourcemod>
#include <sdktools>
#include <multicolors>
#include <GFL-Core>
#include <GFL-MySQL>
#include <GFL-ServerAds>
#undef REQUIRE_PLUGIN
#include <updater>

//#define DEVELOPDEBUG
#define MAXADS 128
#define UPDATE_URL "http://updater.gflclan.com/core.txt"

enum ServerAds
{
	iID,
	String:sMsg[1024],
	iGameID,
	iServerID,
	iPaid,
	iUID,
	iCustom,
	iChatType
}

new g_arrServerAds[MAXADS][ServerAds];

// Forwards
new Handle:g_hOnDefaultAd;
new Handle:g_hOnPaidAd;
new Handle:g_hOnErrorCountReached;

// ConVars
new Handle:g_hAdInterval = INVALID_HANDLE;
new Handle:g_hCustomAdsFile = INVALID_HANDLE;
new Handle:g_hEnableErrorReachLimit;

// ConVar Values
new Float:g_fAdInterval;
new String:g_sCustomAdsFile[PLATFORM_MAX_PATH];
new bool:g_bEnableErrorReachLimit;

// Other
new Handle:g_hDB = INVALID_HANDLE;
new bool:g_bEnabled = false;
new bool:g_bCoreEnabled = false;
new bool:g_bServerHop = false;
new g_iCurAd = 0;
new g_iAdCount = 0;
new g_iSQLErrorCount = 0;

public APLRes:AskPluginLoad2(Handle:hMyself, bool:bLate, String:sErr[], iErrMax) 
{
	RegPluginLibrary("GFL-ServerAds");
	
	return APLRes_Success;
}

public OnLibraryAdded(const String:sLName[]) 
{
	if (StrEqual(sLName, "GFL-MySQL"))
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] OnLibraryAdded() :: GFL MySQL library found.");
		#endif
	}
	
	if (StrEqual(sLName, "GFL-ServerHop"))
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] OnLibraryAdded() :: GFL Server Hop library found.");
		#endif
		g_bServerHop = true;
	}
	
	if (StrEqual(sLName, "updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
}

public Plugin:myinfo = 
{
	name = "GFL-ServerAds",
	description = "GFL's Server Adverts plugin.",
	author = "Roy (Christian Deacon)",
	version = PL_VERSION,
	url = "GFLClan.com & TheDevelopingCommunity.com"
};

public OnPluginStart() 
{
	Forwards();
	ForwardConVars();
	ForwardCommands();
}

stock Forwards() 
{
	g_hOnDefaultAd = CreateGlobalForward("GFLSA_OnDefaultAd", ET_Event);
	g_hOnPaidAd = CreateGlobalForward("GFLSA_OnPaidAd", ET_Event);
	g_hOnErrorCountReached = CreateGlobalForward("GFLSA_OnErrorCountReached", ET_Event);
	
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] Forwards() :: Executed.");
		#endif
}

stock ForwardConVars() 
{
	CreateConVar("GFLServerAds_version", PL_VERSION, "GFL's Server Ads version.");
	
	g_hAdInterval = CreateConVar("sm_gflsa_ad_interval", "30.00", "Time in-between advertisements.");
	HookConVarChange(g_hAdInterval, CVarChanged);
	
	g_hCustomAdsFile = CreateConVar("sm_gflsa_custom_ads_file", "customads.txt", "The file name that displays custom server ads in the sourcemod/configs directory.");
	HookConVarChange(g_hCustomAdsFile, CVarChanged);	
	
	g_hEnableErrorReachLimit = CreateConVar("sm_gflsa_enable_error_reach_limit", "1", "If 1, will retry the database if the MySQL error count is reached.");
	HookConVarChange(g_hEnableErrorReachLimit, CVarChanged);
	
	AutoExecConfig(true, "GFL-ServerAds");
}

public CVarChanged(Handle:hCVar, const String:OldV[], const String:NewV[]) 
{
	ForwardValues();
}

stock ForwardCommands() 
{
	RegAdminCmd("sm_sa_update", Command_UpdateAds, ADMFLAG_ROOT);
	RegAdminCmd("sm_sa_printarray", Command_PrintArray, ADMFLAG_SLAY);
}

public OnConfigsExecuted() 
{
	ForwardValues();
}

stock ForwardValues() 
{
	g_fAdInterval = GetConVarFloat(g_hAdInterval);
	GetConVarString(g_hCustomAdsFile, g_sCustomAdsFile, sizeof(g_sCustomAdsFile));
	g_bEnableErrorReachLimit = GetConVarBool(g_hEnableErrorReachLimit);
}

public GFLMySQL_OnDatabaseConnected(Handle:hDB)
{
	if (hDB != INVALID_HANDLE)
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] GFLMySQL_OnDatabaseConnected() :: Reached.");
		#endif
		g_hDB = hDB;
		g_bEnabled = true;
		
		UpdateAdverts();
	}
	#if defined DEVELOPDEBUG then
		GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] GFLMySQL_OnDatabaseConnected() :: Finished.");
	#endif
		
	CreateTimer(g_fAdInterval, DisplayAdvert, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

public GFLCore_OnLoad()
{
	#if defined DEVELOPDEBUG then
		GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] GFLCore_OnLoad() :: Loaded.");
	#endif
	
	g_bCoreEnabled = true;
}

public GFLCore_OnUnload()
{
	#if defined DEVELOPDEBUG then
		GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] GFLCore_OnUnload() :: Loaded.");
	#endif
	
	g_bCoreEnabled = false;
}

public UpdateAdverts()
{
	#if defined DEVELOPDEBUG then
		GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] UpdateAdverts() :: Reached.");
	#endif
	if (!g_bEnabled || !g_bCoreEnabled)
	{
		if (!g_bEnabled)
		{
			#if defined DEVELOPDEBUG then
				GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] UpdateAdverts() :: Ended early. g_bEnabled = false.");
			#endif
		}
		
		if (g_bCoreEnabled)
		{
			#if defined DEVELOPDEBUG then
				GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] UpdateAdverts() :: Ended early. g_bCoreEnabled = false.");
			#endif
		}
		
		return;
	}
	
	if (g_hDB == INVALID_HANDLE)
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] UpdateAdverts() :: Ended early. g_hDB = INVALID_HANDLE.");
		#endif
		
		GFLCore_LogMessage("", "[GFL-ServerAds] UpdateAdverts() :: Error: Database handle is invalid. Plugin Disabled.");
		g_bEnabled = false;
		return;
	}
	
	// Clear the advertisements.
	ClearServerAdsArray();
	g_iAdCount = 0;
	
	// Default Advertisements.
	decl String:sQuery[256];
	Format(sQuery, sizeof(sQuery), "SELECT * FROM `gfl_adverts-default`");
	SQL_TQuery(g_hDB, AdvertsDefaultCallback, sQuery, _, DBPrio_High);
	
	// Paid Advertisements.
	decl String:sQuery2[256];
	Format(sQuery2, sizeof(sQuery2), "SELECT * FROM `gfl_adverts-paid` WHERE `activated`=1");
	SQL_TQuery(g_hDB, AdvertsPaidCallback, sQuery2, _, DBPrio_High);
	
	// Custom Advertisements
	decl String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/%s", g_sCustomAdsFile);
	new Handle:hKV = CreateKeyValues("CustomAdverts");
	FileToKeyValues(hKV, sPath);
	
	if (KvGotoFirstSubKey(hKV))
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] UpdateAdverts()->CustomAdverts() :: GotoFirstSubKey = true.");
		#endif
		decl String:sSectionName[11];
		do 
		{
			KvGetSectionName(hKV, sSectionName, sizeof(sSectionName));
			
			g_arrServerAds[g_iAdCount][iID] = StringToInt(sSectionName);
			g_arrServerAds[g_iAdCount][iChatType] = KvGetNum(hKV, "chat-type");
			KvGetString(hKV, "message", g_arrServerAds[g_iAdCount][sMsg], 1024);
		
			g_iAdCount++;
		} while (KvGotoNextKey(hKV));		
		KvRewind(hKV);
		KvGotoFirstSubKey(hKV)
	}
	
}

public AdvertsDefaultCallback(Handle:hOwner, Handle:hHndl, const String:sErr[], any:data)
{	
	if (hOwner == INVALID_HANDLE)
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] AdvertsDefaultCallback() :: hOwner = INVALID_HANDLE.");
		#endif
		if (g_bEnableErrorReachLimit) 
		{
			g_iSQLErrorCount++;
			if (g_iSQLErrorCount > 5)
			{
				g_iSQLErrorCount = 0;
				if (StrContains(sErr, "10061")) 
				{
					#if defined DEVELOPDEBUG then
						GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] AdvertsDefaultCallback() :: Error count reached.");
					#endif
					
					Call_StartForward(g_hOnErrorCountReached);
					Call_Finish();
				}
			}
		}
		
		GFLCore_LogMessage("", "[GFL-ServerAds] Error on AdvertsDefault query. Error: %s (%i/5)", sErr, g_iSQLErrorCount);
		g_bEnabled = false;
	}
	
	if (hHndl != INVALID_HANDLE)
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] AdvertsDefaultCallback():: hHndl != INVALID_HANDLE.");
		#endif
		
		g_iSQLErrorCount = 0;
		
		while (SQL_FetchRow(hHndl))
		{
			g_arrServerAds[g_iAdCount][iID] = SQL_FetchInt(hHndl, 0);
			SQL_FetchString(hHndl, 1, g_arrServerAds[g_iAdCount][sMsg], 1024);
			g_arrServerAds[g_iAdCount][iGameID] = SQL_FetchInt(hHndl, 2);
			g_arrServerAds[g_iAdCount][iServerID] = SQL_FetchInt(hHndl, 3);
			g_arrServerAds[g_iAdCount][iChatType] = SQL_FetchInt(hHndl, 4);
			
			g_iAdCount++;
		}
	}
	else
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] AdvertsDefaultCallback() :: hHndl = INVALID_HANDLE. Error: (%s).", sErr);
		#endif
	}
}

public AdvertsPaidCallback(Handle:hOwner, Handle:hHndl, const String:sErr[], any:data)
{
	if (hOwner == INVALID_HANDLE)
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] AdvertsPaidCallback() :: hOwner = INVALID_HANDLE;");
		#endif
		if (g_bEnableErrorReachLimit) 
		{
			g_iSQLErrorCount++;
			if (g_iSQLErrorCount > 5)
			{
				g_iSQLErrorCount = 0;
				if (StrContains(sErr, "10061")) 
				{
					#if defined DEVELOPDEBUG then
						GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] AdvertsPaidCallback() :: Error Count reached.");
					#endif
					Call_StartForward(g_hOnErrorCountReached);
					Call_Finish();
				}
			}
		}
		
		GFLCore_LogMessage("", "[GFL-ServerAds] AdvertsPaid() :: Error: %s (%i/5)", sErr, g_iSQLErrorCount);
		g_bEnabled = false;
	}
	
	if (hHndl != INVALID_HANDLE)
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] AdvertsPaidCallback() :: hHndl != INVALID_HANDLE.");
		#endif
		
		g_iSQLErrorCount = 0;
		
		while (SQL_FetchRow(hHndl))
		{
			g_arrServerAds[g_iAdCount][iID] = SQL_FetchInt(hHndl, 0);
			g_arrServerAds[g_iAdCount][iUID] = SQL_FetchInt(hHndl, 2);
			SQL_FetchString(hHndl, 4, g_arrServerAds[g_iAdCount][sMsg], 1024);
			g_arrServerAds[g_iAdCount][iChatType] = SQL_FetchInt(hHndl, 5);
			
			g_arrServerAds[g_iAdCount][iPaid] = 1;
			
			g_iAdCount++;
		}
	}
	else
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] AdvertsPaidCallback() :: hHndl = INVALID_HANDLE. Error: (%s).", sErr);
		#endif
	}
}

public Action:DisplayAdvert(Handle:hTimer)
{
	if (!g_bEnabled || !g_bCoreEnabled)
	{
		if (!g_bEnabled)
		{
			#if defined DEVELOPDEBUG then
				GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] DisplayAdvert() :: Ended early. g_bEnabled = false.");
			#endif
		}
		
		if (g_bCoreEnabled)
		{
			#if defined DEVELOPDEBUG then
				GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] DisplayAdvert() :: Ended early. g_bCoreEnabled = false.");
			#endif
		}
		
		return;
	}
	
	// Display the correct advert!
	if (!StrEqual(g_arrServerAds[g_iCurAd][sMsg], ""))
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] DisplayAdvert() :: sMsg != \"\"");
		#endif
		
		decl String:sFormattedMsg[1024];
		if (g_arrServerAds[g_iCurAd][iPaid] == 1)
		{
			Format(sFormattedMsg, sizeof(sFormattedMsg), "> {darkred}[AD]{default}%s", g_arrServerAds[g_iCurAd][sMsg]);
			for (new iClient = 1; iClient <= MaxClients; iClient++)
			{
				if (!IsClientInGame(iClient) || !GFLCore_ClientAds(iClient))
				{
					continue;
				}
				
				if (g_arrServerAds[g_iCurAd][iChatType] == 1)
				{
					CPrintToChat(iClient, sFormattedMsg);
				}
				else if (g_arrServerAds[g_iCurAd][iChatType] == 2)
				{
					PrintCenterText(iClient, sFormattedMsg);
				}		
				else if (g_arrServerAds[g_iCurAd][iChatType] == 3)
				{
					PrintHintText(iClient, sFormattedMsg);
				}
			}
			
			// Call the Forward.
			Call_StartForward(g_hOnPaidAd);
			Call_Finish();
		}
		else
		{
			Format(sFormattedMsg, sizeof(sFormattedMsg), "> %s", g_arrServerAds[g_iCurAd][sMsg]);
			for (new iClient = 1; iClient <= MaxClients; iClient++)
			{
				if (!IsClientInGame(iClient) || !GFLCore_ClientAds(iClient))
				{
					continue;
				}
				
				if (g_arrServerAds[g_iCurAd][iChatType] == 1)
				{
					CPrintToChat(iClient, sFormattedMsg);
				}
				else if (g_arrServerAds[g_iCurAd][iChatType] == 2)
				{
					PrintCenterText(iClient, sFormattedMsg);
				}		
				else if (g_arrServerAds[g_iCurAd][iChatType] == 3)
				{
					PrintHintText(iClient, sFormattedMsg);
				}
			}
			
			// Call the Forward.
			Call_StartForward(g_hOnDefaultAd);
			Call_Finish();
		}
	}
	
	g_iCurAd++;
	
	if (g_iCurAd >= g_iAdCount)
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] DisplayAdvert() :: g_iCurAd >= g_iAdCount -> true.");
		#endif
		g_iCurAd = 0;
	}
}

public Action:Command_UpdateAds(iClient, iArgs)
{
	if (!g_bEnabled || !g_bCoreEnabled)
	{
		if (!g_bEnabled)
		{
			#if defined DEVELOPDEBUG then
				GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] Command_UpdateAds() :: Ended early. g_bEnabled = false.");
			#endif
		}
		
		if (!g_bCoreEnabled)
		{
			#if defined DEVELOPDEBUG then
				GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] Command_UpdateAds() :: Ended early. g_bCoreEnabled = false.");
			#endif
		}
		
		if (iClient == 0) 
		{
			PrintToServer("[GFL-ServerAds] Plugin disabled.");
		} 
		else 
		{
			PrintToChat(iClient, "\x03[GFL-ServerAds] \x02Plugin Disabled");
		}	
		return Plugin_Handled;
	}
	
	UpdateAdverts();
	if (iClient > 0)
	{
		PrintToChat(iClient, "\x03[GFL-ServerAds]\x02Server Advertisements updated!");
	}
	else
	{
		PrintToServer("\x03[GFL-ServerAds]\x02Server Advertisements updated!");
	}
	
	return Plugin_Handled;
}

public Action:Command_PrintArray(iClient, iArgs)
{	
	PrintServerAdsArray();
	
	return Plugin_Handled;
}

stock ClearServerAdsArray()
{
	for (new i = 0; i < MAXADS; i++)
	{
		g_arrServerAds[i][iID] = -1;
		strcopy(g_arrServerAds[i][sMsg], 1024, "");
		g_arrServerAds[i][iGameID] = -1;
		g_arrServerAds[i][iServerID] = -1;
		g_arrServerAds[i][iPaid] = -1;
		g_arrServerAds[i][iUID] = -1;
		g_arrServerAds[i][iCustom] = -1;
		g_arrServerAds[i][iChatType] = -1;
	}
}

stock PrintServerAdsArray()
{
	for (new i = 0; i < MAXADS; i++)
	{
		if (!StrEqual(g_arrServerAds[i][sMsg], ""))
		{
			PrintToServer("#%i:", i);
			PrintToServer("---------------------------");
			PrintToServer("Message: %s", g_arrServerAds[i][sMsg]);
			PrintToServer("Chat Type: %i", g_arrServerAds[i][iChatType]);
			PrintToServer("Game ID: %i", g_arrServerAds[i][iGameID]);
			PrintToServer("Server ID: %i", g_arrServerAds[i][iServerID]);
			PrintToServer("Paid: %i", g_arrServerAds[i][iPaid]);
			PrintToServer("Custom: %i", g_arrServerAds[i][iCustom]);
			PrintToServer("---------------------------");
		}
	}
}