/*
	12-19-15: NOT COMPLETE
*/
#include <sourcemod>
#include <sdktools>
#include <multicolors>
#include <GFL-Core>
#include <GFL-MySQL>
//#include <GFL-Badges>
#undef REQUIRE_PLUGIN
#include <updater>

#define DEVELOPDEBUG
#define UPDATE_URL "http://updater.gflclan.com/core.txt"

enum Badges
{
	iPlayTime,
	iKillCount,
	iNPlayTime,
	iNKillCount,
	iStartTime
}

new g_arrBadges[MAXPLAYERS + 1][Badges];

// Forwards

// ConVars
new Handle:g_hTableName = INVALID_HANDLE;
new Handle:g_hRefreshTimer = INVALID_HANDLE;
new Handle:g_hType = INVALID_HANDLE;

// ConVar Values
new String:g_sTableName[MAX_NAME_LENGTH];
new Float:g_fRefreshTimer;
new g_iType;

// Other
new Handle:g_hDB = INVALID_HANDLE;
new bool:g_bEnabled = false;
new bool:g_bCoreEnabled = false;
new String:g_sServerIP[64];

public APLRes:AskPluginLoad2(Handle:hMyself, bool:bLate, String:sErr[], iErrMax) 
{
	RegPluginLibrary("GFL-Badges");
	
	return APLRes_Success;
}

public OnLibraryAdded(const String:sLName[]) 
{
	if (StrEqual(sLName, "GFL-MySQL"))
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] GFL MySQL library found.");
		#endif
	}
	
	if (StrEqual(sLName, "updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
}

public Plugin:myinfo = 
{
	name = "GFL-Badges",
	description = "GFL's Badges plugin.",
	author = "Roy (Christian Deacon)",
	version = PL_VERSION,
	url = "GFLClan.com & TheDevelopingCommunity.com"
};

public OnPluginStart() 
{
	Forwards();
	ForwardConVars();
	ForwardCommands();
	ForwardEvents();
}

stock Forwards() 
{
	#if defined DEVELOPDEBUG then
		GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] Forwards().");
	#endif
}

stock ForwardConVars() 
{
	CreateConVar("GFLBadges_version", PL_VERSION, "GFL's Badges version.");
	
	g_hTableName = CreateConVar("sm_gflbadges_table_name", "gfl_serverplayers", "The table name to pick the players from.");
	HookConVarChange(g_hTableName, CVarChanged);	
	
	g_hRefreshTimer = CreateConVar("sm_gflbadges_refresh_timer", "120.00", "Save all players on the server every x seconds. < 1 disables.");
	HookConVarChange(g_hRefreshTimer, CVarChanged);	
	
	g_hType = CreateConVar("sm_gflbadges_type", "1", "1 = Use MySQL Columns for servers. 2 = Use 'ServerIP' column.");
	HookConVarChange(g_hType, CVarChanged);
	
	AutoExecConfig(true, "GFL-Badges");
}

public CVarChanged(Handle:hCVar, const String:OldV[], const String:NewV[]) 
{
	ForwardValues();
}

stock ForwardCommands() 
{
	RegAdminCmd("sm_gflbadges_updateplayers", Command_UpdatePlayers, ADMFLAG_ROOT);
	RegAdminCmd("sm_gflbadges_addcolumn", Command_AddColumn, ADMFLAG_ROOT);
}

stock ForwardEvents()
{
	HookEvent("player_death", Event_PlayerDeath);
}

public OnConfigsExecuted() 
{
	ForwardValues();
}

stock ForwardValues() 
{
	GetConVarString(g_hTableName, g_sTableName, sizeof(g_sTableName));
	g_fRefreshTimer = GetConVarFloat(g_hRefreshTimer);
	g_iType = GetConVarInt(g_hType);
}

