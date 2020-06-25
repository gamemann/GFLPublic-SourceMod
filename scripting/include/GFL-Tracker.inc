/* NATIVES */
/*
	* Returns the client's current play time.
	*
	*@return	The client's play time (seconds).
*/
native int GFLTracker_GetPlayTime(int iClient);

/*
	* Returns the client's first IP address used.
	*
	*@return	The client's first IP address ever used.
*/
//native int GFLTracker_GetFirstIP(int iClient, String:sSource[64], iMaxLen);

/*
	* Returns the client's last IP address.
	*
	*@return	The client's last IP address used.
*/
native int GFLTracker_GetLastIP(int iClient, char[] sSource);

/*
	* Returns the client's first connect.
	*
	*@return	The client's first connect (UNIX timestamp).
*/
native int GFLTracker_GetFirstConnect(int iClient);

/*
	* Returns the client's last connect.
	*
	*@return	The client's last connect (UNIX timestamp).
*/
native int GFLTracker_GetLastConnect(int iClient);

/*
	* Returns the client's connect count.
	*
	*@return	The client's connect count.
*/
native int GFLTracker_GetConnectCount(int iClient);

/*
	* Returns the client's 'other' column
	*
	*@return	The client's 'other' column.
*/
native int GFLTracker_GetOther(int iClient, char[] sSrc);