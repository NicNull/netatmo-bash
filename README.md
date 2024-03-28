## Netatmo bash script  
Fetches weather station measurement data and saves indoor/outdoor Temperature, Humidity and Pressure in a CSV log file.  
Bash script for getting data from netatmo API and handling OATH access and refresh tokens.  
Handles new OATH method required after April 2024 API update.

Requirements before even trying to start script:  
Get the CLIENT_ID/SECRET by login to dev.netatmo.com myApps/Create   

For login redirect URI a local listening socket is used for the OATH process.  
This requires script to be run on the same host as the webbrowser used for auth.  
It is also possible to skip auto capture and manually enter the return code copied from the response URI:  
``` 
http://127.0.0.1:1337/?code=<your code is here>  
 
