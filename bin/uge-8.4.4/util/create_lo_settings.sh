#!/bin/sh
#
# create Grid Engine settings.[c]sh file
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
##########################################################################
#___INFO__MARK_END__
#
# $1 = base directory  where settings.[c]sh is created

PATH=/bin:/usr/bin

ErrUsage()
{
   echo
   echo "usage: `basename $0` outdir"
   echo "       \$LO_ROOT must be set"
   echo "       \$LO_CELL, \$LO_MASTER_PORT and \$LO_EXECD_PORT must be set if used in your environment"
   echo "       \$LO_CLUSTER_NAME must be set or \$LO_ROOT and \$LO_CELL must be set"
   exit 1
}


if [ $# != 1 ]; then
   ErrUsage
fi

if [ -z "$LO_ROOT" -o -z "$LO_CELL" ]; then
   ErrUsage
fi

SP_CSH=$1/settings.csh
SP_SH=$1/settings.sh

#
# C shell settings file
#

echo "setenv LO_ROOT $LO_ROOT"                           >  $SP_CSH
echo ""                                                  >> $SP_CSH
echo "set ARCH = \`\$LO_ROOT/util/arch\`"                >> $SP_CSH
echo "set DEFAULTMANPATH = \`\$LO_ROOT/util/arch -m\`"   >> $SP_CSH
echo "set MANTYPE = \`\$LO_ROOT/util/arch -mt\`"         >> $SP_CSH
echo ""                                                  >> $SP_CSH

#if [ "$LO_CELL" != "" -a "$LO_CELL" != "default" ]; then
   echo "setenv LO_CELL $LO_CELL"                      >> $SP_CSH
#else
#   echo "unsetenv LO_CELL"                              >> $SP_CSH
#fi

echo "setenv LO_CLUSTER_NAME `cat $LO_ROOT/$LO_CELL/common/cluster_name  2>/dev/null`" >> $SP_CSH

if [ "$LO_MASTER_PORT" != "" ]; then
   echo "setenv LO_MASTER_PORT $LO_MASTER_PORT"                  >> $SP_CSH
else
   echo "unsetenv LO_MASTER_PORT"                                  >> $SP_CSH
fi

if [ "$LO_EXECD_PORT" != "" ]; then
   echo "setenv LO_EXECD_PORT $LO_EXECD_PORT"                      >> $SP_CSH
else
   echo "unsetenv LO_EXECD_PORT"                                    >> $SP_CSH
fi


echo ""                                                          >> $SP_CSH
echo '# library path setting required only for architectures where RUNPATH is not supported' >> $SP_CSH
echo 'if ( $?MANPATH == 1 ) then'                                >> $SP_CSH
echo "   setenv MANPATH \$LO_ROOT/"'${MANTYPE}':'$MANPATH'      >> $SP_CSH
echo "else"                                                      >> $SP_CSH
echo "   setenv MANPATH \$LO_ROOT/"'${MANTYPE}:$DEFAULTMANPATH' >> $SP_CSH
echo "endif"                                                     >> $SP_CSH
echo ""                                                          >> $SP_CSH
echo "set path = ( \$LO_ROOT/bin/"'$ARCH $path )'               >> $SP_CSH

echo 'switch ($ARCH)'                                            >> $SP_CSH
#ENFORCE_SHLIBPATH#echo 'case "sol*":'                           >> $SP_CSH
#ENFORCE_SHLIBPATH#echo 'case "lx*":'                            >> $SP_CSH
#ENFORCE_SHLIBPATH#echo 'case "hp11-64":'                        >> $SP_CSH
#ENFORCE_SHLIBPATH#echo '   breaksw'                             >> $SP_CSH
echo 'case "*":'                                                 >> $SP_CSH
echo "   set shlib_path_name = \`\$LO_ROOT/util/arch -lib\`"       >> $SP_CSH
echo "   if ( \`eval echo '\$?'\$shlib_path_name\` ) then"          >> $SP_CSH
echo "      set old_value = \`eval echo '\$'\$shlib_path_name\`"    >> $SP_CSH
echo "      setenv \$shlib_path_name \"\$LO_ROOT/lib/\$ARCH\":\"\$old_value\""   >> $SP_CSH
echo "   else"                                                      >> $SP_CSH
echo "      setenv \$shlib_path_name \$LO_ROOT/lib/\$ARCH"         >> $SP_CSH
echo "   endif"                                                     >> $SP_CSH
echo "   unset shlib_path_name  old_value"                          >> $SP_CSH
echo "endsw"                                                        >> $SP_CSH
echo "unset ARCH DEFAULTMANPATH MANTYPE"                            >> $SP_CSH

#
# bourne shell settings file
#

echo "LO_ROOT=$LO_ROOT; export LO_ROOT"                        > $SP_SH
echo ""                                                          >> $SP_SH
echo "ARCH=\`\$LO_ROOT/util/arch\`"                             >> $SP_SH
echo "DEFAULTMANPATH=\`\$LO_ROOT/util/arch -m\`"                >> $SP_SH
echo "MANTYPE=\`\$LO_ROOT/util/arch -mt\`"                      >> $SP_SH
echo ""                                                          >> $SP_SH

if [ "$LO_CELL" != "" ]; then
   echo "LO_CELL=$LO_CELL; export LO_CELL"                    >> $SP_SH
else
   echo "unset LO_CELL"                                         >> $SP_SH
fi

echo "LO_CLUSTER_NAME=`cat $LO_ROOT/$LO_CELL/common/cluster_name  2>/dev/null`; export LO_CLUSTER_NAME" >> $SP_SH

if [ "$LO_MASTER_PORT" != "" ]; then
   echo "LO_MASTER_PORT=$LO_MASTER_PORT; export LO_MASTER_PORT"  >> $SP_SH
else
   echo "unset LO_MASTER_PORT"                                       >> $SP_SH              
fi
if [ "$LO_EXECD_PORT" != "" ]; then
   echo "LO_EXECD_PORT=$LO_EXECD_PORT; export LO_EXECD_PORT"        >> $SP_SH
else
   echo "unset LO_EXECD_PORT"                                         >> $SP_SH    
fi


echo ""                                                          >> $SP_SH
echo "if [ \"\$MANPATH\" = \"\" ]; then"                         >> $SP_SH
echo "   MANPATH=\$DEFAULTMANPATH"                               >> $SP_SH
echo "fi"                                                        >> $SP_SH
echo "MANPATH=\$LO_ROOT/\$MANTYPE:\$MANPATH; export MANPATH"    >> $SP_SH
echo ""                                                          >> $SP_SH
echo "PATH=\$LO_ROOT/bin/\$ARCH:\$PATH; export PATH"            >> $SP_SH

echo '# library path setting required only for architectures where RUNPATH is not supported' >> $SP_SH
echo 'case $ARCH in'                                                >> $SP_SH
#ENFORCE_SHLIBPATH#echo 'sol*|lx*|hp11-64)'                         >> $SP_SH
#ENFORCE_SHLIBPATH#echo '   ;;'                                     >> $SP_SH
echo '*)'                                                           >> $SP_SH
echo "   shlib_path_name=\`\$LO_ROOT/util/arch -lib\`"             >> $SP_SH
echo "   old_value=\`eval echo '\$'\$shlib_path_name\`"             >> $SP_SH
echo "   if [ x\$old_value = "x" ]; then"                           >> $SP_SH
echo "      eval \$shlib_path_name=\$LO_ROOT/lib/\$ARCH"           >> $SP_SH
echo "   else"                                                      >> $SP_SH
echo "      eval \$shlib_path_name=\$LO_ROOT/lib/\$ARCH:\$old_value" >> $SP_SH
echo "   fi"                                                        >> $SP_SH
echo "   export \$shlib_path_name"                                  >> $SP_SH
echo '   unset shlib_path_name old_value'                           >> $SP_SH
echo '   ;;'                                                        >> $SP_SH
echo 'esac'                                                         >> $SP_SH
echo "unset ARCH DEFAULTMANPATH MANTYPE"                            >> $SP_SH

