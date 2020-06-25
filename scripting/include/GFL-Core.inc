/* FORWARDS */
/*
	* When the core plugin is loaded.
	*
	*@return			Nothing.
*/
forward GFLCore_OnLoad();

/*
	* When the core plugin is unloaded.
	*
	*@return			Nothing.
*/
forward GFLCore_OnUnload();

/* NATIVES */
/*
	* Logs an advanced message.
	*
	*@param sFile	The file to log to. Leave blank to use the regular date formatting.
	*@param sMsg	The message to log.
	*@return		Nothing.
*/
native bool:GFLCore_LogMessage(String:sFile[] = "", String:sMsg[] = "", any:...);

/*
	* Returns whether the client's advertisements are disabled or not.
	*
	*@param iClient	The Client's index.
	*@return		Returns true if server ads are enabled, false otherwise.
*/
native bool:GFLCore_ClientAds(iClient);