#!/bin/sh
#
# Saves cluster configuration into a directory structure.
# Scriptname: save_sge_config.sh
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
#  Portions of this software are Copyright (c) 2011-2015 Univa Corporation
#
##########################################################################
#___INFO__MARK_END__

SCRIPTNAME=`basename "$0"`

MKDIR=mkdir

if [ "$SCRIPTNAME" = "save_sge_config.sh" ]; then
   if [ -z "$SGE_ROOT" -o -z "$SGE_CELL" ]; then
      echo "Set your SGE_ROOT, SGE_CELL first!" >&2
      exit 1
   fi

   ROOTDIR=$SGE_ROOT
   CELLDIR=$SGE_CELL
   ROOT_NAME="$SGE_ROOT"
   CELL_NAME="$SGE_CELL"
   ARCH=`$ROOTDIR/util/arch`

   QCONF=$ROOTDIR/bin/$ARCH/qconf
   QHOST=$ROOTDIR/bin/$ARCH/qhost
   QSTAT=$ROOTDIR/bin/$ARCH/qstat

   QCONF_NAME="qconf"
   QSTAT_NAME="qstat"
   QQUOTA_NAME="qquota"
   QMASTER_NAME="qmaster"
   PRODUCT_SHORTCUT="sge"
else
   if [ -z "$LO_ROOT" -o -z "$LO_CELL" ]; then
      echo "Set your LO_ROOT, LO_CELL first!" >&2
      exit 1
   fi

   export LO_ENABLE_QCONF_OPTIONS=1
   ROOTDIR=$LO_ROOT
   CELLDIR=$LO_CELL
   ROOT_NAME="$LO_ROOT"
   CELL_NAME="$LO_CELL"
   ARCH=`$LO_ROOT/util/arch`

   QCONF=$LO_ROOT/bin/$ARCH/loconf
   QHOST=$LO_ROOT/bin/$ARCH/lohost
   QSTAT=$LO_ROOT/bin/$ARCH/lostat

   QCONF_NAME="loconf"
   QSTAT_NAME="lostat"
   QQUOTA_NAME="loquota"
   QMASTER_NAME="lomaster"
   PRODUCT_SHORTCUT="lo"
fi

INFOTEXT=$ROOTDIR/utilbin/$ARCH/infotext
HOST=`$ROOTDIR/utilbin/$ARCH/gethostname -aname`

Usage()
{
   myname=`basename $0`
   $INFOTEXT "Usage: $myname <backup_dir>|[-help]\n" \
             "\n<backup_dir> ... Directory in which to store the backup.\n" \
             "                The directory must either be empty or not exist at all."
}

# Dump the states of job class variants (enabled, disabled)
DumpJobClassVariantsToLocation()
{
   dir="${1:?output directory required}"

   if [ ! -d $dir ]; then
      $MKDIR -p $dir
   fi

   output=`$QSTAT -fjc`
   printf "%s" "$output" | while IFS= read -r line; do
      # skip table header
      echo "$line" | grep "job class" > /dev/null 2>&1
      if [ $? -eq 0 ]; then
         continue
      fi
      # skip separator lines
      echo "$line" | grep "\-\-\-\-\-" > /dev/null 2>&1
      if [ $? -eq 0 ]; then
         continue
      fi
      # skip blank lines
      if [ -z "$line" ]; then
         continue
      fi
      # stop if pending job list is reached
      echo "$line" | grep "##########" > /dev/null 2>&1
      if [ $? -eq 0 ]; then
         break
      fi

      # the remaining lines must be job class variants
      name=`echo $line | cut -d" " -f 1`
      state=`expr substr "$line" 76 10`

      # the name is composed from jobclass.variant, split it
      jobclass=`echo $name | cut -d"." -f 1`
      variant=`echo $name | cut -d"." -f 2`

      if [ -z "$state" ]; then
         # state might be an empty string
         state="0"
      elif [ $state = "d" ]; then
         # state "d" translates to state id 1
         state="1"
      fi

      # create a subdirectory for the jobclass
      if [ ! -d "$dir/$jobclass" ]; then
         $MKDIR "$dir/$jobclass"
      fi

      # write the data to a file in this subdirectory
      echo "jcname             $jobclass" >> "$dir/$jobclass/$variant"
      echo "vname              $variant"  >> "$dir/$jobclass/$variant"
      echo "state              $state"    >> "$dir/$jobclass/$variant"
   done
}

