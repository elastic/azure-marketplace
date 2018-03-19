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
    echo "This script installs kibana on a dedicated VM in the elasticsearch ARM template cluster"
    echo ""
    echo "Options:"
    echo "    -n      elasticsearch cluster name"
    echo "    -v      kibana version e.g 6.2.2"
    echo "    -u      elasticsearch url e.g. http://10.0.0.4:9200"
    echo "    -l      install plugins true/false"
    echo "    -S      kibana password"
    echo "    -C      kibana cert to encrypt communication between the browser and Kibana"
    echo "    -K      kibana key to encrypt communication between the browser and Kibana"
    echo "    -P      kibana key passphrase to decrypt the private key (optional as the key may not be encrypted)"
    echo "    -Y      <yaml\nyaml> additional yaml configuration"
    echo "    -H      base64 encoded PKCS#12 archive (.p12/.pfx) containing the key and certificate used to secure Elasticsearch HTTP layer"
    echo "    -G      Password for PKCS#12 archive (.p12/.pfx) containing the key and certificate used to secure Elasticsearch HTTP layer"
    echo "    -V      base64 encoded PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure Elasticsearch HTTP layer"
    echo "    -J      Password for PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure Elasticsearch HTTP layer"
    echo "    -U      Public domain name (and optional port) for this instance of Kibana to configure SAML Single-Sign-On"
    echo "    -h      view this help content"
}

# Custom logging with time so we can easily relate running times, also log to separate file so order is guaranteed.
# The Script extension output the stdout/err buffer in intervals with duplicates.
log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/arm-install.log
}

log "Begin execution of Kibana script extension on ${HOSTNAME}"
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

if service --status-all | grep -Fq 'kibana'; then
  log "Kibana already installed."
  exit 0
fi

#########################
# Parameter handling
#########################

#Script Parameters
CLUSTER_NAME="elasticsearch"
KIBANA_VERSION="6.2.4"
#Default internal load balancer ip
ELASTICSEARCH_URL="http://10.0.0.4:9200"
INSTALL_XPACK=0
USER_KIBANA_PWD="changeme"
SSL_CERT=""
SSL_KEY=""
SSL_PASSPHRASE=""
YAML_CONFIGURATION=""
HTTP_CERT=""
HTTP_CERT_PASSWORD=""
HTTP_CACERT=""
HTTP_CACERT_PASSWORD=""
SAML_SP_URI=""

#Loop through options passed
while getopts :n:v:u:S:C:K:P:Y:H:G:V:J:U:lh optname; do
  log "Option $optname set"
  case $optname in
    n) #set cluster name
      CLUSTER_NAME="${OPTARG}"
      ;;
    v) #kibana version number
      KIBANA_VERSION="${OPTARG}"
      ;;
    u) #elasticsearch url
      ELASTICSEARCH_URL="${OPTARG}"
      ;;
    S) #security kibana pwd
      USER_KIBANA_PWD="${OPTARG}"
      ;;
    l) #install X-Pack
      INSTALL_XPACK=1
      ;;
    C) #kibana ssl cert
      SSL_CERT="${OPTARG}"
      ;;
    K) #kibana ssl key
      SSL_KEY="${OPTARG}"
      ;;
    P) #kibana ssl key passphrase
      SSL_PASSPHRASE="${OPTARG}"
      ;;
    H) #Elasticsearch certificate
      HTTP_CERT="${OPTARG}"
      ;;
    G) #Elasticsearch certificate password
      HTTP_CERT_PASSWORD="${OPTARG}"
      ;;
    V) #Elasticsearch CA certificate
      HTTP_CACERT="${OPTARG}"
      ;;
    J) #Elasticsearch CA certificate password
      HTTP_CACERT_PASSWORD="${OPTARG}"
      ;;
    U) #Service Provider URI
      SAML_SP_URI="${OPTARG}"
      ;;
    Y) #kibana additional yml configuration
      YAML_CONFIGURATION="${OPTARG}"
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

log "Installing Kibana $KIBANA_VERSION for Elasticsearch cluster: $CLUSTER_NAME"
log "Installing X-Pack plugins is set to: $INSTALL_XPACK"
log "Kibana will talk to Elasticsearch over $ELASTICSEARCH_URL"

#########################
# Installation steps as functions
#########################

