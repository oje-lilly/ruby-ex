#!/bin/sh
###############################################################################
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
###############################################################################
# the complexes to be installed with the default (1) settings
memory_utilization=1
die_temperature=1
board_temperature=0
mem_temperature=0
inlet_temperature=1
outlet_temperature=1
fanstatus=0
powerusage=1
powerlimit_physical=0
powerlimit_upper_threshold=0
powerlimit_lower_threshold=0
flash_version=0
driver_version=1
uos_version=1
ecc_state=1
active_cores=1

complex_list="memory_utilization die_temperature board_temperature mem_temperature inlet_temperature outlet_temperature fanstatus powerusage powerlimit_physical powerlimit_upper_threshold powerlimit_lower_threshold flash_version driver_version uos_version ecc_state active_cores"

if [ "$TMPDIR" = "" ]; then
   TMPDIR="/tmp"
fi

disable_all_complexes() {
   list=`echo $complex_list | tr " " "\n"`
   for complex in $list; do
      eval $complex="0"
   done
}

enable_complex() {
   # mark complex to be used
   list=`echo $complex_list | tr " " "\n"`

   for complex in $list; do
      success=0
      if [ "$complex" = "$1" ]; then
         eval $complex="1"
         return
      fi
   done

   if [ "$success" = "0" ]; then
      echo "Unknown complex $1! It must be one of: $complex_list"
      echo "aborting..."
      exit 1
   fi
}


show_usage() {
   echo "Usage:"
   echo
   echo "$1 --dialog"
   echo "   for the interactive mode (requires dialog beeing installed)"
   echo
   echo "Scripting mode:"
   echo
   echo "$1 --install-default <max. amount of MICs per host>"
   echo "   installs all default complexes required for the Phi load sensor"
   echo
   echo "$1 --show-default <max. amount of MICs per host>"
   echo "   shows the default complexes, which are going to be installed in default mode"
   echo
   echo "$1 --remove"
   echo "   removes all Intel Phi related complex values (\"mic.*.*\") from the UGE complex configuration"
   echo
   echo "$1 --install complex1 complex2 .. <max. amount of MICs per host>"
   echo "   installs just the complexes presented as a space separated list"
   echo
   echo "   The complex can be any of the following key-words:"
   echo
   echo "   memory_utilization die_temperature boad_temperature mem_temperature"
   echo "   inlet_temperature output_temperature fanstatus powerusage powerlimit_phyiscal"
   echo "   powerlimit_upper_threshold powerlimit_lower_threshold flash_version"
   echo "   driver_version uos_version ecc_state active_cores"
   echo
   exit 1
}

# expects 2 arguments: amount of mics and the string with XXX to be replaced
for_n_mics() {
   i=0
   while [ $i -lt "$1" ]; do
      repl=`echo "$2" | awk -v i=$i '{gsub(/XXX/,i)}; 1'`
      echo $repl
      i=`expr $i + 1`
   done
}

remove_all_complexes() {
   echo "Removing complexes..."

   qconf -sc > $TMPDIR/$$_complex.tmp
   cat $TMPDIR/$$_complex.tmp | grep -v "^mic.[[:digit:]]*.*|^mic_*" | grep -v "^mic_*" > $TMPDIR/$$_complex2.tmp

   echo "Following complexes are deleted in the Univa Grid Engine complex configuration:"
   cat $TMPDIR/$$_complex.tmp | grep "^mic.[[:digit:]]*.*)"
   cat $TMPDIR/$$_complex.tmp | grep "^mic_*"
   rm $TMPDIR/$$_complex.tmp
   read -p "Do you want to delete them? (y/n)"
   if [ "$REPLY" = "y" ]; then
      qconf -Mc $TMPDIR/$$_complex2.tmp
      rm $TMPDIR/$$_complex2.tmp
   else
      echo "Ok. Aborting deletion..."
      rm $TMPDIR/$$_complex2.tmp
      exit 1
   fi

   read -p "Should I try to remove the phi complex (works only when not referenced)? (y/n)"
   if [ "$REPLY" = "y" ]; then
      qconf -sc > $TMPDIR/$$_complex.tmp
      cat $TMPDIR/$$_complex.tmp | grep -v "^phi " > $TMPDIR/$$_complex2.tmp
      rm $TMPDIR/$$_complex.tmp
      qconf -Mc $TMPDIR/$$_complex2.tmp
      rm $TMPDIR/$$_complex2.tmp
   fi
}

