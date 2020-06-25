#include <sourcemod>
#include <sdktools>
#include <GFL-Core>
#include <GFL-MySQL>
#include <GFL-ServerHop>
#include <multicolors>

#undef REQUIRE_PLUGIN
#include <updater>
#undef REQUIRE_EXTENSIONS
#define REQUIRE_PLUGIN
#include <socket>

#define MAXSERVERS 128
#define MAXGAMES 64
#define UPDATE_URL "http://updater.gflclan.com/GFL-ServerHop.txt"
#define PL_VERSION "1.0.1"

/* Socket defines. */
#define MAX_STR_LEN 160

// ENUM's aren't supported with the new syntax. Therefore, we need to stay on the old syntax until the SourceMod Developers find a better method.
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
	String:sCurMap[MAX_STR_LEN],
	iNew,
	Handle:hSocket
}

enum Games 
{
	iGameID,
	String:sName[MAX_NAME_LENGTH],
	iSpecial,
	String:sAbr[MAX_NAME_LENGTH],
	String:sCode[MAX_NAME_LENGTH]
}

// Arrays
int g_arrServers[MAXSERVERS][Servers];
int g_arrGames[MAXGAMES][Games];

char g_arrMenuTriggers[][] = 
{
	"sm_hop",
	"sm_serverhop",
	"sm_servers",
	"sm_moreservers",
	"sm_gflservers",
	"sm_sh"
};

// Forwards
Handle g_hOnAdvert;
Handle g_hOnServersUpdated;
Handle g_hOnGamesUpdated;

// ConVars
ConVar g_hAdvertInterval = null;
ConVar g_hGameID = null;
ConVar g_hRefreshInterval = null;
ConVar g_hLocationID = null;
ConVar g_hTableName = null;
ConVar g_hGameTableName = null;
ConVar g_hAdvanceDebug = null;
ConVar g_hDisableOffline = null;
ConVar g_hDisableCurrent = null;
ConVar g_hDBPriority = null;
ConVar g_hCreateDBTable = null;
ConVar g_hNewServerAnnounce = null;
ConVar g_hNewServerAnnounceMethod = null;
ConVar g_hUseSocket = null;
ConVar g_hGameAbbreviations = null;
ConVar g_hIPAddress = null;

// ConVar Values
float g_fAdvertInterval;
int g_iGameID;
float g_fRefreshInterval;
int g_iLocationID;
char g_sTableName[MAX_NAME_LENGTH];
char g_sGameTableName[MAX_NAME_LENGTH];
bool g_bAdvanceDebug;
bool g_bDisableOffline;
bool g_bDisableCurrent;
int g_iDBPriority;
bool g_bCreateDBTable;
bool g_bNewServerAnnounce;
int g_iNewAnnounceServerMethod;
bool g_bUseSocket;
bool g_bGameAbbreviations;
char g_sIPAddress[24];

// Other
bool g_bEnabled = false;
Handle g_hAdvertTimer = null;
Handle g_hRefreshTimer = null;
Handle g_hDB = null;
int g_iRotate;
int g_iMaxServers;
int g_iMaxGames;
char g_sServerIP[64];
int g_iServerPort;
bool g_bSocketEnabled = false;

DBPriority dbPriority = DBPrio_Low;

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sErr, int iErrMax)
{
	RegPluginLibrary("GFL-ServerHop");
	
	/* Mark the socket natives as optional. */
	MarkNativeAsOptional("SocketCreate");
	MarkNativeAsOptional("SocketSetArg");
	MarkNativeAsOptional("SocketConnect");
	MarkNativeAsOptional("SocketSend");
	
	return APLRes_Success;
}

public void OnLibraryAdded(const char[] sLName) 
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

public Plugin myinfo = 
{
	name = "GFL-ServerHop",
	author = "Christian Deacon (Roy) and [GRAVE] rig0r",
	description = "GFL's ServerHop plugin.",
	version = PL_VERSION,
	url = "GFLClan.com & TheDevelopingCommunity.com"
};

public void OnPluginStart() 
{
	Forwards();
	ForwardConVars();
	ForwardCommands();
	
	// Events.
	HookEvent("round_start", Event_RoundStart);
	
	// Load Translations.
	LoadTranslations("GFL-ServerHop.phrases.txt");
	
	// Reset the Server Hop array just in case!
	ResetServersArray();
	
	// Check if the socket extension is enabled.
	if (GetExtensionFileStatus("socket.ext") == 1)
	{
		g_bSocketEnabled = true;
	}
}

stock void Forwards() 
{
	g_hOnAdvert = CreateGlobalForward("GFLSH_OnAdvert", ET_Event);
	g_hOnServersUpdated = CreateGlobalForward("GFLSH_OnServersUpdated", ET_Event);
	g_hOnGamesUpdated = CreateGlobalForward("GFLSH_OnGamesUpdated", ET_Event);
}

