#include <sourcemod>
#include <sdktools>
#include <GFL-Core>
#include <GFL-MySQL>
#include <GFL-ServerHop>
#include <multicolors>

#undef REQUIRE_PLUGIN
#include <updater>

//#define DEVELOPDEBUG
#define MAXSERVERS 128
#define UPDATE_URL "http://updater.gflclan.com/core.txt"

enum Servers 
{
	iServerID,
	String:sName[MAX_NAME_LENGTH],
	iLocationID,
	String:sPubIP[MAX_NAME_LENGTH],
	String:sIP[11],
	iPort,
	iGameID,
	iPlayerCount,
	iMaxPlayers,
	iBots,
	String:sCurMap[MAX_NAME_LENGTH]
	
}

// Arrays
new g_arrServers[MAXSERVERS][Servers];

new String:g_arrMenuTriggers[][] = 
{
	"sm_hop",
	"sm_serverhop",
	"sm_servers",
	"sm_moreservers",
	"sm_gflservers",
	"sm_sh"
};

// Forwards
new Handle:g_hOnAdvert;
new Handle:g_hOnServersUpdated;
new Handle:g_hOnErrorCountReached;

// ConVars
new Handle:g_hAdvertInterval = INVALID_HANDLE;
new Handle:g_hGameID = INVALID_HANDLE;
new Handle:g_hRefreshInterval = INVALID_HANDLE;
new Handle:g_hLocationID = INVALID_HANDLE;
new Handle:g_hTableName = INVALID_HANDLE;
new Handle:g_hAdvanceDebug = INVALID_HANDLE;
new Handle:g_hDisableOffline = INVALID_HANDLE;
new Handle:g_hDisableCurrent = INVALID_HANDLE;
new Handle:g_hEnableErrorReachLimit = INVALID_HANDLE;

// ConVar Values
new Float:g_fAdvertInterval;
new g_iGameID;
new Float:g_fRefreshInterval;
new g_iLocationID;
new String:g_sTableName[MAX_NAME_LENGTH];
new bool:g_bAdvanceDebug;
new bool:g_bDisableOffline;
new bool:g_bDisableCurrent;
new bool:g_bEnableErrorReachLimit;

// Other
new bool:g_bEnabled = false;
new bool:g_bCoreEnabled = false;
new Handle:g_hAdvertTimer = INVALID_HANDLE;
new Handle:g_hRefreshTimer = INVALID_HANDLE;
new Handle:g_hDB = INVALID_HANDLE;
new g_iRotate;
new g_iMaxServers;
new iSQLErrorCount;
new String:g_sServerIP[64];
new g_iServerPort;

public APLRes:AskPluginLoad2(Handle:hMyself, bool:bLate, String:sErr[], iErrMax)
{
	RegPluginLibrary("GFL-ServerHop");
	
	return APLRes_Success;
}

