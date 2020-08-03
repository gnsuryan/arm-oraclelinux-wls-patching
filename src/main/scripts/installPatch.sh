#!/bin/bash

function download_patch_file()
{
    
    mkdir -p ${PATCH_HOME_DIR}
    cd ${PATCH_HOME_DIR}
    rm -rf *.zip
    wget https://github.com/gnsuryan/arm-oraclelinux-wls-admin-test/raw/master/src/main/p31471178_122130_Generic.zip
}

function set_wls_classpath()
{
     cd $WLS_HOME/server/bin
     . ./setWLSEnv.sh
     
     echo $CLASSPATH
     
     echo $JAVA_HOME
     export PATH=${WL_HOME}/../OPatch:$JAVA_HOME/bin:$PATH
}

function check_opatch()
{
   opatch lsinventory -jdk $JAVA_HOME
   
   if [ $? == 1 ];
   then
       echo "Unable to run opatch command."
       exit 1
   fi
}

function install_patch()
{
    echo "Applying Patch..."
    cd ${PATCH_HOME_DIR}/${PATCH_NUMBER}
    opatch napply -silent -jdk $JAVA_HOME
}

function verify_patch()
{
    echo "Listing all Patches to see if it contains existing patch"
    opatch lsinventory -jdk $JAVA_HOME

    opatch lsinventory -jdk $JAVA_HOME | grep "Patch  ${PATCH_NUMBER}"
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

################### VALIDATIONS #####################
if test $# -ne 2
then
  echo "Missing or Wrong Arguments "
  echo "Usage: applyWLSPatch.sh <PATCH_ZIP_FILE> <PATCH_NUMBER>"
  exit 1
fi

PATCH_ZIP_FILE="$1"
PATCH_NUMBER="$2"

if [ -z $PATCH_ZIP_FILE ] || [ -z $PATCH_NUMBER ];
then
  echo "Missing arguments: Usage: applyWLSPatch.sh <PATCH_ZIP_FILE>"
  exit 1
fi
################### VALIDATIONS #####################

WLS_HOME="/u01/app/wls/install/oracle/middleware/oracle_home/wlserver"

download_patch_file

set_wls_classpath

check_opatch

install_patch

verify_patch
