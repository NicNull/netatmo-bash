## Netatmo bash script  
Fetches weather station measurement data and saves indoor/outdoor Temperature, Humidity and Pressure in a CSV log file.  
Bash script for getting data from netatmo API and handling OATH access and refresh tokens.  
Handles new OATH method required after May 2024 API update.  

## Script options
The script has also support for fetching battery operated modules battery level and last seen timestamp.  
Devices is marked with a "!" if last seen timestamp is older than 15 minutes, script will exit with return code 1.  
For running the script via crond, a quiet option "-q" or "--quiet" exist that only prints output on errors and module time out.  
The entire json response from the Netatmo API call can be stored in given filename using -j or --json option.  
```
Usage: netatmo-bash.sh [-s|--device-status] [-q|--quiet] [-j|--json <filename>] [--debug] [-h|--help]
                        -s, --device-status : Get available device status
                                -q, --quiet : Do not print values (cron mode)
                                 -j, --json : Save Netatmo json data API reply in <filename>
                                    --debug : Print dubug information

```

## Requiremets
Script relies on "jq" for json handling, "curl" for api access and "nc" for redirect URI snoop.  
``` 
sudo apt install jq curl netcat
```

Configuration requirements before even trying to start script:  
Get the CLIENT_ID/SECRET by login to dev.netatmo.com myApps/Create   
Update the corresponding script variables CLIENT_ID and CLIENT_SECRET to yours.  

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

-------------------------------------------------------------------
 [myNetatmo]                                 [2024-04-08 17:30:16] 
-------------------------- Indoor ---------------------------------
 Temperature: 22.3 °C |  Humidity: 27 % |  CO2: 509 ppm 
-------------------------- Outdoor --------------------------------
 Temperature: 9.1  °C |  Humidity: 78 % |  Pressure: 1002 mb 
-------------------------------------------------------------------
```
 
Device status list:
``` 
$ ./netatmo-bash.sh --device-status
  | Module          | Battery | Age   | Last Seen           
  ------------------+---------+-------+-[2024-04-08 16:35:00]-  <-- (Current time)
  | Outside         | 54 %    | 244 s |  2024-04-08 16:30:56
  | Patio           | 66 %    | 237 s |  2024-04-08 16:31:03
  | Rainguage       | 61 %    | 231 s |  2024-04-08 16:31:09
  | Windguage       | 57 %    | 231 s |  2024-04-08 16:31:09
  ------------------+---------+-------+-----------------------
```

Device status when TIME_OK is passed for module Outside:
```
$ ./netatmo-bash.sh --device-status
  | Module          | Battery | Age   | Last Seen           
  ------------------+---------+-------+-[2024-04-08 16:41:07]-
! | Outside         | 54 %    | 911 s |  2024-04-08 16:22:56
  | Patio           | 66 %    | 604 s |  2024-04-08 16:31:03
  | Rainguage       | 61 %    | 598 s |  2024-04-08 16:31:09
  | Windguage       | 57 %    | 598 s |  2024-04-08 16:31:09
  ------------------+---------+-------+-----------------------
```
Device status for timeout in --quiet mode:
```
$ ./netatmo-bash.sh --device-status --quiet
[UNREACH] Outside: Battery: 54 %, Age: 903 s, Last Seen: 2024-04-08 16:50:35

```