public OnLibraryAdded(const String:sLName[]) 
{
	if (StrEqual(sLName, "GFL-MySQL")) 
	{
		// MySQL library loaded.
		g_bEnabled = true;
	}
	
	if (StrEqual(sLName, "updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
}

public Plugin:myinfo = 
{
	name = "GFL-ServerHop",
	description = "GFL's ServerHop plugin.",
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
	g_hOnAdvert = CreateGlobalForward("GFLSH_OnAdvert", ET_Event);
	g_hOnServersUpdated = CreateGlobalForward("GFLSH_OnServersUpdated", ET_Event);
	g_hOnErrorCountReached = CreateGlobalForward("GFLSH_OnErrorCountReached", ET_Event);
}

stock ForwardConVars() 
{
	CreateConVar("GFLCore_version", PL_VERSION, "GFL's ServerHop version.");
	g_hAdvertInterval = CreateConVar("sm_GFLSH_advert_interval", "65.0", "Every x seconds display a server advertisement.");
	HookConVarChange(g_hAdvertInterval, CVarChanged);
	g_hGameID = CreateConVar("sm_GFLSH_gameid", "4", "The Game ID of the servers you want to retrieve in the database.");
	HookConVarChange(g_hGameID, CVarChanged);	
	g_hRefreshInterval = CreateConVar("sm_GFLSH_refresh_interval", "500.0", "Every x seconds refresh the server list.");
	HookConVarChange(g_hRefreshInterval, CVarChanged);
	g_hLocationID = CreateConVar("sm_GFLSH_locationid", "1", "Server's location ID. 1 = US, 2 = EU, etc..");
	HookConVarChange(g_hLocationID, CVarChanged);	
	g_hTableName = CreateConVar("sm_GFLSH_tablename", "gfl_serverlist", "The table to select the servers from.");
	HookConVarChange(g_hTableName, CVarChanged);	
	g_hAdvanceDebug = CreateConVar("sm_GFLSH_advancedebug", "0", "Enable advanced debugging for this plugin?");
	HookConVarChange(g_hAdvanceDebug, CVarChanged);	
	g_hDisableOffline = CreateConVar("sm_GFLSH_disableoffline", "1", "1 = Don't include offline servers in the advertisements (0 player count).");
	HookConVarChange(g_hDisableOffline, CVarChanged);	
	g_hDisableCurrent = CreateConVar("sm_GFLSH_disablecurrent", "1", "1 = Disable the current server from showing in the advertisement list?");
	HookConVarChange(g_hDisableCurrent, CVarChanged);	
	g_hEnableErrorReachLimit = CreateConVar("sm_GFLSH_enable_error_limit", "1", "If enabled, if the query fail limit goes above 4, the sql database will reconnect. IN BETA DOESN'T WORK RIGHT!");
	HookConVarChange(g_hEnableErrorReachLimit, CVarChanged);
	
	AutoExecConfig(true, "GFL-ServerHop");
}

public CVarChanged(Handle:hCVar, const String:OldV[], const String:NewV[]) {
	ForwardValues();
	
	if (hCVar == g_hAdvertInterval) 
	{
		if (g_hAdvertTimer != INVALID_HANDLE) 
		{
			GFLCore_CloseHandle(g_hAdvertTimer);
			
			g_hAdvertTimer = CreateTimer(StringToFloat(NewV), Timer_Advert, _, TIMER_REPEAT);
		}
	} 
	else if (hCVar == g_hRefreshInterval) 
	{
		if (g_hRefreshTimer != INVALID_HANDLE) 
		{
			GFLCore_CloseHandle(g_hRefreshTimer);
			
			g_hRefreshTimer = CreateTimer(StringToFloat(NewV), Timer_Refresh, _, TIMER_REPEAT);
		}
	}
}

stock ForwardCommands() 
{
	RegAdminCmd("sm_sh_reset", Command_Reset, ADMFLAG_ROOT);
	RegAdminCmd("sm_sh_refresh", Command_Refresh, ADMFLAG_ROOT);
	
	// Menu Triggers
	for (new i = 0; i < sizeof(g_arrMenuTriggers); i++)
	{
		RegConsoleCmd(g_arrMenuTriggers[i], Command_OpenMenu);
	}
}

public OnConfigsExecuted() 
{
	ForwardValues();
}

stock ForwardValues() 
{
	g_fAdvertInterval = GetConVarFloat(g_hAdvertInterval);
	g_iGameID = GetConVarInt(g_hGameID);
	g_fRefreshInterval = GetConVarFloat(g_hRefreshInterval);
	g_iLocationID = GetConVarInt(g_hLocationID);
	GetConVarString(g_hTableName, g_sTableName, sizeof(g_sTableName));
	g_bAdvanceDebug = GetConVarBool(g_hAdvanceDebug);
	g_bDisableOffline = GetConVarBool(g_hDisableOffline);
	g_bDisableCurrent = GetConVarBool(g_hDisableCurrent);
	g_bEnableErrorReachLimit = GetConVarBool(g_hEnableErrorReachLimit);
}

public GFLMySQL_OnDatabaseConnected(Handle:hDB) 
{
	if (hDB != INVALID_HANDLE) 
	{
		g_hDB = hDB;
		if (!g_bEnabled)
		{
			g_bEnabled = true;
		}
		
		#if defined DEVELOPDEBUG then
			PrintToServer("[GFL-ServerHop] Retrieved OnDatabaseConnected()");
		#endif
		
		RetrieveServerIP();
		SetUpServers();
	} 
	else 
	{
		GFLCore_LogMessage("", "[GFL-ServerHop] GFLMySQL_OnDatabaseConnected() :: Database Handle invalid. Plugin disabled.");
		g_bEnabled = false;
	}
	
	g_hAdvertTimer = CreateTimer(g_fAdvertInterval, Timer_Advert, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	g_hRefreshTimer = CreateTimer(g_fRefreshInterval, Timer_Refresh, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public GFLCore_OnLoad()
{
	g_bCoreEnabled = true;
}

public GFLCore_OnUnload()
{
	g_bCoreEnabled = false;
}

stock SetUpServers() 
{
	if (g_hDB == INVALID_HANDLE) 
	{
		GFLCore_LogMessage("", "[GFL-ServerHop] SetUpServers() :: Database Handle invalid. Plugin disabled.");
		g_bEnabled = false;
		return;
	}
	
	decl String:sQuery[256];
	if (g_iLocationID > 0) 
	{
		Format(sQuery, sizeof(sQuery), "SELECT * FROM `%s` WHERE `gameid`=%i AND `location`=%i", g_sTableName, g_iGameID, g_iLocationID);
	}	
	else 
	{
		Format(sQuery, sizeof(sQuery), "SELECT * FROM `%s` WHERE `gameid`=%i", g_sTableName, g_iGameID);
	}
	
	SQL_TQuery(g_hDB, CallBack_TQuery, sQuery, _, DBPrio_High);
}

public CallBack_TQuery(Handle:hOwner, Handle:hHndl, const String:sErr[], any:data) 
{
	if (hOwner == INVALID_HANDLE) 
	{
		if (g_bEnableErrorReachLimit) 
		{
			iSQLErrorCount++;
			
			if (iSQLErrorCount > 5) 
			{
				iSQLErrorCount = 0;
				if (StrContains(sErr, "10061")) 
				{
					Call_StartForward(g_hOnErrorCountReached);
					Call_Finish();
				}
			}
		}
		GFLCore_LogMessage("", "[GFL-ServerHop] CallBack_TQuery() :: Error: %s (%i/5)", sErr, iSQLErrorCount);
		g_bEnabled = false;
	}
	
	if (hHndl != INVALID_HANDLE) 
	{
		ResetServersArray();
		iSQLErrorCount = 0;
		new iCount = 0;
		while (SQL_FetchRow(hHndl)) 
		{
			if (g_bDisableOffline) 
			{
				new iMaxP = SQL_FetchInt(hHndl, 10);
				
				if (iMaxP < 1) 
				{
					if (g_bAdvanceDebug) 
					{
						decl String:sCurIP[32];
						SQL_FetchString(hHndl, 4, sCurIP, sizeof(sCurIP));
						
						GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] CallBack_TQuery() :: Skipped %s due to the server being offline.", sCurIP);
					}
					continue;
				}
			}
			
			if (g_bDisableCurrent) 
			{
				decl String:sServerIP[64];
				SQL_FetchString(hHndl, 4, sServerIP, sizeof(sServerIP));
				
				new iServerPort = SQL_FetchInt(hHndl, 0);
				
				if (StrEqual(sServerIP, g_sServerIP, false) && iServerPort == g_iServerPort) 
				{
					if (g_bAdvanceDebug) 
					{
						GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] CallBack_TQuery() :: Skipped %s:%d due to it matching the current server.", sServerIP, iServerPort);
					}
					continue;
				}
			}
			
			g_arrServers[iCount][iServerID] = SQL_FetchInt(hHndl, 0);
			SQL_FetchString(hHndl, 1, g_arrServers[iCount][sName], MAX_NAME_LENGTH);
			g_arrServers[iCount][iLocationID] = SQL_FetchInt(hHndl, 2);
			SQL_FetchString(hHndl, 3, g_arrServers[iCount][sPubIP], MAX_NAME_LENGTH);
			SQL_FetchString(hHndl, 4, g_arrServers[iCount][sIP], 32);
			g_arrServers[iCount][iPort] = SQL_FetchInt(hHndl, 5);
			g_arrServers[iCount][iGameID] = SQL_FetchInt(hHndl, 8);
			g_arrServers[iCount][iPlayerCount] = SQL_FetchInt(hHndl, 9);
			g_arrServers[iCount][iMaxPlayers] = SQL_FetchInt(hHndl, 10);
			g_arrServers[iCount][iBots] = SQL_FetchInt(hHndl, 11);
			SQL_FetchString(hHndl, 12, g_arrServers[iCount][sCurMap], MAX_NAME_LENGTH);
			
			if (g_bAdvanceDebug) 
			{
				GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] CallBack_TQuery() :: Loading: %s (%i), currently %i/%i (%i). IP: %s:%i (%s:%i) on map: %s also in location %i with the game id being %i", g_arrServers[iCount][sName], g_arrServers[iCount][iServerID], g_arrServers[iCount][iPlayerCount], g_arrServers[iCount][iMaxPlayers], g_arrServers[iCount][iBots], g_arrServers[iCount][sPubIP], g_arrServers[iCount][iPort], g_arrServers[iCount][sIP], g_arrServers[iCount][iPort], g_arrServers[iCount][sCurMap], g_arrServers[iCount][iLocationID], g_arrServers[iCount][iGameID]);
			}
			
			iCount++;
		}
		g_iMaxServers = iCount;
		
		Call_StartForward(g_hOnServersUpdated);
		Call_Finish();
	} 
	else 
	{
		if (g_bEnableErrorReachLimit) 
		{
			iSQLErrorCount++;
			if (iSQLErrorCount > 5) 
			{
				iSQLErrorCount = 0;
				if (StrContains(sErr, "10061")) 
				{
					Call_StartForward(g_hOnErrorCountReached);
					Call_Finish();
				}
			}
		}
		
		g_bEnabled = false;
		GFLCore_LogMessage("", "[GFL-ServerHop] CallBack_TQuery() :: Error: %s (%i/5)", sErr, iSQLErrorCount);
	}
}

/* Commands */
public Action:Command_Reset(iClient, iArgs) 
{
	if (!g_bEnabled || !g_bCoreEnabled)
	{
		if (iClient == 0) 
		{
			PrintToServer("[GFL-ServerHop] Plugin disabled.");
		} 
		else 
		{
			PrintToChat(iClient, "\x03[GFL-ServerHop] \x02Plugin Disabled");
		}	
		return Plugin_Handled;
	}
	
	if (g_hDB != INVALID_HANDLE) 
	{
		GFLCore_CloseHandle(g_hDB);
		
		g_hDB = GFLMySQL_GetDatabase();
	}
	
	if (g_hDB != INVALID_HANDLE) 
	{
		SetUpServers();
		if (iClient == 0) 
		{
			PrintToServer("[GFL-ServerHop] Command ran. Database handle is valid! Refreshing servers now!");
		} 
		else 
		{
			PrintToChat(iClient, "\x03[GFL-ServerHop] \x02Command ran. Database handle is valid! Refreshing servers now!");
		}
	} 
	else 
	{
		if (iClient == 0) 
		{
			PrintToServer("[GFL-ServerHop] Command ran. Database handle is invalid.");
		} 
		else 
		{
			PrintToChat(iClient, "\x03[GFL-ServerHop] \x02Command ran. Database handle is invalid.");
		}
	}
	
	return Plugin_Handled;
}

public Action:Command_Refresh(iClient, iArgs) 
{
	if (!g_bEnabled || !g_bCoreEnabled)
	{
		if (iClient == 0) 
		{
			PrintToServer("[GFL-ServerHop] Plugin disabled.");
		} 
		else 
		{
			PrintToChat(iClient, "\x03[GFL-ServerHop] \x02Plugin Disabled");
		}	
		return Plugin_Handled;
	}
	
	if (g_hDB != INVALID_HANDLE) 
	{
		SetUpServers();
		
		if (iClient == 0) 
		{
			PrintToServer("[GFL-ServerHop] Command ran. Servers refreshing now!");
		} 
		else 
		{
			PrintToChat(iClient, "\x03[GFL-ServerHop] \x02Command ran. Servers refreshing now!");
		}
	} 
	else 
	{
		if (iClient == 0) 
		{
			PrintToServer("[GFL-ServerHop] Command ran. Database handle is invalid.");
		} 
		else 
		{
			PrintToChat(iClient, "\x03[GFL-ServerHop] \x02Command ran. Database handle is invalid.");
		}
	}
	
	return Plugin_Handled;
}

public Action:Command_OpenMenu(iClient, iArgs)
{
	if (!g_bEnabled || !g_bCoreEnabled)
	{
		CPrintToChat(iClient, "{darkred}[GFL-ServerHop]{default}Plugin disabled.");
		return Plugin_Handled;
	}
	
	OpenServersMenu(iClient);
	
	return Plugin_Handled;
}

/* TIMERS */
public Action:Timer_Advert(Handle:hTimer) 
{
	if (!g_bEnabled || !g_bCoreEnabled)
	{
		return;
	}
	
	if (!g_arrServers[g_iRotate][iServerID]) 
	{
		GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] Timer_Advert() :: Server ID is lowered than one. Not continuing. Server name: %s", g_arrServers[g_iRotate][sName]);
		MoveUpServer();
		return;
	}
	
	if (g_bDisableOffline && g_arrServers[g_iRotate][iMaxPlayers] < 1) 
	{
		MoveUpServer();
		if (g_bAdvanceDebug) 
		{
			GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] Timer_Advert() :: Skipped %s due to being offline (0 maximum players).", g_arrServers[g_iRotate][sIP]);
		}
		
		return;
	}
	
	if (g_bDisableCurrent) 
	{
		
		if (StrEqual(g_arrServers[g_iRotate][sIP], g_sServerIP, false) && g_arrServers[g_iRotate][iPort] == g_iServerPort) 
		{
			MoveUpServer();
			if (g_bAdvanceDebug) 
			{
				GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] Timer_Advert() :: Skipped %s:%d due to it matching the current server.", g_arrServers[g_iRotate][sIP], g_arrServers[g_iRotate][iPort]);
			}
			
			return;
		}
	}
	
	decl String:sMsg[256];
	Format(sMsg, sizeof(sMsg), " {darkred}%s  {default}- ({lightgreen}%i{default}/{lightgreen}%i{default}) IP: {lightgreen}%s:%i {default}({lightgreen}%s:%i{default}). Map: {darkred}%s", g_arrServers[g_iRotate][sName], g_arrServers[g_iRotate][iPlayerCount], g_arrServers[g_iRotate][iMaxPlayers], g_arrServers[g_iRotate][sPubIP], g_arrServers[g_iRotate][iPort], g_arrServers[g_iRotate][sIP], g_arrServers[g_iRotate][iPort], g_arrServers[g_iRotate][sCurMap]);
	
	for (new iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || !GFLCore_ClientAds(iClient))
		{
			continue;
		}
		
		CPrintToChat(iClient, sMsg);
	}
	
	if (g_bAdvanceDebug) 
	{
		GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] Timer_Advert() :: Server Advert: %s (%i)(%i)", g_arrServers[g_iRotate][sName], g_arrServers[g_iRotate][iServerID], g_iRotate);
	}
	
	Call_StartForward(g_hOnAdvert);
	Call_Finish();
	
	MoveUpServer();
}

