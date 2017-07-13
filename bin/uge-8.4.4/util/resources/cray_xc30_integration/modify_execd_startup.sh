#!/bin/sh
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

# replace sh to bash -l

sed -i -e 's@^#!/bin/sh@#!/bin/bash -l@g' "$1"
sed -i -e 's@$bin_dir/sge_execd@module load job\n      $bin_dir/sge_execd@g' "$1"