stock void ForwardConVars() 
{	
	g_hAdvertInterval = CreateConVar("sm_GFLSH_advert_interval", "65.0", "Every x seconds display a server advertisement.");
	HookConVarChange(g_hAdvertInterval, CVarChanged);
	
	g_hGameID = CreateConVar("sm_gflsh_gameid", "4", "The Game ID of the servers you want to retrieve in the database. 0 = All");
	HookConVarChange(g_hGameID, CVarChanged);	
	
	g_hRefreshInterval = CreateConVar("sm_gflsh_refresh_interval", "500.0", "Every x seconds refresh the server list.");
	HookConVarChange(g_hRefreshInterval, CVarChanged);
	
	g_hLocationID = CreateConVar("sm_gflsh_locationid", "1", "Server's location ID. 0 = All, 1 = US, 2 = EU, etc..");
	HookConVarChange(g_hLocationID, CVarChanged);
	
	g_hTableName = CreateConVar("sm_gflsh_tablename", "gfl_serverlist", "The table to select the servers from.");
	HookConVarChange(g_hTableName, CVarChanged);		
	
	g_hGameTableName = CreateConVar("sm_gflsh_gametablename", "gfl_gamelist", "The table to select the games from.");
	HookConVarChange(g_hGameTableName, CVarChanged);	
	
	g_hAdvanceDebug = CreateConVar("sm_gflsh_advancedebug", "0", "Enable advanced debugging for this plugin?");
	HookConVarChange(g_hAdvanceDebug, CVarChanged);	
	
	g_hDisableOffline = CreateConVar("sm_gflsh_disableoffline", "1", "1 = Don't include offline servers in the advertisements (0 player count).");
	HookConVarChange(g_hDisableOffline, CVarChanged);
	
	g_hDisableCurrent = CreateConVar("sm_gflsh_disablecurrent", "1", "1 = Disable the current server from showing in the advertisement list?");
	HookConVarChange(g_hDisableCurrent, CVarChanged);	
	
	g_hDBPriority = CreateConVar("sm_gflsh_db_priority", "1", "The priority of queries for the plugin.");
	HookConVarChange(g_hDBPriority, CVarChanged);	
	
	g_hCreateDBTable = CreateConVar("sm_gflsh_db_createtable", "0", "Attempt to create the table needed for this plugin if it doesn't exist.");
	HookConVarChange(g_hCreateDBTable, CVarChanged);	
	
	g_hNewServerAnnounce = CreateConVar("sm_gflsh_new_server_announce", "0", "Announces new servers one round start.");
	HookConVarChange(g_hNewServerAnnounce, CVarChanged);	
	
	g_hUseSocket = CreateConVar("sm_gflsh_use_socket", "1", "Uses socket to request server information instead of MySQL. This requires the socket extension.");
	HookConVarChange(g_hUseSocket, CVarChanged);	

	g_hGameAbbreviations = CreateConVar("sm_gflsh_abbr", "0", "Use the game abbreviation infront of server advertisements.");
	HookConVarChange(g_hGameAbbreviations, CVarChanged);	
	
	g_hNewServerAnnounceMethod = CreateConVar("sm_gflsh_new_server_announce_method", "0", "Method to use on round start (0 = Do it all in one with PrintToChatAll, 1 = Loop through all clients). 0 = Better performance but less randomization, 1 = Worse performance but each client will get a different new server each time (more randomized).");
	HookConVarChange(g_hNewServerAnnounceMethod, CVarChanged);	
	
	g_hIPAddress = CreateConVar("sm_gflsh_server_ip", "", "If the plugin fails to get the current server's public IP due to something like a specific NAT configuration, just use this to set the public IP. Leave blank to let plugin assume what the public IP address is.");
	HookConVarChange(g_hIPAddress, CVarChanged);
	
	AutoExecConfig(true, "GFL-ServerHop");
}

public void CVarChanged(Handle hCVar, const char[] OldV, const char[] NewV) 
{
	ForwardValues();
	
	if (hCVar == g_hAdvertInterval) 
	{
		if (g_hAdvertTimer != null) 
		{
			delete g_hAdvertTimer;
			
			g_hAdvertTimer = CreateTimer(StringToFloat(NewV), Timer_Advert, _, TIMER_REPEAT);
		}
	} 
	else if (hCVar == g_hRefreshInterval) 
	{
		if (g_hRefreshTimer != null) 
		{
			delete g_hRefreshTimer;
			
			g_hRefreshTimer = CreateTimer(StringToFloat(NewV), Timer_Refresh, _, TIMER_REPEAT);
		}
	}
}

stock void ForwardCommands() 
{
	RegAdminCmd("sm_sh_reset", Command_Reset, ADMFLAG_ROOT);
	RegAdminCmd("sm_sh_refresh", Command_Refresh, ADMFLAG_ROOT);
	RegAdminCmd("sm_sh_addserver", Command_AddServer, ADMFLAG_ROOT);
	RegAdminCmd("sm_sh_printservers", Command_PrintServers, ADMFLAG_SLAY);
	RegAdminCmd("sm_sh_printgames", Command_PrintGames, ADMFLAG_SLAY);
	
	// Menu Triggers
	for (int i = 0; i < sizeof(g_arrMenuTriggers); i++)
	{
		RegConsoleCmd(g_arrMenuTriggers[i], Command_OpenMenu);
	}
}

public void OnConfigsExecuted() 
{
	ForwardValues();
}

stock void ForwardValues() 
{
	g_fAdvertInterval = GetConVarFloat(g_hAdvertInterval);
	g_iGameID = GetConVarInt(g_hGameID);
	g_fRefreshInterval = GetConVarFloat(g_hRefreshInterval);
	g_iLocationID = GetConVarInt(g_hLocationID);
	GetConVarString(g_hTableName, g_sTableName, sizeof(g_sTableName));
	GetConVarString(g_hGameTableName, g_sGameTableName, sizeof(g_sGameTableName));
	g_bAdvanceDebug = GetConVarBool(g_hAdvanceDebug);
	g_bDisableOffline = GetConVarBool(g_hDisableOffline);
	g_bDisableCurrent = GetConVarBool(g_hDisableCurrent);
	g_iDBPriority = GetConVarInt(g_hDBPriority);
	g_bCreateDBTable = GetConVarBool(g_hCreateDBTable);
	g_bNewServerAnnounce = GetConVarBool(g_hNewServerAnnounce);
	g_iNewAnnounceServerMethod = GetConVarBool(g_hNewServerAnnounceMethod);
	g_bUseSocket = GetConVarBool(g_hUseSocket);
	g_bGameAbbreviations = GetConVarBool(g_hGameAbbreviations);
	GetConVarString(g_hIPAddress, g_sIPAddress, sizeof(g_sIPAddress));
	
	if (g_iDBPriority == 0)
	{
		// High.
		dbPriority = DBPrio_High;
		
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] ForwardValues() :: DataBase priority set to high.");
		}
	}
	else if (g_iDBPriority == 1)
	{
		// Normal.
		dbPriority = DBPrio_Normal;
		
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] ForwardValues() :: DataBase priority set to normal.");
		}
	}
	else if (g_iDBPriority == 2)
	{
		// Low.
		dbPriority = DBPrio_Low;
		
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] ForwardValues() :: DataBase priority set to low.");
		}
	}
	else
	{
		// Normal.
		dbPriority = DBPrio_Normal;
		
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] ForwardValues() :: DataBase priority set to normal. (value not valid)");
		}
	}
}