# Prints out the complex configuration. Requires a numerical parameter
# which denotes the number of MIC cards installed.
show_complexes() {
   num=$1

   if [ "$memory_utilization" = "1" ]; then
      for_n_mics $num "mic.XXX.mem_total micXXXtotal MEMORY <= YES NO 0 0 NO"
      for_n_mics $num "mic.XXX.mem_free micXXXfree MEMORY <= YES NO 0 0 NO"
      for_n_mics $num "mic.XXX.mem_used micXXXused MEMORY >= YES NO 0 0 NO"
      for_n_mics $num "mic.XXX.mem_bufs micXXXbufs MEMORY >= YES NO 0 0 NO"
      # install derived complex
      echo "mic_mem_total_max mictotalmax MEMORY <= YES NO 0 0 NO"
      echo "mic_mem_free_max micfreemax MEMORY <= YES NO 0 0 NO"
      echo "mic_mem_used_min micusedmin MEMORY >= YES NO 0 0 NO"
      # bufs usually not used
   fi

   if [ "$die_temperature" = "1" ]; then
      for_n_mics $num "mic.XXX.temp_die micXXXtempdie INT <= YES NO 0 0 NO"
      echo "mic_temp_die_max mictempdiemax INT <= YES NO 0 0 NO"
   fi

   if [ "$board_temperature" -eq "1" ]; then
      for_n_mics $num "mic.XXX.temp_board micXXXtempboard INT <= YES NO 0 0 NO"
      echo "mic_temp_board_max mictempboardmax INT <= YES NO 0 0 NO"
   fi

   if [ "$inlet_temperature" -eq "1" ]; then
      for_n_mics $num "mic.XXX.temp_inlet micXXXtempin INT <= YES NO 0 0 NO"
      echo "mic_temp_inlet_max mictempinmax INT <= YES NO 0 0 NO"
   fi

   if [ "$outlet_temperature" -eq "1" ]; then
      for_n_mics $num "mic.XXX.temp_outlet micXXXtempout INT <= YES NO 0 0 NO"
      echo "mic_temp_outlet_max mictempoutmax INT <= YES NO 0 0 NO"
   fi

   if [ "$mem_temperature" -eq "1" ]; then
      for_n_mics $num "mic.XXX.temp_mem micXXXtempmem INT <= YES NO 0 0 NO"
      echo "mic_temp_mem_max mictempmemmax INT <= YES NO 0 0 NO"
   fi

   if [ "$fanstatus" -eq "1" ]; then
      for_n_mics $num "mic.XXX.fan micXXXfan BOOL == YES NO 0 0 NO"
   fi

   if [ "$powerusage" -eq "1" ]; then
      for_n_mics $num "mic.XXX.power micXXXpower INT <= YES NO 0 0 NO"
      # too much power can trigger alarm state, hence ">="
      echo "mic_power_combined micpwrsum INT >= YES NO 0 0"
   fi

   if [ "$powerlimit_physical" -eq "1" ]; then
      for_n_mics $num "mic.XXX.power_physical_limit micXXXpowerlimit INT <= YES NO 0 0 NO"
   fi

   if [ "$powerlimit_upper_threshold" -eq "1" ]; then
      for_n_mics $num "mic.XXX.power_upper_threshold micXXXpoweruthreshold INT <= YES NO 0 0 NO"
   fi

   if [ "$powerlimit_lower_threshold" -eq "1" ]; then
      for_n_mics $num "mic.XXX.power_lower_threshold micXXXpowerlthreshold INT <= YES NO 0 0 NO"
   fi

   if [ "$flash_version" -eq "1" ]; then
      for_n_mics $num "mic.XXX.flash_image_version micXXXflashversion RESTRING == YES NO NONE 0 NO"
   fi

   if [ "$driver_version" -eq "1" ]; then
      for_n_mics $num "mic.XXX.host_driver_version micXXXdriverversion RESTRING == YES NO NONE 0 NO"
   fi

   if [ "$uos_version" -eq "1" ]; then
      for_n_mics $num "mic.XXX.uos_version micXXXuosversion RESTRING == YES NO NONE 0 NO"
   fi

   if [ "$ecc_state" -eq "1" ]; then
      for_n_mics $num "mic.XXX.ecc_on micXXXecc BOOL == YES NO 0 0 NO"
   fi

   if [ "$active_cores" -eq "1" ]; then
      for_n_mics $num "mic.XXX.cores micXXXcores INT <= YES NO 0 0 NO"
      echo "mic_cores_combined miccoresum INT <= YES NO 0 0 NO"
      echo "mic_cores_max miccoremax INT == YES NO 0 0 NO"
   fi

   # general surrogate for requesting a MIC
   if [ "$active_cores" -eq "1" ]; then
      echo "phi phi RSMAP <= YES HOST 0 0 NO"
   fi
}

