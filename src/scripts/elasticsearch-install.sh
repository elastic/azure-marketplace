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
    echo ""
    echo "Options:"
    echo "    -n      elasticsearch cluster name"
    echo "    -v      elasticsearch version e.g. 7.0.0"
    echo "    -p      hostname prefix of nodes for unicast discovery"
    echo "    -m      heap size in megabytes to allocate to JVM"

    echo "    -d      cluster uses dedicated masters"
    echo "    -Z      <number of nodes> hint to the install script how many data nodes we are provisioning"

    echo "    -B      bootstrap password" 
    echo "    -A      elastic user password"  
    echo "    -K      kibana user password"
    echo "    -S      logstash_system user password"
    echo "    -F      beats_system user password"
    echo "    -M      apm_system user password"
    echo "    -R      remote_monitoring_user user password"

    echo "    -x      configure as a dedicated master node"
    echo "    -y      configure as client only node (no master, no data)"
    echo "    -z      configure as data node (no master)"
    echo "    -l      install X-Pack plugin (<6.3.0) or apply trial license for Platinum features (6.3.0+)"
    echo "    -L      <plugin;plugin> install additional plugins"
    echo "    -C      <yaml\nyaml> additional yaml configuration"

    echo "    -H      base64 encoded PKCS#12 archive (.p12/.pfx) containing the key and certificate used to secure the HTTP layer"
    echo "    -G      password for PKCS#12 archive (.p12/.pfx) containing the key and certificate used to secure the HTTP layer"
    echo "    -V      base64 encoded PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure the HTTP layer"
    echo "    -J      password for PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure the HTTP layer"

    echo "    -T      base64 encoded PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure the transport layer"
    echo "    -W      password for PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure the transport layer"
    echo "    -N      password for the generated PKCS#12 archive used to secure the transport layer"

    echo "    -O      URI from which to retrieve the metadata file for the Identity Provider to configure SAML Single-Sign-On"
    echo "    -P      Public domain name for the instance of Kibana to configure SAML Single-Sign-On"
    echo "    -D      Internal Load Balancer IP address"

    echo "    -j      install repository-azure plugin for snapshot and restore"
    echo "    -a      set the default storage account for repository-azure plugin"
    echo "    -k      set the key for the default storage account for repository-azure plugin"
    echo "    -E      set the storage account suffix for repository-azure plugin"

    echo "    -h      view this help content"
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
  # Append it to the hosts file if not there
  echo "127.0.0.1 ${HOSTNAME}" >> /etc/hosts
  log "hostname ${HOSTNAME} added to /etc/hosts"
fi

#########################
# Parameter handling
#########################

CLUSTER_NAME="elasticsearch"
NAMESPACE_PREFIX=""
ES_VERSION="6.4.1"
ES_HEAP=0
INSTALL_XPACK=0
BASIC_SECURITY=0
INSTALL_ADDITIONAL_PLUGINS=""
YAML_CONFIGURATION=""
MANDATORY_PLUGINS=""
CLIENT_ONLY_NODE=0
DATA_ONLY_NODE=0
MASTER_ONLY_NODE=0

CLUSTER_USES_DEDICATED_MASTERS=0
DATANODE_COUNT=0

MINIMUM_MASTER_NODES=3
UNICAST_HOST_PORT=":9300"
UNICAST_HOSTS='["'"$NAMESPACE_PREFIX"'master-0'"$UNICAST_HOST_PORT"'","'"$NAMESPACE_PREFIX"'master-1'"$UNICAST_HOST_PORT"'","'"$NAMESPACE_PREFIX"'master-2'"$UNICAST_HOST_PORT"'"]'

USER_ADMIN_PWD="changeme"
USER_REMOTE_MONITORING_PWD="changeme"
USER_KIBANA_PWD="changeme"
USER_LOGSTASH_PWD="changeme"
USER_BEATS_PWD="changeme"
USER_APM_PWD="changeme"
BOOTSTRAP_PASSWORD="changeme"
SEED_PASSWORD="changeme"

INSTALL_AZURECLOUD_PLUGIN=0
STORAGE_ACCOUNT=""
STORAGE_KEY=""

HTTP_CERT=""
HTTP_CERT_PASSWORD=""
HTTP_CACERT=""
HTTP_CACERT_PASSWORD=""
INTERNAL_LOADBALANCER_IP=""
PROTOCOL="http"
CURL_SWITCH=""

TRANSPORT_CACERT=""
TRANSPORT_CACERT_PASSWORD=""
TRANSPORT_CERT_PASSWORD=""

SAML_METADATA_URI=""
SAML_SP_URI=""

#Loop through options passed
while getopts :n:m:v:A:R:M:K:S:F:Z:p:a:k:L:C:B:E:H:G:T:W:V:J:N:D:O:P:xyzldjh optname; do
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
    R) #security remote_monitoring_user pwd
      USER_REMOTE_MONITORING_PWD="${OPTARG}"
      ;;
    K) #security kibana user pwd
      USER_KIBANA_PWD="${OPTARG}"
      ;;
    S) #security logstash_system user pwd
      USER_LOGSTASH_PWD="${OPTARG}"
      ;;
    F) #security beats_system user pwd
      USER_BEATS_PWD="${OPTARG}"
      ;;
    M) #security apm_system user pwd
      USER_APM_PWD="${OPTARG}"
      ;;
    B) #bootstrap password
      BOOTSTRAP_PASSWORD="${OPTARG}"
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
    D) #internal load balancer IP
      INTERNAL_LOADBALANCER_IP="${OPTARG}"
      ;;
    H) #HTTP cert blob
      HTTP_CERT="${OPTARG}"
      ;;
    G) #HTTP cert password
      HTTP_CERT_PASSWORD="${OPTARG}"
      ;;
    V) #HTTP CA cert
      HTTP_CACERT="${OPTARG}"
      ;;
    J) #HTTP CA cert password
      HTTP_CACERT_PASSWORD="${OPTARG}"
      ;;
    T) #Transport CA cert blob
      TRANSPORT_CACERT="${OPTARG}"
      ;;
    W) #Transport CA cert password
      TRANSPORT_CACERT_PASSWORD="${OPTARG}"
      ;;
    N) #Transport cert password
      TRANSPORT_CERT_PASSWORD="${OPTARG}"
      ;;
    O) #SAML metadata URI
      SAML_METADATA_URI="${OPTARG}"
      ;;
    P) #SAML Service Provider URI
      SAML_SP_URI="${OPTARG}"
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
    E) #azure storage account endpoint suffix
      STORAGE_SUFFIX="${OPTARG}"
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

