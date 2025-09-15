#!/bin/bash
## Netatmo bash script to get weather station data. 
## Bash script for getting data from netatmo API and handling OATH access and refresh tokens. 
## Handles new OATH method required after April 2024 API update.
## See README.md for more details
##
## https://github.com/NicNull/netatmo-bash
##
## Requirements before even trying to start script:
## Get the CLIENT_ID/SECRET by login to dev.netatmo.com myApps/Create 
## 
## For login redirect URI a local listening socket is used for the OATH process.
## This requires script to be run on the same host as the webbrowser used for auth.
## Added --manual-code option to skip auto capture that also skips redirecting to the netatmo dashboard after login.
## It is also possible to press Ctrl-C to activate the manual code prompt before launching the netatmo login URL in the browser.
## Just manually enter the return code copied from the response URI:
## http://127.0.0.1:1337/?code=<your code is here>
##

# Set these to your keys:
CLIENT_ID="########################"
CLIENT_SECRET="###################################"


# Script parameters
REDIR_HOST="127.0.0.1"
REDIR_PORT="1337"
PRINT=1
DEBUG=0
MANUAL_CODE=0
DEVICE_STATUS=0
JSON_FILE=""
# Seconds since last seen to be considered OK (default 15m)
TIME_OK=900   

# Loop through command-line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        '--device-status' | '-s')
            DEVICE_STATUS=1
            ;;
        '-q' | '--quiet')
            PRINT=0
            ;;
        '-j' | '--json')
            if [ -n "$2" ]; then
		JSON_FILE="$2"
            	shift
            else
            	echo "[ERROR]  Option $1 needs an argument!"
            	exit 1
            fi
            ;;
        '--manual-code')
            MANUAL_CODE=1
            ;;
        '--debug')
            DEBUG=1
            ;;
        '--help' | '-h')
            echo "Usage: $(basename "$0") [-s|--device-status] [-q|--quiet] [-j|--json <filename>] [--debug] [-h|--help]" >&2
            echo "                        -s, --device-status : Get available device status" >&2
            echo "                                -q, --quiet : Do not print values (cron mode)" >&2
            echo "                                 -j, --json : Save Netatmo json data API reply in <filename>" >&2
            echo "                              --manual-code : No auto capture of OATH return code or redirect is done" >&2
            echo "                                    --debug : Print dubug information" >&2
            exit 1 
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift  # Move to the next argument
done

# Function to handle Ctrl-C (SIGINT)
cleanup() {
    if [ $MANUAL_CODE -eq 0 ]; then
	    echo -e "\r[WARN]   Aborted redirect URI snoop."
    else
	    echo -e "\r[WARN]   Ctrl-C Pressed. Press again to quit, Enter to continue"
    fi
    trap - SIGINT
}


#
# URI redirect response
#
REPLY=$(cat <<EOF
HTTP/1.1 303 Found
Location: https://home.netatmo.com/
Content-Type: text/html
Cache-Control: max-age=0
EOF
)

#
# Login only first time to get token credential file
#
function loginAuth
{
  REDIR_URL="http://$REDIR_HOST:$REDIR_PORT"
  echo "[INFO]   Go to this URL to get auth code:"
  echo "[ACTION] https://api.netatmo.com/oauth2/authorize?client_id=$CLIENT_ID&redirect_uri=${REDIR_URL}&scope=read_station" 
  echo
  # Trap Ctrl-C and call the cleanup function
  trap cleanup SIGINT
  if [ $MANUAL_CODE -eq 0 ]; then
	echo "[LOGIN]  Listening for redirect URI at $REDIR_URL ..."
	echo "[INFO]   # Ctrl-C to abort and input code manually #"
	CODE=$(nc -q 5 -w 2 -l $REDIR_HOST $REDIR_PORT <<<$REPLY |head -n1)
	CODE=$(grep -Po "code=\K[^ ]+" <<<$CODE)
	if [ -n "$CODE" ]; then
	  echo "[INFO]   Code aquired from response URI" 
	fi
	if [ $DEBUG -eq 1 ]; then
	  echo "[DEBUG]  CODE: $CODE"
	fi
  else
	echo "[INFO]   Manually enter the return code shown in the response URI after login:"
        echo "[INFO]   http://127.0.0.1:1337/?code=<your code is here>"
  fi  
  while [ -z "$CODE" ]; do
    MANUAL_CODE=1
    trap cleanup SIGINT
    read -p "[INPUT]  Enter code: " CODE
  done
  echo
  AUTH=$(curl -s -d "grant_type=authorization_code&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&code=$CODE&redirect_uri=${REDIR_URL}&scope=read_station" "https://api.netatmo.com/oauth2/token") 
  return=$(jq -r '.error|tostring' <<<$AUTH)
  if [ $return != "null" ]; then
    echo "[ERROR]  Login failed ($return), try again! (Bad user/pass or CLIENT ID/SECRET)"
    exit 1 
  fi 
  echo $AUTH > .atmo_auth   
}

