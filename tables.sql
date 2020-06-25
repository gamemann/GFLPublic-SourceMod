-- Table: gfl_adverts-default
-- Description: The global advertisements table. Feel free to rename the table name but please make sure you set the ConVar correctly ("sm_gflsa_global_tablename").
-- -- id - Auto Increment.
-- -- message - The message of the advertisement.
-- -- gameid - The game ID the message is for. Set to 0 for a global message. Set to <gameID> for the message to show for all servers in that game only.
-- -- serverid - The Server ID of the message. CURRENTLY NOT IN USE.
-- -- chattype - The message's type. 1 = PrintToChat, 2 = PrintCenterText, 3 = PrintHintText
CREATE TABLE IF NOT EXISTS `gfl_adverts-default` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `message` varchar(1024) NOT NULL,
  `gameid` int(11) NOT NULL,
  `serverid` int(11) NOT NULL,
  `chattype` int(11) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM  DEFAULT CHARSET=latin1;


-- Table: gfl_adverts-paid
-- Description: A global advertisements table. This is for people that paid for advertisments. This is currently not in use. However, it wouldn't be difficult to write a PHP script that would do this.
-- -- id - Auto Increment.
-- -- pid - Purchase ID. Used for a purchase ID (e.g. IPB Nexus).
-- -- uid - The User's ID in the database (must be a number).
-- -- message - The message of the advertisement.
-- -- chattype - The message's type. 1 = PrintToChat, 2 = PrintCenterText, 3 = PrintHintText
CREATE TABLE IF NOT EXISTS `gfl_adverts-paid` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `pid` int(11) NOT NULL,
  `uid` int(11) NOT NULL,
  `activated` int(1) NOT NULL,
  `message` varchar(1024) NOT NULL,
  `chattype` int(11) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM  DEFAULT CHARSET=latin1;

-- Table: gfl_gamelist
-- Description: The game list.
-- -- id - Auto Increment.
-- -- name - The full name of the game (e.g. Counter-Strike: Global Offensive).
-- -- special - Not very important. However, for GFL, BattleField 3 used a special query method. Therefore, setting this to 1 for BattleField 3 servers resulted in using that query method.
-- -- abr - The game's abbreviation (e.g. CS:GO).
-- Notes:
-- - A default game list was included.
CREATE TABLE IF NOT EXISTS `gfl_gamelist` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(1024) NOT NULL,
  `special` int(255) NOT NULL,
  `abr` varchar(255) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1;

INSERT INTO `gfl_gamelist` (`id`, `name`, `special`, `abr`) VALUES
(1, 'Counter-Strike: Source', 0, 'CS:S'),
(2, 'Team-Fortress 2', 0, 'TF2'),
(3, 'Garry''s Mod', 0, 'GMod'),
(4, 'Counter-Strike: Global Offensive', 0, 'CS:GO'),
(5, 'Red Orchestra 2', 0, 'RO2'),
(6, 'BattleField 3', 1, 'BF3');

-- Table: gfl_locationlist
-- Description: The location list.
-- -- id - Auto Increment.
-- -- name - The full name of the location (e.g. Chicago, United States).
-- -- abr - The location's abbreviation. (e.g. US or Chicago, US).
-- Notes:
-- - A default location list was included.
CREATE TABLE IF NOT EXISTS `gfl_locationlist` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(1024) NOT NULL,
  `abr` varchar(256) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1;

INSERT INTO `gfl_locationlist` (`id`, `name`, `abr`) VALUES
(1, 'United States', 'US'),
(2, 'Germany (EU)', 'EU');

-- Table: gfl_serverlist
-- Description: The server list. This is used for Server Hop and Server IDs. You can write a PHP script to query all these servers for a neat server list for your website.
-- -- id - Auto Increment.
-- -- name - The server's name. This isn't the hostname. (e.g. CS:GO Zombie Escape).
-- -- location - The location ID. IDs come from the `gfl_locationlist` table.
-- -- ip - The IP of the server to connect to. (e.g. goze.gflclan.com).
-- -- publicip - The actual IP of the server. (e.g. 216.52.148.47).
-- -- port - The server's port.
-- -- qport - The querying port. Used for when you write a PHP script to query the servers. Usually the same as `port`.
-- -- description - A quick description of the server.
-- -- gameid - The server's Game ID. IDs come from the `gfl_gamelist` table.
-- -- players - Amount of players the server has. This is updated with the PHP update script.
-- -- playersmax - The maximum amount of players. This is updated with the PHP update script.
-- -- bots - The amount of bots. This is updated with the PHP update script.
-- -- map - The current map. This is updated with the PHP update script.
-- -- order - The order. This can be used to order servers on a website using a PHP script.
-- -- password - The server's password. This can be used in a PHP script.
CREATE TABLE IF NOT EXISTS `gfl_serverlist` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(1024) NOT NULL,
  `location` int(255) NOT NULL,
  `ip` varchar(1024) NOT NULL,
  `publicip` varchar(1024) NOT NULL,
  `port` int(11) NOT NULL,
  `qport` int(11) NOT NULL,
  `description` varchar(1024) NOT NULL,
  `gameid` int(11) NOT NULL,
  `players` int(11) NOT NULL,
  `playersmax` int(11) NOT NULL,
  `bots` int(11) NOT NULL,
  `map` varchar(1024) NOT NULL,
  `order` int(11) NOT NULL,
  `password` varchar(1024) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM  DEFAULT CHARSET=latin1;