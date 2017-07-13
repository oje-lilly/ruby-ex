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
source $SGE_ROOT/$SGE_CELL/common/settings.sh

# Get the job id and task id out of the parameters to this script
export JOB_ID=$1
export SGE_TASK_ID=$2

shift
shift

# get the local hostname
hostname=`$SGE_ROOT/utilbin/lx-amd64/gethostname -name`

# amount of instances started is always 1 since
# mpirun starts it up 

$SGE_ROOT/bin/lx-amd64/qrsh -V -inherit $hostname $@

