#!/bin/bash

set -ex

detect_os() {
  if [ -z "$ID" ]; then
     . /etc/os-release
  fi

  case "$ID" in 
    "alpine") IS_ALPINE=1
    echo "Found alpine based system"
    ;;

    "centos") IS_RHEL=1
    echo "Found RHEL based system"
    ;;

    "ubuntu") IS_DEBIAN=1
    echo "Found debian based system"
    ;;
    
    *) IS_UNKNOWN=1
    ;;
  esac

}

install_alpine_packages() {
  apk add --no-cache \
    ca-certificates \
    libressl \
    pcre \
    zlib 

  apk add --no-cache --virtual /tmp/.build-deps \
    build-base \
    linux-headers \
    libressl-dev \
    pcre-dev \
    wget \
    zlib-dev 
}

detect_os

if [ ! -z $IS_UNKNOWN ]; then
  echo "This script currently only supports systems with yum or apt or apk package manager"
  exit 1
fi

if [ ! -z $IS_RHEL ]; then
  yum install -y wget unzip gcc make openssl-devel pcre-devel zlib-devel
fi 

if [ ! -z $IS_DEBIAN ]; then 
  apt update 
  apt install -y wget unzip make libssl-dev libpcre3-dev gcc make zlib1g-dev
fi 

#if [ ! -z $IS_ALPINE ]; then 
#  install_alpine_packages
#fi 

create_nginx_user() {  
  if [ ! -z $IS_ALPINE ]; then 
    getent group nginx || addgroup nginx
    getent passwd nginx || adduser -G nginx -S -H -s /sbin/nologin nginx 
  else
    getent group nginx || groupadd nginx
    getent user nginx || useradd -g nginx --system --no-create-home nginx 
  fi
}

remove_alpine_packages() {
  apk del /tmp/.build-deps
}