function refreshAuth
{
  AUTH=$(curl -s -d "grant_type=refresh_token&refresh_token=$REFRESH&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET" "https://api.netatmo.com/oauth2/token") 
  if [ $DEBUG -eq 1 ]; then 
    #DEBUG dump
    jq <<<$AUTH
  fi
  return=$(jq -r '.error|tostring' <<<$AUTH)
  if [ $return != "null" ]; then
    echo "[ERROR]  Refresh token failed ($return)"
    exit 1 
  fi 
  echo $AUTH > .atmo_auth   
}

function checkToken
{
  readToken
  EXPIRE=$(jq -r '.expires_in' <<<$AUTH) 
  if [ -f .atmo_auth ]; then
    tokenLife=$(( $(date +"%s") - $(stat -c %Y .atmo_auth) ))
    if [ $DEBUG -eq 1 ]; then 
      echo "[DEBUG]  TokenLife: $tokenLife Exp: $EXPIRE"
    fi
    if [ $tokenLife -ge $EXPIRE ]; then
      if [ $DEBUG -eq 1 ]; then 
	      echo "[DEBUG]  Access token time expired, refreshing token..."
      fi
      refreshAuth
      readToken
    fi
  fi
}

function readToken
{
  if [ ! -f .atmo_auth ]; then
    echo "[INFO]   No authorization file found, Netatmo login required:"
    loginAuth
  fi
  AUTH=$(cat .atmo_auth) 
  REFRESH=$(jq -r '.refresh_token|tostring' <<<$AUTH) 
  TOKEN=$(jq -r '.access_token|tostring' <<<$AUTH) 
  if [ $DEBUG -eq 1 ]; then 
    echo "[rT DEBUG]  $TOKEN $REFRESH"
  fi
}

