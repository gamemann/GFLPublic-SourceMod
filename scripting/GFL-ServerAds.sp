#include <sourcemod>
#include <sdktools>
#include <multicolors>
#include <GFL-Core>
#include <GFL-MySQL>
#include <GFL-ServerAds>

#undef REQUIRE_PLUGIN
#include <updater>

#define MAXADS 128
#define UPDATE_URL "http://updater.gflclan.com/GFL-ServerAds.txt"
#define PL_VERSION "1.0.1"

// ENUM's aren't supported with the new syntax. Therefore, we need to stay on the old syntax until the SourceMod Developers find a better method.
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

int g_arrServerAds[MAXADS][ServerAds];

// Forwards
Handle g_hOnDefaultAd;
Handle g_hOnPaidAd;

// ConVars
ConVar g_hAdInterval = null;
ConVar g_hCustomAdsFile = null;
ConVar g_hGlobalTableName = null;
ConVar g_hPaidTableName = null;
ConVar g_hGameID = null;
ConVar g_hDBPriority = null;
ConVar g_hAdvanceDebug = null;
ConVar g_hCreateDBTable = null;

// ConVar Values
float g_fAdInterval;
char g_sCustomAdsFile[PLATFORM_MAX_PATH];
char g_sGlobalTableName[MAX_NAME_LENGTH];
char g_sPaidTableName[MAX_NAME_LENGTH];
int g_iGameID;
int g_iDBPriority;
bool g_bAdvanceDebug;
bool g_bCreateDBTable;

// Other
Handle g_hDB = null;
bool g_bEnabled = false;
int g_iCurAd = 0;
int g_iAdCount = 0;
Handle g_hAdvertTimer = null;
bool g_bCVarsLoaded = false;

DBPriority dbPriority = DBPrio_Low;

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sErr, int iErrMax) 
{
	RegPluginLibrary("GFL-ServerAds");
	
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
	name = "GFL-ServerAds",
	author = "Christian Deacon (Roy)",
	description = "GFL's Server Advertisements plugin.",
	version = PL_VERSION,
	url = "GFLClan.com & TheDevelopingCommunity.com"
};

public void OnPluginStart() 
{
	g_bCVarsLoaded = false;
	
	Forwards();
	ForwardConVars();
	ForwardCommands();
	
	// Load Translations.
	LoadTranslations("GFL-ServerAds.phrases.txt");
	
	/* Clear the Server Ads array just in case. */
	ClearServerAdsArray();
}

stock void Forwards() 
{
	g_hOnDefaultAd = CreateGlobalForward("GFLSA_OnDefaultAd", ET_Event);
	g_hOnPaidAd = CreateGlobalForward("GFLSA_OnPaidAd", ET_Event);
}

stock void ForwardConVars() 
{	
	g_hAdInterval = CreateConVar("sm_gflsa_ad_interval", "30.00", "Time in-between advertisements.");
	HookConVarChange(g_hAdInterval, CVarChanged);
	
	g_hCustomAdsFile = CreateConVar("sm_gflsa_custom_ads_file", "customads.txt", "The file name that displays custom server ads in the sourcemod/configs directory.");
	HookConVarChange(g_hCustomAdsFile, CVarChanged);	
	
	g_hGlobalTableName = CreateConVar("sm_gflsa_global_tablename", "gfl_adverts-default", "The table name of the global advertisements.");
	HookConVarChange(g_hGlobalTableName, CVarChanged);	
	
	g_hPaidTableName = CreateConVar("sm_gflsa_paid_tablename", "gfl_adverts-paid", "The table name of the paid advertisements.");
	HookConVarChange(g_hPaidTableName, CVarChanged);		
	
	g_hGameID = CreateConVar("sm_gflsa_game_id", "4", "The server's Game ID. Find this on the GitLab page or contact Roy.");
	HookConVarChange(g_hGameID, CVarChanged);	
	
	g_hDBPriority = CreateConVar("sm_gflsa_db_priority", "1", "The priority of queries for the plugin.");
	HookConVarChange(g_hDBPriority, CVarChanged);
	
	g_hAdvanceDebug = CreateConVar("sm_gflsa_advancedebug", "0", "Enable advanced debugging for this plugin?");
	HookConVarChange(g_hAdvanceDebug, CVarChanged);
	
	g_hCreateDBTable = CreateConVar("sm_gflsa_db_createtable", "0", "Attempt to create the tables needed for this plugin if they doesn't exist.");
	HookConVarChange(g_hCreateDBTable, CVarChanged);
	
	AutoExecConfig(true, "GFL-ServerAds");
}

