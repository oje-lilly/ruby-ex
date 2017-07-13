#!/bin/sh
#
# logchecker.sh
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
##########################################################################
#___INFO__MARK_END__
#
# This is a template script for moving, deleting, compressing Grid Engine
# "messages" files, the "accounting" and the "reporting" file
#
# Do not edit this file directly. Copy it e.g. to your
#
#    $SGE_ROOT/default/common
#
# directory. This will make sure that new releases or patches of Sun Grid
# Engine don't override your local changes.
#
#
# After customization this script can be installed as a cron job. If your
# Sun Grid Engine system is running under an admin_user id, make sure to run
# it as the proper user.
#
# Please read the file 
#
#    $SGE_ROOT/doc/logfile-trimming.asc
#
# for more information about this script
#

PATH=/bin:/usr/bin

#---------------------------------------------------------------------------
# begin section that needs to be customized
#

# UNCONFIGURED=yes|no    if set to "no" really do action
#                        otherwise just print what would be done  
UNCONFIGURED=yes


# ECHO=:|echo            be verbose or not, the ":" (colon) is the
#                        null shell command
#
ECHO=echo


# SGE_ROOT=<path to your SGE_ROOT directory>
#
SGE_ROOT=undefined


# SGE_CELL - name of your cell, usually "default"
#          - your "common" directory is always $SGE_ROOT/$SGE_CELL/common
#
SGE_CELL=default


# EXECD_SPOOL - name of the execd spooling directory
#             - it can be a global set at: qconf -sconf -> execd_spool_dir
#               or a local (execd specific): qconf -sconf <execd hostname> -> execd_spool_dir
#             - "none" does nothing, specifying a spool_dir, the execd messages 
#               files are also rotated
EXECD_SPOOL=none


# ACTION_ON=1|2|3|4
#      1 = work on qmaster and scheduler "messages" files only
#      2 = work on "messages" file on current host only
#      3 = work on all accessible execd "messages" files of global config
#      4 = work on qmaster "messages" and all accessible execd "messages" files
#
ACTION_ON=4


# ACTIONSIZE=<size_inkilobyte> rotate/delete only if file size exceeds given
#                             arg. If ACTIONSIZE=0 always work
#
ACTIONSIZE=0


# KEEPOLD=<number>  number of old "messages" files to keep
#                   30 means that extension 0-29 are saved
#                   <= 0 means that "messages" file is deleted, no backup
#                   the most recent messages file has extension ".0"
#
KEEPOLD=30


# GZIP=yes|no compress rotated "messages.0" file
#
GZIP=yes


#ACCT=yes|no        yes = rotate accounting file when rotating qmaster
#                         messages file as well
#                   no  = don't rotate accounting file
#
ACCT=no

#REPO=yes|no        yes = rotate reporting file when rotating qmaster
#                         messages file as well
#                   no  = don't rotate reporting file
#
REPO=no
#
#
# end section that needs to be customized
#---------------------------------------------------------------------------


#---------------------------------------------------------------------------
# execute or just echo given command line
#
Execute()
{
   if [ "$UNCONFIGURED" != no ]; then
      echo Not executing: $*
   else
      $*
   fi
}

#---------------------------------------------------------------------------
# sge_logcheck
#
sge_logcheck()
{
   if [ $1 = 1 ]; then
      msgfile=$2/messages
   else
      msgfile=$2
   fi

   if [ ! -f $msgfile ]; then
      $ECHO "file \"$msgfile\" doesn't exist"
      return
   fi
   
   if [ $ACTIONSIZE -gt 0 ]; then
      msgsize=`du -k $msgfile | cut -f1`
      if [ $msgsize -lt $ACTIONSIZE ]; then
         $ECHO "file \"$msgfile\" doesn't exceed size ${ACTIONSIZE}kb"
         return
      fi
   fi

   if [ $GZIP = yes ]; then
      ext=.gz
   else
      ext=""
   fi

   if [ $KEEPOLD -gt 0 ]; then
      keeptop=`expr $KEEPOLD - 1`
      keepcurr=`expr $keeptop - 1`
      while [ $keepcurr -ge 0 ]; do
         if [ -f $msgfile.${keepcurr}${ext} ]; then
            $ECHO "moving $msgfile.${keepcurr}${ext} --> $msgfile.${keeptop}${ext}"
            Execute mv -f $msgfile.${keepcurr}${ext} $msgfile.${keeptop}${ext}
         fi
         keeptop=$keepcurr
         keepcurr=`expr $keeptop - 1`
      done
      Execute mv -f $msgfile $msgfile.0
      if [ $GZIP = yes ]; then
         $ECHO "compressing $msgfile.0"
         Execute gzip $msgfile.0
      fi
   else
      $ECHO "deleting $msgfile"
      Execute rm -f $msgfile      
   fi
}

