#!/bin/sh

#___INFO__MARK_BEGIN__
##############################################################################
#
#  The contents of this file are made available subject to the terms of the
#  Apache Software License 2.0 ('The License').
#  You may not use this file except in compliance with The License.
#  You may obtain a copy of The License at
#  http://www.apache.org/licenses/LICENSE-2.0.html
#
#  Copyright (c) 2011 Univa Corporation.
#
##############################################################################
#___INFO__MARK_END__

# This script is used in the context of a SGE cluster to start the lodial 
# application of a LO installation. This script is not allowed to print 
# messages to stdout because the stdin and stdout streams are used for 
# communication. 

root=""
cluster_name=""
qmaster_port=""

# Check if $LO_ROOT was passed as first argument 
if [ "$1" = "" -o ! -d "$1" ]; then
   echo "Path of the LO installation needs to be passed as first argument" 1>&2
   exit 1
else
   root=$1
fi

# Check if $SGE_ROOT is set
if [ -z "$SGE_ROOT" ]; then
   echo "SGE_ROOT is not set" 1>&2
   exit 1
fi

# Check if $SGE_CELL is set
if [ -z "$SGE_CELL" ]; then
   echo "SGE_CELL is not set" 1>&2
   exit 1
fi

# Source the setting of the SGE cluster
. $SGE_ROOT/$SGE_CELL/common/settings.sh 1>&2

# In the context of SGE cluster there is a cluster name available
# that we will pass to lodial. This string is used as part of the
# event client name and is need for the registration at LO. 
if [ -z "$SGE_CLUSTER_NAME" ]; then
   echo "SGE_CLUSTER_NAME is not set" 1>&2
   exit 1
else
   cluster_name=$SGE_CLUSTER_NAME
fi

# The qmaster port variable needs also to be specified because it is 
# needed for the registration. Try to read it from the environment
# or service configuration (NIS+, NIS or /etc/services).
if [ -z "$SGE_QMASTER_PORT" ]; then
   sge_arch=`$SGE_ROOT/util/arch`
   qmaster_port=`$SGE_ROOT/utilbin/$sge_arch/getservbyname -number sge_qmaster`
   if [ $? -eq 1 ]; then
      echo "Neither SGE_QMASTER_PORT environment variable nor sge_qmaster service port is defined" 1>&2
      exit 1
   fi
else
   qmaster_port=$SGE_QMASTER_PORT
fi

# Unset all variables that are set in the SGE cluster context
unset SGE_ROOT SGE_QMASTER_PORT SGE_EXECD_PORT SGE_CLUSTER_NAME \
      SGE_CELL SGE_ARCH SGE_DEBUG_LEVEL

# Source the setting of the LO cluster
. $root/default/common/settings.sh 1>&2

# Find the arch string in the LO cluster
ARCH=`$LO_ROOT/util/arch`

# Exec the lodial application
exec $LO_ROOT/bin/$ARCH/lodial -log log_info -name $cluster_name -qmasterport $qmaster_port
