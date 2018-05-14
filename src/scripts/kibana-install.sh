#!/bin/bash

# License: https://github.com/elastic/azure-marketplace/blob/master/LICENSE.txt
#
# Trent Swanson (Full Scale 180 Inc)
# Martijn Laarman, Greg Marzouka, Russ Cam (Elastic)
# Contributors
#

#########################
# HELP
#########################

export DEBIAN_FRONTEND=noninteractive

help()
{
    echo "This script installs kibana on a dedicated VM in the elasticsearch ARM template cluster"
    echo ""
    echo "Options:"
    echo "    -n      elasticsearch cluster name"
    echo "    -v      kibana version e.g 6.2.2"
    echo "    -u      elasticsearch url e.g. http://10.0.0.4:9200"
    echo "    -l      install plugins true/false"
    echo "    -S      kibana password"
    echo "    -C      kibana cert to encrypt communication between the browser and Kibana"
    echo "    -K      kibana key to encrypt communication between the browser and Kibana"
    echo "    -P      kibana key passphrase to decrypt the private key (optional as the key may not be encrypted)"
    echo "    -Y      <yaml\nyaml> additional yaml configuration"
    echo "    -h      view this help content"
}

# Custom logging with time so we can easily relate running times, also log to separate file so order is guaranteed.
# The Script extension output the stdout/err buffer in intervals with duplicates.
log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/arm-install.log
}

log "Begin execution of Kibana script extension on ${HOSTNAME}"
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

if service --status-all | grep -Fq 'kibana'; then
  log "Kibana already installed."
  exit 0
fi

#########################
# Parameter handling
#########################

#Script Parameters
CLUSTER_NAME="elasticsearch"
KIBANA_VERSION="6.2.1"
#Default internal load balancer ip
ELASTICSEARCH_URL="http://10.0.0.4:9200"
INSTALL_XPACK=0
USER_KIBANA_PWD="changeme"
SSL_CERT=""
SSL_KEY=""
SSL_PASSPHRASE=""
YAML_CONFIGURATION=""

#Loop through options passed
while getopts :n:v:u:S:C:K:P:Y:lh optname; do
  log "Option $optname set"
  case $optname in
    n) #set cluster name
      CLUSTER_NAME="${OPTARG}"
      ;;
    v) #kibana version number
      KIBANA_VERSION="${OPTARG}"
      ;;
    u) #elasticsearch url
      ELASTICSEARCH_URL="${OPTARG}"
      ;;
    S) #security kibana pwd
      USER_KIBANA_PWD="${OPTARG}"
      ;;
    l) #install X-Pack
      INSTALL_XPACK=1
      ;;
    C) #kibana ssl cert
      SSL_CERT="${OPTARG}"
      ;;
    K) #kibana ssl key
      SSL_KEY="${OPTARG}"
      ;;
    P) #kibana ssl key passphrase
      SSL_PASSPHRASE="${OPTARG}"
      ;;
    Y) #kibana additional yml configuration
      YAML_CONFIGURATION="${OPTARG}"
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

#########################
# Parameter state changes
#########################

log "Installing Kibana $KIBANA_VERSION for Elasticsearch cluster: $CLUSTER_NAME"
log "Installing X-Pack plugins is set to: $INSTALL_XPACK"
log "Kibana will talk to Elasticsearch over $ELASTICSEARCH_URL"

#########################
# Installation steps as functions
#########################

download_kibana()
{
    log "[download_kibana] Download Kibana $KIBANA_VERSION"
    local DOWNLOAD_URL="https://artifacts.elastic.co/downloads/kibana/kibana-$KIBANA_VERSION-amd64.deb"
    log "[download_kibana] Download location $DOWNLOAD_URL"
    wget --retry-connrefused --waitretry=1 -q "$DOWNLOAD_URL" -O "kibana-$KIBANA_VERSION.deb"
    local EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        log "[download_kibana] Error downloading Kibana $KIBANA_VERSION"
        exit $EXIT_CODE
    fi
    log "[download_kibana] Installing Kibana $KIBANA_VERSION"
    dpkg -i "kibana-$KIBANA_VERSION.deb"
    log "[download_kibana] Installed Kibana $KIBANA_VERSION"
}

## Security
##----------------------------------

