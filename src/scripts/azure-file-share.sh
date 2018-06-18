#!/bin/bash

# License: https://github.com/elastic/azure-marketplace/blob/master/LICENSE.txt
#
# Martijn Laarman, Russ Cam (Elastic)
# Contributors
#

#########################
# HELP
#########################

export DEBIAN_FRONTEND=noninteractive

help()
{
    echo "This script creates a file share in a given azure storage account and mounts the share"
    echo "Parameters:"
}

# Custom logging with time so we can easily relate running times, also log to separate file so order is guaranteed.
# The Script extension output the stdout/err buffer in intervals with duplicates.
log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/arm-install.log
}

log "Begin execution of azure file share script extension on ${HOSTNAME}"
START_TIME=$SECONDS

#########################
# Preconditions
#########################

if [ "${UID}" -ne 0 ];
then
    log "Script executed without root permissions"
    echo "You must be root to run this program." >&2
    exit 3
fi

#########################
# Parameter handling
#########################

STORAGE_ENDPOINT_SUFFIX="core.windows.net"
STORAGE_ACCOUNT_NAME=""
STORAGE_ACCOUNT_KEY=""
STORAGE_QUOTA=5
SHARE_NAME="${HOSTNAME}"
DATA_BASE="/afs"

#Loop through options passed
while getopts :A:K:N:q:b:e:h optname; do
  log "Option $optname set"
  case $optname in
    A) #storage account name
      STORAGE_ACCOUNT_NAME="${OPTARG}"
      ;;
    K) #storage account key
      STORAGE_ACCOUNT_KEY="${OPTARG}"
      ;;
    N) #file share name
      SHARE_NAME="${OPTARG}"
      ;;
    e) #endpoint suffix
      STORAGE_ENDPOINT_SUFFIX="${OPTARG}"
      ;;
    q) #file share quota (in GB)
      STORAGE_QUOTA=${OPTARG}
      ;;
    b) #mount point
      DATA_BASE="${OPTARG}"
      ;;
    h) #show help
      help
      exit 2
      ;;
    \?) #unrecognized option - show help
      log \\n"Option -${BOLD}$OPTARG${NORM} ignored."
      ;;
  esac
done

#########################
# Parameter state changes
#########################

install_azure_cli()
{
  log "[install_azure_cli] installing azure cli 2.0 from apt"
  if [ $(dpkg-query -W -f='${Status}' azure-cli 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
    local AZ_REPO=$(lsb_release -cs)
    echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
      sudo tee /etc/apt/sources.list.d/azure-cli.list

    curl -L https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -

    (apt-get -yq install apt-transport-https || (sleep 15; apt-get -yq install apt-transport-https))
    apt-get update
    (apt-get -yq install azure-cli || (sleep 15; apt-get -yq install azure-cli))
    log "[install_azure_cli] installed azure cli 2.0"
  else
    log "[install_azure_cli] azure cli 2.0 already installed"
  fi
}

create_file_share()
{
  log "[create_file_share] create azure file share $SHARE_NAME with ${STORAGE_QUOTA}GB"
  local CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT_NAME;AccountKey=$STORAGE_ACCOUNT_KEY;EndpointSuffix=$STORAGE_ENDPOINT_SUFFIX"

  if [ $(az storage share exists --name "$SHARE_NAME" --connection-string "$CONNECTION_STRING" | grep -c "\"exists\": true") -eq 0 ]; then
    az storage share create --name "$SHARE_NAME" --quota $STORAGE_QUOTA --connection-string "$CONNECTION_STRING"
    log "[create_file_share] created azure file share $SHARE_NAME"
  else
    log "[create_file_share] azure file share $SHARE_NAME already exists"
  fi
}

mount_file_share()
{
  if [[ -d $DATA_BASE ]]; then
    log "[mount_file_share] mount $DATA_BASE already exists"
  else
    mkdir $DATA_BASE
    log "[mount_file_share] mounting azure file share $SHARE_NAME at $DATA_BASE"
    mount -t cifs //$STORAGE_ACCOUNT_NAME.file.$STORAGE_ENDPOINT_SUFFIX/$SHARE_NAME $DATA_BASE -o vers=3.0,username=$STORAGE_ACCOUNT_NAME,password=$STORAGE_ACCOUNT_KEY,dir_mode=0777,file_mode=0777
    log "[mount_file_share] mounted azure file share $SHARE_NAME at $DATA_BASE"

    log "[mount_file_share] add record to /etc/fstab for $SHARE_NAME"
    echo "//$STORAGE_ACCOUNT_NAME.file.$STORAGE_ENDPOINT_SUFFIX/$SHARE_NAME $DATA_BASE cifs vers=3.0,username=$STORAGE_ACCOUNT_NAME,password=$STORAGE_ACCOUNT_KEY,dir_mode=0777,file_mode=0777" >> /etc/fstab
  fi
}

install_azure_cli

create_file_share

mount_file_share
