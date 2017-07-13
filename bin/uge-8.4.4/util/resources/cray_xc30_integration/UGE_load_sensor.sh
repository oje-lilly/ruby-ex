#!/bin/sh
#___INFO__MARK_BEGIN__
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
#___INFO__MARK_END__

# Set the path to ALPS/BASIL and libjob.so (LD_LIBRARY_PATH).
. "$SGE_ROOT/util/resources/cray_xc30_integration/cray_settings.sh"
# Settings needed by CrayBasil.py script.
. "$SGE_ROOT/$SGE_CELL/common/settings.sh"

# the load sensor always runs on a Cray login node
export SGE_BINARY_PATH=$SGE_ROOT/bin/lx-amd64

# get the machine name of the machine this login node is part of
# the name was added to the local configuration of this login node by the install script
hostname=`hostname`
output=`qconf -sconf "$hostname"`
if [ $? -eq 0 ]; then
   line=`echo "$output" | grep "^cray_machine_name"`
   if [ $? -eq 0 ]; then
      MACHINE_NAME=`echo "$line" | awk '{print $2}'`
   fi
fi

if [ -n "$MACHINE_NAME" ]; then
   postfix="_${MACHINE_NAME}"
else
   postfix=""
fi

# This load sensor is just used for doing regular checks if
# amount of Cray compute nodes (online batch nodes) aligns
# with the UGE configuration. Those checks could also be
# triggered from other locations (like cron jobs) if required.

# If the slots value (like in qstat -g c) should appear more
# closer to the real value of compute nodes, queue slots 
# adaption can be turned on here. Note:
# - This should *not* be turned on when running jobs on
#   login nodes without running on the Cray compute nodes
#   (this is an explicit feature we support).
# - The amount of total slots in the queue is the sum of
#   all slots in the queue instances. Hence when having
#   multiple login nodes the total number of slots is a
#   fraction of available compute nodes.
configure_slots="false"

# a reservation issue occurs when orphaned reservations are
# detected - this state needs to be saved accross load report
# intervals so that when it is fully resolved (no orphaned
# reservation anymore) the Error state is removed. The Error
# state is set from Cray prolog scripts to prevent that more
# jobs are scheduled which finally can't be started.
reservationIssue="false"
end=false
while [ $end = false ]; do
   read input
   result=$?
   if [ $result -ne 0 ]; then
      end=true
      break
   fi
   if [ "$input" = "quit" ]; then
      end=true
      break
   fi

   # don't send anything just update cray_nodes if required
   echo "begin"

   # Check for orphaned reservations
   orphaned_reservations=`"$SGE_ROOT/util/resources/cray_xc30_integration/CrayBasil.py" \
                          --orphanedReservations`
   
   if [ "$?" = "0" ]; then
      # check if we have orphaned nodes
      reservationIssue="true"
      for resid in $orphaned_reservations; do
         if [ "$resid" = "" ]; then
            continue
         fi
         # Cancel reservation until it is away. We consider a 15 second timeout
         # to make progress on other reservations. In an error case the queue
         # is set from the job prolog to an error state, so no further jobs are
         # scheduled.
         retries=0
         exitStatus=0
         while [ $exitStatus -eq 0 -a $retries -le 15 ]; do
            # when those event should be reported they could be attached
            # here to a custom logfile
            echo "Cancel orphaned reservation $resid" >> /tmp/load_sensor.$$
            "$SGE_ROOT/util/resources/cray_xc30_integration/CrayBasil.py" --cancelRes="$resid" \
                                                                              > /dev/null 2>&1
            exitStatus=$?
            retries=`expr "$retries" + 1`
            sleep 1
         done
      done
   fi

   # if we had an orphaned reservation issue which is now resolved
   # we remove the error state
   if [ "$reservationIssue" = "true" ]; then
      orphaned_reservations=`"$SGE_ROOT/util/resources/cray_xc30_integration/CrayBasil.py" \
                             --orphanedReservations`
      if [ "$?" = "15" ]; then
         # no orphaned reservation: remove error state of the login node queue instances
         qmod -cq cray${postfix}.q > /dev/null 2>&1
         reservationIssue="false"
      fi
   fi

   # Do a new inventory call - maybe the admin changed some nodes (batch/interactive)
   new_nodes=`"$SGE_ROOT/util/resources/cray_xc30_integration/CrayBasil.py" --nodes`
   if [ $? -ne 0 ]; then
      # Error -> possibly no valid architecture (please check with xtprocadmin)
      qconf -mattr exechost complex_values "cray_nodes${postfix}=0" global > /dev/null 2>&1
      echo "end"
      continue
   fi
   new_nodes=`echo "$new_nodes" | cut -d',' -f1`
   # When the amount of online nodes are != than configured as cray_nodes then
   # reconfigure the amount.
   configured_nodes=`qconf -se global | grep "cray_nodes${postfix}" | head -n1 | \
                     awk -F"cray_nodes${postfix}=" '{print $2}' | cut -d',' -f1`
   if [ "$new_nodes" != "$configured_nodes" ]; then
      # something changed in the cluster: reconfigure and reschedule job
      qconf -mattr exechost complex_values "cray_nodes${postfix}=$new_nodes" global > /dev/null 2>&1
      if [ "$configure_slots" = "true" ]; then
         qconf -mattr queue slots "$new_nodes" "cray${postfix}.q" > /dev/null 2>&1
      fi
   fi

   echo "end"
done
