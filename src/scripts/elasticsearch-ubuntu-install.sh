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
    echo "-X enable anonymous access with cluster monitoring role (for health probes)"

    echo "-x configure as a dedicated master node"
    echo "-y configure as client only node (no master, no data)"
    echo "-z configure as data node (no master)"
    echo "-l install plugins"
    echo "-L <plugin;plugin> install additional plugins"
    echo "-C <yaml\nyaml> additional yaml configuration"

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
ES_VERSION="5.3.0"
INSTALL_PLUGINS=0
INSTALL_ADDITIONAL_PLUGINS=""
YAML_CONFIGURATION=""
MANDATORY_PLUGINS=""
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
ANONYMOUS_ACCESS=0

INSTALL_AZURECLOUD_PLUGIN=0
STORAGE_ACCOUNT=""
STORAGE_KEY=""

UBUNTU_VERSION=$(lsb_release -sr)

#Loop through options passed
while getopts :n:v:A:R:K:S:Z:p:a:k:L:C:Xxyzldjh optname; do
  log "Option $optname set"
  case $optname in
    n) #set cluster name
      CLUSTER_NAME="${OPTARG}"
      ;;
    v) #elasticsearch version number
      ES_VERSION="${OPTARG}"
      ;;
    A) #security admin pwd
      USER_ADMIN_PWD="${OPTARG}"
      ;;
    R) #security readonly pwd
      USER_READ_PWD="${OPTARG}"
      ;;
    K) #security kibana user pwd
      USER_KIBANA4_PWD="${OPTARG}"
      ;;
    S) #security kibana server pwd
      USER_KIBANA4_SERVER_PWD="${OPTARG}"
      ;;
    X) #anonymous access
      ANONYMOUS_ACCESS=1
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
    C) #additional yaml configuration
      YAML_CONFIGURATION="${OPTARG}"
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
      STORAGE_ACCOUNT="${OPTARG}"
      ;;
    k) #azure storage account key for azure cloud plugin
      STORAGE_KEY="${OPTARG}"
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
    log "[format_data_disks] checking node role"
    if [ ${MASTER_ONLY_NODE} -eq 1 ]; then
        log "[format_data_disks] master node, no data disks attached"
    elif [ ${CLIENT_ONLY_NODE} -eq 1 ]; then
        log "[format_data_disks] client node, no data disks attached"
    else
        log "[format_data_disks] data node, data disks may be attached"
        log "[format_data_disks] starting partition and format attached disks"
        # using the -s paramater causing disks under /datadisks/* to be raid0'ed
        bash vm-disk-utils-0.1.sh -s
        EXIT_CODE=$?
        if [ $EXIT_CODE -ne 0 ]; then
          log "[format_data_disks] returned non-zero exit code: $EXIT_CODE"
          exit $EXIT_CODE
        fi
        log "[format_data_disks] finished partition and format attached disks"
    fi
}

# Configure Elasticsearch Data Disk Folder and Permissions
setup_data_disk()
{
    if [ -d "/datadisks" ]; then
        local RAIDDISK="/datadisks/disk1"
        log "[setup_data_disk] Configuring disk $RAIDDISK/elasticsearch/data"
        mkdir -p "$RAIDDISK/elasticsearch/data"
        chown -R elasticsearch:elasticsearch "$RAIDDISK/elasticsearch"
        chmod 755 "$RAIDDISK/elasticsearch"
    elif [ ${MASTER_ONLY_NODE} -eq 0 -a ${CLIENT_ONLY_NODE} -eq 0 ]; then
        local TEMPDISK="/mnt"
        log "[setup_data_disk] Configuring disk $TEMPDISK/elasticsearch/data"
        mkdir -p "$TEMPDISK/elasticsearch/data"
        chown -R elasticsearch:elasticsearch "$TEMPDISK/elasticsearch"
        chmod 755 "$TEMPDISK/elasticsearch"
    else
        #If we do not find folders/disks in our data disk mount directory then use the defaults
        log "[setup_data_disk] Configured data directory does not exist for ${HOSTNAME}. using defaults"
    fi
}

