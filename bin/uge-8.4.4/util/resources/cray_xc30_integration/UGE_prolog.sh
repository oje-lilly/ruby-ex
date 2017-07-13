#!/bin/bash
#############################################################################
#
#  This code is the Property, a Trade Secret and the Confidential Information
#  of Univa Corporation.
#
#  Copyright Univa Corporation. All Rights Reserved. Access is Restricted.
#
#  It is provided to you under the terms of the
#  Univa Term Software License Agreement.
#
#  If you have any questions, please contact our Support Department.
#
#  www.univa.com
#
###########################################################################

MACHINE_NAME=$1
if [ -n "$MACHINE_NAME" ]; then
   postfix="_${MACHINE_NAME}"
else
   postfix=""
fi

# compose the names of our machine specific environment variables
env_var_cray_nodes="SGE_HGR_cray_nodes${postfix}"
env_var_mppnppn="SGE_HGR_mppnppn${postfix}"
env_var_mppwidth="SGE_HGR_mppwidth${postfix}"
env_var_mppdepth="SGE_HGR_mppdepth${postfix}"

# print general information for better debugging at the beginning
echo "Cray Prolog Begin"
echo "Task id: $SGE_TASK_ID"
echo "Job id: $JOB_ID"
echo "Requested amount of Cray XC30 nodes: ${!env_var_cray_nodes}"
# PROLOG and EPILOG needs to run as root
echo "Running prolog as user: `whoami`"

# Set the path to ALPS/BASIL and libjob.so (LD_LIBRARY_PATH).
source "$SGE_ROOT/util/resources/cray_xc30_integration/cray_settings.sh"
# Settings needed by CrayBasil.py script.
source "$SGE_ROOT/$SGE_CELL/common/settings.sh"

export SGE_BINARY_PATH="$SGE_ROOT/bin/lx-amd64"

if [ "${!env_var_cray_nodes}" == "" ]; then
   echo "No Cray Reservation is done. Job did not request Cray resources."
   exit 0
fi

# Check if job container was created by shepherd (PAGG)
if [ "$PAGG" == "" -o "$PAGG" == "-1" ]; then
   echo "Error. PAGG was not created or is -1. Please ensure" >&2
   echo "that UGE_prolog.sh is started as root and that the" >&2
   echo "CRAY_XC30_LOGIN_NODE=1 parameter is set in execd_params" >&2
   echo "of all login nodes (qconf -mconf <nodename>)." >&2
   # put queue in error state
   exit 1
fi

if [ "${!env_var_mppnppn}" == "" ]; then
   mppnppn=0
else
   mppnppn=${!env_var_mppnppn}
fi

# Create the reservation based on job parameters.
job_parameters="${!env_var_cray_nodes},${!env_var_mppwidth},${!env_var_mppdepth},$mppnppn"
echo "Job layout specification (nodes, width, depth, nppn): $job_parameters"
reservationId=`"$SGE_ROOT/util/resources/cray_xc30_integration/CrayBasil.py" \
               --reserveNodes="$job_parameters"`

# Check if reservation request was successful.
if [ $? -ne 0 ]; then
   # put job in error state
   return_code=100
   # do a new inventory call - maybe the admin changed some nodes (batch/interactive)
   new_nodes=`"$SGE_ROOT/util/resources/cray_xc30_integration/CrayBasil.py" --nodes`
   if [ $? -ne 0 ]; then
      # Error -> possibly no valid architecture (please check with xtprocadmin)
      qconf -mattr exechost complex_values "cray_nodes${postfix}=0" global
      # no free nodes - reschedule
      exit 99
   fi
   # get the amount of compute nodes (batch/up)
   new_nodes=`echo "$new_nodes" | cut -d',' -f1`

   # When the amount of online nodes are != than configured as cray_nodes then
   # reconfigure the amount.
   configured_nodes=`qconf -se global | grep "cray_nodes${postfix}" | head -n1 | \
                     awk -F"cray_nodes${postfix}=" '{print $2}' | cut -d',' -f1`

   if [ "$new_nodes" != "$configured_nodes" ]; then
      # something changed in the cluster: reconfigure and reschedule job
      qconf -mattr exechost complex_values "cray_nodes${postfix}=$new_nodes" global
      echo "Cray configuration changed. Reschedule job."
      exit 99
   fi

   echo "Could not reserve ${!env_var_cray_nodes}!" >&2
   echo "Trying to reserve again in verbose mode."
   errorReason=`"$SGE_ROOT/util/resources/cray_xc30_integration/CrayBasil.py" --verbose \
                --reserveNodes="$job_parameters"`
   if [ $? -eq 0 ]; then
      echo "Unknown condition. Reservation request worked when executing a second time." >&2
      echo "Continuing with job start up." >&2
      reservationId=`echo "$errorReason" | awk 'END {print $NF}'`
   else
      # print error reason for debugging
      echo "$errorReason" >&2
      # put job in error state or reschedule
      echo "No success."
      # check if there are orphaned reservations (then the system
      # needs to be cleared and be resynchronized)
      out=`"$SGE_ROOT/util/resources/cray_xc30_integration/CrayBasil.py" --orphanedReservations`
      ret=$?
      if [ "$ret" = "15" ]; then
         echo "No orphaned reservation detected putting job in error state."
         exit $return_code
      fi
      if [ "$ret" = "0" ]; then
         echo "Orphaned reservations found! Putting queue in error state."
         exit 10
      fi
      echo "Error when executing CrayBasil.py --orphanedReservations"
      echo "$out"
      exit $return_code
   fi
fi

echo "BASIL reservation id: $reservationId"

# set BASIL reservation ID in job context
if [ "$SGE_TASK_ID" == "undefined" ]; then
   "$SGE_ROOT/bin/lx-amd64/qalter" -ac "reservation_1=$reservationId" "$JOB_ID"
else
   "$SGE_ROOT/bin/lx-amd64/qalter" -ac "reservation_$SGE_TASK_ID=$reservationId" "$JOB_ID"
fi

echo "Confirm reservation."
ret=`"$SGE_ROOT/util/resources/cray_xc30_integration/CrayBasil.py" --confirmRes=auto --adminCookie="$PAGG"`
retcode=$?
echo "returns $ret and code $retcode"
if [ $retcode -ne 0 ]; then
   echo "Reservation confirmation for reservation $reservationId failed ($retcode / $ret)" >&2
   echo "Cancel reservation $reservationId" >&2
   "$SGE_ROOT/util/resources/cray_xc30_integration/CrayBasil.py" --cancelRes=auto
   # Loop until reservation cancelation gives an error, then
   # the reservation is away meaning that free nodes are alligned
   # with Grid Engine setting.
   while [ $? -eq 0 ]; do
      sleep 1
      "$SGE_ROOT/util/resources/cray_xc30_integration/CrayBasil.py" --cancelRes=auto
   done
   # put job in error state
   echo "Do not start job."
   exit 2
else
   echo "Reservation confirmation was successful ($retcode / $ret)."
fi
echo "Cray Prolog End"
exit 0

