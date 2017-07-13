#!/bin/sh
#
#___INFO__MARK_BEGIN__
###########################################################################
#
#  The contents of this file are made available subject to the terms of the
#  Apache Software License 2.0 ('The License').
#  You may not use this file except in compliance with The License.
#  You may obtain a copy of The License at
#  http://www.apache.org/licenses/LICENSE-2.0.html
#
#  Copyright (c) 2014-2016 Univa Corporation.
#
###########################################################################
#___INFO__MARK_END__

INFOTEXT=echo
CAT=cat
MKDIR=mkdir
LS=ls
SCRIPTNAME=`basename "$0"`

if [ "$SCRIPTNAME" = "upgrade_config.sh" ]; then
   if [ -z "$SGE_ROOT" -o -z "$SGE_CELL" ]; then
      $INFOTEXT "Set your SGE_ROOT, SGE_CELL first!"
      exit 1
   fi
   ROOTDIR=$SGE_ROOT
   CELLDIR=$SGE_CELL
   ARCH=`$ROOTDIR/util/arch`
   QCONF=$ROOTDIR/bin/$ARCH/qconf
   QCONF_NAME="qconf"
   QMASTER_NAME="qmaster"
   PRODUCT_SHORTCUT="sge"
else
   if [ -z "$LO_ROOT" -o -z "$LO_CELL" ]; then
      $INFOTEXT "Set your LO_ROOT, LO_CELL first!"
      exit 1
   fi
   export LO_ENABLE_QCONF_OPTIONS=1
   ROOTDIR=$LO_ROOT
   CELLDIR=$LO_CELL
   ARCH=`$ROOTDIR/util/arch`
   QCONF=$ROOTDIR/bin/$ARCH/loconf
   QCONF_NAME="loconf"
   QMASTER_NAME="lomaster"
   PRODUCT_SHORTCUT="lo"
fi

HOST=`$ROOTDIR/utilbin/$ARCH/gethostname -aname`

. $ROOTDIR/util/install_modules/inst_common.sh
BasicSettings
GetAdminUser

###############################################################################
# Helper functions
###############################################################################

Usage()
{
   myname=`basename $0`
   $INFOTEXT "Usage: $myname <dir> <date> [-log I|W|C] [-mode upgrade|copy] [-newijs true|false]\n" \
             "               [-execd_spool_dir <value>] [-admin_mail <value>]\n" \
             "               [-gid_range <integer_range_value>] [-help]\n" \
             "   dir   location of the saved cluster configuration\n" \
             "   date  timestamp to use for temporary directory name and log file name\n\n" \
             "Example:\n" \
             "   $myname -log C -mode copy -newijs true -execd_spool_dir /${PRODUCT_SHORTCUT}/real_execd_spool\n" \
             "           -admin_mail user@host.com -gid_range 23000-24000\n" \
             "   Loads the configuration according to the following rules:\n" \
             "   Shows only critical errors\n" \
             "   Uses copy upgrade mode (local execd spool dirs will be changed)\n" \
             "   Enables new interactive job support\n" \
             "   Changes the global execution daemon spooling directory\n" \
             "   Sets the address to which to send mail\n" \
             "   Sets the group ID range"
}

EXIT() {
   if [ "$SCRIPTNAME" = "upgrade_lo_config.sh" ]; then
      unset LO_ENABLE_QCONF_OPTIONS
   fi
   exit "$1"
}

