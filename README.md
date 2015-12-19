# To-Do-List
* Finish GFL-Badges and GFL-SelfMute.
* Organize/optimize code.
* Add translation files.
* GFL-ServerAds: Add global game specific advertisements.

# GFL-Core Features
* Custom Logging.

# GFL-MySQL Features
* Automatically connects to the database and receives the handle with a forward call.
* If the database goes down, it will attempt to reconnect until successful.

# GFL-ServerHop Features
* Display all servers from a MySQL list (`gfl_serverlist` table in GFL's IPB DataBase).
* Updates the list every x seconds.
* Depends on the GFL-MySQL plugin.
* Supporters+ can disable Server Hop advertisements.

# GFL-ServerAds Features
* Global advertisements (using GFL's IPB DataBase).
* Global paid advertisements (using GFL's IPB DataBase) | NOT IN USE YET.
* Server specific advertisements (using customads.txt in the sourcemod/configs folder).
* Three different visual types (Chat, Center, and Hint).
* Supporters+ can disable advertisements.
