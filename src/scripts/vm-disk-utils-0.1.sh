#!/bin/bash

# The MIT License (MIT)
#
# Copyright (c) 2015 Microsoft Azure
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Script Name: vm-disk-utils.sh
# Author: Trent Swanson - Full Scale 180 Inc github:(trentmswanson)
# Version: 0.1
# Last Modified By:       Trent Swanson
# Description:
#  This script automates the partitioning and formatting of data disks
#  Data disks can be partitioned and formatted as seperate disks or in a RAID0 configuration
#  The script will scan for unpartitioned and unformatted data disks and partition, format, and add fstab entries
# Parameters :
#  1 - b: The base directory for mount points (default: /datadisks)
#  2 - s  Create a striped RAID0 Array (No redundancy)
#  3 - h  Help
# Note :
# This script has only been tested on Ubuntu 12.04 LTS and must be root

help()
{
    echo "Usage: $(basename $0) [-b data_base] [-h] [-s] [-o mount_options]"
    echo ""
    echo "Options:"
    echo "   -b         base directory for mount points (default: /datadisks)"
    echo "   -s         create a striped RAID array (no redundancy)"
    echo "   -o         mount options for data disk"
    echo "   -h         this help message"
}

log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] \["format_and_partition_disks"\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] \["format_and_partition_disks"\] "$1" >> /var/log/arm-install.log
}

export DEBIAN_FRONTEND=noninteractive

if [ "${UID}" -ne 0 ];
then
    log "Script executed without root permissions"
    echo "You must be root to run this program." >&2
    exit 3
fi

# Base path for data disk mount points
DATA_BASE="/datadisks"
# Mount options for data disk
MOUNT_OPTIONS="noatime,nodiratime,nodev,noexec,nosuid,nofail"

while getopts b:sho: optname; do
    log "Option $optname set with value ${OPTARG}"
  case ${optname} in
    b)  #Set base path for data disks
      DATA_BASE=${OPTARG}
      ;;
    s)  #Partition and format data disks as raid set
      RAID_CONFIGURATION=1
      ;;
    o) #mount option
      MOUNT_OPTIONS=${OPTARG}
      ;;
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

get_next_md_device() {
    shopt -s extglob
    LAST_DEVICE=$(ls -1 /dev/md+([0-9]) 2>/dev/null|sort -n|tail -n1)
    if [ -z "${LAST_DEVICE}" ]; then
        NEXT=/dev/md0
    else
        NUMBER=$((${LAST_DEVICE/\/dev\/md/}))
        NEXT=/dev/md${NUMBER}
    fi
    echo ${NEXT}
}

is_partitioned() {
    OUTPUT=$(partx -s ${1} 2>&1)
    egrep "partition table does not contains usable partitions|failed to read partition table" <<< "${OUTPUT}" >/dev/null 2>&1
    if [ ${?} -eq 0 ]; then
        return 1
    else
        return 0
    fi
}

has_filesystem() {
    DEVICE=${1}
    OUTPUT=$(file -L -s ${DEVICE})
    grep filesystem <<< "${OUTPUT}" > /dev/null 2>&1
    return ${?}
}

scan_for_new_disks() {
    # Looks for unpartitioned disks
    declare -a RET
    DEVS=($(ls -1 /dev/sd*|egrep -v "[0-9]$"))
    for DEV in "${DEVS[@]}";
    do
        # The disk will be considered a candidate for partitioning
        # and formatting if it does not have a sd?1 entry or
        # if it does have an sd?1 entry and does not contain a filesystem
        is_partitioned "${DEV}"
        if [ ${?} -eq 0 ];
        then
            has_filesystem "${DEV}1"
            if [ ${?} -ne 0 ];
            then
                RET+=" ${DEV}"
            fi
        else
            RET+=" ${DEV}"
        fi
    done
    echo "${RET}"
}

get_next_mountpoint() {
    DIRS=$(ls -1d ${DATA_BASE}/disk* 2>/dev/null| sort --version-sort)
    MAX=$(echo "${DIRS}"|tail -n 1 | tr -d "[a-zA-Z/]")
    if [ -z "${MAX}" ];
    then
        echo "${DATA_BASE}/disk1"
        return
    fi
    IDX=1
    while [ "${IDX}" -lt "${MAX}" ];
    do
        NEXT_DIR="${DATA_BASE}/disk${IDX}"
        if [ ! -d "${NEXT_DIR}" ];
        then
            echo "${NEXT_DIR}"
            return
        fi
        IDX=$(( ${IDX} + 1 ))
    done
    IDX=$(( ${MAX} + 1))
    echo "${DATA_BASE}/disk${IDX}"
}

