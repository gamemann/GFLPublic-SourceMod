/* FORWARDS */
/*
	* Called when the advertisement is displayed.
	*
	*@param arrServer	The array of details for the server.
	*@return			Nothing.
*/
forward GFLSH_OnAdvert();

/*
	* Called when the ServerHop list is retrieved/updated.
	*
	*@return		Nothing.
*/
forward GFLSH_OnServersUpdated();

/*
	* Called when the SQL Error count is reached.
	*
	*@return		Nothing.
*/
forward GFLSH_OnErrorCountReached();

