#!/bin/bash

# The MIT License (MIT)
#
# Copyright (c) 2016 Elastic, Inc.
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

#########################
# HELP
#########################

help()
{
    echo "This script sends user information to Elastic marketing team, allowing for follow-up conversations"
    echo "Parameters:"
    echo "-U api url"
    echo "-I marketing id"
    echo "-c company name"
    echo "-e email address"
    echo "-f first name"
    echo "-l last name"
    echo "-t job title"
    echo "-o country"
    echo "-s cluster setup"
    echo "-h view this help content"
}

# log() does an echo prefixed with time
log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/arm-install.log
}

log "Begin execution of User Information script extension"

#########################
# Paramater handling
#########################

API_URL=""
MARKETING_ID=""
COMPANY_NAME=""
EMAIL=""
FIRST_NAME=""
LAST_NAME=""
JOB_TITLE=""
COUNTRY=""
CLUSTER_SETUP=""

#Loop through options passed
while getopts :U:I:c:e:f:l:t:s:o:h optname; do
  log "Option $optname set"
  case $optname in
    U) #set API url
      API_URL=${OPTARG}
      ;;
    I) #set marketing id
      MARKETING_ID=${OPTARG}
      ;;
    c) #set company name
      COMPANY_NAME=${OPTARG}
      ;;
    e) #set email
      EMAIL=${OPTARG}
      ;;
    f) #set first name
      FIRST_NAME=${OPTARG}
      ;;
    l) #set last name
      LAST_NAME=${OPTARG}
      ;;
    t) #set job title
      JOB_TITLE=${OPTARG}
      ;;
    o) #set country
      COUNTRY=${OPTARG}
      ;;
    s) #set cluster setup
      CLUSTER_SETUP=${OPTARG}
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
# Preconditions
#########################

# Need the endpoint and marketing id to be able to send
if [[ -z $API_URL || -z $MARKETING_ID ]]; then
  log "No api url or marketing id defined."
  exit 1
fi

# Don't try to send a lead if we don't have an email address.
if [[ -z $EMAIL ]]; then
  log "No email address supplied. No lead to send."
  exit 0
fi

#########################
# Installation steps as functions
#########################

post_user_information()
{
    STATUS_CODE=$(curl -X POST "$API_URL" --data-urlencode "Form_Source=Azure Marketplace" --data-urlencode "formid=4026" --data-urlencode "munchkinId=$MARKETING_ID" --data-urlencode "formVid=4026" --data-urlencode "FirstName=$FIRST_NAME" --data-urlencode "LastName=$LAST_NAME" --data-urlencode "Email=$EMAIL" --data-urlencode "Company=$COMPANY_NAME" --data-urlencode "Job_Function__c=$JOB_TITLE" --data-urlencode "Country=$COUNTRY" --data-urlencode "Form_Message=$CLUSTER_SETUP" --silent --write-out %{http_code} --output /dev/null)

    if test $STATUS_CODE -ne 200; then
        log "failed to send lead details. status code: $STATUS_CODE"
    else
        log "lead successfully sent"
    fi
}

post_user_information

log "End execution of User Information script extension"
exit 0
