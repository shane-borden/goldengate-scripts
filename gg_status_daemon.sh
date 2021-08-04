#!/bin/ksh
##################################################################
# Name: ggs_status_daemon.ksh                                    #
# PURPOSE: TO MONITOR LAG OF GOLDEN GATE                         #
# THIS SCRIPT WILL NOTIFY IF REPLICATION LAG IS MORE THEN 30 MIN #
# THIS SCRIPT WILL NOTIFY IF CHECKPOINT LAG IS MORE THAN 15 MIN  #
# THIS SCRIPT WILL NOTIFY OBJECTS ARE ABENDED                    #
##################################################################

helpFunction()
{
   echo ""
   echo "Usage: $0 -o OPERATION (UPDOWN/LAG) -e ENVIRONMENT FILE"
   echo -e "\t-o Designate the script to check lag or up/down condition"
   echo -e "\t-e Environment file that contains the necessary parameters to execute GoldenGate"
   exit 1 # Exit script after printing help
}

chkGoldenGate() {

##########################################################################
# RUNNING SCRIPT TO GET GOLDEN GATE INFORMATION #
##########################################################################
$OGG_HOME/ggsci << EOF > ${LOGDIR}/ggs_objects_check_${OPERATION}.tmp
info all
exit
EOF

##################################################################################
## EXTRACT DATA ABOUT THE GOLDENGATE OBJECTS ONLY ##
##################################################################################

### If NQ Exadata, do not check the CDC Extract because it is not used, else check it
if [[ $(uname -a | awk '{print $2}' | egrep -i 'sphq|ldsfocnq2') ]]
then
    egrep '(EXTRACT|REPLICAT|MANAGER|JAGENT|PMSRVR)' ${LOGDIR}/ggs_objects_check_${OPERATION}.tmp | egrep -v 'Version|ECDCCCB1|RCDCCCB1|RCDCEVT1' | tr ":" " "| tr -s '[:space:]'|cut -d" " -f1-9 > ${LOGDIR}/ggs_objects_${OPERATION}.tmp
else
    egrep '(EXTRACT|REPLICAT|MANAGER|JAGENT|PMSRVR)' ${LOGDIR}/ggs_objects_check_${OPERATION}.tmp | grep -v Version | tr ":" " "| tr -s '[:space:]'|cut -d" " -f1-9 > ${LOGDIR}/ggs_objects_${OPERATION}.tmp
fi

}

checkGoldenGateUpDown() {

##########################################################################
## CHECKING FOR ABENDED PROCESS ##
##########################################################################

awk -v opath="${LOGDIR}" '{if ( $2 == "ABENDED" ) {print $1 " " $3 " HAS ABENDED -- at -- " d "\n"} else {print "NO ABENDS FOR " $1 " " $3 " " d > opath"/ggs_objects_not_abended.log" }}' d="$(date)" ${LOGDIR}/ggs_objects_${OPERATION}.tmp > ${LOGDIR}/ggs_objects_abended.log

##########################################################################
## CHECKING FOR STOPPED PROCESS ##
##########################################################################

awk -v opath="${LOGDIR}" '{if ( $2 == "STOPPED" ) {print $1 " " $3 " IS STOPPED -- at -- " d "\n"} else {print $1 " "  $3 " IS NOT STOPPED " d > opath"/ggs_objects_not_stopped.log" }}' d="$(date)" ${LOGDIR}/ggs_objects_${OPERATION}.tmp > ${LOGDIR}/ggs_objects_stopped.log

if [ -s ${LOGDIR}/ggs_objects_abended.log ]
then
        cat ${LOGDIR}/ggs_objects_abended.log >> ${EMAILFile}
fi

if [ -s ${LOGDIR}/ggs_objects_stopped.log ]
then
        cat ${LOGDIR}/ggs_objects_stopped.log >> ${EMAILFile}
fi

}