download_extract()
{
    URL=$1
    FILENAME=$2
    FOLDER=$3
    EXTRACT=$4

    if [ ! -d $FOLDER ]; then
        mkdir -p $FOLDER
    fi

    if [ ! -d $EXTRACT ]; then
        mkdir -p $EXTRACT
    fi

    if [ ! -f "$FOLDER/$FILENAME" ]; then
        echo "Downloading $URL to $FOLDER/$FILENAME"
        wget --quiet  --force-directories --output-document="$FOLDER/$FILENAME" $URL
    fi

    if [ ! -z "$EXTRACT" ]; then
        echo "Extracting $FOLDER/$FILENAME to $EXTRACT"
        case $FILENAME in
          *.zip) unzip -q -o -d "$EXTRACT" "$FOLDER/$FILENAME";;
          *.tar.gz) tar xf "$FOLDER/$FILENAME" -C "$EXTRACT";;
          *) echo "Unknown file format for $FILENAME";;
        esac

        FILECOUNT=$(ls -al $EXTRACT | wc -l | tr " " "\0")
        if [ "$FILECOUNT" = "4" ]; then
           # We have a single folder and need to move content to upper folder
           FOLDER_NAME=$(ls $EXTRACT | tr " " "\0")
           mv $EXTRACT/$FOLDER_NAME/* $EXTRACT/
           rm -rf $EXTRACT/$FOLDER_NAME
        fi
    fi
}

LUA_JIT_VERSION=${LUA_JIT_VERSION:-2.0.4}
NGINX_VERSION=${NGINX_VERSION:-1.11.3}
NGINX_DEVEL_VERSION=${NGINX_DEVEL_VERSION:-v0.3.0}

# use blank value for NGINX_MODULE_TYPE if you want modules to be statically compiled
NGINX_MODULE_TYPE=${NGINX_MODULE_TYPE:-}

LUA_JIT_FILE=LuaJIT-${LUA_JIT_VERSION}.tar.gz
NGINX_FILE=nginx-$NGINX_VERSION.tar.gz
NGINX_DEVEL_FILE=nginx_devel_kit_${NGINX_DEVEL_VERSION}.tar.gz

LUA_JIT_URL=http://luajit.org/download/LuaJIT-${LUA_JIT_VERSION}.tar.gz
NGINX_URL=http://nginx.org/download/$NGINX_FILE
NGINX_DEVEL_URL=https://github.com/simpl/ngx_devel_kit/archive/${NGINX_DEVEL_VERSION}.tar.gz


LUA_CJSON_FILE=lua_cjson.zip
LUA_CJSON_URL=https://github.com/efelix/lua-cjson/archive/master.zip

LUA_MAIN_URL=https://github.com/openresty/lua-nginx-module/archive/master.zip
LUA_MAIN_FILE=lua-nginx-module.zip

LUA_KAFKA_URL=https://github.com/doujiang24/lua-resty-kafka/archive/master.zip
LUA_KAFKA_FILE=lua-resty-kafka.zip

LUA_SYSLOG_URL=https://gitlab.com/lsyslog/lsyslog/repository/archive.zip?ref=master
LUA_SYSLOG_FILE=lua-syslog.zip

LUA_ECHO_URL=https://github.com/openresty/echo-nginx-module/archive/master.zip
LUA_ECHO_FILE=lua-echo.zip


download_extract $NGINX_URL $NGINX_FILE downloads extracts/nginx-${NGINX_VERSION}
download_extract $NGINX_DEVEL_URL $NGINX_DEVEL_FILE downloads extracts/modules/ngx_devel_kit

download_extract $LUA_CJSON_URL $LUA_CJSON_FILE downloads extracts/deps/lua_cjson
download_extract $LUA_SYSLOG_URL $LUA_SYSLOG_FILE downloads extracts/deps/lua-syslog

download_extract $LUA_MAIN_URL $LUA_MAIN_FILE downloads extracts/modules/lua-nginx-module
download_extract $LUA_ECHO_URL $LUA_ECHO_FILE downloads extracts/modules/lua-echo-module

#if [ -z $IS_ALPINE ]; then
   download_extract $LUA_JIT_URL $LUA_JIT_FILE downloads extracts/deps/luajit
   
   make -C extracts/deps/luajit install
#fi

export LUAJIT_LIB=/usr/local/lib 
export LUAJIT_INC=/usr/local/include/luajit-2.0
export LUA_INCLUDE_DIR=$LUAJIT_INC
export LUA_LIB_DIR=$LUAJIT_LIB

#make -C extracts/deps/lua-syslog 
make -C extracts/deps/lua_cjson


cd extracts/nginx-${NGINX_VERSION}
LUAJIT_LIB=/usr/local/lib LUAJIT_INC=/usr/local/include/luajit-2.0 \
./configure \
--user=nginx                          \
--group=nginx                         \
--prefix=/etc/nginx                   \
--sbin-path=/usr/sbin/nginx           \
--conf-path=/etc/nginx/nginx.conf     \
--pid-path=/var/run/nginx.pid         \
--lock-path=/var/run/nginx.lock       \
--error-log-path=/var/log/nginx/error.log \
--http-log-path=/var/log/nginx/access.log \
--with-http_gzip_static_module        \
--with-http_stub_status_module        \
--with-http_ssl_module                \
--with-pcre                           \
--with-file-aio                       \
--with-http_realip_module             \
--without-http_scgi_module            \
--without-http_uwsgi_module           \
--without-http_fastcgi_module ${NGINX_DEBUG:+--debug} \
--with-cc-opt=-O2 --with-ld-opt='-Wl,-rpath,/usr/local/lib' \
--add${NGINX_MODULE_TYPE}-module=$PWD/../modules/ngx_devel_kit \
--add${NGINX_MODULE_TYPE}-module=$PWD/../modules/lua-nginx-module \
--add${NGINX_MODULE_TYPE}-module=$PWD/../modules/lua-echo-module

make -j 4
make install

create_nginx_user

nginx -t

#if [ ! -z $IS_ALPINE ]; then 
#  remove_alpine_packages
#fi 