public int GFLMySQL_OnDatabaseConnected(Handle hDB) 
{
	if (hDB != null) 
	{
		g_hDB = hDB;
		
		if (!g_bEnabled)
		{
			g_bEnabled = true;
		}
		
		if (g_bCreateDBTable)
		{
			CreateSQLTables();
		}
		
		RetrieveServerIP();
		SetUpServers();
		SetUpGames();
	} 
	else 
	{
		GFLCore_LogMessage("", "[GFL-ServerHop] GFLMySQL_OnDatabaseConnected() :: Database Handle invalid. Plugin disabled.");
		g_bEnabled = false;
	}
	
	if (g_hAdvertTimer != null)
	{
		delete g_hAdvertTimer;
	}
	
	g_hAdvertTimer = CreateTimer(g_fAdvertInterval, Timer_Advert, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	
	if (g_hRefreshTimer == null)
	{
		g_hRefreshTimer = CreateTimer(g_fRefreshInterval, Timer_Refresh, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

public int GFLMySQL_OnDatabaseDown()
{
	g_bEnabled = false;
	GFLCore_LogMessage("", "[GFL-ServerHop] GFLMySQL_OnDatabaseDown() :: Executed...");
	
	if (g_hAdvertTimer != null)
	{
		delete g_hAdvertTimer;
	}
	
	// Reset the Server Hop array just in case!
	ResetServersArray();
}

public void OnMapEnd()
{
	if (g_hAdvertTimer != null)
	{
		delete g_hAdvertTimer;
	}
	
	if (g_hRefreshTimer != null)
	{
		g_hRefreshTimer = null;
	}
}

stock void SetUpServers() 
{
	if (g_hDB == null) 
	{
		GFLCore_LogMessage("", "[GFL-ServerHop] SetUpServers() :: Database Handle invalid.");
		
		return;
	}
	
	char sQuery[256];
	
	// Let's build the location WHERE.
	char sLoc[64];
	
	if (g_iLocationID > 0)
	{
		// Specific location.
		Format(sLoc, sizeof(sLoc), "`location`=%i", g_iLocationID);
	}
	else
	{
		// Global.
		Format(sLoc, sizeof(sLoc), "1=1");
	}
	
	// Let's build the game ID WHERE.
	char sGame[64];
	
	if (g_iGameID > 0)
	{
		// Specific game.
		Format(sGame, sizeof(sGame), "`gameid`=%i", g_iGameID);
	}
	else
	{
		// Global.
		Format(sGame, sizeof(sGame), "1=1");
	}
	
	// Format the query.
	Format(sQuery, sizeof(sQuery), "SELECT * FROM `%s` WHERE %s AND %s", g_sTableName, sLoc, sGame);
	
	if (g_bAdvanceDebug)
	{
		GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] SetUpServers() :: Server Query: %s", sQuery);
	}
	
	SQL_TQuery(g_hDB, CallBack_ServerTQuery, sQuery, _, dbPriority);
}

public void CallBack_ServerTQuery(Handle hOwner, Handle hHndl, const char[] sErr, any data) 
{	
	if (hHndl != null) 
	{
		ResetServersArray();
		
		int iCount = 0;
		int iRowCount = SQL_GetRowCount(hHndl);
		
		if (g_bAdvanceDebug)
		{	
			GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] CallBack_ServerTQuery() :: Received %d row(s).", iRowCount);
		}
		
		while (SQL_FetchRow(hHndl)) 
		{
			// Not sure why it would even get here if there are no results.
			if (iRowCount < 1)
			{
				continue;
			}
			
			if (g_bDisableOffline) 
			{
				int iMaxP = SQL_FetchInt(hHndl, 10);
				
				if (iMaxP < 1) 
				{
					if (g_bAdvanceDebug) 
					{
						char sCurIP[32];
						SQL_FetchString(hHndl, 4, sCurIP, sizeof(sCurIP));
						
						GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] CallBack_ServerTQuery() :: Skipped %s due to the server being offline.", sCurIP);
					}
					
					continue;
				}
			}
			
			if (g_bDisableCurrent) 
			{
				char sServerIP[64];
				SQL_FetchString(hHndl, 4, sServerIP, sizeof(sServerIP));
				
				int iServerPort = SQL_FetchInt(hHndl, 5);
				
				if (StrEqual(sServerIP, g_sServerIP, false) && iServerPort == g_iServerPort) 
				{
					if (g_bAdvanceDebug) 
					{
						GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] CallBack_ServerTQuery() :: Skipped %s:%d due to it matching the current server.", sServerIP, iServerPort);
					}
					
					continue;
				}
			}
			
			// Variables not relying on the socket extension.
			g_arrServers[iCount][iServerID] = SQL_FetchInt(hHndl, 0);
			SQL_FetchString(hHndl, 1, g_arrServers[iCount][sName], MAX_NAME_LENGTH);
			g_arrServers[iCount][iLocationID] = SQL_FetchInt(hHndl, 2);
			SQL_FetchString(hHndl, 3, g_arrServers[iCount][sPubIP], MAX_NAME_LENGTH);
			SQL_FetchString(hHndl, 4, g_arrServers[iCount][sIP], 32);
			g_arrServers[iCount][iPort] = SQL_FetchInt(hHndl, 5);
			g_arrServers[iCount][iGameID] = SQL_FetchInt(hHndl, 8);
			g_arrServers[iCount][iNew] = SQL_FetchInt(hHndl, 16);
			
			// Check if the socket convar is enabled & if the socket extension is enabled.
			if (g_bUseSocket && g_bSocketEnabled)
			{
				// Check to see if the socket exist.
				if (g_arrServers[iCount][hSocket] != null)
				{
					// Close it.
					delete g_arrServers[iCount][hSocket];
				}
				
				// Create the socket.
				g_arrServers[iCount][hSocket] = SocketCreate(SOCKET_UDP, Socket_OnError);
				SocketSetArg(g_arrServers[iCount][hSocket], iCount);
				SocketConnect(g_arrServers[iCount][hSocket], Socket_OnConnected, Socket_OnReceived, Socket_OnDisconnected, g_arrServers[iCount][sPubIP], g_arrServers[iCount][iPort]);
			}
			else
			{
				// Use MySQL instead.
				g_arrServers[iCount][iPlayerCount] = SQL_FetchInt(hHndl, 9);
				g_arrServers[iCount][iMaxPlayers] = SQL_FetchInt(hHndl, 10);
				g_arrServers[iCount][iBots] = SQL_FetchInt(hHndl, 11);
				SQL_FetchString(hHndl, 12, g_arrServers[iCount][sCurMap], MAX_NAME_LENGTH);
			}
			
			if (g_bAdvanceDebug) 
			{
				GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] CallBack_ServerTQuery() :: Loading: %s (%i), currently %i/%i (%i). IP: %s:%i (%s:%i) on map: %s also in location %i with the game id being %i", g_arrServers[iCount][sName], g_arrServers[iCount][iServerID], g_arrServers[iCount][iPlayerCount], g_arrServers[iCount][iMaxPlayers], g_arrServers[iCount][iBots], g_arrServers[iCount][sPubIP], g_arrServers[iCount][iPort], g_arrServers[iCount][sIP], g_arrServers[iCount][iPort], g_arrServers[iCount][sCurMap], g_arrServers[iCount][iLocationID], g_arrServers[iCount][iGameID]);
			}
			
			iCount++;
		}
		
		g_iMaxServers = iCount;
		
		Call_StartForward(g_hOnServersUpdated);
		Call_Finish();
	} 
}

