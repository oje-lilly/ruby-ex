#!/bin/sh
#___INFO__MARK_BEGIN__
###########################################################################
#
#  The contents of this file are made available subject to the terms of the
#  Apache Software License 2.0 ('The License').
#  You may not use this file except in compliance with The License.
#  You may obtain a copy of The License at
#  http://www.apache.org/licenses/LICENSE-2.0.html
#
#  Copyright (c) 2012 Univa Corporation.
#
###########################################################################
#___INFO__MARK_END__

# This wrapper script for qhost adds the "-cb" from 6.2u5 to UGE qhost

# Default to not showing core binding
NCB="1"

# Initialize counter and copy positional arguments
i=0
ARGS=( "$@" )

# Loop through arguments tracking the last ncb/cb option and unsetting it
while [ $# -gt 0 ]
do
   case $1 in
     -cb)
        NCB="0"
        unset ARGS[$i]
        ;;
     -ncb)
        NCB="1"
        unset ARGS[$i]
        ;;
   esac
   #  Pop the current argument
   shift
   i=`expr $i + 1`
done

# Reset the postional arguments with our adjusted parameters
set -- "${ARGS[@]}"

#echo "New parameters $@"

if [ "$NCB" = "1" ]; then
exec qhost -ncb "$@"
else
exec qhost "$@"
fi

