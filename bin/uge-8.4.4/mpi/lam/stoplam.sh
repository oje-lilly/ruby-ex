#!/bin/sh
#
#
#___INFO__MARK_BEGIN__
##########################################################################
#
#  The Contents of this file are made available subject to the terms of
#  the Sun Industry Standards Source License Version 1.2
#
#  Sun Microsystems Inc., March, 2001
#
#
#  Sun Industry Standards Source License Version 1.2
#  =================================================
#  The contents of this file are subject to the Sun Industry Standards
#  Source License Version 1.2 (the "License"); You may not use this file
#  except in compliance with the License. You may obtain a copy of the
#  License at http://gridengine.sunsource.net/Gridengine_SISSL_license.html
#
#  Software provided under this License is provided on an "AS IS" basis,
#  WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING,
#  WITHOUT LIMITATION, WARRANTIES THAT THE SOFTWARE IS FREE OF DEFECTS,
#  MERCHANTABLE, FIT FOR A PARTICULAR PURPOSE, OR NON-INFRINGING.
#  See the License for the specific provisions governing your rights and
#  obligations concerning the Software.
#
#  The Initial Developer of the Original Code is: Sun Microsystems, Inc.
#
#  Copyright: 2001 by Sun Microsystems, Inc.
#
#  All Rights Reserved.
#
#  Portions of this software are Copyright (c) 2011 Univa Corporation
#
##########################################################################
#___INFO__MARK_END__

#
# shutdown of LAM MPI conforming with the Grid Engine
# Parallel Environment interface
#
# Just remove machine-file that was written by startmpi.sh
#
rm $TMPDIR/machines

# test number of args
if [ $# -ne 1 ]; then
   echo "$me: got wrong number of arguments" >&2
   exit 1
fi

# get arguments
lam_dir=$1

rshcmd=rsh
case "$ARC" in
   hp*) rshcmd=remsh ;;
   *) ;;
esac
rm $TMPDIR/$rshcmd

#
# lamhalt, make sure we use the correct LAM installation
#
PATH=$lam_dir/bin:$PATH
export PATH
lamhalt

exit 0
