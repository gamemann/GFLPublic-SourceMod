#include <sourcemod>
#include <sdktools>
#include <GFL-Core>
#include <GFL-MySQL>
#include <GFL-Tracker>
#include <multicolors>

#undef REQUIRE_PLUGIN
#include <updater>

#define UPDATE_URL "http://updater.gflclan.com/GFL-Tracker.txt"
#define PL_VERSION "1.0.0"

#define DEBUGGING_FILE "tracker-debug.log"

// Player ENUM.
enum PlayerData
{
	g_iID,
	String:g_sAuthID[64],
	g_iDiscordID,
	g_iPlayTime,
	String:g_sCurIP[32],
	g_iFirstConnect,
	g_iLastConnect,
	g_iConnects,
	g_iConnStamp,
	String:g_sOther[4096]
}

int g_arrPlayerData[MAXPLAYERS+1][PlayerData];

// Prepared Statements.
char g_arrStatements[][] = 
{
	"SELECT `id`, `discordid`, `firstip`, `playtime`, `firstconnect`, `connects`, `other` FROM `playerdata` WHERE `authid`=?",
	"INSERT INTO `playerdata` (`authid`, `firstip`, `lastip`, `name`, `firstconnect`, `lastconnect`, `connects`) VALUES (?, ?, ?, ?, ?, ?, ?)",
	"UPDATE `playerdata` SET `lastip`=?, `playtime`=?, `lastconnect`=?, `connects`=? WHERE `authid`=?"
}

DBStatement g_dbGetUserInfo = null;
DBStatement g_dbInsertUser = null;
DBStatement g_dbUpdateUser = null;

// ConVars
ConVar g_cvDebug = null;
ConVar g_cvDBPriority = null;

// ConVar Values
int g_bDebug;
int g_iDBPriority;

// Other
Database g_hDB = null;
bool g_bCVarsLoaded = false;
bool g_bEnabled = false;

DBPriority g_dbPriority = DBPrio_Low;

public Plugin myinfo = 
{
	name = "GFL-Tracker",
	author = "Roy (Christian Deacon)",
	description = "Tracks all players.",
	version = PL_VERSION,
	url = "GFLClan.com"
};

// Core Events
public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sErr, int iErrMax) 
{
	RegPluginLibrary("GFL-Tracker");
	
	// Create necessary natives.
	CreateNative("GFLTracker_GetPlayTime", Native_GetPlayTime);
	//CreateNative("GFLTracker_GetFirstIP", Native_GetFirstIP);
	CreateNative("GFLTracker_GetLastIP", Native_GetLastIP);
	CreateNative("GFLTracker_GetFirstConnect", Native_GetFirstConnect);
	CreateNative("GFLTracker_GetLastConnect", Native_GetLastConnect);
	CreateNative("GFLTracker_GetConnectCount", Native_GetConnectCount);
	CreateNative("GFLTracker_GetOther", Native_GetOther);
	
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
	LoadTranslations("GFL-Tracker.phrases.txt");
	
	// Commands.
	RegAdminCmd("sm_gfltracker_reloadusers", Command_ReloadUsers, ADMFLAG_ROOT);
}

public void OnConfigsExecuted()
{
	// Fetch values.
	ForwardValues();
	
	// Hook CVar changes.
	HookConVarChange(g_cvDebug, CVarChanged);
	HookConVarChange(g_cvDBPriority, CVarChanged);
}

// ConVars
void ForwardConVars()
{
	g_cvDebug = CreateConVar("sm_gfltracker_debug", "0", "Whether to enable logging for this plugin or not.");
	g_cvDBPriority = CreateConVar("sm_gfltracker_db_priority", "1", "The priority of queries for the plugin.");
	
	AutoExecConfig(true, "GFL-Tracker");
}

