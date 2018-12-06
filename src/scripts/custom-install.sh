#!/bin/bash

workspace_id=$1
configfile=elasticsearch.conf
targetdir="/etc/opt/microsoft/omsagent/$workspace_id/conf/omsagent.d"
targetfile="$targetdir/$configfile"

#export DEBIAN_FRONTEND=noninteractive

log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/arm-install.log
}

log "Begin execution of Custom script on ${HOSTNAME}"
START_TIME=$SECONDS

log "[settings] pwd $(pwd)"
log "[settings] ls -l $(ls -l)"
log "[settings] workspace id = $workspace_id"
log "[settings] configfile = $configfile"
log "[settings] targetfile = $targetfile"
log "[settings] ls -l $targetdir $(ls -l $targetdir)"

log "[sed] Insert workspace id into config"
sed "s/%WORKSPACE_ID%/$workspace_id/" $configfile > $targetfile

log "[chown] omsagent:omiusers $targetfile"
chown omsagent:omiusers $targetfile

log "[omsagent] restart"
/opt/microsoft/omsagent/bin/service_control restart

ELAPSED_TIME=$(($SECONDS - $START_TIME))
PRETTY=$(printf '%dh:%dm:%ds\n' $(($ELAPSED_TIME/3600)) $(($ELAPSED_TIME%3600/60)) $(($ELAPSED_TIME%60)))

log "End execution of Custom script on ${HOSTNAME} in ${PRETTY}"
exit 0
