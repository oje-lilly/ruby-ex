#!/bin/sh
#
# SGE configuration script (Installation/Uninstallation/Upgrade/Downgrade)
# Scriptname: load_sge_config.sh
# Module: common functions
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
#  Portions of this software are Copyright (c) 2013-2015 Univa Corporation
#
##########################################################################
#___INFO__MARK_END__

SCRIPTNAME=`basename "$0"`
CAT=cat
MKDIR=mkdir
LS=ls

if [ "$SCRIPTNAME" = "load_sge_config.sh" ]; then
   if [ -z "$SGE_ROOT" -o -z "$SGE_CELL" ]; then
      echo "Set your SGE_ROOT, SGE_CELL first!"
      exit 1
   fi

   ARCH=`$SGE_ROOT/util/arch`
   QCONF=$SGE_ROOT/bin/$ARCH/qconf
   QMASTER_NAME="qmaster"
   QCONF_NAME="qconf"
   PRODUCT_SHORTCUT="sge"
   HOST=`$SGE_ROOT/utilbin/$ARCH/gethostname -aname`
   INFOTEXT=$SGE_ROOT/utilbin/$ARCH/infotext
else
   if [ -z "$LO_ROOT" -o -z "$LO_CELL" ]; then
      echo "Set your LO_ROOT, LO_CELL first!"
      exit 1
   fi

   export LO_ENABLE_QCONF_OPTIONS=1
   ARCH=`$LO_ROOT/util/arch`
   QCONF=$LO_ROOT/bin/$ARCH/loconf
   QMASTER_NAME="lomaster"
   QCONF_NAME="loconf"
   PRODUCT_SHORTCUT="lo"
   HOST=`$LO_ROOT/utilbin/$ARCH/gethostname -aname`
   INFOTEXT=$LO_ROOT/utilbin/$ARCH/infotext
fi

SUCCEEDED_LOADLOC=""

Usage()
{
   myname=`basename $0`
   $INFOTEXT "Usage: $myname [-log I|W|C] [-help]\n" \
      "\nExample:\n" \
      "   $myname -log C\n" \
      "   Loads the configuration according to the following rules:\n" \
      "      Shows only critical errors"
}


#All logging is done by this functions
LogIt()
{
   urgency="${1:?Urgency is required [I,W,C]}"
   message="${2:?Message is required}"

   #log file contains all messages
   echo "${urgency} $message" >> $MESSAGE_FILE_NAME
   #log when urgency and level is meet
   case "${urgency}${LOGGER_LEVEL}" in
      CC|CW|CI)
         $INFOTEXT "[CRITICAL] $message"
      ;;
      WW|WI)
         $INFOTEXT "[WARNING] $message"
      ;;
      II)
         $INFOTEXT "[INFO] $message"
		;;  
   esac
}


#Remove line with maching expression
RemoveLineWithMatch()
{
   remFile="${1:?Need the file name to operate}"
   remExpr="${2:?Need an expression, where to remove lines}"

   #Return if no match
   grep "${remExpr}" "$remFile" >/dev/null 2>&1
   if [ $? -ne 0 ]; then
      return
   fi

   sed -e "/${remExpr}/d" $remFile > ${remFile}.tmp
   mv -f ${remFile}.tmp  ${remFile}
}


ReplaceLineWithMatch()
{
   repFile="${1:?Need the file name to operate}"
   repExpr="${2:?Need an expression, where to replace}"
   replace="${3:?Need the replacement text}" 

   #Return if no match
   grep "${repExpr}" "$repFile" >/dev/null 2>&1
   if [ $? -ne 0 ]; then
      return
   fi
   SEP="|"
   echo "$repExpr $replace" | grep "|" >/dev/null 2>&1
   if [ $? -eq 0 ]; then
      echo "$repExpr $replace" | grep "%" >/dev/null 2>&1
      if [ $? -ne 0 ]; then
         SEP="%"
      else
         echo "$repExpr $replace" | grep "?" >/dev/null 2>&1
         if [ $? -ne 0 ]; then
            SEP="?"
         else
            LogIt "C" "$repExpr $replace contains |,% and ? character cannot use sed"
         fi
      fi
   fi
   #We need to change the file
   sed -e "s${SEP}${repExpr}${SEP}${replace}${SEP}g" "$repFile" > "${repFile}.tmp"
   mv -f "${repFile}.tmp"  "${repFile}"
}

