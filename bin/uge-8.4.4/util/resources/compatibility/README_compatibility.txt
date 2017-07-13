This document contains some hints how to get SGE 6.2u5
and Univa Grid Engine (older versions) compatible output.

The file "qhost.sh" provides a wrapper function for qhost
which provides the SGE 6.2u5 compatible qhost (without
arguments) output. It simply accepts the removed "-cb"
switch and when no parameter is given it add a "-ncb" which
shows old SGE 6.2u5 compatible output.

In UGE 8.1 the qhost and qstat -f are showing now the
np_load_avg (normalized load average with respect to the
amount of processors) which is used as default in Grid
Engine for a long time (for example it is the default
load_formula in the scheduler). Previously load_avg was
shown. In order to get SGE 6.2u5 compatible output in
qstat -f the environment variable SGE_LOAD_AVG has to be set
to "load_avg". The same is true for getting compatible
output in qstat -f -xml. For getting the old output
(load instead of normlized load) in qhost the environment
variable SGE_REAL_LOAD has to be set to any value.
In order to reset the output to default the environment
variable has to be reomved.



