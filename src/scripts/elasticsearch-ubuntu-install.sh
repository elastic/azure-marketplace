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
    echo "This script installs Elasticsearch cluster on Ubuntu"
    echo "Parameters:"
    echo "-n elasticsearch cluster name"
    echo "-v elasticsearch version e.g. 6.2.2"
    echo "-p hostname prefix of nodes for unicast discovery"
    echo "-m heap size in megabytes to allocate to JVM"

    echo "-d cluster uses dedicated masters"
    echo "-Z <number of nodes> hint to the install script how many data nodes we are provisioning"

    echo "-A admin password"
    echo "-R read password"
    echo "-K kibana user password"
    echo "-S logstash_system user password"
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
  log "${HOSTNAME} found in /etc/hosts"
else
  log "${HOSTNAME} not found in /etc/hosts"
  # Append it to the hsots file if not there
  echo "127.0.0.1 ${HOSTNAME}" >> /etc/hosts
  log "hostname ${HOSTNAME} added to /etc/hosts"
fi

#########################
# Parameter handling
#########################

CLUSTER_NAME="elasticsearch"
NAMESPACE_PREFIX=""
ES_VERSION="6.2.2"
ES_HEAP=0
INSTALL_XPACK=0
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

USER_ADMIN_PWD="changeme"
USER_READ_PWD="changeme"
USER_KIBANA_PWD="changeme"
USER_LOGSTASH_PWD="changeme"
BOOTSTRAP_PASSWORD="changeme"
SEED_PASSWORD="changeme"
ANONYMOUS_ACCESS=0

INSTALL_AZURECLOUD_PLUGIN=0
STORAGE_ACCOUNT=""
STORAGE_KEY=""

#Loop through options passed
while getopts :n:m:v:A:R:K:S:Z:p:a:k:L:C:B:Xxyzldjh optname; do
  log "Option $optname set"
  case $optname in
    n) #set cluster name
      CLUSTER_NAME="${OPTARG}"
      ;;
    v) #elasticsearch version number
      ES_VERSION="${OPTARG}"
      ;;
    m) #heap_size
      ES_HEAP=${OPTARG}
      ;;
    A) #security admin pwd
      USER_ADMIN_PWD="${OPTARG}"
      ;;
    R) #security readonly pwd
      USER_READ_PWD="${OPTARG}"
      ;;
    K) #security kibana user pwd
      USER_KIBANA_PWD="${OPTARG}"
      ;;
    S) #security logstash_system user pwd
      USER_LOGSTASH_PWD="${OPTARG}"
      ;;
    B) #bootstrap password
      BOOTSTRAP_PASSWORD="${OPTARG}"
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
    l) #install X-Pack
      INSTALL_XPACK=1
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

if [[ "${ES_VERSION}" == \6* && ${INSTALL_XPACK} -ne 0 ]]; then
    log "using bootstrap password as the seed password"
    SEED_PASSWORD="$BOOTSTRAP_PASSWORD"
fi

log "Bootstrapping an Elasticsearch $ES_VERSION cluster named '$CLUSTER_NAME' with minimum_master_nodes set to $MINIMUM_MASTER_NODES"
log "Cluster uses dedicated master nodes is set to $CLUSTER_USES_DEDICATED_MASTERS and unicast goes to $UNICAST_HOSTS"
log "Cluster install X-Pack plugin is set to $INSTALL_XPACK"

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

# Update the oracle-java8-installer to patch download of Java 8u161 to 8u172.
# 8u161 is no longer available for download.
# TODO: Remove this once oracle-java8-installer package is updated
install_java_package()
{
  apt-get -yq $@ install oracle-java8-installer || true \
  && pushd /var/lib/dpkg/info \
  && log "[install_java_package] Update oracle-java8-installer to 8u172" \
  && sed -i 's|JAVA_VERSION=8u161|JAVA_VERSION=8u172|' oracle-java8-installer.* \
  && sed -i 's|PARTNER_URL=http://download.oracle.com/otn-pub/java/jdk/8u161-b12/2f38c3b165be4555a1fa6e98c45e0808/|PARTNER_URL=http://download.oracle.com/otn-pub/java/jdk/8u172-b11/a58eab1ec242421181065cdc37240b08/|' oracle-java8-installer.* \
  && sed -i 's|SHA256SUM_TGZ="6dbc56a0e3310b69e91bb64db63a485bd7b6a8083f08e48047276380a0e2021e"|SHA256SUM_TGZ="28a00b9400b6913563553e09e8024c286b506d8523334c93ddec6c9ec7e9d346"|' oracle-java8-installer.* \
  && sed -i 's|J_DIR=jdk1.8.0_161|J_DIR=jdk1.8.0_172|' oracle-java8-installer.* \
  && popd \
  && log "[install_java_package] Updated oracle-java8-installer" \
  && apt-get -yq $@ install oracle-java8-installer
}