public GFLMySQL_OnDatabaseConnected(Handle:hDB)
{
	if (hDB != INVALID_HANDLE)
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] OnDatabaseConnected() reached.");
		#endif
		g_hDB = hDB;
		g_bEnabled = true;
		
		// Start the plugin!
		AddColumn();
		RetrieveServerIP();
		CreateTimer(g_fRefreshTimer, tSavePlayers, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && g_arrBadges[i][iStartTime] == -1)
			{
				#if defined DEVELOPDEBUG then
					GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] DatabaseConnected() :: Client doesn't have a start time. Setting them up! (Client: %d)", i);
				#endif
				
				SetUpPlayer(i);
			}
		}
	}
	#if defined DEVELOPDEBUG then
		GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] OnDatabaseConnected() finished.");
	#endif
}

public GFLCore_OnLoad()
{
	#if defined DEVELOPDEBUG then
		GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] GFLCore_OnLoad() Loaded.");
	#endif
	
	g_bCoreEnabled = true;
}

public GFLCore_OnUnload()
{
	#if defined DEVELOPDEBUG then
		GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] GFLCore_OnUnload() Loaded.");
	#endif
	
	g_bCoreEnabled = false;
}

public OnClientPutInServer(iClient)
{
	g_arrBadges[iClient][iStartTime] = -1;
	g_arrBadges[iClient][iPlayTime] = -1;
	g_arrBadges[iClient][iKillCount] = -1;
	
	if (g_bEnabled && g_bCoreEnabled)
	{
		SetUpPlayer(iClient);
		
		// Let's update the "lastconnect" value real quick.
		if (g_arrBadges[iClient][iStartTime] > 1)
		{
			decl String:sLastConnectQuery[256], String:sSteamID[64];
			GetClientAuthId(iClient, AuthId_Steam2, sSteamID, sizeof(sSteamID));
			if (g_iType == 1)
			{
				Format(sLastConnectQuery, sizeof(sLastConnectQuery), "UPDATE `%s` SET `%s_lc`=%d WHERE `steamid`='%s' AND `serverip`='0'", g_sTableName, g_sServerIP, GetTime(), sSteamID);
			}
			else
			{
				Format(sLastConnectQuery, sizeof(sLastConnectQuery), "UPDATE `%s` SET `lastconnect`=%d WHERE `steamid`='%s' AND `serverip`='%s'", g_sTableName, GetTime(), sSteamID, g_sServerIP);
			}
			
			SQL_TQuery(g_hDB, LastConnectCallback, sLastConnectQuery);
		}
	}
	else
	{
		if (!g_bEnabled)
		{
			#if defined DEVELOPDEBUG then
				GFLCore_LogMessage("badges-debug.log", "[GFL-Badges]OnClientPutInServer :: !g_bEnabled");
			#endif
		}
		
		if (g_bCoreEnabled)
		{
			#if defined DEVELOPDEBUG then
				GFLCore_LogMessage("badges-debug.log", "[GFL-Badges]OnClientPutInServer :: !g_bCoreEnabled");
			#endif
		}
	}
}