stock void SetUpGames()
{
	if (g_hDB == null) 
	{
		GFLCore_LogMessage("", "[GFL-ServerHop] SetUpGames() :: Database Handle invalid.");
		
		return;
	}
	
	char sQuery[256];
	
	Format(sQuery, sizeof(sQuery), "SELECT * FROM `%s`", g_sGameTableName);
	
	if (g_bAdvanceDebug)
	{
		GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] SetUpGames() :: Game Query: %s", sQuery);
	}
	
	SQL_TQuery(g_hDB, CallBack_GameTQuery, sQuery, _, dbPriority);
}

public void CallBack_GameTQuery(Handle hOwner, Handle hHndl, const char[] sErr, any data) 
{	
	if (hHndl != null) 
	{
		ResetGamesArray();
		
		int iCount = 0;
		int iRowCount = SQL_GetRowCount(hHndl);
		
		if (g_bAdvanceDebug)
		{	
			GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] CallBack_GameTQuery() :: Received %d row(s).", iRowCount);
		}
		
		while (SQL_FetchRow(hHndl)) 
		{
			// Not sure why it would even get here if there are no results.
			if (iRowCount < 1)
			{
				continue;
			}
			
			// Variables.
			g_arrGames[iCount][iGameID] = SQL_FetchInt(hHndl, 0);
			SQL_FetchString(hHndl, 1, g_arrGames[iCount][sName], MAX_NAME_LENGTH);
			g_arrGames[iCount][iSpecial] = SQL_FetchInt(hHndl, 2);
			SQL_FetchString(hHndl, 3, g_arrGames[iCount][sAbr], MAX_NAME_LENGTH);
			SQL_FetchString(hHndl, 4, g_arrGames[iCount][sCode], MAX_NAME_LENGTH);
			
			if (g_bAdvanceDebug) 
			{
				GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] CallBack_GameTQuery() :: Loading: %s (%i), Special: %i, Abbreviation: %s, Code Name: %s", g_arrGames[iCount][sName], g_arrGames[iCount][iGameID], g_arrGames[iCount][iSpecial], g_arrGames[iCount][sAbr], g_arrGames[iCount][sCode]);
			}
			
			iCount++;
		}
		
		g_iMaxGames = iCount;
		
		Call_StartForward(g_hOnGamesUpdated);
		Call_Finish();
	} 
}