# Dump the states of queue instances (disabled, error, etc.)
DumpQueueInstanceStatesToLocation()
{
   dir="${1:?output directory required}"

   if [ ! -d $dir ]; then
      $MKDIR -p $dir
   fi

   output=`$QHOST -q`
   printf "%s\n" "$output" | while IFS= read -r line; do
      # skip table header
      echo "$line" | grep "^HOSTNAME.*ARCH" > /dev/null 2>&1
      if [ $? -eq 0 ]; then
         continue
      fi
      # skip separator lines
      echo "$line" | grep "\-\-\-\-\-" > /dev/null 2>&1
      if [ $? -eq 0 ]; then
         continue
      fi
      # skip global queue
      echo "$line" | grep "^global " > /dev/null 2>&1
      if [ $? -eq 0 ]; then
         continue
      fi
      # all other lines are either host lines or queue lines
      # host lines start at column 1, queue lines at column 4
      echo "$line" | grep "^[[:alnum:]]" > /dev/null 2>&1
      if [ $? -eq 0 ]; then
         # host line
         hostname=`echo $line | cut -d" " -f 1`
         # new host, new queues...
         unset queuename
      else
         # queue line
         queuename=`echo $line | cut -d" " -f 1`
         state=`echo $line | cut -d" " -f 4`
      fi

      # we need at least a queuename/hostname pair to be able to save info
      if [ -n "$hostname" -a -n "$queuename" ]; then
         # create a subdirectory for this queue
         if [ ! -d "$dir/$queuename" ]; then
            $MKDIR "$dir/$queuename"
         fi

         # write data to a host file in this subdirectory
         echo "qname                 $queuename" >> "$dir/$queuename/$hostname"
         echo "hostname              $hostname"  >> "$dir/$queuename/$hostname"
         echo "state                 $state"     >> "$dir/$queuename/$hostname"
      fi
   done
}

#Dump list to dir
DumpListToLocation()
{
   list=$1
   dir=$2
   opt=$3
   if [ ! -d $dir ]; then
     $MKDIR -p $dir
   fi
   if [ -n "$list" ]; then
      for item in $list; do
         # we do not dump templates, as they are builtin
         if [ "$item" != "template" ]; then
            DumpItemToFile $item $dir $opt
         fi
      done
   fi
}


#Dump item to file
DumpItemToFile()
{
   item=$1
   dir=$2
   opt=$3

   $QCONF $opt $item > $dir/${item}
   if [ $? -ne 0 ]; then
      $INFOTEXT "Operation failed: $QCONF $opt > $dir/${item}"
      return 1
   fi
   return 0
}


#Dump qconf option to file
DumpOptionToFile()
{
   opt=$1
   file=$2

   $QCONF $opt > ${file} 2>${file}.err
   ret=$?
   resMsg=`cat ${file}.err`
   rm -f ${file}.err
   if [ $ret -ne 0 ]; then
      case "$resMsg" in
         'no '*)
            return 0
         ;;
      *)
         $INFOTEXT "Operation failed: $QCONF_NAME $opt - $resMsg"
         return 1
         ;;
      esac
   fi
}


