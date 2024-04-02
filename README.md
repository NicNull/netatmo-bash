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
```
## Example output
First run with login required:
```
$ ./netatmo-bash.sh 
[INFO]   No authorization file found, Netatmo login required:
[INFO]   Go to this URL to get auth code:
[ACTION] https://api.netatmo.com/oauth2/authorize?client_id=000000000000000000000&redirect_uri=http://127.0.0.1:1337&scope=read_station

[LOGIN]  Listening for redirect URI at http://127.0.0.1:1337 ...
[INFO]   # Ctrl-C to abort and input code manually #

[INFO]   Values stored in myNetatmo.csv

--------------------------------------------------------------------------
- [myNetatmo]                 Indoor               [2024-03-28 16:58:35] -
--------------------------------------------------------------------------
 Temperature: 22.6 C | Humidity: 26 % | CO2: 482 ppm
----------------------------- Outdoor ------------------------------------
 Temperature: 4.3 C | Humidity: 80 % | Pressure: 995.8 mb
--------------------------------------------------------------------------
``` 