public GetPlayerInfo(Handle: hOwner, Handle:hHndl, const String:sErr[], any:hData)
{
	#if defined DEVELOPDEBUG then
		GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] GetPlayerInfo() :: Executed");
	#endif
	
	// Receive the player's Steam ID.
	new iClient;
	decl String:sSteamID[64];
	
	ResetPack(hData);
	iClient = ReadPackCell(hData);
	ReadPackString(hData, sSteamID, sizeof(sSteamID));
	CloseHandle(hData);
	
	#if defined DEVELOPDEBUG then
		GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] GetPlayerInfo() :: Information (Steam ID: %s) (Client: %d)", sSteamID, iClient);
	#endif
	
	if (hOwner == INVALID_HANDLE)
	{
		#if defined DEVELOPDEBUG
			GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] GetPlayerInfo() :: Database Invalid.");
		#endif
	}
	
	if (hHndl != INVALID_HANDLE)
	{
		new iRows = SQL_GetRowCount(hHndl);
		
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] GetPlayerInfo() :: Rows: %d", iRows);
		#endif
		
		if (iRows > 0)
		{
			#if defined DEVELOPDEBUG then
				GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] GetPlayerInfo() :: Found more than one row!");
			#endif
			while (SQL_FetchRow(hHndl))
			{
				if (g_iType == 1)
				{
					decl String:sFieldKills[64], String:sFieldTime[64];
					Format(sFieldKills, sizeof(sFieldKills), "%s_kills", g_sServerIP);
					Format(sFieldTime, sizeof(sFieldTime), "%s_playtime", g_sServerIP);
					
					new iField1, iField2;
					SQL_FieldNameToNum(hHndl, sFieldKills, iField1);
					SQL_FieldNameToNum(hHndl, sFieldTime, iField2);
					
					g_arrBadges[iClient][iKillCount] = SQL_FetchInt(hHndl, iField1);
					g_arrBadges[iClient][iPlayTime] = SQL_FetchInt(hHndl, iField2);
					
				}
				else
				{
					g_arrBadges[iClient][iKillCount] = SQL_FetchInt(hHndl, 3);
					g_arrBadges[iClient][iPlayTime] = SQL_FetchInt(hHndl, 4);
				}
				
				#if defined DEVELOPDEBUG then
					GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] GetPlayerInfo() :: Client Info Retrieved (Steam ID: %s) (Play Time: %d) (Kill Count: %d)", sSteamID, g_arrBadges[iClient][iPlayTime], g_arrBadges[iClient][iKillCount]);
				#endif
			}
		}
		else
		{
			decl String:sQuery[256];
			if (g_iType == 1)
			{
				Format(sQuery, sizeof(sQuery), "INSERT INTO `%s` (steamid, serverip, %s_kills, %s_playtime) VALUES ('%s', '0', 0, 0);", g_sTableName, g_sServerIP, g_sServerIP, sSteamID);
			}
			else
			{
				Format(sQuery, sizeof(sQuery), "INSERT INTO `%s` (steamid, serverip, kills, playtime) VALUES ('%s', '%s', 0, 0);", g_sTableName, sSteamID, g_sServerIP);
			}
			
			SQL_TQuery(g_hDB, InsertPlayerCallback, sQuery, iClient);
		}
		
		g_arrBadges[iClient][iStartTime] = GetTime();
	}
	else
	{
		GFLCore_LogMessage("", "[GFL-Badges] GetPlayerInfo() :: Error getting player info. Error: %s", sErr);
	}
}

public InsertPlayerCallback(Handle:hOwner, Handle:hHndl, const String:sErr[], any:iClient)
{
	if (hHndl != INVALID_HANDLE)
	{
		g_arrBadges[iClient][iKillCount] = 0;
		g_arrBadges[iClient][iPlayTime] = 0;

		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] InsertPlayerCallback() :: Client inserted into the database.");
		#endif
	}
	else
	{
		GFLCore_LogMessage("", "[GFL-Badges] InsertPlayerCallback() :: Cannot insert player into database. Error: %s", sErr);
	}
}

public OnClientDisconnect(iClient)
{	
	if (g_bEnabled && g_bCoreEnabled)
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] OnClientDisconnect() :: Saving client (Client: %d)", iClient);
		#endif
		
		SavePlayerStats(iClient);
		
		// Let's update the "lastdisconnect" value real quick.
		decl String:sLastDisconnectQuery[256], String:sSteamID[64];
		GetClientAuthId(iClient, AuthId_Steam2, sSteamID, sizeof(sSteamID));
		if (g_iType == 1)
		{
			Format(sLastDisconnectQuery, sizeof(sLastDisconnectQuery), "UPDATE `%s` SET `%s_ld`=%d WHERE `steamid`='%s' AND `serverip`='0'", g_sTableName, g_sServerIP, GetTime(), sSteamID);
		}
		else
		{
			Format(sLastDisconnectQuery, sizeof(sLastDisconnectQuery), "UPDATE `%s` SET `lastdisconnect`=%d WHERE `steamid`='%s' AND `serverip`='%s'", g_sTableName, GetTime(), sSteamID, g_sServerIP);
		}
		
		SQL_TQuery(g_hDB, LastDisconnectCallback, sLastDisconnectQuery);
	}
	else
	{
		if (!g_bEnabled)
		{
			#if defined DEVELOPDEBUG then
				GFLCore_LogMessage("badges-debug.log", "[GFL-Badges]OnClientDisconnect() :: !g_bEnabled");
			#endif
		}
		
		if (g_bCoreEnabled)
		{
			#if defined DEVELOPDEBUG then
				GFLCore_LogMessage("badges-debug.log", "[GFL-Badges]OnClientDisconnect() :: !g_bCoreEnabled");
			#endif
		}
	}
}