public void CVarChanged(Handle hCVar, const char[] OldV, const char[] NewV) 
{
	ForwardValues();
	
	if (hCVar == g_hAdInterval) 
	{
		if (g_hAdvertTimer != null)
		{
			delete g_hAdvertTimer;
		}
		
		g_hAdvertTimer = CreateTimer(g_fAdInterval, DisplayAdvert, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
	}
}

stock void ForwardCommands() 
{
	RegAdminCmd("sm_sa_update", Command_UpdateAds, ADMFLAG_ROOT);
	RegAdminCmd("sm_sa_printarray", Command_PrintArray, ADMFLAG_SLAY);
	RegAdminCmd("sm_sa_printads", Command_PrintAds, ADMFLAG_SLAY);
}

public void OnConfigsExecuted() 
{
	ForwardValues();
}

stock void ForwardValues() 
{
	g_fAdInterval = GetConVarFloat(g_hAdInterval);
	GetConVarString(g_hCustomAdsFile, g_sCustomAdsFile, sizeof(g_sCustomAdsFile));
	GetConVarString(g_hGlobalTableName, g_sGlobalTableName, sizeof(g_sGlobalTableName));
	GetConVarString(g_hPaidTableName, g_sPaidTableName, sizeof(g_sPaidTableName));
	g_iGameID = GetConVarInt(g_hGameID);
	g_iDBPriority = GetConVarInt(g_hDBPriority);
	g_bAdvanceDebug = GetConVarBool(g_hAdvanceDebug);
	g_bCreateDBTable = GetConVarBool(g_hCreateDBTable);
	
	g_bCVarsLoaded = true;
	
	if (g_iDBPriority == 0)
	{
		// High.
		dbPriority = DBPrio_High;
		
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] ForwardValues() :: DataBase priority set to high.");
		}
	}
	else if (g_iDBPriority == 1)
	{
		// Normal.
		dbPriority = DBPrio_Normal;
		
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] ForwardValues() :: DataBase priority set to normal.");
		}
	}
	else if (g_iDBPriority == 2)
	{
		// Low.
		dbPriority = DBPrio_Low;
		
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] ForwardValues() :: DataBase priority set to low.");
		}
	}
	else
	{
		// Normal.
		dbPriority = DBPrio_Normal;
		
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] ForwardValues() :: DataBase priority set to normal. (value not valid)");
		}
	}
}

