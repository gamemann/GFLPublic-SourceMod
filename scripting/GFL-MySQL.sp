#include <sourcemod>
#include <sdktools>
#include <GFL-Core>
#include <GFL-MySQL>
#undef REQUIRE_PLUGIN
#include <updater>

//#define DEVELOPDEBUG
#define UPDATE_URL "http://updater.gflclan.com/core.txt"

// ConVars
new Handle:g_hDatabaseName = INVALID_HANDLE;
new Handle:g_hRetryValue = INVALID_HANDLE;

// ConVar Values
new String:g_sDatabaseName[MAX_NAME_LENGTH];
new Float:g_fRetryValue;

// Forwards
new Handle:g_hOnDatabaseConnected;

// Other
new Handle:g_hSQL = INVALID_HANDLE;
new bool:g_bConnected;
new bool:g_bFirstConnect = true;
new bool:g_bCoreEnabled = false;

public APLRes:AskPluginLoad2(Handle:hMyself, bool:bLate, String:sErr[], iErrMax) 
{
	CreateNative("GFLMySQL_GetDatabase", Native_GetDatabase);
	RegPluginLibrary("GFL-MySQL");
	
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
	name = "GFL-MySQL",
	description = "GFL's plugin MySQL.",
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

public OnMapStart() 
{
	g_bConnected = false;
	CreateTimer(5.0, Timer_Delay, _, TIMER_FLAG_NO_MAPCHANGE);
	
	#if defined DEVELOPDEBUG then
		PrintToServer("[GFL-MySQL]OnMapStart() executed");
	#endif
}

stock Forwards() 
{
	g_hOnDatabaseConnected = CreateGlobalForward("GFLMySQL_OnDatabaseConnected", ET_Event, Param_Cell);
}

stock ForwardConVars() 
{
	CreateConVar("GFLMySQL_version", PL_VERSION, "GFL's MySQL version.");
	
	g_hDatabaseName = CreateConVar("sm_gflsql_name", "gflmysql", "The name of the entry in the databases.cfg.");
	HookConVarChange(g_hDatabaseName, CVarChanged);	
	g_hRetryValue = CreateConVar("sm_gflsql_retryvalue", "30.0", "The number of seconds the database retry value is set to.");
	HookConVarChange(g_hRetryValue, CVarChanged);
	
	AutoExecConfig(true, "GFL-MySQL");
}

public CVarChanged(Handle:hCVar, const String:sOldV[], const String:sNewV[]) 
{
	ForwardValues();
}

stock ForwardCommands() 
{
	RegAdminCmd("sm_gflmysql_connect", Command_ManualConnect, ADMFLAG_ROOT);
}

public OnConfigsExecuted() 
{
	ForwardValues();
}

stock ForwardValues() 
{
	GetConVarString(g_hDatabaseName, g_sDatabaseName, sizeof(g_sDatabaseName));
	g_fRetryValue = GetConVarFloat(g_hRetryValue);
}

public GFLCore_OnLoad()
{
	g_bCoreEnabled = true;
	
	if (!g_bConnected)
	{
		ConnectDatabase();
	}
}

public GFLCore_OnUnload()
{
	g_bCoreEnabled = false;
}

stock ConnectDatabase() 
{
	if (!g_bCoreEnabled)
	{
		return;
	}
	
	#if defined DEVELOPDEBUG then
		PrintToServer("[GFL-MySQL]ConnectDatabase() executed");
	#endif
	
	SQL_TConnect(CallBack_DatabaseConnect, g_sDatabaseName);
}

public CallBack_DatabaseConnect(Handle:hOwner, Handle:hHndl, const String:sErr[], any:data) 
{
	#if defined DEVELOPDEBUG then
		PrintToServer("[GFL-MySQL]CallBack_DatabaseConnect() executed");
	#endif
	if (g_hSQL != INVALID_HANDLE) 
	{
		GFLCore_CloseHandle(g_hSQL);
	}
	g_hSQL = hHndl;
	
	if (g_hSQL == INVALID_HANDLE) 
	{
		GFLCore_LogMessage("", "[GFL-MySQL] CallBack_DatabaseConnect() :: Error connecting to the database. Retrying! Error: %s", sErr);
		g_bConnected = false;
		g_bFirstConnect = false;
	} 
	else 
	{
		g_bConnected = true;
		g_bFirstConnect = false;
		PrintToServer("[GFL-MySQL] Database successfully connected!");

		// Forward the event.
		Call_StartForward(g_hOnDatabaseConnected);
		Call_PushCell(g_hSQL);
		Call_Finish();
	}
}

/* Server Hop Error Count Reached */
public GFLSH_OnErrorCountReached() 
{
	g_bConnected = false;
	g_bFirstConnect = false;
}

/* COMMANDS */
public Action:Command_ManualConnect(iClient, iArgs) 
{
	if (!g_bCoreEnabled)
	{
		if (iClient > 0)
		{
			PrintToChat(iClient, "\x03[GFL-MySQL]\x02Plugin disabled. Please try again later.");
		}
		else
		{
			PrintToServer("GFL-MySQL]Plugin disabled. Core plugin disabled.");
		}
		
		return Plugin_Handled;
	}
	
	ConnectDatabase();
	
	return Plugin_Handled;
}

/* Timers */
public Action:Timer_Delay(Handle:hTimer) 
{
	if (g_fRetryValue < 1.0) 
	{
		g_fRetryValue = 1.0; // Very un-safe to have this value under 1.0...
	}
	CreateTimer(g_fRetryValue, Timer_DBCheck, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action:Timer_DBCheck(Handle:hTimer) 
{
	if (!g_bConnected && !g_bFirstConnect) 
	{
		ConnectDatabase();
	}
}

/* NATIVES */
public Native_GetDatabase(Handle:hPlugin, iNumParams) 
{
	return _:g_hSQL;
}