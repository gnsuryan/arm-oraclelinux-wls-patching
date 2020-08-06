#!/bin/bash

function usage()
{
cat << USAGE >&2
Usage:
    -patchFile          PATCH_FILE      WebLogic Patch File
    -patchNumber        PATCH_NUMBER    WebLogic Patch Number
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
         -patchNumber )        PATCH_NUMBER=$2 ;;
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

    if [ -z "${PATCH_NUMBER}" ];
    then
        echo "Patch Number not provided."
        usage
        exit 1
    fi

}

function copy_patch()
{

    ls -l ${WLS_FILE_SHARE_MOUNT}

    if [[ ! -f ${WLS_FILE_SHARE_MOUNT}/${PATCH_FILE} ]];
    then
        echo "Patch file ${PATCH_FILE} not available on file share mount: ${WLS_FILE_SHARE_MOUNT}"
        exit 1
    fi

    echo "copying patch from file share to patch home directory..."
    cp ${WLS_FILE_SHARE_MOUNT}/${PATCH_FILE} ${PATCH_HOME_DIR}/${PATCH_FILE}
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
    rm -rf ${PATCH_HOME_DIR}/*
}
trap cleanup_patch EXIT


function check_opatch()
{
   runuser -l oracle -c '. /u01/app/wls/install/oracle/middleware/oracle_home/wlserver/server/bin/setWLSEnv.sh; /u01/app/wls/install/oracle/middleware/oracle_home/OPatch/opatch lsinventory -jdk ${JAVA_HOME} > /dev/null 2>&1'

   if [[ $? != 0 ]];
   then
     echo "opatch command failed. Please set WebLogic Classpath appropriately and try again"
     exit 1
   else
     echo "opatch command verified successfully."
   fi
}

function install_patch()
{
    unzip -d ${PATCH_HOME_DIR} ${PATCH_HOME_DIR}/${PATCH_FILE}
    chown -R oracle:oracle ${PATCH_HOME_DIR}

    echo "Applying Patch..."
    runuser -l oracle -c '. /u01/app/wls/install/oracle/middleware/oracle_home/wlserver/server/bin/setWLSEnv.sh; cd /u01/app/wls/patches; /u01/app/wls/install/oracle/middleware/oracle_home/OPatch/opatch napply -silent -jdk ${JAVA_HOME}'
}

function verify_patch()
{
    echo "Listing all Patches to see if it contains existing patch"
    
    runuser -l oracle -c '. /u01/app/wls/install/oracle/middleware/oracle_home/wlserver/server/bin/setWLSEnv.sh; /u01/app/wls/install/oracle/middleware/oracle_home/OPatch/opatch lsinventory -jdk ${JAVA_HOME} | grep "Patch  ${PATCH_NUMBER}"'
    patchApplied=$?

    if [ $patchApplied == "0" ];
    then
      echo "PATCH INSTALL: SUCCESS"
      exit 0
    else
      echo "PATCH INSTALL: FAILED"
      exit 1
    fi
}

#main

CURR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PATCH_HOME_DIR="/u01/app/wls/patches"
WLS_FILE_SHARE_MOUNT="/mnt/wlsshare"

get_param "$@"

validate_input "$@"

setup_patch

copy_patch

check_opatch

install_patch

verify_patch