function getHomeData
{
  checkToken
  HOME_DATA=$(curl -s -d "access_token=$TOKEN" https://app.netatmo.net/api/homesdata?app_type=app_magellan&gateway_types=["NAMain"])
  return=$(jq -r '.error.code' <<<$HOME_DATA)
  if [ $return != "null" ]; then
    if [ $return == "3" ]; then
      if [ $DEBUG -eq 1 ]; then
        echo "[DEBUG]  Access token expired, refreshing token..."
      fi
      refreshAuth
      getHomeData
    elif [ $return == "2" ]; then
      if [ $DEBUG -eq 1 ]; then
        echo "[DEBUG]  Invalid Access token, refreshing token..."
      fi
      refreshAuth
      getHomeData
    else
      message=$(jq -r '.error.message|tostring' <<<$HOME_DATA)
      echo "[ERROR]  Unable to get homesdata, error: $return ($message)"
      exit 1
    fi
  fi
}

function getData
{
  checkToken
  DATA=$(curl -s -d "access_token=$TOKEN&device_id=$STATION" "https://api.netatmo.com/api/getstationsdata") 
  return=$(jq -r '.error.code' <<<$DATA)
  if [ $return != "null" ]; then
    if [ $return == "3" ]; then
      if [ $DEBUG -eq 1 ]; then 
        echo "[DEBUG]  Access token expired, refreshing token..."
      fi
      refreshAuth
      getData
    elif [ $return == "2" ]; then
      if [ $DEBUG -eq 1 ]; then 
        echo "[DEBUG]  Invalid Access token, refreshing token..."
      fi
      refreshAuth
      getData
    else
      message=$(jq -r '.error.message|tostring' <<<$DATA)
      echo "[ERROR]  Unable to get data, error: $return ($message)"
      exit 1 
    fi
  fi 
}

#
# Get battery operated modules battery and last seen information
#
function getModuleStatus {
  seenFail=0
  #RF quality
  declare -A RF_Q
  RF_Q["Bad"]=86
  RF_Q["Avg"]=71
  RF_Q["Good"]=56

  ## Get modules device info
  if [ $PRINT -eq 1 ]; then 
	  printf "%2s| %-15s | %-7s |%-6s| %-5s | %-20s\n" " " "Module" "Battery" "Signal" "Age" "Last Seen"
	  printf "%19s-+-%7s-+-%4s-+-%5s-+%20s\n" "-----------------" "-------" "----" "-----" "-[$DATE]-"
  fi
  for ((i = 0; i < 20; i++)); do
      NAME=$(jq -r .body.devices[0].modules[$i].module_name <<<$DATA)
      if [ "$NAME" == "null" ]; then
	break
      fi
      BATT=$(jq -r .body.devices[0].modules[$i].battery_percent <<<$DATA)
      LS_T=$(jq -r .body.devices[0].modules[$i].last_seen <<<$DATA)
      LS=$(date -d "@${LS_T}" +"%x %X")
      
      # Calculate last seen age and treshold
      AGE=$((DATE_T - LS_T))   
      if [ $AGE -gt $TIME_OK ]; then
    	OK="!"
    	seenFail=1
      else 
    	OK=" "
      fi
      
      # Get RF signal quality index
      RF_val=$(jq -r .body.devices[0].modules[$i].rf_status <<<$DATA)
      # Locate signal level
      for rf_key in "${!RF_Q[@]}"; do
        if [ $RF_val -ge ${RF_Q[$rf_key]} ]; then
          local RF="$rf_key"
          break
        fi
      done  
      
      if [ $PRINT -eq 1 ]; then 
        printf "%-2s| %-15s | %-7s | %-4s | %-5s | %-20s\n" "$OK" "$NAME" "$BATT %" "$RF" "$AGE s" " $LS"
      elif [ $PRINT -eq 0 ] && [ "$OK" == "!" ]; then
        echo "[UNREACH] $NAME: Battery: $BATT %, Signal: $RF, Age: $AGE s, Last Seen: $LS"
      fi
  done
  if [ $PRINT -eq 1 ]; then 
    printf "%19s-+-%7s-+-%4s-+-%5s-+-%20s\n" "-----------------" "-------" "----" "-----" "----------------------"
  fi
  return $seenFail
}


##
## Start script
##
DATE=$(date "+%Y-%m-%d %H:%M:%S")
DATE_ISO8601=$(date --utc "+%Y-%m-%dT%H:%M:%SZ")
DATE_T=$(date "+%s")

## set CWD to script location
cd $(realpath $(dirname $0))
if [ $DEBUG -eq 1 ]; then
  echo "[DEBUG]  CWD is set to: $(pwd)"
fi

## Locate STATION ID from homesdata API 
## (seem to use netatmo.net still, homesdata api do not return anything on netatmo.com endpoint)
getHomeData
# Dump entire table (DEBUG)
#jq <<<$HOME_DATA

STATION=$(jq -r .body.homes[0].modules[0].id <<<$HOME_DATA)
if [ $DEBUG -eq 1 ]; then
  echo "[DEBUG]  STATION: $STATION"
fi
## Fetch measurement data
getData

if [ $DEVICE_STATUS -eq 1 ]; then
  getModuleStatus
  exit $?
fi


# Dump entire json table
if [ -n "$JSON_FILE" ]; then
  if [ $PRINT -eq 1 ]; then
    echo "[INFO]   Storing json data in $JSON_FILE"
  fi
  jq <<<$DATA > $JSON_FILE
fi

HOME_NAME=$(jq -r .body.devices[0].home_name <<<$DATA)

I_TEMP=$(jq .body.devices[0].dashboard_data.Temperature <<<$DATA)
I_HUMI=$(jq .body.devices[0].dashboard_data.Humidity <<<$DATA)
I_CO2=$(jq .body.devices[0].dashboard_data.CO2 <<<$DATA)

O_TEMP=$(jq .body.devices[0].modules[0].dashboard_data.Temperature <<<$DATA)
O_HUMI=$(jq .body.devices[0].modules[0].dashboard_data.Humidity <<<$DATA)
O_PRES=$(jq .body.devices[0].dashboard_data.Pressure <<<$DATA)


#
# Store data in CSV file
# 
# CSV file is named as netatmo body.devices[0].home_name
#

# Create file with header if missing
if ! [ -f "$HOME_NAME.csv" ]; then
  echo "Date,Indoor Temp,Indoor Humidity,Indoor CO2, Outdoor Temp,Outdoor Humidity, Pressure" > "$HOME_NAME.csv" 
fi
echo "$DATE_ISO8601,$I_TEMP,$I_HUMI,$I_CO2,$O_TEMP,$O_HUMI,$O_PRES" >> "$HOME_NAME.csv"


#### Print out
if [ $PRINT -eq 1 ]; then 
  echo "[INFO]   Values stored in $HOME_NAME.csv"
  echo
  echo "-------------------------------------------------------------------"
  printf " [%-22s                     %20s] \n" "${HOME_NAME}]" "[${DATE}"
  echo "-------------------------- Indoor ---------------------------------"
  printf " Temperature: %-5s°C |  Humidity: %-3s%% |  CO2: %s ppm \n" "$I_TEMP" "$I_HUMI" "$I_CO2"
  echo "-------------------------- Outdoor --------------------------------"
  printf " Temperature: %-5s°C |  Humidity: %-3s%% |  Pressure: %s mb \n" "$O_TEMP" "$O_HUMI" "$O_PRES" 
  echo "-------------------------------------------------------------------"
fi

exit 0