add_to_fstab() {
    UUID=${1}
    MOUNTPOINT=${2}
    log "calling fstab with UUID: ${UUID} and mount point: ${MOUNTPOINT}"
    grep "${UUID}" /etc/fstab >/dev/null 2>&1
    if [ ${?} -eq 0 ];
    then
        log "Not adding ${UUID} to fstab again (it's already there!)"
    else
        LINE="UUID=\"${UUID}\"\t${MOUNTPOINT}\text4\t${MOUNT_OPTIONS}\t1 2"
        echo -e "${LINE}" >> /etc/fstab
    fi
}

do_partition() {
# This function creates one (1) primary partition on the
# disk, using all available space
    local _disk=${1}
    local largest_dos_volume_bytes=2199023255040
    local disk_size=$(fdisk -l ${_disk} | grep -E -o ", [0-9]+ bytes," | grep -E -o "[0-9]+")

    if [[ "${disk_size}" -gt "${largest_dos_volume_bytes}" ]]; then
        log "create partition for ${_disk} with parted"
        parted -s ${_disk} -- mklabel gpt mkpart primary 0% 100%
        local EXIT_CODE=$?
        if [[ $EXIT_CODE -ne 0 ]]; then
            log "An error occurred partitioning ${_disk}"
            echo "An error occurred partitioning ${_disk}" >&2
            echo "I cannot continue" >&2
            exit $EXIT_CODE
        fi
    else
        log "create partition for ${_disk} with fdisk"
        local _type=${2}
        if [ -z "${_type}" ]; then
            # default to Linux partition type (ie, ext3/ext4/xfs)
            _type=83
        fi

        echo "n
p
1


t
${_type}
w"| fdisk "${_disk}"

        # Use the bash-specific $PIPESTATUS to ensure we get the correct exit code
        # from fdisk and not from echo
        if [ ${PIPESTATUS[1]} -ne 0 ];
        then
            log "An error occurred partitioning ${_disk}"
            echo "An error occurred partitioning ${_disk}" >&2
            echo "I cannot continue" >&2
            exit 2
        fi
    fi
}
#end do_partition

scan_partition_format()
{
    DISKS=(${@})
    log "Begin formatting data disks"
    log "Disks are ${DISKS[*]}"

    for DISK in "${DISKS[@]}";
    do
        log "Working on ${DISK}"
        is_partitioned ${DISK}
        if [ ${?} -ne 0 ];
        then
            log "${DISK} is not partitioned, partitioning"
            do_partition ${DISK}
        fi
        PARTITION=$(fdisk -l ${DISK}|grep -A 1 Device|tail -n 1|awk '{print $1}')
        has_filesystem ${PARTITION}
        if [ ${?} -ne 0 ];
        then
            log "Creating filesystem on ${PARTITION}."
            # echo "Press Ctrl-C if you don't want to destroy all data on ${PARTITION}"
            # sleep 10
            mkfs -j -t ext4 ${PARTITION}
        fi
        MOUNTPOINT=$(get_next_mountpoint)
        log "Next mount point appears to be ${MOUNTPOINT}"
        [ -d "${MOUNTPOINT}" ] || mkdir -p "${MOUNTPOINT}"
        read UUID FS_TYPE < <(blkid -u filesystem ${PARTITION}|awk -F "[= ]" '{print $3" "$5}'|tr -d "\"")
        add_to_fstab "${UUID}" "${MOUNTPOINT}"
        log "Mounting disk ${PARTITION} on ${MOUNTPOINT}"
        mount "${MOUNTPOINT}"
    done
}

