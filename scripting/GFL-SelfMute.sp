/*
	12-19-15: NOT COMPLETE
*/
#include <sourcemod>
#include <sdktools>
#include <GFL-Core>
#include <GFL-MySQL>
#include <GFL-SelfMute>
#undef REQUIRE_PLUGIN
#include <updater>

#define MAXMUTES "256"

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

// Arrays
new Handle:g_arrMutes[256];

new String:g_arrMenuTriggers[][] = 
{
	"sm_mutes",
	"sm_selfmute",
	"sm_sm",
	"sm_su",
	"sm_unmute"
};

public APLRes:AskPluginLoad2(Handle:hMyself, bool:bLate, String:sErr[], iErrMax) 
{
	RegPluginLibrary("GFL-SelfMute");
	
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
	name = "GFL-SelfMute",
	description = "GFL's plugin Self-Mute.",
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
		PrintToServer("[GFL-SelfMute]OnMapStart() executed");
	#endif
}

public OnClientPutInServer(iClient)
{
	CheckMutes(iClient);
}

stock Forwards() 
{
	g_hOnDatabaseConnected = CreateGlobalForward("GFLSelfMute_OnDatabaseConnected", ET_Event, Param_Cell);
}

stock ForwardConVars() 
{
	CreateConVar("GFLMySQL_version", PL_VERSION, "GFL's MySQL version.");
	
	g_hDatabaseName = CreateConVar("sm_gflselfmute_name", "gflselfmute", "The name of the entry in the databases.cfg.");
	HookConVarChange(g_hDatabaseName, CVarChanged);	
	g_hRetryValue = CreateConVar("sm_gflselfmute_retryvalue", "30.0", "The number of seconds the database retry value is set to.");
	HookConVarChange(g_hRetryValue, CVarChanged);
	
	AutoExecConfig(true, "GFL-SelfMute");
}

public CVarChanged(Handle:hCVar, const String:sOldV[], const String:sNewV[]) 
{
	ForwardValues();
}

stock ForwardCommands() 
{
	RegAdminCmd("sm_gflselfmute_connect", Command_ManualConnect, ADMFLAG_ROOT);
	
	// Menu Triggers
	for (new i = 0; i < sizeof(g_arrMenuTriggers); i++)
	{
		RegConsoleCmd(g_arrMenuTriggers[i], Command_OpenMuteMenu);
	}
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
		PrintToServer("[GFL-SelfMute]ConnectDatabase() executed");
	#endif
	
	SQL_TConnect(CallBack_DatabaseConnect, g_sDatabaseName);
}

public CallBack_DatabaseConnect(Handle:hOwner, Handle:hHndl, const String:sErr[], any:data) 
{
	#if defined DEVELOPDEBUG then
		PrintToServer("[GFL-SelfMute]CallBack_DatabaseConnect() executed");
	#endif
	if (g_hSQL != INVALID_HANDLE) 
	{
		GFLCore_CloseHandle(g_hSQL);
	}
	g_hSQL = hHndl;
	
	if (g_hSQL == INVALID_HANDLE) 
	{
		GFLCore_LogMessage("", "[GFL-SelfMute] CallBack_DatabaseConnect() :: Error connecting to the database. Retrying! Error: %s", sErr);
		g_bConnected = false;
		g_bFirstConnect = false;
	} 
	else 
	{
		g_bConnected = true;
		g_bFirstConnect = false;
		PrintToServer("[GFL-SelfMute] Database successfully connected!");

		// Forward the event.
		Call_StartForward(g_hOnDatabaseConnected);
		Call_PushCell(g_hSQL);
		Call_Finish();
		
		// Now check to see if we need to create the tables.
		SQL_TQuery(g_hSQL, CallBack_CheckTables, "SELECT * FROM `playermutes`", _, DBPrio_Low);
	}
}

public CallBack_CheckTables(Handle:hOwner, Handle:hHndl, const String:sErr[], any:data)
{
	if (hHndl == INVALID_HANDLE)
	{
		CreateTables();
	}
}

/* COMMANDS */
public Action:Command_ManualConnect(iClient, iArgs) 
{
	if (!g_bCoreEnabled)
	{
		if (iClient > 0)
		{
			PrintToChat(iClient, "\x03[GFL-SelfMute]\x02Plugin disabled. Please try again later.");
		}
		else
		{
			PrintToServer("GFL-SelfMute]Plugin disabled. Core plugin disabled.");
		}
		
		return Plugin_Handled;
	}
	
	ConnectDatabase();
	
	return Plugin_Handled;
}

public Action:Command_OpenMuteMenu(iClient, iArgs)
{
	if (!g_bCoreEnabled)
	{
		if (iClient > 0)
		{
			PrintToChat(iClient, "\x03[GFL-SelfMute]\x02Plugin disabled. Please try again later.");
		}
		else
		{
			PrintToServer("GFL-SelfMute]Plugin disabled. Core plugin disabled.");
		}
		
		return Plugin_Handled;
	}
	
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

stock CheckMutes(iClient)
{
	if (IsClientInGame(iClient))
	{
		decl String:sSteamID[64];
		GetClientAuthId(iClient, AuthId_Steam2, sSteamID, sizeof(sSteamID));
		
		decl String:sQuery[256];
		Format(sQuery, sizeof(sQuery), "SELECT * FROM `playermutes` WHERE `victimid`='%s'", sSteamID);
		
		// First, we must get the list from SQL where they are a victim.
		SQL_TQuery(g_hSQL, CallBack_CheckMutes, sQuery, iClient, DBPrio_Low);
	}
}

public CallBack_CheckMutes(Handle:hOwner, Handle:hHndl, const String:sErr[], any:iClient)
{
	if (hHndl != INVALID_HANDLE)
	{
		if (g_arrMutes[GetClientSerial(iClient)] != INVALID_HANDLE)
		{
			g_arrMutes[GetClientSerial(iClient)] = INVALID_HANDLE;
		}
		
		g_arrMutes[GetClientSerial(iClient)] = CreateArray(MAXMUTES);
		decl String:sSteamID[64];
		while (SQL_FetchRow(hHndl))
		{
			SQL_FetchString(hHndl, 2, sSteamID, sizeof(sSteamID));
			
			PushArrayString(g_arrMutes[GetClientSerial(iClient)], sSteamID);
		}
		
		// Now mute everybody.
		//MutePlayer(
	}
	else
	{
		GFLCore_LogMessage("", "[GFL-SelfMute] CallBack_CheckMutes() :: Error with query. Query Error: %s", sErr);
	}
}

stock CreateTables()
{
	SQL_FastQuery("CREATE TABLE IF NOT EXISTS `playermutes` (`id` int(11) NOT NULL, `victimid` varchar(256) NOT NULL, `targetid` varchar(256) NOT NULL, `serverip` varchar(256) NOT NULL) ENGINE=InnoDB DEFAULT CHARSET=latin1;");
	SQL_FastQuery("ALTER TABLE `playermutes` ADD PRIMARY KEY (`id`);");
}