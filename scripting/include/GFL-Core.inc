#define PL_VERSION "1.3"

/* FORWARDS */
/*
	* When the core plugin is unloaded.
	*
	*@return			Nothing.
*/
forward GFLCore_OnUnload();

/*
	* When the core plugin is loaded.
	*
	*@return			Nothing.
*/
forward GFLCore_OnLoad();

/* NATIVES */
/*
	* Logs an advanced message.
	*
	*@param sMsg	The message to log.
	*@param sFile	The file to log to. Leave blank to use the regular date formatting.
	*@return		Nothing.
*/
native bool:GFLCore_LogMessage(String:sFile[] = "", String:sMsg[] = "", any:...);

/*
	* Safely closes a handle.
	*
	*@param hHndl	The handle to safely close.
	*@return		Returns whatever CloseHandle returns.
*/
native bool:GFLCore_CloseHandle(&Handle:hHndl);

/*
	* Returns whether the client's advertisements are disabled or not.
	*
	*@param iClient	The Client's index.
	*@return		Returns true if server ads are enabled, false otherwise.
*/
native bool:GFLCore_ClientAds(iClient);