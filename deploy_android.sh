#!/bin/bash

function check_env() {
  # Safety checks
  if [ -z "$PLAYSTORE_KEY" ]; then
    echo "PLAYSTORE_KEY variable not supplied. Exiting."
    exit 1
  fi
  if [ -z "$AAB_PATH" ]; then
    echo "AAB_PATH variable not supplied. Exiting."
    exit 1
  fi
  if [ -z "$KEYSTORE_PATH" ]; then
    echo "KEYSTORE_PATH variable not supplied. Exiting."
    exit 1
  fi
  if [ -z "$KEYSTORE_ALIAS" ]; then
    echo "KEYSTORE_ALIAS variable not supplied. Exiting."
    exit 1
  fi
  if [ -z "$KEYSTORE_PASS" ]; then
    echo "KEYSTORE_PASS variable not supplied. Exiting."
    exit 1
  fi
  if [ -z "$KEYSTORE_KEY_PASS" ]; then
    echo "KEYSTORE_KEY_PASS variable not supplied. Exiting."
    exit 1
  fi
  if [ -z "$PLAYSTORE_TRACK" ]; then
    echo "PLAYSTORE_TRACK variable not supplied. Exiting."
    exit 1
  fi
  if [ -z "$DRAFT" ]; then
    echo "DRAFT variable not supplied. Exiting."
    exit 1
  fi

  AUTH_TOKEN=$(jq -r '.private_key' $PLAYSTORE_KEY)
  AUTH_ISS=$(jq -r '.client_email' $PLAYSTORE_KEY)
  AUTH_AUD=$(jq -r '.token_uri' $PLAYSTORE_KEY)

  if [ -z "$AUTH_TOKEN" ] || [ -z "$AUTH_ISS" ] || [ -z "$AUTH_AUD" ]; then
    echo "PLAYSTORE_SERVICE_KEY not as expected. Exiting."
    exit 1
  fi

  if [ $DRAFT == true ]; then
    STATUS="draft"
  else
    STATUS="completed"
  fi
}

