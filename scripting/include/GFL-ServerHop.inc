/* FORWARDS */
/*
	* Called when the advertisement is displayed.
	*
	*@param arrServer	The array of details for the server.
	*@return			Nothing.
*/
forward GFLSH_OnAdvert();

/*
	* Called when the ServerHop server list is retrieved/updated.
	*
	*@return		Nothing.
*/
forward GFLSH_OnServersUpdated();

/*
	* Called when the ServerHop game list is retrieved/updated.
	*
	*@return		Nothing.
*/
forward GFLSH_OnGamesUpdated();