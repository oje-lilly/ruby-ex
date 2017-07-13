#! /bin/sh
#
#___INFO__MARK_BEGIN__
##########################################################################
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
##########################################################################
#___INFO__MARK_END__

#set -x

. ./util/install_modules/inst_postgres.sh


#--------------------------------------------------------------------------
# Read a password in from the user. The typed characters are replaced by
# by asterisks ("*") in the output.
#
# No input parameters
# The variable $read_password contains the password at function exit
ReadPassword() {
   read_password=""

   while [ 1 ]; do
      # set terminal to raw mode to read one char
      old_stty=`stty -g`
      stty raw
      stty -echo
      # read one character and print "*" instead of it
      cur_char=`dd bs=1 count=1 2>/dev/null`
      # set terminal back to cooked mode immediately, just to be sure
      stty $old_stty

      # get the ascii-code of character
      ascii_code=`printf '%d' "'$cur_char"`

      if [ $ascii_code -eq 13 -o $ascii_code -eq 3 ]; then
         # the user pressed enter -> password is entered, exit the loop
         # or the user pressed Ctrl-C -> we exit the loop, too
         break
      fi
      # add read character to password
      read_password=$read_password$cur_char

      # print a * instead of the read character
      /bin/echo -n "*"
   done
   /bin/echo ""
}

#--------------------------------------------------------------------------
# Install the UGE_Starter_Service.exe and the RC scripts on Vista and later
#
# No input parameters
# Return Value: 0
# No output
InstallVistaRcScript()
{
   admin_name=""
   admin_password=""

   if [ "$AUTO" = "false" ]; then
      # manual installation
      $INFOTEXT -ask "y" "n" -def "y" -n \
                "\nOn Windows Vista or later, the startup script can't start the %s with\n" \
                "sufficient permissions during boot time. Thus, it is necessary to install a \n" \
                "Windows service (called \"Univa Grid Engine Starter Service\") under the \n" \
                "local Administrators account that runs the startup scripts at boot time.\n" \
                "Do you want to provide the local Administrator's password now so this Windows\n" \
                "Service can be installed with the necessary login informations (answer 'y'), or\n" \
                "do you want to have this service installed with insufficient login informations\n" \
                "now and change them manually later? (answer 'n') (y/n) [y] >> " "execd"

      ret=$?
      if [ $ret -eq 0 ]; then   # answer was 'y'
         # install with username and password
         $INFOTEXT -n "\nPlease enter the name of the local Administrator.\n" \
                      "Default: [Administrator] >> "
         admin_name=`Enter "Administrator"`

         do_loop=1
         while [ $do_loop -eq 1 ]; do
            $INFOTEXT -n "\nPlease enter the password of %s.\n >> " $admin_name
            ReadPassword
            admin_password=$read_password

            $INFOTEXT -n "\nConfirm the password\n >> "
            ReadPassword
            if [ "$admin_password" = "$read_password" ]; then
               do_loop=0
            else
               $INFOTEXT -n "\nPasswords do not match!\n"
            fi
         done
      fi
   else
      # automatic installation
      if [ "$WIN_ADMIN_NAME" != "" -a "$WIN_ADMIN_PASSWORD" != "" ]; then
         admin_name=$WIN_ADMIN_NAME
         admin_password=$WIN_ADMIN_PASSWORD
      fi
   fi
   InstUgeStarterSvc ${admin_name} ${admin_password}
}

#--------------------------------------------------------------------------
# Uninstall the UGE_Starter_Service.exe and the RC scripts on Vista and later
#
# No input parameters
# Return Value: 0
UninstallVistaRcScript()
{
   $INFOTEXT -auto $AUTO -ask "y" "n" -def "y" -n \
             "\nOn Windows Vista and later, there is the Windows service (called \"Univa Grid\n" \
             "Engine Starter Service\") which starts the execution daemons of all installed\n" \
             "Univa Grid Engine clusters at boot time.\n" \
             "This one service is responsible for starting all execution daeons! If you remove it,\n" \
             "no execution daemon will be started at boot time on this host anymore!\n" \
             "Do you want to uninstall and remove it? (y/n) [n] >> "
   ret=$?
   if [ $ret -eq 0 ]; then   # answer was 'y'
      UnInstUgeStarterSvc
   fi
}

#--------------------------------------------------------------------------
# Install the UGE_Starter_Service.exe
#
# $1 - Name of the local Administrator (without any domain specifier)
# $2 - Password of the local Administrator
# No return value
# No output
InstUgeStarterSvc()
{
   $INFOTEXT "Installing UGE Starter Service"
   $INFOTEXT -log "Installing UGE Starter Service"

   admin_name=$1
   admin_password=$2

   tmp_path=$PATH
   PATH=/usr/contrib/win32/bin:/common:$tmp_path
   export PATH

   # Unlike the SGE_Helper_Service.exe, the UGE_Starter_Service.exe
   # stops itself after it has started the sge_execd.
   # Therefore we do not need to test if it runs, we can simply
   # uninstall (which will fail if the Service already was installed, so we
   # ignore this), copy the binary and install the service

   WIN_SVC="UGE_Starter_Service.exe"
   WIN_DIR=`winpath2unix $SYSTEMROOT`

   $INFOTEXT "Uninstalling old UGE Starter Service"
   $INFOTEXT -log "Uninstalling old UGE Starter Service"
   eval "$WIN_DIR/$WIN_SVC -uninstall" < /dev/null > /dev/null 2>&1

   $INFOTEXT "Copying new UGE Starter Service binary"
   $INFOTEXT -log "Copying new UGE Starter Service binary"
   CopyWinSvcBinary "$WIN_SVC" "$WIN_DIR"

   $INFOTEXT "Installing new UGE Starter Service"
   $INFOTEXT -log "Installing new UGE Starter Service"
   InstallWinSvc "$WIN_SVC" "$WIN_DIR" ".\\$admin_name" "$admin_password"

   PATH=$tmp_path
   export PATH
}

#--------------------------------------------------------------------------
# Uninstall the UGE_Starter_Service.exe
#
# No input parameters
# No return value
# No output
UnInstUgeStarterSvc()
{
   tmp_path=$PATH
   PATH=/usr/contrib/win32/bin:/common:$tmp_path
   export PATH

   WIN_DIR=`winpath2unix $SYSTEMROOT`
   WIN_SVC="UGE_Starter_Service.exe"
   WIN_SVC_NAME="Univa Grid Engine Starter Service"

   $INFOTEXT " Stopping service...\n"
   $INFOTEXT -log " Stopping service...\n"

   eval "net stop \"$WIN_SVC_NAME\"" < /dev/null > /dev/null 2>&1

   if [ -f "$WIN_DIR"/"$WIN_SVC" ]; then
      $INFOTEXT "   ... found service binary!" 
      $INFOTEXT -log "   ... found service binary!" 
      $INFOTEXT "   ... uninstalling service!"
      $INFOTEXT -log "   ... uninstalling service!"
      eval "$WIN_DIR/$WIN_SVC -uninstall" < /dev/null > /dev/null 2>&1
      rm $WIN_DIR/"$WIN_SVC"
   fi

   PATH=$tmp_path
   export PATH
}
