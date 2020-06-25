#include <sourcemod>
#include <sdktools>
#include <GFL-Core>
#include <GFL-MySQL>
#include <multicolors>

#undef REQUIRE_PLUGIN
#include <updater>

#define UPDATE_URL "http://updater.gflclan.com/GFL-MySQL.txt"
#define PL_VERSION "1.0.1"

// ConVars
ConVar g_hDatabaseName = null;
ConVar g_hRetryValue = null;
ConVar g_hAdvanceDebug = null;

// ConVar Values
char g_sDatabaseName[MAX_NAME_LENGTH];
float g_fRetryValue;
bool g_bAdvanceDebug;

// Forwards
Handle g_hOnDatabaseConnected;
Handle g_hOnDatabaseDown;

// Other
Handle g_hSQL;
bool g_bConnected = false;
bool g_bFirstConnect = true;
char g_sServerIP[64];
int g_iServerPort;
bool g_bMySQLConnectInProgress = false;
Handle g_hRetryTimer = null;

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sErr, int iErrMax) 
{
	CreateNative("GFLMySQL_GetDatabase", Native_GetDatabase);
	CreateNative("GFLMySQL_LogMessage", Native_GFLMySQL_LogMessage);
	
	RegPluginLibrary("GFL-MySQL");
	
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
	name = "GFL-MySQL",
	author = "Christian Deacon (Roy)",
	description = "GFL's MySQL plugin.",
	version = PL_VERSION,
	url = "GFLClan.com"
};

public void OnPluginStart()
{
	Forwards();
	ForwardConVars();
	ForwardCommands();
	
	// Load Translations.
	LoadTranslations("GFL-MySQL.phrases.txt");
	
	RetrieveServerIP();
}

public void OnMapEnd()
{
	if (g_hRetryTimer != null)
	{
		g_hRetryTimer = null;
	}
}

stock void Forwards() 
{
	g_hOnDatabaseConnected = CreateGlobalForward("GFLMySQL_OnDatabaseConnected", ET_Event, Param_Cell);
	g_hOnDatabaseDown = CreateGlobalForward("GFLMySQL_OnDatabaseDown", ET_Event);
}

stock void ForwardConVars() 
{	
	g_hDatabaseName = CreateConVar("sm_gflsql_name", "gflmysql", "The name of the entry in the databases.cfg.");
	HookConVarChange(g_hDatabaseName, CVarChanged);	
	
	g_hRetryValue = CreateConVar("sm_gflsql_retryvalue", "30.0", "The number of seconds the database retry value is set to.");
	HookConVarChange(g_hRetryValue, CVarChanged);	
	
	g_hAdvanceDebug = CreateConVar("sm_gflsql_debug", "0", "Advanced debug for MySQL?");
	HookConVarChange(g_hAdvanceDebug, CVarChanged);
	
	AutoExecConfig(true, "GFL-MySQL");
}

public void CVarChanged(Handle hCVar, const char[] sOldV, const char[] sNewV) 
{
	ForwardValues();
}

stock void ForwardCommands() 
{
	RegAdminCmd("sm_gflmysql_connect", Command_ManualConnect, ADMFLAG_ROOT);
	RegAdminCmd("sm_gflmysql_check", Command_Check, ADMFLAG_ROOT);
}

public void OnConfigsExecuted() 
{
	ForwardValues();
	
	ConnectDatabase();
}