# Check Data Disk Folder and Permissions
check_data_disk()
{
    if [ ${MASTER_ONLY_NODE} -eq 0 -a ${CLIENT_ONLY_NODE} -eq 0 ]; then
        log "[check_data_disk] data node checking data directory"
        if [ -d "/datadisks" ]; then
            log "[check_data_disk] Data disks attached and mounted at /datadisks"
        elif [ -d "/mnt/elasticsearch/data" ]; then
            log "[check_data_disk] Data directory at /mnt/elasticsearch/data"
        else
            #this could happen when the temporary disk is lost and a new one mounted
            local TEMPDISK="/mnt"
            log "[check_data_disk] No data directory at /mnt/elasticsearch/data dir"
            log "[setup_data_disk] Configuring disk $TEMPDISK/elasticsearch/data"
            mkdir -p "$TEMPDISK/elasticsearch/data"
            chown -R elasticsearch:elasticsearch "$TEMPDISK/elasticsearch"
            chmod 755 "$TEMPDISK/elasticsearch"
        fi
    fi
}

# Update the oracle-java8-installer to patch download of Java 8u151 to 8u162.
# 8u151 is no longer available for download.
# TODO: Remove this once oracle-java8-installer package is updated
install_update_java_package()
{
  apt-get -yq $@ install oracle-java8-installer || true \
  && pushd /var/lib/dpkg/info \
  && log "[install_update_java_package] Update oracle-java8-installer to 8u162" \
  && sed -i 's|JAVA_VERSION=8u151|JAVA_VERSION=8u162|' oracle-java8-installer.* \
  && sed -i 's|PARTNER_URL=http://download.oracle.com/otn-pub/java/jdk/8u151-b12/e758a0de34e24606bca991d704f6dcbf/|PARTNER_URL=http://download.oracle.com/otn-pub/java/jdk/8u162-b12/0da788060d494f5095bf8624735fa2f1/|' oracle-java8-installer.* \
  && sed -i 's|SHA256SUM_TGZ="c78200ce409367b296ec39be4427f020e2c585470c4eed01021feada576f027f"|SHA256SUM_TGZ="68ec82d47fd9c2b8eb84225b6db398a72008285fafc98631b1ff8d2229680257"|' oracle-java8-installer.* \
  && sed -i 's|J_DIR=jdk1.8.0_151|J_DIR=jdk1.8.0_162|' oracle-java8-installer.* \
  && popd \
  && log "[install_update_java_package] Updated oracle-java8-installer" \
  && apt-get -yq $@ install oracle-java8-installer
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
    (install_update_java_package || (sleep 15; install_update_java_package))
    command -v java >/dev/null 2>&1 || { sleep 15; sudo rm /var/cache/oracle-jdk8-installer/jdk-*; sudo apt-get install -f; }

    #if the previous did not install correctly we go nuclear, otherwise this loop will early exit
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
        sudo install_update_java_package --reinstall
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
      log "[install_plugins] Installing X-Pack plugins Security, Marvel, Watcher"
      sudo $(plugin_cmd) install license
      sudo $(plugin_cmd) install shield
      sudo $(plugin_cmd) install watcher
      sudo $(plugin_cmd) install marvel-agent
      log "[install_plugins] Installed X-Pack plugins Security, Marvel, Watcher"
      if dpkg --compare-versions "$ES_VERSION" ">=" "2.3.0"; then
        log "[install_plugins] Installing X-Pack plugin Graph"
        sudo $(plugin_cmd) install graph
        log "[install_plugins] Installed X-Pack plugin Graph"
      fi
    fi

}

install_azure_cloud_plugin()
{
    log "[install_azure_cloud_plugin] Installing plugin Cloud-Azure"
    if [[ "${ES_VERSION}" == \5* ]]; then
    	  sudo $(plugin_cmd) install repository-azure --batch
    else
    	  sudo $(plugin_cmd) install cloud-azure
    fi
    log "[install_azure_cloud_plugin] Installed plugin Cloud-Azure"
}