void ForwardValues()
{
	g_bDebug = g_cvDebug.BoolValue;
	g_iDBPriority = g_cvDBPriority.IntValue;
	
	g_bCVarsLoaded = true;
	
	if (g_iDBPriority == 0)
	{
		// High.
		g_dbPriority = DBPrio_High;
		
		if (g_bDebug)
		{
			GFLCore_LogMessage(DEBUGGING_FILE, "[GFL-Tracker] ForwardValues() :: DataBase priority set to high.");
		}
	}
	else if (g_iDBPriority == 1)
	{
		// Normal.
		g_dbPriority = DBPrio_Normal;
		
		if (g_bDebug)
		{
			GFLCore_LogMessage(DEBUGGING_FILE, "[GFL-Tracker] ForwardValues() :: DataBase priority set to normal.");
		}
	}
	else if (g_iDBPriority == 2)
	{
		// Low.
		g_dbPriority = DBPrio_Low;
		
		if (g_bDebug)
		{
			GFLCore_LogMessage(DEBUGGING_FILE, "[GFL-Tracker] ForwardValues() :: DataBase priority set to low.");
		}
	}
	else
	{
		// Normal.
		g_dbPriority = DBPrio_Normal;
		
		if (g_bDebug)
		{
			GFLCore_LogMessage(DEBUGGING_FILE, "[GFL-Tracker] ForwardValues() :: DataBase priority set to normal. (value not valid)");
		}
	}
}

public void CVarChanged(Handle hCVar, const char[] OldV, const char[] NewV)
{
	if(g_bDebug)
	{
		GFLCore_LogMessage(DEBUGGING_FILE, "[GFL-UserManagement] CVarChanged() :: A CVar has been altered.");
	}
	
	// Get values again
	ForwardValues();
}

