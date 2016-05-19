#!/bin/bash

# The MIT License (MIT)
#
# Portions Copyright (c) 2015 Microsoft Azure
# Portions Copyright (c) 2015 Elastic, Inc.
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
    echo "This script installs Elasticsearch cluster on Ubuntu"
    echo "Parameters:"
    echo "-n elasticsearch cluster name"
    echo "-v elasticsearch version 1.5.0"

    echo "-d cluster uses dedicated masters"
    echo "-Z <number of nodes> hint to the install script how many data nodes we are provisioning"

    echo "-A admin password"
    echo "-R read password"
    echo "-K kibana user password"
    echo "-S kibana server password"

    echo "-x configure as a dedicated master node"
    echo "-y configure as client only node (no master, no data)"
    echo "-z configure as data node (no master)"
    echo "-l install plugins"

    echo "-m marvel host , used for agent config"

    echo "-h view this help content"
}

# log() does an echo prefixed with time
log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/arm-install.log
}

log "Begin execution of Elasticsearch script extension on ${HOSTNAME}"
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

# TEMP FIX - Re-evaluate and remove when possible
# This is an interim fix for hostname resolution in current VM
grep -q "${HOSTNAME}" /etc/hosts
if [ $? == 0 ]
then
  log "${HOSTNAME}found in /etc/hosts"
else
  log "${HOSTNAME} not found in /etc/hosts"
  # Append it to the hsots file if not there
  echo "127.0.0.1 ${HOSTNAME}" >> /etc/hosts
  log "hostname ${HOSTNAME} added to /etchosts"
fi

#########################
# Paramater handling
#########################

CLUSTER_NAME="elasticsearch"
ES_VERSION="2.0.0"
INSTALL_PLUGINS=0
CLIENT_ONLY_NODE=0
DATA_NODE=0
MASTER_ONLY_NODE=0

CLUSTER_USES_DEDICATED_MASTERS=0
DATANODE_COUNT=0

MINIMUM_MASTER_NODES=3
UNICAST_HOSTS='["master-node-0:9300","master-node-1:9300","master-node-2:9300"]'

USER_ADMIN_PWD="changeME"
USER_READ_PWD="changeME"
USER_KIBANA4_PWD="changeME"
USER_KIBANA4_SERVER_PWD="changeME"

#Loop through options passed
while getopts :n:v:A:R:K:S:Z:xyzldh optname; do
  log "Option $optname set"
  case $optname in
    n) #set cluster name
      CLUSTER_NAME=${OPTARG}
      ;;
    v) #elasticsearch version number
      ES_VERSION=${OPTARG}
      ;;
    A) #shield admin pwd
      USER_ADMIN_PWD=${OPTARG}
      ;;
    R) #shield readonly pwd
      USER_READ_PWD=${OPTARG}
      ;;
    K) #shield kibana user pwd
      USER_KIBANA4_PWD=${OPTARG}
      ;;
    S) #shield kibana server pwd
      USER_KIBANA4_SERVER_PWD=${OPTARG}
      ;;
    Z) #number of data nodes hints (used to calculate minimum master nodes)
      DATANODE_COUNT=${OPTARG}
      ;;
    x) #master node
      MASTER_ONLY_NODE=1
      ;;
    y) #client node
      CLIENT_ONLY_NODE=1
      ;;
    z) #client node
      DATA_NODE=1
      ;;
    l) #install plugins
      INSTALL_PLUGINS=1
      ;;
    d) #cluster is using dedicated master nodes
      CLUSTER_USES_DEDICATED_MASTERS=1
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

if [ ${CLUSTER_USES_DEDICATED_MASTERS} -ne 0 ]; then
    MINIMUM_MASTER_NODES=2
    UNICAST_HOSTS='["master-node-0:9300","master-node-1:9300","master-node-2:9300"]'
else
    MINIMUM_MASTER_NODES=$(((DATANODE_COUNT/2)+1))
    UNICAST_HOSTS='['
    for i in $(seq 0 $((DATANODE_COUNT-1))); do
        UNICAST_HOSTS="$UNICAST_HOSTS\"data-node-$i:9300\","
    done
    UNICAST_HOSTS="${UNICAST_HOSTS%?}]"