public Action:Timer_Refresh(Handle:hTimer) 
{
	if (!g_bEnabled || !g_bCoreEnabled)
	{
		return;
	}
		
	#if defined DEVELOPDEBUG then
		PrintToServer("[GFL-ServerHop] Timer_Refresh ran...");
	#endif
	
	SetUpServers();
}

/* Legit Stocks */
stock MoveUpServer() 
{
	g_iRotate++;
	if (g_iRotate >= g_iMaxServers) 
	{
		g_iRotate = 0;
	}
}

ResetServersArray() 
{
	for (new i = 0; i < MAXSERVERS; i++)
	{
		g_arrServers[i][iServerID] = -1;
		strcopy(g_arrServers[i][sName], MAX_NAME_LENGTH, "");
		g_arrServers[i][iLocationID] = -1;
		strcopy(g_arrServers[i][sPubIP], MAX_NAME_LENGTH, "");
		strcopy(g_arrServers[i][sIP], MAX_NAME_LENGTH, "");
		g_arrServers[i][iPort] = -1;
		g_arrServers[i][iGameID] = -1;
		g_arrServers[i][iPlayerCount] = -1;
		g_arrServers[i][iMaxPlayers] = -1;
		g_arrServers[i][iBots] = -1;
		strcopy(g_arrServers[i][sCurMap], MAX_NAME_LENGTH, "");
	}
}