ReplaceOrAddLine()
{
   repFile="${1:?Need the file name to operate}"
   repExpr="${2:?Need an expression, where to replace}"
   replace="${3:?Need the replacement text}" 

   #Does the pattern exists
   grep "${repExpr}" "${repFile}" > /dev/null 2>&1
   if [ $? -eq 0 ]; then #match
      ReplaceLineWithMatch "$repFile" "$repExpr" "$replace"
   else                  #line does not exist
      echo "$replace" >> "$repFile"
   fi
}

CreateTemplateJobClass()
{
   # Create template Job Class if there is none yet
   tmpfile=/tmp/upgrade$$
   $QCONF -sjc > $tmpfile
   $QCONF -Ajc $tmpfile
   rm $tmpfile
}

#Resolve a result during Loading
ResolveResult()
{
   resOpt="${1:?Need an option to decide}"
   resFile="${2:?Need the file name to load}"
   resMsg="${3-""}"
   resRet="${4:?Need a return code to show the last result}"
   LogIt "I" "ResolveResult ret:$resRet,  opt:$resOpt, file:$resFile, msg:${resMsg}"

   obj=`echo ${resMsg} | awk -F'"' '{ print $2 }'`
   obj=${obj:-unknown}

   #we are expecting troubles, possitive match required
   ret=1
   case "$resOpt" in
      -ah|-ac|-as|-am|-ao)
         #We can ignore  (already exists)
         case "$resMsg" in
            *'already exists')
               LogIt "I" "$obj already exists, accepted"
               return 0
            ;;     
         esac
		;;
      -Ahgrp)
         #The proccessors and load values must be frees
         case "$resMsg" in
            *'already exists')
               LogIt "I" "$obj already exists, trying to modify -Mhgrp"
               LoadConfigFile "$resFile" "-Mhgrp"
               ret=$?
               return $ret
            ;;
         esac
      ;;
      -Ae)
         #The proccessors and load values must be frees
         case "$resMsg" in
            *'already exists')
               LogIt "I" "$obj already exists, trying to modify -Me"
               LoadConfigFile "$resFile" "-Me"
               ret=$?
               return $ret
            ;;
         esac
      ;;
      -Acal)
         case "$resMsg" in
            *'already exists')
               LogIt "I" "$obj already exists, trying to modify -Mcal"
               LoadConfigFile "$resFile" "-Mcal"
               ret=$?
               return $ret
            ;;
         esac
      ;;
      -Ajc)
         case "$resMsg" in
            *'already exists')
               LogIt "I" "$obj already exists, trying to modify -Mcal"
               LoadConfigFile "$resFile" "-Mjc"
               ret=$?
               return $ret
            ;;
         esac
      ;;
      -Auser)
         case "$resMsg" in
            *'already exists')
               LogIt "I" "$obj already exists, trying to modify -Muser"
               LoadConfigFile "$resFile" "-Muser"
               ret=$?
               return $ret
            ;;
         esac
      ;;
      -Au)
         case "$resMsg" in
            *'already exists')
               LogIt "I" "$obj already exists, trying to modify -Mu"
               LoadConfigFile "$resFile" "-Mu"
               ret=$?
               return $ret
            ;;
         esac
      ;;
      -Aprj)
         case "$resMsg" in
            *'already exists')
               LogIt "I" "$obj already exists, trying to modify -Mprj"
               LoadConfigFile "$resFile" "-Mprj"
               ret=$?
               return $ret
            ;;
         esac
      ;;
      -Ap)
         case "$resMsg" in
            *'"accounting_summary" is missing'*)
               echo 'accounting_summary   FALSE' >> "$resFile"
               LogIt "I" "accounting_summary added, trying again"
               LoadConfigFile "$resFile" "-Ap"
               ret=$?
               return $ret
            ;;
            *'already exists')
               LogIt "I" "$obj already exists, trying to modify -Mp"
               LoadConfigFile "$resFile" "-Mp"
               ret=$?
               return $ret
            ;;
         esac
      ;;
      -Arqs)
         case "$resMsg" in
            *'already exists')
               LogIt "I" "$obj already exists, trying to modify -Mrqs"
               LoadConfigFile "$resFile" "-Mrqs"
               ret=$?
               return $ret
            ;;
            *'added'*)
               LogIt "I" "$obj added message accepted"
               #rqs shows added always, need to be eliminated
               return 0
            ;;
            'error: invalid option argument "-Arqs"'*)
               LogIt "I" "skipping the -Arqs option"
               return 0
            ;;
         esac
      ;;
      -Mrqs)
         case "$resMsg" in
            *'added'*)
               LogIt "I" "$obj added message accepted"
               #rqs shows added always, need to be eliminated
               return 0
            ;;
         esac
       ;;  
      -Ackpt)
         case "$resMsg" in
            *'already exists')
               LogIt "I" "$obj already exists, trying to modify -Mckpt"
               LoadConfigFile "$resFile" "-Mckpt"
               ret=$?
               return $ret
            ;;
         esac
      ;;
      -Aq)
         case "$resMsg" in
            *'already exists')
               LogIt "I" "$obj already exists, trying to modify -Mq"
               LoadConfigFile "$resFile" "-Mq"
               ret=$?
               return $ret
            ;;
            'Subordinated cluster queue'*)
               obj=`echo $resMsg | awk '{print $4}' | awk -F\" '{ print $2}'`
               LogIt "W" "Non-existing subordinated queue $obj encountered, creating dummy queue [REPEAT REQUIRED]"
               $QCONF -sq | sed "s/^qname.*/qname                    $obj/g" > ${BCK_DIR}/queue.tmp 2>/dev/null
               $QCONF -Aq ${BCK_DIR}/queue.tmp >/dev/null 2>&1
               rm -f ${BCK_DIR}/queue.tmp
               repeat=1
               return 1
            ;;
         esac
      ;;
      -Mq)
         case "$resMsg" in
            'Subordinated cluster queue'*)
               obj=`echo $resMsg | awk '{print $4}' | awk -F\" '{ print $2}'`
               LogIt "W" "Non-existing subordinated queue $obj encountered, creating dummy queue [REPEAT REQUIRED]"
               $QCONF -sq | sed "s/^qname.*/qname                    $obj/g" > ${BCK_DIR}/queue.tmp 2>/dev/null
               $QCONF -Aq ${BCK_DIR}/queue.tmp >/dev/null 2>&1
               rm -f ${BCK_DIR}/queue.tmp
               repeat=1
               return 1
            ;;
         esac
      ;;
   	#If -Aconf fails we try modify
      -Aconf)
         case "$resMsg" in
            *'value == NULL for attribute'*)
               unknown=`echo ${resMsg} | awk -F'"' '{ print $2 }'`
               ReplaceLineWithMatch ${resFile} "${unknown}*" "#${unknown}"
               LogIt "I" "$obj commented, trying to again"
               LoadConfigFile "$resFile" "$resOpt"
               ret=$?
               return $ret
            ;;
            'denied: the path given for'*)
               #FlatFile ${resFile}
               ReplaceLineWithMatch "$resFile" 'qlogin_daemon.*' 'qlogin_daemon   /usr/sbin/in.telnetd'
               ReplaceLineWithMatch "$resFile" 'rlogin_daemon.*' 'rlogin_daemon   /usr/sbin/in.rlogind'
               LogIt "I" "wrong path corrected, trying again"
               LoadConfigFile "$resFile" "$resOpt"
               ret=$?
               return $ret
            ;;   
            *'already exists')
               LogIt "I" "$obj already exists, trying to modify -Mconf"
               LoadConfigFile "$resFile" "-Mconf"
               ret=$?
               return $ret
            ;;
            *'will not be effective before *_execd restart'*)
               #regular upgrade message
               LogIt "I" "message accepted"
               return 0
            ;;
         esac
      ;;
      -Mconf)
         case "$resMsg" in
            *'value == NULL for attribute'*)
               unknown=`echo ${resMsg} | awk -F'"' '{ print $2 }'`
               ReplaceLineWithMatch ${resFile} "${unknown}*" "#${unknown}"
               LogIt "I" "$obj commented, trying to again"
               LoadConfigFile "$resFile" "$resOpt"
               ret=$?
               return $ret
            ;;
            'denied: the path given for'*)
               #FlatFile ${resFile}
               ReplaceLineWithMatch "$resFile" 'qlogin_daemon.*' 'qlogin_daemon   builtin'
               ReplaceLineWithMatch "$resFile" 'rlogin_daemon.*' 'rlogin_daemon   builtin'
               LogIt "I" "wrong path corrected, trying again"
               LoadConfigFile "$resFile" "$resOpt"
               ret=$?
               return $ret
            ;;   
            *'will not be effective before *_execd restart'*)
               #regular upgrade message
               LogIt "I" "message accepted"
               return 0
            ;;
         esac
      ;;
      -Mc)
         case "$resMsg" in
            '')
               LogIt "I" "empty output from -Mc option accepted"
               return 0
            ;;
         esac
      ;;
   esac

   case "$resMsg" in
      *'unknown attribute name'*)
         #this is a donwngrade option
         #FlatFile ${resFile}
         RemoveLineWithMatch ${resFile} ${obj}
         LogIt "I" "$obj attribute was removed, trying again"
         LoadConfigFile "$resFile" "$resOpt"
         ret=$?
         return $ret
      ;; 
      *'added'*)
         LogIt "I" "added $obj accepted"
         addedConf=1
         return 0
      ;;
      *'modified'*)
         LogIt "I" "modified $obj accepted"
         return 0
      ;;
      *'changed'*)
         LogIt "I" "changed $obj accepted"
         return 0
      ;;
      *'does not exist')
         #some object doesnot exists, must be reloaded
         LogIt "W" "$obj object does not exist. [REPEAT REQUIRED]"
         repeat=1
         return 1
      ;;
   esac
   return $ret
}

