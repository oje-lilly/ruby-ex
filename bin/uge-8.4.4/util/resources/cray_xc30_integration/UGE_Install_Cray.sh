#!/bin/bash
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

##
# This function installs a complex when it does not exist yet.
# Requires two parameters: 
#    - $1 is the complex name $2 is complex config line.
#
function install_complex
{
   local complex_name=$1
   local complex_config=$2
   local complex_installed=$(qconf -sc | grep -c "$complex_name")

   local output=""

   if [ "$complex_installed" -eq "0" ]; then
      echo "Adding complex \"$complex_name\" to the complex configuration."
      qconf -sc > /tmp/complex_config.$$
      # Cray requests should always be on top of the list
      # hence they have a high resource urgency.
      echo "$complex_config" >> /tmp/complex_config.$$
      output=$(qconf -Mc /tmp/complex_config.$$ 2>&1)
      if [ $? -ne 0 ]; then
         echo "Adding complex \"$1\" failed: $output"
      else
         echo "Successfully added complex \"$1\"."
      fi
      rm -f /tmp/complex_config.$$
   else
      echo "The complex \"$complex_name\" already exists."
   fi
}

##
# Add a new or replace an existing entry to an UGE config file
#
# Add a new config entry or replace an existing one in a UGE config file. If the entry already
# exists, the full entry (i.e. the whole line) is replaced. Otherwise the new entry is appended to
# the end.
# An UGE config file is created by redirecting the output of a "qconf -s*" command to a file. The
# lines in the config file must not be wrapped, set the "SGE_SINGLE_LINE=1" environment variable to
# ensure this.
#
# Example 1: Replace the full "execd_params" list with "KEEP_ACTIVE=TRUE":
#   env SGE_SINGLE_LINE=1 qconf -sconf > /tmp/global
#   add_or_replace_entry_in_config_file "/tmp/global" "execd_params" "KEEP_ACTIVE=TRUE"
#   qconf -Mconf /tmp/global
#
# Example 2: Replace the configured PE list with the three PEs "mype", "yourpe" and "ourpe":
#   env SGE_SINGLE_LINE=1 qconf -sconf > /tmp/global
#   add_or_replace_entry_in_config_file "/tmp/global" "pe_list" "mype,yourpe,ourpe"
#   qconf -Mconf /tmp/global
#
# Example 3: Add a new config entry to the configuration:
#   env SGE_SINGLE_LINE=1 qconf -sconf myhost > /tmp/myhost
#   add_or_replace_entry_in_config_file "/tmp/myhost" "new_config" "myconfigvalue"
#   qconf -Mconf /tmp/myhost
#
# Parameters:
# $1 config_file   Name of the file that contains the config
# $2 config_name   e.g. "prolog" or "qmaster_params"
# $3 config_value  e.g. "/path/to/prolog.sh arg1 arg2 arg3"
#
function add_or_replace_entry_in_config_file
{
   if [ $# -ne 3 ]; then
      echo "invalid number of arguments!"
      return 1
   else
      local config_file=$1
      local config_name=$2
      local config_value=$3

      local found_config_name=0

      # read the whole file to an array of lines
      declare -a file_content
      if [ -e "$config_file" ]; then
         while IFS= read -r line; do
            file_content=("${file_content[@]}" "$line")
         done < "$config_file"
      fi

      # search the whole config file for the $config_name
      for (( line_nr = 0; line_nr < ${#file_content[@]}; line_nr++ )); do
         # check if line starts with $config_name
         echo "${file_content[$line_nr]}" | awk '{print $1;}' | grep "$config_name" > /dev/null
         if [ $? -ne 0 -a $found_config_name -eq 0 ]; then
            continue
         fi

         # obviously we found the line with $config_name
         found_config_name=1
         break
      done

      if [ $found_config_name -eq 0 ]; then
         # if we didn't find the line, append it
         line_nr=$((line_nr + 1))
      fi
      # replace the found line or append a newa new  line
      file_content[$line_nr]="$config_name $config_value"

      # write the array to the file again
      printf "%s\n" "${file_content[@]}" > "$config_file"
   fi
   return 0
}

##
# Add a new or modify a list value to an UGE config file
#
# Add a new list with the given key-value pair to a config file, add a new key-value pair to an
# existing list or modify the existing value of an existing key in an existing list in an UGE
# config file.
# An UGE config file is created by redirecting the output of a "qconf -s*" command to a file. The
# lines in the config file must not be wrapped, set the "SGE_SINGLE_LINE=1" environment variable to
# ensure this.
#
# Example 1: Add a new list to the global configuration:
#   env SGE_SINGLE_LINE=1 qconf -sconf > /tmp/global
#   add_or_modify_config_list_value "/tmp/global" "my_personal_list" "my_key" "my_value"
#   qconf -Mconf /tmp/global
# creates the entry "my_personal_list my_key=my_value"
#
# Example 2: Add a new key-value pair to an existing list in the global configuration:
#   env SGE_SINGLE_LINE=1 qconf -sconf > /tmp/global
#   add_or_modify_config_list_value "/tmp/global" "qmaster_params" "ENABLE_FORCED_QDEL" "1"
#   qconf -Mconf /tmp/global
# adds "ENABLE_FORCED_QDEL=1" to the "qmaster_params". If "qmaster_params" was set to "none"
# before, "none" is removed.
#
# Example 3: Modify an existing value in the global configuration:
#   env SGE_SINGLE_LINE=1 qconf -sconf > /tmp/global
#   add_or_modify_config_list_value "/tmp/global" "execd_params" "KEEP_ACTIVE" "TRUE"
#   qconf -Mconf /tmp/global
# modifies "KEEP_ACTIVE" from "ERROR" to "TRUE".
#
# $1 config_file   Name of the file that contains the config
# $2 config_name   e.g. "execd_params" or "qmaster_params"
# $3 config_key    e.g. "KEEP_ACTIVE"
# $4 config_value  e.g. "ALWAYS"
#
function add_or_modify_config_list_value
{
   if [ $# -ne 4 ]; then
      echo "invalid number of arguments!"
      return 1
   else
      local config_file=$1
      local config_name=$2
      local config_key=$3
      local config_value=$4

      local found_config_name=0

      # read the whole file to an array of lines
      declare -a file_content
      if [ -e "$config_file" ]; then
         while IFS= read -r line; do
            file_content=("${file_content[@]}" "$line")
         done < "$config_file"
      fi
      # search the whole config file for the $config_name
      for (( line_nr = 0; line_nr < ${#file_content[@]}; line_nr++ )); do
         # check if line starts with $config_name
         echo "${file_content[$line_nr]}" | awk '{print $1;}' | \
              grep -F "$config_name" > /dev/null 2>&1
         if [ $? -eq 0 ]; then
            local line=""

            # obviously we found the line with $config_name
            found_config_name=1

            # strip the config_name from the line
            line=$(echo "${file_content[$line_nr]}" | cut -d" " -f2-)
            # trim white spaces from start and end of line
            line=$(echo "$line" | awk '{$1=$1;print}')
            if [ "$line" = "none" -o "$line" = "NONE" ]; then
               # no entry yet in this config? just replace it
               file_content[$line_nr]="$config_name $config_key=$config_value"
            else
               # there is a config list, does it already contain our config_key?
               echo "$line" | grep -F "$config_key" > /dev/null 2>&1
               if [ $? -ne 0 ]; then
                  # it doesn't contain our config_key, so we can just append it
                  file_content[$line_nr]="$config_name $line,$config_key=$config_value"
               else
                  declare -a fields

                  # the config_key is already part of the list, replace it

                  # split the line in key-value pairs, i.e. "A=1,B=2,C=3" -> "A=1" "B=2" "C=3"
                  line=$(echo "$line" | tr ',' ' ')
                  fields=(${line})

                  # find the key-value pair that contains our config_key
                  for (( i = 0; i < ${#fields[@]}; i++ )); do
                     echo "${fields[$i]}" | grep "^$config_key" > /dev/null 2>&1
                     if [ $? -eq 0 ]; then
                        # replace with new value
                        fields[$i]="$config_key=$config_value"
                        # build one line from the array
                        line="${fields[*]}"
                        # replace the line in the array with this line
                        file_content[$line_nr]="$config_name $line"
                        break
                     fi
                  done
               fi
            fi

            # we changed the line we were looking for, so we can stop now
            break
         fi
      done < <(echo "${file_content[@]}")
      if [ $found_config_name -eq 0 ]; then
         # the config_name is not part of this config yet, just add it
         file_content[${#file_content[@]}]="$config_name $config_key=$config_value"
      fi

      # the array was already changed, so simply write it to the config file
      printf "%s\n" "${file_content[@]}" > "$config_file"
   fi
   return 0
}

##
# Add or replace the machine specific values in the UGE_JSV.tcl script
#
# If it doesn't exist yet, this function creates the UGE_JSV.tcl JSV script from the template. It
# then checks if the machine specific values for the current machine name already exist in the
# UGE_JSV.tcl script. If yes, these values are deleted.
# Then, new values for the current machine name are added to the UGE_JSV.tcl script.
#
# The machine specific values are
#    cores_per_host
#    cores_per_NUMA_node
#    NUMA_nodes_per_host
# each of them postfixed by an underscore (_) and the machine name, if this name is given.
#
# $1 jsv_script     Name of the file that contains the config
# $2 postfix        Machine name, an empty string if none is defined
# $3 cores_per_host Number of cores on this host
# $4 cores_per_node Number of cores per NUMA node on this host
# $5 numa_nodes     Number of NUMA nodes on this host
#
function add_or_replace_machine_specific_values_in_jsv
{
   if [ $# -ne 5 ]; then
      echo "invalid number of arguments!"
      return 1
   else
      local jsv_script=$1
      local postfix=$2
      local cores_per_host=$3
      local cores_per_node=$4
      local numa_nodes=$5

      # read the whole file to an array of lines
      declare -a file_content
      if [ -e "$jsv_script" ]; then
         while IFS= read -r line; do
            file_content=("${file_content[@]}" "$line")
         done < "$jsv_script"
      fi

      # Search for the start mark, then search until the end mark if the values for the current
      # machine name already exist. If yes, delete them.
      local start_mark_line=-1
      local end_mark_line=-1
      for (( line_nr=0; line_nr < ${#file_content[@]}; line_nr++ )); do
         echo "${file_content[$line_nr]}" | grep "START HOST SPECIFIC VALUES" >/dev/null 2>&1
         if [ $? -eq 0 ]; then
            # we found the start mark
            start_mark_line="$line_nr"
         fi
         echo "${file_content[$line_nr]}" | grep "END HOST SPECIFIC VALUES" >/dev/null 2>&1
         if [ $? -eq 0 ]; then
            # we found the start mark
            end_mark_line="$line_nr"
            break
         fi
         if [ $start_mark_line -ne -1 ]; then
            # we already found the start mark, now search for the values
            echo "${file_content[$line_nr]}" | \
                 grep "set cores_per_host${postfix} .*" >/dev/null 2>&1
            local res1="$?"
            echo "${file_content[$line_nr]}" | \
                 grep "set cores_per_NUMA_node${postfix} .*" >/dev/null 2>&1
            local res2="$?"
            echo "${file_content[$line_nr]}" | \
                 grep "set NUMA_nodes_per_host${postfix} .*" >/dev/null 2>&1
            local res3="$?"
            if [ "$res1" -eq "0" -o "$res2" -eq "0" -o "$res3" -eq "0" ]; then
               # remove this line
               file_content=("${file_content[@]:0:$line_nr}" \
                             "${file_content[@]:$((line_nr + 1))}")
               # decrease the index, so the next for round will set it to the new next line
               line_nr=$((line_nr - 1))
            fi
         fi
      done

      if [ "$end_mark_line" -eq "-1" ]; then
         echo "didn't find end mark in $jsv_script, can't modify it properly!"
      else
         # Add new values before the end mark
         local insert_line=$((start_mark_line+1))
         local new_line[0]="   set cores_per_host${postfix} $cores_per_host"
         local new_line[1]="   set cores_per_NUMA_node${postfix} $cores_per_node"
         local new_line[2]="   set NUMA_nodes_per_host${postfix} $numa_nodes"
         for (( i=$((${#new_line[@]}-1)); i>=0; i-- )) do
            file_content=("${file_content[@]:0:$insert_line}" "${new_line[$i]}" \
                          "${file_content[@]:$insert_line}")
         done
      fi

      # write the array to the file again
      printf "%s\n" "${file_content[@]}" > "$jsv_script"
   fi
   return 0
}


##############
# MAIN
##############

ARGC=$#

# parse command line arguments, see help output
if [ "$ARGC" -ge "1" ]; then
   while [ "$ARGC" -gt "0" ]; do
      case "$1" in
         -help)
            echo "$(basename "$0") [-help|-name <machine name>]"
            echo "-help                  prints this help output"
            echo "-name <machine name>   give this Cray machine a name - the whole machine, not"
            echo "                       this login node. This name is appended to all UGE"
            echo "                       objects that are created for this Cray machine to allow"
            echo "                       to distinguish it from other Cray machines"
            echo ""
            exit 0
            ;;
         -name)
            if [ "$ARGC" -gt "1" ]; then
               MACHINE_NAME="$2"
            else
               echo "missing machine name argument of \"-name\" switch!"
               exit 1
            fi
            # skip "-name" and the machine name
            shift 2
            ARGC=$((ARGC-2))
            ;;
         *)
            echo "Got unknown command line argument $1!"
            exit 1
            ;;
      esac
   done
fi

# source UGE settings (SGE_ROOT / SGE_CELL  must be set)
if [ "$SGE_ROOT" == "" -o "$SGE_CELL" == "" ]; then
   echo "\$SGE_ROOT or \$SGE_CELL is not set! Please source UGE settings."
   exit 1
fi

source "$SGE_ROOT/$SGE_CELL/common/settings.sh"
integration_path=./

if [ -f "$integration_path/cray_settings.sh" ]; then
   # Check if the path in cray_settings.sh was updated by the admin!
   length=$(grep "export PATH" "$integration_path/cray_settings.sh" | wc -c)
   if [ $length -lt 20 ]; then
      echo "Please update PATH in ./cray_settings.sh!"
      exit 1
   fi
   source "$integration_path/cray_settings.sh"
else
   echo "Please call the installation script from the cray_xc30_integration directory!"
   exit 1
fi

# pre-check: The filesystem needs to be writable.
touch ./fs.test
if [ $? -ne 0 ]; then
   echo "Filesystem not writable by the current user. Please switch"
   echo "to an UGE admin user which is allowed to write in the current"
   echo "directory."
   exit 1
fi
rm -f ./fs.test

# check if configuration is consistent
architecture=$("$integration_path/CrayBasil.py" --nodes)
# return code does not indicate inconsistency
if [ $? -ne 0 ]; then
   echo "Abort installation. Cray XC-30 configuration is not consistent."
   echo "CrayBasil --nodes returned:"
   echo "$architecture"
fi

# --------------------------------------------------------------------
# Maybe not all login nodes are used as Grid Engine execution hosts.
# Hence it is required to get this information from the administrator.
# --------------------------------------------------------------------
echo "Please provide the login nodes of the Cray XC30 system,"
echo "which should be used to run Univa Grid Engine jobs."
echo "They need to be registered as UGE execution daemons already."
echo "Specify the list of nodes as space separated strings."
echo "Use CTRL+C in order to abort installation"
echo 
echo "Cray Login Nodes: "
read list

# convert list to array
login_node_list=( $list )
login_node_list_length=${#login_node_list[@]}
# check if at least one login node was provided
if [ ${login_node_list_length} -le 0 ]; then
   echo "No login nodes specified. Aborting."
   exit 1
fi

echo "Using following Cray login nodes: ${login_node_list[@]}"
echo "Press enter to continue."
read x

if [ -n "$MACHINE_NAME" ]; then
   postfix="_${MACHINE_NAME}"
else
   postfix=""
fi

# ----------------------------------------------
# Create the resources when they don't exist yet
# ----------------------------------------------
echo "Installing the complex values"
echo "-----------------------------"
install_complex "cray_nodes${postfix}"          "cray_nodes${postfix}          cn${postfix}     INT      <= YES YES 0 100000"
install_complex "cray_alps_version${postfix}"   "cray_alps_version${postfix}   calps${postfix}  RESTRING == NO NO NONE 0"
install_complex "cray_basil_version${postfix}"  "cray_basil_version${postfix}  cbasil${postfix} RESTRING == NO NO NONE 0"
install_complex "cray_cores_per_host${postfix}" "cray_cores_per_host${postfix} ccph${postfix}   INT      <= NO NO 0 0"
install_complex "cray_numa_nodes${postfix}"     "cray_numa_nodes${postfix}     cnn${postfix}    INT      <= NO NO 0 0"
# Those architecture resources must be consumables otherwise SGE_HGR_ is not in env
install_complex "mppwidth${postfix}"            "mppwidth${postfix}            mwidth${postfix} INT      <= YES JOB 0 0"
install_complex "mppdepth${postfix}"            "mppdepth${postfix}            mdepth${postfix} INT      <= YES JOB 0 0"
install_complex "mppnppn${postfix}"             "mppnppn${postfix}             mppn${postfix}   INT      <= YES JOB 0 0"
# Guard that protects non-Cray jobs from beeing scheduled to cray.q
#  - no need to postfix it, this one can be used for all cray queues.
install_complex "cray_forced"                   "cray_forced         cf     INT      >= FORCED NO 0 0"
echo ""

# --------------------
# Initialize resources
# --------------------
cray_alps_version=$("$integration_path/CrayBasil.py" --alps)
cray_basil_version=$("$integration_path/CrayBasil.py" --basil)
architecture=$("$integration_path/CrayBasil.py" --nodes)
if [ $? != 0 ]; then
   echo "Error. The Cray XC30 system needs to have a homogeneous architecture."
   echo "Please reconfigure Cray cluster so that all BATCH nodes have the"
   echo "same architecture (xtprocadmin tool)."
   exit 1
fi

nodes=$(echo "$architecture" | cut -f1 -d",")
numa_nodes=$(echo "$architecture" | cut -f2 -d",")
cores_per_node=$(echo "$architecture" | cut -f3 -d",")
cores_per_host=$((numa_nodes * cores_per_node))

echo "Initialize resources in global configuration"
echo "--------------------------------------------"
# Initialize the cray_nodes resource on global level. This is needed
# when you have more than one login nodes. Therefore it is required
# for the job to request a login node -> login_node

# The ALPS version installed on the Cray machine.
qconf -mattr exechost complex_values "cray_alps_version${postfix}=$cray_alps_version" global
# The BASIL version installed on the Cray machine.
qconf -mattr exechost complex_values "cray_basil_version${postfix}=$cray_basil_version" global
# Amount of available Cray nodes. A Cray node is always used exclusively.
qconf -mattr exechost complex_values "cray_nodes${postfix}=$nodes" global
# Amount of core per host of the homogeneous Cray machine
qconf -mattr exechost complex_values "cray_cores_per_host${postfix}=$cores_per_host" global
# Amount of NUMA nodes per host of the homogeneous Cray machine
qconf -mattr exechost complex_values "cray_numa_nodes${postfix}=$numa_nodes" global
# Amount of processing elements (PEs) used for the job
qconf -mattr exechost complex_values "mppwidth${postfix}=1000000" global
# Amount of cores per processing element
qconf -mattr exechost complex_values "mppdepth${postfix}=1000000" global
# Processing elements per execution host
qconf -mattr exechost complex_values "mppnppn${postfix}=1000000" global
echo ""

# Initialize the login_nodes host group
echo "Creating or modifying login node host list"
echo "------------------------------------------"

hostgroup_tmpfile="/tmp/cray_login_nodes${postfix}.$$"
hostgroup_name="@login_nodes${postfix}"
echo "group_name $hostgroup_name" > "$hostgroup_tmpfile"
echo "hostlist ${login_node_list[@]}" >> "$hostgroup_tmpfile"
echo "Adding host group \"$hostgroup_name\""
output=$(qconf -Ahgrp "$hostgroup_tmpfile" 2>&1)
if [ $? -ne 0 ]; then
   echo "$output" | grep "already exists" > /dev/null 2>&1
   if [ $? -ne 0 ]; then
      echo "Adding host group \"$hostgroup_name\" failed. Output was: $output"
   else
      echo "Host group \"$hostgroup_name\" already exists. Adding login node list."
      output=$(qconf -mattr hostgroup hostlist "${login_node_list[@]}" "@login_nodes${postfix}" 2>&1)
      if [ $? -ne 0 ]; then
         echo "Adding login node list failed: $output"
      else
         echo "Successfully added login node list."
      fi
   fi
else
   echo "Successfully added host group \"$hostgroup_name\"."
fi
rm "$hostgroup_tmpfile"
echo ""

# Set for each execution daemon the CRAY_XC30_LOGIN_NODE=1 execd_param
echo "Adding CRAY_XC30_LOGIN_NODE=1 to the \"execd_params\" of the execution daemon of each login node."
for node in "${login_node_list[@]}"; do
   node_tmpfile="/tmp/$node"
   env SGE_SINGLE_LINE=1 qconf -sconf $node > "$node_tmpfile"
   add_or_modify_config_list_value "$node_tmpfile" "execd_params" "CRAY_XC30_LOGIN_NODE" "1"
   output=$(qconf -Mconf "$node_tmpfile" 2>&1)
   if [ $? -ne 0 ]; then
      echo "Adding CRAY_XC30_LOGIN_NODE=1 to the \"execd_params\" of login node \"$node\" failed:"
      echo "$output"
   else
      echo "Successfully added CRAY_XC30_LOGIN_NODE=1 to the \"execd_params\" of the execution"
      echo "daemon of login node \"$node\"."
   fi

   add_or_modify_config_list_value "$node_tmpfile" "execd_params" "SCRIPT_TIMEOUT" "01:00:00"
   output=$(qconf -Mconf "$node_tmpfile" 2>&1)
   if [ $? -ne 0 ]; then
      echo "Adding SCRIPT_TIMEOUT=00:30:00 to the \"execd_params\" of login node \"$node\" failed:"
      echo "$output"
   else
      echo "Successfully added SCRIPT_TIMEOUT=01:00:00 to the \"execd_params\" of the execution"
      echo "daemon of login node \"$node\"."
   fi
   rm -f "$node_tmpfile"
done
echo ""

# Install cray parallel environment
pe_name="cray${postfix}.pe"
echo "Adding parallel environment \"$pe_name\"."
output=$(env SGE_SINGLE_LINE=1 qconf -spl | grep -F "$pe_name" 2>&1)
if [ $? -ne 0 ]; then
   pe_config_file="/tmp/$pe_name"
   cp ./templates/cray.pe "$pe_config_file"
   add_or_replace_entry_in_config_file "$pe_config_file" "pe_name" "$pe_name"

   output=$(qconf -Ap "$pe_config_file" 2>&1)
   if [ $? -ne 0 ]; then
      echo "Adding parallel environment \"$pe_name\" failed: $output"
   else
      echo "Added parallel environment \"$pe_name\"."
   fi
   rm "$pe_config_file"
else
   echo "Parallel environment \"$pe_name\" already exists, no need to add it."
fi
echo ""

# Install queue: "cray.q" or "cray_hostname.q"
queue_name="cray${postfix}.q"
echo "Adding queue \"$queue_name\"."
output=$(env SGE_SINGLE_LINE=1 qconf -sql | grep -F "$queue_name" 2>&1)
if [ $? -ne 0 ]; then
   queue_config_file="/tmp/$queue_name"
   cp ./templates/cray_q.config "$queue_config_file"

   add_or_replace_entry_in_config_file "$queue_config_file" "qname"    "$queue_name"
   add_or_replace_entry_in_config_file "$queue_config_file" "pe_list"  "$pe_name"
   add_or_replace_entry_in_config_file "$queue_config_file" "hostlist" "$hostgroup_name"
   add_or_replace_entry_in_config_file "$queue_config_file" "prolog"   \
      "root@\$sge_root/util/resources/cray_xc30_integration/UGE_prolog.sh $MACHINE_NAME"

   output=$(qconf -Aq "$queue_config_file" 2>&1)
   if [ $? -ne 0 ]; then
      echo "Adding queue \"$queue_name\"failed: $output"
   else
      echo "Successfully installed queue \"$queue_name\"."
   fi
   rm "$queue_config_file"
else
   echo "Queue \"$queue_name\" already was installed! Please check if it is valid!"
fi
echo ""

current_dir=$(pwd)


## Adapt the JSV script: Add host specific values
# Copy the template or enhance an already existing JSV file
if [ ! -e ./UGE_JSV.tcl ]; then
   # JSV file does not exist yet, copy it
   cp ./templates/UGE_JSV.tcl.template ./UGE_JSV.tcl
fi

# add or replace values for the current machine name
add_or_replace_machine_specific_values_in_jsv "./UGE_JSV.tcl" "$postfix" "$cores_per_host" \
                                              "$cores_per_node" "$numa_nodes"
chmod +x ./UGE_JSV.tcl

# Install the JSV script which ensures correctness of cray PE and mpp requests.
env SGE_SINGLE_LINE=1 qconf -sconf > /tmp/global.$$
jsv_settings=$(grep jsv_url "/tmp/global.$$" | awk '{print $2}')
if [ "$jsv_settings" == "none" -o "$jsv_settings" == "NONE" ]; then
   echo "Adding JSV script which ensures correctnes of Cray jobs to global config."
   grep -v "^jsv_url" < /tmp/global.$$ > /tmp/global
   echo "jsv_url $current_dir/UGE_JSV.tcl" >> /tmp/global
   qconf -Mconf /tmp/global
   rm /tmp/global
   rm /tmp/global.$$
else
   echo
   echo "A JSV script is already installed in the cluster. You need to submit all jobs with"
   echo "# qsub -jsv $current_dir/UGE_JSV.tcl"
   echo "to ensure job parameter correctness!"
   echo
fi

# Install load sensor which ensures that "cray_nodes" gets aligned
# when configuration (BATCH / INTERACTIVE Cray nodes) changed.
# Install it only on the first Cray login node to avoid to many
# updates.
echo "Installing load sensor"
node_tmpfile="/tmp/$node"
env SGE_SINGLE_LINE=1 qconf -sconf ${login_node_list[0]} > "$node_tmpfile"
# configure the load sensor
add_or_replace_entry_in_config_file "$node_tmpfile" "load_sensor" \
                           "$SGE_ROOT/util/resources/cray_xc30_integration/UGE_load_sensor.sh"
# write the cray_machine_name to the local config of the host, so the load sensor can read it from there
add_or_replace_entry_in_config_file "$node_tmpfile" "cray_machine_name" "$MACHINE_NAME"
output=$(qconf -Mconf "$node_tmpfile" 2>&1)
if [ $? -ne 0 ]; then
   echo "Installing load sensors failed: $output"
else
   echo "Successfully installed the load sensor"
fi
rm -f "$node_tmpfile"

# The last step is changing the execd startup scripts.
echo
echo "This is the last step of the installation. Now the execution daemon"
echo "startup scripts are modified so that #!/bin/sh is replaced to #!/bin/bash -l"
echo "and before execution daemon is started up a module load job is performed."
echo "This is required that the execution daemon and the shepher have the"
echo "right libjob.so (Cray library) in path, which is required for setting"
echo "the PAGG enviornment variable for the job."
echo "You will be prompted for the root password of the execution hosts."
echo "You can abort the installation but you need to change the files manually"
echo "then."
echo

cellname=$(cat "$SGE_ROOT/$SGE_CELL/common/cluster_name")
startupfile="/etc/init.d/sgeexecd.$cellname"

# Create the file which does the changes.
# change sh to bash -l which allows "module load"
# adding "module load job"
for node in "${login_node_list[@]}"
do
   echo "Changing $startupfile on host $node"
   ssh "root@$node" "$SGE_ROOT/util/resources/cray_xc30_integration/modify_execd_startup.sh $startupfile"
done

echo
echo "Installation finished."
echo 
echo "Please adapt now your rur.conf file so that it the RUR outputplugin user is"
echo "enabled (user: true). It is usually located at /etc/opt/cray/rur/rur.conf but"
echo "needs to be changed by xtopview. Also be sure that taskstats is set to true"
echo "in the [plugins] section. In the [user] section arg needs to be set to jobid."
echo 
echo "You need to restart alps after changing rur.conf (/etc/init.d/alps restart) and"
echo "wait a few minutes."
echo
echo "Those settings are required to have Cray accounting available in qacct."

exit 0

