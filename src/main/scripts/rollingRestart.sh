#!/bin/bash

function rollingRestart()
{
    echo "Creating rolling restart script for Domain"
    cat <<EOF >${DOMAIN_PATH}/rolling-restart.py

import sys, socket
import os
import time
from java.util import Date
from java.text import SimpleDateFormat

try:
   connect('$WLS_USERNAME', '$WLS_PASSWORD', 't3://$WLS_ADMIN_URL')
   progress = rollingRestart('${DOMAIN_NAME}', options='isDryRun=false,shutdownTimeout=60,isAutoRevertOnFailure=true')
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
    echo "Adding managed server $wlsServerName"
    runuser -l oracle -c ". $oracleHome/oracle_common/common/bin/setWlstEnv.sh; java $WLST_ARGS weblogic.WLST $DOMAIN_PATH/roling-restart.py"
    if [[ $? != 0 ]]; then
         echo "Error : Rolling Restart for Domain $DOMAIN_NAME failed"
         exit 1
    else
         echo "Rolling Restart completed for Domain $DOMAIN_NAME"
    fi
}


#main

CURR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOMAIN_PATH="/u01/domains"
username="oracle"
groupname="oracle"

read DOMAIN_NAME WLS_USERNAME WLS_PASSWORD WLS_ADMIN_URL

rollingRestart