# Install Oracle Java
install_java()
{
  log "[install_java] Update apt"
  sudo apt-get update

  log "[install_java] Installing OpenJDK 8"
  sudo apt-get install openjdk-8-jre -y
  command -v java >/dev/null 2>&1 || { sleep 15; sudo apt autoremove openjdk-8-jre -y; sudo apt-get install openjdk-8-jre -y; }

  #if the previus did not install correctly we go nuclear, otherwise this loop will early exit
  for i in $(seq 30); do
    if $(command -v java >/dev/null 2>&1); then
      log "[install_java] Installed java!"
      return
    else
      sleep 5
      sudo apt autoremove openjdk-8-jre -y 
      sudo apt-get install openjdk-8-jre -y
      log "[install_java] Seeing if java is Installed after nuclear retry ${i}/30"
    fi
  done
  command -v java >/dev/null 2>&1 || { log "Java did not get installed properly even after a retry and a forced installation" >&2; exit 50; }
}

# Install Elasticsearch
install_es()
{
    DOWNLOAD_URL="https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$ES_VERSION.deb?ultron=msft&gambit=azure"

    log "[install_es] Installing Elasticsearch $ES_VERSION"
    log "[install_es] Download location - $DOWNLOAD_URL"
    wget --retry-connrefused --waitretry=1 -q "$DOWNLOAD_URL" -O elasticsearch.deb
    local EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        log "[install_es] Error downloading Elasticsearch $ES_VERSION"
        exit $EXIT_CODE
    fi
    log "[install_es] Downloaded Elasticsearch $ES_VERSION"
    dpkg -i elasticsearch.deb
    log "[install_es] Installed Elasticsearch $ES_VERSION"
    log "[install_es] Disable Elasticsearch System-V style init scripts (will be using monit)"
    update-rc.d elasticsearch disable
}

## Plugins
##----------------------------------

plugin_cmd()
{
    echo /usr/share/elasticsearch/bin/elasticsearch-plugin
}

install_xpack()
{
    log "[install_xpack] Installing X-Pack plugins"
    $(plugin_cmd) install x-pack --batch
    log "[install_xpack] Installed X-Pack plugins"
}

install_azure_cloud_plugin()
{
    log "[install_azure_cloud_plugin] Installing plugin Cloud-Azure"
    $(plugin_cmd) install repository-azure --batch
    log "[install_azure_cloud_plugin] Installed plugin Cloud-Azure"
}

install_additional_plugins()
{
    SKIP_PLUGINS="license shield watcher marvel-agent graph cloud-azure x-pack repository-azure"
    log "[install_additional_plugins] Installing additional plugins"
    for PLUGIN in $(echo $INSTALL_ADDITIONAL_PLUGINS | tr ";" "\n")
    do
        if [[ $SKIP_PLUGINS =~ $PLUGIN ]]; then
            log "[install_additional_plugins] Skipping plugin $PLUGIN"
        else
            log "[install_additional_plugins] Installing plugin $PLUGIN"
            $(plugin_cmd) install $PLUGIN --batch
            log "[install_additional_plugins] Add plugin $PLUGIN to mandatory plugins"
            MANDATORY_PLUGINS+="$PLUGIN,"
            log "[install_additional_plugins] Installed plugin $PLUGIN"
        fi
    done
    log "[install_additional_plugins] Installed additional plugins"
}

## Security
##----------------------------------

security_cmd()
{
    echo /usr/share/elasticsearch/bin/x-pack/users
}

node_is_up()
{
  curl --output /dev/null --silent --head --fail http://localhost:9200 -u elastic:$1 -H 'Content-Type: application/json'
  return $?
}

