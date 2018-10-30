#!/bin/bash

# License: https://github.com/elastic/azure-marketplace/blob/master/LICENSE.txt
#
# Russ Cam (Elastic)
#

export DEBIAN_FRONTEND=noninteractive

#########################
# HELP
#########################

help()
{
    echo "This script installs Logstash on a dedicated Ubuntu VM"
    echo ""
    echo "Options:"
    echo "    -v      Logstash version e.g. 6.4.0"
    echo "    -m      heap size in megabytes to allocate to JVM"
    echo "    -u      Elasticsearch URL to configure monitoring and make available to configuration through ELASTICSEARCH_URL variable"

    echo "    -S      logstash_system user password"
    echo "    -l      whether to install X-Pack plugins (or enable trial license in 6.3.0+)"

    echo "    -H      base64 encoded PKCS#12 archive (.p12/.pfx) containing the key and certificate used to secure the Elasticsearch HTTP layer"
    echo "    -G      password for PKCS#12 archive (.p12/.pfx) containing the key and certificate used to secure the Elasticsearch HTTP layer"
    echo "    -V      base64 encoded PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure the Elasticsearch HTTP layer"
    echo "    -J      password for PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure the Elasticsearch HTTP layer"

    echo "    -L      <plugin;plugin> install additional plugins"
    echo "    -c      base 64 encoded Logstash conf file"
    echo "    -K      Logstash keystore password for Logstash 6.2.0+"
    echo "    -Y      <yaml\nyaml> additional yaml configuration"

    echo "    -h      view this help content"
}

# Custom logging with time so we can easily relate running times, also log to separate file so order is guaranteed.
log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/arm-install.log
}

log "Begin execution of Logstash script extension on ${HOSTNAME}"
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

#########################
# Parameter handling
#########################

#Script Parameters
LOGSTASH_VERSION="6.4.0"
LOGSTASH_HEAP=0
ELASTICSEARCH_URL="http://10.0.0.4:9200"
INSTALL_XPACK=0
INSTALL_ADDITIONAL_PLUGINS=""
USER_LOGSTASH_PWD="changeme"
LOGSTASH_KEYSTORE_PWD="changeme"
LOGSTASH_CONF_FILE=""
YAML_CONFIGURATION=""
HTTP_CERT=""
HTTP_CERT_PASSWORD=""
HTTP_CACERT=""
HTTP_CACERT_PASSWORD=""

#Loop through options passed
while getopts :v:m:u:S:H:G:V:J:L:c:K:Y:lh optname; do
  log "Option $optname set"
  case $optname in
    v) #logstash version number
      LOGSTASH_VERSION="${OPTARG}"
      ;;
    m) #heap_size
      LOGSTASH_HEAP=${OPTARG}
      ;;
    u) #elasticsearch url
      ELASTICSEARCH_URL="${OPTARG}"
      ;;
    S) #security logstash pwd
      USER_LOGSTASH_PWD="${OPTARG}"
      ;;
    l) #install X-Pack
      INSTALL_XPACK=1
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
    L) #install additional plugins
      INSTALL_ADDITIONAL_PLUGINS="${OPTARG}"
      ;;
    c) #logstash configuration file
      LOGSTASH_CONF_FILE="${OPTARG}"
      ;;
    K) #logstash keystore password
      LOGSTASH_KEYSTORE_PWD="${OPTARG}"
      ;;
    Y) #logstash additional yml configuration
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
# Installation steps as functions
#########################

# Install Oracle Java
install_java()
{
  bash java-install.sh
}