install_additional_plugins()
{
    SKIP_PLUGINS="license shield watcher marvel-agent graph cloud-azure repository-azure"
    log "[install_additional_plugins] Installing additional plugins"
    for PLUGIN in $(echo $INSTALL_ADDITIONAL_PLUGINS | tr ";" "\n")
    do
        if [[ $SKIP_PLUGINS =~ $PLUGIN ]]; then
            log "[install_additional_plugins] Skipping plugin $PLUGIN"
        else
            log "[install_additional_plugins] Installing plugin $PLUGIN"
            if [[ "${ES_VERSION}" == \5* ]]; then
                sudo $(plugin_cmd) install $PLUGIN --batch
                MANDATORY_PLUGINS+="$PLUGIN,"
            else
                sudo $(plugin_cmd) install $PLUGIN
            fi
            log "[install_additional_plugins] Installed plugin $PLUGIN"
        fi
    done
    log "[install_additional_plugins] Installed additional plugins"
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
    log "[apply_security_settings]  Check that $SEC_FILE contains kibana4 role"
    if ! sudo grep -q "kibana4:" "$SEC_FILE"; then
        log "[apply_security_settings]  No kibana4 role. Adding now"
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
        log "[apply_security_settings]  kibana4 role added"
    fi
    log "[apply_security_settings]  Finished checking roles.yml for kibana4 role"

    if [ ${ANONYMOUS_ACCESS} -ne 0 ]; then
      log "[apply_security_settings]  Check that $SEC_FILE contains anonymous_user role"
      if ! sudo grep -q "anonymous_user:" "$SEC_FILE"; then
          log "[apply_security_settings]  No anonymous_user role. Adding now"
          {
              echo -e ""
              echo -e "# anonymous user role."
              echo -e "anonymous_user:"
              echo -e "  cluster:"
              echo -e "    - cluster:monitor/main"
          } >> $SEC_FILE
          log "[apply_security_settings]  anonymous_user role added"
      fi
      log "[apply_security_settings]  Finished checking roles.yml for anonymous_user role"
    fi

    log "[apply_security_settings] Start adding es_admin"
    sudo $(security_cmd) useradd "es_admin" -p "${USER_ADMIN_PWD}" -r admin
    log "[instalapply_security_settingsl_plugins] Finished adding es_admin"

    log "[apply_security_settings]  Start adding es_read"
    sudo $(security_cmd) useradd "es_read" -p "${USER_READ_PWD}" -r user
    log "[apply_security_settings]  Finished adding es_read"

    log "[apply_security_settings]  Start adding es_kibana"
    sudo $(security_cmd) useradd "es_kibana" -p "${USER_KIBANA4_PWD}" -r kibana4
    log "[apply_security_settings]  Finished adding es_kibana"

    log "[apply_security_settings]  Start adding es_kibana_server"
    sudo $(security_cmd) useradd "es_kibana_server" -p "${USER_KIBANA4_SERVER_PWD}" -r kibana4_server
    log "[apply_security_settings]  Finished adding es_kibana_server"
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

      #create a readonly role that mimics the `user` role in the old shield plugin for es 2.x for `es_read`
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

      # create an anonymous_user role
      if [ ${ANONYMOUS_ACCESS} -ne 0 ]; then
        log "[apply_security_settings] create anonymous_user role"
        curl_ignore_409 -XPOST -u elastic:$USER_ADMIN_PWD 'localhost:9200/_xpack/security/role/anonymous_user?pretty' -d'
        {
          "cluster": [ "cluster:monitor/main" ]
        }'
        if [[ $? != 0 ]]; then
          log "[apply_security_settings] could not create anonymous_user role"
          exit 10
        fi
        log "[apply_security_settings] added anonymous_user role"
      fi

      log "[apply_security_settings] updated roles and users"
    fi
}

## Configuration
##----------------------------------

