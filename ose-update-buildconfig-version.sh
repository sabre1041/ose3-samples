#!/bin/bash


#
# HOST
# USER
# PASSWORD
# PROJECT
# APP



usage() {
  echo "Usage $0 -h|--host=\"<host>\" -u|--user=\"<username>\" -p|--password=\"<password>\" -n|--namespace=\"<namespace>\" -a|--app=\"<app>\" -v|--version=\"<version>\""
}


# Check program dependencies

command -v jq -q >/dev/null 2>&1 || { echo >&2 "json parser jq is required but not installed yet... aborting."; exit 1; }


# Process Input

for i in "$@"
do
  case $i in
    -h=*|--host=*)
      HOST="${i#*=}"
      shift;;
    -u=*|--user=*)
      USER="${i#*=}"
      shift;;
    -p=*|--password=*)
      PASSWORD="${i#*=}"
      shift;;
    -n=*|--namespace=*)
      NAMESPACE="${i#*=}"
      shift;;
    -a=*|--app=*)
      APP="${i#*=}"
      shift;;
    -v=*|--version=*)
      VERSION="${i#*=}"
      shift;;
  esac
done

if [ -z $HOST ] || [ -z $USER ] || [ -z $PASSWORD ] || [ -z $NAMESPACE ] || [ -z $APP ]; then
  echo "Missing required args"
  usage
  exit 1
fi 


# Get auth token
CHALLENGE_RESPONSE=$(curl -s  -I --insecure -f  "https://${HOST}:8443/oauth/authorize?response_type=token&client_id=openshift-challenging-client" --user ${USER}:${PASSWORD} -H "X-CSRF-Token: 1")

if [ $? -ne 0 ]; then
    echo "Unauthorized Access Attempt"
    exit 1
fi

echo "Authenticated"

TOKEN=$(echo "$CHALLENGE_RESPONSE" | grep -oP "access_token=\K[^&]*")

if [ -z "$TOKEN" ]; then
    echo "Token is blank!"
    exit 1
fi


# Get build config for app
BUILD_CONFIG=$(curl -s -H "Authorization: Bearer ${TOKEN}" --insecure -f https://${HOST}:8443/osapi/v1beta3/namespaces/${NAMESPACE}/buildconfigs/${APP})

if [ -z "$BUILD_CONFIG" ]; then
    echo "Error locating build config"
    exit 1
fi

echo "Located build config"

# Determine current version
CURRENT_VERSION=$(echo "$BUILD_CONFIG" | jq -r '.spec.strategy.customStrategy.env[] as $cusenv | select($cusenv.name == "ARTIFACT_VERSION") | $cusenv.value | .')

if [ -z "$CURRENT_VERSION" ]; then
    echo "Unable to determine current version of artifact"
    exit 1
fi


# Update version of artifact
UPDATED_BUILD_CONFIG=$(echo "$BUILD_CONFIG" | sed "s/\"value\": \"$CURRENT_VERSION\"/\"value\": \"$VERSION\"/")



# Update buildconfig in OSE
curl -s -X PUT -d "${UPDATED_BUILD_CONFIG}" -H "Authorization: Bearer ${TOKEN}" --insecure -f https://${HOST}:8443/osapi/v1beta3/namespaces/${NAMESPACE}/buildconfigs/${APP} > /dev/null

if [  $? -ne 0  ]; then
    echo "Error updating build configuration"
    exit 1
fi

echo "Project version has been updated!"
