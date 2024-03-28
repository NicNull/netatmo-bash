## Netatmo bash script  
Bash script for getting data from netatmo API and handling OATH access and refresh tokens.  
Handles new OATH method required after April 2024 API update.

Requirements before even trying to start script:  
Get the CLIENT_ID/SECRET by login to dev.netatmo.com myApps/Create   
Station MAC address is avialable in my.netatmo.com Settings/Manage Home/RoomName/MAC Address
 
For login redirect URI a public available web server running netatmo.php is required for the OATH process.  
An example netatmo.php file and nginx configuration is provided as well.
