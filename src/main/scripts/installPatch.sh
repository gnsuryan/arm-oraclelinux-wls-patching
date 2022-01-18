#!/bin/bash

function validate_input()
{
    
    if [ -z "${PATCH_FILE}" ];
    then
        echo "Patch File not provided."
        usage
        exit 1
    fi

    if [ -z "${SERVER_VM_NAME}" ];
    then
        echo "Server VM Name not provided."
        usage
        exit 1
    fi

    if [ -z "${SERVER_NAME}" ];
    then
        echo "Server Name not provided."
        usage
        exit 1
    fi

    if [ -z "${WLS_USERNAME}" ];
    then
        echo "WLS Username not provided."
        usage
        exit 1
    fi

    if [ -z "${WLS_PASSWORD}" ];
    then
        echo "WLS Password not provided."
        usage
        exit 1
    fi

    if [ -z "${WLS_ADMIN_URL}" ];
    then
        echo "Admin URL not provided."
        usage
        exit 1
    fi
}

function runCommandAsOracleUser()
{
   cmd="$1"
   echo "Exec command $cmd"

   runuser -l oracle -c "$cmd" &
   myPid=$!
   wait $myPid
   status="$?"
   echo -e "\nRETVAL=$status"

}

function getReturnCode()
{
  retVal="$1"
  retCode="$(echo "$retVal"|grep "RETVAL" | cut -d'=' -f2)"
  echo "$retCode"
}

function copy_patch()
{

    ls -l ${WLS_PATCH_FILE_SHARE_MOUNT}

    if [[ ! -f ${WLS_PATCH_FILE_SHARE_MOUNT}/${PATCH_FILE} ]];
    then
        echo "Patch file ${PATCH_FILE} not available on file share mount: ${WLS_PATCH_FILE_SHARE_MOUNT}"
        exit 1
    fi

    echo "copying patch from file share to patch home directory..."
    cp ${WLS_PATCH_FILE_SHARE_MOUNT}/${PATCH_FILE} ${PATCH_HOME_DIR}/${PATCH_FILE}
}

function setup_patch()
{
    echo "Creating directory required for applying patch"
    mkdir -p ${PATCH_HOME_DIR}

    cleanup_patch
}