fi

log "Bootstrapping an Elasticsearch $ES_VERSION cluster named '$CLUSTER_NAME' with minimum_master_nodes set to $MINIMUM_MASTER_NODES"
log "Cluster uses dedicated master nodes is set to $CLUSTER_USES_DEDICATED_MASTERS and unicast goes to $UNICAST_HOSTS"
log "Cluster install script is set to $INSTALL_PLUGIN"


#########################
# Installation steps as functions
#########################

# Format data disks (Find data disks then partition, format, and mount them as seperate drives)
format_data_disks()
{
    log "[format_data_disks] starting to RAID0 the attached disks"
    # using the -s paramater causing disks under /datadisks/* to be raid0'ed
    bash vm-disk-utils-0.1.sh -s
    log "[format_data_disks] finished RAID0'ing the attached disks"
}

# Configure Elasticsearch Data Disk Folder and Permissions
setup_data_disk()
{
    local RAIDDISK="/datadisks/disk1"
    log "[setup_data_disk] Configuring disk $RAIDDISK/elasticsearch/data"
    mkdir -p "$RAIDDISK/elasticsearch/data"
    chown -R elasticsearch:elasticsearch "$RAIDDISK/elasticsearch"
    chmod 755 "$RAIDDISK/elasticsearch"
}

# Install Oracle Java
install_java()
{
    log "[install_java] Adding apt repository for java 8"
    (add-apt-repository -y ppa:webupd8team/java || (sleep 15; add-apt-repository -y ppa:webupd8team/java))
    log "[install_java] updating apt-get"

    (apt-get -y update || (sleep 15; apt-get -y update)) > /dev/null
    log "[install_java] updated apt-get"
    echo debconf shared/accepted-oracle-license-v1-1 select true | sudo debconf-set-selections
    echo debconf shared/accepted-oracle-license-v1-1 seen true | sudo debconf-set-selections
    log "[install_java] Installing Java"
    (apt-get -y install oracle-java8-installer || (sleep 15; apt-get -y install oracle-java8-installer)) || (sudo rm /var/cache/oracle-jdk8-installer/jdk-*; sudo apt-get install)
    log "[install_java] Installed Java"
}

# Install Elasticsearch
install_es()
{
    if [[ "${ES_VERSION}" == \2* ]]; then
        DOWNLOAD_URL="https://download.elasticsearch.org/elasticsearch/release/org/elasticsearch/distribution/deb/elasticsearch/$ES_VERSION/elasticsearch-$ES_VERSION.deb?ultron=msft&gambit=azure"
    else
        DOWNLOAD_URL="https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-$ES_VERSION.deb"
    fi

    log "[install_es] Installing Elaticsearch Version - $ES_VERSION"
    log "[install_es] Download location - $DOWNLOAD_URL"
    sudo wget -q "$DOWNLOAD_URL" -O elasticsearch.deb
    log "[install_es] Downloaded elasticsearch $ES_VERSION"
    sudo dpkg -i elasticsearch.deb
    log "[install_es] Installing Elaticsearch Version - $ES_VERSION"
}

install_plugins()
{
    log "[install_plugins] Installing Plugins Shield, Marvel, Watcher"
    sudo /usr/share/elasticsearch/bin/plugin install license
    sudo /usr/share/elasticsearch/bin/plugin install shield
    sudo /usr/share/elasticsearch/bin/plugin install watcher
    sudo /usr/share/elasticsearch/bin/plugin install marvel-agent
    if dpkg --compare-versions "$ES_VERSION" ">=" "2.3.0"; then
      sudo /usr/share/elasticsearch/bin/plugin install graph
    fi

    log "[install_plugins] Start adding es_admin"
    sudo /usr/share/elasticsearch/bin/shield/esusers useradd "es_admin" -p "${USER_ADMIN_PWD}" -r admin
    log "[install_plugins] Finished adding es_admin"

    log "[install_plugins]  Start adding es_read"
    sudo /usr/share/elasticsearch/bin/shield/esusers useradd "es_read" -p "${USER_READ_PWD}" -r user
    log "[install_plugins]  Finished adding es_read"

    log "[install_plugins]  Start adding es_kibana"
    sudo /usr/share/elasticsearch/bin/shield/esusers useradd "es_kibana" -p "${USER_KIBANA4_PWD}" -r kibana4
    log "[install_plugins]  Finished adding es_kibina"

    log "[install_plugins]  Start adding es_kibana_server"
    sudo /usr/share/elasticsearch/bin/shield/esusers useradd "es_kibana_server" -p "${USER_KIBANA4_SERVER_PWD}" -r kibana4_server
    log "[install_plugins]  Finished adding es_kibana_server"

    echo "marvel.agent.enabled: true" >> /etc/elasticsearch/elasticsearch.yml
}

