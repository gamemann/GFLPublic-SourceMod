/*
	* Called when the GFL-MySQL plugin successfully connects to the database.
	*
	*@param hDB		The database handle.
	*@return		Nothing.
*/
forward GFLMySQL_OnDatabaseConnected(Handle:hDB);

/* NATIVES */
/*
	* Returns the current database handle from GFL-MySQL.
	*
	*@return	The database handle.
*/
native Handle:GFLMySQL_GetDatabase();