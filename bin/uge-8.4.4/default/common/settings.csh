setenv SGE_ROOT /opt/uge/uge-8.4.4

setenv USE_SYSTEMD true
set ARCH = `$SGE_ROOT/util/arch`
set DEFAULTMANPATH = `$SGE_ROOT/util/arch -m`
set MANTYPE = `$SGE_ROOT/util/arch -mt`

setenv SGE_CELL default
setenv SGE_CLUSTER_NAME p6434
setenv SGE_QMASTER_PORT 6434
setenv SGE_EXECD_PORT 6435 

# library path setting required only for architectures where RUNPATH is not supported
if ( $?MANPATH == 1 ) then
   setenv MANPATH $SGE_ROOT/${MANTYPE}:$MANPATH
else
   setenv MANPATH $SGE_ROOT/${MANTYPE}:$DEFAULTMANPATH
endif

set path = ( $SGE_ROOT/bin/$ARCH $path )
switch ($ARCH)
case "sol*":
case "lx*":
case "hp11-64":
   breaksw
case "*":
   set shlib_path_name = `$SGE_ROOT/util/arch -lib`
   if ( `eval echo '$?'$shlib_path_name` ) then
      set old_value = `eval echo '$'$shlib_path_name`
      setenv $shlib_path_name "$SGE_ROOT/lib/$ARCH":"$old_value"
   else
      setenv $shlib_path_name $SGE_ROOT/lib/$ARCH
   endif
   unset shlib_path_name  old_value
endsw
unset ARCH DEFAULTMANPATH MANTYPE