download_kibana()
{
    log "[download_kibana] Download Kibana $KIBANA_VERSION"
    local DOWNLOAD_URL="https://artifacts.elastic.co/downloads/kibana/kibana-$KIBANA_VERSION-amd64.deb"
    log "[download_kibana] Download location $DOWNLOAD_URL"
    wget --retry-connrefused --waitretry=1 -q "$DOWNLOAD_URL" -O "kibana-$KIBANA_VERSION.deb"
    local EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        log "[download_kibana] Error downloading Kibana $KIBANA_VERSION"
        exit $EXIT_CODE
    fi
    log "[download_kibana] Installing Kibana $KIBANA_VERSION"
    dpkg -i "kibana-$KIBANA_VERSION.deb"
    log "[download_kibana] Installed Kibana $KIBANA_VERSION"
}

## Security
##----------------------------------

install_pwgen()
{
    log "[install_pwgen] Installing pwgen tool if needed"
    if [ $(dpkg-query -W -f='${Status}' pwgen 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
      (apt-get -yq install pwgen || (sleep 15; apt-get -yq install pwgen))
    fi
}

configuration_and_plugins()
{
    local KIBANA_CONF=/etc/kibana/kibana.yml
    local SSL_PATH=/etc/kibana/ssl
    # backup the current config
    mv $KIBANA_CONF $KIBANA_CONF.bak

    log "[configuration_and_plugins] Configuring kibana.yml"

    # set the elasticsearch URL
    echo "elasticsearch.url: \"$ELASTICSEARCH_URL\"" >> $KIBANA_CONF
    echo "server.host:" $(hostname -I) >> $KIBANA_CONF
    # specify kibana log location
    echo "logging.dest: /var/log/kibana.log" >> $KIBANA_CONF
    touch /var/log/kibana.log
    chown kibana: /var/log/kibana.log

    # set logging to silent by default
    echo "logging.silent: true" >> $KIBANA_CONF

    # install x-pack
    if [ ${INSTALL_XPACK} -ne 0 ]; then
      echo "elasticsearch.username: kibana" >> $KIBANA_CONF
      echo "elasticsearch.password: \"$USER_KIBANA_PWD\"" >> $KIBANA_CONF

      install_pwgen
      local ENCRYPTION_KEY=$(pwgen 64 1)
      echo "xpack.security.encryptionKey: \"$ENCRYPTION_KEY\"" >> $KIBANA_CONF
      log "[configuration_and_plugins] X-Pack Security encryption key generated"
      ENCRYPTION_KEY=$(pwgen 64 1)
      echo "xpack.reporting.encryptionKey: \"$ENCRYPTION_KEY\"" >> $KIBANA_CONF
      log "[configuration_and_plugins] X-Pack Reporting encryption key generated"

      log "[configuration_and_plugins] Installing X-Pack plugin"
      /usr/share/kibana/bin/kibana-plugin install x-pack
      log "[configuration_and_plugins] Installed X-Pack plugin"
    fi

    # configure HTTPS if cert and private key supplied
    if [[ -n "${SSL_CERT}" && -n "${SSL_KEY}" ]]; then
      [ -d $SSL_PATH ] || mkdir -p $SSL_PATH
      log "[configuration_and_plugins] Save kibana cert to file"
      echo ${SSL_CERT} | base64 -d | tee $SSL_PATH/kibana.crt
      log "[configuration_and_plugins] Save kibana key to file"
      echo ${SSL_KEY} | base64 -d | tee $SSL_PATH/kibana.key

      log "[configuration_and_plugins] Configuring SSL/TLS to Kibana"
      echo "server.ssl.enabled: true" >> $KIBANA_CONF
      echo "server.ssl.key: $SSL_PATH/kibana.key" >> $KIBANA_CONF
      echo "server.ssl.certificate: $SSL_PATH/kibana.crt" >> $KIBANA_CONF
      if [[ -n "${SSL_PASSPHRASE}" ]]; then
          echo "server.ssl.keyPassphrase: \"$SSL_PASSPHRASE\"" >> $KIBANA_CONF
      fi
      log "[configuration_and_plugins] Configured SSL/TLS to Kibana"
    fi

    # configure HTTPS communication with Elasticsearch if cert supplied and x-pack installed.
    # Kibana x-pack installed implies it's also installed for Elasticsearch
    if [[ -n "${HTTP_CERT}" || -n "${HTTP_CACERT}" && ${INSTALL_XPACK} -ne 0 ]]; then
      [ -d $SSL_PATH ] || mkdir -p $SSL_PATH

      if [[ -n "${HTTP_CERT}" ]]; then
        # convert PKCS#12 certificate to PEM format
        log "[configuration_and_plugins] Save PKCS#12 archive for Elasticsearch HTTP to file"
        echo ${HTTP_CERT} | base64 -d | tee $SSL_PATH/elasticsearch-http.p12
        log "[configuration_and_plugins] Extract CA cert from PKCS#12 archive for Elasticsearch HTTP"
        echo "$HTTP_CERT_PASSWORD" | openssl pkcs12 -in $SSL_PATH/elasticsearch-http.p12 -out $SSL_PATH/elasticsearch-http-ca.crt -cacerts -nokeys -chain -passin stdin

        log "[configuration_and_plugins] Configuring TLS for Elasticsearch"
        if [[ $(stat -c %s $SSL_PATH/elasticsearch-http-ca.crt 2>/dev/null) -eq 0 ]]; then
            log "[configuration_and_plugins] No CA cert extracted from HTTP cert. Setting verification mode to none"
            echo "elasticsearch.ssl.verificationMode: none" >> $KIBANA_CONF
        else
            log "[configuration_and_plugins] CA cert extracted from HTTP PKCS#12 archive. Setting verification mode to certificate"
            echo "elasticsearch.ssl.verificationMode: certificate" >> $KIBANA_CONF
            echo "elasticsearch.ssl.certificateAuthorities: [ $SSL_PATH/elasticsearch-http-ca.crt ]" >> $KIBANA_CONF
        fi

      else

        # convert PKCS#12 CA certificate to PEM format
        local HTTP_CACERT_FILENAME=elasticsearch-http-ca.p12
        log "[configuration_and_plugins] Save PKCS#12 archive for Elasticsearch HTTP CA to file"
        echo ${HTTP_CACERT} | base64 -d | tee $SSL_PATH/$HTTP_CACERT_FILENAME
        log "[configuration_and_plugins] Convert PKCS#12 archive for Elasticsearch HTTP CA to PEM format"
        echo "$HTTP_CACERT_PASSWORD" | openssl pkcs12 -in $SSL_PATH/$HTTP_CACERT_FILENAME -out $SSL_PATH/elasticsearch-http-ca.crt -clcerts -nokeys -chain -passin stdin

        log "[configuration_and_plugins] Configuring TLS for Elasticsearch"
        if [[ $(stat -c %s $SSL_PATH/elasticsearch-http-ca.crt 2>/dev/null) -eq 0 ]]; then
            log "[configuration_and_plugins] No CA cert extracted from HTTP CA. Setting verification mode to none"
            echo "elasticsearch.ssl.verificationMode: none" >> $KIBANA_CONF
        else
            log "[configuration_and_plugins] CA cert extracted from HTTP CA PKCS#12 archive. Setting verification mode to full"
            echo "elasticsearch.ssl.verificationMode: full" >> $KIBANA_CONF
            log "[configuration_and_plugins] Set CA cert in certificate authorities"
            echo "elasticsearch.ssl.certificateAuthorities: [ $SSL_PATH/elasticsearch-http-ca.crt ]" >> $KIBANA_CONF
        fi
      fi
      chown -R kibana: $SSL_PATH
      log "[configuration_and_plugins] Configured TLS for Elasticsearch"
    fi

    # Configure SAML Single-Sign-On
    if [[ -n "$SAML_SP_URI" && ${INSTALL_XPACK} -ne 0 ]]; then
      log "[configuration_and_plugins] Configuring Kibana for SAML Single-Sign-On"
      # Allow both saml and basic realms
      echo "xpack.security.authProviders: [ saml,basic ]" >> $KIBANA_CONF
      echo "server.xsrf.whitelist: [ /api/security/v1/saml ]" >> $KIBANA_CONF

      local PROTOCOL="`echo $SAML_SP_URI | grep '://' | sed -e's,^\(.*://\).*,\1,g'`"
      local HOSTNAME_AND_PORT=`echo $SAML_SP_URI | sed -e s,$PROTOCOL,,g`
      local HOSTNAME=`echo $HOSTNAME_AND_PORT | sed -e s,.*@,,g | cut -d: -f1`
      local PORT=`echo $HOSTNAME_AND_PORT | grep : | cut -d: -f2`
      if [[ -z "$PORT" ]]; then
        if [[ "$PROTOCOL" == "https://" ]]; then
          PORT=443
        else
          PORT=80
        fi
      fi

      # Kibana is reached through a Public IP address (or a provided URI)
      # so needs to be configured with this for SAML SSO
      echo "xpack.security.public.protocol: ${PROTOCOL%://}" >> $KIBANA_CONF
      echo "xpack.security.public.hostname: \"${HOSTNAME%/}\"" >> $KIBANA_CONF
      echo "xpack.security.public.port: ${PORT%/}" >> $KIBANA_CONF
      log "[configuration_and_plugins] Configured Kibana for SAML Single-Sign-On"
    fi

    # Additional yaml configuration
    if [[ -n "$YAML_CONFIGURATION" ]]; then
        log "[configuration_and_plugins] include additional yaml configuration"
        local SKIP_LINES="elasticsearch.username elasticsearch.password "
        SKIP_LINES+="server.ssl.key server.ssl.cert server.ssl.enabled "
        SKIP_LINES+="xpack.security.encryptionKey xpack.reporting.encryptionKey "
        SKIP_LINES+="elasticsearch.url server.host logging.dest logging.silent "
        SKIP_LINES+="elasticsearch.ssl.certificate elasticsearch.ssl.key elasticsearch.ssl.certificateAuthorities "
        SKIP_LINES+="elasticsearch.ssl.ca elasticsearch.ssl.keyPassphrase elasticsearch.ssl.verify "
        SKIP_LINES+="xpack.security.authProviders server.xsrf.whitelist "
        SKIP_LINES+="xpack.security.public.protocol xpack.security.public.hostname xpack.security.public.port "
        local SKIP_REGEX="^\s*("$(echo $SKIP_LINES | tr " " "|" | sed 's/\./\\\./g')")"
        IFS=$'\n'
        for LINE in $(echo -e "$YAML_CONFIGURATION"); do
          if [[ -n "$LINE" ]]; then
              if [[ $LINE =~ $SKIP_REGEX ]]; then
                  log "[configuration_and_plugins] Skipping line '$LINE'"
              else
                  log "[configuration_and_plugins] Adding line '$LINE' to $KIBANA_CONF"
                  echo "$LINE" >> $KIBANA_CONF
              fi
          fi
        done
        unset IFS
        log "[configuration_and_plugins] included additional yaml configuration"
        log "[configuration_and_plugins] run yaml lint on configuration"
        install_yamllint
        LINT=$(yamllint -d "{extends: relaxed, rules: {key-duplicates: {level: error}}}" $KIBANA_CONF; exit ${PIPESTATUS[0]})
        EXIT_CODE=$?
        log "[configuration_and_plugins] ran yaml lint (exit code $EXIT_CODE) $LINT"
        if [ $EXIT_CODE -ne 0 ]; then
            log "[configuration_and_plugins] errors in yaml configuration. exiting"
            exit 11
        fi
    fi
}

install_yamllint()
{
    log "[install_yamllint] installing yamllint"
    (apt-get -yq install yamllint || (sleep 15; apt-get -yq install yamllint))
    log "[install_yamllint] installed yamllint"
}

install_start_service()
{
    log "[install_start_service] Configuring service for kibana to run at start"
    update-rc.d kibana defaults 95 10
    log "[install_start_service] Starting kibana!"
    service kibana start
}

#########################
# Installation sequence
#########################

log "[apt-get] updating apt-get"
(apt-get -y update || (sleep 15; apt-get -y update)) > /dev/null
log "[apt-get] updated apt-get"

log "[install_sequence] Starting installation"
download_kibana
configuration_and_plugins
install_start_service
log "[install_sequence] Finished installation"

ELAPSED_TIME=$(($SECONDS - $START_TIME))
PRETTY=$(printf '%dh:%dm:%ds\n' $(($ELAPSED_TIME/3600)) $(($ELAPSED_TIME%3600/60)) $(($ELAPSED_TIME%60)))
log "End execution of Kibana script extension in ${PRETTY}"