# Install Logstash
install_logstash()
{
  local PACKAGE="logstash-$LOGSTASH_VERSION.deb"
  local ALGORITHM="512"
  if dpkg --compare-versions "$LOGSTASH_VERSION" "lt" "5.6.2"; then
    ALGORITHM="1"
  fi

  local SHASUM="$PACKAGE.sha$ALGORITHM"
  local DOWNLOAD_URL="https://artifacts.elastic.co/downloads/logstash/$PACKAGE?ultron=msft&gambit=azure"
  local SHASUM_URL="https://artifacts.elastic.co/downloads/logstash/$SHASUM?ultron=msft&gambit=azure"

  log "[install_logstash] installing Logstash $LOGSTASH_VERSION"
  wget --retry-connrefused --waitretry=1 -q "$SHASUM_URL" -O $SHASUM
  local EXIT_CODE=$?
  if [ $EXIT_CODE -ne 0 ]; then
      log "[install_logstash] error downloading Logstash $LOGSTASH_VERSION sha$ALGORITHM checksum"
      exit $EXIT_CODE
  fi
  log "[install_logstash] download location - $DOWNLOAD_URL"
  wget --retry-connrefused --waitretry=1 -q "$DOWNLOAD_URL" -O $PACKAGE
  EXIT_CODE=$?
  if [ $EXIT_CODE -ne 0 ]; then
      log "[install_logstash] error downloading Logstash $LOGSTASH_VERSION"
      exit $EXIT_CODE
  fi
  log "[install_logstash] downloaded Logstash $LOGSTASH_VERSION"

  # earlier sha files do not contain the package name. add it
  grep -q "$PACKAGE" $SHASUM || sed -i "s/.*/&  $PACKAGE/" $SHASUM

  shasum -a $ALGORITHM -c $SHASUM
  EXIT_CODE=$?
  if [ $EXIT_CODE -ne 0 ]; then
      log "[install_logstash] error validating checksum for Logstash $LOGSTASH_VERSION"
      exit $EXIT_CODE
  fi

  dpkg -i $PACKAGE
  log "[install_logstash] installed Logstash $LOGSTASH_VERSION"
}

## Security
##----------------------------------

add_keystore_or_env_var()
{
  local KEY=$1
  local VALUE="$2"
  local SYS_CONFIG=/etc/sysconfig

  if [[ ! -f $SYS_CONFIG/logstash ]]; then
    [ -d $SYS_CONFIG ] || mkdir -p $SYS_CONFIG
    touch $SYS_CONFIG/logstash
    chmod 600 $SYS_CONFIG/logstash
  fi

  if dpkg --compare-versions "$LOGSTASH_VERSION" "ge" "6.2.0"; then
    # create keystore if it doesn't exist
    if [[ ! -f /etc/logstash/logstash.keystore ]]; then
      set +o history
      export LOGSTASH_KEYSTORE_PASS="$LOGSTASH_KEYSTORE_PWD"
      echo "LOGSTASH_KEYSTORE_PASS=\"$LOGSTASH_KEYSTORE_PWD\"" >> $SYS_CONFIG/logstash
      set -o history

      log "[add_keystore_or_env_var] creating logstash keystore"
      /usr/share/logstash/bin/logstash-keystore create --path.settings /etc/logstash
      log "[add_keystore_or_env_var] created logstash keystore"
    fi

    log "[add_keystore_or_env_var] adding $KEY to logstash keystore"
    echo "$VALUE" | /usr/share/logstash/bin/logstash-keystore add $KEY --path.settings /etc/logstash
    log "[add_keystore_or_env_var] added $KEY logstash keystore"
  else
    log "[add_keystore_or_env_var] adding environment variable for $KEY"
    set +o history
    export $KEY="$VALUE"
    echo "$KEY=\"$VALUE\"" >> $SYS_CONFIG/logstash
    set -o history
    log "[add_keystore_or_env_var] added environment variable for $KEY"
  fi
}

