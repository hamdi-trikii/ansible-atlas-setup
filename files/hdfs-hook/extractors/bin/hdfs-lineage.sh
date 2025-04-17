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
  if [ -z "${ATLAS_CONF_DIR}" ] || [ ! -e "${ATLAS_CONF_DIR}" ] && [ -e /etc/atlas/conf ]; then
        ATLAS_CONF_DIR=/etc/atlas/conf
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
      if [[ ${atlas_enableTLS} == "true" ]]; then
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

          # Change the atlas hook to synchronous/asynchronous by taking configuration from hdfs.conf
          grep -i "atlas.notification.hook.asynchronous" ${BASEDIR}/conf/hdfs.conf >> ${NEW_ATLAS_APPLICATION_PROPERTIES}

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
  if [ -z "${ATLAS_LOG_DIR}" ] || [ ! -e "${ATLAS_LOG_DIR}" ]; then
      ATLAS_LOG_DIR="/var/log/atlas"
  fi


  if [ ! -e "${ATLAS_LOG_DIR}" ]; then
    echo "$ATLAS_LOG_DIR not found on the system. Please make sure valid Atlas log directory is set to ATLAS_LOG_DIR."
    exit 1
  fi

  export ATLAS_LOG_DIR
  export LOGFILE="$ATLAS_LOG_DIR/hdfs-lineage.log"
}

function construct_classpath() {
  # Construct Atlas classpath using jars from lib/hdfs/ directory.
  for i in "${BASEDIR}/lib/hdfs/"*.jar; do
    ATLASCPPATH="${ATLASCPPATH}:$i"
  done
  for i in "/opt/apache-atlas-2.4.0/server/webapp/atlas/WEB-INF/lib/"*.jar; do
    ATLASCPPATH="${ATLASCPPATH}:$i"
  done

  # Add Atlas config and lineage config dir to classpath
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
CLI_ARGS=
ERR_STR=$'Currently supported operations are
./hdfs-lineage.sh -put /srcPath /destPath
./hdfs-lineage.sh -copyFromLocal /srcPath /destPath
./hdfs-lineage.sh -cp /srcPath /destPath
./hdfs-lineage.sh -mv /srcPath /destPath
./hdfs-lineage.sh -rm /srcPath
These operations support single srcPath and destPath
'

while true
do
  option=$1
  shift

#usage: hdfs-lineage
# -conf,--config <arg>         Configuration file for HDFS lineage
# -t,--transactionId <arg>  Transaction ID to use
  case "$option" in
    -conf) CLI_ARGS="$CLI_ARGS -conf $1"; shift;;
    #-t) ARGS="$ARGS -t $1"; shift;;
    -h) export HELP_OPTION="true"; CLI_ARGS="$CLI_ARGS -h";;
    -j) JVM_ARGS="$JVM_ARGS $1"; shift;;
    -l) export ATLAS_LOG_DIR="$1"; export LOGFILE="$ATLAS_LOG_DIR/hdfs-lineage.log"; shift;;
    --config) CLI_ARGS="$CLI_ARGS --config $1"; shift;;
    --help) export HELP_OPTION="true"; CLI_ARGS="$CLI_ARGS --help";;
    #--transactionId) ARGS="$ARGS --transactionId $1"; shift;;
    --jvmarg) JVM_ARGS="$JVM_ARGS $1"; shift;;
    --logdir) export ATLAS_LOG_DIR="$1"; export LOGFILE="$ATLAS_LOG_DIR/hdfs-lineage.log"; shift;;
    "") break;;
    *) ARGS="$ARGS $option"
  esac
done

JAVA_PROPERTIES="$ATLAS_OPTS -Datlas.log.dir=$ATLAS_LOG_DIR -Datlas.log.file=$LOGFILE
-Dlog4j.configurationFile=log4j.properties -Dlog4j.configuration=log4j.properties"
JAVA_PROPERTIES="${JAVA_PROPERTIES} ${JVM_ARGS} -Xss1M"


# hdfs lineage code
RETVAL=4
allArgs=(${ARGS[@]})





