#Backup selected files from SgeCell (bootstrap, etc.)
BackupSgeCell()
{
   VERSION=`$QCONF -help | sed  -n '1,1 p'` 2>&1
   ret=$?
   if [ "$ret" = "0" ]; then
      echo $VERSION > $DEST_DIR/version
   else
      $INFOTEXT "[CRITICAL] $QMASTER_NAME is not installed"
      exit 1
   fi
   $QCONF -sq > /dev/null 2>&1
   ret=$?
   if [ "$ret" != "0" ]; then
      $INFOTEXT "[CRITICAL] $QMASTER_NAME is not running"
      exit 1
   fi

   #sge_root
   cat $ROOTDIR/$CELLDIR/common/settings.sh | grep "ROOT_NAME" | head -1 > "${DEST_DIR}/${PRODUCT_SHORTCUT}_root"
   #sge_cell
   cat $ROOTDIR/$CELLDIR/common/settings.sh | grep "CELL_NAME" | head -1 > "${DEST_DIR}/${PRODUCT_SHORTCUT}_cell"
   #qmaster_port, execd_port
   cat $ROOTDIR/$CELLDIR/common/settings.sh | grep "PORT" > "${DEST_DIR}/ports"

   #arseqnum, jobseqnum
   tmp_spool=`cat $ROOTDIR/$CELLDIR/common/bootstrap | grep qmaster_spool_dir | awk '{ print $2 }'`
   cp ${tmp_spool}/arseqnum "$DEST_DIR" 2>/dev/null
   cp ${tmp_spool}/jobseqnum "$DEST_DIR" 2>/dev/null

   #CELLDIR content
   mkdir -p "$DEST_DIR/cell"
   cp $ROOTDIR/$CELLDIR/common/act_qmaster "${DEST_DIR}/cell"
   cp $ROOTDIR/$CELLDIR/common/bootstrap "${DEST_DIR}/cell"
   #cluster_name
   if [ -f $ROOTDIR/$CELLDIR/common/cluster_name ]; then
      cp $ROOTDIR/$CELLDIR/common/cluster_name "${DEST_DIR}/cell"
   fi
   #host_aliases
   if [ -f $ROOTDIR/$CELLDIR/common/host_aliases ]; then
      cp $ROOTDIR/$CELLDIR/common/host_aliases "${DEST_DIR}/cell"
   fi
   #qtask
   if [ -f $ROOTDIR/$CELLDIR/common/qtask ]; then
      cp $ROOTDIR/$CELLDIR/common/qtask "${DEST_DIR}/cell"
   fi
   #sge_aliases
   if [ -f $ROOTDIR/$CELLDIR/common/sge_aliases ]; then
      cp $ROOTDIR/$CELLDIR/common/sge_aliases "${DEST_DIR}/cell"
   fi
   #sge_ar_request
   if [ -f $ROOTDIR/$CELLDIR/common/sge_ar_request ]; then
      cp $ROOTDIR/$CELLDIR/common/sge_ar_request "${DEST_DIR}/cell"
   fi
   #sge_request
   if [ -f $ROOTDIR/$CELLDIR/common/sge_request ]; then
      cp $ROOTDIR/$CELLDIR/common/sge_request "${DEST_DIR}/cell"
   fi
   #sge_qstat
   if [ -f $ROOTDIR/$CELLDIR/common/sge_${QSTAT_NAME} ]; then
      cp $ROOTDIR/$CELLDIR/common/sge_${QSTAT_NAME} "${DEST_DIR}/cell"
   fi
   #sge_qquota
   if [ -f $ROOTDIR/$CELLDIR/common/sge_${QQUOTA_NAME} ]; then
      cp $ROOTDIR/$CELLDIR/common/sge_${QQUOTA_NAME} "${DEST_DIR}/cell"
   fi

   #shadow_masters
   if [ -f $ROOTDIR/$CELLDIR/common/shadow_masters ]; then
      cp $ROOTDIR/$CELLDIR/common/shadow_masters "${DEST_DIR}/cell"
   fi
   #Accounting file
   if [ -r "$ROOTDIR/$CELLDIR/common/accounting" ]; then
      cp "$ROOTDIR/$CELLDIR/common/accounting" "${DEST_DIR}/cell"
   fi
   #Save dbwriter.conf for simple dbwriter upgrade, if present
   if [ -r "$ROOTDIR/$CELLDIR/common/dbwriter.conf" ]; then
      cp "$ROOTDIR/$CELLDIR/common/dbwriter.conf" "${DEST_DIR}/cell"
   fi

   #Save JMX settings if present
   if [ -d "$ROOTDIR/$CELLDIR/common/jmx" ]; then
      cp -r "$ROOTDIR/$CELLDIR/common/jmx" "${DEST_DIR}/cell/jmx"
   fi

   #Save cluster's windows host info
   res=`$QHOST -l "arch=win*" 2>/dev/null`
   if [ -n "$res" ]; then     # has windows hosts
      echo "$res" | grep "win*" | awk '{print $1}' > "${DEST_DIR}"/win_hosts
   fi
}