/* Events. */
public Action Event_RoundStart(Event eEvent, const char[] sEName, bool bDontBroadcast)
{
	// Check whether the ConVar is enabled and if we have servers.
	if (g_bNewServerAnnounce && g_iMaxServers > 0)
	{
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverhop-debug.log", "Event_RoundStart() :: New Server Announce enabled...");
		}
		
		// Check the method used.
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverhop-debug.log", "Event_RoundStart() :: Method used: %i...", g_iNewAnnounceServerMethod);
		}
		
		if (g_iNewAnnounceServerMethod == 0)
		{
			bool bFound = false;
			int iCount = GetRandomInt(0, (g_iMaxServers - 1));
			int iAttempts = 0;
			
			if (g_bAdvanceDebug)
			{
				GFLCore_LogMessage("serverhop-debug.log", "Event_RoundStart() :: Starting while loop. (iCount = %i)...", iCount);
			}
			
			// Loop through all the servers and find a new one.
			while (!bFound)
			{
				// Check whether it's a new server or not.
				if (g_arrServers[iCount][iNew] > 0)
				{
					if (g_bAdvanceDebug)
					{
						GFLCore_LogMessage("serverhop-debug.log", "Event_RoundStart() :: Found a new server. (ID: %i)...", iCount);
					}
					
					bFound = true;
					break;
				}
				
				// Increment the count. 
				iCount++;
				
				// Increment the attempts.
				iAttempts++;
				
				// Check how many attempts, if it's above the server count, break the entire loop.
				if (iAttempts > g_iMaxServers)
				{
					if (g_bAdvanceDebug)
					{
						GFLCore_LogMessage("serverhop-debug.log", "Event_RoundStart() :: iAttempts > g_iMaxServers. Breaking loop...");
					}
					break;
				}
				
				// Check the count.
				if (iCount > (g_iMaxServers - 1))
				{
					if (g_bAdvanceDebug)
					{
						GFLCore_LogMessage("serverhop-debug.log", "Event_RoundStart() :: iCount > (g_iMaxServers - 1). Resetting iCount to 0...");
					}
				
					iCount = 0;
				}
				
				if (g_bAdvanceDebug)
				{
					GFLCore_LogMessage("serverhop-debug.log", "Event_RoundStart() :: Looping again...");
				}
			}
			
			// Check if a server was found.
			if (bFound)
			{
				// Format the message.
				char sMsg[512];
				Format(sMsg, sizeof(sMsg), "%t", "NewServerAnnounceMsg", g_arrServers[iCount][sName], g_arrServers[iCount][iPlayerCount], g_arrServers[iCount][iMaxPlayers], g_arrServers[iCount][sPubIP], g_arrServers[iCount][iPort], g_arrServers[iCount][sIP], g_arrServers[iCount][iPort], g_arrServers[iCount][sCurMap]);
				
				// Print to the client.
				CPrintToChatAll(sMsg);
			}
		}
		else
		{
			// Loop through all the players.
			for (int i = 1; i <= MaxClients; i++)
			{
				// Check if the client is in-game.
				if (!IsClientInGame(i))
				{
					continue;
				}
				
				if (g_bAdvanceDebug)
				{
					GFLCore_LogMessage("serverhop-debug.log", "Event_RoundStart() :: Looping through client #%i (%N)...", i, i);
				}
				
				bool bFound = false;
				int iCount = GetRandomInt(0, (g_iMaxServers - 1));
				int iAttempts = 0;
				
				if (g_bAdvanceDebug)
				{
					GFLCore_LogMessage("serverhop-debug.log", "Event_RoundStart() :: Starting while loop. (iCount = %i)...", iCount);
				}
				
				// Loop through all the servers and find a new one.
				while (!bFound)
				{
					// Check whether it's a new server or not.
					if (g_arrServers[iCount][iNew] > 0)
					{
						if (g_bAdvanceDebug)
						{
							GFLCore_LogMessage("serverhop-debug.log", "Event_RoundStart() :: Found a new server. (ID: %i)...", iCount);
						}
						
						bFound = true;
						break;
					}
					
					// Increment the count.
					iCount++;
					
					// Increment the attempts.
					iAttempts++;
					
					// Check how many attempts, if it's above the server count, break the entire loop.
					if (iAttempts > g_iMaxServers)
					{
						if (g_bAdvanceDebug)
						{
							GFLCore_LogMessage("serverhop-debug.log", "Event_RoundStart() :: iAttempts > g_iMaxServers. Breaking loop...");
						}
						break;
					}
					
					// Check the count.
					if (iCount > (g_iMaxServers - 1))
					{
						if (g_bAdvanceDebug)
						{
							GFLCore_LogMessage("serverhop-debug.log", "Event_RoundStart() :: iCount > (g_iMaxServers - 1). Resetting iCount to 0...");
						}
					
						iCount = 0;
					}
					
					if (g_bAdvanceDebug)
					{
						GFLCore_LogMessage("serverhop-debug.log", "Event_RoundStart() :: Looping again...");
					}
				}
				
				// Check if a server was found.
				if (bFound)
				{
					// Format the message.
					char sMsg[512];
					Format(sMsg, sizeof(sMsg), "%t", "NewServerAnnounceMsg", g_arrServers[iCount][sName], g_arrServers[iCount][iPlayerCount], g_arrServers[iCount][iMaxPlayers], g_arrServers[iCount][sPubIP], g_arrServers[iCount][iPort], g_arrServers[iCount][sIP], g_arrServers[iCount][iPort], g_arrServers[iCount][sCurMap]);
					
					// Print to the client.
					CPrintToChat(i, sMsg);
				}
			}
		}
	}
}

/* Commands */
public Action Command_Reset(int iClient, int iArgs) 
{
	if (!g_bEnabled)
	{
		CReplyToCommand(iClient, "%t%t", "Tag", "PluginDisabled");
		
		return Plugin_Handled;
	}
	
	if (g_hDB != null) 
	{
		delete g_hDB;
		
		g_hDB = GFLMySQL_GetDatabase();
	}
	
	if (g_hDB != null) 
	{
		SetUpServers();
		SetUpGames();
		
		CReplyToCommand(iClient, "%t%t", "Tag", "ResetSuccess");
	} 
	else 
	{
		CReplyToCommand(iClient, "%t%t", "Tag", "ResetFailed");
	}
	
	return Plugin_Handled;
}

public Action Command_Refresh(int iClient, int iArgs) 
{
	if (!g_bEnabled)
	{
		CReplyToCommand(iClient, "%t%t", "Tag", "PluginDisabled");
		
		return Plugin_Handled;
	}
	
	if (g_hDB != null) 
	{
		SetUpServers();
		
		CReplyToCommand(iClient, "%t%t", "Tag", "RefreshSuccess");
	} 
	else 
	{
		CReplyToCommand(iClient, "%t%t", "Tag", "RefreshFailed");
	}
	
	return Plugin_Handled;
}

public Action Command_OpenMenu(int iClient, int iArgs)
{
	if (!g_bEnabled)
	{
		CReplyToCommand(iClient, "%t%t", "Tag", "PluginDisabled");
		
		return Plugin_Handled;
	}
	
	OpenServersMenu(iClient);
	
	return Plugin_Handled;
}

public Action Command_AddServer(int iClient, iArgs)
{
	if (!g_bEnabled)
	{
		CReplyToCommand(iClient, "%t%t", "Tag", "PluginDisabled");
		
		return Plugin_Handled;
	}
	
	if (iArgs < 5)
	{
		CReplyToCommand(iClient, "%t%t", "Tag", "AddServerLow");
		
		return Plugin_Handled;
	}
	
	// Get everything.
	char ssName[MAX_NAME_LENGTH], sDesc[256], sPublicIP[64], sGameID[11], sLocationID[11];
	
	GetCmdArg(1, ssName, sizeof(ssName));
	GetCmdArg(2, sDesc, sizeof(sDesc));
	GetCmdArg(3, sPublicIP, sizeof(sPublicIP));
	GetCmdArg(4, sGameID, sizeof(sGameID));
	GetCmdArg(5, sLocationID, sizeof(sLocationID));
	
	// DataPack
	DataPack pack = new DataPack();
	
	pack.WriteCell(iClient);
	pack.WriteString(ssName);
	pack.WriteString(sDesc);
	pack.WriteString(sPublicIP);
	pack.WriteCell(StringToInt(sGameID));
	pack.WriteCell(StringToInt(sLocationID));
	
	// Now check if the server exist, if it does, update the information. Otherwise, insert the information.
	char sQuery[256];
	Format(sQuery, sizeof(sQuery), "SELECT * FROM `%s` WHERE `publicip`='%s' AND `port`=%d", g_sTableName, g_sServerIP, g_iServerPort); 
	
	SQL_TQuery(g_hDB, Callback_AddServer, sQuery, pack, dbPriority);
	
	return Plugin_Handled;
}

