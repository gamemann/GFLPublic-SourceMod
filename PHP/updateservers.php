<?php
	/*
		File Name: updateservers.php
		Date Created: 1-1-16
		Author: Roy (Christian Deacon)
		Note: Feel free to edit.
	*/
	
	/* CONFIG */
	
	// MySQL Connection
	$DBHost = 'localhost';			// The MySQL host.
	$DBUser = 'root';				// The MySQL user.
	$DBPass = '';					// The MySQL user's password.
	$DBDatabase = 'MyDataBase';		// The MySQL Database name.
	
	// MySQL Details
	$DBTable = 'gfl_serverlist';	// The table we will be using to update the server list.
	
	// Advance Debug
	$advanceDebug = true;
	
	// Source Query Class
	require_once('SourceQuery/bootstrap.php');
	
	use xPaw\SourceQuery\SourceQuery;
	
	// Start the code.
	$db = new mysqli($DBHost, $DBUser, $DBPass, $DBDatabase);
	
	if (!$db)
	{
		die ('Error connecting to the database. Error: ' . $db->error);
	}
	
	$query = $db->query("SELECT * FROM `" . $DBTable . "`");
	
	if ($query)
	{
		if ($query->num_rows > 0)
		{
			while ($row = $query->fetch_assoc())
			{
				$serverInfo = Array();
				$sQuery = new SourceQuery();
				
				try
				{
					$sQuery->Connect($row['publicip'], $row['port'], 1);
					
					$serverInfo = $sQuery->GetInfo();
				}
				catch (Exception $e)
				{
					if ($advanceDebug)
					{
						throw ($e);
					}
				}
				
				$online = 0;
				
				if (isset($serverInfo['MaxPlayers']))
				{
					$online = 1;
				}
				
				$sQuery->Disconnect();
				
				$updateQuery = $db->query("UPDATE `" . $DBTable . "` SET `players`=" . $serverInfo['Players'] . ", `playersmax`=" . $serverInfo['MaxPlayers'] . ", `bots`=" . $serverInfo['Bots'] . ", `map`='" . $serverInfo['Map'] . "' WHERE `id`=" . $row['id']);
				
				if ($updateQuery)
				{
					if ($online)
					{
						$status = '<span style="color: #15CF04;"><strong>ONLINE</strong></span>';
					}
					else
					{
						$status = '<span style="color: #FF0000;"><strong>OFFLINE</strong></span>';
					}
					
					echo 'Updated Server: ' . $row['ip'] . ':' . $row['port'] . ' (' . $row['publicip'] . ':' . $row['port'] . ') - ' . $status . '<br />';
				}
			}
		}
		else
		{
			echo 'No servers to update.';
		}
	}
	else
	{
		die ('MySQL Query Error: ' . $db->error);
	}
?>