# supports security features with a basic license
if [[ $(dpkg --compare-versions "$ES_VERSION" "ge" "7.1.0"; echo $?) -eq 0 || ($(dpkg --compare-versions "$ES_VERSION" "ge" "6.8.0"; echo $?) -eq 0 && $(dpkg --compare-versions "$ES_VERSION" "lt" "7.0.0"; echo $?) -eq 0) ]]; then
  BASIC_SECURITY=1
fi

# zen2 should emit the ports from hosts
if dpkg --compare-versions "$ES_VERSION" "ge" "7.0.0"; then
  UNICAST_HOST_PORT=""
fi

if [ ${CLUSTER_USES_DEDICATED_MASTERS} -ne 0 ]; then
    MINIMUM_MASTER_NODES=2
    UNICAST_HOSTS='["'"$NAMESPACE_PREFIX"'master-0'"$UNICAST_HOST_PORT"'","'"$NAMESPACE_PREFIX"'master-1'"$UNICAST_HOST_PORT"'","'"$NAMESPACE_PREFIX"'master-2'"$UNICAST_HOST_PORT"'"]'
else
    MINIMUM_MASTER_NODES=$(((DATANODE_COUNT/2)+1))
    UNICAST_HOSTS='['
    for i in $(seq 0 $((DATANODE_COUNT-1))); do
        UNICAST_HOSTS="$UNICAST_HOSTS\"${NAMESPACE_PREFIX}data-$i${UNICAST_HOST_PORT}\","
    done
    UNICAST_HOSTS="${UNICAST_HOSTS%?}]"
fi

if [[ ${INSTALL_XPACK} -ne 0 || ${BASIC_SECURITY} -ne 0 ]]; then
    log "using bootstrap password as the seed password"
    SEED_PASSWORD="$BOOTSTRAP_PASSWORD"
fi

log "bootstrapping an Elasticsearch $ES_VERSION cluster named '$CLUSTER_NAME' with minimum_master_nodes set to $MINIMUM_MASTER_NODES"
log "cluster uses dedicated master nodes is set to $CLUSTER_USES_DEDICATED_MASTERS and unicast goes to $UNICAST_HOSTS"
log "cluster install X-Pack plugin is set to $INSTALL_XPACK"
log "cluster basic security is set to $BASIC_SECURITY"

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
        if [[ $EXIT_CODE -ne 0 ]]; then
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
        log "[setup_data_disk] configuring disk $RAIDDISK/elasticsearch/data"
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
        log "[setup_data_disk] configured data directory does not exist for ${HOSTNAME}. using defaults"
    fi
}

# Check Data Disk Folder and Permissions
check_data_disk()
{
    if [ ${MASTER_ONLY_NODE} -eq 0 -a ${CLIENT_ONLY_NODE} -eq 0 ]; then
        log "[check_data_disk] data node checking data directory"
        if [ -d "/datadisks" ]; then
            log "[check_data_disk] data disks attached and mounted at /datadisks"
        elif [ -d "/mnt/elasticsearch/data" ]; then
            log "[check_data_disk] data directory at /mnt/elasticsearch/data"
        else
            #this could happen when the temporary disk is lost and a new one mounted
            local TEMPDISK="/mnt"
            log "[check_data_disk] no data directory at /mnt/elasticsearch/data dir"
            log "[check_data_disk] configuring disk $TEMPDISK/elasticsearch/data"
            mkdir -p "$TEMPDISK/elasticsearch/data"
            chown -R elasticsearch:elasticsearch "$TEMPDISK/elasticsearch"
            chmod 755 "$TEMPDISK/elasticsearch"
        fi
    fi
}

# Install OpenJDK
install_java()
{
  bash java-install.sh -v "$ES_VERSION"
}

# Install Elasticsearch
install_es()
{
    local OS_SUFFIX=""
    if dpkg --compare-versions "$ES_VERSION" "ge" "7.0.0"; then
      OS_SUFFIX="-amd64"
    fi
    local PACKAGE="elasticsearch-${ES_VERSION}${OS_SUFFIX}.deb"
    local ALGORITHM="512"
    local SHASUM="$PACKAGE.sha$ALGORITHM"
    local DOWNLOAD_URL="https://artifacts.elastic.co/downloads/elasticsearch/$PACKAGE?ultron=msft&gambit=azure"
    local SHASUM_URL="https://artifacts.elastic.co/downloads/elasticsearch/$SHASUM?ultron=msft&gambit=azure"

    log "[install_es] installing Elasticsearch $ES_VERSION"
    wget --retry-connrefused --waitretry=1 -q "$SHASUM_URL" -O $SHASUM
    local EXIT_CODE=$?
    if [[ $EXIT_CODE -ne 0 ]]; then
        log "[install_es] error downloading Elasticsearch $ES_VERSION sha$ALGORITHM checksum"
        exit $EXIT_CODE
    fi
    log "[install_es] download location - $DOWNLOAD_URL"
    wget --retry-connrefused --waitretry=1 -q "$DOWNLOAD_URL" -O $PACKAGE
    EXIT_CODE=$?
    if [[ $EXIT_CODE -ne 0 ]]; then
        log "[install_es] error downloading Elasticsearch $ES_VERSION"
        exit $EXIT_CODE
    fi
    log "[install_es] downloaded Elasticsearch $ES_VERSION"

    # earlier sha files do not contain the package name. add it
    grep -q "$PACKAGE" $SHASUM || sed -i "s/.*/&  $PACKAGE/" $SHASUM

    shasum -a $ALGORITHM -c $SHASUM
    EXIT_CODE=$?
    if [[ $EXIT_CODE -ne 0 ]]; then
        log "[install_es] error validating checksum for Elasticsearch $ES_VERSION"
        exit $EXIT_CODE
    fi

    dpkg -i $PACKAGE
    log "[install_es] installed Elasticsearch $ES_VERSION"
}

## Plugins
##----------------------------------

plugin_cmd()
{
    echo /usr/share/elasticsearch/bin/elasticsearch-plugin
}

