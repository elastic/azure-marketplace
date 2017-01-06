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

help()
{
    echo "This script installs Elasticsearch cluster on Ubuntu"
    echo "Parameters:"
    echo "-n elasticsearch cluster name"
    echo "-v elasticsearch version 1.5.0"
    echo "-p hostname prefix of nodes for unicast discovery"

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
    echo "-L <plugin;plugin> install additional plugins"

    echo "-j install azure cloud plugin for snapshot and restore"
    echo "-a set the default storage account for azure cloud plugin"
    echo "-k set the key for the default storage account for azure cloud plugin"

    echo "-h view this help content"
}
# Custom logging with time so we can easily relate running times, also log to separate file so order is guaranteed.
# The Script extension output the stdout/err buffer in intervals with duplicates.
log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/arm-install.log
}

log "Begin execution of Elasticsearch script extension on ${HOSTNAME}"
START_TIME=$SECONDS

export DEBIAN_FRONTEND=noninteractive

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
# Parameter handling
#########################

CLUSTER_NAME="elasticsearch"
NAMESPACE_PREFIX=""
ES_VERSION="2.0.0"
INSTALL_PLUGINS=0
INSTALL_ADDITIONAL_PLUGINS=""
CLIENT_ONLY_NODE=0
DATA_ONLY_NODE=0
MASTER_ONLY_NODE=0

CLUSTER_USES_DEDICATED_MASTERS=0
DATANODE_COUNT=0

MINIMUM_MASTER_NODES=3
UNICAST_HOSTS='["'"$NAMESPACE_PREFIX"'master-0:9300","'"$NAMESPACE_PREFIX"'master-1:9300","'"$NAMESPACE_PREFIX"'master-2:9300"]'

USER_ADMIN_PWD="changeME"
USER_READ_PWD="changeME"
USER_KIBANA4_PWD="changeME"
USER_KIBANA4_SERVER_PWD="changeME"

INSTALL_AZURECLOUD_PLUGIN=0
STORAGE_ACCOUNT=""
STORAGE_KEY=""

#Loop through options passed
while getopts :n:v:A:R:K:S:Z:p:a:k:L:xyzldjh optname; do
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
    z) #data node
      DATA_ONLY_NODE=1
      ;;
    l) #install plugins
      INSTALL_PLUGINS=1
      ;;
    L) #install additional plugins
      INSTALL_ADDITIONAL_PLUGINS="${OPTARG}"
      ;;
    d) #cluster is using dedicated master nodes
      CLUSTER_USES_DEDICATED_MASTERS=1
      ;;
    p) #namespace prefix for nodes
      NAMESPACE_PREFIX="${OPTARG}"
      ;;
    j) #install azure cloud plugin
      INSTALL_AZURECLOUD_PLUGIN=1
      ;;
    a) #azure storage account for azure cloud plugin
      STORAGE_ACCOUNT=${OPTARG}
      ;;
    k) #azure storage account key for azure cloud plugin
      STORAGE_KEY=${OPTARG}
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
    UNICAST_HOSTS='["'"$NAMESPACE_PREFIX"'master-0:9300","'"$NAMESPACE_PREFIX"'master-1:9300","'"$NAMESPACE_PREFIX"'master-2:9300"]'
else
    MINIMUM_MASTER_NODES=$(((DATANODE_COUNT/2)+1))
    UNICAST_HOSTS='['
    for i in $(seq 0 $((DATANODE_COUNT-1))); do
        UNICAST_HOSTS="$UNICAST_HOSTS\"${NAMESPACE_PREFIX}data-$i:9300\","
    done
    UNICAST_HOSTS="${UNICAST_HOSTS%?}]"
fi

