#!/bin/bash

function usage()
{
cat << USAGE >&2
Usage:
    -patchFile          PATCH_FILE      WebLogic Patch File
    -h|?|--help         HELP            Help/Usage info
USAGE

exit 1
}

function get_param()
{
    while [ "$1" ]
    do
        case "$1" in    
         -h |?|--help )        usage ;;
         -patchFile   )        PATCH_FILE=$2 ;;
         -serverVMName  )      SERVER_VM_NAME=$2 ;;
                     *)        echo 'invalid arguments specified'
                               usage;;
        esac
        shift 2
    done
}

function validate_input()
{
    
    if test $# -ne 4
    then
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
  fi

  echo "weblogic server services shutdown complete on VM $SERVER_VM_NAME"

}

function restart_server()
{
  echo "Restarting weblogic server services on VM $SERVER_VM_NAME"

  if [ "$SERVER_VM_NAME" == "adminVM" ];
  then
     systemctl start wls_admin.service
     systemctl status wls_admin.service
  else
     systemctl start wls_nodemanager.service
     systemctl status wls_nodemanager.service
  fi

  echo "weblogic server services restart complete on VM $SERVER_VM_NAME"

}


#main

CURR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PATCH_HOME_DIR="/u01/app/wls/patches"
WLS_PATCH_FILE_SHARE_MOUNT="/mnt/wlsshare/patches"

get_param "$@"

validate_input "$@"

setup_patch

copy_patch

getPatchNumber

check_opatch

shutdown_server

install_patch

verify_patch

restart_server
