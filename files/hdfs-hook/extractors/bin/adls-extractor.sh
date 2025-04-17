#!/bin/bash
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License. See accompanying LICENSE file.
#

function validate_java() {
  if test -z "${JAVA_HOME}"
  then
      JAVA_BIN=`which java 2> /dev/null`
      JAR_BIN=`which jar 2> /dev/null`
  else
      JAVA_BIN="${JAVA_HOME}/bin/java"
      JAR_BIN="${JAVA_HOME}/bin/jar"
  fi

  export JAVA_BIN

  if [ -z "${JAVA_BIN}" ] || [ -z "${JAR_BIN}" ]; then
    echo "java and/or jar not found on the system. Please set JAVA_HOME or make sure java and jar commands are available."
    exit 1
  fi

  if [ ! -e "${JAVA_BIN}" ] || [ ! -e "${JAR_BIN}" ]; then
    echo "$JAVA_BIN and/or $JAR_BIN not found on the system. Please make sure java and jar commands are available."
    exit 1
  fi
}

function validate_atlas_config_path() {
  if test -z "${ATLAS_CONF_DIR}"
  then
    CURRENT_ATLAS_PROC_DIR=`ls -t /var/run/cloudera-scm-agent/process 2> /dev/null | grep -i ".*atlas-ATLAS_SERVER$" | head -1`
    ATLAS_CONF_DIR="/var/run/cloudera-scm-agent/process/${CURRENT_ATLAS_PROC_DIR}/conf"

    if [ -z "${ATLAS_CONF_DIR}" ] || [ ! -e "${ATLAS_CONF_DIR}" ]; then
      ATLAS_CONF_DIR=`ps -eo cmd | grep -i "\-Datlas.conf=.* org.apache.atlas.Atlas .*" | grep -v "grep" | sed -n -e 's/^.*\-Datlas.conf=\(.*\) \-Xms.*$/\1/p' | cut -d " " -f 1`
      if [ -z "${ATLAS_CONF_DIR}" ] || [ ! -e "${ATLAS_CONF_DIR}" ] && [ -e /etc/atlas/conf ]; then
        ATLAS_CONF_DIR=/etc/atlas/conf
      fi
    fi
  fi

  if [ -z "${ATLAS_CONF_DIR}" ]; then
    echo "Atlas config directory not found. Please set valid Atlas config directory to ATLAS_CONF_DIR."
    exit 1
  fi

  if [ ! -e "${ATLAS_CONF_DIR}" ]; then
    echo "$ATLAS_CONF_DIR not found on the system. Please make sure valid Atlas config directory is set to ATLAS_CONF_DIR."
    exit 1
  fi
}