public int GFLMySQL_OnDatabaseConnected(Database hDB)
{
	if (g_bDebug)
	{
		GFLCore_LogMessage(DEBUGGING_FILE, "[GFL-Tracker] GFLMySQL_OnDatabaseConnected() :: Executed...");
	}
	
	// Set g_bEnabled to false just in case.
	g_bEnabled = false;
	
	if (hDB != null && g_bCVarsLoaded)
	{
		g_hDB = hDB;
		g_bEnabled = true;
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
	GFLCore_LogMessage("", "[GFL-Tracker] GFLMySQL_OnDatabaseDown() :: Executed...");
	g_bEnabled = false;
	
	// Create a retry timer.
	CreateTimer(30.0, Timer_Reconnect, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

public Action Timer_Reconnect(Handle hTimer)
{
	// Let's try to grab the database.
	Database hDB = GFLMySQL_GetDatabase();
	
	// Check if database is valid.
	if (hDB != null)
	{
		// Attempt to reconnect.
		GFLMySQL_OnDatabaseConnected(hDB);
		
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

public void OnClientPostAdminCheck(int iClient)
{
	if (g_bEnabled)
	{
		LoadUser(iClient, true);
	}
}

public void LoadUser(int iClient, bool bConnect)
{
	char sAuthID[64];
	char sIP[32];
	char sFirstIP[32];
	char sName[MAX_NAME_LENGTH];
	
	int iID = 0;
	int iDiscordID = 0;
	int iPlayTime = 0;
	int iFirstConnect = 0;
	int iConnects = 0;
	char sOther[4096];
	
	GetClientAuthId(iClient, AuthId_SteamID64, sAuthID, sizeof(sAuthID), true);
	GetClientIP(iClient, sIP, sizeof(sIP));
	GetClientName(iClient, sName, sizeof(sName));
	
	if (g_dbGetUserInfo == null)
	{
		// Create the prepared statement real quick.
		char sErr[255];
		
		g_dbGetUserInfo = SQL_PrepareQuery(g_hDB, g_arrStatements[0], sErr, sizeof(sErr));
		
		if (g_dbGetUserInfo == null)
		{
			GFLCore_LogMessage("", "[GFL-Tracker] LoadUser() :: Error creating prepared statement (g_dbGetUserInfo) - %s", sErr);
			
			return;
		}
	}
	
	SQL_BindParamString(g_dbGetUserInfo, 0, sAuthID, false);
	
	if (!SQL_Execute(g_dbGetUserInfo))
	{
		char sQueryErr[255];
		SQL_GetError(g_hDB, sQueryErr, sizeof(sQueryErr));
		
		GFLCore_LogMessage("", "[GFL-Tracker] LoadUser() :: Couldn't execute prepared statement (g_dbGetUserInfo). Error - %s", sQueryErr);
		
		return;
	}
	
	if (SQL_GetRowCount(g_dbGetUserInfo) < 1)
	{
		// Let's enter the user into the database.
		
		// Check if the `g_dbInsertUser` prepared statement is created.
		if (g_dbInsertUser == null)
		{
			char sErr[255];
			
			g_dbInsertUser = SQL_PrepareQuery(g_hDB, g_arrStatements[1], sErr, sizeof(sErr));
			
			if (g_dbInsertUser == null)
			{
				GFLCore_LogMessage("", "[GFL-Tracker] LoadUser() :: Error creating prepared statement (g_dbInsertUser) - %s", sErr);
				
				return;
			}
		}
		
		// Add debugging message.
		if (g_bDebug)
		{
			GFLCore_LogMessage(DEBUGGING_FILE, "[GFL-Tracker] LoadUser() :: Inserting %s (%s) into the database with the IP %s", sName, sAuthID, sIP);
		}
		
		// Fill out defaults that need values.
		SQL_BindParamString(g_dbInsertUser, 0, sAuthID, false);
		SQL_BindParamString(g_dbInsertUser, 1, sIP, false);
		SQL_BindParamString(g_dbInsertUser, 2, sIP, false);
		SQL_BindParamString(g_dbInsertUser, 3, sName, false);
		SQL_BindParamInt(g_dbInsertUser, 4, GetTime());
		SQL_BindParamInt(g_dbInsertUser, 5, GetTime());
		SQL_BindParamInt(g_dbInsertUser, 6, 1);
		
		if (!SQL_Execute(g_dbInsertUser))
		{
			char sQueryErr[255];
			SQL_GetError(g_hDB, sQueryErr, sizeof(sQueryErr));
			
			GFLCore_LogMessage("", "[GFL-Tracker] LoadUser() :: Couldn't execute prepared statement (g_dbInsertUser). Error - %s", sQueryErr);
			
			return;
		}
		
		iID = SQL_GetInsertId(g_hDB);
	}
	else
	{
		while (SQL_FetchRow(g_dbGetUserInfo))
		{
			iID = SQL_FetchInt(g_dbGetUserInfo, 0);
			iDiscordID = SQL_FetchInt(g_dbGetUserInfo, 1);
			SQL_FetchString(g_dbGetUserInfo, 2, sFirstIP, sizeof(sFirstIP));
			iPlayTime = SQL_FetchInt(g_dbGetUserInfo, 3);
			iFirstConnect = SQL_FetchInt(g_dbGetUserInfo, 4);
			iConnects = SQL_FetchInt(g_dbGetUserInfo, 5);
			SQL_FetchString(g_dbGetUserInfo, 6, sOther, sizeof(sOther));
		}
	}
	
	// Fill the array.
	g_arrPlayerData[iClient][g_iID] = iID;
	strcopy(g_arrPlayerData[iClient][g_sAuthID], 64, sAuthID);
	g_arrPlayerData[iClient][g_iDiscordID] = iDiscordID;
	g_arrPlayerData[iClient][g_iPlayTime] = iPlayTime;
	strcopy(g_arrPlayerData[iClient][g_sCurIP], 32, sIP);
	g_arrPlayerData[iClient][g_iFirstConnect] = iFirstConnect;
	g_arrPlayerData[iClient][g_iLastConnect] = GetTime();
	g_arrPlayerData[iClient][g_iConnects] = iConnects;
	g_arrPlayerData[iClient][g_iConnStamp] = GetTime();
	strcopy(g_arrPlayerData[iClient][g_sOther], 4096, sOther);
	
	// Add onto the connects count if it's a connect.
	if (bConnect)
	{
		g_arrPlayerData[iClient][g_iConnects] = g_arrPlayerData[iClient][g_iConnects] + 1;
	}
	
	// Add debugging message.
	if (g_bDebug)
	{
		GFLCore_LogMessage(DEBUGGING_FILE, "[GFL-Tracker] LoadUser() :: Loaded user %s (%s)(%i) with the IP %s and play time %i. Their Discord ID is %i and the current timestamp is %i", sName, sAuthID, iID, sIP, iPlayTime, iDiscordID, GetTime());
	}
}

public void OnClientDisconnect(int iClient)
{
	SaveUser(iClient, true);
}

public bool SaveUser(int iClient, bool bReset)
{
	// Check if the client's ID is higher than 0.
	if (g_arrPlayerData[iClient][g_iID] < 1)
	{
		return false;
	}
	
	// Create Update prepared statement if it doesn't exist.
	if (g_dbUpdateUser == null)
	{
		char sErr[255];
		
		g_dbUpdateUser = SQL_PrepareQuery(g_hDB, g_arrStatements[2], sErr, sizeof(sErr));
		
		if (g_dbUpdateUser == null)
		{
			GFLCore_LogMessage("", "[GFL-Tracker] SaveUser() :: Error creating prepared statement (g_dbUpdateUser) - %s", sErr);
				
			return false;
		}
	}
	
	// Let's now update some values (e.g. add on time).
	g_arrPlayerData[iClient][g_iPlayTime] = g_arrPlayerData[iClient][g_iPlayTime] + (GetTime() - g_arrPlayerData[iClient][g_iConnStamp]);
	g_arrPlayerData[iClient][g_iConnStamp] = GetTime();
	
	SQL_BindParamString(g_dbUpdateUser, 0, g_arrPlayerData[iClient][g_sCurIP], false);
	SQL_BindParamInt(g_dbUpdateUser, 1, g_arrPlayerData[iClient][g_iPlayTime]);
	SQL_BindParamInt(g_dbUpdateUser, 2, g_arrPlayerData[iClient][g_iLastConnect]);
	SQL_BindParamInt(g_dbUpdateUser, 3, g_arrPlayerData[iClient][g_iConnects]);
	SQL_BindParamString(g_dbUpdateUser, 4, g_arrPlayerData[iClient][g_sAuthID], false);
	
	if (!SQL_Execute(g_dbUpdateUser))
	{
		char sQueryErr[255];
		SQL_GetError(g_hDB, sQueryErr, sizeof(sQueryErr));
		
		GFLCore_LogMessage("", "[GFL-Tracker] SaveUser() :: Couldn't execute prepared statement (g_dbUpdateUser). Error - %s", sQueryErr);
		
		return false;
	}
	
	if (g_bDebug)
	{
		GFLCore_LogMessage(DEBUGGING_FILE, "[GFL-Tracker] SaveUser() :: Saving %s (%i) with a new play time of %i and connects of %i. Their last connect was on %i", g_arrPlayerData[iClient][g_sAuthID], g_arrPlayerData[iClient][g_iID], g_arrPlayerData[iClient][g_iPlayTime], g_arrPlayerData[iClient][g_iConnects], g_arrPlayerData[iClient][g_iLastConnect]);
	}
	
	if (bReset)
	{
		ResetData(iClient);
	}
	
	return true;
}

public Action Command_ReloadUsers(int iClient, int iArgs)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}
		
		SaveUser(i, false);
		
		CReplyToCommand(iClient, "%t%t", "TrackerTag", "ReloadedUser", iClient, g_arrPlayerData[i][g_sAuthID]);
	}
	
	CReplyToCommand(iClient, "%t%t", "TrackerTag", "ReloadedAllUsers");
	
	return Plugin_Handled;
}

public void ResetData(int iIndex)
{
	g_arrPlayerData[iIndex][g_iID] = -1;
	strcopy(g_arrPlayerData[iIndex][g_sAuthID], 64, "");
	g_arrPlayerData[iIndex][g_iDiscordID] = -1;
	g_arrPlayerData[iIndex][g_iPlayTime] = -1;
	strcopy(g_arrPlayerData[iIndex][g_sCurIP], 32, "");
	g_arrPlayerData[iIndex][g_iFirstConnect] = -1;
	g_arrPlayerData[iIndex][g_iLastConnect] = -1;
	g_arrPlayerData[iIndex][g_iConnects] = -1;
	g_arrPlayerData[iIndex][g_iConnStamp] = -1;
	strcopy(g_arrPlayerData[iIndex][g_sOther], 4096, "");
}

/* Natives */
public int Native_GetPlayTime(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	return g_arrPlayerData[iClient][g_iPlayTime];
}

public int Native_GetLastIP(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	SetNativeString(2, g_arrPlayerData[iClient][g_sCurIP], 32);
}

public int Native_GetFirstConnect(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	return g_arrPlayerData[iClient][g_iFirstConnect];
}

public int Native_GetLastConnect(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	return g_arrPlayerData[iClient][g_iLastConnect];
}

public int Native_GetConnectCount(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	return g_arrPlayerData[iClient][g_iConnects];
}

public int Native_GetOther(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	SetNativeString(2, g_arrPlayerData[iClient][g_sOther], 4096);
}