stock RetrieveServerIP()
{
	new iPieces[4];
	new iLongIP = GetConVarInt(FindConVar("hostip"));
	g_iServerPort = GetConVarInt(FindConVar("hostport"));
	
	iPieces[0] = (iLongIP >> 24) & 0x000000FF;
	iPieces[1] = (iLongIP >> 16) & 0x000000FF;
	iPieces[2] = (iLongIP >> 8) & 0x000000FF;
	iPieces[3] = iLongIP & 0x000000FF;
	
	Format(g_sServerIP, sizeof(g_sServerIP), "%d.%d.%d.%d", iPieces[0], iPieces[1], iPieces[2], iPieces[3]);
	
	#if defined DEVELOPDEBUG then
		GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] RetrieveServerIP() :: Got server IP: %s:%d.", g_sServerIP, g_iServerPort);
	#endif
}

stock OpenServersMenu(iClient)
{
	new Handle:hMenu = CreateMenu(MenuCallback);
	SetMenuTitle(hMenu, "GFL Servers");
	for (new i = 0; i < MAXSERVERS; i++)
	{
		if (g_arrServers[i][iServerID] > 0)
		{
			decl String:sID[11];
			Format(sID, sizeof(sID), "%d", i);
			
			decl String:sFullName[255];
			Format(sFullName, sizeof(sFullName), "%s (%d/%d)", g_arrServers[i][sName], g_arrServers[i][iPlayerCount], g_arrServers[i][iMaxPlayers]);
			
			AddMenuItem(hMenu, sID, sFullName);
		}
	}
	
	DisplayMenu(hMenu, iClient, 0);
	SetMenuExitButton(hMenu, true);
}