checkPreviousLag() {
##########################################################################
## CHECKING IF THERE WAS PREVIOUS LAG IN THE CASE OF PERIODIC ALERTS
##########################################################################
GGSCI_LAG_CHECK=0
GGSCI_CHECKPOINT_LAG_CHECK=0

if [ -s ${LOGDIR}/ggs_objects_lag.log ]
then
        echo "GGSCI_LAG_CHECK|$(date)" >> ${LOGDIR}/ggs_objects_previous_lag.log
        GGSCI_LAG_CHECK=$(grep GGSCI_LAG_CHECK ${LOGDIR}/ggs_objects_previous_lag.log | wc -l)

        if [ ${GGSCI_LAG_CHECK} -ge 2 ]
        then
                mv ${LOGDIR}/ggs_objects_previous_lag.log ${LOGDIR}/ggs_objects_previous_lag.log.${TIMESTAMP}
        fi
fi

if [ -s ${LOGDIR}/ggs_objects_checkpoint_lag.log ]
then
        echo "GGSCI_CHECKPOINT_LAG_CHECK|$(date)" >> ${LOGDIR}/ggs_objects_previous_checkpoint_lag.log
        GGSCI_CHECKPOINT_LAG_CHECK=$(grep GGSCI_CHECKPOINT_LAG_CHECK ${LOGDIR}/ggs_objects_previous_checkpoint_lag.log | wc -l)

        if [ ${GGSCI_CHECKPOINT_LAG_CHECK} -ge 2 ]
        then
                mv ${LOGDIR}/ggs_objects_previous_checkpoint_lag.log ${LOGDIR}/ggs_objects_previous_checkpoint_lag.log.${TIMESTAMP}
        fi
fi
}

checkGoldenGateLag() {
##########################################################################
## CHECKING FOR LAG OF MORE THEN 30 ##
## AND CHECKPOINT LAG OF MORE THAN 15 ##
##########################################################################

awk -v opath="${LOGDIR}" -v lag_hours="${LAG_HOURS}" -v lag_mins="${LAG_MINS}" '{if ( $4 > lag_hours || $5 >= lag_mins ) {print $1 " " $3 " HAS LAG of " $4" hour " $5 " min -- at -- " d } else {print "NO LAG FOR " $3 " " d > opath"/ggs_objects_no_lag.log" }}' d="$(date)" ${LOGDIR}/ggs_objects_${OPERATION}.tmp > ${LOGDIR}/ggs_objects_lag.log

awk -v opath="${LOGDIR}" -v lag_checkpoint_hours="${LAG_CHECKPOINT_HOURS}" -v lag_checkpoint_mins="${LAG_CHECKPOINT_MINS}" '{if ( $7 >= lag_checkpoint_hours && $8 >= lag_checkpoint_mins ) {print $1 " " $3 " HAS CHECKPOINT LAG of " $7" hour " $8 " min -- at -- " d "\n"} else {print "NO CHECKPOINT LAG FOR " $3 " " d > opath"/ggs_objects_no_checkpoint_lag.log" }}' d="$(date)" ${LOGDIR}/ggs_objects_${OPERATION}.tmp > ${LOGDIR}/ggs_objects_checkpoint_lag.log


## Determine if there has been previous lag
        checkPreviousLag

if [[ -s ${LOGDIR}/ggs_objects_lag.log && ${GGSCI_LAG_CHECK} -ge 2 ]]
then
        cat ${LOGDIR}/ggs_objects_lag.log >> ${EMAILFile}
fi

if [[ -s ${LOGDIR}/ggs_objects_checkpoint_lag.log && ${GGSCI_CHECKPOINT_LAG_CHECK} -ge 2 ]]
then
        cat ${LOGDIR}/ggs_objects_checkpoint_lag.log >> ${EMAILFile}
fi

#### Clean up previous lag files if present and the previous check vars are set to 0 ####
#### Handles the situation where a lag was present below the threshold and then no lag was present on next run ####

if [[ -s ${LOGDIR}/ggs_objects_previous_lag.log && ${GGSCI_LAG_CHECK} -eq 0 ]]
then
                rm ${LOGDIR}/ggs_objects_previous_lag.log
fi

if [[ -s ${LOGDIR}/ggs_objects_previous_checkpoint_lag.log && ${GGSCI_CHECKPOINT_LAG_CHECK} -eq 0 ]]
then
                rm ${LOGDIR}/ggs_objects_previous_checkpoint_lag.log
fi

}