function prepare_atlas_application_properties() {
  if [ ! -z "${ATLAS_CONF_DIR}" ] && [ -e "${ATLAS_CONF_DIR}" ]; then
    ATLAS_PROCESS_APPLICATION_PROPERTIES="${ATLAS_CONF_DIR}/atlas-application.properties"

    if [ -f "$ATLAS_PROCESS_APPLICATION_PROPERTIES" ]
    then
      # Load the properties to variables
      while IFS='=' read -r key value
      do
        key=$(echo $key | tr '.' '_')
        key=$(echo -e "${key}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        value=$(echo -e "${value}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        eval ${key}=\${value} 2> /dev/null
      done < "${ATLAS_PROCESS_APPLICATION_PROPERTIES}"

      # Check if TLS is enabled
      if [ ${atlas_enableTLS} == "true" ]; then
        if [ -z ${atlas_kafka_ssl_truststore_password} ] || [ -z ${truststore_password} ]; then
          # Create a temporary directory and set trap to remove the same in case of unexpected exit
          export scratch_dir=$(mktemp -d -t tmp.XXXXXXXXXXXXXXXX)
          trap "{ rm -rf ${scratch_dir}; }" EXIT

          if [ -z ${scratch_dir} ]; then
            echo "Unable to create temporary directory."
            exit 1
          fi

          # New configuration will be created at this temporary directory
          NEW_ATLAS_APPLICATION_PROPERTIES="${scratch_dir}/atlas-application.properties"

          # Create the application properties file at the temporary directory
          cp -rf ${ATLAS_PROCESS_APPLICATION_PROPERTIES} ${NEW_ATLAS_APPLICATION_PROPERTIES}

          # Change the atlas hook to synchronous/asynchronous by taking configuration from adls.conf
          grep -i "atlas.notification.hook.asynchronous" ${BASEDIR}/conf/adls.conf >> ${NEW_ATLAS_APPLICATION_PROPERTIES}

          currParameter="";
          SSL_CLIENT_CONFIG="/etc/hadoop/conf/ssl-client.xml";

          # Check if ssl client config file present
          if [ -f ${SSL_CLIENT_CONFIG} ]; then
            # Load the configuartion for location and password from ssl-client.xml
            for i in `echo "cat /configuration/property/name/text()|/configuration/property/value/text()" | xmllint --nocdata --shell ${SSL_CLIENT_CONFIG} | sed '1d;\$d' | grep -v "\-\-\-"`
            do
              if [ ! -z "${currParameter}" ]; then
                currParameter=$(echo $currParameter | tr '.' '_')
                eval ${currParameter}=\${i}
                currParameter=""
              fi

              if [ "${i}" == "ssl.client.truststore.location" ] || [ "${i}" == "ssl.client.truststore.password" ]; then
                currParameter="${i}";
              fi
            done

            if [ -z ${ssl_client_truststore_location} ] || [ -z ${ssl_client_truststore_password} ]; then
              echo "ssl.client.truststore.location or ssl.client.truststore.password configuration missing from ${SSL_CLIENT_CONFIG}."
              exit 1
            else
              # Modify or add trust store location and password at new atlas application properties
              grep -q '^atlas.kafka.ssl.truststore.location' ${NEW_ATLAS_APPLICATION_PROPERTIES} && sed -i -e 's;atlas.kafka.ssl.truststore.location=.*;atlas.kafka.ssl.truststore.location='"$ssl_client_truststore_location"';g' ${NEW_ATLAS_APPLICATION_PROPERTIES} || echo "atlas.kafka.ssl.truststore.location=$ssl_client_truststore_location" >> ${NEW_ATLAS_APPLICATION_PROPERTIES}
              grep -q '^atlas.kafka.ssl.truststore.password' ${NEW_ATLAS_APPLICATION_PROPERTIES} && sed -i -e 's;atlas.kafka.ssl.truststore.password=.*;atlas.kafka.ssl.truststore.password='"$ssl_client_truststore_password"';g' ${NEW_ATLAS_APPLICATION_PROPERTIES} || echo "atlas.kafka.ssl.truststore.password=$ssl_client_truststore_password" >> ${NEW_ATLAS_APPLICATION_PROPERTIES}
              grep -q '^truststore.file' ${NEW_ATLAS_APPLICATION_PROPERTIES} && sed -i -e 's;truststore.file=.*;truststore.file='"$ssl_client_truststore_location"';g' ${NEW_ATLAS_APPLICATION_PROPERTIES} || echo "truststore.file=$ssl_client_truststore_location" >> ${NEW_ATLAS_APPLICATION_PROPERTIES}
              grep -q '^truststore.password' ${NEW_ATLAS_APPLICATION_PROPERTIES} && sed -i -e 's;truststore.password=.*;truststore.password='"$ssl_client_truststore_password"';g' ${NEW_ATLAS_APPLICATION_PROPERTIES} || echo "truststore.password=$ssl_client_truststore_password" >> ${NEW_ATLAS_APPLICATION_PROPERTIES}
            fi
          else
            echo "${SSL_CLIENT_CONFIG} not found."
            exit 1
          fi
        fi
      fi
    else
      echo "$ATLAS_PROCESS_APPLICATION_PROPERTIES not found."
      exit 1
    fi
  fi
}

function set_log_dir_file() {
  if test -z "${ATLAS_LOG_DIR}"
  then
    ATLAS_LOG_DIR=`cat $ATLAS_CONF_DIR/atlas-log4j.properties | grep -i "log\.dir=" | cut -d "=" -f 2`
    if [ -z "${ATLAS_LOG_DIR}" ] || [ ! -e "${ATLAS_LOG_DIR}" ]; then
      ATLAS_LOG_DIR="/var/log/atlas"
    fi
  fi

  if [ ! -e "${ATLAS_LOG_DIR}" ]; then
    echo "$ATLAS_LOG_DIR not found on the system. Please make sure valid Atlas log directory is set to ATLAS_LOG_DIR."
    exit 1
  fi

  export ATLAS_LOG_DIR
  export LOGFILE="$ATLAS_LOG_DIR/adls-extractor.log"
}

function construct_classpath() {
  # Construct Atlas classpath using jars from lib/azure-adls/ directory.
  for i in "${BASEDIR}/lib/azure-adls/"*.jar; do
    ATLASCPPATH="${ATLASCPPATH}:$i"
  done

  # Add Atlas config and extractors config dir to classpath
  export ATLASCPPATH=${ATLAS_CONF_DIR}:"${BASEDIR}/conf":${ATLASCPPATH}

  if [ ! -z ${scratch_dir} ]; then
    export ATLASCPPATH=${scratch_dir}:${ATLASCPPATH}
  fi
}

# Main Processing Starts Here

# Resolve links - $0 may be a softlink
PRG="${0}"

while [ -h "${PRG}" ]; do
  ls=`ls -ld "${PRG}"`
  link=`expr "$ls" : '.*-> \(.*\)$'`
  if expr "$link" : '/.*' > /dev/null; then
    PRG="$link"
  else
    PRG=`dirname "${PRG}"`/"$link"
  fi
done

BASEDIR=`dirname ${PRG}`
BASEDIR=`cd ${BASEDIR}/..;pwd`
ATLAS_BASE_DIR="$(dirname "$BASEDIR")"
SERVER_LIB_PATH="$ATLAS_BASE_DIR/server/webapp/atlas/WEB-INF/lib"

validate_java
validate_atlas_config_path
prepare_atlas_application_properties
construct_classpath
set_log_dir_file

TIME=`date +%Y%m%d%H%M%s`
export CP="${ATLASCPPATH}"

ARGS=
JVM_ARGS=

while true
do
  option=$1
  shift

#usage: adls-extractor
# -c,--config <arg>       Configuration file for ADLS extraction
# -e,--extraction <arg>   Extraction type to be done. Possible values are
#                         “INC” and “BULK” for incremental and Bulk
#                         extractions.
# -l,--logdir <arg>       Log directory for Azure ADLS Extractor
# -f,failOnError          Fail when error is encountered
  case "$option" in
    -c) ARGS="$ARGS -c $1"; shift;;
    -e) ARGS="$ARGS -e $1"; shift;;
    -f) ARGS="$ARGS -f";;
    -h) export HELP_OPTION="true"; ARGS="$ARGS -h";;
    -j) JVM_ARGS="$JVM_ARGS $1"; shift;;
    -l) export ATLAS_LOG_DIR="$1"; export LOGFILE="$ATLAS_LOG_DIR/adls-extractor.log"; shift;;
    --config) ARGS="$ARGS --config $1"; shift;;
    --failOnError) ARGS="$ARGS --failOnError";;
    --help) export HELP_OPTION="true"; ARGS="$ARGS --help";;
    --extraction) ARGS="$ARGS --extraction $1"; shift;;
    --jvmarg) JVM_ARGS="$JVM_ARGS $1"; shift;;
    --logdir) export ATLAS_LOG_DIR="$1"; export LOGFILE="$ATLAS_LOG_DIR/adls-extractor.log"; shift;;
    "") break;;
    *) ARGS="$ARGS $option"
  esac
done

JAVA_PROPERTIES="$ATLAS_OPTS -Datlas.log.dir=$ATLAS_LOG_DIR -Datlas.log.file=$LOGFILE
-Dlog4j.configurationFile=log4j.properties -Dlog4j.configuration=log4j.properties"
JAVA_PROPERTIES="${JAVA_PROPERTIES} ${JVM_ARGS} -Xss1M"

if [ -z ${HELP_OPTION} ]; then
  echo "Log file for Azure ADLS Extraction is $LOGFILE"
fi

"${JAVA_BIN}" ${JAVA_PROPERTIES} -cp "${CP}" org.apache.atlas.adls.cli.ADLSExtractorMain $ARGS

RETVAL=$?
if [ -z ${HELP_OPTION} ]; then
  [ $RETVAL -eq 0 ] && echo Azure ADLS Meta Data extracted successfully!!!
  [ $RETVAL -eq 1 ] && echo Failed to extract ADLS Meta Data!!!
  [ $RETVAL -eq 2 ] && RETVAL=0
fi

exit $RETVAL
