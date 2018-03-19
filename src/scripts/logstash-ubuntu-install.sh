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
    echo "This script installs logstash on a dedicated VM in the elasticsearch ARM template cluster"
    echo "Parameters:"
    # TODO: Add parameters here

    echo "-h view this help content"
}

# Custom logging with time so we can easily relate running times, also log to separate file so order is guaranteed.
# The Script extension output the stdout/err buffer in intervals with duplicates.
log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/arm-install.log
}

log "Begin execution of Logstash script extension on ${HOSTNAME}"
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

if service --status-all | grep -Fq 'logstash'; then
  log "Logstash already installed."
  exit 0
fi

#########################
# Parameter handling
#########################

#Script Parameters
LOGSTASH_VERSION="6.2.1"
ELASTICSEARCH_URL="http://10.0.0.4:9200"
INSTALL_XPACK=0
INSTALL_ADDITIONAL_PLUGINS=""
USER_LOGSTASH_PWD="changeme"
LOGSTASH_KEYSTORE_PWD="changeme"
LOGSTASH_CONF_FILE=""

#Loop through options passed
while getopts :v:u:S:c:K:L:h optname; do
  log "Option $optname set"
  case $optname in
    v) #logstash version number
      LOGSTASH_VERSION="${OPTARG}"
      ;;
    u) #elasticsearch url
      ELASTICSEARCH_URL="${OPTARG}"
      ;;
    S) #security logstash pwd
      USER_LOGSTASH_PWD="${OPTARG}"
      ;;
    l) #install X-Pack
      INSTALL_XPACK=1
      ;;
    L) #install additional plugins
      INSTALL_ADDITIONAL_PLUGINS="${OPTARG}"
      ;;
    c) #logstash configuration
      LOGSTASH_CONF_FILE="${OPTARG}"
      ;;
    K) #logstash keystore password
      LOGSTASH_KEYSTORE_PWD="${OPTARG}"
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
#########################
# Parameter state changes
#########################

log "installing logstash $LOGSTASH_VERSION"
log "installing X-Pack plugins is set to: $INSTALL_XPACK"

#########################
# Installation steps as functions
#########################

download_install_deb()
{
  log "[download_install_deb] starting download of package"
  local DOWNLOAD_URL="https://artifacts.elastic.co/downloads/logstash/logstash-$LOGSTASH_VERSION.deb"
  curl -o "logstash-$LOGSTASH_VERSION.deb" "$DOWNLOAD_URL"
  log "[download_install_deb] installing downloaded package"
  dpkg -i "logstash-$LOGSTASH_VERSION.deb"
}

## Security
##----------------------------------

add_keystore_or_env_var()
{
  if dpkg --compare-versions "$LOGSTASH_VERSION" ">=" "6.2.0"; then
    log "[configuration_and_plugins] adding $1 to logstash keystore"
    echo "$2" | bin/logstash-keystore add $1
    log "[configuration_and_plugins] added $1 logstash keystore"
  else
    log "[add_keystore_or_env_var] adding environment variable for $1"
    set +o history
    export $1="$2"
    set -o history
    log "[add_keystore_or_env_var] added environment variable for $1"
  fi
}

install_additional_plugins()
{
    SKIP_PLUGINS="x-pack"
    log "[install_additional_plugins] installing additional plugins"
    for PLUGIN in $(echo $INSTALL_ADDITIONAL_PLUGINS | tr ";" "\n")
    do
        if [[ $SKIP_PLUGINS =~ $PLUGIN ]]; then
            log "[install_additional_plugins] skipping plugin $PLUGIN"
        else
            log "[install_additional_plugins] installing plugin $PLUGIN"
            /usr/share/logstash/bin/logstash-plugin install $PLUGIN
            log "[install_additional_plugins] installed plugin $PLUGIN"
        fi
    done
    log "[install_additional_plugins] installed additional plugins"
}

configuration_and_plugins()
{
    # backup the current config
    local LOGSTASH_CONF=/etc/logstash/logstash.yml
    mv "$LOGSTASH_CONF" "$LOGSTASH_CONF.bak"

    log "[configuration_and_plugins] configuring logstash.yml"

    mkdir -p /var/log/logstash
    chown -R logstash: /var/log/logstash

    # logstash conf file
    if [[ -n "$LOGSTASH_CONF_FILE" ]]; then
      echo "$LOGSTASH_CONF_FILE" > /etc/logstash/conf.d/logstash.conf
    fi

    # logstash keystore
    if dpkg --compare-versions "$LOGSTASH_VERSION" ">=" "6.2.0"; then
      set +o history
      export LOGSTASH_KEYSTORE_PASS="$LOGSTASH_KEYSTORE_PWD"
      set -o history
      log "[configuration_and_plugins] creating logstash keystore"
      bin/logstash-keystore create
      log "[configuration_and_plugins] created logstash keystore"
    fi

    add_keystore_or_env_var 'LOGSTASH_SYSTEM_PASS' "$USER_LOGSTASH_PWD"
    add_keystore_or_env_var 'ELASTICSEARCH_URL' "$ELASTICSEARCH_URL"

    # install x-pack
    if [ ${INSTALL_XPACK} -ne 0 ]; then
      echo "xpack.monitoring.elasticsearch.username: logstash_system" >> $LOGSTASH_CONF
      echo 'xpack.monitoring.elasticsearch.password: ${LOGSTASH_SYSTEM_PASS}' >> $LOGSTASH_CONF

      log "[configuration_and_plugins] installing x-pack plugin"
      /usr/share/logstash/bin/logstash-plugin install x-pack
      log "[configuration_and_plugins] installed x-pack plugin"
    fi

    # install additional plugins
    if [[ -n "$INSTALL_ADDITIONAL_PLUGINS" ]]; then
      install_additional_plugins
    fi
}

install_start_service()
{
    log "[install_start_service] starting logstash"
    systemctl start logstash.service
    log "[install_start_service] started logstash!"
}

#########################
# Installation sequence
#########################

log "[apt-get] updating apt-get"
(apt-get -y update || (sleep 15; apt-get -y update)) > /dev/null
log "[apt-get] updated apt-get"

log "[install_sequence] Starting installation"
download_install_deb
configuration_and_plugins
install_start_service
log "[install_sequence] Finished installation"

ELAPSED_TIME=$(($SECONDS - $START_TIME))
PRETTY=$(printf '%dh:%dm:%ds\n' $(($ELAPSED_TIME/3600)) $(($ELAPSED_TIME%3600/60)) $(($ELAPSED_TIME%60)))
log "End execution of Logstash script extension in ${PRETTY}"
