/*
	* Called when the GFL-MySQL plugin successfully connects to the database.
	*
	*@param hDB		The database handle.
	*@return		Nothing.
*/
forward GFLMySQL_OnDatabaseConnected(Handle:hDB);

/*
	* Called when the MySQL database is detected as offline.
	*
	*@return		Nothing.
*/
forward GFLMySQL_OnDatabaseDown();

/* NATIVES */
/*
	* Returns the current database handle from GFL-MySQL.
	*
	*@return	The database handle.
*/
native Handle:GFLMySQL_GetDatabase();

/*
	* Logs a message to our SQL database.
	*
	*@param sPlugin	The Plugin's name.
	*@param sMsg	The message to log.
	*@return		Nothing.
*/
native bool:GFLMySQL_LogMessage(String:sPlugin[] = "", String:sMsg[] = "", any:...);