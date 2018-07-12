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
    echo "This script bootstraps an Elasticsearch cluster on a data node"
    echo "Parameters:"
    echo "-n elasticsearch cluster name"
    echo "-v elasticsearch version 2.3.3"
    echo "-p hostname prefix of nodes for unicast discovery"
    echo "-m heap size in megabytes to allocate to JVM"

    echo "-d cluster uses dedicated masters"
    echo "-Z <number of nodes> hint to the install script how many data nodes we are provisioning"
    echo "-Y <number of nodes> hint to the install script how many client nodes we are provisioning"

    echo "-A admin password"
    echo "-R read password"
    echo "-K kibana user password"
    echo "-S logstash_system user password"
    echo "-X enable anonymous access with monitoring role (for health probes)"

    echo "-l install plugins"
    echo "-L <plugin;plugin> install additional plugins"

    echo "-D Internal Load balancer IP. Used as an IP SAN when generating certs with HTTP CA"
    echo "-H base64 encoded PKCS#12 archive (.p12/.pfx) containing the key and certificate used to secure the HTTP layer"
    echo "-G password for PKCS#12 archive (.p12/.pfx) containing the key and certificate used to secure the HTTP layer"
    echo "-V base64 encoded PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure the HTTP layer"
    echo "-J password for PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure the HTTP layer"

    echo "-T base64 encoded PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure the transport layer"
    echo "-W password for PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure the transport layer"
    echo "-N password for the generated PKCS#12 archive used to secure the transport layer"

    echo "-O URI from which to retrieve the metadata file for the Identity Provider to configure SAML Single-Sign-On"
    echo "-P Public domain name (and optional port) for the instance of Kibana to configure SAML Single-Sign-On"

    echo "-U api url"
    echo "-I marketing id"
    echo "-c company name"
    echo "-e email address"
    echo "-f first name"
    echo "-m last name"
    echo "-t job title"
    echo "-s cluster setup"
    echo "-o country"

    echo "-j install azure cloud plugin for snapshot and restore"
    echo "-a set the default storage account for azure cloud plugin"
    echo "-k set the key for the default storage account for azure cloud plugin"

    echo "-h view this help content"
}

log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/arm-install.log
}

log "Begin execution of Data Node Install script extension"

#########################
# Paramater handling
#########################

CLUSTER_NAME="elasticsearch"
NAMESPACE_PREFIX=""
ES_VERSION="6.2.4"
ES_HEAP=0
INSTALL_XPACK=0
INSTALL_ADDITIONAL_PLUGINS=""
YAML_CONFIGURATION=""
INSTALL_AZURECLOUD_PLUGIN=0
STORAGE_ACCOUNT=""
STORAGE_KEY=""
CLUSTER_USES_DEDICATED_MASTERS=0
DATANODE_COUNT=0
DATA_ONLY_NODE=0

USER_ADMIN_PWD="changeme"
USER_READ_PWD="changeme"
USER_KIBANA_PWD="changeme"
BOOTSTRAP_PASSWORD="changeme"
ANONYMOUS_ACCESS=0

HTTP_CERT=""
HTTP_CERT_PASSWORD=""
HTTP_CACERT=""
HTTP_CACERT_PASSWORD=""
INTERNAL_LOADBALANCER_IP=""

TRANSPORT_CACERT=""
TRANSPORT_CACERT_PASSWORD=""
TRANSPORT_CERT_PASSWORD=""

SAML_METADATA_URI=""
SAML_SP_URI=""

API_URL=""
MARKETING_ID=""
COMPANY_NAME=""
EMAIL=""
FIRST_NAME=""
LAST_NAME=""
JOB_TITLE=""
CLUSTER_SETUP=""
COUNTRY=""
INSTALL_SWITCHES=""

