#!/bin/bash

# The MIT License (MIT)
#
# Portions Copyright (c) 2015 Microsoft Azure
# Portions Copyright (c) 2015 Elastic, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Trent Swanson (Full Scale 180 Inc)
# Martijn Laarman (Elastic)
# Russ Cam (Elastic)

#########################
# HELP
#########################

help()
{
    echo "This script bootstraps an Elasticsearch cluster on a data node"
    echo "Parameters:"
    echo "-n elasticsearch cluster name"
    echo "-v elasticsearch version 2.3.3"
    echo "-p hostname prefix of nodes for unicast discovery"

    echo "-d cluster uses dedicated masters"
    echo "-Z <number of nodes> hint to the install script how many data nodes we are provisioning"

    echo "-A admin password"
    echo "-R read password"
    echo "-K kibana user password"
    echo "-S kibana server password"

    echo "-l install plugins"
    echo "-L <plugin;plugin> install additional plugins"

    echo "-U api url"
    echo "-I marketing id"
    echo "-c company name"
    echo "-e email address"
    echo "-f first name"
    echo "-m last name"
    echo "-t job title"
    echo "-s cluster setup"
    echo "-o country"

    echo "-j install azure cloud plugin for snapshot and restore"
    echo "-a set the default storage account for azure cloud plugin"
    echo "-k set the key for the default storage account for azure cloud plugin"

    echo "-h view this help content"
}

log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/arm-install.log
}

log "Begin execution of Data Node Install script extension"

#########################
# Paramater handling
#########################

CLUSTER_NAME="elasticsearch"
NAMESPACE_PREFIX=""
ES_VERSION="2.0.0"
INSTALL_PLUGINS=0
INSTALL_ADDITIONAL_PLUGINS=""
INSTALL_AZURECLOUD_PLUGIN=0
STORAGE_ACCOUNT=""
STORAGE_KEY=""
CLUSTER_USES_DEDICATED_MASTERS=0
DATANODE_COUNT=0
DATA_ONLY_NODE=0

USER_ADMIN_PWD="changeME"
USER_READ_PWD="changeME"
USER_KIBANA4_PWD="changeME"
USER_KIBANA4_SERVER_PWD="changeME"

API_URL=""
MARKETING_ID=""
COMPANY_NAME=""
EMAIL=""
FIRST_NAME=""
LAST_NAME=""
JOB_TITLE=""
CLUSTER_SETUP=""
COUNTRY=""
INSTALL_SWITCHES=""

#Loop through options passed
while getopts :n:v:A:R:K:S:Z:p:U:I:c:e:f:m:t:s:o:a:k:L:xyzldjh optname; do
  log "Option $optname set"
  case $optname in
    n) #set cluster name
      CLUSTER_NAME=${OPTARG}
      ;;
    v) #elasticsearch version number
      ES_VERSION=${OPTARG}
      ;;
    A) #shield admin pwd
      USER_ADMIN_PWD=${OPTARG}
      ;;
    R) #shield readonly pwd
      USER_READ_PWD=${OPTARG}
      ;;
    K) #shield kibana user pwd
      USER_KIBANA4_PWD=${OPTARG}
      ;;
    S) #shield kibana server pwd
      USER_KIBANA4_SERVER_PWD=${OPTARG}
      ;;
    Z) #number of data nodes hints (used to calculate minimum master nodes)
      DATANODE_COUNT=${OPTARG}
      ;;
    l) #install plugins
      INSTALL_PLUGINS=1
      ;;
    j) #install azure cloud plugin
      INSTALL_AZURECLOUD_PLUGIN=1
      ;;
    L) #install additional plugins
      INSTALL_ADDITIONAL_PLUGINS="${OPTARG}"
      ;;
    a) #azure storage account for azure cloud plugin
      STORAGE_ACCOUNT=${OPTARG}
      ;;
    k) #azure storage account key for azure cloud plugin
      STORAGE_KEY=${OPTARG}
      ;;
    d) #cluster is using dedicated master nodes
      CLUSTER_USES_DEDICATED_MASTERS=1
      ;;
    x) #master node
      log "master node argument will be ignored"
      ;;
    y) #client node
      log "client node argument will be ignored"
      ;;
    z) #data node
      DATA_ONLY_NODE=1
      ;;
    p) #namespace prefix for nodes
      NAMESPACE_PREFIX="${OPTARG}"
      ;;
    U) #set API url
      API_URL=${OPTARG}
      ;;
    I) #set marketing id
      MARKETING_ID=${OPTARG}
      ;;
    c) #set company name
      COMPANY_NAME=${OPTARG}
      ;;
    e) #set email
      EMAIL=${OPTARG}
      ;;
    f) #set first name
      FIRST_NAME=${OPTARG}
      ;;
    m) #set last name
      LAST_NAME=${OPTARG}
      ;;
    t) #set job title
      JOB_TITLE=${OPTARG}
      ;;
    o) #set country
      COUNTRY=${OPTARG}
      ;;
    s) #set cluster setup
      CLUSTER_SETUP=${OPTARG}
      ;;
    h) #show help
      help
      exit 2
      ;;
    \?) #unrecognized option - show help
      echo -e \\n"Option -${BOLD}$OPTARG${NORM} not allowed."
      help
      exit 2
      ;;
  esac
done

if [ $CLUSTER_USES_DEDICATED_MASTERS -eq 1 ]; then
  INSTALL_SWITCHES="$INSTALL_SWITCHES -d"
fi

if [ $DATA_ONLY_NODE -eq 1 ]; then
  INSTALL_SWITCHES="$INSTALL_SWITCHES -z"
fi

if [ $INSTALL_AZURECLOUD_PLUGIN -eq 1 ]; then
  INSTALL_SWITCHES="$INSTALL_SWITCHES -j"
fi

if [ $INSTALL_PLUGINS -eq 1 ]; then
  INSTALL_SWITCHES="$INSTALL_SWITCHES -l"
fi

if [[ ! -z "${INSTALL_ADDITIONAL_PLUGINS// }" ]]; then
  INSTALL_SWITCHES="$INSTALL_SWITCHES -L $INSTALL_ADDITIONAL_PLUGINS"
fi

# install elasticsearch
bash elasticsearch-ubuntu-install.sh -n "$CLUSTER_NAME" -v "$ES_VERSION" -A "$USER_ADMIN_PWD" -R "$USER_READ_PWD" -K "$USER_KIBANA4_PWD" -S "$USER_KIBANA4_SERVER_PWD" -Z "$DATANODE_COUNT" -p "$NAMESPACE_PREFIX" -a "$STORAGE_ACCOUNT" -k "$STORAGE_KEY" $INSTALL_SWITCHES
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  log "installing Elasticsearch returned exit code $EXIT_CODE"
  exit $EXIT_CODE
fi

bash user-information.sh -U "$API_URL" -I "$MARKETING_ID" -c "$COMPANY_NAME" -e "$EMAIL" -f "$FIRST_NAME" -l "$LAST_NAME" -t "$JOB_TITLE" -s "$CLUSTER_SETUP" -o "$COUNTRY"
EXIT_CODE=$?
log "End execution of Data Node Install script extension"
exit $EXIT_CODE
