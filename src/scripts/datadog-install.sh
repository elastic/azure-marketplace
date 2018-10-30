#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

ELASTIC_CONFIG_FILE=/etc/datadog-agent/conf.d/elastic.d/elastic.yaml
DD_AGENT=/var/tmp/install_datadog_agent.sh

# Custom logging with time so we can easily relate running times, also log to separate file so order is guaranteed.
# The Script extension output the stdout/err buffer in intervals with duplicates.
log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/datadog-install.log
}

if [ "$1" == "" ]; then
    log "Must provide a DataDog API Key" >&2
    exit 1
fi

if [ "$2" == "" ]; then
    log "Must provide a Node Type value (master=0;client=1;data=2)" >&2
    exit 1
fi

NODE_TYPE_NAME=""

case $NODE_TYPE in
    0)
        NODE_TYPE_NAME="master"
        ;;
    1)
        NODE_TYPE_NAME="client"
        ;;
    2)
        NODE_TYPE_NAME="data"
        ;;
    *)
        log "Invalid value for the NODE_TYPE argument. Must be either 0=master, 1=client or 2=data."
        exit 1
        ;;
esac

log "Installing DataDog plugin onto this machine using API Key [$1]"

wget -q https://raw.githubusercontent.com/DataDog/datadog-agent/master/cmd/agent/install_script.sh -O $DD_AGENT
chmod +x $DD_AGENT
DD_API_KEY=$1 $DD_AGENT
rm /etc/datadog-agent/conf.d/elastic.d/auto_conf.yaml

echo "ad_identifiers:
    - elasticsearch
instances:
    - url: 'http://localhost:9200'
pshard_stats: true
cluster_stats: false
pending_task_stats: true
tags:
    - 'elasticsearch-role:$NODE_TYPE_NAME-node'" >> $ELASTIC_CONFIG_FILE

systemctl restart datadog-agent

log "Finished installing DataDog plugin..."