public void Callback_AddServer(Handle hOwner, Handle hHndl, const char[] sErr, DataPack pack)
{
	if (hHndl != null)
	{
		// Read the pack.
		char ssName[MAX_NAME_LENGTH], sDesc[256], sPublicIP[64];
		
		pack.Reset();
		
		int iClient = pack.ReadCell();
		pack.ReadString(ssName, sizeof(ssName));
		pack.ReadString(sDesc, sizeof(sDesc));
		pack.ReadString(sPublicIP, sizeof(sPublicIP));
		int iiGameID = pack.ReadCell();
		int iiLocationID = pack.ReadCell();
		
		delete(pack);
		
		// Escaped Strings.
		char escName[MAX_NAME_LENGTH], escDesc[256], escPublicIP[64];
		
		SQL_EscapeString(g_hDB, ssName, escName, sizeof(escName));
		SQL_EscapeString(g_hDB, sDesc, escDesc, sizeof(escDesc));
		SQL_EscapeString(g_hDB, sPublicIP, escPublicIP, sizeof(escPublicIP));
		
		char sQuery[2048];
		
		if (SQL_GetRowCount(hHndl) < 1)
		{
			// Insert.
			Format(sQuery, sizeof(sQuery), "INSERT INTO `%s` (`name`, `location`, `ip`, `publicip`, `port`, `qport`, `description`, `gameid`, `players`, `playersmax`, `bots`, `order`) VALUES ('%s', %d, '%s', '%s', %d, %d, '%s', %d, 0, 0, 0, 0);", g_sTableName, escName, iiLocationID, escPublicIP, g_sServerIP, g_iServerPort, g_iServerPort, escDesc, iiGameID); 
		}
		else
		{
			// Update.
			Format(sQuery, sizeof(sQuery), "UPDATE `%s` SET `name`='%s', `description`='%s', `ip`='%s', `location`=%d, `gameid`=%d WHERE `publicip`='%s' AND `port`=%d", g_sTableName, escName, escDesc, escPublicIP, iiLocationID, iiGameID, g_sServerIP, g_iServerPort);
		}
		
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] Callback_AddServer() :: sQuery = %s", sQuery);
		}
		
		SQL_TQuery(g_hDB, Callback_AddServerToDatabase, sQuery, iClient, dbPriority);
	}
	else
	{
		GFLCore_LogMessage("", "[GFL-ServerHop] Callback_AddServer() :: hHndl is null. Error: %s", sErr);
	}
}

public void Callback_AddServerToDatabase(Handle hOwner, Handle hHndl, const char[] sErr, any iClient)
{
	if (hHndl != null)
	{
		if (IsClientInGame(iClient))
		{
			char sSteamID[64];
			GetClientAuthId(iClient, AuthId_Steam2, sSteamID, sizeof(sSteamID), true); 
			
			GFLCore_LogMessage("", "[GFL-ServerHop] Callback_AddServerToDatabase() :: Server added to the database by %N (%s)", iClient, sSteamID);
			
			CReplyToCommand(iClient, "%t%t", "Tag", "AddServerSuccess");
		}
	}
	else
	{
		GFLCore_LogMessage("", "[GFL-ServerHop] Callback_AddServerToDatabase() :: hHndl is null. Error: %s", sErr);
	}
}

public Action Command_PrintServers(int iClient, int iArgs)
{
	char sMsg[1024];
	
	for (int i = 0; i < g_iMaxServers; i++)
	{
		if (StrEqual(g_arrServers[i][sName], ""))
		{
			continue;
		}
		
		Format(sMsg, sizeof(sMsg), "[%i] %t%t", g_arrServers[i][iServerID], "ServerHopAdPrefix", "ServerHopAd", g_arrServers[i][sName], g_arrServers[i][iPlayerCount], g_arrServers[i][iMaxPlayers], g_arrServers[i][sPubIP], g_arrServers[i][iPort], g_arrServers[i][sIP], g_arrServers[i][iPort], g_arrServers[i][sCurMap]);

		CPrintToChat(iClient, sMsg);
	}
	
	return Plugin_Handled;
}

public Action Command_PrintGames(int iClient, int iArgs)
{
	char sMsg[1024];
	
	for (int i = 0; i < g_iMaxGames; i++)
	{
		if (StrEqual(g_arrGames[i][sName], ""))
		{
			continue;
		}
		
		Format(sMsg, sizeof(sMsg), "[%i] %t%t", g_arrGames[i][iGameID], "ServerHopAdPrefix", "ServerHopGameAd", g_arrGames[i][sName], g_arrGames[i][iSpecial], g_arrGames[i][sAbr], g_arrGames[i][sCode]);

		CPrintToChat(iClient, sMsg);
	}
	
	return Plugin_Handled;
}



/* TIMERS */
public Action Timer_Advert(Handle hTimer) 
{
	if (!g_bEnabled)
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
		// Find the next online server.
		for (int i = g_iRotate; i < g_iMaxServers; i++)
		{
			if (g_bAdvanceDebug) 
			{
				GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] Timer_Advert() :: Skipped %s due to being offline (0 maximum players).", g_arrServers[g_iRotate][sIP]);
			}
		
			MoveUpServer();
			
			if (g_arrServers[g_iRotate][iMaxPlayers] > 0)
			{
				break;
			}
		}
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
	
	// Game abbreviations.
	char sAbbr[MAX_NAME_LENGTH];
	strcopy(sAbbr, sizeof(sAbbr), "");
	
	if (g_bGameAbbreviations)
	{
		int iGame = FindGameID(g_arrServers[g_iRotate][iGameID]);
		
		if (iGame > -1)
		{
			char sTemp[MAX_NAME_LENGTH];
			Format(sTemp, sizeof(sTemp), "[%s]", g_arrGames[iGame][sAbr]);
			
			strcopy(sAbbr, sizeof(sAbbr), sTemp);
			//PrintToServer("This: %s (%s)", sAbbr, sTemp);
		}
	}
	
	char sMsg[256];
	Format(sMsg, sizeof(sMsg), "%t%t", "ServerHopAdPrefix", "ServerHopAd", g_arrServers[g_iRotate][sName], g_arrServers[g_iRotate][iPlayerCount], g_arrServers[g_iRotate][iMaxPlayers], g_arrServers[g_iRotate][sPubIP], g_arrServers[g_iRotate][iPort], g_arrServers[g_iRotate][sIP], g_arrServers[g_iRotate][iPort], g_arrServers[g_iRotate][sCurMap], sAbbr);
	
	for (int iClient = 1; iClient <= MaxClients; iClient++)
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

