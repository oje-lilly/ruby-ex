#!/bin/sh
# Example of a load sensor starter, which reports all Intel Phi load values.
#
# Open host configuration: qconf -mconf <hostname>
# add line: load_sensor $SGE_ROOT/util/resources/loadsensors/phi/phi_sensor.sh
#
# If less values should be reported start load_sensor below with -c configfile.
# See: load_sensor -h
#
# HINT: Requires Intel Phi drivers beeing installed as well as the MicAccessSDK lib
#       in the library path. Setting LD_LIBRARY_PATH to "/opt/intel/mic/sysmgmt/sdk/lib/Linux/"
#       might be required in order to use the correct library.

$SGE_ROOT/util/resources/loadsensors/phi/lx-amd64/load_sensor -a

