#!/bin/bash

# Script to perform push/pull docker operations against an OpenShift docker registry

set -e

EMAIL="jenkins@openshift.com"
DIRECTORY=$(pwd)

ORIG_HOME=$HOME

trap end_trap EXIT

function end_trap() {
  HOME=$ORIG_HOME
}

usage() {
  echo "Usage $0 -h|--host=\"<host>\" -u|--users=\"<user>\" -n|--namespace=\"<namespace>\" -a|--app=\"<app>\" -t|--token=\"<token>\" -o|--operation=\"<operation>\" -s|--sudo=\"<sudo>\""
}

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
    -n=*|--namespace=*)
      NAMESPACE="${i#*=}"
      shift;;
    -a=*|--app=*)
      APP="${i#*=}"
      shift;;
    -t=*|--token=*)
      TOKEN="${i#*=}"
      shift;;
    -o=*|--operation=*)
      OPERATION="${i#*=}"
      shift;;
    -s=*|--sudo=*)
      SUDO="sudo"
      shift;;
  esac
done


if [ -z $HOST ] || [ -z $TOKEN ] || [ -z $APP ] || [ -z $USER ] || [ -z $NAMESPACE ] || [ -z $OPERATION ]; then
  echo "Missing required arguments!"
  usage
  exit 1
fi


# Validate Docker Operation
if [ $OPERATION != "push" ] && [ $OPERATION != "pull" ]; then
  echo "Operation must be configured as 'push' or 'pull'" 
  exit 1
fi


${SUDO} docker login -u="${USER}" -e=${EMAIL} -p="${TOKEN}" ${HOST}

${SUDO} docker ${OPERATION} "${HOST}/${NAMESPACE}/${APP}"

${SUDO} docker logout ${HOST}