if [[ ${#allArgs[@]} -ne 0 ]]; then
  hdfsCmd="/opt/hadoop-3.3.2/bin/hdfs dfs ${allArgs[*]}"
  opName="${allArgs[0]}"

  while getopts ":t:" option ${allArgs[@]:1}; do :; done

  allPaths=("${allArgs[@]:$OPTIND }")

  if ([[ "$opName" =~ ^-put|-copyFromLocal|-mv|-cp ]] && [ ${#allPaths[@]} = 2 ]) || ([ "$opName" = "-rm" ] && [ ${#allPaths[@]} = 1 ]); then
    srcPath="${allPaths[0]}"

    if [ "$srcPath" == "." ] || [ "$srcPath" == "-" ]; then
      echo "Invalid src.Please enter proper file or folder"
    else
      if [ "$opName" = "-cp" ] || [ "$opName" = "-mv" ]; then
          /opt/hadoop-3.3.2/bin/hdfs dfs -test -f "$srcPath"
          isSrcPathFile=$?
      fi
      ### Execute the hdfs command
      /opt/hadoop-3.3.2/bin/hdfs dfs ${allArgs[*]}
      status=$?
      if [ $status -eq 0 ]; then
        echo "$hdfsCmd command was successful"
        case $opName in
        -put | -copyFromLocal)
          destPath="${allPaths[1]}"
          /opt/hadoop-3.3.2/bin/hdfs dfs -test -d "$destPath"
          isDestPathFolder=$?
          if [[ -f $srcPath && $isDestPathFolder -eq 0 ]]; then
            if [[ $destPath == */ ]]
              then
                destPath=("$destPath$(basename "$srcPath")")
              else
                destPath=("$destPath/$(basename "$srcPath")")
            fi
          fi
          createTime="$(/opt/hadoop-3.3.2/bin/hdfs dfs -stat %Y $destPath)"
          ;;
        -cp | -mv)
          destPath="${allPaths[1]}"
          echo "warn!!!!!!!!!!!! "
          /opt/hadoop-3.3.2/bin/hdfs dfs -test -d "$destPath"
          isDestPathFolder=$?
          if [[ $isSrcPathFile -eq 0 && $isDestPathFolder -eq 0 ]]; then
            if [[ $destPath == */ ]]
              then
                destPath=("$destPath$(basename "$srcPath")")
              else
                destPath=("$destPath/$(basename "$srcPath")")
            fi
          fi
          createTime="$(/opt/hadoop-3.3.2/bin/hdfs dfs -stat %Y $destPath)"
          ;;
        -rm)
          destPath=""
          createTime=""
          ;;
        *)
          echo "Command not supported"
          exit $RETVAL
          ;;
        esac

        if [ -z ${HELP_OPTION} ]; then
          echo "Log file for HDFS Lineage is $LOGFILE"
        fi

        # call to the main java class
        "${JAVA_BIN}" ${JAVA_PROPERTIES} -cp "${CP}" org.apache.atlas.hdfs.cli.HDFSLineageMain  $CLI_ARGS "$opName" "$srcPath" "$destPath" "$createTime"
        RETVAL=$?
      else

        echo "$hdfsCmd failed"
      fi

    fi
  else
   echo "$ERR_STR"
  fi
else
    "${JAVA_BIN}" ${JAVA_PROPERTIES} -cp "${CP}" org.apache.atlas.hdfs.cli.HDFSLineageMain "-h"
    RETVAL=$?

    echo "$ERR_STR"

fi

if [ -z ${HELP_OPTION} ]; then
  [ $RETVAL -eq 0 ] && echo "HDFS lineage created successfully!!!"
  [ $RETVAL -eq 1 ] && echo "Failed to create HDFS lineage. Please check log file."
  [ $RETVAL -eq 2 ] && RETVAL=0
  [ $RETVAL -eq 3 ] && echo "HDFS Lineage is not created , as path(s) not whitelisted"
  [ $RETVAL -eq 4 ] && echo "Failed to create HDFS lineage. Please check hdfs command."
fi

exit $RETVAL
