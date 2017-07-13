#!/bin/sh
#
# Set file permissions of Grid Engine distribution
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
#
# The $OPTFILES are not mandatory for a distribution and will be set only if
# they exist
#
# This script must be called by user root on a machine where user root has
# permissions to change the ownership of a file
# 
# It is not necessary to run this script if the distribtuon has been
# installed with pkgadd, since pkgadd takes care about the correct
# permissions.
#

PATH=/bin:/usr/bin:/usr/sbin

FILELIST="bin dtrace examples install_execd install_qmaster \
          lib util utilbin"

OPTFILES="catman doc include man"

SUIDFILES="utilbin/*/rsh utilbin/*/rlogin utilbin/*/testsuidroot utilbin/*/authuser"

instauto=false
instlo=false

if [ $1 = -auto ]; then
   instauto=true
   shift
fi

if [ $1 = -lo ]; then
   instlo=true
   shift
fi

if [ "$instlo" = true ]; then
   root_dir=$LO_ROOT
   root_txt="\$LO_ROOT"
   product_name="License Orchestrator"
   FILELIST="$FILELIST inst_lo"
else
   root_dir=$SGE_ROOT
   root_txt="\$SGE_ROOT"
   product_name="Grid Engine"
   FILELIST="$FILELIST 3rd_party ckpt inst_sge mpi pvm qmon start_gui_installer install_execd.bat"
   OPTFILES="$OPTFILES hadoop docker"
   SUIDFILES="$SUIDFILES bin/*/sgepasswd"
fi

umask 022

#---------------------------------------------------
# SetFilePerm
#
SetFilePerm()
{
   f="$1"
   user="0"
   group="0"

   $ECHO "Verifying and setting file permissions and owner in >$f<"

   chmod -R go+r $f
   find $f -type d -exec chmod 755 {} \;
   find $f -type f -perm -100 -exec chmod go+x {} \;
   chown -R $user $f
   chgrp -R $group $f
}

#---------------------------------------------------------------------
# MAIN MAIN
#

if [ -z "$root_dir" -o ! -d "$root_dir" ]; then
   echo 
   echo ERROR: Please set your $root_txt environment variable
   echo and start this script again. Exit.
   echo 
   exit 1
fi

if [ ! -f "$root_dir/util/arch" ]; then
   echo 
   echo ERROR: The shell script \"$root_dir/util/arch\" does not exist.
   echo Please verify your distribution and restart this script. Exit.
   echo
   exit 1
fi

if [ ! -f $root_dir/util/arch_variables ]; then
   echo
   echo ERROR: Missing shell script \"$root_dir/util/arch_variables\".
   echo Please verify your distribution and restart this script. Exit.
   echo
   exit 1
fi

. $root_dir/util/arch_variables

if [ $ARCH = "win32-x86" ]; then
   echo
   echo "ERROR: Using this script on windows is not supported!"
   echo "Please execute this script on a unix host"
   echo
   exit 1
fi

if [ $# -lt 1 ]; then
   echo
   echo Set file permissions and owner of $product_name distribution in $root_txt
   echo 
   echo "usage: $0 [-auto] [-lo] <$root_txt>"
   echo 
   echo example: $0 $root_txt
   echo
   exit 1
fi

if [ $1 = / -o $1 = /etc ]; then
   echo
   echo ERROR: cannot set permissions in \"$1\" directory of your system.
   echo
   exit 1
fi

if [ `echo $1 | env LC_ALL=C cut -c1` != / ]; then
   echo
   echo ERROR: Please give an absolute path for the distribution.
   echo
   exit 1
fi


if [ $instauto = true ]; then
   :
else
   clear
   $ECHO "                    WARNING WARNING WARNING"
   $ECHO "                    -----------------------"
   $ECHO "We will set the the file ownership and permission to"
   $ECHO
   $ECHO "   UserID:         0"
   $ECHO "   GroupID:        0"
   $ECHO "   In directory:   $1"
   $ECHO
   $ECHO "We will also install the following binaries as SUID-root:"
   $ECHO
   $ECHO "   $root_txt/utilbin/<arch>/rlogin"
   $ECHO "   $root_txt/utilbin/<arch>/rsh"
   $ECHO "   $root_txt/utilbin/<arch>/testsuidroot"
   $ECHO "   $root_txt/bin/<arch>/sgepasswd"
   $ECHO

   TEXT="Do you want to set the file permissions (yes/no) [NO] >> \c"

   YesNo_done=false
   while [ $YesNo_done = false ]; do
      $ECHO "$TEXT" 
      read YesNo_INP
      if [ "$YesNo_INP" = "yes" -o "$YesNo_INP" = YES ]; then
         YesNo_done=true
      elif [ "$YesNo_INP" = "NO" -o "$YesNo_INP" = no ]; then
         $ECHO
         $ECHO "We will NOT set the file permissions. Exiting."
         exit 1
      fi
   done
fi

cd $1
if [ $? != 0 ]; then
   $ECHO "ERROR: can't change to directory \"$1\". Exiting."
   exit 1
fi

for f in $FILELIST; do
   if [ ! -f $f -a ! -d $f ]; then
      $ECHO
      $ECHO "Obviously this is not a complete $product_name distribution or this"
      $ECHO "is not your $root_txt directory."
      $ECHO
      $ECHO "Missing file or directory: $f"
      $ECHO
      $ECHO "Your file permissions will not be set. Exit."
      $ECHO
      exit 1
   fi
done

for f in $FILELIST $OPTFILES; do
   if [ -d $f -o -f $f ]; then
      SetFilePerm $f
   fi
done

for file in $SUIDFILES; do
   # Windows NFS Server does not like suid files
   if [ "`echo $file | grep win32-x86`" != "" ]; then
      chmod 511 $file
   else
      chmod 4555 $file
   fi
done

$ECHO
$ECHO "Your file permissions were set"
$ECHO