#---------------------------------------------------------------------------
# MAIN-MAIN-MAIN-MAIN-MAIN-MAIN-MAIN-MAIN-MAIN-MAIN-MAIN-MAIN-MAIN-MAIN-MAIN
#---------------------------------------------------------------------------


ARGC=$#
while [ $ARGC != 0 ]; do
   case $1 in
   -action_on)
      if [ $ARGC -lt 2 ]; then
         echo "Error: \"-action_on\" needs argument" >&2
         exit 1
      fi
      ACTION_ON=$2
      ;;
   -execd_spool)
      if [ $ARGC -lt 2 ]; then
         echo "Error: \"-execd_spool\" needs argument" >&2
         exit 1
      fi
      EXECD_SPOOL=$2
      ;;
   -h|-help|--help)
      echo "logchecker.sh [-action_on 1|2|3|4] [-execd_spool <spool_dir>]" >&2
      exit 0
      ;;
   *)
      echo "Error: unknown command line option: \"$1\""
      exit
      ;;
   esac
   shift 2
   ARGC=`expr $ARGC - 2`
done


if [ $SGE_ROOT = undefined ]; then
   echo SGE_ROOT is still set to \"undefined\". Exiting.
   exit 1
fi

if [ -x $SGE_ROOT/util/arch ]; then
   ARCH=`$SGE_ROOT/util/arch`
else
   echo "can't find script \"$SGE_ROOT/util/arch\". Exiting."
   exit 1
fi

if [ ! -d $SGE_ROOT/utilbin/$ARCH ]; then
   echo "can't find directory \"$SGE_ROOT/utilbin/$ARCH\". Exiting."
   exit 1
fi

bootstrap_file=$SGE_ROOT/$SGE_CELL/common/bootstrap
if [ ! -f $bootstrap_file ]; then
   echo "your \"bootstrap\" file does not exist. Exiting."
   exit 1
fi

qma_spool_dir=`grep '^qmaster_spool_dir' $bootstrap_file | awk '{print $2}'`

execd_spool_dir=$EXECD_SPOOL

if [ "$qma_spool_dir" = "" -o "$execd_spool_dir" = "" ]; then
   echo "can't determine qmaster and/or execd spool directory" >&2
   exit 1
fi

if [ $ACTION_ON = 1 -o $ACTION_ON = 4 ]; then
   sge_logcheck 1 $qma_spool_dir
   sge_logcheck 1 $qma_spool_dir/schedd

   if [ $ACCT = yes ]; then
      sge_logcheck 2 $SGE_ROOT/$SGE_CELL/common/accounting
   fi

	if [ $REPO = yes ]; then
      sge_logcheck 2 $SGE_ROOT/$SGE_CELL/common/reporting
   fi
fi

if [ $ACTION_ON = 2 ]; then
   uqhostname=`$SGE_ROOT/utilbin/$ARCH/gethostname -name | cut -f1 -d.`
   if [ -d $execd_spool_dir/$uqhostname ]; then 
      sge_logcheck 1 $execd_spool_dir/$uqhostname
   else
      $ECHO "directory \"$execd_spool_dir/$uqhostname\" doesn't exit"
   fi
fi

if [ $ACTION_ON = 3 -o $ACTION_ON = 4 -a $execd_spool_dir != "none" ]; then
   for hostdir in `ls $execd_spool_dir| grep -v '^qmaster$'`; do
      if [ -d $execd_spool_dir/$hostdir ]; then
         sge_logcheck 1 $execd_spool_dir/$hostdir
      else
         $ECHO "directory \"$execd_spool_dir/$hostdir\" doesn't exit"
      fi
   done
fi