public Action Timer_Refresh(Handle hTimer) 
{
	if (!g_bEnabled)
	{
		return;
	}
	
	SetUpServers();
}

/* Legit Stocks */
stock void MoveUpServer() 
{
	g_iRotate++;
	
	if (g_iRotate >= g_iMaxServers) 
	{
		g_iRotate = 0;
	}
}

stock void ResetServersArray() 
{
	for (int i = 0; i < MAXSERVERS; i++)
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
		g_arrServers[i][iNew] = -1;
		g_arrServers[i][hSocket] = null;
	}
}

stock void ResetGamesArray() 
{
	for (int i = 0; i < MAXGAMES; i++)
	{
		g_arrGames[i][iGameID] = -1;
		strcopy(g_arrGames[i][sName], MAX_NAME_LENGTH, "");
		g_arrGames[i][iSpecial] = -1;
		strcopy(g_arrGames[i][sAbr], MAX_NAME_LENGTH, "");
		strcopy(g_arrGames[i][sCode], MAX_NAME_LENGTH, "");
	}
}

stock void RetrieveServerIP()
{
	// Check if there's an empty IP Address CVar.
	if (StrEqual(g_sIPAddress, "", false))
	{
		int iPieces[4];
		int iLongIP = GetConVarInt(FindConVar("hostip"));
		g_iServerPort = GetConVarInt(FindConVar("hostport"));
		
		iPieces[0] = (iLongIP >> 24) & 0x000000FF;
		iPieces[1] = (iLongIP >> 16) & 0x000000FF;
		iPieces[2] = (iLongIP >> 8) & 0x000000FF;
		iPieces[3] = iLongIP & 0x000000FF;
		
		Format(g_sServerIP, sizeof(g_sServerIP), "%d.%d.%d.%d", iPieces[0], iPieces[1], iPieces[2], iPieces[3]);
	}
	else
	{
		strcopy(g_sServerIP, sizeof(g_sServerIP), g_sIPAddress);
		g_iServerPort = GetConVarInt(FindConVar("hostport"));
	}
}

stock void OpenServersMenu(iClient)
{
	if (g_iMaxServers < 1)
	{
		CReplyToCommand(iClient, "%t%t", "Tag", "NoServers");
		
		return;
	}
	
	Handle hMenu = CreateMenu(MenuCallback);
	SetMenuTitle(hMenu, "GFL Servers");
	
	for (int i = 0; i < MAXSERVERS; i++)
	{
		if (g_arrServers[i][iServerID] > 0)
		{
			char sID[11];
			Format(sID, sizeof(sID), "%d", i);
			
			char sFullName[255];
			Format(sFullName, sizeof(sFullName), "%s (%d/%d)", g_arrServers[i][sName], g_arrServers[i][iPlayerCount], g_arrServers[i][iMaxPlayers]);
			
			AddMenuItem(hMenu, sID, sFullName);
		}
	}
	
	DisplayMenu(hMenu, iClient, 0);
	
	// Make sure the handle is valid. Some errors spammed in the logs when no items were added to the list.
	if (hMenu != null)
	{
		SetMenuExitButton(hMenu, true);
	}
}

public int MenuCallback(Menu mMenu, MenuAction maAction, int iClient, int iItem)
{
	if (maAction == MenuAction_Select)
	{
		char sInfo[32];
		GetMenuItem(mMenu, iItem, sInfo, sizeof(sInfo));
		
		int iInfo = StringToInt(sInfo);
		
		DisplayServerInfo(iClient, iInfo);
	}
	else if (maAction == MenuAction_End)
	{
		delete(mMenu);
	}
}