#Import item to file
LoadConfigFile()
{
   loadFile="${1:?Need the file name}"
   loadOpt="${2:?Need an option}"

   #do not load empty files
   if [ -f "$loadFile" -a ! -s "$loadFile" ]; then
      LogIt "W" "File $loadFile is empty. Skipping ..."
      return 0
   fi

   if [ "${configLevel:=1}" -gt 20 ]; then
   	LogIt "C" "Too deep in Load Config File"
	   EXIT 1
   fi

   configLevel=`expr ${configLevel} + 1`

   loadMsg=`$QCONF $loadOpt $loadFile 2>&1`

   ResolveResult "$loadOpt" "$loadFile" "$loadMsg" "$ret"
   ret=$?

   if [ "$ret" != "0" ]; then
      errorMsg="Load operation failed: $QCONF_NAME $loadOpt $loadFile -> $loadMsg"
      LogIt "W" "$errorMsg"
   fi

   configLevel=`expr ${configLevel} - 1`
   return $ret
}


#Import list of objects or directory of the objects
LoadListFromLocation()
{
   loadLoc="${1:?Need the location}"
   qconfOpt="${2:?Need an option}"

   failed=0

   for finished in `echo "$SUCCEEDED_LOADLOC" | awk '{for (i=1; i<=NF ; i++) print $i}'`; do
      if [ "$finished" = "$loadLoc" ]; then
         LogIt "I" "$QCONF_NAME $qconfOpt $loadLoc skipped because succeeded already in previous run"
         return 0
      fi
   done

   LogIt "I" "$QCONF_NAME $qconfOpt $loadLoc"

   #File list
   if [ -f "$loadLoc" ]; then
      list=`$CAT $loadLoc`
      if [ -z "$list" ]; then
	      return
      fi

      for item in $list; do
         LoadConfigFile $item $qconfOpt
         if [ $? -ne 0 ]; then
            failed=1
         fi
      done
   #Directory list is not empty
   elif [ -d "$loadLoc" ]; then
      llList=`ls -1 ${loadLoc}`
      if [ -z "$llList" ]; then
         return
      fi

      for item in ${loadLoc}/*; do
         #we prefer full file names
         full=`ls $item`
         LoadConfigFile $full $qconfOpt
         if [ $? -ne 0 ]; then
            failed=1
         fi
      done
   else
      #Not a file or directory (skip)
      errorMsg = "wrong directory or file: $loadLoc"
      LogIt "W" "$errorMsg"
   fi

   if [ $failed -eq  0 ]; then
      SUCCEEDED_LOADLOC="$SUCCEEDED_LOADLOC $loadLoc"
   fi

   return $ret
}


# All SGE objects
LoadConfigurations()
{
   dir=${1:?}
   # There are the add,Load oprtions
   #     -Aattr obj_spec fname obj_instance,...   <add to object attributes>
   #     -aattr obj_spec attr_name val obj_instance,...
   #     -astnode node_path=shares,... <add share tree node>

   # -ah hostname,... <add administrative host>
   LoadListFromLocation "$dir/admin_hosts" "-ah"

   # -as hostname,... <add submit hosts>
   LoadListFromLocation "$dir/submit_hosts" "-as"

   # -am user,... <add managers>
   LoadListFromLocation "$dir/managers" "-am"

   # -ao user,... <add operators>
   LoadListFromLocation "$dir/operators" "-ao"

   # -Mc fname <modify complex>
   if [ "$SCRIPTNAME" = "load_sge_config.sh" ]; then
      LoadConfigFile "$dir/centry" "-Mc"
   else
      LoadConfigFile "$dir/centry" "-Ml"
   fi

   # -Ae fname    <add execution host>
   LoadListFromLocation "$dir/execution" "-Ae"

   # -Acal fname <add calendar>
   LoadListFromLocation "$dir/calendars" "-Acal"

   # -Ackpt fname <add ckpt. environment>
   LoadListFromLocation "$dir/ckpt" "-Ackpt"

   # -Ahgrp file <add host group config>
   LoadListFromLocation "$dir/hostgroups" "-Ahgrp"

   # -Auser fname <add user>
   LoadListFromLocation "$dir/users" "-Auser"

   # -Au fname   <add an ACL>
   LoadListFromLocation "$dir/usersets" "-Au"

   # -Aprj fname <add new project>
   LoadListFromLocation "$dir/projects" "-Aprj"

   # -Ap fname <add PE configuration>
   LoadListFromLocation "$dir/pe" "-Ap"

   # -Aq fname  <add new queue>
   LoadListFromLocation "$dir/cqueues" "-Aq"

   # -Arqs fname <add RQS configuration>
   LoadListFromLocation "$dir/resource_quotas" "-Arqs"

   # -Aconf file_list  <add configurations>
   LoadListFromLocation "$dir/configurations" "-Aconf"

   # -Astree fname  <add share tree>
   LoadConfigFile "$dir/sharetree" "-Astree"

   # -Msconf  fname  <modify scheduler configuration>
   LoadConfigFile "$dir/schedconf" "-Msconf"

   if [ -d "$dir/jobclasses" ]; then
      # -Mjc fname <modify job_class entry from file>
      LoadListFromLocation "$dir/jobclasses" "-Ajc"
   else
      CreateTemplateJobClass
   fi
   if [ "$SCRIPTNAME" = "load_lo_config.sh" ]; then
      unset LO_ENABLE_QCONF_OPTIONS
      # -Alm fname <add license manager>
      LoadListFromLocation "$dir/lms" "-Alm"
      # -Augec fname <add uge cluster>
      LoadListFromLocation "$dir/ugecs" "-Augec"
      export LO_ENABLE_QCONF_OPTIONS=1
   fi
}


# Load once all the configurations
LoadOnce()
{
   dir=${1:?}

   #clean added new configuration
   addedConf=0
   #clean the error code
   errorMsg=''

   LoadConfigurations "$dir"

   # no added configuration, stop to repeat
   if [ $addedConf = 0 ]; then
      repeat=0
   fi
}


# Reload the configuration till there is nothing to add
IterativeLoad()
{
   dir=${1:?}

   repeat=0
   loadLevel=1
   errorMsg=''

   LoadOnce "$dir"
   while [ $repeat -eq  1 ]; do
      loadLevel=`expr ${loadLevel} + 1`
      if [ "${loadLevel}" -gt 10 ]; then
         LogIt "C" "Too deep in Load Level"
         EXIT 1
      fi
      LogIt "W" "[REPEAT LOAD]"
      LoadOnce "$dir"
   done

   if [ -n "$errorMsg" ]; then
      LogIt "C" "$errorMsg"
      EXIT 1
   fi
}

EXIT() {
   if [ -n "$BCK_DIR" ]; then
      rm -rf "$BCK_DIR" 2>/dev/null
      echo Exiting...
   fi
   if [ "$SCRIPTNAME" = "load_lo_config.sh" ]; then
      unset LO_ENABLE_QCONF_OPTIONS
   fi
   exit "$1"
}

########
# MAIN #
########
if [ "$1" = -help -o $# -eq 0 ]; then
   Usage
   exit 0
fi

DIR="${1:?The load directory is required}"
shift

LOGGER_LEVEL="W"

# copy the saved config to a working directory
DATE=`date '+%Y-%m-%d_%H:%M:%S'`
BCK_DIR="/tmp/${PRODUCT_SHORTCUT}_backup_$DATE"
if [ ! -d "$BCK_DIR" ]; then
   mkdir -p $BCK_DIR
else
   $INFOTEXT "Creating directory $BCK_DIR failed - already exists. Try again!"
   exit 1
fi
cp -fR "${DIR}"/* "$BCK_DIR"
$INFOTEXT "Copied ${DIR} to $BCK_DIR"
# Make files readable for all
chmod -R g+r,o+r "$BCK_DIR"/*

MESSAGE_FILE_NAME="/tmp/${PRODUCT_SHORTCUT}_backup_load_${DATE}.log"

ARGC=$#
while [ $ARGC -gt 0 ]; do
   case $1 in
      -log)
         shift
         if [ "$1" != "C" -a "$1" != "W" -a "$1" != "I" ]; then
            LogIt "W" "LOAD invoked with invalid log level "$1" using W"
         else
            LOGGER_LEVEL="$1"
         fi
         ;;
      *)
         echo "Invalid argument \'$1\'"
         Usage
         exit 1
         ;;
   esac
   shift
   ARGC=`expr $ARGC - 2`
done

CURRENT_VERSION=`$QCONF -help | sed  -n '1,1 p'` 2>&1
ret=$?
if [ "$ret" != "0" ]; then
   $INFOTEXT "ERROR: $QCONF_NAME -help failed"
   LogIt "C" "$QMASTER_NAME is not installed"
   EXIT 1
fi
admin_hosts=`$QCONF -sh 2>/dev/null`
if [ -z "$admin_hosts" ]; then
   $INFOTEXT "ERROR: $QCONF_NAME -sh failed. Qmaster is probably not running?"
   LogIt "C" "$QMASTER_NAME is not running"
   EXIT 1
fi
tmp_adminhost=`$QCONF -sh | grep "^${HOST}$"`
if [ "$tmp_adminhost" != "$HOST" ]; then
   $INFOTEXT "ERROR: Load must be started on admin host ($QMASTER_NAME host recommended)."
   LogIt "C" "Can't start load_${PRODUCT_SHORTCUT}_config.sh on $HOST: not an admin host"
   EXIT 1
fi

LOAD_VERSION=`cat ${BCK_DIR}/version`
LogIt "I" "LOAD $DIR backup from $BCK_DIR"
LogIt "I" "$CURRENT_VERSION"
LogIt "I" "$LOAD_VERSION"

$INFOTEXT "Loading saved cluster configuration from $DIR (log in $MESSAGE_FILE_NAME)..."
IterativeLoad "${BCK_DIR}"

LogIt "I" "LOADING FINISHED"
$INFOTEXT "Done"
EXIT 0