configure_elasticsearch_yaml()
{
    # Backup the current Elasticsearch configuration file
    mv /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak
    local ES_CONF=/etc/elasticsearch/elasticsearch.yml
    # Set cluster and machine names - just use hostname for our node.name
    echo "cluster.name: $CLUSTER_NAME" >> $ES_CONF
    echo "node.name: ${HOSTNAME}" >> $ES_CONF

    # Check if data disks are attached. If they are then use them, otherwise if this is a data node, use the temporary disk
    local DATAPATH_CONFIG=""
    if [ -d "/datadisks" ]; then
        DATAPATH_CONFIG="/datadisks/disk1/elasticsearch/data"
    elif [ ${MASTER_ONLY_NODE} -eq 0 -a ${CLIENT_ONLY_NODE} -eq 0 ]; then
        DATAPATH_CONFIG="/mnt/elasticsearch/data"
    fi

    if [ -n "$DATAPATH_CONFIG" ]; then
        log "[configure_elasticsearch_yaml] Update configuration with data path list of $DATAPATH_CONFIG"
        echo "path.data: $DATAPATH_CONFIG" >> $ES_CONF
    fi

    # Configure discovery
    log "[configure_elasticsearch_yaml] Update configuration with hosts configuration of $UNICAST_HOSTS"
    echo "discovery.zen.ping.unicast.hosts: $UNICAST_HOSTS" >> $ES_CONF

    # Configure Elasticsearch node type
    log "[configure_elasticsearch_yaml] Configure master/client/data node type flags master-$MASTER_ONLY_NODE data-$DATA_ONLY_NODE"

    if [ ${MASTER_ONLY_NODE} -ne 0 ]; then
        log "[configure_elasticsearch_yaml] Configure node as master only"
        echo "node.master: true" >> $ES_CONF
        echo "node.data: false" >> $ES_CONF
        # echo "marvel.agent.enabled: false" >> $ES_CONF
    elif [ ${DATA_ONLY_NODE} -ne 0 ]; then
        log "[configure_elasticsearch_yaml] Configure node as data only"
        echo "node.master: false" >> $ES_CONF
        echo "node.data: true" >> $ES_CONF
        # echo "marvel.agent.enabled: false" >> $ES_CONF
    elif [ ${CLIENT_ONLY_NODE} -ne 0 ]; then
        log "[configure_elasticsearch_yaml] Configure node as client only"
        echo "node.master: false" >> $ES_CONF
        echo "node.data: false" >> $ES_CONF
        # echo "marvel.agent.enabled: false" >> $ES_CONF
    else
        log "[configure_elasticsearch_yaml] Configure node as master and data"
        echo "node.master: true" >> $ES_CONF
        echo "node.data: true" >> $ES_CONF
    fi

    echo "discovery.zen.minimum_master_nodes: $MINIMUM_MASTER_NODES" >> $ES_CONF

    if [[ "${ES_VERSION}" == \5* ]]; then
        echo "network.host: [_site_, _local_]" >> $ES_CONF
    else
        echo "discovery.zen.ping.multicast.enabled: false" >> $ES_CONF
        echo "network.host: _non_loopback_" >> $ES_CONF
        echo "marvel.agent.enabled: true" >> $ES_CONF
    fi

    echo "node.max_local_storage_nodes: 1" >> $ES_CONF

    # Configure mandatory plugins
    if [[ -n "${MANDATORY_PLUGINS}" ]]; then
        log "[configure_elasticsearch_yaml] Set plugin.mandatory to $MANDATORY_PLUGINS"
        echo "plugin.mandatory: ${MANDATORY_PLUGINS%?}" >> $ES_CONF
    fi

    # Configure Azure Cloud plugin
    if [[ -n "$STORAGE_ACCOUNT" && -n "$STORAGE_KEY" ]]; then
        log "[configure_elasticsearch_yaml] Configure storage for Azure Cloud"
        echo "cloud.azure.storage.default.account: ${STORAGE_ACCOUNT}" >> $ES_CONF
        echo "cloud.azure.storage.default.key: ${STORAGE_KEY}" >> $ES_CONF
    fi

    # Configure Anonymous access
    if [ ${ANONYMOUS_ACCESS} -ne 0 ]; then
      if [[ "${ES_VERSION}" == \5* ]]; then
        {
            echo -e ""
            echo -e "# anonymous access"
            echo -e "xpack.security.authc:"
            echo -e "  anonymous:"
            echo -e "    username: anonymous_user"
            echo -e "    roles: anonymous_user"
            echo -e "    authz_exception: false"
            echo -e ""
        } >> $ES_CONF
      else
        {
            echo -e ""
            echo -e "# anonymous access"
            echo -e "shield.authc:"
            echo -e "  anonymous:"
            echo -e "    username: anonymous_user"
            echo -e "    roles: anonymous_user"
            echo -e "    authz_exception: false"
            echo -e ""
        } >> $ES_CONF
      fi
    fi

    # Additional yaml configuration
    if [[ -n "$YAML_CONFIGURATION" ]]; then
        log "[configure_elasticsearch_yaml] include additional yaml configuration"

        local SKIP_LINES="cluster.name node.name path.data discovery.zen.ping.unicast.hosts "
        SKIP_LINES+="node.master node.data discovery.zen.minimum_master_nodes network.host "
        SKIP_LINES+="discovery.zen.ping.multicast.enabled marvel.agent.enabled "
        SKIP_LINES+="node.max_local_storage_nodes plugin.mandatory cloud.azure.storage.default.account "
        SKIP_LINES+="cloud.azure.storage.default.key xpack.security.authc shield.authc"
        local SKIP_REGEX="^\s*("$(echo $SKIP_LINES | tr " " "|" | sed 's/\./\\\./g')")"
        IFS=$'\n'
        for LINE in $(echo -e "$YAML_CONFIGURATION")
        do
            if [[ -n "$LINE" ]]; then
                if [[ $LINE =~ $SKIP_REGEX ]]; then
                    log "[configure_elasticsearch_yaml] Skipping line '$LINE'"
                else
                    log "[configure_elasticsearch_yaml] Adding line '$LINE' to $ES_CONF"
                    echo -e "$LINE" >> $ES_CONF
                fi
            fi
        done
        unset IFS
        log "[configure_elasticsearch_yaml] included additional yaml configuration"
        log "[configure_elasticsearch_yaml] run yaml lint on configuration"
        install_yamllint
        LINT=$(yamllint -d "{extends: relaxed, rules: {key-duplicates: {level: error}}}" $ES_CONF; exit ${PIPESTATUS[0]})
        EXIT_CODE=$?
        log "[configure_elasticsearch_yaml] ran yaml lint (exit code $EXIT_CODE) $LINT"
        if [ $EXIT_CODE -ne 0 ]; then
            log "[configure_elasticsearch_yaml] errors in yaml configuration. exiting"
            exit 11
        fi
    fi

    # Swap is disabled by default in Ubuntu Azure VMs, no harm in adding memory lock
    # if dpkg --compare-versions "$ES_VERSION" ">=" "2.4.0"; then
    #     log "[configure_elasticsearch_yaml] Setting bootstrap.memory_lock: true"
    #     echo "bootstrap.memory_lock: true" >> $ES_CONF
    # else
    #     log "[configure_elasticsearch_yaml] Setting bootstrap.mlockall: true"
    #     echo "bootstrap.mlockall: true" >> $ES_CONF
    # fi
}