public LastConnectCallback(Handle:hOwner, Handle:hHndl, const String:sErr[], any:data)
{
	if (hHndl != INVALID_HANDLE)
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] LastConnectCallback() :: Updated player successfully.");
		#endif
	}
	else
	{
		GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] LastConnectCallback() :: Did not update player successfully. Error: %s", sErr);
	}
}

public LastDisconnectCallback(Handle:hOwner, Handle:hHndl, const String:sErr[], any:data)
{
	if (hHndl != INVALID_HANDLE)
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] LastDisconnectCallback() :: Updated player successfully.");
		#endif
	}
	else
	{
		GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] LastDisconnectCallback() :: Did not update player successfully. Error: %s", sErr);
	}
}

public Event_PlayerDeath(Handle:hEvent, const String:sName[], bool:bDontBroadcast)
{
	if (g_bEnabled && g_bCoreEnabled)
	{
		new iAttacker = GetClientOfUserId(GetEventInt(hEvent, "attacker"));
		if (g_arrBadges[iAttacker][iStartTime] > 1)
		{
			g_arrBadges[iAttacker][iKillCount]++;
			g_arrBadges[iAttacker][iNKillCount]++;
			
			#if defined DEVELOPDEBUG then
				GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] Event_PlayerDeath() :: Client Kills Incremented (Client: %d) (Kills: %d)", iAttacker, g_arrBadges[iAttacker][iKillCount]);
			#endif
		}
		else
		{
			#if defined DEVELOPDEBUG then
				GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] Event_PlayerDeath() :: Client's Start Time invalid. (Client: %d) (Start Time: %d)", iAttacker, g_arrBadges[iAttacker][iStartTime]);
			#endif
		}
	}
	else
	{
		if (!g_bEnabled)
		{
			#if defined DEVELOPDEBUG then
				GFLCore_LogMessage("badges-debug.log", "[GFL-Badges]Event_PlayerDeath() :: !g_bEnabled");
			#endif
		}
		
		if (g_bCoreEnabled)
		{
			#if defined DEVELOPDEBUG then
				GFLCore_LogMessage("badges-debug.log", "[GFL-Badges]Event_PlayerDeath() :: !g_bCoreEnabled");
			#endif
		}
	}
}

public Action:tSavePlayers(Handle:hTimer)
{
	if (!g_bEnabled || !g_bCoreEnabled)
	{
		return Plugin_Stop;
	}
	
	#if defined DEVELOPDEBUG then
		GFLCore_LogMessage("badges-debug.log", "[GFL-Badges]tSavePlayers() :: Executed.");
	#endif
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			SavePlayerStats(i, true);
		}
	}
	
	return Plugin_Continue;
}

public Action:Command_UpdatePlayers(iClient, iArgs)
{
	if (!g_bEnabled || !g_bCoreEnabled)
	{	
		if (!g_bEnabled)
		{
			#if defined DEVELOPDEBUG then
				GFLCore_LogMessage("badges-debug.log", "[GFL-Badges]Command_UpdatePlayers() :: !g_bEnabled.");
			#endif
		}		
		
		if (!g_bCoreEnabled)
		{
			#if defined DEVELOPDEBUG then
				GFLCore_LogMessage("badges-debug.log", "[GFL-Badges]Command_UpdatePlayers() :: !g_CoreEnabled.");
			#endif
		}
		
		if (iClient > 0)
		{
			CPrintToChat(iClient, "{darkred}[GFL-Badges]{lightgreen}Plugin disabled.");
		}
		else
		{
			PrintToServer("[GFL-Badges]Plugin disabled.");
		}
		
		return Plugin_Handled;
	}
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			SavePlayerStats(i, true);
		}
	}
	
	if (iClient > 0)
	{
		CPrintToChat(iClient, "{darkred}[GFL-Badges]{lightgreen}Updated all players!");
	}
	else
	{
		PrintToServer("[GFL-Badges]Updated all players!");
	}
	
	return Plugin_Handled;
}