elastic_user_exists()
{
  local USER_TYPENAME curl_error_code http_code
  if [[ "${ES_VERSION}" == \5* ]]; then
    USER_TYPENAME="reserved-user"
  else
    USER_TYPENAME="doc"
  fi

  exec 17>&1
  http_code=$(curl -H 'Content-Type: application/json' --write-out '\n%{http_code}\n' http://localhost:9200/.security/$USER_TYPENAME/elastic -u elastic:$1 | tee /dev/fd/17 | tail -n 1)
  curl_error_code=$?
  exec 17>&-
  if [ $http_code -eq 200 ]; then
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

wait_for_started()
{
  local TOTAL_RETRIES=60
  for i in $(seq $TOTAL_RETRIES); do
    if $(node_is_up "$SEED_PASSWORD" || node_is_up "$USER_ADMIN_PWD"); then
      log "[wait_for_started] Node is up!"
      return
    else
      sleep 5
      log "[wait_for_started] Seeing if node is up after sleeping 5 seconds, retry ${i}/$TOTAL_RETRIES"
    fi
  done
  log "[wait_for_started] never saw elasticsearch go up locally"
  exit 10
}

# since upserts of roles users CAN throw 409 conflicts we ignore these for now
# opened an issue on x-pack repos to handle this more gracefully later
curl_ignore_409 () {
    _curl_with_error_code "$@" | sed '$d'
}

_curl_with_error_code () {
    local curl_error_code http_code
    exec 17>&1
    http_code=$(curl -H 'Content-Type: application/json' --write-out '\n%{http_code}\n' "$@" | tee /dev/fd/17 | tail -n 1)
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
    # if the node is up, check that the elastic user exists in the .security index if
    # the elastic user password is the same as the bootstrap password.
    if [[ $(node_is_up "$USER_ADMIN_PWD") && ("$USER_ADMIN_PWD" != "$SEED_PASSWORD" || $(elastic_user_exists "$USER_ADMIN_PWD")) ]]; then
      log "[apply_security_settings] Can already ping node using user provided credentials, exiting early!"
    else
      log "[apply_security_settings] start updating roles and users"

      local XPACK_USER_ENDPOINT="http://localhost:9200/_xpack/security/user"
      local XPACK_ROLE_ENDPOINT="http://localhost:9200/_xpack/security/role"

      #update builtin `elastic` account.
      local ADMIN_JSON=$(printf '{"password":"%s"}\n' $USER_ADMIN_PWD)
      echo $ADMIN_JSON | curl_ignore_409 -XPUT -u "elastic:$SEED_PASSWORD" "$XPACK_USER_ENDPOINT/elastic/_password" -d @-
      if [[ $? != 0 ]]; then
        #Make sure another deploy did not already change the elastic password
        curl_ignore_409 -XGET -u "elastic:$USER_ADMIN_PWD" 'http://localhost:9200/'
        if [[ $? != 0 ]]; then
          log "[apply_security_settings] could not update the builtin elastic user"
          exit 10
        fi
      fi
      log "[apply_security_settings] updated builtin elastic superuser password"

      #update builtin `kibana` account
      local KIBANA_JSON=$(printf '{"password":"%s"}\n' $USER_KIBANA_PWD)
      echo $KIBANA_JSON | curl_ignore_409 -XPUT -u "elastic:$USER_ADMIN_PWD" "$XPACK_USER_ENDPOINT/kibana/_password" -d @-
      if [[ $? != 0 ]];  then
        log "[apply_security_settings] could not update the builtin kibana user"
        exit 10
      fi
      log "[apply_security_settings] updated builtin kibana user password"

      if dpkg --compare-versions "$ES_VERSION" ">=" "5.2.0"; then
        #update builtin `logstash_system` account
        local LOGSTASH_JSON=$(printf '{"password":"%s"}\n' $USER_LOGSTASH_PWD)
        echo $LOGSTASH_JSON | curl_ignore_409 -XPUT -u "elastic:$USER_ADMIN_PWD" "$XPACK_USER_ENDPOINT/logstash_system/_password" -d @-
        if [[ $? != 0 ]];  then
          log "[apply_security_settings] could not update the builtin logstash_system user"
          exit 10
        fi
        log "[apply_security_settings] updated builtin logstash_system user password"
      fi

      #create a readonly role that mimics the `user` role in the old shield plugin
      curl_ignore_409 -XPOST -u "elastic:$USER_ADMIN_PWD" "$XPACK_ROLE_ENDPOINT/user" -d'
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
      local USER_JSON=$(printf '{"password":"%s","roles":["user"]}\n' $USER_READ_PWD)
      echo $USER_JSON | curl_ignore_409 -XPOST -u "elastic:$USER_ADMIN_PWD" "$XPACK_USER_ENDPOINT/es_read" -d @-
      if [[ $? != 0 ]]; then
        log "[apply_security_settings] could not add es_read"
        exit 10
      fi
      log "[apply_security_settings] added es_read account"

      # create an anonymous_user role
      if [ ${ANONYMOUS_ACCESS} -ne 0 ]; then
        log "[apply_security_settings] create anonymous_user role"
        curl_ignore_409 -XPOST -u "elastic:$USER_ADMIN_PWD" "$XPACK_ROLE_ENDPOINT/anonymous_user" -d'
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

setup_bootstrap_password()
{
  log "[setup_bootstrap_password] adding bootstrap.password to keystore"
  echo "$BOOTSTRAP_PASSWORD" | /usr/share/elasticsearch/bin/elasticsearch-keystore add bootstrap.password -xf
  log "[setup_bootstrap_password] added bootstrap.password to keystore"
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

    # put log files on the OS disk in a writable location
    echo "path.logs: /var/log/elasticsearch" >> $ES_CONF

    # Check if data disks are attached. If they are then use them. Otherwise
    # 1. if this is a data node, use the temporary disk with all the caveats that come with using ephemeral storage for data
    #    https://docs.microsoft.com/en-us/azure/virtual-machines/windows/about-disks-and-vhds#temporary-disk
    # 2. for any other node, use the OS disk
    local DATAPATH_CONFIG="/var/lib/elasticsearch"
    if [ -d "/datadisks" ]; then
        DATAPATH_CONFIG="/datadisks/disk1/elasticsearch/data"
    elif [ ${MASTER_ONLY_NODE} -eq 0 -a ${CLIENT_ONLY_NODE} -eq 0 ]; then
        DATAPATH_CONFIG="/mnt/elasticsearch/data"
    fi

    # configure path.data
    log "[configure_elasticsearch_yaml] Update configuration with data path list of $DATAPATH_CONFIG"
    echo "path.data: $DATAPATH_CONFIG" >> $ES_CONF

    # Configure discovery
    log "[configure_elasticsearch_yaml] Update configuration with hosts configuration of $UNICAST_HOSTS"
    echo "discovery.zen.ping.unicast.hosts: $UNICAST_HOSTS" >> $ES_CONF

    # Configure Elasticsearch node type
    log "[configure_elasticsearch_yaml] Configure master/client/data node type flags only master-$MASTER_ONLY_NODE only data-$DATA_ONLY_NODE"

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
    echo "network.host: [_site_, _local_]" >> $ES_CONF
    echo "node.max_local_storage_nodes: 1" >> $ES_CONF

    # Configure mandatory plugins
    if [[ -n "${MANDATORY_PLUGINS}" ]]; then
        log "[configure_elasticsearch_yaml] Set plugin.mandatory to $MANDATORY_PLUGINS"
        echo "plugin.mandatory: ${MANDATORY_PLUGINS%?}" >> $ES_CONF
    fi

    # Configure Azure Cloud plugin
    if [[ -n "$STORAGE_ACCOUNT" && -n "$STORAGE_KEY" ]]; then
      if [[ "${ES_VERSION}" == \6* ]]; then
        log "[configure_elasticsearch_yaml] Configure storage for Azure Cloud in keystore"
        echo "$STORAGE_ACCOUNT" | /usr/share/elasticsearch/bin/elasticsearch-keystore add azure.client.default.account -xf
        echo "$STORAGE_KEY" | /usr/share/elasticsearch/bin/elasticsearch-keystore add azure.client.default.key -xf
      else
        log "[configure_elasticsearch_yaml] Configure storage for Azure Cloud in $ES_CONF"
        echo "cloud.azure.storage.default.account: ${STORAGE_ACCOUNT}" >> $ES_CONF
        echo "cloud.azure.storage.default.key: ${STORAGE_KEY}" >> $ES_CONF
      fi
    fi

    # Configure Anonymous access
    if [ ${ANONYMOUS_ACCESS} -ne 0 ]; then
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
    log "[configure_elasticsearch_yaml] Setting bootstrap.memory_lock: true"
    echo "bootstrap.memory_lock: true" >> $ES_CONF
}

configure_elasticsearch()
{
    log "[configure_elasticsearch] configuring elasticsearch default configuration"

    if [[ "$ES_HEAP" -eq "0" ]]; then
      log "[configure_elasticsearch] configuring heap size from available memory"
      ES_HEAP=`free -m |grep Mem | awk '{if ($2/2 >31744) print 31744;else print int($2/2+0.5);}'`
    fi

    log "[configure_elasticsearch] configure elasticsearch heap size - $ES_HEAP"
    sed -i -e "s/^\-Xmx.*/-Xmx${ES_HEAP}m/" /etc/elasticsearch/jvm.options
    sed -i -e "s/^\-Xms.*/-Xms${ES_HEAP}m/" /etc/elasticsearch/jvm.options
    log "[configure_elasticsearch] configured elasticsearch default configuration"
}

configure_os_properties()
{
    log "[configure_os_properties] configuring operating system level configuration"
    # DNS Retry
    echo "options timeout:10 attempts:5" >> /etc/resolvconf/resolv.conf.d/head
    resolvconf -u

    # Increase maximum mmap count
    echo "vm.max_map_count = 262144" >> /etc/sysctl.conf

    # Update pam_limits for bootstrap memory lock
    echo "# allow user 'elasticsearch' mlockall" >> /etc/security/limits.conf
    echo "elasticsearch soft memlock unlimited" >> /etc/security/limits.conf
    echo "elasticsearch hard memlock unlimited" >> /etc/security/limits.conf

    # Required for bootstrap memory lock
    echo "MAX_LOCKED_MEMORY=unlimited" >> /etc/default/elasticsearch

    # Maximum number of open files for elasticsearch user
    echo "elasticsearch - nofile 65536" >> /etc/security/limits.conf

    # Ubuntu ignores the limits.conf file for processes started by init.d by default, so enable them
    echo "session    required   pam_limits.so" >> /etc/pam.d/su

    log "[configure_os_properties] configured operating system level configuration"
}

## Installation of dependencies
##----------------------------------

install_yamllint()
{
    log "[install_yamllint] installing yamllint"
    (apt-get -yq install yamllint || (sleep 15; apt-get -yq install yamllint))
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
    touch /etc/monit/conf.d/elasticsearch.conf
    echo "check process elasticsearch with pidfile \"/var/run/elasticsearch/elasticsearch.pid\"" >> /etc/monit/conf.d/elasticsearch.conf
    echo "  group elasticsearch" >> /etc/monit/conf.d/elasticsearch.conf
    echo "  start program = \"/etc/init.d/elasticsearch start\"" >> /etc/monit/conf.d/elasticsearch.conf
    echo "  stop program = \"/etc/init.d/elasticsearch stop\"" >> /etc/monit/conf.d/elasticsearch.conf

    # comment out include /etc/monit/conf-enabled/* as not needed. Prevents unuseful warning to stderr
    sed -i 's|\s*include /etc/monit/conf-enabled/*|# include /etc/monit/conf-enabled/*|' /etc/monit/monitrc

    log "[install_monit] installed monit"
}

start_monit()
{
    log "[start_monit] starting monit"
    /etc/init.d/monit start
    monit reload # use the new configuration
    monit start all
    log "[start_monit] started monit"
}

port_forward()
{
    log "[port_forward] setting up port forwarding from 9201 to 9200"
    #redirects 9201 > 9200 locally
    #this to overcome a limitation in ARM where to vm loadbalancers can route on the same backed ports
    iptables -t nat -I PREROUTING -p tcp --dport 9201 -j REDIRECT --to-ports 9200
    iptables -t nat -I OUTPUT -p tcp -o lo --dport 9201 -j REDIRECT --to-ports 9200

    #install iptables-persistent to restore configuration after reboot
    log "[port_forward] installing iptables-persistent"
    (apt-get -yq install iptables-persistent || (sleep 15; apt-get -yq install iptables-persistent))

    # persist iptables changes
    service netfilter-persistent save
    service netfilter-persistent start
    # add netfilter-persistent to startup before elasticsearch
    update-rc.d netfilter-persistent defaults 90 15

    log "[port_forward] installed iptables-persistent"
    log "[port_forward] port forwarding configured"
}

#########################
# Installation sequence
#########################

# if elasticsearch is already installed assume this is a redeploy
# change yaml configuration and only restart the server when needed
if monit status elasticsearch >& /dev/null; then

  configure_elasticsearch_yaml

  # if this is a data node using temp disk, check existence and permissions
  check_data_disk

  # restart elasticsearch if the configuration has changed
  cmp --silent /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.bak \
    || monit restart elasticsearch

  exit 0
fi

format_data_disks

log "[apt-get] updating apt-get"
(apt-get -y update || (sleep 15; apt-get -y update)) > /dev/null
log "[apt-get] updated apt-get"

install_ntp

install_java

install_es

setup_data_disk

if [ ${INSTALL_XPACK} -ne 0 ]; then
    install_xpack
    # in 6.x we need to set up the bootstrap.password in the keystore to use when setting up users
    if [[ "${ES_VERSION}" == \6* ]]; then
        setup_bootstrap_password
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

port_forward

start_monit

# patch roles and users through the REST API which is a tad trickier
if [[ ${INSTALL_XPACK} -ne 0 ]]; then
  wait_for_started
  apply_security_settings
fi

ELAPSED_TIME=$(($SECONDS - $START_TIME))
PRETTY=$(printf '%dh:%dm:%ds\n' $(($ELAPSED_TIME/3600)) $(($ELAPSED_TIME%3600/60)) $(($ELAPSED_TIME%60)))

log "End execution of Elasticsearch script extension on ${HOSTNAME} in ${PRETTY}"
exit 0