sendGoldenGateStatus() {
##########################################################
## SENDING EMAIL IF ERRORS ARE IN LOGFILE ###
##########################################################

if [ -s $EMAILFile ]
then
        echo $(date) "-- SCRIPT OPERATION ${OPERATION} -- FOUND PROBLEM AND REACHED THRESHOLD IN ${OGG_HOME} -- Sending Email" >> $LOGDIR/ggsci-status-daemon_${DATE}.log
        cat $EMAILFile | mailx -s "GGSCI-STATUS-DAEMON DETECTED ${OPERATION} PROBLEM IN ${OGG_HOME} ON: $HOST" $EMAILRECEPIENTS
else
        if [[ ((${GGSCI_LAG_CHECK} -gt 0 && ${GGSCI_LAG_CHECK} -lt 2) || (${GGSCI_CHECKPOINT_LAG_CHECK} -gt 0 && ${GGSCI_CHECKPOINT_LAG_CHECK} -lt 2)) ]]
        then
                echo `date` "-- SCRIPT OPERATION ${OPERATION} -- FOUND PROBLEM IN ${OGG_HOME} - EMAIL THRESHOLD NOT REACHED" >> $LOGDIR/ggsci-status-daemon_${DATE}.log
                if [[ -s ${LOGDIR}/ggs_objects_lag.log ]]
                then
                   while read lag
                   do
                      echo ${lag} >> $LOGDIR/ggsci-status-daemon_${DATE}.log
                   done < ${LOGDIR}/ggs_objects_lag.log
                fi

                if [[ -s ${LOGDIR}/ggs_objects_checkpoint_lag.log ]]
                then
                   while read lag
                   do
                      echo ${lag} >> $LOGDIR/ggsci-status-daemon_${DATE}.log
                   done < ${LOGDIR}/ggs_objects_checkpoint_lag.log
                fi
        else
                echo `date` "-- SCRIPT OPERATION ${OPERATION} -- NO ERRORS FOUND" >> $LOGDIR/ggsci-status-daemon_${DATE}.log
        fi
fi
}

cleanupFiles(){
##########################################################
## TEMPORARY FILE CLEANUP ##
##########################################################

if [ -e "${EMAILFile}" ]
then
    mv ${EMAILFile} ${EMAILFile}.${TIMESTAMP}
fi

find ${LOGDIR} -type f -name "ggsci-status-daemon_*.log" -mtime +7 -delete 2>&1
find ${LOGDIR} -type f -name "ggs_email_${OPERATION}.log.*" -mtime +2 -delete 2>&1
find ${LOGDIR} -type f -name "ggs_objects_previous_lag.log.*" -mtime +2 -delete 2>&1
find ${LOGDIR} -type f -name "ggs_objects_previous_checkpoint_lag.log.*" -mtime +2 -delete 2>&1

}

##########################################################
## MAINLINE LOGIC ##
##########################################################
## Setup environment variables

while getopts "o:e:" opt
do
   case "$opt" in
      o ) OPERATION="$OPTARG" ;;
      e ) ENVIRONMENT="$OPTARG" ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# Print helpFunction in case parameters are empty
if [ -z "$OPERATION" ] || [ -z "$ENVIRONMENT" ]
then
   echo "Some or all of the parameters are empty";
   helpFunction
fi

SCRIPT_HOME=$(dirname $0)
LOGDIR=${SCRIPT_HOME}/log
HOST=$(uname -a | awk '{print $2}')
EMAILRECEPIENTS="shane@gluent.com shane.borden@deancare.com"
DATE=$(date '+%m%d%Y')
TIMESTAMP=$(date '+%m%d%Y%H%M%S')
LAG_HOURS=00
LAG_MINS=30
LAG_CHECKPOINT_HOURS=00
LAG_CHECKPOINT_MINS=15

### Check that necessary directories and files exist
if [ ! -d ${LOGDIR} ]; then
    mkdir -p ${LOGDIR}
fi

if [[ -e ${ENVIRONMENT} ]]; then
    . ${ENVIRONMENT} 2>&1 > ${LOGDIR}/ggs_environment.out
else
   echo "Environment File not valid.  Exiting!"
   exit 1
fi

## Begin Mainline Processing

if [[ ${OPERATION} = "UPDOWN" ]]
then

        EMAILFile=${LOGDIR}/ggs_email_${OPERATION}.log

        ## Clean up temp files in case they exist when script starts
        cleanupFiles

        ## Retrieve info all from ggsci
        chkGoldenGate

        ## Parse results from ggsci
        checkGoldenGateUpDown

        ## Email status if necessary
        sendGoldenGateStatus

elif [[ ${OPERATION} = "LAG" ]]
then

        EMAILFile=${LOGDIR}/ggs_email_${OPERATION}.log

        ## Clean up temp files in case they exist when script starts
        cleanupFiles

        ## Retrieve info all from ggsci
        chkGoldenGate

        ## Parse results from ggsci
        checkGoldenGateLag

        ## Email status if necessary
        sendGoldenGateStatus

else
        echo "Must provide a valid parameter of 'UPDOWN' or 'LAG'"
fi

################# SCRIPT END ######################