configure_elasticsearch_yaml()
{
    # Backup the current Elasticsearch configuration file
    mv /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.bak

    # Set cluster and machine names - just use hostname for our node.name
    echo "cluster.name: $CLUSTER_NAME" >> /etc/elasticsearch/elasticsearch.yml
    echo "node.name: ${HOSTNAME}" >> /etc/elasticsearch/elasticsearch.yml

    log "[configure_elasticsearch_yaml] Update configuration with data path list of $DATAPATH_CONFIG"
    echo "path.data: /datadisks/disk1/elasticsearch/data" >> /etc/elasticsearch/elasticsearch.yml

    # Configure discovery
    log "[configure_elasticsearch_yaml] Update configuration with hosts configuration of $UNICAST_HOSTS"
    echo "discovery.zen.ping.multicast.enabled: false" >> /etc/elasticsearch/elasticsearch.yml
    echo "discovery.zen.ping.unicast.hosts: $UNICAST_HOSTS" >> /etc/elasticsearch/elasticsearch.yml

    # Configure Elasticsearch node type
    log "[configure_elasticsearch_yaml] Configure master/client/data node type flags master-$MASTER_ONLY_NODE data-$DATA_NODE"

    if [ ${MASTER_ONLY_NODE} -ne 0 ]; then
        log "[configure_elasticsearch_yaml] Configure node as master only"
        echo "node.master: true" >> /etc/elasticsearch/elasticsearch.yml
        echo "node.data: false" >> /etc/elasticsearch/elasticsearch.yml
        # echo "marvel.agent.enabled: false" >> /etc/elasticsearch/elasticsearch.yml
    elif [ ${DATA_NODE} -ne 0 ]; then
        log "[configure_elasticsearch_yaml] Configure node as data only"
        echo "node.master: false" >> /etc/elasticsearch/elasticsearch.yml
        echo "node.data: true" >> /etc/elasticsearch/elasticsearch.yml
        # echo "marvel.agent.enabled: false" >> /etc/elasticsearch/elasticsearch.yml
    elif [ ${CLIENT_ONLY_NODE} -ne 0 ]; then
        log "[configure_elasticsearch_yaml] Configure node as data only"
        echo "node.master: false" >> /etc/elasticsearch/elasticsearch.yml
        echo "node.data: false" >> /etc/elasticsearch/elasticsearch.yml
        # echo "marvel.agent.enabled: false" >> /etc/elasticsearch/elasticsearch.yml
    else
        log "[configure_elasticsearch_yaml] Configure node for master and data"
        echo "node.master: true" >> /etc/elasticsearch/elasticsearch.yml
        echo "node.data: true" >> /etc/elasticsearch/elasticsearch.yml
    fi

    echo "discovery.zen.minimum_master_nodes: $MINIMUM_MASTER_NODES" >> /etc/elasticsearch/elasticsearch.yml
    echo "network.host: _non_loopback_" >> /etc/elasticsearch/elasticsearch.yml

    # Swap is disabled by default in Ubuntu Azure VMs
    # echo "bootstrap.mlockall: true" >> /etc/elasticsearch/elasticsearch.yml
}

install_ntp()
{
    log "[install_ntp] installing ntp deamon"
    apt-get -y install ntp
    ntpdate pool.ntp.org
    log "[install_ntp] installed ntp deamon and ntpdate"
}