public int GFLMySQL_OnDatabaseConnected(Handle hDB)
{
	if (g_bAdvanceDebug)
	{
		GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] GFLMySQL_OnDatabaseConnected() :: Executed...");
	}
	
	// Set g_bEnabled to false just in case.
	g_bEnabled = false;
	
	if (hDB != null && g_bCVarsLoaded)
	{
		g_hDB = hDB;
		g_bEnabled = true;
		
		if (g_bCreateDBTable)
		{
			CreateSQLTables();
		}
		
		UpdateAdverts();
		
		if (g_hAdvertTimer != null)
		{
			delete g_hAdvertTimer;
		}
		
		g_hAdvertTimer = CreateTimer(g_fAdInterval, DisplayAdvert, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
	}
	else
	{
		g_bEnabled = false;
		
		// Create a retry timer.
		CreateTimer(30.0, Timer_Reconnect, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
	}
}

public int GFLMySQL_OnDatabaseDown()
{
	GFLCore_LogMessage("", "[GFL-ServerAds] GFLMySQL_OnDatabaseDown() :: Executed...");
	g_bEnabled = false;
	
	if (g_hAdvertTimer != null)
	{
		delete g_hAdvertTimer;
	}

	/* Clear the Server Ads array just in case. */
	ClearServerAdsArray();
	
	// Create a retry timer.
	CreateTimer(30.0, Timer_Reconnect, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

public Action Timer_Reconnect(Handle hTimer)
{
	// Let's try to grab the database.
	Handle hDB = GFLMySQL_GetDatabase();
	
	// Check if database is valid.
	if (hDB != null)
	{
		// Attempt to reconnect.
		GFLMySQL_OnDatabaseConnected(hDB);
		
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

public void UpdateAdverts()
{
	if (g_bAdvanceDebug)
	{
		GFLCore_LogMessage("", "[GFL-ServerAds] UpdateAdverts() :: Executed.");
	}

	if (!g_bEnabled)
	{
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("", "[GFL-ServerAds] UpdateAdverts() :: Database down. Aborting...");
		}
		
		return;
	}
	
	if (g_hDB == null)
	{		
		GFLCore_LogMessage("", "[GFL-ServerAds] UpdateAdverts() :: Error: Database handle is invalid.");
		return;
	}
	
	// Clear the advertisements.
	ClearServerAdsArray();
	g_iAdCount = 0;
	
	// Global Advertisements.
	char sQuery[256];
	Format(sQuery, sizeof(sQuery), "SELECT * FROM `%s` WHERE `gameid`=0", g_sGlobalTableName);
	SQL_TQuery(g_hDB, AdvertsDefaultCallback, sQuery, _, dbPriority);
	
	// Paid Advertisements.
	char sQuery2[256];
	Format(sQuery2, sizeof(sQuery2), "SELECT * FROM `%s` WHERE `activated`=1", g_sPaidTableName);
	SQL_TQuery(g_hDB, AdvertsPaidCallback, sQuery2, _, dbPriority);
	
	// Global Game Advertisements.
	char sQuery3[256];
	Format(sQuery3, sizeof(sQuery3), "SELECT * FROM `%s` WHERE `gameid`=%d", g_sGlobalTableName, g_iGameID);
	SQL_TQuery(g_hDB, AdvertsDefaultCallback, sQuery3, _, dbPriority);
	
	// Custom Advertisements
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/%s", g_sCustomAdsFile);
	Handle hKV = CreateKeyValues("CustomAdverts");
	FileToKeyValues(hKV, sPath);
	
	if (KvGotoFirstSubKey(hKV))
	{	
		char sSectionName[11];
		
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

public void AdvertsDefaultCallback(Handle hOwner, Handle hHndl, const char[] sErr, any data)
{	
	if (hHndl != null)
	{	
		while (SQL_FetchRow(hHndl))
		{
			g_arrServerAds[g_iAdCount][iID] = SQL_FetchInt(hHndl, 0);
			SQL_FetchString(hHndl, 1, g_arrServerAds[g_iAdCount][sMsg], 1024);
			g_arrServerAds[g_iAdCount][iGameID] = SQL_FetchInt(hHndl, 2);
			g_arrServerAds[g_iAdCount][iServerID] = SQL_FetchInt(hHndl, 3);
			g_arrServerAds[g_iAdCount][iChatType] = SQL_FetchInt(hHndl, 4);
			
			if (g_bAdvanceDebug)
			{
				GFLCore_LogMessage("", "[GFL-ServerAds] AdvertsDefaultCallback() :: Added advertisement (ID: %i, Game ID: %i, Msg: \"%s\")", g_arrServerAds[g_iAdCount][iID], g_arrServerAds[g_iAdCount][iGameID], g_arrServerAds[g_iAdCount][sMsg]);
			}
			
			g_iAdCount++;
		}
	}
}

public void AdvertsPaidCallback(Handle hOwner, Handle hHndl, const char[] sErr, any data)
{	
	if (hHndl != null)
	{	
		while (SQL_FetchRow(hHndl))
		{
			g_arrServerAds[g_iAdCount][iID] = SQL_FetchInt(hHndl, 0);
			g_arrServerAds[g_iAdCount][iUID] = SQL_FetchInt(hHndl, 2);
			SQL_FetchString(hHndl, 4, g_arrServerAds[g_iAdCount][sMsg], 1024);
			g_arrServerAds[g_iAdCount][iChatType] = SQL_FetchInt(hHndl, 5);
			
			g_arrServerAds[g_iAdCount][iPaid] = 1;
			
			if (g_bAdvanceDebug)
			{
				GFLCore_LogMessage("", "[GFL-ServerAds] AdvertsPaidCallback() :: Added advertisement (ID: %i, Msg: \"%s\")", g_arrServerAds[g_iAdCount][iID], g_arrServerAds[g_iAdCount][sMsg]);
			}
			
			g_iAdCount++;
		}
	}
}

public Action DisplayAdvert(Handle hTimer)
{
	if (g_bAdvanceDebug)
	{
		GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] DisplayAdvert() :: Executed.");
	}
	
	if (!g_bEnabled)
	{
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] DisplayAdvert() :: Plugin Disabled.");
		}
		
		return Plugin_Stop;
	}
	
	// Display the correct advert!
	if (!StrEqual(g_arrServerAds[g_iCurAd][sMsg], ""))
	{
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] DisplayAdvert() :: Displaying Ad #%i", g_iCurAd);
		}
		
		char sFormattedMsg[1024];
		
		if (g_arrServerAds[g_iCurAd][iPaid] == 1)
		{
			Format(sFormattedMsg, sizeof(sFormattedMsg), "%t%t", "ChatPrefix", "PaidAd", g_arrServerAds[g_iCurAd][sMsg]);
			
			for (int iClient = 1; iClient <= MaxClients; iClient++)
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
			Format(sFormattedMsg, sizeof(sFormattedMsg), "%t%s", "ChatPrefix", g_arrServerAds[g_iCurAd][sMsg]);
			
			for (int iClient = 1; iClient <= MaxClients; iClient++)
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
		g_iCurAd = 0;
	}
	
	return Plugin_Continue;
}

public void OnMapEnd()
{
	if (g_hAdvertTimer != null)
	{
		delete g_hAdvertTimer;
	}
}

public Action Command_UpdateAds(int iClient, int iArgs)
{
	if (!g_bEnabled)
	{
		CReplyToCommand(iClient, "%t%t", "Tag", "PluginDisabled");
		
		return Plugin_Handled;
	}
	
	UpdateAdverts();
	
	CReplyToCommand(iClient, "%t%t", "Tag", "ServerAdsUpdated");
	
	return Plugin_Handled;
}

public Action Command_PrintArray(int iClient, int iArgs)
{	
	PrintServerAdsArray();
	
	return Plugin_Handled;
}

public Action Command_PrintAds(int iClient, int iArgs)
{
	for (int i = 0; i < g_iAdCount; i++)
	{
		// Check if the ad is valid.
		if (StrEqual(g_arrServerAds[i][sMsg], ""))
		{
			continue;
		}
		
		char sFormattedMsg[1024];
		
		// Check ad type.
		if (g_arrServerAds[i][iPaid] == 1)
		{
			// Paid ad.
			Format(sFormattedMsg, sizeof(sFormattedMsg), "[%i] %t%t", g_arrServerAds[i][iID], "ChatPrefix", "PaidAd", g_arrServerAds[i][sMsg]);
			
			CPrintToChat(iClient, sFormattedMsg);
		}
		else
		{
			// Default/Game ad.
			Format(sFormattedMsg, sizeof(sFormattedMsg), "[%i] %t%s", g_arrServerAds[i][iID], "ChatPrefix", g_arrServerAds[i][sMsg]);
			
			CPrintToChat(iClient, sFormattedMsg);
		}
	}

	return Plugin_Handled;
}

stock void ClearServerAdsArray()
{
	for (int i = 0; i < MAXADS; i++)
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

stock void PrintServerAdsArray()
{
	for (int i = 0; i < g_iAdCount; i++)
	{
		if (StrEqual(g_arrServerAds[i][sMsg], ""))
		{
			continue;
		}
		
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

stock void CreateSQLTables()
{
	// We need to make sure they aren't already created.
	char sQuery[64];
	
	Format(sQuery, sizeof(sQuery), "SELECT * FROM `%s`", g_sGlobalTableName);
	SQL_TQuery(g_hDB, Callback_GlobalTableCheck, sQuery, _, dbPriority);

	Format(sQuery, sizeof(sQuery), "SELECT * FROM `%s`", g_sPaidTableName);
	SQL_TQuery(g_hDB, Callback_PaidTableCheck, sQuery, _, dbPriority);
}

// Global Table.
public void Callback_GlobalTableCheck(Handle hOwner, Handle hHndl, const char[] sErr, any Data)
{
	if (hHndl == null)
	{
		// Create the tables.
		char sQuery[2048];
		Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `%s` (`id` int(11) NOT NULL AUTO_INCREMENT,`message` varchar(1024) NOT NULL,`gameid` int(11) NOT NULL,`serverid` int(11) NOT NULL,`chattype` int(11) NOT NULL, PRIMARY KEY (`id`)) ENGINE=MyISAM  DEFAULT CHARSET=latin1;", g_sGlobalTableName);
		
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] Callback_GlobalTableCheck() :: Create Table Query: %s", sQuery);
		}
		
		SQL_TQuery(g_hDB, Callback_CreateGlobalTable, sQuery, _, dbPriority);
	}
}

public void Callback_CreateGlobalTable(Handle hOwner, Handle hHndl, const char[] sErr, any Data)
{
	if (hHndl == null)
	{
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] Callback_CreateGlobalTable() :: Error creating the `%s` table. Error: %s", g_sGlobalTableName, sErr);
		}
	}
	else
	{
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] Callback_CreateGlobalTable() :: `%s` table created successfully!", g_sGlobalTableName);
		}
	}
}

