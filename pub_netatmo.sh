#!/bin/bash
# Fetch access token without login to get public data for netatmo station based on GPS coordinates on netatmo weathermap.

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
# set -u # Using variables like TEMPERATURE conditionally, so disable for now
# Pipe commands return the exit status of the last command to exit non-zero.
set -o pipefail

## --- Configuration ---
# GPS Coordinates for scraping, enter intended target area.
CLIENT_LAT="00.000000000000"
CLIENT_LON="00.000000000000"
# Target Station ID to filter for
CLIENT_STATION_ID="00:00:00:00:00:00"
# Target file path for the filtered JSON output
OUTPUT_JSON_FILE="/tmp/temperatur.json"  # Adjust path as needed
OUTPUT_TEMP_FILE="/tmp/temp.txt"         # Adjust path as needed



# Using the same NE/SW point focuses the API on stations very close to this single point.
LAT_NE="$CLIENT_LAT"
LON_NE="$CLIENT_LON"
LAT_SW="$LAT_NE" # Same as NE Lat
LON_SW="$LON_NE" # Same as NE Lon

# Netatmo URLs
WEATHERMAP_URL="https://weathermap.netatmo.com/"
NETATMO_API_URL="https://api.netatmo.com/api/getpublicdata"
NETATMO_AUTH="https://auth.netatmo.com/weathermap/token"

# User-Agent to mimic a browser
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"

# --- Prerequisite Check ---
if ! command -v jq &> /dev/null
then
    echo "Error: 'jq' command not found. Please install jq (e.g., 'sudo apt install jq' or 'brew install jq')." >&2
    exit 1
fi
if ! command -v curl &> /dev/null
then
    echo "Error: 'curl' command not found. Please install curl." >&2
    exit 1
fi

# --- Scrape Access Token ---
echo "Scraping access token from ${NETATMO_AUTH}..."
ACCESS_TOKEN=$(curl -s ${NETATMO_AUTH} --compressed -H "User-Agent: ${USER_AGENT}" \
                    -H 'Accept: application/json, text/plain, */*' -H 'Accept-Language: en-US,en;q=0.5' \
                    -H 'Accept-Encoding: gzip, deflate, br, zstd' -H "Origin: ${WEATHERMAP_URL}" \
                    -H 'Connection: keep-alive' -H "Referer: ${WEATHERMAP_URL}" \
                    -H 'Sec-Fetch-Dest: empty' -H 'Sec-Fetch-Mode: cors' -H 'Sec-Fetch-Site: same-site' | \
               jq -r '.body')

if [[ -z "${ACCESS_TOKEN}" ]]; then
  echo "Error: Failed to scrape access token from ${NETATMO_AUTH}" >&2
  exit 1
fi
echo "Access token scraped successfully."

# --- Make API Call ---
echo "Fetching public data from Netatmo API..."
QUERY_PARAMS="lat_ne=${LAT_NE}&lon_ne=${LON_NE}&lat_sw=${LAT_SW}&lon_sw=${LON_SW}&filter=false"
RAW_API_DATA=$(curl --fail -s -L \
     -H "User-Agent: ${USER_AGENT}" \
     -H "Authorization: Bearer ${ACCESS_TOKEN}" \
     -H "accept: application/json" \
     "${NETATMO_API_URL}?${QUERY_PARAMS}")

if [[ -z "$RAW_API_DATA" ]]; then
    echo "Error: API call returned empty data." >&2
    exit 1
fi

if ! echo "$RAW_API_DATA" | jq -e . >/dev/null 2>&1; then
    echo "Error: API response is not valid JSON." >&2
    # echo "Invalid JSON received: $RAW_API_DATA" >&2 # Uncomment for debugging
    exit 1
fi
if [[ "[]" = "$(jq -r '.body' <<<$RAW_API_DATA)" ]]; then
    echo "Error: API response did not return any station data, check GPS coordinates using $WEATHERMAP_URL" >&2
    echo $(jq '.body' <<<$RAW_API_DATA)
    exit 1
fi
echo "API data received successfully."
    
# --- Filter API Data for Target Station ---
echo "Filtering data for station ID: ${CLIENT_STATION_ID}..."
# Pipe RAW_API_DATA to jq instead of using <<<
FILTERED_JSON=$(echo "$RAW_API_DATA" | jq -c --arg stationId "$CLIENT_STATION_ID" \
    ' .body = [ .body[] | select(._id == $stationId) ] ')

