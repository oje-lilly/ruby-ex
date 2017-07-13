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

show_usage() {
   echo "Usage:"
   echo
   echo "$1 --install hostname"
   echo "   adds all Intel KNL related complex values to the UGE complex configuration"
   echo "   as also the KNL loadsensor to the configuration of the given host"
   echo
   echo "$1 --install_only_loadsensor hostname"
   echo "   adds the KNL loadsensor to the configuration of the given host"
   echo
   echo "$1 --remove_all hostname"
   echo "   removes all Intel KNL related complex values from UGE complex configuration"
   echo "   as also the KNL loadsensor from the configuration of the given host"
   echo
   echo "$1 --remove_complexes"
   echo "   removes all Intel KNL related complex values from UGE complex configuration"
   echo
   echo "$1 --remove_loadsensor hostname"
   echo "   removes the KNL loadsensor from the configuration of the given host"
   echo
   exit 1
}

remove_all_complexes() {
   echo "Removing complexes..."

   qconf -sc > $TMPDIR/$$_complex.tmp
   cat $TMPDIR/$$_complex.tmp | grep -v "^knl_*" > $TMPDIR/$$_complex2.tmp

   echo "Following complexes are deleted in the Univa Grid Engine complex configuration:"
   cat $TMPDIR/$$_complex.tmp | grep "^knl_*"
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

}

remove_load_sensor() {
   qconf -sconf $1 > $TMPDIR/$1

   # remove load_sensor
   sed -i '/load_sensor/d' $TMPDIR/$1

   qconf -Mconf $TMPDIR/$1
   rm $TMPDIR/$1
}

add_load_sensor() {
   qconf -sconf $1 > $TMPDIR/$1
   grep -q "load_sensor" $TMPDIR/$1
   if [ $? -eq 0 ]; then
      sed -i '/^load_sensor/ s/$/ $SGE_ROOT\/util\/resources\/loadsensors\/lx-amd64\/knl_sensor/' $TMPDIR/$1
   else
      echo "load_sensor $SGE_ROOT/util/resources/loadsensors/lx-amd64/knl_sensor" >> $TMPDIR/$1
   fi      
   qconf -Mconf $TMPDIR/$1
   rm $TMPDIR/$1
}

add_complexes() {
   qconf -sc > $TMPDIR/complexconfig$$.tmp
   echo "knl_cluster_mode knl_cmode RESTRING == YES NO NONE 0 NO" >> $TMPDIR/complexconfig$$.tmp
   echo "knl_memory_mode knl_mmode RESTRING == YES NO NONE 0 NO" >> $TMPDIR/complexconfig$$.tmp
   echo "knl_MCDRAM_total knl_total MEMORY <= YES NO 0 0 NO" >> $TMPDIR/complexconfig$$.tmp
   echo "knl_MCDRAM_cache knl_cache MEMORY <= YES NO 0 0 NO" >> $TMPDIR/complexconfig$$.tmp
   qconf -Mc $TMPDIR/complexconfig$$.tmp
   rm $TMPDIR/complexconfig$$.tmp
}

if [ "$TMPDIR" = "" ]; then
   TMPDIR="/tmp"
fi

if [ $# -eq 0 ]; then
   show_usage $0
fi

if [ "$1" = "--help" -o "$1" = "-help" -o "$1" = "-h" ]; then
   show_usage $0
fi

if [ "$1" = "--remove_all" ]; then
   if [ $#  -lt 2 ]; then
      show_usage $0
   fi
   remove_all_complexes
   remove_load_sensor $2
   exit
fi

if [ "$1" = "--remove_complexes" ]; then
   remove_all_complexes
   exit
fi

if [ "$1" = "--remove_loadsensor" ]; then
   if [ $#  -lt 2 ]; then
      show_usage $0
   fi
   remove_load_sensor $2
   exit
fi

if [ "$1" = "--install" ]; then
   if [ $#  -lt 2 ]; then
      show_usage $0
   fi
   add_complexes
   add_load_sensor $2
   exit
fi

if [ "$1" = "--install_only_loadsensor" ]; then
   if [ $#  -lt 2 ]; then
      show_usage $0
   fi
   add_load_sensor $2
   exit
fi

show_usage $0