install_repository_azure_plugin()
{
    log "[install_repository_azure_plugin] installing plugin repository-azure"
    $(plugin_cmd) install repository-azure --batch
    log "[install_repository_azure_plugin] installed plugin repository-azure"
}

install_additional_plugins()
{
    SKIP_PLUGINS="license shield watcher marvel-agent graph cloud-azure x-pack repository-azure"

    if dpkg --compare-versions "$ES_VERSION" "ge" "6.7.0"; then
      # plugins are bundled in the distribution
      SKIP_PLUGINS+=" ingest-geoip ingest-user-agent"
    fi

    log "[install_additional_plugins] Installing additional plugins"
    for PLUGIN in $(echo $INSTALL_ADDITIONAL_PLUGINS | tr ";" "\n")
    do
        if [[ $SKIP_PLUGINS =~ $PLUGIN ]]; then
            log "[install_additional_plugins] skipping plugin $PLUGIN"
        else
            log "[install_additional_plugins] installing plugin $PLUGIN"
            $(plugin_cmd) install $PLUGIN --batch
            log "[install_additional_plugins] add plugin $PLUGIN to mandatory plugins"
            MANDATORY_PLUGINS+="$PLUGIN,"
            log "[install_additional_plugins] installed plugin $PLUGIN"
        fi
    done
    log "[install_additional_plugins] installed additional plugins"
}

## Security
##----------------------------------

node_is_up()
{
  exec 17>&1
  local response=$(curl -XGET -u "elastic:$1" -H 'Content-Type: application/json' --write-out '\n%{http_code}\n' \
    "$PROTOCOL://localhost:9200/_cluster/health?wait_for_status=green&timeout=30s&filter_path=status" $CURL_SWITCH | tee /dev/fd/17) 
  local curl_error_code=$?
  local http_code=$(echo "$response" | tail -n 1)
  exec 17>&-
  if [[ $curl_error_code -ne 0 ]]; then
    return $curl_error_code
  fi
  
  if [[ $http_code -eq 200 ]]; then
    local body=$(echo "$response" | head -n -1)
    local status=$(jq -r .status <<< $body)
    log "[node_is_up] cluster health is $status"
    if [[ "$status" -eq "green" ]]; then
      return 0
    fi
  fi
  return 127
}