print_config_file() {
   config=""
   if [ "$memory_utilization" = "1" ]; then
      config="memory_utilization $config"
   fi

   if [ "$die_temperature" = "1" ]; then
      config="die_temperature $config"
   fi

   if [ "$board_temperature" -eq "1" ]; then
      config="board_temperature $config"
   fi

   if [ "$inlet_temperature" -eq "1" ]; then
      config="inlet_temperature $config"
   fi

   if [ "$outlet_temperature" -eq "1" ]; then
      config="outlet_temperature $config"
   fi

   if [ "$mem_temperature" -eq "1" ]; then
      config="mem_temperature $config"
   fi

   if [ "$fanstatus" -eq "1" ]; then
      config="fanstatus $config"
   fi

   if [ "$powerusage" -eq "1" ]; then
      config="powerusage $config"
   fi

   if [ "$powerlimit_physical" -eq "1" ]; then
      config="powerlimit_physical $config"
   fi

   if [ "$powerlimit_upper_threshold" -eq "1" ]; then
      config="powerlimit_upper_threshold $config"
   fi

   if [ "$powerlimit_lower_threshold" -eq "1" ]; then
      config="powerlimit_lower_threshold $config"
   fi

   if [ "$flash_version" -eq "1" ]; then
      config="flash_version $config"
   fi

   if [ "$driver_version" -eq "1" ]; then
      config="driver_version $config"
   fi

   if [ "$uos_version" -eq "1" ]; then
      config="uos_version $config"
   fi

   if [ "$ecc_state" -eq "1" ]; then
      config="ecc_state $config"
   fi

   if [ "$active_cores" -eq "1" ]; then
      config="active_cores $config"
   fi

   echo "$config"
}


show_load_sensor_config() {
   echo ""
   echo "Now the Intel Phi load sensor has to be installed on the corresponding hosts."
   echo "-----------------------------------------------------------------------------"
   echo ""
   echo "Modify the $SGE_ROOT/util/resources/loadsensors/phi/phi_sensor.sh file, so that"
   echo "it starts the load sensor binary with the config file, in order to control that"
   echo "only values of installed complexes are reported."
   echo ""
   echo "Open the host configuration with"
   echo "   qconf -mconf <exechostname>"
   echo ""
   echo "Add the following line:"
   echo "   load_sensor $SGE_ROOT/util/resources/loadsensors/phi/phi_sensor.sh"
   echo ""
   echo "The configuration file is a text file containing a space separated list of the"
   echo "corresponding load values. Based on the resource you had selected it must have"
   echo "following content (file with the name phi_load_sensor_config.txt generated):"

   echo ""
   print_config_file
   print_config_file > phi_load_sensor_config.txt
   echo ""

   echo "More information you can get when you are calling phi_load_sensor --help."
   echo ""
   echo "After a load interval qhost should report load values of the Intel Phi cards."
   echo ""
   echo "Hints for debugging: Start the load sensor on the corresponding host on command"
   echo "line and hit <enter>. The load sensor reports each time enter was pressed a new"
   echo "set of load values."
   echo "Start the load sensor with the config file on command line. Check if the load"
   echo "sensor is started on the execution host by the execution daemon. Check if"
   echo "complexes are installed in the complex configuration (qconf -sc)."
   echo ""
   echo "Finally the amount of Phi's installed per host must be initialized."
   echo ""
   echo "Example: Initializing 4 Intel Phi's on host <hostname>"
   echo ""
   echo "   qconf -mattr exechost complex_values \"phi=4(mic0 mic1 mic2 mic3)\" <hostname>"
   echo ""
   echo "Or, if you want to have jobs automatically bound to near cores, add"
   echo "the coresponding topology mask (more information in the UGE admin guide). Example:"
   echo ""
   echo "   qconf -mattr exechost complex_values \"phi=4(mic0:SCCCCccccScccccccc mic1:SccccCCCCScccccccc mic2:SccccccccSCCCCcccc mic3:SccccccccSccccCCCC)\" <hostname>"
   echo ""
}


# without arguments it shows help

#echo $1
#echo $#