install_pwgen()
{
    log "[install_pwgen] Installing pwgen tool if needed"
    if [ $(dpkg-query -W -f='${Status}' pwgen 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
      (apt-get -yq install pwgen || (sleep 15; apt-get -yq install pwgen))
    fi
}

configuration_and_plugins()
{
    # backup the current config
    mv /etc/kibana/kibana.yml /etc/kibana/kibana.yml.bak

    log "[configuration_and_plugins] Configuring kibana.yml"
    local KIBANA_CONF=/etc/kibana/kibana.yml
    # set the elasticsearch URL
    echo "elasticsearch.url: \"$ELASTICSEARCH_URL\"" >> $KIBANA_CONF
    echo "server.host:" $(hostname -I) >> $KIBANA_CONF
    # specify kibana log location
    echo "logging.dest: /var/log/kibana.log" >> $KIBANA_CONF
    touch /var/log/kibana.log
    chown kibana: /var/log/kibana.log

    # set logging to silent by default
    echo "logging.silent: true" >> $KIBANA_CONF

    # install x-pack
    if [ ${INSTALL_XPACK} -ne 0 ]; then
      echo "elasticsearch.username: kibana" >> $KIBANA_CONF
      echo "elasticsearch.password: $USER_KIBANA_PWD" >> $KIBANA_CONF

      install_pwgen
      local ENCRYPTION_KEY=$(pwgen 64 1)
      echo "xpack.security.encryptionKey: \"$ENCRYPTION_KEY\"" >> $KIBANA_CONF
      log "[configuration_and_plugins] X-Pack Security encryption key generated"
      ENCRYPTION_KEY=$(pwgen 64 1)
      echo "xpack.reporting.encryptionKey: \"$ENCRYPTION_KEY\"" >> $KIBANA_CONF
      log "[configuration_and_plugins] X-Pack Reporting encryption key generated"

      log "[configuration_and_plugins] Installing X-Pack plugin"
      /usr/share/kibana/bin/kibana-plugin install x-pack
      log "[configuration_and_plugins] Installed X-Pack plugin"
    fi

    # configure HTTPS if cert and private key supplied
    if [[ -n "${SSL_CERT}" && -n "${SSL_KEY}" ]]; then
      mkdir -p /etc/kibana/ssl
      log "[configuration_and_plugins] Save kibana cert blob to file"
      echo ${SSL_CERT} | base64 -d | tee /etc/kibana/ssl/kibana.crt
      log "[configuration_and_plugins] Save kibana key blob to file"
      echo ${SSL_KEY} | base64 -d | tee /etc/kibana/ssl/kibana.key

      log "[configuration_and_plugins] Configuring encrypted communication"

      if dpkg --compare-versions "$KIBANA_VERSION" ">=" "5.3.0"; then
          echo "server.ssl.enabled: true" >> $KIBANA_CONF
          echo "server.ssl.key: /etc/kibana/ssl/kibana.key" >> $KIBANA_CONF
          echo "server.ssl.certificate: /etc/kibana/ssl/kibana.crt" >> $KIBANA_CONF

          if [[ -n "${SSL_PASSPHRASE}" ]]; then
              echo "server.ssl.keyPassphrase: \"$SSL_PASSPHRASE\"" >> $KIBANA_CONF
          fi
      else
          echo "server.ssl.key: /etc/kibana/ssl/kibana.key" >> $KIBANA_CONF
          echo "server.ssl.cert: /etc/kibana/ssl/kibana.crt" >> $KIBANA_CONF
      fi

      log "[configuration_and_plugins] Configured encrypted communication"
    fi

    # Additional yaml configuration
    if [[ -n "$YAML_CONFIGURATION" ]]; then
        log "[configuration_and_plugins] include additional yaml configuration"
        local SKIP_LINES="elasticsearch.username elasticsearch.password "
        SKIP_LINES+="server.ssl.key server.ssl.cert server.ssl.enabled "
        SKIP_LINES+="xpack.security.encryptionKey xpack.reporting.encryptionKey "
        SKIP_LINES+="elasticsearch.url server.host logging.dest logging.silent "
        local SKIP_REGEX="^\s*("$(echo $SKIP_LINES | tr " " "|" | sed 's/\./\\\./g')")"
        IFS=$'\n'
        for LINE in $(echo -e "$YAML_CONFIGURATION")
        do
            if [[ -n "$LINE" ]]; then
                if [[ $LINE =~ $SKIP_REGEX ]]; then
                    log "[configuration_and_plugins] Skipping line '$LINE'"
                else
                    log "[configuration_and_plugins] Adding line '$LINE' to $KIBANA_CONF"
                    echo -e "$LINE" >> $KIBANA_CONF
                fi
            fi
        done
        unset IFS
        log "[configuration_and_plugins] included additional yaml configuration"
        log "[configuration_and_plugins] run yaml lint on configuration"
        install_yamllint
        LINT=$(yamllint -d "{extends: relaxed, rules: {key-duplicates: {level: error}}}" $KIBANA_CONF; exit ${PIPESTATUS[0]})
        EXIT_CODE=$?
        log "[configuration_and_plugins] ran yaml lint (exit code $EXIT_CODE) $LINT"
        if [ $EXIT_CODE -ne 0 ]; then
            log "[configuration_and_plugins] errors in yaml configuration. exiting"
            exit 11
        fi
    fi
}

install_yamllint()
{
    log "[install_yamllint] installing yamllint"
    (apt-get -yq install yamllint || (sleep 15; apt-get -yq install yamllint))
    log "[install_yamllint] installed yamllint"
}

install_start_service()
{
    log "[install_start_service] Configuring service for kibana to run at start"
    update-rc.d kibana defaults 95 10
    log "[install_start_service] Starting kibana!"
    service kibana start
}

#########################
# Installation sequence
#########################

log "[apt-get] updating apt-get"
(apt-get -y update || (sleep 15; apt-get -y update)) > /dev/null
log "[apt-get] updated apt-get"

log "[install_sequence] Starting installation"
download_kibana
configuration_and_plugins
install_start_service
log "[install_sequence] Finished installation"

ELAPSED_TIME=$(($SECONDS - $START_TIME))
PRETTY=$(printf '%dh:%dm:%ds\n' $(($ELAPSED_TIME/3600)) $(($ELAPSED_TIME%3600/60)) $(($ELAPSED_TIME%60)))
log "End execution of Kibana script extension in ${PRETTY}"
