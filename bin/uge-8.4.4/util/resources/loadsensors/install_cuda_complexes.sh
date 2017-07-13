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

#
# Adds CUDA complexes (which are reported by the CUDA load sensor)
# to the complex configuration.
#
InstallCudaComplexes()
{
   amount_selected="false"

   while [ $amount_selected = "false" ]; do
      echo -n "How many GPU devices does your host with the most GPU devices have? "
      read amount
      # check if it is a number
      if [ $amount -eq $amount 2> /dev/null ]; then
         echo -n "Really $amount? (y/n) "
         read yesno
         if [ "$yesno" = "y" ]; then
            # ok, remove the complexes
            amount_selected="true"
         fi
      else
         echo "Sorry, this is not a number."
      fi
   done


   # decrement by one because we're starting at 0
   amount=`expr $amount - 1`

   echo ""
   new_complexes="cuda.verstr cuda.verstr RESTRING == YES NO NONE 0"
   new_complexes="$new_complexes\ncuda.devices cuda.devices    INT <= YES NO 0 0"
   echo ""

   for i in $(seq 0 $amount); do
      new_complexes="$new_complexes\ncuda.$i.totalMem cuda.$i.totalMem  MEMORY  <= YES NO 0 0 NO"
      new_complexes="$new_complexes\ncuda.$i.freeMem  cuda.$i.freeMem   MEMORY  <= YES NO 0 0 NO"
      new_complexes="$new_complexes\ncuda.$i.usedMem  cuda.$i.usedMem   MEMORY  <= YES NO 0 0 NO"
      new_complexes="$new_complexes\ncuda.$i.eccEnabled cuda.$i.eccEnabled INT  <= YES NO 0 0 NO"
      new_complexes="$new_complexes\ncuda.$i.volatileEccCount cuda.$i.volatileEccCount INT <= YES NO 0 0 NO"
      new_complexes="$new_complexes\ncuda.$i.name cuda.$i.name RESTRING == YES NO NONE 0 NO"
      new_complexes="$new_complexes\ncuda.$i.temperature cuda.$i.temperature DOUBLE <= YES NO 0 0 NO\n"
   done

   echo "The following new complexes are going to be installed:"
   echo ""
   printf "%b" "$new_complexes"
   echo ""

   complex_list="cuda_verstr cuda_devices"
   for i in $(seq 0 $amount); do
      complex_list="$complex_list cuda.$i.totalMem"
      complex_list="$complex_list cuda.$i.freeMem"
      complex_list="$complex_list cuda.$i.usedMem"
      complex_list="$complex_list cuda.$i.eccEnabled"
      complex_list="$complex_list cuda.$i.volatileEccCount"
      complex_list="$complex_list cuda.$i.name"
      complex_list="$complex_list cuda.$i.temperature"
   done

   printf "%b" "Complex list:\n" "$complex_list"

   echo -e "\nChecking now if some complexes are already installed..\n"

   for i in $complex_list; do
      output=`qconf -sc | grep $i`
      if [ "x$output" != "x" ]; then
         echo "\nError"
         echo "Please remove $i first from complex configuration (or call --uninstall)!"
         exit 1
      fi
   done

   # Now the complexes can be added...
   qconf -sc > /tmp/uge.$$.complexes

   printf "%b" "$new_complexes" >> /tmp/uge.$$.complexes

   # add new complexes to the UGE configuration
   qconf -Mc /tmp/uge.$$.complexes

   rm -f /tmp/uge.$$.complexes

   echo "done"
}

#
# Removes the CUDA complexes from the complex configuration.
#
DeinstallCudaComplexes()
{
   echo "Removing CUDA load sensor complexes from UGE complex configuration\n"

   echo "Following complexes are installed:"

   complex_list="cuda.verstr cuda.devices"
   # add 99 devices (should be sufficient)
   for i in $(seq 0 99); do
      complex_list="$complex_list cuda.$i.totalMem"
      complex_list="$complex_list cuda.$i.freeMem"
      complex_list="$complex_list cuda.$i.usedMem"
      complex_list="$complex_list cuda.$i.eccEnabled"
      complex_list="$complex_list cuda.$i.volatileEccCount"
      complex_list="$complex_list cuda.$i.name"
      complex_list="$complex_list cuda.$i.temperature"
   done

   for i in $complex_list; do
      output=`qconf -sc | grep $i`
      if [ "x$output" != "x" ]; then
         echo "\nRemoving: $output\n"
         # remove the complex from qconf -sc output and write it in tmp file
         qconf -sc | grep -v $i > /tmp/uge.$$.complexes$i
         qconf -Mc /tmp/uge.$$.complexes$i
         rm -f /tmp/uge.$$.complexes$i
      fi
   done

   echo "List of cuda variables that are still in the complex configuration:\n"
   qconf -sc | grep cuda
}

ErrUsage()
{
   echo ""
   echo "Usage: install_cuda_complexes.sh --install | --uninstall"
   echo ""
   echo "   --install    Installs new complexes for the CUDA load sensor"
   echo "   --uninstall  Uninstalls all CUDA load sensor related complexes"
   echo ""
}

###############
# main script #
###############

# check if SGE_ROOT is unset or empty
if [ -z "$SGE_ROOT" ]; then
   echo "Please source the common/settings.sh file for your cluster first!"
   exit 1
fi

# amount of parameters does not fit
if [ $# -ne 1 ]; then
   ErrUsage
   exit 1
fi

################
# installation #
################

if [ "x$1" = "x--install" ]; then
   echo "This script installs new complexes for the CUDA load sensor!"
   InstallCudaComplexes
   exit
fi

###################
# un-installation #
###################

if [ "x$1" = "x--uninstall" ]; then
   echo "Are you sure to remove cuda.* complexes? (y/n)"
   read remove
   if [ "x$remove" = "xy" ]; then
      # ok, remove the complexes
      DeinstallCudaComplexes
   else
      echo "Aborting..."
      exit 1
   fi
   exit
fi

###################
# wrong parameter #
###################

echo "Unkown parameter: $1"
ErrUsage
exit 1

