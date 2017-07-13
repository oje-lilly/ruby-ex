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
echo "Cray Epilog Begin"

# The environment is needed by CrayBasil.py script.
source "$SGE_ROOT/$SGE_CELL/common/settings.sh"

# Set the path to ALPS/BASIL.
source "$SGE_ROOT/util/resources/cray_xc30_integration/cray_settings.sh"

# Cancel reservation until it is really away. Otherwise nodes are
# reported as free (consumable!) in Grid Engine but not free on
# the Cray system.
exitStatus=0
while [ $exitStatus -eq 0 ]; do
   output=$("$SGE_ROOT/util/resources/cray_xc30_integration/CrayBasil.py" --cancelRes=auto)
   exitStatus=$?
   echo "$output" >&2
   sleep 1
done

# Forward accounting information from RUR to Grid Engine accounting.
# It is expected the the "user" RUR outputplugin is enabled with
# "jobid" argument. That means that in the user home directory a
# file "rur.<ugejobid>" or "rur.<jobid>.<taskid>" is generated, which
# contains the information needed.
rur_file_location=""
if [ "$SGE_TASK_ID" == "undefined" ]; then
   rur_file_location=$SGE_O_HOME/rur.$JOB_ID
else
   rur_file_location=$SGE_O_HOME/rur.$JOB_ID.$SGE_TASK_ID
fi

accounting=$("$SGE_ROOT/util/resources/cray_xc30_integration/CrayBasil.py" --rur="$rur_file_location")
if [ $? != 0 ]; then
   echo "Error while reading out RUR file for job. ($accounting)" >&2
else
   utime=$(echo "$accounting" | awk '{print $1}')
   stime=$(echo "$accounting" | awk '{print $2}')
   maxrss=$(echo "$accounting" | awk '{print $3}')
   inblock=$(echo "$accounting" | awk '{print $4}')
   outblock=$(echo "$accounting" | awk '{print $5}')

   # Hint: RUR output file could be deleted here
   # Replace ru_maxrss ru_utime ru_stime ru_inblock ru_outblock by aprun
   # values (ru_utime + ru_stime will change cpu time in qacct).
   sed -i 's/^ru_utime.*/ru_utime='"$utime"'/' "$SGE_JOB_SPOOL_DIR/usage"
   sed -i 's/^ru_stime.*/ru_stime='"$stime"'/' "$SGE_JOB_SPOOL_DIR/usage"
   sed -i 's/^ru_maxrss.*/ru_maxrss='"$maxrss"'/' "$SGE_JOB_SPOOL_DIR/usage"
   sed -i 's/^ru_inblock.*/ru_inblock='"$inblock"'/' "$SGE_JOB_SPOOL_DIR/usage"
   sed -i 's/^ru_oublock.*/ru_oublock='"$outblock"'/' "$SGE_JOB_SPOOL_DIR/usage"
fi

# Remove BASIL reservation ID from job context. This is needed
# to keep the job context as small as possible when large array
# jobs are submitted.
if [ "$SGE_TASK_ID" == "undefined" ]; then
   "$SGE_ROOT/bin/lx-amd64/qalter" -dc "reservation_1" "$JOB_ID"
else
   "$SGE_ROOT/bin/lx-amd64/qalter" -dc "reservation_$SGE_TASK_ID" "$JOB_ID"
fi

echo "Cray Epilog End"
