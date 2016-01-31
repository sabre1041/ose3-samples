#!/bin/bash


PORT=8443
OUTPUT_TAG="default"


usage() {
  echo "
  Usage: $0 [options]

  Options:
  -h|--host=<host>              : OpenShift Master
  -p|--port=<port>              : OpenShift Master port (Default: 8443)
  -t|--token=<token>            : OAuth Token to authenticate as
  -u|--user=<username>          : Username to authenticate as (Instead of Token)
  -w|--password=<password>      : Password to authenticate as (Instead of Token)
  -n|--namespace=<namespace>    : OpenShift Project
  -a|--app=<app>                : OpenShift Application
  -g|--new-tag=<tag>            : Tag to apply to the output image (Default: latest)
  -s|--source=<source>          : URL of the packaged application to retrieve from a remote source
  "
}




# Process Input

for i in "$@"
do
  case $i in
    -h=*|--host=*)
      HOST="${i#*=}"
      shift;;
    -p=*|--port=*)
      PORT="${i#*=}"
      shift;;
    -u=*|--user=*)
      USER="${i#*=}"
      shift;;
    -w=*|--password=*)
      PASSWORD="${i#*=}"
      shift;;
    -n=*|--namespace=*)
      NAMESPACE="${i#*=}"
      shift;;
    -a=*|--app=*)
      APP="${i#*=}"
      shift;;
    -s=*|--source=*)
      SOURCE="${i#*=}"
      shift;;
    -t=*|--token=*)
      TOKEN="${i#*=}"
      shift;;
    -g=*|--new-tag=*)
      OUTPUT_TAG="${i#*=}"
      shift;;
  esac
done

if [ -z $HOST ] || [ -z $NAMESPACE ] || [ -z $APP ] || [ -z $SOURCE ]; then
  echo "Missing required arguments!"
  usage
  exit 1
fi 

if [ -z $PASSWORD ] && [ -z $TOKEN ]; then
	echo "Token or Password must be provided"
	usage
	exit 1
fi

# Get token if not present
if [ -z $TOKEN ]; then
	
	# Validate user and password are present
	if [ -z $PASSWORD ] && [ -z $USER ]; then
		echo "Username and Password must be provided"
		usage
		exit 1
	fi

	# Get auth token
	CHALLENGE_RESPONSE=$(curl -s  -I --insecure -f  "https://${HOST}:${PORT}/oauth/authorize?response_type=token&client_id=openshift-challenging-client" --user ${USER}:${PASSWORD} -H "X-CSRF-Token: 1")

	if [ $? -ne 0 ]; then
	    echo "Error: Unauthorized Access Attempt"
	    exit 1
	fi


	TOKEN=$(echo "$CHALLENGE_RESPONSE" | grep -oP "access_token=\K[^&]*")

	if [ -z "$TOKEN" ]; then
    	echo "Token is blank!"
    	exit 1
	fi
fi

# Get build config for app
BUILD_CONFIG=$(curl -s -H "Authorization: Bearer ${TOKEN}" --insecure -f https://${HOST}:${PORT}/oapi/v1/namespaces/${NAMESPACE}/buildconfigs/${APP})

# Check the build configuration response code
BUILD_CONFIG_RESPONSE=$?
if [  $BUILD_CONFIG_RESPONSE -ne 0  ]; then
    echo "Error retrieving Build Configuration. curl error: $BUILD_CONFIG_RESPONSE"
    exit 1
fi

# Check to see if the build configuration is empty
if [ -z "$BUILD_CONFIG" ]; then
    echo "Error locating build config"
    exit 1
fi

# Update version of artifact
UPDATED_BUILD_CONFIG=$(echo "$BUILD_CONFIG" | jq ".spec.strategy.sourceStrategy.env |= map(if .name == \"SRC_APP_URL\" then . + {\"value\":\"$SOURCE\"} else . end)")

# Extract Existing Tag
UPDATED_OUTPUT_TAG=$(echo "$UPDATED_BUILD_CONFIG" | jq -r .spec.output.to.name | sed "s/:[^:]*$/:${OUTPUT_TAG}/")

# Update the output tag
UPDATED_BUILD_CONFIG=$(echo "$UPDATED_BUILD_CONFIG" | jq ".spec.output.to.name = \"$UPDATED_OUTPUT_TAG\"")

# Update buildconfig in OSE
curl -s -X PUT -d "${UPDATED_BUILD_CONFIG}" -H "Authorization: Bearer ${TOKEN}" --insecure -f https://${HOST}:8443/oapi/v1/namespaces/${NAMESPACE}/buildconfigs/${APP} > /dev/null

if [  $? -ne 0  ]; then
    echo "Error updating build configuration"
    exit 1
fi

echo
echo "Application source has been updated!"
