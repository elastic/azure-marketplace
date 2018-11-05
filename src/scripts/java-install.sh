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
    echo "This script installs Java on Ubuntu using the oracle-java8-installer apt package"
    echo ""
    echo "Options:"
    echo "   -h         this help message"
}

log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] \["install_java"\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] \["install_java"\] "$1" >> /var/log/arm-install.log
}

#########################
# Parameter handling
#########################

while getopts h optname; do
    log "Option $optname set with value ${OPTARG}"
  case ${optname} in
    h)  #show help
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

# Update the oracle-java8-installer to patch download of Java 8u181 to 8u191.
# 8u181 download is now archived
# TODO: Remove this once oracle-java8-installer package is updated
install_java_package()
{
  local ORACLE_DOWNLOAD_URL=http://download.oracle.com/otn-pub/java/jdk

  local PACKAGE_VERSION=8u181
  local PACKAGE_URL=8u181-b13/96a7b8442fe848ef90c96a2fad6ed6d1/
  local PACKAGE_SHASUM=1845567095bfbfebd42ed0d09397939796d05456290fb20a83c476ba09f991d3
  local PACKAGE_DIR=jdk1.8.0_181

  local PATCH_VERSION=8u191
  local PATCH_URL=8u191-b12/2787e4a523244c269598db4e85c51e0c/
  local PATCH_SHASUM=53c29507e2405a7ffdbba627e6d64856089b094867479edc5ede4105c1da0d65
  local PATCH_DIR=jdk1.8.0_191

  apt-get -yq $@ install oracle-java8-installer || true \
  && pushd /var/lib/dpkg/info \
  && log "[install_java_package] update oracle-java8-installer to $PATCH_VERSION" \
  && sed -i "s|JAVA_VERSION=$PACKAGE_VERSION|JAVA_VERSION=$PATCH_VERSION|" oracle-java8-installer.* \
  && sed -i "s|PARTNER_URL=$ORACLE_DOWNLOAD_URL/$PACKAGE_URL|PARTNER_URL=$ORACLE_DOWNLOAD_URL/$PATCH_URL|" oracle-java8-installer.* \
  && sed -i "s|SHA256SUM_TGZ=\"$PACKAGE_SHASUM\"|SHA256SUM_TGZ=\"$PATCH_SHASUM\"|" oracle-java8-installer.* \
  && sed -i "s|J_DIR=$PACKAGE_DIR|J_DIR=$PATCH_DIR|" oracle-java8-installer.* \
  && popd \
  && log "[install_java_package] updated oracle-java8-installer" \
  && apt-get -yq $@ install oracle-java8-installer
}

install_java()
{
    log "adding apt repository for java"
    (add-apt-repository -y ppa:webupd8team/java || (sleep 15; add-apt-repository -y ppa:webupd8team/java))
    log "updating apt-get"
    (apt-get -y update || (sleep 15; apt-get -y update)) > /dev/null
    log "updated apt-get"
    echo debconf shared/accepted-oracle-license-v1-1 select true | debconf-set-selections
    echo debconf shared/accepted-oracle-license-v1-1 seen true | debconf-set-selections
    log "installing java"
    (install_java_package || (sleep 15; install_java_package))
    command -v java >/dev/null 2>&1 || { sleep 15; rm /var/cache/oracle-jdk8-installer/jdk-*; apt-get install -f; }

    #if the previous did not install correctly we go nuclear, otherwise this loop will early exit
    for i in $(seq 30); do
      if $(command -v java >/dev/null 2>&1); then
        log "installed java!"
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
        log "seeing if java is installed after nuclear retry ${i}/30"
      fi
    done
    command -v java >/dev/null 2>&1 || { log "java did not get installed properly even after a retry and a forced installation" >&2; exit 50; }
}

install_java