function cleanup_patch()
{
    echo "cleaning up..."

    if [ ! -z "${PATCH_HOME_DIR}" ];
    then
        rm -rf ${PATCH_HOME_DIR}/*
    fi

    rm -rf ${DOMAIN_PATH}/*.py


}
#trap cleanup_patch EXIT


function check_opatch()
{
   ret="$(runCommandAsOracleUser '. /u01/app/wls/install/oracle/middleware/oracle_home/wlserver/server/bin/setWLSEnv.sh; /u01/app/wls/install/oracle/middleware/oracle_home/OPatch/opatch lsinventory  > /dev/null 2>&1')"
   echo "$ret"

   retVal=$(getReturnCode "$ret")

   if [[ "$retVal" != "0" ]];
   then
     echo "opatch command failed. Please set WebLogic Classpath appropriately and try again"
     exit 1
   else
     echo "opatch command verified successfully."
   fi
}

function getPatchNumber()
{
    PATCH_NUMBER=$(runuser -l oracle -c ". /u01/app/wls/install/oracle/middleware/oracle_home/wlserver/server/bin/setWLSEnv.sh > /dev/null 2>&1; /u01/app/wls/install/oracle/middleware/oracle_home/OPatch/opatch query --all ${PATCH_HOME_DIR}/${PATCH_FILE} |grep '<ONEOFF'|grep 'REF_ID'|cut -d'\"' -f2")
    echo "PATCH_NUMBER: ${PATCH_NUMBER}"
}

function install_patch()
{
    unzip -qq -d ${PATCH_HOME_DIR} ${PATCH_HOME_DIR}/${PATCH_FILE}
    chown -R oracle:oracle ${PATCH_HOME_DIR}

    JAVA_HOME=$(runuser -l oracle -c ". /u01/app/wls/install/oracle/middleware/oracle_home/wlserver/server/bin/setWLSEnv.sh > /dev/null 2>&1 && echo \$JAVA_HOME")

    echo "JAVA_HOME: $JAVA_HOME"

    PATCH_NUMBER=$(runuser -l oracle -c ". /u01/app/wls/install/oracle/middleware/oracle_home/wlserver/server/bin/setWLSEnv.sh > /dev/null 2>&1; /u01/app/wls/install/oracle/middleware/oracle_home/OPatch/opatch query --all ${PATCH_HOME_DIR}/${PATCH_FILE} |grep '<ONEOFF'|grep 'REF_ID'|cut -d'\"' -f2")

    echo "PATCH_NUMBER: $PATCH_NUMBER"

    patchApplyCommand="cd /u01/app/wls/install/oracle/middleware/oracle_home/OPatch && ./opatch apply -silent -jre ${JAVA_HOME}/jre  ${PATCH_HOME_DIR}/$PATCH_NUMBER"

    echo "Applying Patch... using command: $patchApplyCommand"
    ret=$(runCommandAsOracleUser "$patchApplyCommand")
    echo "$ret"
    
    retVal=$(getReturnCode "$ret")

   if [[ "$retVal" != "0" ]];
   then
     echo "opatch command failed. Please set WebLogic Classpath appropriately and try again"
     exit 1
   else
     echo "opatch command verified successfully."
   fi

}

function verify_patch()
{
    echo "Listing all Patches to see if it contains existing patch"
    
    ret="$(runCommandAsOracleUser '. /u01/app/wls/install/oracle/middleware/oracle_home/wlserver/server/bin/setWLSEnv.sh; /u01/app/wls/install/oracle/middleware/oracle_home/OPatch/opatch lsinventory -jdk ${JAVA_HOME}')"
    echo "$ret"
    retVal=$(echo "$ret"|grep "Patch  ${PATCH_NUMBER}")

    if [ "$?" == "0" ];
    then
      echo "PATCH INSTALL: SUCCESS"
    else
      echo "PATCH INSTALL: FAILED"
      exit 1
    fi
}

function shutdown_server()
{
  echo "shutting down weblogic server services on VM $SERVER_VM_NAME"

  if [ "$SERVER_VM_NAME" == "adminVM" ];
  then
     systemctl stop wls_admin.service
     systemctl status wls_admin.service
  else
     systemctl stop wls_nodemanager.service
     systemctl status wls_nodemanager.service
     create_server_shutdown_py_script
     runuser -l oracle -c ". /u01/app/wls/install/oracle/middleware/oracle_home/wlserver/server/bin/setWLSEnv.sh; java weblogic.WLST ${DOMAIN_PATH}/shutdown-server.py"

     if [ "$?" == "0" ];
     then
       echo "Server $SERVER_NAME successfully shutdown"
     else
       echo "Server $SERVER_NAME shutdown failed !!"
       exit 1
     fi
  fi

  echo "weblogic server services shutdown complete on VM $SERVER_VM_NAME"

}

function create_server_shutdown_py_script()
{
    echo "Creating server shutdown script for server $SERVER_NAME"
    cat <<EOF >${DOMAIN_PATH}/shutdown-server.py
connect('$WLS_USERNAME','$WLS_PASSWORD','t3://$WLS_ADMIN_URL')
domainRuntime()
slrBean = cmo.lookupServerLifeCycleRuntime('$SERVER_NAME')
status = slrBean.getState()
print 'current server status: '+status
if status != 'SHUTDOWN':
   shutdown('$SERVER_NAME','Server')
else:
   print 'Server $SERVER_NAME already shutdown'

disconnect()
EOF
     sudo chown -R $username:$groupname ${DOMAIN_PATH}
}

function create_server_start_py_script()
{
    echo "Creating server start script for server $SERVER_NAME"
    cat <<EOF >${DOMAIN_PATH}/start-server.py
connect('$WLS_USERNAME','$WLS_PASSWORD','t3://$WLS_ADMIN_URL')
domainRuntime()
slrBean = cmo.lookupServerLifeCycleRuntime('$SERVER_NAME')
status = slrBean.getState()
print 'current server status: '+status
if status != 'RUNNING':
   start('$SERVER_NAME','Server')
else:
   print 'Server $SERVER_NAME already running'

disconnect()
EOF
     sudo chown -R $username:$groupname ${DOMAIN_PATH}
}

function start_server()
{
  echo "Starting weblogic server services on VM $SERVER_VM_NAME"

  if [ "$SERVER_VM_NAME" == "adminVM" ];
  then
     systemctl start wls_admin.service
     systemctl status wls_admin.service
  else
     systemctl start wls_nodemanager.service
     systemctl status wls_nodemanager.service
     create_server_start_py_script
     runuser -l oracle -c ". /u01/app/wls/install/oracle/middleware/oracle_home/wlserver/server/bin/setWLSEnv.sh; java weblogic.WLST ${DOMAIN_PATH}/start-server.py"

     if [ "$?" == "0" ];
     then
       echo "Server $SERVER_NAME successfully started"
     else
       echo "Server $SERVER_NAME start failed !!"
       exit 1
     fi
  fi

  echo "weblogic server services start complete on VM $SERVER_VM_NAME"

}

#This function to wait for admin server
function wait_for_admin()
{
    if [ "$SERVER_VM_NAME" == "adminVM" ];
    then
       return
    fi

     #wait for admin to start
    count=1
    CHECK_URL="http://$WLS_ADMIN_URL/weblogic/ready"
    status=`curl --insecure -ILs $CHECK_URL | tac | grep -m1 HTTP/1.1 | awk {'print $2'}`
    echo "Waiting for admin server to start"
    while [[ "$status" != "200" ]]
    do
      echo "."
      count=$((count+1))
      if [ $count -le 30 ];
      then
          sleep 1m
      else
         echo "Error : Maximum attempts exceeded while starting admin server"
         exit 1
      fi
      status=`curl --insecure -ILs $CHECK_URL | tac | grep -m1 HTTP/1.1 | awk {'print $2'}`
      if [ "$status" == "200" ];
      then
         echo "Admin Server started succesfully..."
         break
      fi
    done
}


#main

CURR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PATCH_HOME_DIR="/u01/app/wls/patches"
WLS_FILE_SHARE="/mnt/wlsshare"
WLS_PATCH_FILE_SHARE_MOUNT="${WLS_FILE_SHARE}/patches"
DOMAIN_PATH="/u01/domains"
username="oracle"
groupname="oracle"

read PATCH_FILE SERVER_VM_NAME SERVER_NAME WLS_USERNAME WLS_PASSWORD WLS_ADMIN_URL

validate_input

setup_patch

copy_patch

getPatchNumber

check_opatch

wait_for_admin

shutdown_server

install_patch

verify_patch

wait_for_admin

start_server