configure_logstash_yaml()
{
    local LOGSTASH_CONF=/etc/logstash/logstash.yml
    local SSL_PATH=/etc/logstash/ssl
    local LOG_PATH=/var/log/logstash
    local XPACK_BUNDLED=$(dpkg --compare-versions "$LOGSTASH_VERSION" "ge" "6.3.0"; echo $?)

    # backup the current config
    if [[ -f $LOGSTASH_CONF ]]; then
      log "[configure_logstash_yaml] moving $LOGSTASH_CONF to $LOGSTASH_CONF.bak"
      mv $LOGSTASH_CONF $LOGSTASH_CONF.bak
    fi

    log "[configure_logstash_yaml] configuring logstash.yml"

    echo "node.name: \"${HOSTNAME}\"" >> $LOGSTASH_CONF

    # logstash conf file
    if [[ -n "$LOGSTASH_CONF_FILE" ]]; then
      local CONF_FILE=/etc/logstash/conf.d/logstash.conf

      if [[ -f $CONF_FILE ]]; then
        log "[configure_logstash_yaml] moving $CONF_FILE to $CONF_FILE.bak"
        mv $CONF_FILE $CONF_FILE.bak
      fi

      log "[configure_logstash_yaml] writing logstash conf to $CONF_FILE"
      echo ${LOGSTASH_CONF_FILE} | base64 -d | tee $CONF_FILE
    fi

    # allow values to be referenced in *.conf files
    add_keystore_or_env_var 'LOGSTASH_SYSTEM_PASSWORD' "$USER_LOGSTASH_PWD"
    add_keystore_or_env_var 'ELASTICSEARCH_URL' "$ELASTICSEARCH_URL"

    # put data on the OS disk in a writable location
    # TODO: Consider allowing attached managed disk in future
    echo "path.data: /var/lib/logstash" >> $LOGSTASH_CONF

    # explicitly set the default conf file dir
    if dpkg --compare-versions "$LOGSTASH_VERSION" "ge" "6.2.0"; then
      echo "path.config: /etc/logstash/conf.d/*.conf" >> $LOGSTASH_CONF
    else
      echo "path.config: /etc/logstash/conf.d" >> $LOGSTASH_CONF
    fi

    # TODO: make persistent queues configurable?
    # echo "queue.type: persisted" >> $LOGSTASH_CONF

    # put log files on the OS disk in a writable location
    mkdir -p $LOG_PATH
    chown -R logstash: $LOG_PATH
    echo "path.logs: $LOG_PATH" >> $LOGSTASH_CONF
    echo "log.level: error" >> $LOGSTASH_CONF

    # install x-pack
    if [[ $INSTALL_XPACK -ne 0 ]]; then
      if dpkg --compare-versions "$LOGSTASH_VERSION" "lt" "6.3.0"; then
        log "[configure_logstash_yaml] installing x-pack plugin"
        /usr/share/logstash/bin/logstash-plugin install x-pack
        log "[configure_logstash_yaml] installed x-pack plugin"
      fi

      echo 'xpack.monitoring.elasticsearch.url: "${ELASTICSEARCH_URL}"' >> $LOGSTASH_CONF

      # assumes Security is enabled, so configure monitoring credentials
      echo "xpack.monitoring.elasticsearch.username: logstash_system" >> $LOGSTASH_CONF
      echo 'xpack.monitoring.elasticsearch.password: "${LOGSTASH_SYSTEM_PASSWORD}"' >> $LOGSTASH_CONF
    elif [[ $XPACK_BUNDLED -eq 0 ]]; then
      # configure monitoring for basic
      echo 'xpack.monitoring.elasticsearch.url: "${ELASTICSEARCH_URL}"' >> $LOGSTASH_CONF
    fi

    local MONITORING='true'

    # Make the HTTP CA cert for communication with Elasticsearch available to
    # Logstash conf files through ${ELASTICSEARCH_CACERT}
    if [[ -n "${HTTP_CERT}" || -n "${HTTP_CACERT}" && ${INSTALL_XPACK} -ne 0 ]]; then

      MONITORING='false'

      [ -d $SSL_PATH ] || mkdir -p $SSL_PATH

      if [[ -n "${HTTP_CERT}" ]]; then
        # convert PKCS#12 certificate to PEM format
        log "[configure_logstash_yaml] Save PKCS#12 archive for Elasticsearch HTTP to file"
        echo ${HTTP_CERT} | base64 -d | tee $SSL_PATH/elasticsearch-http.p12
        log "[configure_logstash_yaml] Extract CA cert from PKCS#12 archive for Elasticsearch HTTP"
        echo "$HTTP_CERT_PASSWORD" | openssl pkcs12 -in $SSL_PATH/elasticsearch-http.p12 -out $SSL_PATH/elasticsearch-http-ca.crt -cacerts -nokeys -chain -passin stdin

        log "[configure_logstash_yaml] Configuring ELASTICSEARCH_CACERT for Elasticsearch TLS"
        if [[ $(stat -c %s $SSL_PATH/elasticsearch-http-ca.crt 2>/dev/null) -eq 0 ]]; then
            log "[configure_logstash_yaml] No CA cert extracted from HTTP cert. Cannot make ELASTICSEARCH_CACERT available to conf files"
        else
            log "[configure_logstash_yaml] CA cert extracted from HTTP PKCS#12 archive. Make ELASTICSEARCH_CACERT available to conf files"
            add_keystore_or_env_var "ELASTICSEARCH_CACERT" "$SSL_PATH/elasticsearch-http-ca.crt"

            # logstash performs hostname verification for monitoring
            # which will not work for a HTTP cert provided by the user, where logstash communicates through internal loadbalancer.
            # 6.4.0 exposes verification_mode, so set this to none and document.
            if dpkg --compare-versions "$LOGSTASH_VERSION" "ge" "6.4.0"; then
              echo 'xpack.monitoring.elasticsearch.ssl.ca: "${ELASTICSEARCH_CACERT}"' >> $LOGSTASH_CONF
              echo 'xpack.monitoring.elasticsearch.ssl.verification_mode: none' >> $LOGSTASH_CONF
              MONITORING='true'
            fi
        fi

      else
        # convert PKCS#12 CA certificate to PEM format
        local HTTP_CACERT_FILENAME=elasticsearch-http-ca.p12
        log "[configure_logstash_yaml] Save PKCS#12 archive for Elasticsearch HTTP CA to file"
        echo ${HTTP_CACERT} | base64 -d | tee $SSL_PATH/$HTTP_CACERT_FILENAME
        log "[configure_logstash_yaml] Convert PKCS#12 archive for Elasticsearch HTTP CA to PEM format"
        echo "$HTTP_CACERT_PASSWORD" | openssl pkcs12 -in $SSL_PATH/$HTTP_CACERT_FILENAME -out $SSL_PATH/elasticsearch-http-ca.crt -clcerts -nokeys -chain -passin stdin

        log "[configure_logstash_yaml] Configuring ELASTICSEARCH_CACERT for Elasticsearch TLS"
        if [[ $(stat -c %s $SSL_PATH/elasticsearch-http-ca.crt 2>/dev/null) -eq 0 ]]; then
            log "[configure_logstash_yaml] No CA cert extracted from HTTP CA PKCS#12 archive. Cannot make ELASTICSEARCH_CACERT available to conf files"
        else
            log "[configure_logstash_yaml] CA cert extracted from HTTP CA PKCS#12 archive. Make ELASTICSEARCH_CACERT available to conf files"
            add_keystore_or_env_var "ELASTICSEARCH_CACERT" "$SSL_PATH/elasticsearch-http-ca.crt"

            # HTTP certs created from a HTTP CA provided by the user will include the
            # IP address of the internal loadbalancer, so hostname verification will pass.
            echo 'xpack.monitoring.elasticsearch.ssl.ca: "${ELASTICSEARCH_CACERT}"' >> $LOGSTASH_CONF
            MONITORING='true'
        fi
      fi

      chown -R logstash: $SSL_PATH
      log "[configure_logstash_yaml] Configured ELASTICSEARCH_CACERT for Elasticsearch TLS"
      log "[configure_logstash_yaml] X-Pack monitoring for Logstash set to $MONITORING"
    fi

    if [[ $XPACK_BUNDLED -eq 0 || $INSTALL_XPACK -ne 0 ]]; then
      echo "xpack.monitoring.enabled: $MONITORING" >> $LOGSTASH_CONF
    fi

    # TODO: Configure Centralized Pipeline Management?
    # https://www.elastic.co/guide/en/logstash/current/configuring-centralized-pipelines.html

    # Additional yaml configuration
    if [[ -n "$YAML_CONFIGURATION" ]]; then
        log "[configure_logstash] include additional yaml configuration"

        local SKIP_LINES="node.name path.data path.logs "
        SKIP_LINES+="xpack.monitoring.elasticsearch.username xpack.monitoring.elasticsearch.password "
        SKIP_LINES+="xpack.monitoring.enabled xpack.monitoring.elasticsearch.ssl.ca xpack.monitoring.elasticsearch.ssl.verification_mode "
        local SKIP_REGEX="^\s*("$(echo $SKIP_LINES | tr " " "|" | sed 's/\./\\\./g')")"
        IFS=$'\n'
        for LINE in $(echo -e "$YAML_CONFIGURATION"); do
          if [[ -n "$LINE" ]]; then
              if [[ $LINE =~ $SKIP_REGEX ]]; then
                  log "[configure_logstash] Skipping line '$LINE'"
              else
                  log "[configure_logstash] Adding line '$LINE' to $LOGSTASH_CONF"
                  echo "$LINE" >> $LOGSTASH_CONF
              fi
          fi
        done
        unset IFS
        log "[configure_logstash] included additional yaml configuration"
        log "[configure_logstash] run yaml lint on configuration"
        install_yamllint
        LINT=$(yamllint -d "{extends: relaxed, rules: {key-duplicates: {level: error}}}" $LOGSTASH_CONF; exit ${PIPESTATUS[0]})
        EXIT_CODE=$?
        log "[configure_logstash] ran yaml lint (exit code $EXIT_CODE) $LINT"
        if [ $EXIT_CODE -ne 0 ]; then
            log "[configure_logstash] errors in yaml configuration. exiting"
            exit 11
        fi
    fi
}

