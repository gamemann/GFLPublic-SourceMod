#include <sourcemod>
#include <sdktools>
#include <GFL-Core>
#include <GFL-RconLogger>
#include <multicolors>
#include <smrcon>

#undef REQUIRE_PLUGIN
#include <updater>
#include <GFL-MySQL>

#define UPDATE_URL "http://updater.gflclan.com/GFL-RConLogger.txt"
#define PL_VERSION "1.0.1"

// ConVars
ConVar g_hTableName = null;
ConVar g_hDBPriority = null;

// ConVar Values
char g_sTableName[MAX_NAME_LENGTH];

// Other
bool g_bMySQLEnabled = false;
char g_sServerIP[32];
int g_iServerPort;

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sErr, int iErrMax)
{
	RegPluginLibrary("GFL-RconLogger");
	
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
	name = "GFL-RconLogger",
	author = "Christian Deacon (Roy)",
	description = "Logs all RCON attempts to a log file and database.",
	version = PL_VERSION,
	url = "GFLClan.com"
};

public void OnPluginStart() 
{
	//Forwards();
	ForwardConVars();
	//ForwardCommands();
	
	/* Events. */
	
	// Load Translations.
	LoadTranslations("GFL-RconLogger.phrases.txt");
}

stock void ForwardConVars() 
{	
	g_hTableName = CreateConVar("sm_gflrl_tablename", "rconlogs", "The table to insert the logs into.");
	HookConVarChange(g_hTableName, CVarChanged);	
	
	g_hDBPriority = CreateConVar("sm_gflrl_db_priority", "1", "The priority of queries for the plugin.");
	HookConVarChange(g_hDBPriority, CVarChanged);	
	
	AutoExecConfig(true, "GFL-RconLogger");
}

public void CVarChanged(Handle hCVar, const char[] OldV, const char[] NewV) 
{
	ForwardValues();
}

public void OnConfigsExecuted() 
{
	ForwardValues();
}

stock void ForwardValues() 
{
	GetConVarString(g_hTableName, g_sTableName, sizeof(g_sTableName));
}

public int GFLMySQL_OnDatabaseDown()
{
	g_bMySQLEnabled = false;
	GFLCore_LogMessage("", "[GFL-RconLogger] GFLMySQL_OnDatabaseDown() :: Executed...");
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

public Action SMRcon_OnAuth(int iID, const char[] sAddress, const char[] sPassword, bool &bAllow)
{
	if (g_bMySQLEnabled)
	{
		/* Log the RCON attempt. */
		GFLMySQL_LogMessage("GFL-RconLogger", "RCON attempt from %s", sAddress);
	}
	
	/* Log message to the  file. */
	GFLCore_LogMessage("rcon.log", "[GFL-RconLogger] SMRcon_OnAuth() :: User tried authing into the server. IP: %s Password: %s", sAddress, sPassword);
	
	return Plugin_Continue;
}

public Action SMRCon_OnCommand(int iID, const char[] sAddress, const char[] sCommand, bool &bAllow)
{
	if (g_bMySQLEnabled)
	{
		/* Log the RCON command. */
		GFLMySQL_LogMessage("GFL-RconLogger", "RCON command by %s on server %s:%i. (Command: %s)", sAddress, g_sServerIP, g_iServerPort, sCommand);
	}
	
	/* Log message to the  file. */
	GFLCore_LogMessage("rcon.log", "[GFL-RconLogger] SMRCon_OnCommand() :: RCON command executed. IP: %s | Command: %s", sAddress, sCommand);
	
	return Plugin_Continue;
}