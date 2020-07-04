# Archived
You can find the latest version of each plugin in GFL's organization [here](https://github.com/GFLClan).

# To-Do-List
* None.

# GFL-Core Features
* Custom Logging.

# GFL-MySQL Features
* Automatically connects to the database and receives the handle with a forward call.
* If the database goes down, it will attempt to reconnect until successful.

# GFL-ServerHop Features
* Display all servers from a MySQL list (`gfl_serverlist` table in GFL's IPB DataBase).
* Updates the list every x seconds.
* Depends on the GFL-MySQL plugin.
* Anybody with a specific flag can disable Server Hop advertisements (e.g. Donators, Supporters, etc).
* Set query priority levels.

# GFL-ServerAds Features
* Global advertisements.
* Global game advertisements.
* Global paid advertisements.
* Server specific advertisements (using customads.txt in the sourcemod/configs folder).
* Three different visual types (Chat, Center, and Hint).
* Depends on the GFL-MySQL plugin.
* Anybody with a specific flag can disable advertisements (e.g. Donators, Supporters, etc).
* Set query priority levels.

# Install Instructions
* Create a MySQL database and make sure to set up the database entry in sourcemod/configs/databases.cfg (entry name: gflmysql).
* Let the server create the tables or import the SQL file located in the root of this repository.
* Read the SQL file located in the root of this repository for information on setting up the database.