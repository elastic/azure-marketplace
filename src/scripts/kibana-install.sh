#!/bin/bash

# The MIT License (MIT)
#
# Portions Copyright (c) 2015 Microsoft Azure
# Portions Copyright (c) 2015 Elastic, Inc.
#
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
#

#########################
# HELP
#########################

help()
{
    echo "This script installs kibana on a dedicated VM in the elasticsearch ARM template cluster"
    echo "Parameters:"
    echo "-n elasticsearch cluster name"
    echo "-v kibana version e.g 4.2.1"
    echo "-e elasticsearch version e.g 2.3.1"
    echo "-u elasticsearch url e.g. http://10.0.0.4:9200"
    echo "-l install plugins true/false"
    echo "-S kibana server password"
    echo "-m <internal/external> hints whether to use the internal loadbalancer or internal client node (when external loadbalancing)"

    echo "-h view this help content"
}

# log() does an echo prefixed with time
log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/arm-install.log
}

log "Begin execution of Kibana script extension on ${HOSTNAME}"
START_TIME=$SECONDS

export DEBIAN_FRONTEND=noninteractive

if service --status-all | grep -Fq 'kibana'; then
  log "Kibana already installed"
  exit 0
fi

#########################
# Paramater handling
#########################

#Script Parameters
CLUSTER_NAME="elasticsearch"
KIBANA_VERSION="4.2.1"
ES_VERSION="2.0.0"
#Default internal load balancer ip
ELASTICSEARCH_URL="http://10.0.0.4:9200"
INSTALL_PLUGINS=0
HOSTMODE="internal"

USER_KIBANA4_SERVER_PWD="changeME"

#Loop through options passed
while getopts :n:v:e:u:S:m:lh optname; do
  log "Option $optname set"
  case $optname in
    n) #set cluster name
      CLUSTER_NAME=${OPTARG}
      ;;
    v) #kibana version number
      KIBANA_VERSION=${OPTARG}
      ;;
    e) #elasticsearch version number
      ES_VERSION=${OPTARG}
      ;;
    u) #elasticsearch url
      ELASTICSEARCH_URL=${OPTARG}
      ;;
    S) #shield kibana server pwd
      USER_KIBANA4_SERVER_PWD=${OPTARG}
      ;;
    m) #shield kibana server pwd
      HOSTMODE=${OPTARG}
      ;;
    l) #install plugins
      INSTALL_PLUGINS=1
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

log "installing kibana $KIBANA_VERSION for Elasticsearch $ES_VERSION cluster: $CLUSTER_NAME"
log "installing kibana plugins is set to: $INSTALL_PLUGINS"
log "Kibana will talk to elasticsearch over $ELASTICSEARCH_URL"

#########################
# Installation
#########################

sudo groupadd -g 999 kibana
sudo useradd -u 999 -g 999 kibana

sudo mkdir -p /opt/kibana

if dpkg --compare-versions "$KIBANA_VERSION" ">=" "4.6.0"; then
    DOWNLOAD_URL="https://download.elastic.co/kibana/kibana/kibana-$KIBANA_VERSION-linux-x86_64.tar.gz"
else
    DOWNLOAD_URL="https://download.elastic.co/kibana/kibana/kibana-$KIBANA_VERSION-linux-x64.tar.gz"
fi

log "downloading kibana $KIBANA_VERSION from $DOWNLOAD_URL"
curl -o kibana.tar.gz "$DOWNLOAD_URL"
tar xvf kibana.tar.gz -C /opt/kibana/ --strip-components=1
log "kibana $KIBANA_VERSION downloaded"

sudo chown -R kibana: /opt/kibana

mv /opt/kibana/config/kibana.yml /opt/kibana/config/kibana.yml.bak

# set the elasticsearch URL
echo "elasticsearch.url: \"$ELASTICSEARCH_URL\"" >> /opt/kibana/config/kibana.yml
# specify kibana log location
echo "logging.dest: /var/log/kibana.log" >> /opt/kibana/config/kibana.yml

if [ ${INSTALL_PLUGINS} -ne 0 ]; then
    echo "elasticsearch.username: es_kibana_server" >> /opt/kibana/config/kibana.yml
    echo "elasticsearch.password: \"$USER_KIBANA4_SERVER_PWD\"" >> /opt/kibana/config/kibana.yml

    # install shield only on Elasticsearch 2.4.0+ so that graph can be used.
    # cannot be installed on earlier versions as 
    # they do not allow unsafe sessions (i.e. sending session cookie over HTTP)
    if dpkg --compare-versions "$ES_VERSION" ">=" "2.4.0"; then
      log "installing latest shield"
      /opt/kibana/bin/kibana plugin --install kibana/shield/2.4.0
      log "shield plugin installed"

      # NOTE: These settings allow Shield to work in Kibana without HTTPS. 
      # This is NOT recommended for production.
      echo "shield.useUnsafeSessions: true" >> /opt/kibana/config/kibana.yml
      echo "shield.skipSslCheck: true" >> /opt/kibana/config/kibana.yml

      log "generating shield encryption key"
      if [ $(dpkg-query -W -f='${Status}' pwgen 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
        (sudo apt-get -yq install pwgen || (sleep 15; sudo apt-get -yq install pwgen))
      fi
      ENCRYPTION_KEY=$(pwgen 64 1)    
      echo "shield.encryptionKey: \"$ENCRYPTION_KEY\"" >> /opt/kibana/config/kibana.yml
      log "shield encryption key generated"    
    fi

    # install graph
    if dpkg --compare-versions "$ES_VERSION" ">=" "2.3.0"; then
      log "installing graph plugin"
      /opt/kibana/bin/kibana plugin --install elasticsearch/graph/$ES_VERSION
      log "graph plugin installed"
    fi

    # install reporting
    if dpkg --compare-versions "$KIBANA_VERSION" ">=" "4.6.1"; then
      log "installing reporting plugin"
      /opt/kibana/bin/kibana plugin --install kibana/reporting/2.4.1
      log "reporting plugin installed"

      log "generating reporting encryption key"
      if [ $(dpkg-query -W -f='${Status}' pwgen 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
        (sudo apt-get -yq install pwgen || (sleep 15; sudo apt-get -yq install pwgen))
      fi
      ENCRYPTION_KEY=$(pwgen 64 1)    
      echo "reporting.encryptionKey: \"$ENCRYPTION_KEY\"" >> /opt/kibana/config/kibana.yml
      log "reporting encryption key generated"    
    fi

    log "installing monitoring plugin"
    /opt/kibana/bin/kibana plugin --install elasticsearch/marvel/$ES_VERSION
    log "monitoring plugin installed"
    log "installing sense plugin"
    /opt/kibana/bin/kibana plugin --install elastic/sense
    log "sense plugin installed"

    # sense default url to point at Elasticsearch on first load
    echo "sense.defaultServerUrl: \"$ELASTICSEARCH_URL\"" >> /opt/kibana/config/kibana.yml
fi

# Add upstart task and start kibana service
cat << EOF > /etc/init/kibana.conf
# kibana
description "Elasticsearch Kibana Service"

start on starting
script
    /opt/kibana/bin/kibana
end script
EOF

chmod +x /etc/init/kibana.conf
sudo service kibana start

ELAPSED_TIME=$(($SECONDS - $START_TIME))
PRETTY=$(printf '%dh:%dm:%ds\n' $(($ELAPSED_TIME/3600)) $(($ELAPSED_TIME%3600/60)) $(($ELAPSED_TIME%60)))
log "End execution of Kibana script extension in ${PRETTY}"