function get_app_info() {
  # Calculate app information
  AAPT=$(find $ANDROID_HOME -name "aapt" | sort -r | head -1)
  APKS_PATH="/tmp/workspace/aab/app.apks"
  bundletool build-apks --bundle=$AAB_PATH --output=$APKS_PATH --mode=universal \
    --ks=$KEYSTORE_PATH --ks-pass=pass:$KEYSTORE_PASS --ks-key-alias=$KEYSTORE_ALIAS --key-pass=pass:$KEYSTORE_KEY_PASS
  unzip $APKS_PATH -d /tmp/workspace/aab/unzipped
  APK_PATH="/tmp/workspace/aab/unzipped/universal.apk"
  PACKAGE_NAME=$($AAPT dump badging $APK_PATH | grep package | awk '{print $2}' | sed s/name=//g | sed s/\'//g)
  VERSION_CODE=$($AAPT dump badging $APK_PATH | grep versionCode | awk '{print $3}' | sed s/versionCode=//g | sed s/\'//g)
  rm -rf /tmp/workspace/aab

  if [ -z "$PACKAGE_NAME" ]; then
    echo "PACKAGE_NAME not determined from apk. Exiting."
    exit 1
  fi
  if [ -z "$VERSION_CODE" ]; then
    echo "VERSION_CODE not determined from apk. Exiting."
    exit 1
  fi

  echo "AAB_PATH: $AAB_PATH"
  echo "BUILD_NO: $ANDROID_CODE"
  echo "PACKAGE_NAME: $PACKAGE_NAME"
  echo "VERSION_CODE: $VERSION_CODE"
  echo "PLAYSTORE_TRACK: $PLAYSTORE_TRACK"
  echo "STATUS: $STATUS"
}

function build_app() {
  cd ${ANDROID_WALLET_REPO}
  ./gradlew :app:bundleRelease
  bundle=${ANDROID_WALLET_REPO}/app/build/outputs/bundle/release/app-release.aab
  echo "Signing bundle..."
  jarsigner -keystore ${KEYSTORE_PATH} -storepass ${KEYSTORE_PASS} -keypass ${KEYSTORE_KEY_PASS} "${bundle}" "${KEYSTORE_ALIAS}"
  cd ${SCRIPT_DIR}
}

function jwt_claims() {
  cat <<EOF
{
  "iss": "$AUTH_ISS",
  "scope": "https://www.googleapis.com/auth/androidpublisher",
  "aud": "$AUTH_AUD",
  "exp": $(($(date +%s) + 300)),
  "iat": $(date +%s)
}
EOF
}

function get_access_token() {
  # Get access token
  echo "Getting access token..."

  JWT_HEADER=$(echo -n '{"alg":"RS256","typ":"JWT"}' | openssl base64 -e)
  JWT_CLAIMS=$(echo -n "$(jwt_claims)" | openssl base64 -e)
  JWT_PART_1=$(echo -n "$JWT_HEADER.$JWT_CLAIMS" | tr -d '\n' | tr -d '=' | tr '/+' '_-')
  JWT_SIGNING=$(echo -n "$JWT_PART_1" | openssl dgst -binary -sha256 -sign <(printf '%s\n' "$AUTH_TOKEN") | openssl base64 -e)
  JWT_PART_2=$(echo -n "$JWT_SIGNING" | tr -d '\n' | tr -d '=' | tr '/+' '_-')

  HTTP_RESPONSE_TOKEN=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
    --header "Content-type: application/x-www-form-urlencoded" \
    --request POST \
    --data "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=$JWT_PART_1.$JWT_PART_2" \
    "$AUTH_AUD")
  HTTP_BODY_TOKEN=$(echo $HTTP_RESPONSE_TOKEN | sed -e 's/HTTPSTATUS\:.*//g')
  HTTP_STATUS_TOKEN=$(echo $HTTP_RESPONSE_TOKEN | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

  if [ $HTTP_STATUS_TOKEN != 200 ]; then
    echo -e "Create access token failed"
    echo "Status: $HTTP_STATUS_TOKEN"
    echo "Body: $HTTP_BODY_TOKEN"
    echo "Exiting"
    exit 1
  fi
  echo $HTTP_BODY_TOKEN | jq
  ACCESS_TOKEN=$(echo $HTTP_BODY_TOKEN | jq -r '.access_token')
}

post_data_create_edit() {
  EXPIRY=$(($(date +%s) + 120))
  cat <<EOF
{
  "id": "circleci-$ANDROID_CODE",
  "expiryTimeSeconds": "$EXPIRY"
}
EOF
}

function create_edit() {
  # Create new edit
  echo "Creating new edit for ${PACKAGE_NAME}"

  HTTP_RESPONSE_CREATE_EDIT=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
    --header "Authorization: Bearer $ACCESS_TOKEN" \
    --header "Content-Type: application/json" \
    --request POST \
    --data "$(post_data_create_edit)" \
    https://www.googleapis.com/androidpublisher/v3/applications/$PACKAGE_NAME/edits)
  HTTP_BODY_CREATE_EDIT=$(echo $HTTP_RESPONSE_CREATE_EDIT | sed -e 's/HTTPSTATUS\:.*//g')
  HTTP_STATUS_CREATE_EDIT=$(echo $HTTP_RESPONSE_CREATE_EDIT | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

  if [ $HTTP_STATUS_CREATE_EDIT != 200 ]; then
    echo -e "Create edit failed"
    echo "Status: $HTTP_STATUS_CREATE_EDIT"
    echo "Body: $HTTP_BODY_CREATE_EDIT"
    echo "Exiting"
    exit 1
  fi

  #debug
  echo $($HTTP_BODY_CREATE_EDIT | jq)
  EDIT_ID=$(echo $HTTP_BODY_CREATE_EDIT | jq -r '.id')

}

set -ea
SCRIPT_DIR=$(pwd)
# Main deployment script for new Tari releases
DATE=$(date +%Y-%m-%d)
source .env

check_env
#get_app_info
#build_app
get_access_token
create_edit


function later() {



  # Upload aab
  echo "Uploading aab..."

  HTTP_RESPONSE_UPLOAD_AAB=$(curl --write-out "HTTPSTATUS:%{http_code}" \
    --header "Authorization: Bearer $ACCESS_TOKEN" \
    --header "Content-Type: application/octet-stream" \
    --progress-bar \
    --request POST \
    --upload-file $AAB_PATH \
    https://www.googleapis.com/upload/androidpublisher/v3/applications/$PACKAGE_NAME/edits/$EDIT_ID/bundles?uploadType=media)
  HTTP_BODY_UPLOAD_AAB=$(echo $HTTP_RESPONSE_UPLOAD_AAB | sed -e 's/HTTPSTATUS\:.*//g')
  HTTP_STATUS_UPLOAD_AAB=$(echo $HTTP_RESPONSE_UPLOAD_AAB | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

  if [ $HTTP_STATUS_UPLOAD_AAB != 200 ]; then
    echo -e "Upload aab failed"
    echo "Status: $HTTP_STATUS_UPLOAD_AAB"
    echo "Body: $HTTP_BODY_UPLOAD_AAB"
    echo "Exiting"
    exit 1
  fi

  # Assign edit to track
  echo "Assigning edit to track..."

  post_data_assign_track() {
    cat <<EOF
{
  "track": "$PLAYSTORE_TRACK",
  "releases": [
    {
      "versionCodes": [
        $VERSION_CODE
      ],
      "status": "$STATUS"
    }
  ]
}
EOF
  }

  HTTP_RESPONSE_ASSIGN_TRACK=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
    --header "Authorization: Bearer $ACCESS_TOKEN" \
    --header "Content-Type: application/json" \
    --request PUT \
    --data "$(post_data_assign_track)" \
    https://www.googleapis.com/androidpublisher/v3/applications/$PACKAGE_NAME/edits/$EDIT_ID/tracks/$PLAYSTORE_TRACK)
  HTTP_BODY_ASSIGN_TRACK=$(echo $HTTP_RESPONSE_ASSIGN_TRACK | sed -e 's/HTTPSTATUS\:.*//g')
  HTTP_STATUS_ASSIGN_TRACK=$(echo $HTTP_RESPONSE_ASSIGN_TRACK | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

  if [ $HTTP_STATUS_ASSIGN_TRACK != 200 ]; then
    echo -e "Assign track failed"
    echo "Status: $HTTP_STATUS_ASSIGN_TRACK"
    echo "Body: $HTTP_BODY_ASSIGN_TRACK"
    echo "Exiting"
    exit 1
  fi

  # Commit edit
  echo "Committing edit..."

  HTTP_RESPONSE_COMMIT=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
    --header "Authorization: Bearer $ACCESS_TOKEN" \
    --request POST \
    https://www.googleapis.com/androidpublisher/v3/applications/$PACKAGE_NAME/edits/$EDIT_ID:commit)
  HTTP_BODY_COMMIT=$(echo $HTTP_RESPONSE_COMMIT | sed -e 's/HTTPSTATUS\:.*//g')
  HTTP_STATUS_COMMIT=$(echo $HTTP_RESPONSE_COMMIT | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

  if [ $HTTP_STATUS_COMMIT != 200 ]; then
    echo -e "Commit edit failed"
    echo "Status: $HTTP_STATUS_COMMIT"
    echo "Body: $HTTP_BODY_COMMIT"
    echo "Exiting"
    exit 1
  fi
}

echo "Success"
