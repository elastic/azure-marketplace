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

    echo "-H base64 encoded PKCS#12 archive (.p12/.pfx) containing the key and certificate used to secure the HTTP layer"
    echo "-G password for PKCS#12 archive (.p12/.pfx) containing the key and certificate used to secure the HTTP layer"
    echo "-V base64 encoded PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure the HTTP layer"
    echo "-J password for PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure the HTTP layer"

    echo "-T base64 encoded PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure the transport layer"
    echo "-W password for PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure the transport layer"
    echo "-N password for the generated PKCS#12 archive used to secure the transport layer"

    echo "-O URI from which to retrieve the metadata file for the Identity Provider to configure SAML Single-Sign-On"
    echo "-P Public domain name for the instance of Kibana to configure SAML Single-Sign-On"

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
  # Append it to the hosts file if not there
  echo "127.0.0.1 ${HOSTNAME}" >> /etc/hosts
  log "hostname ${HOSTNAME} added to /etc/hosts"
fi

#########################
# Parameter handling
#########################

CLUSTER_NAME="elasticsearch"
NAMESPACE_PREFIX=""
ES_VERSION="6.2.4"
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
while getopts :n:m:v:A:R:K:S:Z:p:a:k:L:C:B:E:H:G:T:W:V:J:N:D:O:P:xyzldjh optname; do
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

log "bootstrapping an Elasticsearch $ES_VERSION cluster named '$CLUSTER_NAME' with minimum_master_nodes set to $MINIMUM_MASTER_NODES"
log "cluster uses dedicated master nodes is set to $CLUSTER_USES_DEDICATED_MASTERS and unicast goes to $UNICAST_HOSTS"
log "cluster install X-Pack plugin is set to $INSTALL_XPACK"

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

# Update the oracle-java8-installer to patch download of Java 8u171 to 8u181.
# 8u171 download is now archived
# TODO: Remove this once oracle-java8-installer package is updated
install_java_package()
{
  apt-get -yq $@ install oracle-java8-installer || true \
  && pushd /var/lib/dpkg/info \
  && log "[install_java_package] update oracle-java8-installer to 8u181" \
  && sed -i 's|JAVA_VERSION=8u171|JAVA_VERSION=8u181|' oracle-java8-installer.* \
  && sed -i 's|PARTNER_URL=http://download.oracle.com/otn-pub/java/jdk/8u171-b11/512cd62ec5174c3487ac17c61aaa89e8/|PARTNER_URL=http://download.oracle.com/otn-pub/java/jdk/8u181-b13/96a7b8442fe848ef90c96a2fad6ed6d1/|' oracle-java8-installer.* \
  && sed -i 's|SHA256SUM_TGZ="b6dd2837efaaec4109b36cfbb94a774db100029f98b0d78be68c27bec0275982"|SHA256SUM_TGZ="1845567095bfbfebd42ed0d09397939796d05456290fb20a83c476ba09f991d3"|' oracle-java8-installer.* \
  && sed -i 's|J_DIR=jdk1.8.0_171|J_DIR=jdk1.8.0_181|' oracle-java8-installer.* \
  && popd \
  && log "[install_java_package] updated oracle-java8-installer" \
  && apt-get -yq $@ install oracle-java8-installer
}

