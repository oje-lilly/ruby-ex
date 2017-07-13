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

host=$1
echo "Reschedule jobs on host $host"
for jobid in `qhost -h $1 -j | tail --lines=+7 | awk '{print $1"."$10}'`; do
   lastchar=`echo -n $jobid | tail -c -1`
   if [ "$lastchar" == "." ]; then
      jobid=${jobid}1
   fi
   qmod -f -rj $jobid
done

