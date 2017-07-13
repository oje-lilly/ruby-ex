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
#  Copyright (c) 2011-2012 Univa Corporation.
#
###########################################################################
#___INFO__MARK_END__

# This is an OpenMPI example integration script in order to use core
# binding with OpenMPI. When submitting parallel jobs the core binding
# can be requested with "-binding pe linear:2" for example, which
# means that the scheduler will choose per machine 2 cores. Those
# selected cores are added the "pe_hostfile" generated on the master
# tasks host (the "pe" option).
# Depending on the amount of selected slots per host and selected
# cores per node this script transfers the information into a
# "rankfile". When the amount of slots is equal to the amount of
# cores per machine, then for each rank a different core is chosen
# in order to bind the rank on a different core (this is preferred).
# If the amount is different then each rank is bound to all selected
# cores on the machine, i.e. all ranks on the same machine have
# the same binding.

# This script has to be added to the OpenMPI parallel environment
# qconf -mp <yourpename> in the "start_proc_args" field.
# It transforms the "pe_hostfile" into a rankfile saved in the $TMPDIR
# directory into "pe_rankfile".

# ----------------------------------------------
# The OpenMPI mpirun has to be called then with:
#    "--rankfile $TMPDIR/pe_rankfile".
# ----------------------------------------------

# If the integration should work with OpenMPI
# jobs using core binding and as well es other
# OpenMPI jobs which don't use core binding,
# the existence of the pe_rankfile has to be
# checked in the job script before using
# --rankfile.

# Create tmp file with a list of all hosts used for the PE job.
cat $PE_HOSTFILE | cut -f 1 -d" " | sort -u | uniq > hosts

# this is the path to the rankfile
pe_rankfile="$TMPDIR/pe_rankfile"

# counter for the ranks
next_rank=0

# Go through all hosts participating in PE job an create for each
# host list of ranks. Depending on if the amount of slots per
# is equal to the amount of selected cores per host (or not),
# exactly one core (selected from the Univa Grid Engine scheduler)
# or all cores selected for the complete host are added to the
# pe_rankfile in the $TMPDIR.
while read host
do
   echo "process host $host"
   # Count the total amount of slots for that host for all queue instances.
   # (some strange shells on Solaris loose the variables of the inner loop)
   echo "0" > sge_slots
   echo "" > sge_binding
   while read pe_line
   do
      line_contains_host=`expr "$pe_line" : "$host"`
      if [ $line_contains_host -gt 0 ]; then
         # add slots for this host
         new_slots=`echo $pe_line | cut -f 2 -d" "`
         slots=`cat ./sge_slots`
         slots=`expr $slots + $new_slots`
         echo $slots > sge_slots
         # read out core binding for this host (they all have the same)
         echo $pe_line | cut -f 4 -d" " > sge_binding
      fi
   done < $PE_HOSTFILE

   # re-read innerloop variables
   slots=`cat ./sge_slots`
   binding=`cat ./sge_binding`

   if [ "$binding" != "<NULL>" -a "$binding" != "" ]; then
      # parse the socket,core pairs and put it in rankfile format
      # "socket:core,socket:core"
      # replace : by , and replace , by :
      binding=`echo $binding | sed 's/,/-/g'`
      binding=`echo $binding | sed 's/:/,/g'`
      binding=`echo $binding | sed 's/-/:/g'`
      # Count the amount of <socket>:<cores> pairs per host.
      amount_of_cores=`echo $binding | tr "," " " | wc -w`
   else
      # if there is no core binding selected, don't create a ranfile
      continue
   fi
   # Rankfile Format: rank <number>=<host> slot=<socket>:core>,..
   # Check if amount of cores and amount of ranks per host are equal.

   if [ "$amount_of_cores" -eq "$slots" ]; then
      i=1
      while [ "$i" -le "$slots" ]; do
         # For this rank we add the i'th core from the binding string of host.
         proc=`echo $binding | cut -d"," -f $i`
         echo "rank $next_rank=$host slot=$proc" >> $pe_rankfile
         next_rank=`expr 1 + $next_rank`
         i=`expr $i + 1`
      done
   else
      # If we have more cores than slots or less cores than ranks then each rank
      # should get all cores selected on the specific host.
      i=1
      while [ "$i" -le "$slots" ]; do
         echo "rank $next_rank=$host slot=$binding" >> $pe_rankfile
         next_rank=`expr 1 + $next_rank`
         i=`expr $i + 1`
      done
   fi
done < ./hosts

# Delete the temporary host list.
rm hosts
rm sge_binding
rm sge_slots