public Action:Command_AddColumn(iClient, iArgs)
{
	if (!g_bEnabled || !g_bCoreEnabled)
	{
		CReplyToCommand(iClient, "{darkred}[GFL-Badges]{default}Plugin disabled.");
		return Plugin_Handled;
	}
	
	if (g_iType != 1)
	{
		CReplyToCommand(iClient, "{darkred}[GFL-Badges]{default}\"sm_gflbadges_type\" is not set to 1.");
		return Plugin_Handled;
	}
	
	AddColumn();
	CReplyToCommand(iClient, "{darkred}[GFL-Badges]{lightgreen}AddColumns() {default}executed!");
	
	return Plugin_Handled;
}

stock SetUpPlayer(iClient)
{
	if (IsFakeClient(iClient))
	{
		return;
	}
	
	decl String:sSteamID[64];
	GetClientAuthId(iClient, AuthId_Steam2, sSteamID, sizeof(sSteamID));
	
	#if defined DEVELOPDEBUG then
		GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] SetUpPlayer() :: Executed. (Steam ID: %s)", sSteamID);
	#endif
	
	if (IsValidSteamID(sSteamID))
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] SetUpPlayer() :: IsValidSteamID passed. (Steam ID: %s)", sSteamID);
		#endif
		new Handle:hData = CreateDataPack();
		WritePackCell(hData, iClient);
		WritePackString(hData, sSteamID);
		
		decl String:sQuery[256];
		if (g_iType == 1)
		{
			Format(sQuery, sizeof(sQuery), "SELECT * FROM `%s` WHERE `steamid`='%s' AND `serverip`='0'", g_sTableName, sSteamID);
		}
		else
		{
			Format(sQuery, sizeof(sQuery), "SELECT * FROM `%s` WHERE `steamid`='%s' AND `serverip`='%s'", g_sTableName, sSteamID, g_sServerIP);
		}
		
		SQL_TQuery(g_hDB, GetPlayerInfo, sQuery, hData);
		
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] SetUpPlayer() :: Query Executed: %s", sQuery);
		#endif
	}
}

stock SavePlayerStats(iClient, bool:bTimer=false)
{
	if (IsFakeClient(iClient))
	{
		return;
	}
	
	if (g_arrBadges[iClient][iStartTime] > 1000)
	{
		new iEndTime = GetTime();
		g_arrBadges[iClient][iPlayTime] += (iEndTime - g_arrBadges[iClient][iStartTime]);
		g_arrBadges[iClient][iNPlayTime] = (iEndTime - g_arrBadges[iClient][iStartTime]);
		
		if (g_arrBadges[iClient][iNPlayTime] < 1)
		{
			return;
		}
		
		if (g_arrBadges[iClient][iNKillCount] < -1)
		{
			return;
		}
		
		if (bTimer)
		{
			g_arrBadges[iClient][iStartTime] = GetTime();
		}
		
		decl String:sQuery[256], String:sSteamID[64];
		GetClientAuthId(iClient, AuthId_Steam2, sSteamID, sizeof(sSteamID));
		if (g_iType == 1)
		{
			Format(sQuery, sizeof(sQuery), "UPDATE `%s` SET `%s_kills`=%s_kills+%d, `%s_playtime`=%s_playtime+%d WHERE `steamid`='%s' AND `serverip`='0'", g_sTableName, g_sServerIP, g_sServerIP, g_arrBadges[iClient][iNKillCount], g_sServerIP, g_sServerIP, g_arrBadges[iClient][iNPlayTime], sSteamID);
		}
		else
		{
			Format(sQuery, sizeof(sQuery), "UPDATE `%s` SET `kills`=kills+%d, `playtime`=playtime+%d WHERE `steamid`='%s' AND `serverip`='%s'", g_sTableName, g_arrBadges[iClient][iNKillCount], g_arrBadges[iClient][iNPlayTime], sSteamID, g_sServerIP);
		}
		
		SQL_TQuery(g_hDB, UpdatePlayerCallback, sQuery);
	}
	else
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] SavePlayerStats() :: Client doesn't have a valid start time (Client: %d) (Start Time: %d)", iClient, g_arrBadges[iClient][iStartTime]);
		#endif
		
		SetUpPlayer(iClient);
	}
}