stock void DisplayServerInfo(int iClient, int i)
{
	if (!IsClientInGame(iClient))
	{
		return;
	}
	
	char sFullName[255], sPlayerCount[255], sPublicIP[255], sRealIP[255], sMapName[64], sFullMenu[1024], sFullIP[64], sNew[32];
	
	Format(sFullName, sizeof(sFullName), "%t", "MenuName", g_arrServers[i][sName]);
	Format(sPlayerCount, sizeof(sPlayerCount), "%t", "MenuPlayers", g_arrServers[i][iPlayerCount], g_arrServers[i][iMaxPlayers]);
	Format(sPublicIP, sizeof(sPublicIP), "%t", "MenuPublicIP", g_arrServers[i][sPubIP], g_arrServers[i][iPort]);
	Format(sRealIP, sizeof(sRealIP), "%t", "MenuRealIP", g_arrServers[i][sIP], g_arrServers[i][iPort]);
	Format(sMapName, sizeof(sMapName), "%t", "MenuMap", g_arrServers[i][sCurMap]);
	if (g_arrServers[i][iNew] > 0)
	{
		Format(sNew, sizeof(sNew), "%t: Yes", "MenuNew");
	}
	else
	{
		Format(sNew, sizeof(sNew), "%t: No", "MenuNew");
	}
	Format(sFullMenu, sizeof(sFullMenu), "%s\n%s\n%s\n%s\n%s\n%s", sFullName, sPlayerCount, sPublicIP, sRealIP, sMapName, sNew);
	
	Handle hMenu = CreateMenu(ServerInfoMenuCallback);
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

public int ServerInfoMenuCallback(Menu mMenu, MenuAction maAction, int iClient, int iItem)
{
	if (maAction == MenuAction_Select)
	{
		char sInfo[64];
		GetMenuItem(mMenu, iItem, sInfo, sizeof(sInfo));
		
		if (StrEqual(sInfo, "back", false))
		{
			OpenServersMenu(iClient);
		}
		else
		{
			ConnectToServer(iClient, sInfo);
		}
	}
	else if (maAction == MenuAction_End)
	{
		delete(mMenu);
	}
}

stock void ConnectToServer(int iClient, const char[] sRealIP)
{
	Handle hKV = CreateKeyValues("menu");
	KvSetString(hKV, "time", "20");
	KvSetString(hKV, "title", sRealIP);
	CreateDialog(iClient, hKV, DialogType_AskConnect);
	delete(hKV);
}

stock void CreateSQLTables()
{
	// We need to make sure they aren't already created.
	char sQuery[64];
	Format(sQuery, sizeof(sQuery), "SELECT * FROM `%s`", g_sTableName);
	SQL_TQuery(g_hDB, Callback_TableCheck, sQuery, _, dbPriority);
}

public void Callback_TableCheck(Handle hOwner, Handle hHndl, const char[] sErr, any Data)
{
	if (hHndl == null)
	{
		// Create the tables.
		char sQuery[2048];
		Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `%s` (`id` int(11) NOT NULL AUTO_INCREMENT, `name` varchar(1024) NOT NULL,`location` int(255) NOT NULL,`ip` varchar(1024) NOT NULL,`publicip` varchar(1024) NOT NULL,`port` int(11) NOT NULL,`qport` int(11) NOT NULL,`description` varchar(1024) NOT NULL,`gameid` int(11) NOT NULL,`players` int(11) NOT NULL,`playersmax` int(11) NOT NULL,`bots` int(11) NOT NULL,`map` varchar(1024) NOT NULL,`order` int(11) NOT NULL,`password` varchar(1024) NOT NULL, `lastupdated` int(11) NOT NULL, `new` int(1) NOT NULL, PRIMARY KEY (`id`)) ENGINE=MyISAM  DEFAULT CHARSET=latin1;", g_sTableName);
		
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] Callback_TableCheck() :: Create Table Query: %s", sQuery);
		}
		
		SQL_TQuery(g_hDB, Callback_CreateTable, sQuery, _, dbPriority);
	}
}

public void Callback_CreateTable(Handle hOwner, Handle hHndl, const char[] sErr, any Data)
{
	if (hHndl == null)
	{
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] Callback_CreateTable() :: Error creating the `%s` table. Error: %s", g_sTableName, sErr);
		}
	}
	else
	{
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("serverhop-debug.log", "[GFL-ServerHop] Callback_CreateTable() :: `%s` table created successfully!", g_sTableName);
		}
	}
}

/* These are functions found from the original server hop plugin (https://forums.alliedmods.net/showthread.php?p=1036475). However, I've converted them to the new SM syntax. */
stock int GetByte(char[] sReceiveData, int iOffset)
{
	return sReceiveData[iOffset];
}

stock char GetString(char[] sReceiveData, int iDataSize, int iOffset )
{
	char sServerStr[MAX_STR_LEN] = "";
	int j = 0;

	for (int i = iOffset; i < iDataSize; i++) 
	{
		sServerStr[j] = sReceiveData[i];
		j++;
		
		if ( sReceiveData[i] == '\x0' ) 
		{
			break;
		}
	}
	
	return sServerStr;
}

/* Socket. */
public int Socket_OnConnected(Handle hSock, int iCount)
{
	char queryString[25];
	Format(queryString, sizeof( queryString ), "%s", "\xFF\xFF\xFF\xFF\x54Source Engine Query");
	SocketSend(hSock, queryString, sizeof(queryString));
}

public int Socket_OnReceived(Handle hSock, char[] sReceiveData, const int iDataSize, int iCount)
{
	// Initialize the variables needed.
	char sSrvName[MAX_STR_LEN];
	char sMapName[MAX_STR_LEN];
	char sGameDir[MAX_STR_LEN];
	char sGameDesc[MAX_STR_LEN];

	// Get the server information.
	int iOffset = 2;
	sSrvName = GetString(sReceiveData, iDataSize, iOffset);
	iOffset += strlen(sSrvName) + 1;
	sMapName = GetString(sReceiveData, iDataSize, iOffset);
	iOffset += strlen(sMapName) + 1;
	sGameDir = GetString(sReceiveData, iDataSize, iOffset);
	iOffset += strlen(sGameDir ) + 1;
	sGameDesc = GetString(sReceiveData, iDataSize, iOffset);
	iOffset += strlen(sGameDesc) + 1;
	iOffset += 2;
	g_arrServers[iCount][iPlayerCount] = GetByte(sReceiveData, iOffset)
	iOffset++;
	g_arrServers[iCount][iMaxPlayers] = GetByte(sReceiveData, iOffset);
	
	// Copy map name.
	strcopy(g_arrServers[iCount][sCurMap], MAX_STR_LEN, sMapName);

	// Delete the socket handle.
	delete hSock;
}

public int Socket_OnDisconnected(Handle hSock, int iCount)
{
	// Delete the socket's handle.
	delete hSock;
}

public int Socket_OnError(Handle hSock, const int iErrorType, const int iErrorNum, int iCount)
{
	// Since the server is down, set the maxplayers to 0, etc.
	g_arrServers[iCount][iMaxPlayers] = 0;
	g_arrServers[iCount][iPlayerCount] = 0;
	
	// Delete the socket's handle. 
	delete hSock;
}

stock int FindGameID(int iGame)
{
	int iID = 0;
	
	for (int i = 0; i < g_iMaxGames; i++)
	{
		if (g_arrGames[i][iGameID] != iGame)
		{
			// Not the game ID. Continue...
			//PrintToServer("Wrong game! %i doesn't equal %i (%s)", iGame, g_arrGames[i][iGameID], g_arrGames[i][sAbr]);
			continue;
		}
		
		//PrintToServer("Right game! %i does equal %i (%s)", iGame, g_arrGames[i][iGameID], g_arrGames[i][sAbr]);
		iID = i;
		break;
	}
	
	// Return the incremental value.
	return iID;
}