create_striped_volume()
{
    DISKS=(${@})
    log "Begin creating striped volume"
    log "Disks are ${DISKS[*]}"

    declare -a PARTITIONS

    for DISK in "${DISKS[@]}";
    do
        log "Working on ${DISK}"
        is_partitioned ${DISK}
        if [ ${?} -ne 0 ];
        then
            log "${DISK} is not partitioned, partitioning"
            do_partition ${DISK} fd
        fi

        PARTITION=$(fdisk -l ${DISK}|grep -A 2 Device|tail -n 1|awk '{print $1}')
        PARTITIONS+=("${PARTITION}")
    done

    log "Using ${#PARTITIONS[@]} partitions ${PARTITIONS[*]}"
    MOUNTPOINT=$(get_next_mountpoint)
    STRIDE=128 #(512kB stripe size) / (4kB block size)
    log "Next mount point appears to be ${MOUNTPOINT}"
    [ -d "${MOUNTPOINT}" ] || mkdir -p "${MOUNTPOINT}"

    MDDEVICE="${DISKS[0]}1"
    if [ "${#DISKS[@]}" -eq 1 ];
    then
        log "only one disk (${DISKS[0]}) attached. mount it"
        mkfs.ext4 -b 4096 -E stride=${STRIDE},nodiscard "${MDDEVICE}"

        log "attempting to get UUID from ${MDDEVICE}"
        read UUID FS_TYPE < <(blkid -u filesystem ${MDDEVICE}|awk -F "[= ]" '{print $3" "$5}'|tr -d "\"")

        log "adding UUID: ${UUID} to fstab ${MDDEVICE}"
        add_to_fstab "${UUID}" "${MOUNTPOINT}"

        mount "${MOUNTPOINT}"
    else
        log "${#DISKS[@]} disks are attached. RAID0-ing them using mdadm"
        MDDEVICE=$(get_next_md_device)
        log "Next md device is ${MDDEVICE}"
        udevadm control --stop-exec-queue
        mdadm --create ${MDDEVICE} --level=0 -c 64 --raid-devices=${#PARTITIONS[@]} ${PARTITIONS[*]}
        udevadm control --start-exec-queue

        #Make a file system on the new device
        PARTITIONSNUM=${#PARTITIONS[@]}
        STRIPEWIDTH=$((${STRIDE} * ${PARTITIONSNUM}))
        mkfs.ext4 -b 4096 -E stride=${STRIDE},stripe-width=${STRIPEWIDTH},nodiscard "${MDDEVICE}"

        log "attempting to get UUID from ${MDDEVICE}"
        read UUID FS_TYPE < <(blkid -u filesystem ${MDDEVICE}|awk -F "[= ]" '{print $3" "$5}'|tr -d "\"")

        if [[ -z "$UUID" && "${#DISKS[@]}" -ne 1 ]]; then
            log "UUID is empty. checking state of ${MDDEVICE}"

            # check if disk is inactive and spare. if it is, stop and assemble
            if grep -q "$(basename ${MDDEVICE}) : inactive" /proc/mdstat; then
              log "${MDDEVICE} is inactive, stopping and assembling"
              mdadm --stop "${MDDEVICE}"
              mdadm --assemble --scan
              log "${MDDEVICE} stopped and assembled"
            fi

            log "checking state of ${MDDEVICE}"
            if ! grep -q "$(basename ${MDDEVICE}) : active raid0" /proc/mdstat; then
              log "${MDDEVICE} not active. exiting"
              exit 4
            fi

            log "${MDDEVICE} is active"
            mkfs.ext4 -b 4096 -E stride=${STRIDE},stripe-width=${STRIPEWIDTH},nodiscard "${MDDEVICE}"

            log "attempting to get UUID from ${MDDEVICE} again"
            read UUID FS_TYPE < <(blkid -u filesystem ${MDDEVICE}|awk -F "[= ]" '{print $3" "$5}'|tr -d "\"")

            if [[ -z "$UUID" ]]; then
              log "UUID is still empty. exiting"
              exit 4
            fi
        fi

        log "adding UUID: ${UUID} to fstab ${MDDEVICE}"
        add_to_fstab "${UUID}" "${MOUNTPOINT}"

        mount "${MOUNTPOINT}"

        log "add entry to  /etc/mdadm/mdadm.conf for RAID array"
        mdadm --detail --scan | tee -a /etc/mdadm/mdadm.conf
        log "update update-initramfs"
        update-initramfs -u
    fi
}

check_mdadm() {
  log "installing or updating mdadm"
  (apt-get -y update || (sleep 15; apt-get -y update)) > /dev/null
  log "apt-get updated installing mdadm now"
  (apt-get -yq install mdadm || (sleep 15; apt-get -yq install mdadm))
  dpkg -s mdadm >/dev/null 2>&1
  log "apt-get installed mdadm and can be found returns: ${?}"
}

# Create Partitions
DISKS=($(scan_for_new_disks))

if [ "${#DISKS[@]}" -eq 0 ];
then
    log "No unpartitioned disks without filesystems detected"
    exit 0
fi

if [ "$RAID_CONFIGURATION" -eq 1 ]; then
    check_mdadm
    create_striped_volume "${DISKS[@]}"
else
    scan_partition_format "${DISKS[@]}"
fi
