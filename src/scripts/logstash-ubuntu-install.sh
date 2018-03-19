#!/bin/bash

# License: https://github.com/elastic/azure-marketplace/blob/master/LICENSE.txt
#
# Russ Cam (Elastic)
#

#########################
# HELP
#########################

help()
{
    echo "This script installs logstash on a dedicated VM in the elasticsearch ARM template cluster"
    echo "Parameters:"

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

export DEBIAN_FRONTEND=noninteractive

if service --status-all | grep -Fq 'logstash'; then
  log "Logstash already installed."
  exit 0
fi

#########################
# Parameter handling
#########################

#Script Parameters
CLUSTER_NAME="elasticsearch"
LOGSTASH_VERSION="6.2.1"
ES_VERSION="6.2.1"
#Default internal load balancer ip
ELASTICSEARCH_URL="http://10.0.0.4:9200"
INSTALL_XPACK=0
USER_LOGSTASH_PWD="changeme"

#Loop through options passed
while getopts :n:v:e:u:S:C:K:P:m:lh optname; do
  log "Option $optname set"
  case $optname in
    n) #set cluster name
      CLUSTER_NAME="${OPTARG}"
      ;;
    v) #logstash version number
      LOGSTASH_VERSION="${OPTARG}"
      ;;
    e) #elasticsearch version number
      ES_VERSION="${OPTARG}"
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

log "installing logstash $LOGSTASH_VERSION for Elasticsearch $ES_VERSION cluster: $CLUSTER_NAME"
log "installing X-Pack plugins is set to: $INSTALL_XPACK"
log "Logstash will talk to Elasticsearch over $ELASTICSEARCH_URL"

#########################
# Installation steps as functions
#########################

download_install_deb()
{
    log "[download_install_deb] starting download of package"
    local DOWNLOAD_URL="https://artifacts.elastic.co/downloads/kibana/kibana-$KIBANA_VERSION-amd64.deb"
    curl -o "kibana-$KIBANA_VERSION.deb" "$DOWNLOAD_URL"
    log "[download_install_deb] installing downloaded package"
    dpkg -i "kibana-$KIBANA_VERSION.deb"
}

## Security
##----------------------------------

configuration_and_plugins()
{
    # backup the current config
    mv /etc/kibana/kibana.yml /etc/kibana/kibana.yml.bak

    log "[configuration_and_plugins] configuring kibana.yml"
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
      ENCRYPTION_KEY=$(pwgen 64 1)
      echo "xpack.reporting.encryptionKey: \"$ENCRYPTION_KEY\"" >> $KIBANA_CONF
      log "[configuration_and_plugins] x-pack security encryption key generated"

      log "[configuration_and_plugins] installing x-pack plugin"
      /usr/share/kibana/bin/kibana-plugin install x-pack
      log "[configuration_and_plugins] installed x-pack plugin"
    fi

    # configure HTTPS if cert and private key supplied
    if [[ -n "${SSL_CERT}" && -n "${SSL_KEY}" ]]; then
      mkdir -p /etc/kibana/ssl
      log "[configuration_and_plugins] save kibana cert blob to file"
      echo ${SSL_CERT} | base64 -d | tee /etc/kibana/ssl/kibana.crt
      log "[configuration_and_plugins] save kibana key blob to file"
      echo ${SSL_KEY} | base64 -d | tee /etc/kibana/ssl/kibana.key

      log "[configuration_and_plugins] configuring encrypted communication"

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

      log "[configuration_and_plugins] configured encrypted communication"
    fi
}

install_start_service()
{
    log "[install_start_service] configuring service for kibana to run at start"
    update-rc.d kibana defaults 95 10
    log "[install_start_service] starting kibana!"
    service kibana start
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
log "End execution of Kibana script extension in ${PRETTY}"
