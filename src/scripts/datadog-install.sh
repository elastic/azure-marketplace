#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

# Custom logging with time so we can easily relate running times, also log to separate file so order is guaranteed.
# The Script extension output the stdout/err buffer in intervals with duplicates.
log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/datadog-install.log
}

if [ "$1" == "" ]; then
    log "Must provide a DataDog API Key as the one and only argument" >&2
    exit 1
fi

log "Installing DataDog plugin onto this machine using API Key [$1]"

wget -q https://raw.githubusercontent.com/DataDog/datadog-agent/master/cmd/agent/install_script.sh -O /var/tmp/install_datadog_agent.sh
chmod +x /var/tmp/install_datadog_agent.sh
DD_API_KEY=$1 /var/tmp/install_datadog_agent.sh
rm /etc/datadog-agent/conf.d/elastic.d/auto_conf.yaml
echo "ad_identifiers:" | tee -a /etc/datadog-agent/conf.d/elastic.d/elastic.yaml
echo "  - elasticsearch" | tee -a /etc/datadog-agent/conf.d/elastic.d/elastic.yaml
echo "instances:" | tee -a /etc/datadog-agent/conf.d/elastic.d/elastic.yaml
echo "  - url: 'http://localhost:9200'" | tee -a /etc/datadog-agent/conf.d/elastic.d/elastic.yaml
echo "    pshard_stats: true" | tee -a /etc/datadog-agent/conf.d/elastic.d/elastic.yaml
echo "    cluster_stats: false" | tee -a /etc/datadog-agent/conf.d/elastic.d/elastic.yaml
echo "    pending_task_stats: true" | tee -a /etc/datadog-agent/conf.d/elastic.d/elastic.yaml
echo "    tags:" | tee -a /etc/datadog-agent/conf.d/elastic.d/elastic.yaml
echo "      - 'elasticsearch-role:data-node'" | tee -a /etc/datadog-agent/conf.d/elastic.d/elastic.yaml
systemctl restart datadog-agent

log "Finished installing DataDog plugin..."