if [[ "[]" = "$(jq -r '.body' <<<$FILTERED_JSON)" ]]; then
    echo "Error: Failed to find Station $CLIENT_STATION_ID in response:" >&2
    jq '.body[]._id' <<<$RAW_API_DATA
    exit 1
fi
if ! echo "$FILTERED_JSON" | jq -e . >/dev/null 2>&1; then
    echo "Error: Result is not valid JSON." >&2
    exit 1
fi
echo "Data filtered successfully."

# --- Extract Outdoor Temperature ---
echo "Extracting outdoor temperature for station ID: ${CLIENT_STATION_ID}..."
# The multi-line jq script is enclosed in single quotes '.
TEMPERATURE=$(echo "$FILTERED_JSON" | jq -e -r --arg stationId "$CLIENT_STATION_ID" '
    # Assign the first station object (or null) to $station
    .body[0] as $station |
    # Proceed only if a station object exists
    if $station then
      # Find the module ID corresponding to "NAModule1"
      # ($station.module_types | to_entries | map(select(.value == "NAModule1").key)[0]) as $module_id | # Alternative way to find module_id
      ($station.module_types | to_entries[] | select(.value == "NAModule1") | .key) as $module_id |
      # Proceed only if the outdoor module ID was found
      if $module_id then
        # Get the measures for this module
        $station.measures[$module_id] as $measure |
        # Find the index of "temperature" in the type array
        ($measure.type | index("temperature")) as $idx |
        # Find the latest timestamp key in the "res" object
        ($measure.res | keys | map(tonumber) | max | tostring) as $ts |
        # Check if index, timestamp, and the data array exist and are valid
        if $idx != null and $ts != null and (($measure.res[$ts]? | length // -1) > $idx) then
          # Extract the temperature value using the index
          $measure.res[$ts][$idx]
        else
          # Could not find temperature data for this module
          empty
        end
      else
        # NAModule1 type not found for this station
        empty
      end
    else
      # Target station ID was not found in the body array
      empty
    end
    ') # End of jq script and command substitution

# Check jq's exit status ($?) to see if temperature was found
JQ_EXIT_STATUS=$?

if [[ $JQ_EXIT_STATUS -eq 0 ]]; then
  true
  echo "Temperature extracted successfully: ${TEMPERATURE}"
elif [[ $JQ_EXIT_STATUS -eq 1 ]]; then # jq -e returns 1 for null/false/empty output
  echo "Warning: Could not find outdoor temperature ('NAModule1' with 'temperature') for station ${CLIENT_STATION_ID} in the filtered data." >&2
  TEMPERATURE="null" # Assign a default value indicating not found
else # Any other non-zero status is a jq processing error
  echo "Error: jq failed unexpectedly while extracting temperature (exit status: $JQ_EXIT_STATUS)." >&2
  TEMPERATURE="error"
  # exit 1 # Optional: Make this a fatal error
fi

# --- Save Filtered JSON to File ---
echo "Saving filtered JSON to ${OUTPUT_JSON_FILE}..."
if printf "%s" "$FILTERED_JSON" > "$OUTPUT_JSON_FILE"; then
  true
  #echo "Filtered JSON saved successfully." >&2
else
  PRINTF_STATUS=$?
  echo "Error: Failed to write filtered JSON to ${OUTPUT_JSON_FILE} (Status: ${PRINTF_STATUS})" >&2
  # exit 1 # Optional: Make this a fatal error
fi

# --- Optional: Use the TEMPERATURE variable ---
if [[ "$TEMPERATURE" != "null" && "$TEMPERATURE" != "error" ]]; then
   echo "Logging temperature: $TEMPERATURE"
  if printf "%s" "$TEMPERATURE" > "$OUTPUT_TEMP_FILE"; then
    true
    #echo "TEMPERATURE saved successfully." >&2
  else
    PRINTF_STATUS=$?
    echo "Error: Failed to write filtered JSON to ${OUTPUT_JSON_FILE} (Status: ${PRINTF_STATUS})" >&2
    # exit 1 # Optional: Make this a fatal error
  fi
fi

echo "Script finished."
exit 0