stock void ForwardValues() 
{
	GetConVarString(g_hDatabaseName, g_sDatabaseName, sizeof(g_sDatabaseName));
	g_fRetryValue = GetConVarFloat(g_hRetryValue);
	g_bAdvanceDebug = GetConVarBool(g_hAdvanceDebug);
	
	if (g_hRetryTimer != null)
	{
		delete g_hRetryTimer;
	}
	
	g_hRetryTimer = CreateTimer(g_fRetryValue, Timer_DBCheck, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

stock void ConnectDatabase() 
{	
	if (g_bAdvanceDebug)
	{
		GFLCore_LogMessage("mysql-debug.log", "[GFL-MySQL] ConnectDatabase() :: Executed.");
	}
	
	if (g_hSQL != null)
	{
		CheckDatabase();
		
		if (g_hAdvanceDebug)
		{
			GFLCore_LogMessage("mysql-debug.log", "[GFL-MySQL] ConnectDatabase() :: g_hSQL isn't null. Re-using database handle to save connection space.");
		}
		
		CallBack_DatabaseConnect(g_hSQL, g_hSQL, "", 0);
	}
	else
	{
		/* Check if a connection is already in progress... */
		if (!g_bMySQLConnectInProgress)
		{
			g_bMySQLConnectInProgress = true;
			SQL_TConnect(CallBack_DatabaseConnect, g_sDatabaseName);
		}
		else
		{
			if (g_bAdvanceDebug)
			{
				GFLCore_LogMessage("mysql-debug.log", "[GFL-MySQL] ConnectDatabase() :: Already a connection in progress. Ignoring...");
			}
		}
	}
}

public void CallBack_DatabaseConnect(Handle hOwner, Handle hHndl, const char[] sErr, any data) 
{
	g_bMySQLConnectInProgress = false;
	g_bFirstConnect = false;
	
	if (hHndl == null) 
	{
		GFLCore_LogMessage("", "[GFL-MySQL] CallBack_DatabaseConnect() :: Error connecting to the database. Retrying! Error: %s", sErr);
		g_bConnected = false;
	} 
	else 
	{
		g_hSQL = hHndl;
		g_bConnected = true;
		
		PrintToServer("[GFL-MySQL] Database successfully connected!");

		// Forward the event.
		Call_StartForward(g_hOnDatabaseConnected);
		Call_PushCell(g_hSQL);
		Call_Finish();
		
		if (g_bAdvanceDebug)
		{
			GFLCore_LogMessage("mysql-debug.log", "[GFL-MySQL] CallBack_DatabaseConnect() :: Successfully connected!");
		}
	}
}

/* COMMANDS */
public Action Command_ManualConnect(int iClient, int iArgs) 
{	
	ConnectDatabase();
	
	return Plugin_Handled;
}

public Action Command_Check(int iClient, int iArgs)
{	
	CReplyToCommand(iClient, "%t%t", "Tag", "CheckingDatabase");
	
	if (g_bConnected)
	{
		CheckDatabase();
		CReplyToCommand(iClient, "%t%t", "Tag", "CheckOkay");
	}
	else
	{
		CReplyToCommand(iClient, "%t%t", "Tag", "CheckFailed");
	}
	
	return Plugin_Handled;
}

/* Timers */
public Action Timer_DBCheck(Handle hTimer) 
{
	if (g_bAdvanceDebug)
	{
		GFLCore_LogMessage("mysql-debug.log", "[GFL-MySQL] Timer_DBCheck() :: Executed...");
	}
	
	if (!g_bConnected && !g_bFirstConnect) 
	{
		/* Attempt to reconnect to the database. */
		ConnectDatabase();
	}
	else if (!g_bFirstConnect)
	{
		/* Check the database. */
		CheckDatabase();
	}
}

/* NATIVES */
public Native_GetDatabase(Handle hPlugin, int iNumParams) 
{
	return _:g_hSQL;
}

public int Native_GFLMySQL_LogMessage(Handle hPlugin, int iNumParmas) 
{
	if (g_hSQL == null)
	{
		return false;
	}
	
	char sMsg[4096], sPlugin[64], sDate[MAX_NAME_LENGTH];
	GetNativeString(1, sPlugin, sizeof(sPlugin));
	GetNativeString(2, sMsg, sizeof(sMsg));
	
	char sFormattedMsg[4096];
	FormatNativeString(0, 0, 3, sizeof(sFormattedMsg), _, sFormattedMsg, sMsg);
	
	FormatTime(sDate, sizeof(sDate), "%m-%d-%y", GetTime());
	
	char sQuery[4096];
	Format(sQuery, sizeof(sQuery), "INSERT INTO `glogs` (`sid`, `sdate`, `thetime`, `ip`, `port`, `plugin`, `message`) VALUES (0, '%s', %i, '%s', %i, '%s', '%s');", sDate, GetTime(), g_sServerIP, g_iServerPort, sPlugin, sFormattedMsg);
	
	SQL_TQuery(g_hSQL, Callback_LogMessage, sQuery, _, DBPrio_Low); 
	
	return true;
}

public void Callback_LogMessage(Handle hOwner, Handle hHndl, const char[] sErr, any Data)
{
	if (hHndl == null)
	{
		GFLCore_LogMessage("", "[GFL-MySQL] Error logging message. Error: %s", sErr);
	}
}

/* Stocks */
stock void RetrieveServerIP()
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

stock void CheckDatabase()
{
	SQL_TQuery(g_hSQL, Callback_CheckDatabase, "SELECT `sid` FROM `glogs` LIMIT 1", _, DBPrio_Normal);
}

public void Callback_CheckDatabase(Handle hOwner, Handle hHndl, const char[] sErr, any Data)
{
	if (g_bAdvanceDebug)
	{
		GFLCore_LogMessage("mysql-debug.log", "[GFL-MySQL] Callback_CheckDatabase() :: Executed...");
	}

	if (StrContains(sErr, "Can't connect", false) != -1 || StrContains(sErr, "Error connecting to the database", false) != -1 || hOwner == null)
	{
		/* We have a problem! */
		g_bConnected = false;
		
		GFLCore_LogMessage("", "[GFL-MySQL] Callback_CheckDatabase() :: Found the MySQL server offline! Error: %s", sErr);
		
		/* Delete the g_hSQL handle since it's down! */
		delete g_hSQL;
		
		Call_StartForward(g_hOnDatabaseDown);
		Call_Finish();
	}
}