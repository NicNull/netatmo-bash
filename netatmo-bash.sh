#!/bin/bash
## Netatmo bash script  
## Bash script for getting data from netatmo API and handling OATH access and refresh tokens. 
## Handles new OATH method required after April 2024 API update.
##
## https://github.com/NicNull/netatmo-bash
##
## Requirements before even trying to start script:
## Get the CLIENT_ID/SECRET by login to dev.netatmo.com myApps/Create 
## Station MAC address is avialable in my.netatmo.com Settings/Manage Home/RoomName/MAC Address
## 
## For login redirect URI a public available web server running netatmo.php is required for the OATH process.
## An example netatmo.php file and nginx configuration is provided as well.
##
REDIR_URL="<your webserver URL>"
STATION="##:##:##:##:##:##"
CLIENT_ID="########################"
CLIENT_SECRET="###################################"
PRINT=1
DEBUG=1


#Login only first time to get token credential file
function loginAuth
{
  echo "Go to this URL to get auth code:"
  echo "https://api.netatmo.com/oauth2/authorize?client_id=$CLIENT_ID&redirect_uri=https://$REDIR_URL/netatmo.php&scope=read_station" 
  echo
  read -p "Enter code: " CODE 
  echo
  AUTH=$(curl -s -d "grant_type=authorization_code&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&code=$CODE&redirect_uri=https://$REDIR_URL/netatmo.php&scope=read_station" "https://api.netatmo.net/oauth2/token") 
  return=$(jq -r '.error|tostring' <<<$AUTH)
  if [ $return != "null" ]; then
    echo "Login failed ($return), try again! (Bad user/pass or CLIENT ID/SECRET)"
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
    echo "Refresh token failed ($return)"
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
      echo "DEBUG: TokenLife: $tokenLife Exp: $EXPIRE"
    fi
    if [ $tokenLife -ge $EXPIRE ]; then
      if [ $DEBUG -eq 1 ]; then 
	echo "Access token time expired, refreshing token..."
      fi
      refreshAuth
      readToken
    fi
  fi
}

function readToken
{
  if [ ! -f .atmo_auth ]; then
    echo "No authorization file found, Netatmo login required:"
    loginAuth
  fi
  AUTH=$(cat .atmo_auth) 
  REFRESH=$(jq -r '.refresh_token|tostring' <<<$AUTH) 
  TOKEN=$(jq -r '.access_token|tostring' <<<$AUTH) 
  if [ $DEBUG -eq 1 ]; then 
    echo "DEBUG: $TOKEN $REFRESH"
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
        echo "Access token expired, refreshing token..."
      fi
      refreshAuth
      getData
    elif [ $return == "2" ]; then
      if [ $DEBUG -eq 1 ]; then 
        echo "Invalid Access token, refreshing token..."
      fi
      refreshAuth
      getData
    else
      message=$(jq -r '.error.message|tostring' <<<$DATA)
      echo "Unable to get data, error: $return ($message)"
      exit 1 
    fi
  fi 
}

##
## Start script
##

getData

##Dump entire table (DEBUG)
#jq <<<$DATA

I_TEMP=$(jq .body.devices[0].dashboard_data.Temperature <<<$DATA)
I_HUMI=$(jq .body.devices[0].dashboard_data.Humidity <<<$DATA)
I_CO2=$(jq .body.devices[0].dashboard_data.CO2 <<<$DATA)

O_TEMP=$(jq .body.devices[0].modules[0].dashboard_data.Temperature <<<$DATA)
O_HUMI=$(jq .body.devices[0].modules[0].dashboard_data.Humidity <<<$DATA)
O_PRES=$(jq .body.devices[0].dashboard_data.Pressure <<<$DATA)


#### Print out
if [ $PRINT -eq 1 ]; then 
  echo "------------------------ Indoor ------------------------------------------"
  echo " Temperature: $I_TEMP C | Humidity: $I_HUMI % | CO2: $I_CO2 ppm"
  echo "------------------------ Outdoor -----------------------------------------"
  echo " Temperature: $O_TEMP C | Humidity: $O_HUMI % | Pressure: $O_PRES mb" 
  echo "--------------------------------------------------------------------------"
fi

exit 0