# Install Oracle Java
install_java()
{
    log "[install_java] adding apt repository for Java 8"
    (add-apt-repository -y ppa:webupd8team/java || (sleep 15; add-apt-repository -y ppa:webupd8team/java))
    log "[install_java] updating apt-get"
    (apt-get -y update || (sleep 15; apt-get -y update)) > /dev/null
    log "[install_java] updated apt-get"
    echo debconf shared/accepted-oracle-license-v1-1 select true | debconf-set-selections
    echo debconf shared/accepted-oracle-license-v1-1 seen true | debconf-set-selections
    log "[install_java] installing Java"
    (install_java_package || (sleep 15; install_java_package))
    command -v java >/dev/null 2>&1 || { sleep 15; rm /var/cache/oracle-jdk8-installer/jdk-*; apt-get install -f; }

    #if the previous did not install correctly we go nuclear, otherwise this loop will early exit
    for i in $(seq 30); do
      if $(command -v java >/dev/null 2>&1); then
        log "[install_java] installed Java!"
        return
      else
        sleep 5
        rm /var/cache/oracle-jdk8-installer/jdk-*;
        rm -f /var/lib/dpkg/info/oracle-java8-installer*
        rm /etc/apt/sources.list.d/*java*
        apt-get -yq purge oracle-java8-installer*
        apt-get -yq autoremove
        apt-get -yq clean
        (add-apt-repository -y ppa:webupd8team/java || (sleep 15; add-apt-repository -y ppa:webupd8team/java))
        apt-get -yq update
        install_java_package --reinstall
        log "[install_java] seeing if Java is installed after nuclear retry ${i}/30"
      fi
    done
    command -v java >/dev/null 2>&1 || { log "[install_java] Java did not get installed properly even after a retry and a forced installation" >&2; exit 50; }
}

# Install Elasticsearch
install_es()
{
    DOWNLOAD_URL="https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$ES_VERSION.deb?ultron=msft&gambit=azure"

    log "[install_es] installing Elasticsearch $ES_VERSION"
    log "[install_es] download location - $DOWNLOAD_URL"
    wget --retry-connrefused --waitretry=1 -q "$DOWNLOAD_URL" -O elasticsearch.deb
    local EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        log "[install_es] error downloading Elasticsearch $ES_VERSION"
        exit $EXIT_CODE
    fi
    log "[install_es] downloaded Elasticsearch $ES_VERSION"
    dpkg -i elasticsearch.deb
    log "[install_es] installed Elasticsearch $ES_VERSION"
    log "[install_es] disable Elasticsearch System-V style init scripts (will be using monit to manage Elasticsearch service)"
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
    if dpkg --compare-versions "$ES_VERSION" "lt" "6.3.0"; then
      log "[install_xpack] installing X-Pack plugins"
      $(plugin_cmd) install x-pack --batch
      log "[install_xpack] installed X-Pack plugins"
    else
      log "[install_xpack] X-Pack bundled by default. Skip installing"
    fi
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
  curl --output /dev/null --silent --head --fail $PROTOCOL://localhost:9200 -u elastic:$1 -H 'Content-Type: application/json' $CURL_SWITCH
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
  http_code=$(curl -H 'Content-Type: application/json' --write-out '\n%{http_code}\n' $PROTOCOL://localhost:9200/.security/$USER_TYPENAME/elastic -u elastic:$1 $CURL_SWITCH | tee /dev/fd/17 | tail -n 1)
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
      log "[wait_for_started] node is up!"
      return
    else
      sleep 5
      log "[wait_for_started] seeing if node is up after sleeping 5 seconds, retry ${i}/$TOTAL_RETRIES"
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
    http_code=$(curl -H 'Content-Type: application/json' --write-out '\n%{http_code}\n' "$@" $CURL_SWITCH | tee /dev/fd/17 | tail -n 1)
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
      log "[apply_security_settings] can already ping node using user provided credentials, exiting early!"
    else
      log "[apply_security_settings] start updating roles and users"

      local XPACK_USER_ENDPOINT="$PROTOCOL://localhost:9200/_xpack/security/user"
      local XPACK_ROLE_ENDPOINT="$PROTOCOL://localhost:9200/_xpack/security/role"

      #update builtin `elastic` account.
      local ADMIN_JSON=$(printf '{"password":"%s"}\n' $USER_ADMIN_PWD)
      echo $ADMIN_JSON | curl_ignore_409 -XPUT -u "elastic:$SEED_PASSWORD" "$XPACK_USER_ENDPOINT/elastic/_password" -d @-
      if [[ $? != 0 ]]; then
        #Make sure another deploy did not already change the elastic password
        curl_ignore_409 -XGET -u "elastic:$USER_ADMIN_PWD" "$PROTOCOL://localhost:9200/"
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

      #update builtin `logstash_system` account
      local LOGSTASH_JSON=$(printf '{"password":"%s"}\n' $USER_LOGSTASH_PWD)
      echo $LOGSTASH_JSON | curl_ignore_409 -XPUT -u "elastic:$USER_ADMIN_PWD" "$XPACK_USER_ENDPOINT/logstash_system/_password" -d @-
      if [[ $? != 0 ]];  then
        log "[apply_security_settings] could not update the builtin logstash_system user"
        exit 10
      fi
      log "[apply_security_settings] updated builtin logstash_system user password"

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
      log "[apply_security_settings] updated roles and users"
    fi
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
        return 0
    elif [[ -f $HTTP_CACERT_PATH ]]; then
        log "[configure_http_tls] HTTP CA already exists"
        return 0
    fi

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

      elif [[ -f $BIN_DIR/elasticsearch-certgen || -f $BIN_DIR/x-pack/certgen ]]; then
          local CERTGEN=$BIN_DIR/elasticsearch-certgen
          if [[ ! -f $CERTGEN ]]; then
              CERTGEN=$BIN_DIR/x-pack/certgen
          fi
          {
              echo -e "instances:"
              echo -e "  - name: \"$HOSTNAME\""
              echo -e "    dns:"
              echo -e "      - \"$HOSTNAME\""
              echo -e "    ip:"
              echo -e "      - \"$(hostname -I | xargs)\""
              # include the load balancer IP within the certificate, allowing
              # full verification mode in Kibana when accessing cluster through
              # internal loadbalancer
              echo -e "      - \"$INTERNAL_LOADBALANCER_IP\""
              echo -e "    filename: \"elasticsearch-http\""
          } >> $SSL_PATH/elasticsearch-http.yml

          log "[configure_http_tls] converting PKCS#12 HTTP CA to PEM"
          echo "$HTTP_CACERT_PASSWORD" | openssl pkcs12 -in $HTTP_CACERT_PATH -out $SSL_PATH/elasticsearch-http-ca.key -nocerts -nodes -passin stdin
          echo "$HTTP_CACERT_PASSWORD" | openssl pkcs12 -in $HTTP_CACERT_PATH -out $SSL_PATH/elasticsearch-http-ca.crt -clcerts -nokeys -passin stdin

          log "[configure_http_tls] generate HTTP cert using $CERTGEN"
          $CERTGEN --in $SSL_PATH/elasticsearch-http.yml --out $SSL_PATH/elasticsearch-http.zip \
              --cert $SSL_PATH/elasticsearch-http-ca.crt --key $SSL_PATH/elasticsearch-http-ca.key --pass "$HTTP_CACERT_PASSWORD"
          log "[configure_http_tls] generated HTTP cert"

          install_unzip
          log "[configure_http_tls] unzip HTTP cert"
          unzip $SSL_PATH/elasticsearch-http.zip -d $SSL_PATH
          log "[configure_http_tls] move HTTP cert"
          mv $SSL_PATH/elasticsearch-http/elasticsearch-http.crt $SSL_PATH/elasticsearch-http.crt
          log "[configure_http_tls] move HTTP private key"
          mv $SSL_PATH/elasticsearch-http/elasticsearch-http.key $SSL_PATH/elasticsearch-http.key

          # Encrypt the private key if there's a password
          if [[ -n "$HTTP_CERT_PASSWORD" ]]; then
            log "[configure_http_tls] encrypt HTTP private key"
            echo "$HTTP_CERT_PASSWORD" | openssl rsa -aes256 -in $SSL_PATH/elasticsearch-http.key -out $SSL_PATH/elasticsearch-http-encrypted.key -passout stdin
            mv $SSL_PATH/elasticsearch-http-encrypted.key $SSL_PATH/elasticsearch-http.key
          fi
      else
          log "[configure_http_tls] no certutil or certgen tool could be found to generate a HTTP cert"
          exit 12
      fi
    fi

    log "[configure_http_tls] configuring SSL/TLS for HTTP layer"
    echo "xpack.security.http.ssl.enabled: true" >> $ES_CONF

    if [[ "${ES_VERSION}" == \6* ]]; then
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
      else
          # dealing with PEM certs
          echo "xpack.security.http.ssl.certificate: $SSL_PATH/elasticsearch-http.crt" >> $ES_CONF
          echo "xpack.security.http.ssl.key: $SSL_PATH/elasticsearch-http.key" >> $ES_CONF
          if [[ $(stat -c %s $SSL_PATH/elasticsearch-http-ca.crt 2>/dev/null) -ne 0 ]]; then
              echo "xpack.security.http.ssl.certificate_authorities: [ $SSL_PATH/elasticsearch-http-ca.crt ]" >> $ES_CONF
          fi

          if [[ -n "$HTTP_CERT_PASSWORD" ]]; then
              log "[configure_http_tls] configure HTTP key password in keystore"
              create_keystore_if_not_exists
              echo "$HTTP_CERT_PASSWORD" | $KEY_STORE add xpack.security.http.ssl.secure_key_passphrase -xf
          fi
      fi
    else
      # Elasticsearch 5.x does not support PKCS#12 archives, so any passed or generated certs will need to be converted to PEM
      if [[ -f $HTTP_CERT_PATH ]]; then
          log "[configure_http_tls] convert PKCS#12 HTTP to PEM"
          echo "$HTTP_CERT_PASSWORD" | openssl pkcs12 -in $HTTP_CERT_PATH -out $SSL_PATH/elasticsearch-http.crt -nokeys -passin stdin
          echo "$HTTP_CERT_PASSWORD" | openssl pkcs12 -in $HTTP_CERT_PATH -out $SSL_PATH/elasticsearch-http.key -nocerts -nodes -passin stdin
          echo "$HTTP_CERT_PASSWORD" | openssl pkcs12 -in $HTTP_CERT_PATH -out $SSL_PATH/elasticsearch-http-ca.crt -cacerts -nokeys -chain -passin stdin
      fi

      echo "xpack.security.http.ssl.certificate: $SSL_PATH/elasticsearch-http.crt" >> $ES_CONF
      echo "xpack.security.http.ssl.key: $SSL_PATH/elasticsearch-http.key" >> $ES_CONF

      if [[ $(stat -c %s $SSL_PATH/elasticsearch-http-ca.crt 2>/dev/null) -ne 0 ]]; then
          echo "xpack.security.http.ssl.certificate_authorities: [ $SSL_PATH/elasticsearch-http-ca.crt ]" >> $ES_CONF
      fi

      if [[ -n "$HTTP_CERT_PASSWORD" ]]; then
          # Encrypt the private key if there's a password
          log "[configure_http_tls] encrypt HTTP private key"
          echo "$HTTP_CERT_PASSWORD" | openssl rsa -aes256 -in $SSL_PATH/elasticsearch-http.key -out $SSL_PATH/elasticsearch-http-encrypted.key -passout stdin
          mv $SSL_PATH/elasticsearch-http-encrypted.key $SSL_PATH/elasticsearch-http.key

          if dpkg --compare-versions "$ES_VERSION" "ge" "5.6.0"; then
            log "[configure_http_tls] configure HTTP key password in keystore"
            create_keystore_if_not_exists
            echo "$HTTP_CERT_PASSWORD" | $KEY_STORE add xpack.security.http.ssl.secure_key_passphrase -xf
          else
            log "[configure_http_tls] configure HTTP key password in config"
            echo "xpack.security.http.ssl.key_passphrase: \"$HTTP_CERT_PASSWORD\"" >> $ES_CONF
          fi
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
        return 0
    fi

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

    # Generate certs with certutil or certgen
    if [[ -f $BIN_DIR/elasticsearch-certutil || -f $BIN_DIR/x-pack/certutil ]]; then
        local CERTUTIL=$BIN_DIR/elasticsearch-certutil
        if [[ ! -f $CERTUTIL ]]; then
            CERTUTIL=$BIN_DIR/x-pack/certutil
        fi

        log "[configure_transport_tls] generate Transport cert using $CERTUTIL"
        $CERTUTIL cert --name "$HOSTNAME" --dns "$HOSTNAME" --ip $(hostname -I) --out $TRANSPORT_CERT_PATH --pass "$TRANSPORT_CERT_PASSWORD" --ca $TRANSPORT_CACERT_PATH --ca-pass "$TRANSPORT_CACERT_PASSWORD"
        log "[configure_transport_tls] generated Transport cert"

    elif [[ -f $BIN_DIR/elasticsearch-certgen || -f $BIN_DIR/x-pack/certgen ]]; then
        local CERTGEN=$BIN_DIR/elasticsearch-certgen
        if [[ -f $BIN_DIR/x-pack/certgen ]]; then
            CERTGEN=$BIN_DIR/x-pack/certgen
        fi
        {
            echo -e "instances:"
            echo -e "  - name: \"$HOSTNAME\""
            echo -e "    dns:"
            echo -e "      - \"$HOSTNAME\""
            echo -e "    ip:"
            echo -e "      - \"$(hostname -I | xargs)\""
            echo -e "    filename: \"elasticsearch-transport\""
        } >> $SSL_PATH/elasticsearch-transport.yml

        log "[configure_transport_tls] convert PKCS#12 Transport CA to PEM"
        echo "$TRANSPORT_CACERT_PASSWORD" | openssl pkcs12 -in $TRANSPORT_CACERT_PATH -out $SSL_PATH/elasticsearch-transport-ca.key -nocerts -nodes -passin stdin
        echo "$TRANSPORT_CACERT_PASSWORD" | openssl pkcs12 -in $TRANSPORT_CACERT_PATH -out $SSL_PATH/elasticsearch-transport-ca.crt -clcerts -nokeys -chain -passin stdin

        log "[configure_transport_tls] generate Transport cert using $CERTGEN"
        $CERTGEN --in $SSL_PATH/elasticsearch-transport.yml --out $SSL_PATH/elasticsearch-transport.zip --cert $SSL_PATH/elasticsearch-transport-ca.crt --key $SSL_PATH/elasticsearch-transport-ca.key --pass "$TRANSPORT_CACERT_PASSWORD"

        install_unzip
        log "[configure_transport_tls] unzip Transport cert"
        unzip $SSL_PATH/elasticsearch-transport.zip -d $SSL_PATH
        log "[configure_transport_tls] move Transport cert"
        mv $SSL_PATH/elasticsearch-transport/elasticsearch-transport.crt $SSL_PATH/elasticsearch-transport.crt
        log "[configure_transport_tls] move Transport private key"
        mv $SSL_PATH/elasticsearch-transport/elasticsearch-transport.key $SSL_PATH/elasticsearch-transport.key

        # Encrypt the private key if there's a password
        if [[ -n "$TRANSPORT_CERT_PASSWORD" ]]; then
          log "[configure_transport_tls] encrypt Transport key"
          echo "$TRANSPORT_CERT_PASSWORD" | openssl rsa -aes256 -in $SSL_PATH/elasticsearch-transport.key -out $SSL_PATH/elasticsearch-transport-encrypted.key -passout stdin
          mv $SSL_PATH/elasticsearch-transport-encrypted.key $SSL_PATH/elasticsearch-transport.key
        fi
    else
        log "[configure_transport_tls] no certutil or certgen tool could be found to generate a Transport cert"
        exit 12
    fi

    log "[configure_transport_tls] configuring SSL/TLS for Transport layer"
    echo "xpack.security.transport.ssl.enabled: true" >> $ES_CONF

    if [[ "${ES_VERSION}" == \6* ]]; then
      if [[ -f $TRANSPORT_CERT_PATH ]]; then
          echo "xpack.security.transport.ssl.keystore.path: $TRANSPORT_CERT_PATH" >> $ES_CONF
          echo "xpack.security.transport.ssl.truststore.path: $TRANSPORT_CERT_PATH" >> $ES_CONF
          if [[ -n "$TRANSPORT_CERT_PASSWORD" ]]; then
              create_keystore_if_not_exists
              log "[configure_transport_tls] configure Transport key password in keystore"
              echo "$TRANSPORT_CERT_PASSWORD" | $KEY_STORE add xpack.security.transport.ssl.keystore.secure_password -xf
              echo "$TRANSPORT_CERT_PASSWORD" | $KEY_STORE add xpack.security.transport.ssl.truststore.secure_password -xf
          fi
      else
          # dealing with PEM certs
          echo "xpack.security.transport.ssl.certificate: $SSL_PATH/elasticsearch-transport.crt" >> $ES_CONF
          echo "xpack.security.transport.ssl.key: $SSL_PATH/elasticsearch-transport.key" >> $ES_CONF
          echo "xpack.security.transport.ssl.certificate_authorities: [ $SSL_PATH/elasticsearch-transport-ca.crt ]" >> $ES_CONF
          if [[ -n "$TRANSPORT_CERT_PASSWORD" ]]; then
              log "[configure_transport_tls] configure Transport key password in keystore"
              create_keystore_if_not_exists
              echo "$TRANSPORT_CERT_PASSWORD" | $KEY_STORE add xpack.security.transport.ssl.secure_key_passphrase -xf
          fi
      fi
    else
      if [[ -f $TRANSPORT_CERT_PATH ]]; then
          log "[configure_transport_tls] converting PKCS#12 Transport archive to PEM"
          echo "$TRANSPORT_CERT_PASSWORD" | openssl pkcs12 -in $TRANSPORT_CERT_PATH -out $SSL_PATH/elasticsearch-transport.crt -clcerts -nokeys -passin stdin
          echo "$TRANSPORT_CERT_PASSWORD" | openssl pkcs12 -in $TRANSPORT_CERT_PATH -out $SSL_PATH/elasticsearch-transport.key -nocerts -nodes -passin stdin
          echo "$TRANSPORT_CERT_PASSWORD" | openssl pkcs12 -in $TRANSPORT_CERT_PATH -out $SSL_PATH/elasticsearch-transport-ca.crt -cacerts -nokeys -chain -passin stdin
      fi

      echo "xpack.security.transport.ssl.certificate: $SSL_PATH/elasticsearch-transport.crt" >> $ES_CONF
      echo "xpack.security.transport.ssl.key: $SSL_PATH/elasticsearch-transport.key" >> $ES_CONF
      echo "xpack.security.transport.ssl.certificate_authorities: [ $SSL_PATH/elasticsearch-transport-ca.crt ]" >> $ES_CONF
      if [[ -n "$TRANSPORT_CERT_PASSWORD" ]]; then
          if dpkg --compare-versions "$ES_VERSION" "ge" "5.6.0"; then
              log "[configure_transport_tls] configure Transport key password in keystore"
              create_keystore_if_not_exists
              echo "$TRANSPORT_CERT_PASSWORD" | $KEY_STORE add xpack.security.transport.ssl.secure_key_passphrase -xf
          else
              log "[configure_transport_tls] configure Transport key password in config"
              echo "xpack.security.transport.ssl.key_passphrase: \"$TRANSPORT_CERT_PASSWORD\"" >> $ES_CONF
          fi
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
  local METADATA=$(curl -sH Metadata:true "http://169.254.169.254/metadata/instance?api-version=2017-08-01")
  local FAULT_DOMAIN=$(jq -r .compute.platformFaultDomain <<< $METADATA)
  local UPDATE_DOMAIN=$(jq -r .compute.platformUpdateDomain <<< $METADATA)
  echo "node.attr.fault_domain: $FAULT_DOMAIN" >> $ES_CONF
  echo "node.attr.update_domain: $UPDATE_DOMAIN" >> $ES_CONF
  log "[configure_awareness_attributes] configure shard allocation awareness using fault_domain and update_domain"
  echo "cluster.routing.allocation.awareness.attributes: fault_domain,update_domain" >> $ES_CONF
}

configure_elasticsearch_yaml()
{
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
    log "[configure_elasticsearch_yaml] update configuration with hosts configuration of $UNICAST_HOSTS"
    echo "discovery.zen.ping.unicast.hosts: $UNICAST_HOSTS" >> $ES_CONF

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

    echo "discovery.zen.minimum_master_nodes: $MINIMUM_MASTER_NODES" >> $ES_CONF
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
      if [[ "${ES_VERSION}" == \6* ]]; then
        log "[configure_elasticsearch_yaml] configure storage for repository-azure plugin in keystore"
        create_keystore_if_not_exists
        echo "$STORAGE_ACCOUNT" | /usr/share/elasticsearch/bin/elasticsearch-keystore add azure.client.default.account -xf
        echo "$STORAGE_KEY" | /usr/share/elasticsearch/bin/elasticsearch-keystore add azure.client.default.key -xf
        echo "azure.client.default.endpoint_suffix: $STORAGE_SUFFIX" >> $ES_CONF
      else
        log "[configure_elasticsearch_yaml] configure storage for repository-azure plugin in $ES_CONF"
        echo "cloud.azure.storage.default.account: ${STORAGE_ACCOUNT}" >> $ES_CONF
        echo "cloud.azure.storage.default.key: ${STORAGE_KEY}" >> $ES_CONF
      fi
    fi

    if [ ${INSTALL_XPACK} -ne 0 ]; then
        if dpkg --compare-versions "$ES_VERSION" "ge" "6.3.0"; then
            log "[configure_elasticsearch_yaml] Set generated license type to trial"
            echo "xpack.license.self_generated.type: trial" >> $ES_CONF
        fi
        log "[configure_elasticsearch_yaml] Set X-Pack Security enabled"
        echo "xpack.security.enabled: true" >> $ES_CONF
    fi

    # Additional yaml configuration
    if [[ -n "$YAML_CONFIGURATION" ]]; then
        log "[configure_elasticsearch_yaml] include additional yaml configuration"

        local SKIP_LINES="cluster.name node.name path.data discovery.zen.ping.unicast.hosts "
        SKIP_LINES+="node.master node.data discovery.zen.minimum_master_nodes network.host "
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
        if [ $EXIT_CODE -ne 0 ]; then
            log "[configure_elasticsearch_yaml] errors in yaml configuration. exiting"
            exit 11
        fi
    fi

    # Swap is disabled by default in Ubuntu Azure VMs, no harm in adding memory lock
    log "[configure_elasticsearch_yaml] setting bootstrap.memory_lock: true"
    echo "bootstrap.memory_lock: true" >> $ES_CONF

    # Configure SSL/TLS for HTTP layer
    if [[ -n "${HTTP_CERT}" || -n "$HTTP_CACERT" && ${INSTALL_XPACK} -ne 0 ]]; then
        configure_http_tls $ES_CONF
    fi

    # Configure TLS for Transport layer
    if [[ -n "${TRANSPORT_CACERT}" && ${INSTALL_XPACK} -ne 0 ]]; then
        configure_transport_tls $ES_CONF
    fi

    # Configure SAML realm only for valid versions of Elasticsearch and if the conditions are met
    if [[ $(dpkg --compare-versions "$ES_VERSION" "ge" "6.2.0") -eq 0 && -n "$SAML_METADATA_URI" && -n "$SAML_SP_URI" && ( -n "$HTTP_CERT" || -n "$HTTP_CACERT" ) && ${INSTALL_XPACK} -ne 0 ]]; then
      log "[configure_elasticsearch_yaml] configuring SAML realm named 'saml_aad' for $SAML_SP_URI"
      [ -d /etc/elasticsearch/saml ] || mkdir -p /etc/elasticsearch/saml
      wget --retry-connrefused --waitretry=1 -q "$SAML_METADATA_URI" -O /etc/elasticsearch/saml/metadata.xml
      chown -R elasticsearch:elasticsearch /etc/elasticsearch/saml
      SAML_SP_URI="${SAML_SP_URI%/}"
      # extract the entityID from the metadata file
      local IDP_ENTITY_ID="$(grep -oP '\sentityID="(.*?)"\s' /etc/elasticsearch/saml/metadata.xml | sed 's/^.*"\(.*\)".*/\1/')"
      {
          echo -e ""
          echo -e "xpack.security.authc.realms.saml_aad:"
          echo -e "  type: saml"
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
    install_repository_azure_plugin
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
