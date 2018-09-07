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

  # TODO: Ability to stop, change configuration and restart

  exit 0
fi

#########################
# Parameter handling
#########################

#Script Parameters
LOGSTASH_VERSION="6.2.4"
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

# Install Oracle Java
install_java()
{
  bash java-ubuntu-install.sh
}

# Install Logstash
install_logstash()
{
  local DOWNLOAD_URL="https://artifacts.elastic.co/downloads/logstash/logstash-$LOGSTASH_VERSION.deb?ultron=msft&gambit=azure"

  log "[install_logstash] installing Logstash $LOGSTASH_VERSION"
  log "[install_logstash] download location - $DOWNLOAD_URL"
  wget --retry-connrefused --waitretry=1 -q "$DOWNLOAD_URL" -O logstash.deb
  local EXIT_CODE=$?
  if [ $EXIT_CODE -ne 0 ]; then
      log "[install_logstash] error downloading Logstash $LOGSTASH_VERSION"
      exit $EXIT_CODE
  fi
  log "[install_logstash] downloaded Logstash $LOGSTASH_VERSION"
  dpkg -i logstash.deb
  log "[install_logstash] installed Logstash $LOGSTASH_VERSION"
}

## Security
##----------------------------------

add_keystore_or_env_var()
{
  local KEY=$1
  local VALUE="$2"

  if dpkg --compare-versions "$LOGSTASH_VERSION" ">=" "6.2.0"; then
    # TODO: Should be set in  /etc/sysconfig/logstash
    # See https://www.elastic.co/guide/en/logstash/current/keystore.html#keystore-password
    set +o history
    export LOGSTASH_KEYSTORE_PASS="$LOGSTASH_KEYSTORE_PWD"
    set -o history

    # create it the keystore if it doesn't exist
    if [[ ! -f /etc/logstash/logstash.keystore ]]; then
      log "[configure_logstash] creating logstash keystore"
      /usr/share/logstash/bin/logstash-keystore create
      log "[configure_logstash] created logstash keystore"
    fi

    log "[configuration_and_plugins] adding $KEY to logstash keystore"
    echo "$VALUE" | /usr/share/logstash/bin/logstash-keystore add $KEY
    log "[configuration_and_plugins] added $KEY logstash keystore"
  else
    log "[add_keystore_or_env_var] adding environment variable for $KEY"
    set +o history
    export $KEY="$VALUE"
    set -o history
    log "[add_keystore_or_env_var] added environment variable for $KEY"
  fi
}

configure_logstash()
{
    # backup the current config
    local LOGSTASH_CONF=/etc/logstash/logstash.yml
    mv $LOGSTASH_CONF $LOGSTASH_CONF.bak

    log "[configure_logstash] configuring logstash.yml"

    echo "node.name: \"${HOSTNAME}\"" >> $LOGSTASH_CONF

    # logstash conf file
    if [[ -n "$LOGSTASH_CONF_FILE" ]]; then
      local CONF_FILE=/etc/logstash/conf.d/logstash.conf
      mv $CONF_FILE $CONF_FILE.bak
      echo ${LOGSTASH_CONF_FILE} | base64 -d | tee $CONF_FILE
    fi

    # allow values to be referenced in *.conf files
    add_keystore_or_env_var 'LOGSTASH_SYSTEM_PASS' "$USER_LOGSTASH_PWD"
    add_keystore_or_env_var 'ELASTICSEARCH_URL' "$ELASTICSEARCH_URL"

    # put data on the OS disk in a writable location
    echo "path.data: /var/lib/logstash" >> $LOGSTASH_CONF

    # TODO: make configurable?
    # echo "queue.type: persisted" >> $LOGSTASH_CONF

    # put log files on the OS disk in a writable location
    local LOG_PATH=/var/log/logstash
    mkdir -p $LOG_PATH
    chown -R logstash: $LOG_PATH
    echo "path.logs: $LOG_PATH" >> $LOGSTASH_CONF
    echo "log.level: error" >> $LOGSTASH_CONF

    # install x-pack
    if [ ${INSTALL_XPACK} -ne 0 ]; then
      if dpkg --compare-versions "$LOGSTASH_VERSION" "<" "6.3.0"; then
        log "[configure_logstash] installing x-pack plugin"
        /usr/share/logstash/bin/logstash-plugin install x-pack
        log "[configure_logstash] installed x-pack plugin"
      fi

      echo "xpack.monitoring.elasticsearch.username: logstash_system" >> $LOGSTASH_CONF
      # reference from env var or keystore
      echo 'xpack.monitoring.elasticsearch.password: "${LOGSTASH_SYSTEM_PASS}"' >> $LOGSTASH_CONF
      echo "xpack.monitoring.enabled: true" >> $LOGSTASH_CONF
    fi

    # Additional yaml configuration
    if [[ -n "$YAML_CONFIGURATION" ]]; then
        log "[configure_logstash] include additional yaml configuration"

        local SKIP_LINES="node.name path.data path.logs "
        SKIP_LINES+="xpack.monitoring.elasticsearch.username xpack.monitoring.elasticsearch.password "
        SKIP_LINES+="xpack.monitoring.enabled "
        local SKIP_REGEX="^\s*("$(echo $SKIP_LINES | tr " " "|" | sed 's/\./\\\./g')")"
        IFS=$'\n'
        for LINE in $(echo -e "$YAML_CONFIGURATION"); do
          if [[ -n "$LINE" ]]; then
              if [[ $LINE =~ $SKIP_REGEX ]]; then
                  log "[configure_logstash] Skipping line '$LINE'"
              else
                  log "[configure_logstash] Adding line '$LINE' to $LOGSTASH_CONF"
                  echo "$LINE" >> $LOGSTASH_CONF
              fi
          fi
        done
        unset IFS
        log "[configure_logstash] included additional yaml configuration"
        log "[configure_logstash] run yaml lint on configuration"
        install_yamllint
        LINT=$(yamllint -d "{extends: relaxed, rules: {key-duplicates: {level: error}}}" $LOGSTASH_CONF; exit ${PIPESTATUS[0]})
        EXIT_CODE=$?
        log "[configure_logstash] ran yaml lint (exit code $EXIT_CODE) $LINT"
        if [ $EXIT_CODE -ne 0 ]; then
            log "[configure_logstash] errors in yaml configuration. exiting"
            exit 11
        fi
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

start_service()
{
    log "[start_service] starting logstash"
    systemctl start logstash.service
    log "[start_service] started logstash!"
}

install_apt_package()
{
  local PACKAGE=$1
  if [ $(dpkg-query -W -f='${Status}' $PACKAGE 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
    log "[install_$PACKAGE] installing $PACKAGE"
    (apt-get -yq install $PACKAGE || (sleep 15; apt-get -yq install $PACKAGE))
    log "[install_$PACKAGE] installed $PACKAGE"
  fi
}

install_yamllint()
{
  install_apt_package yamllint
}

#########################
# Installation sequence
#########################

log "[apt-get] updating apt-get"
(apt-get -y update || (sleep 15; apt-get -y update)) > /dev/null
log "[apt-get] updated apt-get"

install_java

install_logstash

configuration_and_plugins

# install additional plugins
if [[ -n "$INSTALL_ADDITIONAL_PLUGINS" ]]; then
  install_additional_plugins
fi

start_service

ELAPSED_TIME=$(($SECONDS - $START_TIME))
PRETTY=$(printf '%dh:%dm:%ds\n' $(($ELAPSED_TIME/3600)) $(($ELAPSED_TIME%3600/60)) $(($ELAPSED_TIME%60)))
log "End execution of Logstash script extension in ${PRETTY}"
