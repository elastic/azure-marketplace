#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

help()
{
    echo "This script installs NGINX reverse proxy"
    echo ""
    echo "Options:"
    echo "    -u      Basic Authentication user name"
    echo "    -p      Basic Authentication passowrd"
    echo "    -n      TCP port number for NGINX to listen"
    echo "    -c      BASE64-encoded PFX file for TLS connection"
    echo "    -k      Optional password for PFX file needed to extract the RSA key"
    echo "    -h      view this help content"
}

# Custom logging with time so we can easily relate running times, also log to separate file so order is guaranteed.
# The Script extension output the stdout/err buffer in intervals with duplicates.
log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/nginx-install.log
}

#########################
# Parameter handling
#########################

AUTH_USERNAME=""
AUTH_PASSWORD=""
NGINX_PORT=0
PFX_B64=""
PFX_PWD=""

#Loop through options passed
while getopts :u:p:n:c:k:h optname; do
  log "Option $optname set"
  case $optname in
    u) # basic auth user name
      AUTH_USERNAME="${OPTARG}"
      ;;
    p) # basic auth password
      AUTH_PASSWORD="${OPTARG}"
      ;;
    n) # TCP port number
      NGINX_PORT=${OPTARG}
      ;;
    c) # base64 encoded PFX file
      PFX_B64="${OPTARG}"
      ;;
    k) # password for the PFX file
      PFX_PWD="${OPTARG}"
      ;;
    h) #show help
      help
      exit 2
      ;;
    \?) #unrecognized option - show help
      echo -e \\n"ERROR: unknown option -${BOLD}$OPTARG${NORM}" >&2
      help
      exit 2
      ;;
  esac
done


if [ "${AUTH_USERNAME}" == "" -o "${AUTH_PASSWORD}" == "" -o ${NGINX_PORT} -eq 0 -o "${PFX_B64}" == "" ];
then
    echo "ERROR: missing input arguments" >&2
    help
    exit 3
fi

#########################
# Constants
#########################

NGINX_DIR=/etc/nginx
NGINX_LOG_DIR=/var/log/nginx
BASIC_AUTH_PATH=$NGINX_DIR/.htpasswd
CERT_DIR=$NGINX_DIR/ssl
CRT_PATH=$CERT_DIR/host.crt
KEY_PATH=$CERT_DIR/host.key
DEFAULT_SITE_PATH=$NGINX_DIR/sites-available/default
ES_LOCAL_ADDRESS=http://localhost:9200

#########################
# Installation functions
#########################

install_nginx()
{
  apt-get -yq install nginx
}

restart_nginx()
{
  systemctl restart nginx
}

# These utils contain the 'htpasswd'
install_apache_utils()
{
  apt-get -yq install apache2-utils
}

create_basic_auth_file()
{
  htpasswd -cb $BASIC_AUTH_PATH "$AUTH_USERNAME" "$AUTH_PASSWORD"
}

install_certificate()
{
  mkdir $CERT_DIR
  echo ${PFX_B64} | base64 -d >> $CERT_DIR/host.pfx
  openssl pkcs12 -in $CERT_DIR/host.pfx -clcerts -nokeys -out $CRT_PATH -passin pass:"$PFX_PWD"
  openssl pkcs12 -in $CERT_DIR/host.pfx -nodes -passin pass:"$PFX_PWD" | openssl rsa -out $KEY_PATH
  rm $CERT_DIR/host.pfx
}

write_server_config()
{
  rm $NGINX_DIR/nginx.conf

  echo "user www-data;
worker_processes auto;
pid /run/nginx.pid;

events {
	worker_connections 768;
}

http {
	sendfile on;
	tcp_nopush on;
	tcp_nodelay on;
	keepalive_timeout 65;
	types_hash_max_size 2048;

	default_type application/octet-stream;

	gzip on;
	gzip_disable "msie6";

	ssl_protocols TLSv1.2; # omit SSLv3 because of POODLE (CVE-2014-3566)
	ssl_prefer_server_ciphers on;
	ssl_certificate $CRT_PATH;
	ssl_certificate_key $KEY_PATH;

	access_log $NGINX_LOG_DIR/access.log;
	error_log $NGINX_LOG_DIR/error.log;

	include $NGINX_DIR/conf.d/*.conf;
	include $NGINX_DIR/sites-enabled/*;
	include $NGINX_DIR/mime.types;
}" >> $NGINX_DIR/nginx.conf

}

write_site_config()
{
  rm $DEFAULT_SITE_PATH

  echo "server {
	listen $NGINX_PORT ssl default_server;
	listen [::]:$NGINX_PORT ssl default_server;
	location / {
		proxy_pass $ES_LOCAL_ADDRESS;
		auth_basic "ElasticSearch!";
		auth_basic_user_file $BASIC_AUTH_PATH;
	}
}" >> $DEFAULT_SITE_PATH

}

#########################
# Execution
#########################

log "Install NGINX"
install_nginx

log "Install Apache2 utils"
install_apache_utils

log "Create user file for basic authentication"
create_basic_auth_file

log "Install certificate for secure connection"
install_certificate

log "Write NGINX server configuration"
write_server_config

log "Write NGINX site configuration"
write_site_config

log "Re-start NGINX"
restart_nginx
