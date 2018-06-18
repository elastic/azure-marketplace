#!/bin/bash

# License: https://github.com/elastic/azure-marketplace/blob/master/LICENSE.txt
#
# Martijn Laarman, Greg Marzouka, Russ Cam (Elastic)
# Contributors
#

#########################
# Install Java with apt-get and brute force retries
#########################

log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/arm-install.log
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
    log "[install_java] adding apt repository for java 8"
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
        log "[install_java] installed java!"
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
        log "[install_java] seeing if java is Installed after nuclear retry ${i}/30"
      fi
    done
    command -v java >/dev/null 2>&1 || { log "Java did not get installed properly even after a retry and a forced installation" >&2; exit 50; }
}

install_java
