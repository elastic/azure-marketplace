#!/bin/bash

if [ "$1" == "" ]; then
    echo "Must provide a DataDog API Key as the one and only argument"
    exit 1
fi

echo "Installing DataDog plugin onto this machine using API Key [$1]"

wget -q https://raw.githubusercontent.com/DataDog/datadog-agent/master/cmd/agent/install_script.sh -O /var/tmp/install_datadog_agent.sh
chmod +x /var/tmp/install_datadog_agent.sh
DD_API_KEY=$1 /var/tmp/install_datadog_agent.sh
rm /etc/datadog-agent/conf.d/elastic.d/auto_conf.yaml
echo "ad_identifiers:" | sudo tee -a /etc/datadog-agent/conf.d/elastic.d/elastic.yaml
echo "  - elasticsearch" | sudo tee -a /etc/datadog-agent/conf.d/elastic.d/elastic.yaml
echo "instances:" | sudo tee -a /etc/datadog-agent/conf.d/elastic.d/elastic.yaml
echo "  - url: 'http://localhost:9200'" | sudo tee -a /etc/datadog-agent/conf.d/elastic.d/elastic.yaml
echo "    pshard_stats: true" | sudo tee -a /etc/datadog-agent/conf.d/elastic.d/elastic.yaml
echo "    cluster_stats: false" | sudo tee -a /etc/datadog-agent/conf.d/elastic.d/elastic.yaml
echo "    pending_task_stats: true" | sudo tee -a /etc/datadog-agent/conf.d/elastic.d/elastic.yaml
echo "    tags:" | sudo tee -a /etc/datadog-agent/conf.d/elastic.d/elastic.yaml
echo "      - 'elasticsearch-role:data-node'" | sudo tee -a /etc/datadog-agent/conf.d/elastic.d/elastic.yaml
systemctl restart datadog-agent