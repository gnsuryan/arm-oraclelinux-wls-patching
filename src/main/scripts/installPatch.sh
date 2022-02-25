#!/bin/bash

function validate_input()
{
    if [ -z "${IS_CLUSTER_DOMAIN}" ];
    then
        echo "IS_CLUSTER_DOMAIN Flag not provided"
        usage
        exit 1
    fi
    
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
trap cleanup_patch EXIT


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

function install_patch()
{
    unzip -qq -d ${PATCH_HOME_DIR} ${PATCH_HOME_DIR}/${PATCH_FILE}
    chown -R oracle:oracle ${PATCH_HOME_DIR}
    rm -rf ${PATCH_HOME_DIR}/${PATCH_FILE}

    JAVA_HOME=$(runuser -l oracle -c ". /u01/app/wls/install/oracle/middleware/oracle_home/wlserver/server/bin/setWLSEnv.sh > /dev/null 2>&1 && echo \$JAVA_HOME")

    echo "JAVA_HOME: $JAVA_HOME"

    cd ${PATCH_HOME_DIR}/*
    
	patchListFile=`find . -name linux64_patchlist.txt`
	if [[ "${patchListFile}" == *"linux64_patchlist.txt"* ]];
	then
		echo "Applying WebLogic Stack Patch Bundle"
		command="/u01/app/wls/install/oracle/middleware/oracle_home/OPatch/opatch napply -silent -oh /u01/app/wls/install/oracle/middleware/oracle_home  -phBaseFile linux64_patchlist.txt"
		echo $command
		ret=$(runCommandAsOracleUser "cd ${PATCH_HOME_DIR}/*/binary_patches ; ${command}")
	else
		echo "Applying regular WebLogic patch"
		command="/u01/app/wls/install/oracle/middleware/oracle_home/OPatch/opatch apply -silent"
		echo $command
		ret=$(runCommandAsOracleUser "cd ${PATCH_HOME_DIR}/* ; ${command}")
	fi

    retVal=$(getReturnCode "$ret")
    
    if [[ "$retVal" != "0" ]];
    then
        echo "opatch command failed. Please set WebLogic Classpath appropriately and try again"
        exit 1
    else
        echo "opatch command applied successfully."
    fi

}

function start_coherence_server()
{
  if [ "$SERVER_VM_NAME" != *"StorageVM"* ];
  then
     return
  else
     echo "Starting weblogic coherence server on VM $SERVER_VM_NAME"
     systemctl start wls_nodemanager.service
     systemctl status wls_nodemanager.service
     create_server_start_py_script
     runuser -l oracle -c ". /u01/app/wls/install/oracle/middleware/oracle_home/wlserver/server/bin/setWLSEnv.sh; java weblogic.WLST ${DOMAIN_PATH}/shutdown-server.py"

     if [ "$?" == "0" ];
     then
       echo "Coherence Server $SERVER_NAME successfully shutdown"
     else
       echo "Coherence Server $SERVER_NAME shutdown failed !!"
       exit 1
     fi
  fi
}

function shutdown_coherence_server()
{
  if [ "$SERVER_VM_NAME" != *"StorageVM"* ];
  then
     return
  else
     echo "Shutting down weblogic coherence server on VM $SERVER_VM_NAME"
     systemctl stop wls_nodemanager.service
     systemctl status wls_nodemanager.service
     create_server_shutdown_py_script
     runuser -l oracle -c ". /u01/app/wls/install/oracle/middleware/oracle_home/wlserver/server/bin/setWLSEnv.sh; java weblogic.WLST ${DOMAIN_PATH}/shutdown-server.py"

     if [ "$?" == "0" ];
     then
       echo "Coherence Server $SERVER_NAME successfully shutdown"
     else
       echo "Coherence Server $SERVER_NAME shutdown failed !!"
       exit 1
     fi
  fi
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

function shutdown_wls_service()
{
  echo "Shutdown weblogic server services on VM $SERVER_VM_NAME"

  if [ "$SERVER_VM_NAME" == "adminVM" ];
  then
     systemctl stop wls_admin.service
     systemctl status wls_admin.service
  else
     systemctl stop wls_nodemanager.service
     systemctl status wls_nodemanager.service
  fi

  echo "weblogic server services shutdown complete on VM $SERVER_VM_NAME"
}

function start_wls_service()
{
  echo "Starting weblogic server services on VM $SERVER_VM_NAME"

  if [ "$SERVER_VM_NAME" == "adminVM" ];
  then
     systemctl start wls_admin.service
     systemctl status wls_admin.service
  else
     systemctl start wls_nodemanager.service
     systemctl status wls_nodemanager.service
  fi

  echo "weblogic server services start complete on VM $SERVER_VM_NAME"

}

#This function to wait for admin server
function wait_for_admin()
{

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

function performRollingRestartForManagedServers()
{

    if [ "$SERVER_VM_NAME" != "adminVM" ];
    then
       return
    fi

    if [ "${IS_CLUSTER_DOMAIN}" != "true" ];
    then
       return
    fi

    echo "Creating rolling restart script for Domain"
    cat <<EOF >${DOMAIN_PATH}/rolling-restart.py

import sys, socket
import os
import time
from java.util import Date
from java.text import SimpleDateFormat

try:
   connect('$WLS_USERNAME', '$WLS_PASSWORD', 't3://$WLS_ADMIN_URL')
   progress = rollingRestart('${CLUSTER_NAME}')
   lastProgressString = ""

   progressString=progress.getProgressString()
   # for testing progressString="12 / 12"
   steps=progressString.split('/')


   while not (steps[0].strip() == steps[1].strip()):
     if not (progressString == lastProgressString):
       print "Completed step " + steps[0].strip() + " of " + steps[1].strip() + " total steps"
       lastProgressString = progressString

     java.lang.Thread.sleep(1000)

     progressString=progress.getProgressString()
     steps=progressString.split('/')
     if(len(steps) == 1):
       print steps[0]
       break;

   if(len(steps) == 2):
     print "Completed step " + steps[0].strip() + " of " + steps[1].strip() + " total steps"

   t = Date()
   endTime=SimpleDateFormat("hh:mm:ss").format(t)

   print ""
   print "RolloutDirectory task finished at " + endTime
   print ""
   viewMBean(progress)

   state = progress.getStatus()
   error = progress.getError()
   #TODO: better error handling with the progress.getError obj and msg
   # not a string, can raise directly
   stateString = '%s' % state
   if stateString != 'SUCCESS':
     #msg = 'State is %s and error is: %s' % (state,error)
     msg = "State is: " + state
     raise(msg)
   elif error is not None:
     msg = "Error not null for state: " + state
     print msg
     #raise("Error not null for state: %s and error is: %s" + (state,error))
     raise(error)
except Exception, e:
  e.printStackTrace()
  dumpStack()
  raise("Rollout failed")

exit()
EOF

    sudo chown -R $username:$groupname $DOMAIN_PATH
    echo "Performing rolling restart for Cluster $CLUSTER_NAME"
    runuser -l oracle -c ". /u01/app/wls/install/oracle/middleware/oracle_home/wlserver/server/bin/setWLSEnv.sh; java weblogic.WLST $DOMAIN_PATH/rolling-restart.py"
    if [[ $? != 0 ]]; then
         echo "Error : Rolling Restart for Cluster $CLUSTER_NAME failed"
         exit 1
    else
         echo "Rolling Restart completed for Cluster $CLUSTER_NAME"
    fi
}

function restart_coherence_server()
{
   start_coherence_server
   shutdown_coherence_server
}


#main

CURR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PATCH_HOME_DIR="/u01/app/wls/patches"
WLS_FILE_SHARE="/mnt/wlsshare"
WLS_PATCH_FILE_SHARE_MOUNT="${WLS_FILE_SHARE}/patches"
DOMAIN_PATH="/u01/domains"
username="oracle"
groupname="oracle"
CLUSTER_NAME="cluster1"

read PATCH_FILE IS_CLUSTER_DOMAIN SERVER_VM_NAME SERVER_NAME WLS_USERNAME WLS_PASSWORD WLS_ADMIN_URL

IS_CLUSTER_DOMAIN="${IS_CLUSTER_DOMAIN,,}"

validate_input

setup_patch

copy_patch

check_opatch

wait_for_admin

install_patch

wait_for_admin

#shutdown_wls_service

#start_wls_service

#performRollingRestartForManagedServers

#restart_coherence_server