configure_logstash()
{
    log "[configure_logstash] configuring Logstash default configuration"

    if [[ "$LOGSTASH_HEAP" -eq "0" ]]; then
      log "[configure_logstash] configuring heap size from available memory"
      LOGSTASH_HEAP=`free -m | grep Mem | awk '{if ($2/2 > 8092) print 8092;else print int($2/2+0.5);}'`
    fi

    log "[configure_logstash] configure logstash heap size - $LOGSTASH_HEAP megabytes"
    sed -i -e "s/^\-Xmx.*/-Xmx${LOGSTASH_HEAP}m/" /etc/logstash/jvm.options
    sed -i -e "s/^\-Xms.*/-Xms${LOGSTASH_HEAP}m/" /etc/logstash/jvm.options
}

install_additional_plugins()
{
    SKIP_PLUGINS="x-pack"
    log "[install_additional_plugins] installing additional plugins"
    for PLUGIN in $(echo $INSTALL_ADDITIONAL_PLUGINS | tr ";" "\n")
    do
        if [[ $SKIP_PLUGINS =~ $PLUGIN ]]; then
            log "[install_additional_plugins] skipping plugin $PLUGIN"
        else
            log "[install_additional_plugins] installing plugin $PLUGIN"
            /usr/share/logstash/bin/logstash-plugin install $PLUGIN
            log "[install_additional_plugins] installed plugin $PLUGIN"
        fi
    done
    log "[install_additional_plugins] installed additional plugins"
}

