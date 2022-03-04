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

function cleanup()
{
    echo "cleaning up..."

    if [ ! -z "${PATCH_HOME_DIR}" ];
    then
        rm -rf ${PATCH_HOME_DIR}/*
    fi

    rm -rf ${DOMAIN_PATH}/*.py
}

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

function shutdown_wls_service()
{
  echo "Shutdown weblogic server services on VM $SERVER_VM_NAME"

  if [ "$SERVER_VM_NAME" == "adminVM" ];
  then
     systemctl stop wls_nodemanager.service
     systemctl status wls_nodemanager.service
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

function create_shutdown_py_script()
{
    echo "Creating server shutdown script for all servers running on VM $SERVER_VM_NAME"
    cat <<EOF >${DOMAIN_PATH}/machine-shutdown-server.py
connect('$WLS_USERNAME','$WLS_PASSWORD','t3://$WLS_ADMIN_URL')
cd('/')
current_m=''
hostname='$SERVER_VM_NAME'
machines = cmo.getMachines()
for m in machines:
    print str(m)
    nm = m.getNodeManager()
    if nm.getListenAddress() in hostname:
        current_m=m

print 'current_m: '+str(current_m)

serverConfig()
serversToShutdown=[]
servers = cmo.getServers()
for s in servers:
    name = s.getName()
    print 'server : '+name
    if name in 'admin' :
       continue
    ref = getMBean('/Servers/'+name+'/Machine/'+current_m.getName())
    print str(ref)
    if ref != None:
       serversToShutdown.append(name)

print 'ServerToShutdown List'
for x in range(len(serversToShutdown)):
    print serversToShutdown[x]

domainRuntime()
for servername in serversToShutdown:
       try:
           slrBean = cmo.lookupServerLifeCycleRuntime(servername)
           status = slrBean.getState()
           print 'Server ='+servername+', Status = '+status
           if status == 'SHUTDOWN':
              print 'Server '+servername+' already shutdown'
              continue
       except Exception,e:
           print e
           continue

       Thread.sleep(2000)
       print 'shutting down server: '+servername
       shutdown(servername,'Server',ignoreSessions='true', force='true')
       Thread.sleep(10000)
       slrBean = cmo.lookupServerLifeCycleRuntime(servername)
       status = slrBean.getState()
       print 'Server ='+servername+', Status = '+status
       if status == 'SHUTDOWN':
          print 'Server '+servername+' shutdown successfully'
       else:
          raise Exception('Failed to shutdown server '+servername)

disconnect()
EOF
     sudo chown -R $username:$groupname ${DOMAIN_PATH}
}

function create_server_status_py_script()
{
    echo "Creating server status check script for all servers configured on VM $SERVER_VM_NAME"
    cat <<EOF >${DOMAIN_PATH}/machine-check-server-status.py

connect('$WLS_USERNAME','$WLS_PASSWORD','t3://$WLS_ADMIN_URL')
cd('/')
current_m=''
hostname='$SERVER_VM_NAME'
machines = cmo.getMachines()
for m in machines:
    nm = m.getNodeManager()
    if nm.getListenAddress() in hostname:
        current_m=m

print 'current_m: '+str(current_m)

serverConfig()
serversForStatusCheck=[]
servers = cmo.getServers()
for s in servers:
    name = s.getName()
    if name in 'admin' :
       continue

    i=1
    serverConfig()
    ref = getMBean('/Servers/'+name+'/Machine/'+current_m.getName())
    if ref != None:
       serversForStatusCheck.append(name)


domainRuntime()
for servername in serversForStatusCheck:
    i=1
    statusFlag=False
    while i<=5 and statusFlag == False:
        slrBean = cmo.lookupServerLifeCycleRuntime(servername)
        status = slrBean.getState()
        print 'Server = '+servername+', Status = '+status
        if status == 'RUNNING':
            statusFlag=True
            break
        else:
            statusFlag=False
            Thread.sleep(60000)
        i+=1

    if statusFlag != True:
        raise Exception('Server '+servername+' not running despite waiting for 5 minutes')
    else:
        print 'Server '+servername+' running successfully'

disconnect()
EOF
     sudo chown -R $username:$groupname ${DOMAIN_PATH}
}

function shutdownAllServersOnVM()
{
     echo "Shutting down all servers running on VM $SERVER_VM_NAME"
     create_shutdown_py_script
     runuser -l oracle -c ". /u01/app/wls/install/oracle/middleware/oracle_home/wlserver/server/bin/setWLSEnv.sh; java weblogic.WLST ${DOMAIN_PATH}/machine-shutdown-server.py"

     if [ "$?" == "0" ];
     then
       echo "All Servers on VM $SERVER_VM_NAME successfully shutdown"
     else
       echo "All Servers shutdown failed on VM $SERVER_VM_NAME !!"
       exit 1
     fi
}

function checkStatusOfServersOnVM()
{
     echo "Checking status of all servers configured on VM $SERVER_VM_NAME"
     create_server_status_py_script
     runuser -l oracle -c ". /u01/app/wls/install/oracle/middleware/oracle_home/wlserver/server/bin/setWLSEnv.sh; java weblogic.WLST ${DOMAIN_PATH}/machine-check-server-status.py"

     if [ "$?" == "0" ];
     then
       echo "All Servers on VM $SERVER_VM_NAME are running"
     else
       echo "One or more Servers on VM $SERVER_VM_NAME are not running!!"
       exit 1
     fi
}

#main

CURR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PATCH_HOME_DIR="/u01/app/wls/patches"
WLS_FILE_SHARE="/mnt/wlsshare"
WLS_PATCH_FILE_SHARE_MOUNT="${WLS_FILE_SHARE}/patches"
DOMAIN_PATH="/u01/domains"
username="oracle"
groupname="oracle"

read PATCH_FILE SERVER_VM_NAME WLS_USERNAME WLS_PASSWORD WLS_ADMIN_URL

validate_input

if [ "$SERVER_VM_NAME" == "adminVM" ];
then
    wait_for_admin
    shutdown_wls_service
    setup_patch
    copy_patch
    check_opatch
    install_patch
    start_wls_service
    wait_for_admin
else
    shutdown_wls_service
    shutdownAllServersOnVM
    setup_patch
    copy_patch
    check_opatch
    install_patch
    start_wls_service
    checkStatusOfServersOnVM
fi

cleanup