install_monit()
{
    log "[install_monit] installing monit"
    apt-get -y install monit
    echo "set daemon 30" >> /etc/monit/monitrc
    echo "set httpd port 2812 and" >> /etc/monit/monitrc
    echo "    use address localhost" >> /etc/monit/monitrc
    echo "    allow localhost" >> /etc/monit/monitrc
    sudo touch /etc/monit/conf.d/elasticsearch.conf
    echo "check process elasticsearch with pidfile \"/var/run/elasticsearch/elasticsearch.pid\"" >> /etc/monit/conf.d/elasticsearch.conf
    echo "  group elasticsearch" >> /etc/monit/conf.d/elasticsearch.conf
    echo "  start program = \"/etc/init.d/elasticsearch start\"" >> /etc/monit/conf.d/elasticsearch.conf
    echo "  stop program = \"/etc/init.d/elasticsearch stop\"" >> /etc/monit/conf.d/elasticsearch.conf
    log "[install_monit] installed monit"
}

start_monit()
{
    log "[start_monit] starting monit"
    sudo /etc/init.d/monit start
    sudo monit start all
    log "[start_monit] started monit"
}

start_elasticsearch()
{
    #and... start the service
    log "[start_elasticsearch] Starting Elasticsearch on ${HOSTNAME}"
    update-rc.d elasticsearch defaults 95 10
    sudo service elasticsearch start
    log "[start_elasticsearch] complete elasticsearch setup and started"
}

configure_os_properties()
{
    log "[configure_os_properties] configuring operating system level configuration"
    # DNS Retry
    echo "options timeout:10 attempts:5" >> /etc/resolvconf/resolv.conf.d/head
    resolvconf -u

    # Increase maximum mmap count
    echo "vm.max_map_count = 262144" >> /etc/sysctl.conf

    #TODO: Move this to an init.d script so we can handle instance size increases
    ES_HEAP=`free -m |grep Mem | awk '{if ($2/2 >31744)  print 31744;else print $2/2;}'`
    log "[configure_os_properties] Configure elasticsearch heap size - $ES_HEAP"
    echo "ES_HEAP_SIZE=${ES_HEAP}m" >> /etc/default/elasticsearch

    # Verify this is necessary on azure
    # ML: 80% certain i verified this but will do so again
    #echo "elasticsearch    -    nofile    65536" >> /etc/security/limits.conf
    #echo "elasticsearch     -    memlock   unlimited" >> /etc/security/limits.conf
    #echo "session    required    pam_limits.so" >> /etc/pam.d/su
    #echo "session    required    pam_limits.so" >> /etc/pam.d/common-session
    #echo "session    required    pam_limits.so" >> /etc/pam.d/common-session-noninteractive
    #echo "session    required    pam_limits.so" >> /etc/pam.d/sudo
    log "[configure_os_properties] configured operating system level configuration"

}

port_forward()
{
    log "[port_forward] setting up port forwarding from 9201 to 9200"
    #redirects 9201 > 9200 locally
    #this to overcome a limitation in ARM where to vm loadbalancers can route on the same backed ports
    sudo iptables -t nat -I PREROUTING -p tcp --dport 9201 -j REDIRECT --to-ports 9200
    sudo iptables -t nat -I OUTPUT -p tcp -o lo --dport 9201 -j REDIRECT --to-ports 9200
}

start_walinuxagent()
{
    log "[start_walinuxagent] making sure the walinuxagent is running"
    sudo service walinuxagent start
}

#########################
# Instalation sequence
#########################


if service --status-all | grep -Fq 'elasticsearch'; then
  sudo service elasticsearch stop

  configure_elasticsearch_yaml

  sudo service elasticsearch start
  exit 0
fi

format_data_disks

setup_data_disk

start_walinuxagent

install_ntp

install_java

start_walinuxagent

install_es

if [ ${INSTALL_PLUGINS} -ne 0 ]; then
    install_plugins
fi

install_monit

configure_elasticsearch_yaml

configure_os_properties

start_monit

start_elasticsearch

port_forward

start_walinuxagent

ELAPSED_TIME=$(($SECONDS - $START_TIME))
PRETTY=$(printf '%dh:%dm:%ds\n' $(($ELAPSED_TIME/3600)) $(($ELAPSED_TIME%3600/60)) $(($ELAPSED_TIME%60)))

log "End execution of Elasticsearch script extension on ${HOSTNAME} in ${PRETTY}"
exit 0