if [ $# -eq 0 ]; then
   show_usage $0
fi

if [ "$1" = "--help" -o "$1" = "-help" -o "$1" = "-h" ]; then
   show_usage $0
fi

if [ "$1" = "--remove" ]; then
   remove_all_complexes
   exit
fi

if [ "$1" = "--dialog" ]; then
   # display dialog for chosing the complexes
   dialog --msgbox "Univa Grid Engine Installation Script for Intel Phi Load-Sensor Resources.\n\nThis tool installs the needed complexes in the UGE complex configuration for the Intel Phi load sensor." 20 60

   dialog --inputbox "How many Intel Phi cards are going to be installed on a host (maximum)?" 10 60 2> $TMPDIR/$$_tmp_amount
   response=$?
   if [ "$response" = "1" ]; then
      # cancel pressed
      rm $TMPDIR/$$_tmp_amount
      exit 1
   fi

   amount=`cat $TMPDIR/$$_tmp_amount`
   rm $TMPDIR/$$_tmp_amount

   # amount must be > 0

   selection_list="memory_utilization 'mic.mem' on die_temperature 'mic.temp.die' on"
   dialog --checklist "Select complexes to install" 100 100 80 memory_utilization 'Memory (total/free/used/bufs) state on Phi Card' on die_temperature 'Temperature on Phi die (core)' on board_temperature 'Temperature on Phi board' off mem_temperature 'Temperature on Phi memory' off inlet_temperature 'Incoming temperature of Phi Cards' off outlet_temperature 'Outcoming temperature of the Phi Cards' off fanstatus 'Status of the fans' off powerusage 'Consumed power in Watts from Phi Cards' on powerlimit_physical 'Physical power limit' off powerlimit_upper_threshold 'Upper threshold of the powerlimit' off powerlimit_lower_threshold 'Lower threshold of the powerlimit' off flash_version 'Version of the Phi flash' off driver_version 'Version of the driver' on uos_version 'Version of OS on Phi' on ecc_state 'ECC of memory on Phi' on active_cores 'Amount of cores on Phi' on 2> $TMPDIR/$$_tmp
   response=$?
   if [ "$response" = "1" ]; then
      # cancel pressed
      rm $TMPDIR/$$_tmp
      exit 1
   fi

   selection=`cat $TMPDIR/$$_tmp`
   rm $TMPDIR/$$_tmp

   dialog --msgbox "Installing complexes for: $selection" 20 60

   # remove quotas
   selection=`echo $selection | sed -e s/\"//g`
   disable_all_complexes

   for cmplx in $selection; do
      enable_complex $cmplx
   done

   # now install all marked one
   qconf -sc > $TMPDIR/complexconfig$$.tmp
   show_complexes $amount >> $TMPDIR/complexconfig$$.tmp
   cat $TMPDIR/complexconfig$$.tmp
   qconf -Mc $TMPDIR/complexconfig$$.tmp
   rm $TMPDIR/complexconfig$$.tmp
   show_load_sensor_config

   exit
fi

# all others need at least 2 parameters
if [ $# -eq 1 ]; then
   show_usage $0
fi

if [ "$1" = "--show-default" ]; then
   # set selection to all
   mics="$2"
   show_complexes $mics
   show_load_sensor_config
fi

if [ "$1" = "--install-default" ]; then
   # set selection to all
   mics="$2"
   qconf -sc > $TMPDIR/complexconfig$$.tmp
   show_complexes $mics >> $TMPDIR/complexconfig$$.tmp
   qconf -Mc $TMPDIR/complexconfig$$.tmp
   rm $TMPDIR/complexconfig$$.tmp
   show_load_sensor_config
fi

if [ "$1" = "--install" ]; then
   # set complexes to install
   disable_all_complexes
   # go through argument list and take the last argument as amount of MICs installed
   for amount; do true; done

   for arg
   do
      if [ "$arg" = "--install" ]; then
         # skipt first argument
         continue
      fi
      if [ "$arg" = "$amount" ]; then
         # skip last argument
         continue
      fi
      # all other arguments are complexes which should be installed
      echo $powerusage
      echo "enable complex $arg"
      enable_complex $arg
   done

   # now install all marked one
   qconf -sc > $TMPDIR/complexconfig$$.tmp
   show_complexes $amount >> $TMPDIR/complexconfig$$.tmp
   cat $TMPDIR/complexconfig$$.tmp
   qconf -Mc $TMPDIR/complexconfig$$.tmp
   rm $TMPDIR/complexconfig$$.tmp
   show_load_sensor_config
fi

echo

