#!/bin/bash

# License: https://github.com/elastic/azure-marketplace/blob/master/LICENSE.txt
#
# Russ Cam (Elastic)
#

export DEBIAN_FRONTEND=noninteractive

#########################
# HELP
#########################

help()
{
    echo "This script installs Java on Ubuntu using the openjdk-8-jdk apt package"
    echo ""
    echo "Options:"
    echo "   -h         this help message"
}

log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] \["install_java"\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] \["install_java"\] "$1" >> /var/log/arm-install.log
}

#########################
# Parameter handling
#########################

ES_VERSION=""

while getopts :v:h optname; do
    log "Option $optname set with value ${OPTARG}"
  case ${optname} in
    v) #elasticsearch version number
      ES_VERSION="${OPTARG}"
      ;;
    h)  #show help
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

install_java()
{
    log "installing java"
    (apt-get -yq install openjdk-8-jdk || (sleep 15; apt-get -yq install openjdk-8-jdk))
    command -v java >/dev/null 2>&1 || { log "java did not get installed" >&2; exit 50; }
    log "installed java"
}

log "updating apt-get"
(apt-get -y update || (sleep 15; apt-get -y update)) > /dev/null
log "updated apt-get"

# Only install Java if not bundled with Elasticsearch
if [[ -z "$ES_VERSION" || $(dpkg --compare-versions "$ES_VERSION" "lt" "7.0.0"; echo $?) -eq 0 ]]; then
  install_java
else
  log "not installing java, using JDK bundled with distribution"
fi