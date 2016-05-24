#!/bin/bash
set -e

PORT=8443

# Validate JQ is installed
command -v jq -q >/dev/null 2>&1 || { echo >&2 "json parser jq is required but not installed yet... aborting."; exit 1; }

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
  -m|--method=<method>          : Method to execute against <build|deploy>
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
    -t=*|--token=*)
      TOKEN="${i#*=}"
      shift;;
    -ot=*|--output-tag=*)
      OUTPUT_TAG="${i#*=}"
      shift;;
    -m=*|--method=*)
      METHOD="${i#*=}"
      shift;;
  esac
done

if [ "${METHOD}" != "build" ] && [ "${METHOD}" != "deployment" ]; then
  echo "Error: Invalid Action Type"
  exit 1
fi

if [ -z "${OUTPUT_TAG}" ]; then
    echo "Error: Output Tag Not Specified"
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
	CHALLENGE_RESPONSE=$(curl -s  -I --insecure -f  "https://${HOST}:8443/oauth/authorize?response_type=token&client_id=openshift-challenging-client" --user ${USER}:${PASSWORD} -H "X-CSRF-Token: 1")

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

function update_build() {

    # Application BuildConfig
    BUILD_CONFIG=$(curl -s -H "Authorization: Bearer ${TOKEN}" --insecure -f https://${HOST}:${PORT}/oapi/v1/namespaces/${NAMESPACE}/buildconfigs/${APP})

    # Extract Existing Tag
    UPDATED_OUTPUT_TAG=$(echo "$BUILD_CONFIG" | jq -r .spec.output.to.name | sed "s/:[^:]*$/:${OUTPUT_TAG}/")
    
    # Update the output tag
    UPDATED_BUILD_CONFIG=$(echo "$BUILD_CONFIG" | jq ".spec.output.to.name = \"$UPDATED_OUTPUT_TAG\"")
    
    # Update BuildConfig
    curl -s -X PUT -d "${UPDATED_BUILD_CONFIG}" -H "Authorization: Bearer ${TOKEN}" --insecure -f https://${HOST}:8443/oapi/v1/namespaces/${NAMESPACE}/buildconfigs/${APP} > /dev/null

    if [  $? -ne 0  ]; then
        echo "Error updating build configuration"
        exit 1
    fi

    echo
    echo "Application build has been updated!"
}

function update_deployment() {
   
    # Application DeploymentConfig
    DEPLOYMENT_CONFIG=$(curl -s -f -H "Authorization: Bearer ${TOKEN}" --insecure  https://${HOST}:${PORT}/oapi/v1/namespaces/${NAMESPACE}/deploymentconfigs/${APP})

    # Extract Existing Tag
    UPDATED_OUTPUT_TAG=$(echo ${DEPLOYMENT_CONFIG} | jq -r ".spec.triggers[] | select(.type ==\"ImageChange\") | .imageChangeParams.from.name" | sed "s/:[^:]*$/:${OUTPUT_TAG}/")
    
    # Update DeploymentConfig
    UPDATED_DEPLOYMENT_CONFIG=$(echo "${DEPLOYMENT_CONFIG}" | jq  ".spec.triggers |= map(if .type == \"ImageChange\" then .imageChangeParams.from.name = \"${UPDATED_OUTPUT_TAG}\" else . end)")
    
    # Update DeploymentConfig
    curl -s -X PUT -d "${UPDATED_DEPLOYMENT_CONFIG}" -H "Authorization: Bearer ${TOKEN}" --insecure -f https://${HOST}:8443/oapi/v1/namespaces/${NAMESPACE}/deploymentconfigs/${APP} > /dev/null

    if [  $? -ne 0  ]; then
        echo "Error updating deployment configuration"
        exit 1
    fi

    echo
    echo "Application deployment has been updated!"

}

update_$METHOD