#Loop through options passed
while getopts :n:m:v:A:R:K:S:Z:p:U:I:c:e:f:g:t:s:o:a:k:L:C:B:E:H:G:T:W:V:J:N:D:O:P:Xxyzldjh optname; do
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
    l) #install X-Pack
      INSTALL_XPACK=1
      ;;
    j) #install azure cloud plugin
      INSTALL_AZURECLOUD_PLUGIN=1
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
    a) #azure storage account for azure cloud plugin
      STORAGE_ACCOUNT="${OPTARG}"
      ;;
    k) #azure storage account key for azure cloud plugin
      STORAGE_KEY="${OPTARG}"
      ;;
    E) #azure storage account endpoint suffix
      STORAGE_SUFFIX="${OPTARG}"
      ;;
    d) #cluster is using dedicated master nodes
      CLUSTER_USES_DEDICATED_MASTERS=1
      ;;
    x) #master node
      log "master node argument will be ignored"
      ;;
    y) #client node
      log "client node argument will be ignored"
      ;;
    z) #data node
      DATA_ONLY_NODE=1
      ;;
    p) #namespace prefix for nodes
      NAMESPACE_PREFIX="${OPTARG}"
      ;;
    U) #set API url
      API_URL="${OPTARG}"
      ;;
    I) #set marketing id
      MARKETING_ID="${OPTARG}"
      ;;
    c) #set company name
      COMPANY_NAME="${OPTARG}"
      ;;
    e) #set email
      EMAIL="${OPTARG}"
      ;;
    f) #set first name
      FIRST_NAME="${OPTARG}"
      ;;
    g) #set last name
      LAST_NAME="${OPTARG}"
      ;;
    t) #set job title
      JOB_TITLE="${OPTARG}"
      ;;
    o) #set country
      COUNTRY="${OPTARG}"
      ;;
    s) #set cluster setup
      CLUSTER_SETUP="${OPTARG}"
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

if [ $CLUSTER_USES_DEDICATED_MASTERS -eq 1 ]; then
  INSTALL_SWITCHES="$INSTALL_SWITCHES -d"
fi

if [ $DATA_ONLY_NODE -eq 1 ]; then
  INSTALL_SWITCHES="$INSTALL_SWITCHES -z"
fi

if [ $INSTALL_AZURECLOUD_PLUGIN -eq 1 ]; then
  INSTALL_SWITCHES="$INSTALL_SWITCHES -j"
fi

if [ $INSTALL_XPACK -eq 1 ]; then
  INSTALL_SWITCHES="$INSTALL_SWITCHES -l"
fi

if [ $ANONYMOUS_ACCESS -eq 1 ]; then
  INSTALL_SWITCHES="$INSTALL_SWITCHES -X"
fi

# install elasticsearch
bash elasticsearch-ubuntu-install.sh -n "$CLUSTER_NAME" -m $ES_HEAP -v "$ES_VERSION" -A "$USER_ADMIN_PWD" -R "$USER_READ_PWD" -K "$USER_KIBANA_PWD" -S "$USER_LOGSTASH_PWD" -B "$BOOTSTRAP_PASSWORD" -Z "$DATANODE_COUNT" -p "$NAMESPACE_PREFIX" -a "$STORAGE_ACCOUNT" -k "$STORAGE_KEY" -E "$STORAGE_SUFFIX" -L "$INSTALL_ADDITIONAL_PLUGINS" -C "$YAML_CONFIGURATION" -H "$HTTP_CERT" -G "$HTTP_CERT_PASSWORD" -V "$HTTP_CACERT" -J "$HTTP_CACERT_PASSWORD" -T "$TRANSPORT_CACERT" -W "$TRANSPORT_CACERT_PASSWORD" -N "$TRANSPORT_CERT_PASSWORD" -D "$INTERNAL_LOADBALANCER_IP"  -O "$SAML_METADATA_URI" -P "$SAML_SP_URI" $INSTALL_SWITCHES
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  log "installing Elasticsearch returned exit code $EXIT_CODE"
  exit $EXIT_CODE
fi

bash user-information.sh -U "$API_URL" -I "$MARKETING_ID" -c "$COMPANY_NAME" -e "$EMAIL" -f "$FIRST_NAME" -l "$LAST_NAME" -t "$JOB_TITLE" -s "$CLUSTER_SETUP" -o "$COUNTRY"
EXIT_CODE=$?
log "End execution of Data Node Install script extension"
exit $EXIT_CODE