configure_elasticsearch()
{
    log "[configure_elasticsearch] configuring elasticsearch default configuration"
    local ES_HEAP=`free -m |grep Mem | awk '{if ($2/2 >31744) print 31744;else print int($2/2+0.5);}'`
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

install_yamllint()
{
    log "[install_yamllint] installing yamllint"
    if [[ "${UBUNTU_VERSION}" == "16"* ]]; then
      (apt-get -yq install yamllint || (sleep 15; apt-get -yq install yamllint))
    else
      # Install yamllint via pip for Ubuntu 14.04
      (apt-get -yq install python-pip || (sleep 15; apt-get -yq install python-pip))
      pip install yamllint
    fi
    log "[install_yamllint] installed yamllint"
}

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

    # iptables-persistent is different on 16 compared to 14
    if [[ "${UBUNTU_VERSION}" == "16"* ]]; then
      sudo service netfilter-persistent save
      sudo service netfilter-persistent start
      # add netfilter-persistent to startup before elasticsearch
      sudo update-rc.d netfilter-persistent defaults 90 15
    else
      #persist the rules to file
      sudo service iptables-persistent save
      sudo service iptables-persistent start
      # add iptables-persistent to startup before elasticsearch
      sudo update-rc.d iptables-persistent defaults 90 15
    fi

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

  # if this is a data node using temp disk, check existence and permissions
  check_data_disk

  # restart elasticsearch if the configuration has changed
  cmp --silent /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.bak \
    || sudo monit restart elasticsearch

  exit 0
fi

format_data_disks

log "[apt-get] updating apt-get"
(sudo apt-get -y update || (sleep 15; sudo apt-get -y update)) > /dev/null
log "[apt-get] updated apt-get"

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