########
# MAIN #
########
if [ "$1" = "-help" -o $# -eq 0 ]; then
   Usage
   exit 0
fi

#Dump all curent configuration to the temp directory called ccc
DEST_DIR="${1:?The save directory is required}"

admin_hosts=`$QCONF -sh 2>/dev/null`
if [ -z "$admin_hosts" ]; then
   $INFOTEXT "ERROR: $QCONF_NAME -sh failed. $QMASTER_NAME is probably not running?"
   exit 1
fi

tmp_adminhost=`$QCONF -sh | grep "^${HOST}$"`
if [ "$tmp_adminhost" != "$HOST" ]; then
   $INFOTEXT "ERROR: $0 must be started on an admin host ($QMASTER_NAME host recommended)."
   exit 1
fi

if [ ! -d "$DEST_DIR" ]; then
   $MKDIR -p $DEST_DIR
elif [ `ls -1 "$DEST_DIR" | wc -l` -gt 0 ]; then
   $INFOTEXT "ERROR: The save directory $DEST_DIR must be empty"
   exit 1
fi

date '+%Y-%m-%d_%H:%M:%S' > "$DEST_DIR/backup_date"
BackupSgeCell

OLD_SGE_LINE="$SGE_SINGLE_LINE"
SGE_SINGLE_LINE=1
export SGE_SINGLE_LINE

#There are the show options, which are not used
#
#     -sds                          <show detached settings>
#     -secl                         <show event clients>
#     -sep                          <show licensed processors>
#     -shgrp_tree group             <show host group tree>
#     -shgrp_resolved               <show host group hosts>
#     -sobjl obj_spec attr_name val <show object list>
#     -sstnode node_path,...        <show share tree node>
#     -sss                          <show scheduler status>

#     -sh                           <show administrative hosts>
DumpOptionToFile "-sh" "$DEST_DIR/admin_hosts"

#     -ss                           <show submit hosts>
DumpOptionToFile "-ss" "$DEST_DIR/submit_hosts"

#     -sm                           <show managers>
DumpOptionToFile "-sm" "$DEST_DIR/managers"

#     -so                           <show operators>
DumpOptionToFile "-so" "$DEST_DIR/operators"

#     -sc                           <show complexes>
if [ "$SCRIPTNAME" = "save_sge_config.sh" ]; then
   DumpOptionToFile "-sc" "$DEST_DIR/centry"
else
   DumpOptionToFile "-sl" "$DEST_DIR/centry"
fi

#     -sel                          <show execution hosts>
list=`$QCONF -sel 2>/dev/null`
#     -se hostname                  <show execution host>
DumpListToLocation "$list" $DEST_DIR/execution "-se"
DumpOptionToFile "-se global" $DEST_DIR/execution/global

#     -scall                        <show calendar list>
list=`$QCONF -scall 2>/dev/null`
#     -scal calendar_name           <show calendar>
DumpListToLocation "$list" $DEST_DIR/calendars "-scal"

#     -sjcl                         <show job class list>
list=`$QCONF -sjcl 2>/dev/null`
#     -sjc jc_name                  <show job class>
DumpListToLocation "$list" $DEST_DIR/jobclasses "-sjc"

#     -sckptl                       <show ckpt. environment list>
list=`$QCONF -sckptl 2>/dev/null`
#     -sckpt ckpt_name              <show ckpt. environment>
DumpListToLocation "$list" $DEST_DIR/ckpt "-sckpt"

#     -ssconf                       <show scheduler configuration>
DumpOptionToFile "-ssconf" "$DEST_DIR/schedconf"

#     -shgrpl                       <show host group lists>
list=`$QCONF -shgrpl 2>/dev/null`
#     -shgrp group                  <show host group config.>
DumpListToLocation "$list" $DEST_DIR/hostgroups "-shgrp"

#     -suserl                       <show users>
list=`$QCONF -suserl 2>/dev/null`
#     -suser user,...               <show user>
DumpListToLocation "$list" $DEST_DIR/users "-suser"

#     -sprjl                        <show project list>
list=`$QCONF -sprjl 2>/dev/null`
#     -sprj project                 <show project>
DumpListToLocation "$list" $DEST_DIR/projects "-sprj"

#   [-sconfl]                       <show a list of all local configurations>
list=`$QCONF -sconfl 2>/dev/null`
#    -sconf [host,...|global]      <show configuration>
DumpListToLocation "$list" $DEST_DIR/configurations "-sconf"
DumpOptionToFile "-sconf global" "$DEST_DIR/configurations/global"

#     -spl                          <show PE-list>
list=`$QCONF -spl 2>/dev/null`
#     -sp pe_name                   <show PE configuration>
DumpListToLocation "$list" $DEST_DIR/pe "-sp"

#     -sul                          <show user ACL lists>
list=`$QCONF -sul 2>/dev/null`
#     -su acl_name                  <show user ACL>
DumpListToLocation "$list" $DEST_DIR/usersets "-su"

#     -sql                          <show queue list>
list=`$QCONF -sql 2>/dev/null`
#     -sq wc_queue_list             <show queues>
DumpListToLocation "$list" $DEST_DIR/cqueues "-sq"

#     -srqsl                        <show RQS-list>
list=`$QCONF -srqsl 2>/dev/null`
#     -srqs [rqs_name_list]         <show RQS configuration>
DumpListToLocation "$list" $DEST_DIR/resource_quotas "-srqs"

#     -sstree                       <show share tree>
DumpOptionToFile "-sstree" "$DEST_DIR/sharetree"

DumpJobClassVariantsToLocation "$DEST_DIR/vinstances"

DumpQueueInstanceStatesToLocation "$DEST_DIR/qinstances"

if [ "$SCRIPTNAME" = "save_lo_config.sh" ]; then
   unset LO_ENABLE_QCONF_OPTIONS
#     -slml                      <show license manager list>
   list=`$QCONF -slml 2>/dev/null`
   DumpListToLocation "$list" $DEST_DIR/lms "-slm"

#     -sugecl                      <show uge cluster list>
   list=`$QCONF -sugecl 2>/dev/null`
   DumpListToLocation "$list" $DEST_DIR/ugecs "-sugec"
fi

#Make files readable for all
chmod -R g+r,o+r "$DEST_DIR"/*

$INFOTEXT "Configuration successfully saved to $DEST_DIR directory."
exit 0
