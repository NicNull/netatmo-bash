#!/bin/bash
## Netatmo bash script to get weather station data. 
## Bash script for getting data from netatmo API and handling OATH access and refresh tokens. 
## Handles new OATH method required after April 2024 API update.
##
## https://github.com/NicNull/netatmo-bash
##
## Requirements before even trying to start script:
## Get the CLIENT_ID/SECRET by login to dev.netatmo.com myApps/Create 
## 
## For login redirect URI a local listening socket is used for the OATH process.
## This requires script to be run on the same host as the webbrowser used for auth.
## It is also possible to skip auto capture and manually enter the return code copied from the response URI:
## http://127.0.0.1:1337/?code=<your code is here>
##

REDIR_URL="http://127.0.0.1:1337"
CLIENT_ID="########################"
CLIENT_SECRET="###################################"
PRINT=1
DEBUG=0

# Function to handle Ctrl-C (SIGINT)
cleanup() {
    echo -e "\r[WARN]   Aborted redirect URI snoop."
    trap - SIGINT
}

# Trap Ctrl-C and call the cleanup function
trap cleanup SIGINT

#
# URI redirect response
#
REPLY=$(cat <<EOF
HTTP/1.1 303 Found
Location: https://home.netatmo.com/
Content-Type: text/html
EOF
)

#
# Login only first time to get token credential file
#
function loginAuth
{
  echo "[INFO]   Go to this URL to get auth code:"
  echo "[ACTION] https://api.netatmo.com/oauth2/authorize?client_id=$CLIENT_ID&redirect_uri=${REDIR_URL}&scope=read_station" 
  echo
  echo "[LOGIN]  Listening for redirect URI at $REDIR_URL ..."
  echo "[INFO]   # Ctrl-C to abort and input code manually #"
  CODE=$(nc -q 5 -w 1 -l 1337 <<<$REPLY |head -n1 |grep -Po "code=\K[^ ]+")
  
  if [ -z "$CODE" ]; then
    read -p "[INPUT]  Enter code: " CODE 
  fi
  echo
  AUTH=$(curl -s -d "grant_type=authorization_code&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&code=$CODE&redirect_uri=${REDIR_URL}&scope=read_station" "https://api.netatmo.net/oauth2/token") 
  return=$(jq -r '.error|tostring' <<<$AUTH)
  if [ $return != "null" ]; then
    echo "[ERROR]  Login failed ($return), try again! (Bad user/pass or CLIENT ID/SECRET)"
    exit 1 
  fi 
  echo $AUTH > .atmo_auth   
}

function refreshAuth
{
  AUTH=$(curl -s -d "grant_type=refresh_token&refresh_token=$REFRESH&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET" "https://api.netatmo.net/oauth2/token") 
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
    echo "[DEBUG]  $TOKEN $REFRESH"
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
  DATA=$(curl -s -d "access_token=$TOKEN&device_id=$STATION" "https://api.netatmo.net/api/getstationsdata") 
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

##
## Start script
##

## set CWD to script location
cd $(realpath $(dirname $0))
if [ $DEBUG -eq 1 ]; then
  echo "[DEBUG]  CWD is set to: $(pwd)"
fi

## Locate STATION ID from homesdata API
getHomeData
# Dump entire table (DEBUG)
#jq <<<$HOME_DATA

STATION=$(jq -r .body.homes[0].modules[0].id <<<$HOME_DATA)

## Fetch measurement data
getData

# Dump entire table (DEBUG)
#jq <<<$DATA

HOME_NAME=$(jq -r .body.devices[0].home_name <<<$DATA)

I_TEMP=$(jq .body.devices[0].dashboard_data.Temperature <<<$DATA)
I_HUMI=$(jq .body.devices[0].dashboard_data.Humidity <<<$DATA)
I_CO2=$(jq .body.devices[0].dashboard_data.CO2 <<<$DATA)

O_TEMP=$(jq .body.devices[0].modules[0].dashboard_data.Temperature <<<$DATA)
O_HUMI=$(jq .body.devices[0].modules[0].dashboard_data.Humidity <<<$DATA)
O_PRES=$(jq .body.devices[0].dashboard_data.Pressure <<<$DATA)

DATE=$(date "+%Y-%m-%d %H:%M:%S")
DATE_ISO8601=$(date --utc "+%Y-%m-%dT%H:%M:%SZ")

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
  echo "--------------------------------------------------------------------------"
  echo -n "                              Indoor               [$DATE] -"
  echo -e "\r- [$HOME_NAME]"
  echo "--------------------------------------------------------------------------"
  echo " Temperature: $I_TEMP C | Humidity: $I_HUMI % | CO2: $I_CO2 ppm"
  echo "----------------------------- Outdoor ------------------------------------"
  echo " Temperature: $O_TEMP C | Humidity: $O_HUMI % | Pressure: $O_PRES mb" 
  echo "--------------------------------------------------------------------------"
fi

exit 0

