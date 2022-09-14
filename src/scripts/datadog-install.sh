#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

help()
{
    echo "Installs DataDog agent"
    echo ""
    echo "Options:"
    echo "    -k      DataDog API key"
    echo "    -r      Node role: master, data, client"
    echo "    -h      view this help content"
}

# Custom logging with time so we can easily relate running times, also log to separate file so order is guaranteed.
# The Script extension output the stdout/err buffer in intervals with duplicates.
log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/datadog-install.log
}

#########################
# Parameter handling
#########################

API_KEY=""
NODE_ROLE=""

#Loop through options passed
while getopts :k:r:h optname; do
  log "Option $optname set"
  case $optname in
    k) # DataDog API key
      API_KEY="${OPTARG}"
      ;;
    r) # Node role
      NODE_ROLE="${OPTARG}"
      ;;
    h) #show help
      help
      exit 2
      ;;
    \?) #unrecognized option - show help
      echo -e \\n"ERROR: unknown option -${BOLD}$OPTARG${NORM}" >&2
      help
      exit 2
      ;;
  esac
done

if [ "$API_KEY" == "" ]; then
    log "Must provide a DataDog API Key" >&2
    exit 1
fi

if [ "$NODE_ROLE" == "" ]; then
    log "Must provide a Node Type value: master, client, or data" >&2
    exit 1
fi

#########################
# Constants
#########################

ELASTIC_CONFIG_FILE=/etc/datadog-agent/conf.d/elastic.d/elastic.yaml
DD_AGENT=/var/tmp/install_datadog_agent.sh

#########################
# Execution
#########################

log "Installing DataDog plugin onto this machine using API Key [$API_KEY]"

wget -q https://raw.githubusercontent.com/DataDog/datadog-agent/master/cmd/agent/install_script.sh -O $DD_AGENT
chmod +x $DD_AGENT
DD_API_KEY=$API_KEY DD_AGENT_MAJOR_VERSION=7 $DD_AGENT
rm /etc/datadog-agent/conf.d/elastic.d/auto_conf.yaml

echo "instances:
    - url: 'http://$(hostname):9200'
pshard_stats: true
cluster_stats: false
pending_task_stats: true
tags:
    - 'elasticsearch-role:$NODE_ROLE-node'" >> $ELASTIC_CONFIG_FILE

systemctl restart datadog-agent

log "Finished installing DataDog plugin."