// Paid Table.
public void Callback_PaidTableCheck(Handle hOwner, Handle hHndl, const char[] sErr, any Data)
{
	if (hHndl == null)
	{
		// Create the tables.
		char sQuery[2048];
		Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `gfl_adverts-paid` (`id` int(11) NOT NULL AUTO_INCREMENT,`pid` int(11) NOT NULL,`uid` int(11) NOT NULL,`activated` int(1) NOT NULL,`message` varchar(1024) NOT NULL,`chattype` int(11) NOT NULL,PRIMARY KEY (`id`)) ENGINE=MyISAM  DEFAULT CHARSET=latin1;", g_sPaidTableName);
		
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] Callback_PaidTableCheck() :: Create Table Query: %s", sQuery);
		}
		
		SQL_TQuery(g_hDB, Callback_CreatePaidTable, sQuery, _, dbPriority);
	}
}

public void Callback_CreatePaidTable(Handle hOwner, Handle hHndl, const char[] sErr, any Data)
{
	if (hHndl == null)
	{
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] Callback_CreatePaidTable() :: Error creating the `%s` table. Error: %s", g_sPaidTableName, sErr);
		}
	}
	else
	{
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverads-debug.log", "[GFL-ServerAds] Callback_CreatePaidTable() :: `%s` table created successfully!", g_sPaidTableName);
		}
	}
}