elastic_user_exists()
{
  local ELASTIC_USER_NAME USER_TYPENAME curl_error_code http_code
  if [[ "${ES_VERSION}" == \6* ]]; then
    USER_TYPENAME="doc"
    ELASTIC_USER_NAME="reserved-user-elastic"
  else
    # 7.x +
    USER_TYPENAME="_doc"
    ELASTIC_USER_NAME="reserved-user-elastic"
  fi

  exec 17>&1
  http_code=$(curl -H 'Content-Type: application/json' --write-out '\n%{http_code}\n' $PROTOCOL://localhost:9200/.security/$USER_TYPENAME/$ELASTIC_USER_NAME -u "elastic:$1" $CURL_SWITCH | tee /dev/fd/17 | tail -n 1)
  curl_error_code=$?
  exec 17>&-
  if [[ $http_code -eq 200 ]]; then
    return 0
  fi
  if [[ $curl_error_code -ne 0 ]]; then
      return $curl_error_code
  fi
  if [[ $http_code -ge 400 && $http_code -lt 600 ]]; then
      echo "HTTP $http_code" >&2
      return 127
  fi
}

wait_for_started()
{
  local TOTAL_RETRIES=60
  for i in $(seq $TOTAL_RETRIES); do
    node_is_up "$SEED_PASSWORD"
    if [[ $? != 0 ]]; then
      node_is_up "$USER_ADMIN_PWD"
      if [[ $? != 0 ]]; then
        sleep 5
        log "[wait_for_started] seeing if node is up after sleeping 5 seconds, retry ${i}/$TOTAL_RETRIES"
      else
        log "[wait_for_started] node is up!"
        return
      fi
    else
      log "[wait_for_started] node is up!"
      return
    fi
  done
  log "[wait_for_started] never saw elasticsearch go up locally"
  exit 10
}

# since upserts of roles users CAN throw 409 conflicts we ignore these for now
# opened an issue on x-pack repos to handle this more gracefully later
curl_ignore_409 () {
    local curl_error_code http_code
    exec 17>&1
    http_code=$(curl -H 'Content-Type: application/json' --write-out '\n%{http_code}\n' "$@" $CURL_SWITCH | tee /dev/fd/17 | tail -n 1)
    curl_error_code=$?
    exec 17>&-
    if [[ $http_code -eq 409 ]]; then
      return 0
    fi
    if [[ $curl_error_code -ne 0 ]]; then
        return $curl_error_code
    fi
    if [[ $http_code -ge 400 && $http_code -lt 600 ]]; then
        echo "HTTP $http_code" >&2
        return 127
    fi
}

# waits for the .security alias/index to be green
wait_for_green_security_index() 
{
  local retries=0
  until [ "$retries" -ge 12 ]
  do
    exec 17>&1
    local response=$(curl -XGET -u "elastic:$USER_ADMIN_PWD" -H 'Content-Type: application/json' --write-out '\n%{http_code}\n' \
      "$PROTOCOL://localhost:9200/_cluster/health/.security?wait_for_status=green&timeout=30s&filter_path=status" $CURL_SWITCH | tee /dev/fd/17) 
    local curl_error_code=$?
    local http_code=$(echo "$response" | tail -n 1)
    exec 17>&-
    if [[ $curl_error_code -ne 0 ]]; then
      log "[wait_for_green_security_index] curl exit code $curl_error_code waiting for security index to be green"
      return $curl_error_code
    fi
    if [[ $http_code -eq 200 ]]; then
      local body=$(echo "$response" | head -n -1)
      local status=$(jq -r .status <<< $body)
      log "[wait_for_green_security_index] security index is $status"
      if [[ $status -eq "green" ]]; then
        return 0
      else
        return 127
      fi
    fi
    if [[ $http_code -ge 400 && $http_code -lt 600 ]]; then
        log "[wait_for_green_security_index] status code $http_code waiting for security index to be green"
        echo "HTTP $http_code" >&2
        retries=$((retries+1))
        sleep 10
    fi
  done
  return 127
}

escape_pwd() 
{
  echo $1 | sed 's/"/\\"/g'
}

apply_security_settings()
{
    # if the node is up, check that the elastic user exists in the .security index if
    # the elastic user password is the same as the bootstrap password.
    node_is_up "$USER_ADMIN_PWD"
    if [[ $? -eq 0 ]]; then
      log "[apply_security_settings] can ping node using user provided credentials"
      if [[ "$USER_ADMIN_PWD" -ne "$SEED_PASSWORD" ]]; then
        log "[apply_security_settings] elastic user password already changed, exiting early!"
        return
      fi

      elastic_user_exists "$USER_ADMIN_PWD"
      if [[ $? -eq 0 ]]; then
        log "[apply_security_settings] elastic user exists, exiting early!"
        return
      fi
    fi

    log "[apply_security_settings] start updating roles and users"

    local XPACK_SECURITY_PATH
    if dpkg --compare-versions "$ES_VERSION" "ge" "7.0.0"; then
      XPACK_SECURITY_PATH="_security"
    else
      XPACK_SECURITY_PATH="_xpack/security"
    fi

    local XPACK_USER_ENDPOINT="$PROTOCOL://localhost:9200/$XPACK_SECURITY_PATH/user"
    local XPACK_ROLE_ENDPOINT="$PROTOCOL://localhost:9200/$XPACK_SECURITY_PATH/role"

    #update builtin `elastic` account.
    local ESCAPED_USER_ADMIN_PWD=$(escape_pwd $USER_ADMIN_PWD)
    local ADMIN_JSON=$(printf '{"password":"%s"}\n' $ESCAPED_USER_ADMIN_PWD)
    echo $ADMIN_JSON | curl_ignore_409 -XPUT -u "elastic:$SEED_PASSWORD" "$XPACK_USER_ENDPOINT/elastic/_password" -d @-
    if [[ $? != 0 ]]; then
      wait_for_green_security_index
      if [[ $? != 0 ]]; then
        log "[apply_security_settings] did not see green security index"
      fi

      #Make sure another deploy did not already change the elastic password
      curl_ignore_409 -XGET -u "elastic:$USER_ADMIN_PWD" "$PROTOCOL://localhost:9200/"
      if [[ $? != 0 ]]; then
        log "[apply_security_settings] could not update the built-in elastic user"
        exit 10
      fi
    fi
    log "[apply_security_settings] updated built-in elastic superuser password"

    wait_for_green_security_index
    if [[ $? != 0 ]]; then
      log "[apply_security_settings] did not see green security index"
    fi

    #update builtin `kibana`/`kibana_system` account
    local ESCAPED_USER_KIBANA_PWD=$(escape_pwd $USER_KIBANA_PWD)
    local KIBANA_JSON=$(printf '{"password":"%s"}\n' $ESCAPED_USER_KIBANA_PWD)
    local KIBANA_USER="kibana"
    if dpkg --compare-versions "$ES_VERSION" "ge" "7.8.0"; then
      KIBANA_USER="kibana_system"
    fi 

    echo $KIBANA_JSON | curl_ignore_409 -XPUT -u "elastic:$USER_ADMIN_PWD" "$XPACK_USER_ENDPOINT/$KIBANA_USER/_password" -d @-
    if [[ $? != 0 ]];  then
      log "[apply_security_settings] could not update the built-in $KIBANA_USER user"
      exit 10
    fi
    log "[apply_security_settings] updated built-in $KIBANA_USER user password"

    #update builtin `logstash_system` account
    local ESCAPED_USER_LOGSTASH_PWD=$(escape_pwd $USER_LOGSTASH_PWD)
    local LOGSTASH_JSON=$(printf '{"password":"%s"}\n' $ESCAPED_USER_LOGSTASH_PWD)
    echo $LOGSTASH_JSON | curl_ignore_409 -XPUT -u "elastic:$USER_ADMIN_PWD" "$XPACK_USER_ENDPOINT/logstash_system/_password" -d @-
    if [[ $? != 0 ]];  then
      log "[apply_security_settings] could not update the built-in logstash_system user"
      exit 10
    fi
    log "[apply_security_settings] updated built-in logstash_system user password"

    #update builtin `beats_system` account
    local ESCAPED_USER_BEATS_PWD=$(escape_pwd $USER_BEATS_PWD)
    local BEATS_JSON=$(printf '{"password":"%s"}\n' $ESCAPED_USER_BEATS_PWD)
    echo $BEATS_JSON | curl_ignore_409 -XPUT -u "elastic:$USER_ADMIN_PWD" "$XPACK_USER_ENDPOINT/beats_system/_password" -d @-
    if [[ $? != 0 ]];  then
      log "[apply_security_settings] could not update the built-in beats_system user"
      exit 10
    fi
    log "[apply_security_settings] updated built-in beats_system user password"

    #update builtin `apm_system` account
    local ESCAPED_USER_APM_PWD=$(escape_pwd $USER_APM_PWD)
    local APM_JSON=$(printf '{"password":"%s"}\n' $ESCAPED_USER_APM_PWD)
    echo $APM_JSON | curl_ignore_409 -XPUT -u "elastic:$USER_ADMIN_PWD" "$XPACK_USER_ENDPOINT/apm_system/_password" -d @-
    if [[ $? != 0 ]];  then
      log "[apply_security_settings] could not update the built-in apm_system user"
      exit 10
    fi
    log "[apply_security_settings] updated built-in apm_system user password"
  
    #update builtin `remote_monitoring_user`
    local ESCAPED_USER_REMOTE_MONITORING_PWD=$(escape_pwd $USER_REMOTE_MONITORING_PWD)
    local REMOTE_MONITORING_JSON=$(printf '{"password":"%s"}\n' $ESCAPED_USER_REMOTE_MONITORING_PWD)
    echo $REMOTE_MONITORING_JSON | curl_ignore_409 -XPUT -u "elastic:$USER_ADMIN_PWD" "$XPACK_USER_ENDPOINT/remote_monitoring_user/_password" -d @-
    if [[ $? != 0 ]];  then
      log "[apply_security_settings] could not update the built-in remote_monitoring_user user"
      exit 10
    fi
    log "[apply_security_settings] updated built-in remote_monitoring_user user password" 
}

create_keystore_if_not_exists()
{
  [[ -f /etc/elasticsearch/elasticsearch.keystore ]] || (/usr/share/elasticsearch/bin/elasticsearch-keystore create)
}

setup_bootstrap_password()
{
  log "[setup_bootstrap_password] adding bootstrap.password to keystore"
  create_keystore_if_not_exists
  echo "$BOOTSTRAP_PASSWORD" | /usr/share/elasticsearch/bin/elasticsearch-keystore add bootstrap.password -xf
  log "[setup_bootstrap_password] added bootstrap.password to keystore"
}

configure_http_tls()
{
    local ES_CONF=$1
    local SSL_PATH=/etc/elasticsearch/ssl
    local HTTP_CERT_FILENAME=elasticsearch-http.p12
    local HTTP_CERT_PATH=$SSL_PATH/$HTTP_CERT_FILENAME
    local HTTP_CACERT_FILENAME=elasticsearch-http-ca.p12
    local HTTP_CACERT_PATH=$SSL_PATH/$HTTP_CACERT_FILENAME
    local BIN_DIR=/usr/share/elasticsearch/bin
    local KEY_STORE=$BIN_DIR/elasticsearch-keystore

    # check if any certs already exist on disk
    if [[ -f $HTTP_CERT_PATH ]]; then
        log "[configure_http_tls] HTTP cert already exists"
    elif [[ -f $HTTP_CACERT_PATH ]]; then
        log "[configure_http_tls] HTTP CA already exists"
    else
        [ -d $SSL_PATH ] || mkdir -p $SSL_PATH
        # Use HTTP cert if supplied, otherwise generate one
        if [[ -n "${HTTP_CERT}" ]]; then
          log "[configure_http_tls] save HTTP cert blob to file"
          echo ${HTTP_CERT} | base64 -d | tee $HTTP_CERT_PATH
        else
          # Use the CA cert to generate certs if supplied
          log "[configure_http_tls] save HTTP CA cert blob to file"
          echo ${HTTP_CACERT} | base64 -d | tee $HTTP_CACERT_PATH

          # Check the cert is a CA
          echo "$HTTP_CACERT_PASSWORD" | openssl pkcs12 -in $HTTP_CACERT_PATH -clcerts -nokeys -passin stdin \
            | openssl x509 -text -noout | grep "CA:TRUE"
          if [[ $? -ne 0 ]]; then
              log "[configure_http_tls] HTTP CA blob is not a Certificate Authority (CA)"
              exit 12
          fi

          if [[ -f $BIN_DIR/elasticsearch-certutil || -f $BIN_DIR/x-pack/certutil ]]; then
              local CERTUTIL=$BIN_DIR/elasticsearch-certutil
              if [[ ! -f $CERTUTIL ]]; then
                  CERTUTIL=$BIN_DIR/x-pack/certutil
              fi

              log "[configure_http_tls] generate HTTP cert for node using $CERTUTIL"
              $CERTUTIL cert --name "$HOSTNAME" --dns "$HOSTNAME" --ip $(hostname -I) --ip $INTERNAL_LOADBALANCER_IP \
                  --out $HTTP_CERT_PATH --pass "$HTTP_CERT_PASSWORD" --ca $HTTP_CACERT_PATH --ca-pass "$HTTP_CACERT_PASSWORD"
              log "[configure_http_tls] generated HTTP cert for node"
          else
              log "[configure_http_tls] no certutil tool could be found to generate a HTTP cert"
              exit 12
          fi
        fi
    fi

    log "[configure_http_tls] configuring SSL/TLS for HTTP layer"
    echo "xpack.security.http.ssl.enabled: true" >> $ES_CONF

    if [[ -f $HTTP_CERT_PATH ]]; then
        # dealing with PKCS#12 archive
        echo "xpack.security.http.ssl.keystore.path: $HTTP_CERT_PATH" >> $ES_CONF
        echo "xpack.security.http.ssl.truststore.path: $HTTP_CERT_PATH" >> $ES_CONF
        if [[ -n "${HTTP_CERT_PASSWORD}" ]]; then
          log "[configure_http_tls] configure HTTP key password in keystore"
          create_keystore_if_not_exists
          echo "$HTTP_CERT_PASSWORD" | $KEY_STORE add xpack.security.http.ssl.keystore.secure_password -xf
          echo "$HTTP_CERT_PASSWORD" | $KEY_STORE add xpack.security.http.ssl.truststore.secure_password -xf
        fi
    fi

    chown -R elasticsearch:elasticsearch $SSL_PATH
    # use HTTPS for calls to localhost when TLS configured on HTTP layer
    PROTOCOL="https"
    # use the insecure flag to make calls to https://localhost:9200 to bootstrap cluster. curl checks
    # that the certificate subject name matches the host name when using --cacert which may not be true
    CURL_SWITCH="-k"
    log "[configure_http_tls] configured SSL/TLS for HTTP layer"
}

configure_transport_tls()
{
    local ES_CONF=$1
    local SSL_PATH=/etc/elasticsearch/ssl
    local TRANSPORT_CERT_FILENAME=elasticsearch-transport.p12
    local TRANSPORT_CERT_PATH=$SSL_PATH/$TRANSPORT_CERT_FILENAME
    local TRANSPORT_CACERT_FILENAME=elasticsearch-transport-ca.p12
    local TRANSPORT_CACERT_PATH=$SSL_PATH/$TRANSPORT_CACERT_FILENAME
    local BIN_DIR=/usr/share/elasticsearch/bin
    local KEY_STORE=$BIN_DIR/elasticsearch-keystore

    # check if any cert already exists on disk
    if [[ -f $TRANSPORT_CACERT_PATH ]]; then
        log "[configure_http_tls] Transport CA already exists"
    else
        [ -d $SSL_PATH ] || mkdir -p $SSL_PATH

        # Use CA to generate certs
        log "[configure_transport_tls] save Transport CA blob to file"
        echo ${TRANSPORT_CACERT} | base64 -d | tee $TRANSPORT_CACERT_PATH

        # Check the cert is a CA
        echo "$TRANSPORT_CACERT_PASSWORD" | openssl pkcs12 -in $TRANSPORT_CACERT_PATH -clcerts -nokeys -passin stdin \
          | openssl x509 -text -noout | grep "CA:TRUE"
        if [[ $? -ne 0 ]]; then
            log "[configure_transport_tls] Transport CA blob is not a Certificate Authority (CA)"
            exit 12
        fi

        # Generate certs with certutil
        if [[ -f $BIN_DIR/elasticsearch-certutil || -f $BIN_DIR/x-pack/certutil ]]; then
            local CERTUTIL=$BIN_DIR/elasticsearch-certutil
            if [[ ! -f $CERTUTIL ]]; then
                CERTUTIL=$BIN_DIR/x-pack/certutil
            fi

            log "[configure_transport_tls] generate Transport cert using $CERTUTIL"
            $CERTUTIL cert --name "$HOSTNAME" --dns "$HOSTNAME" --ip $(hostname -I) --out $TRANSPORT_CERT_PATH --pass "$TRANSPORT_CERT_PASSWORD" --ca $TRANSPORT_CACERT_PATH --ca-pass "$TRANSPORT_CACERT_PASSWORD"
            log "[configure_transport_tls] generated Transport cert"

        else
            log "[configure_transport_tls] no certutil tool could be found to generate a Transport cert"
            exit 12
        fi
    fi

    log "[configure_transport_tls] configuring SSL/TLS for Transport layer"
    echo "xpack.security.transport.ssl.enabled: true" >> $ES_CONF

    if [[ -f $TRANSPORT_CERT_PATH ]]; then
        echo "xpack.security.transport.ssl.keystore.path: $TRANSPORT_CERT_PATH" >> $ES_CONF
        echo "xpack.security.transport.ssl.truststore.path: $TRANSPORT_CERT_PATH" >> $ES_CONF
        if [[ -n "$TRANSPORT_CERT_PASSWORD" ]]; then
            create_keystore_if_not_exists
            log "[configure_transport_tls] configure Transport key password in keystore"
            echo "$TRANSPORT_CERT_PASSWORD" | $KEY_STORE add xpack.security.transport.ssl.keystore.secure_password -xf
            echo "$TRANSPORT_CERT_PASSWORD" | $KEY_STORE add xpack.security.transport.ssl.truststore.secure_password -xf
        fi
    fi

    chown -R elasticsearch:elasticsearch $SSL_PATH
    log "[configure_transport_tls] configured SSL/TLS for Transport layer"
}

## Configuration
##----------------------------------

configure_awareness_attributes()
{
  local ES_CONF=$1
  install_jq
  log "[configure_awareness_attributes] configure fault and update domain attributes"
  local METADATA=$(curl -sH Metadata:true "http://169.254.169.254/metadata/instance?api-version=2018-10-01")
  local FAULT_DOMAIN=$(jq -r .compute.platformFaultDomain <<< $METADATA)
  local UPDATE_DOMAIN=$(jq -r .compute.platformUpdateDomain <<< $METADATA)
  echo "node.attr.fault_domain: $FAULT_DOMAIN" >> $ES_CONF
  echo "node.attr.update_domain: $UPDATE_DOMAIN" >> $ES_CONF
  log "[configure_awareness_attributes] configure shard allocation awareness using fault_domain and update_domain"
  echo "cluster.routing.allocation.awareness.attributes: fault_domain,update_domain" >> $ES_CONF
}

configure_elasticsearch_yaml()
{
    log "[configure_elasticsearch_yaml] configure elasticsearch.yml file"
    local ES_CONF=/etc/elasticsearch/elasticsearch.yml
    # Backup the current Elasticsearch configuration file
    mv $ES_CONF $ES_CONF.bak

    # Set cluster and machine names - just use hostname for our node.name
    echo "cluster.name: \"$CLUSTER_NAME\"" >> $ES_CONF
    echo "node.name: \"${HOSTNAME}\"" >> $ES_CONF

    # put log files on the OS disk in a writable location
    echo "path.logs: /var/log/elasticsearch" >> $ES_CONF

    # Check if data disks are attached. If they are then use them. Otherwise
    # 1. if this is a data node, use the temporary disk with all the caveats that come with using ephemeral storage for data
    #    https://docs.microsoft.com/en-us/azure/virtual-machines/windows/about-disks-and-vhds#temporary-disk
    # 2. for any other node, use the OS disk
    local DATAPATH_CONFIG=/var/lib/elasticsearch
    if [ -d /datadisks ]; then
        DATAPATH_CONFIG=/datadisks/disk1/elasticsearch/data
    elif [ ${MASTER_ONLY_NODE} -eq 0 -a ${CLIENT_ONLY_NODE} -eq 0 ]; then
        DATAPATH_CONFIG=/mnt/elasticsearch/data
    fi

    # configure path.data
    log "[configure_elasticsearch_yaml] update configuration with data path list of $DATAPATH_CONFIG"
    echo "path.data: $DATAPATH_CONFIG" >> $ES_CONF

    # Configure discovery
    if dpkg --compare-versions "$ES_VERSION" "lt" "7.0.0"; then
      log "[configure_elasticsearch_yaml] update configuration with discovery.zen.ping.unicast.hosts set to $UNICAST_HOSTS"
      echo "discovery.zen.ping.unicast.hosts: $UNICAST_HOSTS" >> $ES_CONF
      echo "discovery.zen.minimum_master_nodes: $MINIMUM_MASTER_NODES" >> $ES_CONF
    else
      log "[configure_elasticsearch_yaml] update configuration with discovery.seed_hosts and cluster.initial_master_nodes set to $UNICAST_HOSTS"
      echo "discovery.seed_hosts: $UNICAST_HOSTS" >> $ES_CONF
      echo "cluster.initial_master_nodes: $UNICAST_HOSTS" >> $ES_CONF
    fi

    # Configure Elasticsearch node type
    log "[configure_elasticsearch_yaml] configure master/client/data node type flags only master-$MASTER_ONLY_NODE only data-$DATA_ONLY_NODE"
    if [ ${MASTER_ONLY_NODE} -ne 0 ]; then
        log "[configure_elasticsearch_yaml] configure node as master only"
        echo "node.master: true" >> $ES_CONF
        echo "node.data: false" >> $ES_CONF
    elif [ ${DATA_ONLY_NODE} -ne 0 ]; then
        log "[configure_elasticsearch_yaml] configure node as data only"
        echo "node.master: false" >> $ES_CONF
        echo "node.data: true" >> $ES_CONF
    elif [ ${CLIENT_ONLY_NODE} -ne 0 ]; then
        log "[configure_elasticsearch_yaml] configure node as client only"
        echo "node.master: false" >> $ES_CONF
        echo "node.data: false" >> $ES_CONF
    else
        log "[configure_elasticsearch_yaml] configure node as master and data"
        echo "node.master: true" >> $ES_CONF
        echo "node.data: true" >> $ES_CONF
    fi
    
    echo "network.host: [_site_, _local_]" >> $ES_CONF
    echo "node.max_local_storage_nodes: 1" >> $ES_CONF

    configure_awareness_attributes $ES_CONF

    # Configure mandatory plugins
    if [[ -n "${MANDATORY_PLUGINS}" ]]; then
        log "[configure_elasticsearch_yaml] set plugin.mandatory to $MANDATORY_PLUGINS"
        echo "plugin.mandatory: ${MANDATORY_PLUGINS%?}" >> $ES_CONF
    fi

    # Configure Azure Cloud plugin
    if [[ -n "$STORAGE_ACCOUNT" && -n "$STORAGE_KEY" && -n "$STORAGE_SUFFIX" ]]; then
      log "[configure_elasticsearch_yaml] configure storage for repository-azure plugin in keystore"
      create_keystore_if_not_exists
      echo "$STORAGE_ACCOUNT" | /usr/share/elasticsearch/bin/elasticsearch-keystore add azure.client.default.account -xf
      echo "$STORAGE_KEY" | /usr/share/elasticsearch/bin/elasticsearch-keystore add azure.client.default.key -xf
      echo "azure.client.default.endpoint_suffix: $STORAGE_SUFFIX" >> $ES_CONF
    fi

    if [[ ${INSTALL_XPACK} -ne 0 ]]; then
      log "[configure_elasticsearch_yaml] Set generated license type to trial"
      echo "xpack.license.self_generated.type: trial" >> $ES_CONF
    fi

    if [[ ${INSTALL_XPACK} -ne 0 || ${BASIC_SECURITY} -ne 0 ]]; then
      log "[configure_elasticsearch_yaml] Set X-Pack Security enabled"
      echo "xpack.security.enabled: true" >> $ES_CONF
    fi

    # Additional yaml configuration
    if [[ -n "$YAML_CONFIGURATION" ]]; then
        log "[configure_elasticsearch_yaml] include additional yaml configuration"

        local SKIP_LINES="cluster.name node.name path.data discovery.zen.ping.unicast.hosts "
        SKIP_LINES+="node.master node.data discovery.zen.minimum_master_nodes network.host "
        SKIP_LINES+="discovery.seed_hosts cluster.initial_master_nodes "
        SKIP_LINES+="discovery.zen.ping.multicast.enabled marvel.agent.enabled "
        SKIP_LINES+="node.max_local_storage_nodes plugin.mandatory cloud.azure.storage.default.account "
        SKIP_LINES+="cloud.azure.storage.default.key azure.client.default.endpoint_suffix xpack.security.authc "
        SKIP_LINES+="xpack.ssl.verification_mode xpack.security.http.ssl.enabled "
        SKIP_LINES+="xpack.security.http.ssl.keystore.path xpack.security.http.ssl.truststore.path "
        SKIP_LINES+="xpack.security.transport.ssl.enabled xpack.security.transport.ssl.verification_mode "
        SKIP_LINES+="xpack.security.transport.ssl.keystore.path xpack.security.transport.ssl.truststore.path "
        local SKIP_REGEX="^\s*("$(echo $SKIP_LINES | tr " " "|" | sed 's/\./\\\./g')")"
        IFS=$'\n'
        for LINE in $(echo -e "$YAML_CONFIGURATION"); do
          if [[ -n "$LINE" ]]; then
              if [[ $LINE =~ $SKIP_REGEX ]]; then
                  log "[configure_elasticsearch_yaml] Skipping line '$LINE'"
              else
                  log "[configure_elasticsearch_yaml] Adding line '$LINE' to $ES_CONF"
                  echo "$LINE" >> $ES_CONF
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
        if [[ $EXIT_CODE -ne 0 ]]; then
            log "[configure_elasticsearch_yaml] errors in yaml configuration. exiting"
            exit 11
        fi
    fi

    # Swap is disabled by default in Ubuntu Azure VMs, no harm in adding memory lock
    log "[configure_elasticsearch_yaml] setting bootstrap.memory_lock: true"
    echo "bootstrap.memory_lock: true" >> $ES_CONF

    local INSTALL_CERTS=0
    if [[ ${INSTALL_XPACK} -ne 0 || ${BASIC_SECURITY} -ne 0 ]]; then
      INSTALL_CERTS=1
    fi

    # Configure SSL/TLS for HTTP layer
    if [[ -n "${HTTP_CERT}" || -n "$HTTP_CACERT" && ${INSTALL_CERTS} -ne 0 ]]; then
        configure_http_tls $ES_CONF
    fi

    # Configure TLS for Transport layer
    if [[ -n "${TRANSPORT_CACERT}" && ${INSTALL_CERTS} -ne 0 ]]; then
        configure_transport_tls $ES_CONF
    fi

    # Configure SAML realm only for valid versions of Elasticsearch and if the conditions are met
    if [[ -n "$SAML_METADATA_URI" && -n "$SAML_SP_URI" && ( -n "$HTTP_CERT" || -n "$HTTP_CACERT" ) && ${INSTALL_XPACK} -ne 0 ]]; then     
      log "[configure_elasticsearch_yaml] configuring native realm name 'native1' as SAML realm will be configured"     
      {
          echo -e ""
          # include the realm type in the setting name in 7.x +
          if dpkg --compare-versions "$ES_VERSION" "lt" "7.0.0"; then
            echo -e "xpack.security.authc.realms.native1:"
            echo -e "  type: native"
          else
            echo -e "xpack.security.authc.realms.native.native1:"
          fi
          echo -e "  order: 0"
          echo -e ""
      } >> $ES_CONF
      log "[configure_elasticsearch_yaml] configured native realm"    
      log "[configure_elasticsearch_yaml] configuring SAML realm named 'saml_aad' for $SAML_SP_URI"
      [ -d /etc/elasticsearch/saml ] || mkdir -p /etc/elasticsearch/saml
      wget --retry-connrefused --waitretry=1 -q "$SAML_METADATA_URI" -O /etc/elasticsearch/saml/metadata.xml
      chown -R elasticsearch:elasticsearch /etc/elasticsearch/saml
      SAML_SP_URI="${SAML_SP_URI%/}"
      # extract the entityID from the metadata file
      local IDP_ENTITY_ID="$(grep -oP '\sentityID="(.*?)"\s' /etc/elasticsearch/saml/metadata.xml | sed 's/^.*"\(.*\)".*/\1/')"
      {
          echo -e ""
          # include the realm type in the setting name in 7.x +
          if dpkg --compare-versions "$ES_VERSION" "lt" "7.0.0"; then
            echo -e "xpack.security.authc.realms.saml_aad:"
            echo -e "  type: saml"
          else
            echo -e "xpack.security.authc.realms.saml.saml_aad:"
          fi
          echo -e "  order: 2"
          echo -e "  idp.metadata.path: /etc/elasticsearch/saml/metadata.xml"
          echo -e "  idp.entity_id: \"$IDP_ENTITY_ID\""
          echo -e "  sp.entity_id:  \"$SAML_SP_URI/\""
          echo -e "  sp.acs: \"$SAML_SP_URI/api/security/v1/saml\""
          echo -e "  sp.logout: \"$SAML_SP_URI/logout\""
          echo -e "  attributes.principal: \"http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name\""
          echo -e "  attributes.name: \"http://schemas.microsoft.com/identity/claims/displayname\""
          echo -e "  attributes.mail: \"http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress\""
          echo -e "  attributes.groups: \"http://schemas.microsoft.com/ws/2008/06/identity/claims/role\""
      } >> $ES_CONF
      log "[configure_elasticsearch_yaml] configured SAML realm"
    fi
}

configure_elasticsearch()
{
    log "[configure_elasticsearch] configuring elasticsearch default configuration"

    if [[ "$ES_HEAP" -eq "0" ]]; then
      log "[configure_elasticsearch] configuring heap size from available memory"
      ES_HEAP=`free -m |grep Mem | awk '{if ($2/2 >31744) print 31744;else print int($2/2+0.5);}'`
    fi

    log "[configure_elasticsearch] configure elasticsearch heap size - $ES_HEAP megabytes"
    sed -i -e "s/^\-Xmx.*/-Xmx${ES_HEAP}m/" /etc/elasticsearch/jvm.options
    sed -i -e "s/^\-Xms.*/-Xms${ES_HEAP}m/" /etc/elasticsearch/jvm.options
}

configure_os_properties()
{
    log "[configure_os_properties] configuring operating system level configuration"
    # DNS Retry
    echo "options timeout:10 attempts:5" >> /etc/resolvconf/resolv.conf.d/head
    resolvconf -u

    # Required for bootstrap memory lock with systemd
    local SYSTEMD_OVERRIDES=/etc/systemd/system/elasticsearch.service.d
    [ -d $SYSTEMD_OVERRIDES ] || mkdir -p $SYSTEMD_OVERRIDES
    {
      echo "[Service]"
      echo "LimitMEMLOCK=infinity"
    } >> $SYSTEMD_OVERRIDES/override.conf

    log "[configure_os_properties] configure systemd to start Elasticsearch service automatically when system boots"
    systemctl daemon-reload
    systemctl enable elasticsearch.service

    log "[configure_os_properties] configured operating system level configuration"
}

## Installation of dependencies
##----------------------------------

install_apt_package()
{
  local PACKAGE=$1
  if [ $(dpkg-query -W -f='${Status}' $PACKAGE 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
    log "[install_$PACKAGE] installing $PACKAGE"
    (apt-get -yq install $PACKAGE || (sleep 15; apt-get -yq install $PACKAGE))
    log "[install_$PACKAGE] installed $PACKAGE"
  fi
}

install_unzip()
{
    install_apt_package unzip
}

install_jq()
{
    install_apt_package jq
}

install_yamllint()
{
    install_apt_package yamllint
}

install_ntp()
{
    install_apt_package ntp
    install_apt_package ntpdate

    if systemctl -q is-active ntp.service; then
      systemctl stop ntp.service
    fi

    ntpdate pool.ntp.org
    systemctl start ntp.service
}

start_systemd()
{
    log "[start_systemd] starting Elasticsearch"
    systemctl start elasticsearch.service
    log "[start_systemd] started Elasticsearch"
}

port_forward()
{
    log "[port_forward] setting up port forwarding from 9201 to 9200"
    #redirects 9201 > 9200 locally
    #this to overcome a limitation in ARM where to vm 2 loadbalancers cannot route on the same backend ports
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
if systemctl -q is-active elasticsearch.service; then
  log "[elasticsearch] elasticsearch service is already active"

  configure_elasticsearch_yaml

  # if this is a data node using temp disk, check existence and permissions
  check_data_disk

  # restart elasticsearch if the configuration has changed
  cmp --silent /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak
  COMPARE_YML=$?
  log "[elasticsearch] comparing elasticsearch.yml with elasticsearch.yml.bak: $COMPARE_YML"
  $COMPARE_YML || systemctl reload-or-restart elasticsearch.service
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

if [[ ${INSTALL_XPACK} -ne 0 || ${BASIC_SECURITY} -ne 0 ]]; then
    setup_bootstrap_password
fi

if [[ ! -z "${INSTALL_ADDITIONAL_PLUGINS// }" ]]; then
    install_additional_plugins
fi

if [ ${INSTALL_AZURECLOUD_PLUGIN} -ne 0 ]; then
    install_repository_azure_plugin
fi


configure_elasticsearch_yaml

configure_elasticsearch

configure_os_properties

port_forward

start_systemd

# patch roles and users through the REST API which is a tad trickier
if [[ ${INSTALL_XPACK} -ne 0 || ${BASIC_SECURITY} -ne 0 ]]; then
  wait_for_started
  apply_security_settings
fi

ELAPSED_TIME=$(($SECONDS - $START_TIME))
PRETTY=$(printf '%dh:%dm:%ds\n' $(($ELAPSED_TIME/3600)) $(($ELAPSED_TIME%3600/60)) $(($ELAPSED_TIME%60)))

log "End execution of Elasticsearch script extension on ${HOSTNAME} in ${PRETTY}"
exit 0