log "Bootstrapping an Elasticsearch $ES_VERSION cluster named '$CLUSTER_NAME' with minimum_master_nodes set to $MINIMUM_MASTER_NODES"
log "Cluster uses dedicated master nodes is set to $CLUSTER_USES_DEDICATED_MASTERS and unicast goes to $UNICAST_HOSTS"
log "Cluster install plugins is set to $INSTALL_PLUGINS"


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
    (apt-get -yq install oracle-java8-installer || (sleep 15; apt-get -yq install oracle-java8-installer))
    command -v java >/dev/null 2>&1 || { sleep 15; sudo rm /var/cache/oracle-jdk8-installer/jdk-*; sudo apt-get install -f; }

    #if the previus did not install correctly we go nuclear, otherwise this loop will early exit
    for i in $(seq 30); do
      if $(command -v java >/dev/null 2>&1); then
        log "[install_java] Installed java!"
        return
      else
        sleep 5
        sudo rm /var/cache/oracle-jdk8-installer/jdk-*;
        sudo rm -f /var/lib/dpkg/info/oracle-java8-installer*
        sudo rm /etc/apt/sources.list.d/*java*
        sudo apt-get -yq purge oracle-java8-installer*
        sudo apt-get -yq autoremove
        sudo apt-get -yq clean
        (add-apt-repository -y ppa:webupd8team/java || (sleep 15; add-apt-repository -y ppa:webupd8team/java))
        sudo apt-get -yq update
        sudo apt-get -yq install --reinstall oracle-java8-installer
        log "[install_java] Seeing if java is Installed after nuclear retry ${i}/30"
      fi
    done
    command -v java >/dev/null 2>&1 || { log "Java did not get installed properly even after a retry and a forced installation" >&2; exit 50; }
}

# Install Elasticsearch
install_es()
{
    if [[ "${ES_VERSION}" == \2* ]]; then
        DOWNLOAD_URL="https://download.elasticsearch.org/elasticsearch/release/org/elasticsearch/distribution/deb/elasticsearch/$ES_VERSION/elasticsearch-$ES_VERSION.deb?ultron=msft&gambit=azure"
    elif [[ "${ES_VERSION}" == \5* ]]; then
        DOWNLOAD_URL="https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$ES_VERSION.deb?ultron=msft&gambit=azure"
    else
        DOWNLOAD_URL="https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-$ES_VERSION.deb"
    fi

    log "[install_es] Installing Elasticsearch Version - $ES_VERSION"
    log "[install_es] Download location - $DOWNLOAD_URL"
    sudo wget -q "$DOWNLOAD_URL" -O elasticsearch.deb
    log "[install_es] Downloaded elasticsearch $ES_VERSION"
    sudo dpkg -i elasticsearch.deb
    log "[install_es] Installed Elasticsearch Version - $ES_VERSION"

    log "[install_es] Disable Elasticsearch System-V style init scripts (will be using monit)"
    sudo update-rc.d elasticsearch disable
}

## Plugins
##----------------------------------

plugin_cmd()
{
    if [[ "${ES_VERSION}" == \5* ]]; then
      echo /usr/share/elasticsearch/bin/elasticsearch-plugin
    else
      echo /usr/share/elasticsearch/bin/plugin
    fi
}

install_plugins()
{
    if [[ "${ES_VERSION}" == \5* ]]; then
      sudo $(plugin_cmd) install x-pack --batch
    else
      log "[install_plugins] Installing X-Pack plugins Shield, Marvel, Watcher"
      sudo $(plugin_cmd) install license
      sudo $(plugin_cmd) install shield
      sudo $(plugin_cmd) install watcher
      sudo $(plugin_cmd) install marvel-agent
      if dpkg --compare-versions "$ES_VERSION" ">=" "2.3.0"; then
        log "[install_plugins] Installing X-Pack plugin Graph"
        sudo $(plugin_cmd) install graph
        log "[install_plugins] Installed X-Pack plugin Graph"
      fi
      log "[install_plugins] Installed X-Pack plugins Shield, Marvel, Watcher"
    fi

}

install_azure_cloud_plugin()
{
    log "[install_azure_cloud_plugin] Installing plugin Cloud-Azure"
    sudo $(plugin_cmd) install repository-azure
    log "[install_azure_cloud_plugin] Installed plugin Cloud-Azure"
}

install_additional_plugins()
{
    SKIP_PLUGINS="license shield watcher marvel-agent graph cloud-azure"
    log "[install_additional_plugins] Installing additional plugins"
    for PLUGIN in $(echo $INSTALL_ADDITIONAL_PLUGINS | tr ";" "\n")
    do
        if [[ $SKIP_PLUGINS =~ $PLUGIN ]]; then
            log "[install_additional_plugins] Skipping plugin $PLUGIN"
        else
            log "[install_additional_plugins] Installing plugin $PLUGIN"
            sudo $(plugin_cmd) install $PLUGIN
            log "[install_additional_plugins] Installed plugin $PLUGIN"
        fi
    done
}

## Security
##----------------------------------

security_cmd()
{
    if [[ "${ES_VERSION}" == \5* ]]; then
      echo /usr/share/elasticsearch/bin/x-pack/users
    else
      echo /usr/share/elasticsearch/bin/shield/esusers
    fi
}

apply_security_settings_2x()
{
    local SEC_FILE=/etc/elasticsearch/shield/roles.yml
    log "[install_plugins]  Check that $SEC_FILE contains kibana4 role"
    if ! sudo grep -q "kibana4:" "$SEC_FILE"; then
        log "[install_plugins]  No kibana4 role. Adding now"
        {
            echo -e ""
            echo -e "# kibana4 user role."
            echo -e "kibana4:"
            echo -e "  cluster:"
            echo -e "    - monitor"
            echo -e "  indices:"
            echo -e "    - names: '*'"
            echo -e "      privileges:"
            echo -e "        - view_index_metadata"
            echo -e "        - read"
            echo -e "    - names: '.kibana*'"
            echo -e "      privileges:"
            echo -e "        - manage"
            echo -e "        - read"
            echo -e "        - index"
        } >> $SEC_FILE
        log "[install_plugins]  kibana4 role added"
    fi
    log "[install_plugins]  Finished checking roles.yml for kibana4 role"

    log "[install_plugins] Start adding es_admin"
    sudo $(security_cmd) useradd "es_admin" -p "${USER_ADMIN_PWD}" -r admin
    log "[install_plugins] Finished adding es_admin"

    log "[install_plugins]  Start adding es_read"
    sudo $(security_cmd) useradd "es_read" -p "${USER_READ_PWD}" -r user
    log "[install_plugins]  Finished adding es_read"

    log "[install_plugins]  Start adding es_kibana"
    sudo $(security_cmd) useradd "es_kibana" -p "${USER_KIBANA4_PWD}" -r kibana4
    log "[install_plugins]  Finished adding es_kibana"

    log "[install_plugins]  Start adding es_kibana_server"
    sudo $(security_cmd) useradd "es_kibana_server" -p "${USER_KIBANA4_SERVER_PWD}" -r kibana4_server
    log "[install_plugins]  Finished adding es_kibana_server"
}

node_is_up()
{
  curl --output /dev/null --silent --head --fail http://localhost:9200 --user elastic:$1
  return $?
}
wait_for_started()
{
  for i in $(seq 30); do
    if $(node_is_up "changeme" || node_is_up "$USER_ADMIN_PWD"); then
      log "[wait_for_started] Node is up!"
      return
    else
      sleep 5
      log "[wait_for_started] Seeing if node is up for the after sleeping 5 seconds, retry ${i}/30"
    fi
  done
  log "[wait_for_started] never saw elasticsearch go up locally"
  exit 10
}

#since upserts of roles users CAN throw 409 conflicts we ignore these for now
#opened a tick on x-pack repos to handle this more gracefully later
curl_ignore_409 () {
    _curl_with_error_code "$@" | sed '$d'
}
_curl_with_error_code () {
    local curl_error_code http_code
    exec 17>&1
    http_code=$(curl --write-out '\n%{http_code}\n' "$@" | tee /dev/fd/17 | tail -n 1)
    curl_error_code=$?
    exec 17>&-
    if [ $http_code -eq 409 ]; then
      return 0
    fi
    if [ $curl_error_code -ne 0 ]; then
        return $curl_error_code
    fi
    if [ $http_code -ge 400 ] && [ $http_code -lt 600 ]; then
        echo "HTTP $http_code" >&2
        return 127
    fi
}

apply_security_settings()
{
    if node_is_up "$USER_ADMIN_PWD"; then
      log "[apply_security_settings] Can already ping node using user provided credentials, exiting early!"
    else
      log "[apply_security_settings] start updating roles and users"

      #update superuser `elastic` this takes the role of `es_admin` in 2.x clusters
      local ADMIN_JSON=$(printf '{"password": "%s"}\n' $USER_ADMIN_PWD)
      echo $ADMIN_JSON | curl_ignore_409 -XPUT -u elastic:changeme 'localhost:9200/_xpack/security/user/elastic/_password' -d @-
      if [[ $? != 0 ]]; then
        #Make sure another deploy did not already change the elastic password
        curl_ignore_409 -XGET -u elastic:$USER_ADMIN_PWD  'localhost:9200/'
        if [[ $? != 0 ]]; then
          log "[apply_security_settings] could not update the builtin elastic user"
          exit 10
        fi
      fi
      log "[apply_security_settings] updated builtin elastic superuser password"

      #update builtin `kibana` server account
      local KIBANA_JSON=$(printf '{"password": "%s"}\n' $USER_KIBANA4_SERVER_PWD)
      echo $KIBANA_JSON | curl_ignore_409 -XPUT -u elastic:$USER_ADMIN_PWD 'localhost:9200/_xpack/security/user/kibana/_password' -d @-
      if [[ $? != 0 ]];  then
        log "[apply_security_settings] could not update the builtin kibana user"
        exit 10
      fi
      log "[apply_security_settings] updated builtin kibana user password"

      # add `es_kibana` user with the new builtin [kibana_user, monitoring_user, reporting_user] roles
      local KIBANA_USER_JSON=$(printf '{"password": "%s", "roles":["kibana_user", "monitoring_user", "reporting_user"]}\n' $USER_KIBANA4_PWD)
      echo $KIBANA_USER_JSON | curl_ignore_409 -XPOST -u elastic:$USER_ADMIN_PWD 'localhost:9200/_xpack/security/user/es_kibana?pretty' -d @-
      if [[ $? != 0 ]]; then
        log "[apply_security_settings] could not add es_kibana"
        exit 10
      fi
      log "[apply_security_settings] added es_kibana account"

      #create a readonly role that mimmics the `user` role in shield for `es_read`
      curl_ignore_409 -XPOST -u elastic:$USER_ADMIN_PWD 'localhost:9200/_xpack/security/role/user?pretty' -d'
      {
        "cluster": [ "monitor" ],
        "indices": [
          {
            "names": [ "*" ],
            "privileges": [ "read", "monitor", "view_index_metadata" ]
          }
        ]
      }'
      if [[ $? != 0 ]]; then
        log "[apply_security_settings] could not create user role"
        exit 10
      fi
      log "[apply_security_settings] added user role"

      # add `es_read` user with the newly created `user` role
      local USER_JSON=$(printf '{"password": "%s", "roles":["user"]}\n' $USER_READ_PWD)
      echo $USER_JSON | curl_ignore_409 -XPOST -u elastic:$USER_ADMIN_PWD 'localhost:9200/_xpack/security/user/es_read?pretty' -d @-
      if [[ $? != 0 ]]; then
        log "[apply_security_settings] could not add es_read"
        exit 10
      fi
      log "[apply_security_settings] added es_read account"

      log "[apply_security_settings] updated roles and users"
    fi
}

## Configuration
##----------------------------------

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
    echo "discovery.zen.ping.unicast.hosts: $UNICAST_HOSTS" >> /etc/elasticsearch/elasticsearch.yml

    # Configure Elasticsearch node type
    log "[configure_elasticsearch_yaml] Configure master/client/data node type flags master-$MASTER_ONLY_NODE data-$DATA_ONLY_NODE"

    if [ ${MASTER_ONLY_NODE} -ne 0 ]; then
        log "[configure_elasticsearch_yaml] Configure node as master only"
        echo "node.master: true" >> /etc/elasticsearch/elasticsearch.yml
        echo "node.data: false" >> /etc/elasticsearch/elasticsearch.yml
        # echo "marvel.agent.enabled: false" >> /etc/elasticsearch/elasticsearch.yml
    elif [ ${DATA_ONLY_NODE} -ne 0 ]; then
        log "[configure_elasticsearch_yaml] Configure node as data only"
        echo "node.master: false" >> /etc/elasticsearch/elasticsearch.yml
        echo "node.data: true" >> /etc/elasticsearch/elasticsearch.yml
        # echo "marvel.agent.enabled: false" >> /etc/elasticsearch/elasticsearch.yml
    elif [ ${CLIENT_ONLY_NODE} -ne 0 ]; then
        log "[configure_elasticsearch_yaml] Configure node as client only"
        echo "node.master: false" >> /etc/elasticsearch/elasticsearch.yml
        echo "node.data: false" >> /etc/elasticsearch/elasticsearch.yml
        # echo "marvel.agent.enabled: false" >> /etc/elasticsearch/elasticsearch.yml
    else
        log "[configure_elasticsearch_yaml] Configure node as master and data"
        echo "node.master: true" >> /etc/elasticsearch/elasticsearch.yml
        echo "node.data: true" >> /etc/elasticsearch/elasticsearch.yml
    fi

    echo "discovery.zen.minimum_master_nodes: $MINIMUM_MASTER_NODES" >> /etc/elasticsearch/elasticsearch.yml

    if [[ "${ES_VERSION}" == \5* ]]; then
        echo "network.host: [_site_, _local_]" >> /etc/elasticsearch/elasticsearch.yml
    else
        echo "discovery.zen.ping.multicast.enabled: false" >> /etc/elasticsearch/elasticsearch.yml
        echo "network.host: _non_loopback_" >> /etc/elasticsearch/elasticsearch.yml
        echo "marvel.agent.enabled: true" >> /etc/elasticsearch/elasticsearch.yml
    fi

    echo "node.max_local_storage_nodes: 1" >> /etc/elasticsearch/elasticsearch.yml

    # Configure Azure Cloud plugin
    if [[ -n $STORAGE_ACCOUNT && -n $STORAGE_KEY ]]; then
        log "[configure_elasticsearch_yaml] Configure storage for Azure Cloud"
        echo "cloud.azure.storage.default.account: ${STORAGE_ACCOUNT}" >> /etc/elasticsearch/elasticsearch.yml
        echo "cloud.azure.storage.default.key: ${STORAGE_KEY}" >> /etc/elasticsearch/elasticsearch.yml
    fi

    # Swap is disabled by default in Ubuntu Azure VMs
    # echo "bootstrap.mlockall: true" >> /etc/elasticsearch/elasticsearch.yml
}

configure_elasticsearch()
{
    log "[configure_elasticsearch] configuring elasticsearch default configuration"
    local ES_HEAP=`free -m |grep Mem | awk '{if ($2/2 >31744)  print 31744;else print $2/2;}'`
    if [[ "${ES_VERSION}" == \5* ]]; then
      configure_elasticsearch5 $ES_HEAP
    else
      configure_elasticsearch2 $ES_HEAP
    fi
    log "[configure_elasticsearch] configured elasticsearch default configuration"
}
configure_elasticsearch2()
{
    log "[configure_elasticsearch] Configure elasticsearch 2.x heap size - $1"
    echo "ES_HEAP_SIZE=$1m" >> /etc/default/elasticsearch

    # Allow dots in field names in 2.4.0+
    if dpkg --compare-versions "$ES_VERSION" ">=" "2.4.0"; then
      log "[configure_elasticsearch] Configure allow dots in field names"
      echo "ES_JAVA_OPTS=-Dmapper.allow_dots_in_name=true" >> /etc/default/elasticsearch
    fi
}

configure_elasticsearch5()
{
    log "[configure_elasticsearch] Configure elasticsearch 5.x heap size - $1"
    echo "-Xmx$1m" >> /etc/elasticsearch/jvm.options
    echo "-Xms$1m" >> /etc/elasticsearch/jvm.options
}

configure_os_properties()
{
    log "[configure_os_properties] configuring operating system level configuration"
    # DNS Retry
    echo "options timeout:10 attempts:5" >> /etc/resolvconf/resolv.conf.d/head
    resolvconf -u

    # Increase maximum mmap count
    echo "vm.max_map_count = 262144" >> /etc/sysctl.conf

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

## Installation of dependencies
##----------------------------------

install_ntp()
{
    log "[install_ntp] installing ntp daemon"
    (apt-get -yq install ntp || (sleep 15; apt-get -yq install ntp))
    ntpdate pool.ntp.org
    log "[install_ntp] installed ntp daemon and ntpdate"
}

install_monit()
{
    log "[install_monit] installing monit"
    (apt-get -yq install monit || (sleep 15; apt-get -yq install monit))
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
    sudo monit reload # use the new configuration
    sudo monit start all
    log "[start_monit] started monit"
}

port_forward()
{
    log "[port_forward] setting up port forwarding from 9201 to 9200"
    #redirects 9201 > 9200 locally
    #this to overcome a limitation in ARM where to vm loadbalancers can route on the same backed ports
    sudo iptables -t nat -I PREROUTING -p tcp --dport 9201 -j REDIRECT --to-ports 9200
    sudo iptables -t nat -I OUTPUT -p tcp -o lo --dport 9201 -j REDIRECT --to-ports 9200

    #install iptables-persistent to restore configuration after reboot
    log "[port_forward] installing iptables-persistent"
    (apt-get -yq install iptables-persistent || (sleep 15; apt-get -yq install iptables-persistent))
    #persist the rules to file
    sudo service iptables-persistent save
    sudo service iptables-persistent start
    # add iptables-persistent to startup before elasticsearch
    sudo update-rc.d iptables-persistent defaults 90 15
    log "[port_forward] installed iptables-persistent"
    log "[port_forward] port forwarding configured"
}

#########################
# Installation sequence
#########################


# if elasticsearch is already installed assume this is a redeploy
# change yaml configuration and only restart the server when needed
if sudo monit status elasticsearch >& /dev/null; then

  configure_elasticsearch_yaml

  # restart elasticsearch if the configuration has changed
  cmp --silent /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.bak \
    || sudo monit restart elasticsearch

  exit 0
fi

format_data_disks

install_ntp

install_java

install_es

setup_data_disk

if [ ${INSTALL_PLUGINS} -ne 0 ]; then
    install_plugins
    # in 2.x we use the file realm so we can apply security config before boot up
    if [[ "${ES_VERSION}" == \2* ]]; then
        apply_security_settings_2x
    fi
fi

if [[ ! -z "${INSTALL_ADDITIONAL_PLUGINS// }" ]]; then
    install_additional_plugins
fi

if [ ${INSTALL_AZURECLOUD_PLUGIN} -ne 0 ]; then
    install_azure_cloud_plugin
fi

install_monit

configure_elasticsearch_yaml

configure_elasticsearch

configure_os_properties

start_monit

port_forward

# In 5.x we have to patch roles and users through the REST API which is a tad trickier
if [ ${INSTALL_PLUGINS} -ne 0 ]; then
    if [[ "${ES_VERSION}" == \5* ]]; then
        wait_for_started
        apply_security_settings
    fi
fi

ELAPSED_TIME=$(($SECONDS - $START_TIME))
PRETTY=$(printf '%dh:%dm:%ds\n' $(($ELAPSED_TIME/3600)) $(($ELAPSED_TIME%3600/60)) $(($ELAPSED_TIME%60)))

log "End execution of Elasticsearch script extension on ${HOSTNAME} in ${PRETTY}"
exit 0