public UpdatePlayerCallback(Handle:hOwner, Handle:hHndl, const String:sErr[], any:data)
{
	if (hOwner != INVALID_HANDLE)
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] SavePlayerStats() :: Client Saved");
		#endif
	}
	else
	{
		GFLCore_LogMessage("", "[GFL-Badges] SavePlayerStats() :: Cannot update player. Error: %s", sErr);
	}
}

stock IsValidSteamID(const String:sSteamID[])
{
	if (StrEqual(sSteamID, "STEAM_0:0:0", false) || StrEqual(sSteamID, "CONSOLE", false) || StrEqual(sSteamID, "Bot", false))
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] IsValidSteamID() :: Invalid: %s.", sSteamID);
		#endif
		
		return false;
	}
	
	return true;
}

stock RetrieveServerIP()
{
	new iPieces[4];
	new iLongIP = GetConVarInt(FindConVar("hostip"));
	new iPort = GetConVarInt(FindConVar("hostport"));
	
	iPieces[0] = (iLongIP >> 24) & 0x000000FF;
	iPieces[1] = (iLongIP >> 16) & 0x000000FF;
	iPieces[2] = (iLongIP >> 8) & 0x000000FF;
	iPieces[3] = iLongIP & 0x000000FF;
	
	Format(g_sServerIP, sizeof(g_sServerIP), "%d.%d.%d.%d:%d", iPieces[0], iPieces[1], iPieces[2], iPieces[3], iPort);
	
	#if defined DEVELOPDEBUG then
		GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] RetrieveServerIP() :: Got server IP: %s.", g_sServerIP);
	#endif
}

stock AddColumn()
{
	if (g_iType != 1)
	{
		return;
	}
	
	decl String:sQuery[255];
	
	Format(sQuery, sizeof(sQuery), "SHOW COLUMNS from `%s` LIKE '%s_kills'", g_sTableName, g_sServerIP);
	SQL_TQuery(g_hDB, AddColumnCallback, sQuery);
}

public AddColumnCallback(Handle:hOwner, Handle:hHndl, const String:sErr[], any:data)
{
	if (hHndl != INVALID_HANDLE)
	{
		#if defined DEVELOPDEBUG then
			GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] AddColumnCallback() :: hHndl != INVALID_HANDLE.");
		#endif
		
		new iRows = SQL_GetRowCount(hHndl);
		
		if (iRows < 1)
		{
			#if defined DEVELOPDEBUG then
				GFLCore_LogMessage("badges-debug.log", "[GFL-Badges] AddColumnCallback() :: iRows < 1. Adding column.");
			#endif
			// Need to add the column.
			decl String:sAddQuery[255];
			
			Format(sAddQuery, sizeof(sAddQuery), "ALTER TABLE `%s` ADD %s_playtime INT (11) ADD %s_kills INT (11) ADD %s_lc INT (11) ADD %s_ld INT (11)", g_sTableName, g_sServerIP, g_sServerIP, g_sServerIP, g_sServerIP);
			SQL_FastQuery(g_hDB, sAddQuery);
		}
	}
	else
	{
		GFLCore_LogMessage("", "[GFL-Badges] AddColumnCallback() :: hHndl is invalid. Error: %s", sErr);
	}
}