#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

#########################
# Help
#########################

help()
{
    echo "This script installs various tools on a machine"
    echo ""
    echo "Options:"
    echo "   -h         this help message"
}

log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] \["install_tools"\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] \["install_tools"\] "$1" >> /var/log/arm-install.log
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

#########################
# Installation functions
#########################

# nmon is a simple tool that allows to view stats on CPU, memory, network, and disk usage.
# http://nmon.sourceforge.net/pmwiki.php
install_nmon()
{
  apt-get -yq install nmon
}

install_tools()
{
  log "Installing nmon.."
  install_nmon
}

#########################
# Execution
#########################

install_tools