# All logging is done by this functions
LogIt()
{
   urgency="${1:?Urgency is required [I,W,C]}"
   message="${2:?Message is required}"

   #log file contains all messages
   echo "${urgency} $message" >> $LOG_FILE_NAME
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

###############################################################################
# File modification functions
###############################################################################

# Remove a parameter from an attribute(line) in a config file
RemoveAttribute()
{
   remFile="${1:?Need the file name to operate}"
   remAttr="${2:?Need an attribute name, where to remove a parameter}"
   remParam="${3:?Need a parameter name to remove}"
   remDefault="${4:?Need a default value for the attribute}"

   # search line
   line=`grep "^${remAttr}" "$remFile" 2>/dev/null`
   if [ $? -ne 0 ]; then
      return
   fi

   params=`echo $line | cut -f 2- -d " "`
   remaining_params=""
   OLD_IFS="$IFS"
   IFS=" ,"
   for p in $params; do
      echo "$p" | grep -i "$remParam" >/dev/null 2>&1
      if [ $? -ne 0 ]; then
         remaining_params="$remaining_params $p"
      fi
   done
   IFS="$OLD_IFS"

   if [ "$remaining_params" = "" ]; then
      remaining_params="$remDefault"
   fi

   ReplaceLineWithMatch "$remFile" "^$remAttr .*" "$remAttr $remaining_params"
}

# Remove line with maching expression
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

AddLineIfNotExisting()
{
   addFile="${1:?Need the file name to operate}"
   addExpr="${2:?Need an expression to check if line already exists}"
   addLine="${3:?Need a line to add}"

   grep "$addExpr" "$addFile" > /dev/null 2>&1
   if [ $? -ne 0 ]; then
      echo "$addLine" >> "$addFile"
   fi
}

###############################################################################
# Grid Engine version comparison functions
###############################################################################

version_map="SGE 6.2u5        : 6250,
             UGE 8.0.0        : 8000,
             UGE 8.0.0p1      : 8000,
             UGE 8.0.0p2      : 8000,
             UGE 8.0.1alpha1  : 8010,
             UGE 8.0.1alpha2  : 8010,
             UGE 8.0.1        : 8010,
             UGE 8.0.1p1      : 8010,
             UGE 8.0.1p2      : 8010,
             UGE 8.0.1p3      : 8010,
             UGE 8.0.1p4      : 8010,
             UGE 8.0.1p5      : 8010,
             UGE 8.0.1p6      : 8010,
             UGE 8.0.1p7      : 8010,
             UGE 8.0.1p7_1    : 8010,
             UGE 8.0.1p8      : 8010,
             UGE 8.0.1p9      : 8010,
             UGE 8.0.1p10     : 8010,
             UGE 8.0.1p11     : 8010,
             UGE 8.0.1p12     : 8010,
             UGE 8.0.1p13     : 8010,
             UGE 8.0.1p14     : 8010,
             UGE 8.0.1p15     : 8010,
             UGE 8.0.1p16     : 8010,
             UGE 8.0.1p17     : 8010,
             UGE 8.1.0alpha1  : 8100,
             UGE 8.1.0alpha2  : 8100,
             UGE 8.1.0beta2   : 8100,
             UGE 8.1.0        : 8100,
             UGE 8.1.1        : 8110,
             UGE 8.1.1p1      : 8110,
             UGE 8.1.2        : 8120,
             UGE 8.1.2_1      : 8120,
             UGE 8.1.3        : 8130,
             UGE 8.1.4        : 8140,
             UGE 8.1.5        : 8150,
             UGE 8.1.6        : 8160,
             UGE 8.1.6p1      : 8160,
             UGE 8.1.7alpha   : 8170,
             UGE 8.1.7        : 8170,
             UGE 8.1.7p1      : 8170,
             UGE 8.1.7p2      : 8170,
             UGE 8.1.7p3      : 8170,
             UGE 8.1.7p4      : 8170,
             UGE 8.1.7p5      : 8170,
             UGE 8.2.0alpha1  : 8200,
             UGE 8.2.0alpha2  : 8200,
             UGE 8.2.0alpha3  : 8200,
             UGE 8.2.0alpha4  : 8200,
             UGE 8.2.0alpha5  : 8200,
             UGE 8.2.0alpha6  : 8200,
             UGE 8.2.0alpha7  : 8200,
             UGE 8.2.0alpha8  : 8200,
             UGE 8.2.0beta1   : 8200,
             UGE 8.2.0        : 8200,
             UGE 8.2.0p2      : 8200,
             UGE 8.2.1        : 8200,
             UGE 8.2.1_C1_2   : 8200,
             UGE 8.2.1p1      : 8200,
             UGE 8.3.0prealpha : 8300,
             UGE 8.3.0beta1   : 8300,
             UGE 8.3.0beta2   : 8300,
             UGE 8.3.0beta3   : 8300,
             UGE 8.3.0        : 8300,
             UGE 8.3.0p1      : 8300,
             UGE 8.3.1beta    : 8300,
             UGE 8.3.1        : 8300,
             UGE 8.3.1p1      : 8300,
             UGE 8.3.1p2      : 8300,
             UGE 8.3.1p3      : 8300,
             UGE 8.3.1p4      : 8300,
             UGE 8.3.1p5      : 8300,
             UGE 8.3.1p6      : 8300,
             UGE 8.3.1p7      : 8300,
             UGE 8.3.1p8      : 8300,
             UGE 8.3.1p8_C2_1 : 8300,
             UGE 8.3.1p8_C2_2 : 8300,
             UGE 8.3.1p9      : 8300,
             UGE 8.3.1p10     : 8300,
             UGE 8.3.1p11     : 8300,
             UGE 8.4.0alpha1  : 8400,
             UGE 8.4.0beta1   : 8400,
             UGE 8.4.0beta2   : 8400,
             UGE 8.4.0        : 8400,
             UGE 8.4.1prealpha : 8410,
             UGE 8.4.1        : 8410,
             UGE 8.4.2        : 8420"

GetMapEntry()
{
   line="${1:?Missing line parameter}"
   column="${2:?Missing column parameter}"

   # get the left field (=key) of the idx'th row of the version map, strip blanks
   ret=`echo $version_map | cut -d"," -f $line | cut -d':' -f $column | sed -e 's/^[[:space:]]*//g' -e 's/[[:space:]]*\$//g'`
   echo "$ret"
}

CompareVersions()
{
   ver1="${1:?Missing version paramter 1}"
   ver2="${2:?Missing version paramter 2}"

   # we are not interested in SGE/OGE/UGE prefixes
   ver1=`echo $ver1 | sed -n 's/[a-zA-Z]* \([0-9].*\)/\1/p'`
   ver2=`echo $ver2 | sed -n 's/[a-zA-Z]* \([0-9].*\)/\1/p'`

   version_nr_1=0
   version_nr_2=0
   do_loop="true"
   i=1
   while [ $do_loop = "true" ]; do
      version_name=`GetMapEntry $i 1`
      if [ -z "$version_name" ]; then
         do_loop="false"
         continue
      else
         # we are not interested in SGE/OGE/UGE prefixes
         version_name=`echo $version_name | sed -n 's/[a-zA-Z]* \([0-9].*\)/\1/p'`
         if [ "$ver1" = "$version_name" ]; then
            version_nr_1=`GetMapEntry $i 2`
         fi
         if [ "$ver2" = "$version_name" ]; then
            version_nr_2=`GetMapEntry $i 2`
         fi

         if [ $version_nr_1 -ne 0 -a $version_nr_2 -ne 0 ]; then
            do_loop="false"
         else
            i=`expr $i + 1`
         fi
      fi
   done

   if [ $version_nr_1 -lt $version_nr_2 ]; then
      ret=-1
   elif [ $version_nr_1 -eq $version_nr_2 ]; then
      ret=0
   else
      ret=1
   fi

   echo $ret
}


###############################################################################
# Upgrade functions
###############################################################################

UpgradeConfigTo62u5()
{
   working_dir="${1:?Missing working dir parameter}"

   echo "Upgrading config to SGE 6.2u5"

   # COMPLEXES
   # add m_core if missing (new in 62u5)
   AddLineIfNotExisting "$working_dir/centry" "^m_core " \
      "m_core              core       INT         <=    YES         NO         0        0"

   # add m_socket if missing (new in 62u5)
   AddLineIfNotExisting "$working_dir/centry" "^m_socket " \
      "m_socket            socket     INT         <=    YES         NO         0        0"

   # add m_topology if missing (new in 62u5)
   AddLineIfNotExisting "$working_dir/centry" "^m_topology " \
      "m_topology          topo       RESTRING    ==    YES         NO         NONE     0"

   # add m_topology_inuse if missing (new in 62u5)
   AddLineIfNotExisting "$working_dir/centry" "^m_topology_inuse " \
      "m_topology_inuse    utopo      RESTRING    ==    YES         NO         NONE     0"

   # add display_win_gui if missing (new before 62u5)
   AddLineIfNotExisting "$working_dir/centry" "^display_win_gui " \
      "display_win_gui     dwg        BOOL        ==    YES         NO         0        0"

   # ADVANCE RESERVATION USERS
   # add arusers ACL for 6.2+
   if [ ! -f $working_dir/usersets/arusers ]; then
      echo "name       arusers
            type       ACL
            oticket    0
            fshare     0
            entries    NONE" > $working_dir/usersets/arusers
   fi

   # update version file
   echo "SGE 6.2u5" > ${working_dir}/version
}

UpgradeConfigTo800()
{
   working_dir="${1:?Missing working dir parameter}"

   echo "Upgrading config to UGE 8.0.0"

   # COMPLEXES
   # add m_thread if missing (new in 8.0.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_thread " \
      "m_thread            thread     INT         <=    YES         NO         0        0"

   # update version file
   echo "UGE 8.0.0" > ${working_dir}/version
}

UpdateSchedulerConfigurationTo810()
{
   modFile=$1
   value=""
   newParams=""
   params_found=false

   # FAIR_URGENCY
   #
   # In UGE < 8.1, the FAIR_URGENCY was defined in the scheduler "params" list.
   # From 8.1 on, there is a separate entry "fair_urgency_list".
   # To perform the update, the list must be parsed from the "params" list, must
   # be deleted there and must be moved over to the "fair_urgency_list".
   #
   # An old "params" entry could look like this:
   # params   FAIR_URGENCY=h_vmem \
   #          test=123, FAIR_URGENCY=s_vmem:s_rt:h_rt FAIR_URGENCY=load_avg \
   #          FAIR_URGENCY=cpu:io
   #
   # The effective "FAIR_URGENCY=cpu:io" must be moved to the "fair_urgency_list":
   # fair_urgency_list  cpu,io
   #
   # and must be removed from the params, which has to look like this afterwards:
   # params   test=123

   # read the scheduler config file line by line, skip all before the "params"
   # entry and parse the one starting with "params" and all lines continued by "\"
   while read line; do
      if [ "$params_found" = "false" ]; then
         first_word=`echo $line | egrep "^params "`
         if [ "$first_word" = "" ]; then
            continue
         fi
      fi
      params_found=true
      has_continuation=false

      # convert commas to spaces
      converted_line=`echo $line | tr -s ',' ' '`
      # also remove the word "params" from this line
      converted_line=`echo $converted_line | sed 's/params//'`
      # split the line at spaces
      for tupel in $converted_line; do
         # now one tupel is e.g. "FAIR_URGENCY=h_vmem:io" or "test=123"
         # get key (FAIR_URGENCY) and value (h_vmem:io) from it
         key=`echo $tupel | cut -d"=" -f 1`
         if [ "$key" = "FAIR_URGENCY" ]; then
            value=`echo $tupel | cut -d"=" -f 2`
         else
            if [ "$key" = '\' ]; then
               has_continuation=true
            fi
         fi
      done

      # now we can simply remove all "FAIR_URGENCY=" entries from the line
      cleaned_line=`echo $converted_line | sed 's/FAIR_URGENCY=[^ ,\\]*//g'`

      # also remove all (trailing) "\" characters
      cleaned_line=`echo $cleaned_line | sed 's/\\\\//g'`

      # append this line to the new params buffer
      newParams=$newParams" "$cleaned_line

      # now we can completely remove the line from the original configuration -
      # the newParams contains all information we need
      RemoveLineWithMatch ${modFile} ${line}

      # if there is no next line that belongs to the params we can stop parsing
      if [ "$has_continuation" != "true" ]; then
         break
      fi
   done < $modFile

   # add the new "params" to the configuration
   newParams=`echo $newParams | tr -s ' '`
   if [ "$newParams" = "" ]; then
      newParams="NONE"
   fi
   ReplaceOrAddLine ${modFile} 'params.*' "params  $newParams"

   if [ "$value" != "" ]; then
      # the value still contains colons as separators, have to convert this to commas:
      value=`echo $value | tr -s ':' ','`
   else
      value="NONE"
   fi
   # Add the fair_urgency_list to the scheduler configuration
   ReplaceOrAddLine ${modFile} 'fair_urgency_list.*' "fair_urgency_list     $value"
}

UpdateQueueConfigurationTo810()
{
   modFile=$1

   # Add jc_list defaults to queue config (new in 8.1.0)
   ReplaceOrAddLine ${modFile} 'jc_list.*' "jc_list   ANY_JC,NO_JC"
}

UpgradeConfigTo810()
{
   working_dir="${1:?Missing working dir parameter}"

   echo "Upgrading config to UGE 8.1.0"

   # COMPLEXES
   # add m_numa_nodes if missing (new in 810alpha1)
   AddLineIfNotExisting "$working_dir/centry" "^m_numa_nodes " \
      "m_numa_nodes        nodes      INT         <=    YES         NO         0        0"

   # add m_mem_used if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_mem_used " \
      "m_mem_used          mused      MEMORY      >=    YES         NO         0        0"

   # add m_mem_used_n0 if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_mem_used_n0 " \
      "m_mem_used_n0       mused0     MEMORY      >=    YES         NO         0        0"

   # add m_mem_used_n1 if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_mem_used_n1 " \
      "m_mem_used_n1       mused1     MEMORY      >=    YES         NO         0        0"

   # add m_mem_used_n2 if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_mem_used_n2 " \
      "m_mem_used_n2       mused2     MEMORY      >=    YES         NO         0        0"

   # add m_mem_used_n3 if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_mem_used_n3 " \
      "m_mem_used_n3       mused3     MEMORY      >=    YES         NO         0        0"

   # add m_mem_free if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_mem_free " \
      "m_mem_free          mfree      MEMORY      <=    YES         YES        0        0"

   # add m_mem_free_n0 if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_mem_free_n0 " \
      "m_mem_free_n0       mfree0     MEMORY      <=    YES         YES        0        0"

   # add m_mem_free_n1 if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_mem_free_n1 " \
      "m_mem_free_n1       mfree1     MEMORY      <=    YES         YES        0        0"

   # add m_mem_free_n2 if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_mem_free_n2 " \
      "m_mem_free_n2       mfree2     MEMORY      <=    YES         YES        0        0"

   # add m_mem_free_n3 if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_mem_free_n3 " \
      "m_mem_free_n3       mfree3     MEMORY      <=    YES         YES        0        0"

   # add m_mem_total_n0 if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_mem_total_n0 " \
      "m_mem_total_n0      mmem0      MEMORY      <=    YES         YES        0        0"

   # add m_mem_total_n1 if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_mem_total_n1 " \
      "m_mem_total_n1      mmem1      MEMORY      <=    YES         YES        0        0"

   # add m_mem_total_n2 if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_mem_total_n2 " \
      "m_mem_total_n2      mmem2      MEMORY      <=    YES         YES        0        0"

   # add m_mem_total_n3 if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_mem_total_n3 " \
      "m_mem_total_n3      mmem3      MEMORY      <=    YES         YES        0        0"

   # add m_mem_total if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_mem_total " \
      "m_mem_total         mmem       MEMORY      <=    YES         YES        0        0"

   # add m_cache_l3 if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_cache_l3 " \
      "m_cache_l3          mcache3    MEMORY      <=    YES         NO         0        0"

   # add m_cache_l2 if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_cache_l2 " \
      "m_cache_l2          mcache2    MEMORY      <=    YES         NO         0        0"

   # add m_cache_l1 if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_cache_l1 " \
      "m_cache_l1          mcache1    MEMORY      <=    YES         NO         0        0"

   # add m_topology_numa if missing (new in 8.1.0)
   AddLineIfNotExisting "$working_dir/centry" "^m_topology_numa " \
      "m_topology_numa     unuma      RESTRING    ==    YES         NO         NONE     0"

   # SCHEDULER CONFIG
   UpdateSchedulerConfigurationTo810 "$working_dir/schedconf"

   # QUEUE configuration
   for item in `ls -1 $working_dir/cqueues`; do
      UpdateQueueConfigurationTo810 "${working_dir}/cqueues/$item"
   done

   # update version file
   echo "UGE 8.1.0" > ${working_dir}/version
}

UpgradeConfigTo815()
{
   working_dir="${1:?Missing working dir parameter}"

   echo "Upgrading config to UGE 8.1.5"

   # COMPLEXES
   # add d_rt if missing (new in 8.1.5)
   AddLineIfNotExisting "$working_dir/centry" "^d_rt " \
      "d_rt                d_rt       TIME        <=    YES         NO         0:0:0     0"

   # update version file
   echo "UGE 8.1.5" > ${working_dir}/version
}

UpgradeConfigTo817()
{
   working_dir="${1:?Missing working dir parameter}"

   echo "Upgrading config to UGE 8.1.7"

   # update version file
   echo "UGE 8.1.7" > ${working_dir}/version
}

UpgradeConfigTo820()
{
   working_dir="${1:?Missing working dir parameter}"

   echo "Upgrading config to UGE 8.2.0"

   # QUEUE CONFIG
   # add d_rt if missing (new in 8.2.0)
   for item in `ls -1 $working_dir/cqueues`; do
      AddLineIfNotExisting "$working_dir/cqueues/$item" "^d_rt " "d_rt       INFINITY"
   done

   # check if d_rt is configured in any host, if yes inform user that d_rt was
   # moved to the cluster queue
   #for item in `ls -1 $working_dir/execution`; do
   #   grep "d_rt" "$working_dir/execution/$item" > /dev/null 2>&1
   #   if [ $? -eq 0 ]; then
   #      echo "d_rt is configured in the $item execution host configuration. Since"
   #      echo "UGE 8.2.0, d_rt is part of the cluster queue configuration, so it shouldn't"
   #      echo "be necessary anymore to configure it in the execution host configuration."
   #      echo ""
   #   fi
   #done

   # SCHEDULER CONFIG
   # add backfilling if missing (new in 8.2.0)
   AddLineIfNotExisting "$working_dir/schedconf" "^backfilling " "backfilling   ON"

   # GLOBAL CONFIG
   AddLineIfNotExisting "$working_dir/configurations/global" "^max_advance_reservations" \
      "max_advance_reservations     0"
   AddLineIfNotExisting "$working_dir/configurations/global" "^default_jc " "default_jc none"
   AddLineIfNotExisting "$working_dir/configurations/global" "^enforce_jc " "enforce_jc false"
   AddLineIfNotExisting "$working_dir/configurations/global" "^cgroups_params " \
      "cgroups_params cgroup_path=none cpuset=false mount=false freezer=false freeze_pe_tasks=false killing=false forced_numa=false h_vmem_limit=false m_mem_free_hard=false m_mem_free_soft=false min_memory_limit=0"

   # PARALLEL ENVIRONMENTS
   for item in `ls -1 $working_dir/pe`; do
      # add daemon_forks_slaves FALSE if missing (new in 8.2.0)
      AddLineIfNotExisting "$working_dir/pe/$item" "^daemon_forks_slaves " \
         "daemon_forks_slaves    FALSE"

      # add master_forks_slaves FALSE if missing (new in 8.2.0)
      AddLineIfNotExisting "$working_dir/pe/$item" "^master_forks_slaves " \
         "master_forks_slaves    FALSE"
   done

   # JOB CLASSES
   if [ -d "$working_dir/jobclasses" ]; then
      for item in `ls -1 $working_dir/jobclasses`; do
         # add masterl attribute (new in 8.2.0)
         AddLineIfNotExisting "$working_dir/jobclasses/$item" "^masterl " \
            "masterl         {+}UNSPECIFIED"
         # add rou attribute (new in 8.2.0)
         AddLineIfNotExisting "$working_dir/jobclasses/$item" "^rou " \
            "rou             {+}UNSPECIFIED"
         # add tc attribute (new in 8.2.0)
         AddLineIfNotExisting "$working_dir/jobclasses/$item" "^tc " \
            "tc              {+}UNSPECIFIED"
      done
   fi

   # ACCOUNTING FILE
   # This file already was copied over to $SGE_ROOT, so modify it there
   # multiply all timestamps by 1000 (since 8.2.0, it's all in milliseconds)
   acc_file_orig="$ROOTDIR/$CELLDIR/common/accounting"
   acc_file_mod="$working_dir/accounting.mod"
   if [ -f "$acc_file_orig" ]; then
      # create an empty .mod file
      touch "$acc_file_mod"

      # get version from accounting file comment
      # if there is no version in the accounting file
      # use the version from saved config
      version=`grep "^# Version: " "$acc_file_orig" | cut -d":" -f 2`
      if [ "$version" = "" ]; then
         version=`cat ${working_dir}/version`
      else
         version="UGE $version"
      fi
      result=`CompareVersions "$version" "UGE 8.2.0"`
      if [ $result -lt 0 ]; then
         # the accounting file is from an older version
         # we have to multiply all times by 1000
         echo "# Version: 8.2.0" >> "$acc_file_mod"
         while read line; do
            # just copy other comments
            echo $line | grep "^#" > /dev/null 2>&1
            if [ $? -eq 0 ]; then
               echo $line >> "$acc_file_mod"
               continue
            fi

            # everything else must be data lines

            # modify all time stamps in all data lines
            i=1
            do_loop=true
            while [ "$do_loop" = "true" ]; do
               # get next field from line
               string=`echo $line | cut -d":" -f $i`

               if [ -z "$string" ]; then
                  # we exceeded the last field
                  do_loop=false
                  # append "\n" to the end of the line
                  echo "" >> "$acc_file_mod"
                  continue
               elif [ $i -gt 1 ]; then
                  # append ":" to what we wrote last loop
                  echo -n ":" >> "$acc_file_mod"
               fi

               # time stamps are in fields 9, 10, 11 and 28
               if [ $i -eq 9 -o $i -eq 10 -o $i -eq 11 -o $i -eq 28 ]; then
                  ms_value=`expr $string \* 1000`
                  echo -n "$ms_value" >> "$acc_file_mod"
               else
                  # for all other fields, just copy the string
                  echo -n "$string" >> "$acc_file_mod"
               fi

               i=`expr $i + 1`
            done
         done < "$acc_file_orig"

         ExecuteAsAdmin cp "$acc_file_mod" "$acc_file_orig"
         ExecuteAsAdmin chmod 644 "$acc_file_orig"
      fi
   fi

   # update version file
   echo "UGE 8.2.0" > ${working_dir}/version
}

UpdateSchedulerConfigurationTo830()
{
   working_dir="${1:?Missing working dir parameter}"

   egrep -i "SHARETREE_RESERVED_USAGE=1|SHARETREE_RESERVED_USAGE=TRUE" "$working_dir/configurations/global" >/dev/null 2>&1
   if [ $? -eq 0 ]; then
      has_reserved_usage=1
   else
      has_reserved_usage=0
   fi

   usage_weight_list=`grep "^usage_weight_list" "$working_dir/schedconf"`
   if [ $? -ne 0 ]; then
      # usage_weight_list missing? Add a correct one.
      if [ $has_reserved_usage -eq 1 ]; then
         new_usage_weight_list="wallclock=1.0, cpu=0.0, mem=0.0, io=0.0"
      else
         new_usage_weight_list="wallclock=0.0, cpu=1.0, mem=0.0, io=0.0"
      fi
   else
      values=`echo $usage_weight_list | cut -f 2- -d " "`
      cpu=0.0
      mem=0.0
      io=0.0
      OLD_IFS="$IFS"
      IFS=", "
      for i in $values; do
         name=`echo $i | cut -f 1 -d =`
         value=`echo $i | cut -f 2 -d =`
         eval $name=$value
      done
      IFS="$OLD_IFS"
      if [ $has_reserved_usage -eq 1 ]; then
         new_usage_weight_list="wallclock=$cpu, cpu=0.0, mem=$mem, io=$io"
      else
         new_usage_weight_list="wallclock=0.0, cpu=$cpu, mem=$mem, io=$io"
      fi
   fi

   ReplaceOrAddLine "$working_dir/schedconf" "usage_weight_list .*" "usage_weight_list $new_usage_weight_list"
}

UpgradeConfigTo830()
{
   working_dir="${1:?Missing working dir parameter}"

   echo "Upgrading config to UGE 8.3.0"

   # CENTRY CONFIG
   # add aapre-attribute (available after preemption) if missing (new in 8.3.0)
   cat $working_dir/centry | while read line
   do
      # skip comments (lines that start with hash-character
      if [ `echo "$line" | cut -c 1` = "#" ]; then
         continue
      fi

      # skip lines that do not have 8 words
      if [ `echo "$line" | wc -w` -ne 8 ]; then
         continue
      fi

      # find out if we have to add TRUE or FALSE for the aapre-attribute
      attribute=`echo "$line" | awk '{print $1;}'`
      consumable=`echo "$line" | awk '{print $6;}'`
      if [ "$attribute" = "slots" -o $consumable != "NO" ]; then
         boolean_to_add="TRUE"
      else
         boolean_to_add="FALSE"
      fi

      # replace the existing line
      ReplaceOrAddLine "$working_dir/centry" "^${attribute} .*" "$line $boolean_to_add"
   done

   # RESERVED USAGE
   # we removed execd params
   #  * ACCT_RESERVED_USAGE
   #  * SHARETREE_RESERVED_USAGE
   #  * ENABLE_REAL_CPU
   #  * ENABLE_REAL_MEM
   # we added wallclock to the schedd_config:usage_weight_list
   UpdateSchedulerConfigurationTo830 "$working_dir"
   for i in `ls -1 $working_dir/configurations`; do
      RemoveAttribute "$working_dir/configurations/$i" "execd_params" "_RESERVED_USAGE" "NONE"
      RemoveAttribute "$working_dir/configurations/$i" "execd_params" "ENABLE_REAL_" "NONE"
   done

   # changes to the exec host object, added lines
   #  * license_constraints
   #  * license_oversubscription
   for i in `ls -1 $working_dir/execution`; do
      AddLineIfNotExisting "$working_dir/execution/$i" "^license_constraints" "license_constraints NONE"
      AddLineIfNotExisting "$working_dir/execution/$i" "^license_oversubscription" "license_oversubscription NONE"
   done

   # SCHEDULER CONFIG
   # add preemption related parameters (new in 8.3.0)
   AddLineIfNotExisting "$working_dir/schedconf" "^prioritize_preemptees"           "prioritize_preemptees TRUE"
   AddLineIfNotExisting "$working_dir/schedconf" "^preemptees_keep_resources"       "preemptees_keep_resources FALSE"
   AddLineIfNotExisting "$working_dir/schedconf" "^max_preemptees"                  "max_preemptees 0"
   AddLineIfNotExisting "$working_dir/schedconf" "^preemption_distance"             "preemption_distance 00:15:00"
   AddLineIfNotExisting "$working_dir/schedconf" "^preemption_priority_adjustments" "preemption_priority_adjustments NONE"

   # update version file
   echo "UGE 8.3.0" > ${working_dir}/version
}

UpgradeConfigTo840()
{
   working_dir="${1:?Missing working dir parameter}"

   echo "Upgrading config to UGE 8.4.0"

   # add docker and docker_images if missing (new in 8.4.0 / former 8.3.2)
   AddLineIfNotExisting "$working_dir/centry" "^docker " \
      "docker              dock       BOOL        ==    YES         NO         0        0       NO"
   AddLineIfNotExisting "$working_dir/centry" "^docker_images " \
      "docker_images       dockimg    RESTRING    ==    YES         NO         NONE     0       NO"

   # update version file
   echo "UGE 8.4.0" > ${working_dir}/version
}

# TODO: Not all config values really have to be set in all versions! Clean this up!
UpgradeConfigAllVersions()
{
   working_dir="${1:?Missing working dir parameter}"

   # EXECUTION HOST CONFIG
   for item in `ls -1 $working_dir/execution`; do
      # the execution daemon has to fill these lines from the load sensor
      RemoveLineWithMatch ${working_dir}/execution/$item 'load_values.*'
      RemoveLineWithMatch ${working_dir}/execution/$item 'processors.*'
   done

   # GLOBAL/LOCAL CONFIG
   for item in `ls -1 $working_dir/configurations`; do
      modFile="$working_dir/configurations/$item"

      if [ "$item" = "global" ]; then
         if [ -n "$EXECD_SPOOL_DIR" ]; then
            ReplaceOrAddLine ${modFile} 'execd_spool_dir.*'     "execd_spool_dir              $EXECD_SPOOL_DIR"
         fi
         if [ -n "$GID_RANGE" ]; then
            ReplaceOrAddLine ${modFile} 'gid_range.*'     "gid_range              $GID_RANGE"
         fi
         if [ -n "$ADMIN_MAIL" ]; then
            ReplaceOrAddLine ${modFile} 'administrator_mail.*'     "administrator_mail              $ADMIN_MAIL"
         fi

         if [ "$newIJS" = true ]; then # new IJS settings
            ReplaceOrAddLine ${modFile} 'qlogin_command.*' "qlogin_command               builtin"
            ReplaceOrAddLine ${modFile} 'qlogin_daemon.*'  "qlogin_daemon                builtin"

            ReplaceOrAddLine ${modFile} 'rlogin_command.*' "rlogin_command               builtin"
            ReplaceOrAddLine ${modFile} 'rlogin_daemon.*'  "rlogin_daemon                builtin"

            ReplaceOrAddLine ${modFile} 'rsh_command.*'    "rsh_command                  builtin"
            ReplaceOrAddLine ${modFile} 'rsh_daemon.*'     "rsh_daemon                   builtin"
         fi

         if [ "$SGE_ENABLE_JMX" = "true" -a "$SGE_JVM_LIB_PATH" != "" ]; then
            ReplaceOrAddLine ${modFile} 'libjvm_path.*'            "libjvm_path                  $SGE_JVM_LIB_PATH"
         fi
         if [ "$SGE_ENABLE_JMX" = "true" -a "$SGE_ADDITIONAL_JVM_ARGS" != "" ]; then
            ReplaceOrAddLine ${modFile} 'additional_jvm_args.*'    "additional_jvm_args          $SGE_ADDITIONAL_JVM_ARGS"
         fi
      else
         # LOCAL configurations
         if [ "$newIJS" = true ]; then # new IJS settings
            RemoveLineWithMatch ${modFile} 'qlogin_command.*'
            RemoveLineWithMatch ${modFile} 'qlogin_daemon.*'

            RemoveLineWithMatch ${modFile} 'rlogin_command.*'
            RemoveLineWithMatch ${modFile} 'rlogin_daemon.*'

            RemoveLineWithMatch ${modFile} 'rsh_command.*'
            RemoveLineWithMatch ${modFile} 'rsh_daemon.*'
         fi
         #We need to change local execd spool dirs for copy mode
         if [ "$mode" = copy ]; then
            local_dir=`grep execd_spool_dir ${modFile} 2>/dev/null | awk '{print $2}'`
            if [ -n "$local_dir" ]; then
               local_dir=`dirname $local_dir 2>/dev/null`
               if [ -n "$local_dir" ]; then
                  if [ -n "$SGE_CLUSTER_NAME" ]; then
                     local_dir="${local_dir}/${SGE_CLUSTER_NAME}"
                  elif [ -n "$SGE_QMASTER_PORT" ]; then
                     local_dir="${local_dir}/${SGE_QMASTER_PORT}"
                  else
                     local_dir="${local_dir}/${CELLDIR}"
                  fi
                  ReplaceOrAddLine ${modFile} 'execd_spool_dir.*'  "execd_spool_dir                $local_dir"
               fi
            fi
         fi
      fi
   done
}

##
# @brief update the configuration to the current version
#
# Update the saved cofiguration step by step up to the current version.
# The configuration is iteratively updated to the next version until the
# current version is reached. This update is done between all configuration
# versions, not necessarily between all Grid Engine versions, which might
# share the same configuration version.
#
# If a new Grid Engine version is to be supported, add a new entry to the
# "version_map" variable. A new upgrade subfunction is necessary only if
# also the configuration version changes.
#
# @param[in]  Directory of the saved configuration. It is recommended to copy
#             the saved configuration and provide the path to the copy.
#
# @returns nothing
#
UpgradeConfig()
{
   working_dir="${1:?Missing working dir parameter}"

   current_version=`cat ${working_dir}/version`

   result=`CompareVersions "${current_version}" "SGE 6.2u5"`
   if [ $result -lt 0 ]; then
      UpgradeConfigTo62u5 "$working_dir"
      current_version=`cat ${working_dir}/version`
   fi

   result=`CompareVersions "${current_version}" "UGE 8.0.0"`
   if [ $result -lt 0 ]; then
      UpgradeConfigTo800 "$working_dir"
      current_version=`cat ${working_dir}/version`
   fi

   result=`CompareVersions "${current_version}" "UGE 8.1.0"`
   if [ $result -lt 0 ]; then
      UpgradeConfigTo810 "$working_dir"
      current_version=`cat ${working_dir}/version`
   fi

   result=`CompareVersions "${current_version}" "UGE 8.1.5"`
   if [ $result -lt 0 ]; then
      UpgradeConfigTo815 "$working_dir"
      current_version=`cat ${working_dir}/version`
   fi

   result=`CompareVersions "${current_version}" "UGE 8.1.7"`
   if [ $result -lt 0 ]; then
      UpgradeConfigTo817 "$working_dir"
      current_version=`cat ${working_dir}/version`
   fi

   result=`CompareVersions "${current_version}" "UGE 8.2.0"`
   if [ $result -lt 0 ]; then
      UpgradeConfigTo820 "$working_dir"
      current_version=`cat ${working_dir}/version`
   fi

   result=`CompareVersions "${current_version}" "UGE 8.3.0"`
   if [ $result -lt 0 ]; then
      UpgradeConfigTo830 "$working_dir"
      current_version=`cat ${working_dir}/version`
   fi

   result=`CompareVersions "${current_version}" "UGE 8.4.0"`
   if [ $result -lt 0 ]; then
      UpgradeConfigTo840 "$working_dir"
      current_version=`cat ${working_dir}/version`
   fi

   # this should always be the last one
   UpgradeConfigAllVersions "$working_dir"
}

########
# MAIN #
########
if [ "$1" = -help -o $# -eq 0 ]; then
   Usage
   exit 0
fi

DIR="${1:?The backup directory is required}"
LOG_FILE_NAME="${2:?A log file path and name is required}"

shift 2

ARGC=$#
while [ $ARGC -gt 0 ]; do
   case $1 in
      -log)
         shift
         if [ "$1" != "C" -a "$1" != "W" -a "$1" != "I" ]; then
            LogIt "W" "UPGRADE invoked with invalid log level "$1" using W"
         else
            LOGGER_LEVEL="$1"
         fi
         ;;
      -mode)
         shift
         if [ "$1" != "upgrade" -a "$1" != "copy" ]; then
            LogIt "W" "UPGRADE invoked with invalid mode "$1" using $mode"
         else
            LogIt "I" "UPGRADE invoked with -mode $1"
            mode="$1"
         fi
         ;;
      -newijs)
         shift
         if [ "$1" != "true" -a "$1" != "false" ]; then
            LogIt "W" "UPGRADE invoked with invalid newijs "$1" using $newIJS"
         else
            LogIt "I" "UPGRADE invoked with -newijs true"
            newIJS="$1"
         fi
         ;;
      -execd_spool_dir)
         shift
         LogIt "I" "UPGRADE invoked with -execd_spool_dir $1"
         EXECD_SPOOL_DIR="$1"
         ;;
      -admin_mail)
         shift
         LogIt "I" "UPGRADE invoked with -admin_mail $1"
         ADMIN_MAIL="$1"
         ;;
      -gid_range)
         shift
         LogIt "I" "UPGRADE invoked with -gid_range $1"
         GID_RANGE="$1"
         ;;
   esac
   ARGC=`expr $ARGC - 2`
   shift
done

CURRENT_VERSION=`$QCONF -help | sed  -n '1,1 p'` 2>&1
if [ $? -ne 0 ]; then
   LogIt "C" "$QCONF_NAME -help failed"
   LogIt "C" "$QMASTER_NAME is not installed"
   EXIT 1
fi
admin_hosts=`$QCONF -sh 2>/dev/null`
if [ -z "$admin_hosts" ]; then
   $INFOTEXT "ERROR: $QCONF_NAME -sh failed. Qmaster is probably not running?"
   LogIt "C" "$QMASTER_NAME is not running"
   EXIT 1
fi
tmp_adminhost=`$QCONF -sh | grep "^${HOST}$" 2>/dev/null`
if [ "$tmp_adminhost" != "$HOST" ]; then
   $INFOTEXT "ERROR: Load must be started on admin host ($QMASTER_NAME host recommended)."
   LogIt "C" "Can't start load_${PRODUCT_SHORTCUT}_config.sh on $HOST: not an admin host"
   EXIT 1
fi


LogIt "I" "Upgrading saved cluster configuration in ${DIR} to version $CURRENT_VERSION"
UpgradeConfig "${DIR}" $CURRENT_VERSION

LogIt "I" "Finished upgrading"
EXIT 0