start_systemd()
{
    log "[start_systemd] starting logstash"
    systemctl start logstash.service
    log "[start_systemd] started logstash!"
}

install_apt_package()
{
  local PACKAGE=$1
  if [ $(dpkg-query -W -f='${Status}' $PACKAGE 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
    log "[install_$PACKAGE] installing $PACKAGE"
    (apt-get -yq install $PACKAGE || (sleep 15; apt-get -yq install $PACKAGE))
    log "[install_$PACKAGE] installed $PACKAGE"
  fi
}

install_yamllint()
{
  install_apt_package yamllint
}

#########################
# Installation sequence
#########################

if systemctl -q is-active logstash.service; then
  log "logstash already installed and running. reconfigure and restart if logstash.yml has changed"

  configure_logstash_yaml

  # restart logstash if config has changed
  cmp --silent /etc/logstash/logstash.yml /etc/logstash/logstash.yml.bak \
    || systemctl reload-or-restart logstash.service

  exit 0
fi

log "installing logstash $LOGSTASH_VERSION"
log "installing X-Pack plugins is set to: $INSTALL_XPACK"
log "[apt-get] updating apt-get"
(apt-get -y update || (sleep 15; apt-get -y update)) > /dev/null
log "[apt-get] updated apt-get"

install_java

install_logstash

configure_logstash_yaml

configure_logstash

# install additional plugins
if [[ -n "$INSTALL_ADDITIONAL_PLUGINS" ]]; then
  install_additional_plugins
fi

start_systemd

ELAPSED_TIME=$(($SECONDS - $START_TIME))
PRETTY=$(printf '%dh:%dm:%ds\n' $(($ELAPSED_TIME/3600)) $(($ELAPSED_TIME%3600/60)) $(($ELAPSED_TIME%60)))
log "End execution of Logstash script extension in ${PRETTY}"