public MenuCallback(Handle:hMenu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_Select)
	{
		decl String:sInfo[32];
		GetMenuItem(hMenu, param2, sInfo, sizeof(sInfo));
		
		new iInfo = StringToInt(sInfo);
		
		DisplayServerInfo(param1, iInfo);
	}
	else if (action == MenuAction_End)
	{
		CloseHandle(hMenu);
	}
}

stock DisplayServerInfo(iClient, i)
{
	if (!IsClientInGame(iClient))
	{
		return;
	}
	
	decl String:sFullName[255], String:sPlayerCount[255], String:sPublicIP[255], String:sRealIP[255], String:sMapName[64], String:sFullMenu[1024], String:sFullIP[64];
	
	Format(sFullName, sizeof(sFullName), "Name: %s", g_arrServers[i][sName]);
	Format(sPlayerCount, sizeof(sPlayerCount), "Players: %d/%d", g_arrServers[i][iPlayerCount], g_arrServers[i][iMaxPlayers]);
	Format(sPublicIP, sizeof(sPublicIP), "Public IP: %s:%d", g_arrServers[i][sPubIP], g_arrServers[i][iPort]);
	Format(sRealIP, sizeof(sRealIP), "Real IP: %s:%d", g_arrServers[i][sIP], g_arrServers[i][iPort]);
	Format(sMapName, sizeof(sMapName), "Map: %s", g_arrServers[i][sCurMap]);
	Format(sFullMenu, sizeof(sFullMenu), "%s\n%s\n%s\n%s\n%s", sFullName, sPlayerCount, sPublicIP, sRealIP, sMapName);
	
	new Handle:hMenu = CreateMenu(ServerInfoMenuCallback);
	SetMenuTitle(hMenu, sFullMenu);
	
	if (GetEngineVersion() != Engine_CSGO)
	{
		Format(sFullIP, sizeof(sFullIP), "%s:%d", g_arrServers[i][sIP], g_arrServers[i][iPort]);
		AddMenuItem(hMenu, sFullIP, "Connect");
	}
	
	AddMenuItem(hMenu, "back", "Back");
	
	DisplayMenu(hMenu, iClient, 30);
	SetMenuExitButton(hMenu, true);
}

public ServerInfoMenuCallback(Handle:hMenu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_Select)
	{
		decl String:sInfo[64];
		GetMenuItem(hMenu, param2, sInfo, sizeof(sInfo));
		
		if (StrEqual(sInfo, "back", false))
		{
			OpenServersMenu(param1);
		}
		else
		{
			ConnectToServer(param1, sInfo);
		}
	}
	else if (action == MenuAction_End)
	{
		CloseHandle(hMenu);
	}
}

stock ConnectToServer(iClient, const String:sRealIP[])
{
	new Handle:hKV = CreateKeyValues("menu");
	KvSetString(hKV, "time", "20");
	KvSetString(hKV, "title", sRealIP);
	CreateDialog(iClient, hKV, DialogType_AskConnect);
	CloseHandle(hKV);
}
