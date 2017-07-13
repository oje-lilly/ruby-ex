#!/bin/bash
#___INFO__MARK_BEGIN__
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
#___INFO__MARK_END__

# Following information is required:
# - URI (needs to be http:// not file://) of UGE documentation
# - Path to CMU installation
# - SGE_ environment variables must be present (source settings.sh)

# Check for settings.
CMU_PATH=""
UGE_DOCUMENTATION=""

user=`whoami`
if [ "$user" != "root" ]; then
   echo "This installation script needs to run as root."
   exit 1
fi

if [ "$SGE_ROOT" = "" -o "$SGE_CELL" = "" ]; then
   echo "Univa Grid Engine location is unknown."
   echo "Please source <uge_install_path>/<cellname>/common/settings.sh first!"
   exit 1
fi

DIR=`pwd`
if [ -f $DIR/install_cmu_uge_extensions.sh ]; then
   # Installation is started in own directory.
   echo "Note: Integration only works with HP Insight CMU 7.2 and higher."
   echo "Please abort (CTRL + c) and update HP Insight CMU if you have an older version."
else
   echo "Installation can only be started if script is called in installation directory."
   exit 1
fi

# Check if directory is writable, otherwise this directory needs
# to be copied to a root writable directory manually.
touch test.fs
if [ $? != 0 ]; then
   echo "Sorry! This directory is not writable by root. You need"
   echo "to copy this directory to a root writable location and"
   echo "call the installation again."
   exit 1
fi
rm -f test.fs

# Ask for CMU path.
if [ -d /opt/cmu ]; then
   read -p "HP Insight CMU at /opt/cmu detected. Should this installation be used (y/n)? "
   if [ "$REPLY" = "y" -o "$REPLY" = "Y" -o "$REPLY" = "yes" ]; then
      CMU_PATH="/opt/cmu"
   else 
      read -p "Please enter full path to HP Insight CMU (i.e. /opt/cmu)"
      CMU_PATH=$REPLY
   fi
else
   read -p "Please set path (like /opt/cmu) to CMU installation."
   CMU_PATH=$REPLY
fi

echo "Checking HP Insight CMU installation path."

if [ -d "$CMU_PATH" ]; then
   if [ -f "$CMU_PATH/etc/ActionAndAlertsFile.txt" ]; then
      # ok - looks like a valid installation
      echo "HP Insight CMU installation found." 
   else
      echo "$CMU_PATH/etc/ActionAndAlertsFile.txt does not exit. Exiting."
      exit 1
   fi
else 
   echo "$CMU_PATH is not a directory. Exiting."
   exit 1
fi

read -p "Do you have UGE HTML documentation placed on a webserver (y/n)? "
if [ "$REPLY" = "y" -o "$REPLY" = "Y" -o "$REPLY" = "yes" ]; then
   read -p "What is the URL (http://yourserver/documentation)?"
   if [ "$REPLY" != "" ]; then
      UGE_DOCUMENATION=$REPLY
   fi
else
   echo "Skipping adding a link to the documentation."
fi

###############################################################################
### Installation 
###############################################################################

echo "Installation of HP Insight CMU Univa Grid Engine custom menu."

# backup
date=`date +%s`
cp $CMU_PATH/etc/cmu_custom_menu $CMU_PATH/etc/cmu_custom_menu.UGE_backup_$date
# remove UGE integration when it exists as text between # UGE CMU START and # UGE CMU END
sed -i '/# UGE CMU START/,/# UGE CMU END/d' $CMU_PATH/etc/cmu_custom_menu
# append Univa custom menu to CMU
# resolve all placeholders for $SGE_ROOT and $SGE_CELL
sed -e 's|UGEPATH|'"$SGE_ROOT"'|g' ./custom_menu > /tmp/custom_menu_$$ 
sed -i -e 's|UGECELL|'"$SGE_CELL"'|g' /tmp/custom_menu_$$
# Set link to Guides if needed
if [ "$UGE_DOCUMENTATION" != "" ]; then
   echo "GUI;Univa Grid Engine|Grid Engine Guides;BROWSE $UGE_DOCUMENTATION" >>  /tmp/custom_menu_$$
fi
echo "# UGE CMU END" >> /tmp/custom_menu_$$

cat /tmp/custom_menu_$$ >> $CMU_PATH/etc/cmu_custom_menu
rm /tmp/custom_menu_$$

echo "Installation of Actions and Alerts"

# Put Univa Grid Engine related metrics right after "ACTIONS" in file
cp $CMU_PATH/etc/ActionAndAlertsFile.txt $CMU_PATH/etc/ActionAndAlertsFile.txt.UGE_backup_$date
# Remove UGE integration when it exists as text between # UGE CMU START and # UGE CMU END
sed -i '/# UGE CMU START/,/# UGE CMU END/d' $CMU_PATH/etc/ActionAndAlertsFile.txt
# Install Univa Grid Engine actions
sed -i -e '/^ACTIONS/r./actions' $CMU_PATH/etc/ActionAndAlertsFile.txt
# Set path to Univa Grid Engine installation.
sed -i -e 's@UGEPATH@'"$SGE_ROOT"'@g' $CMU_PATH/etc/ActionAndAlertsFile.txt

echo "Installation of Dynamic User Defined Host Groups"

echo "Warning: Commenting out original CMU_DYNAMIC_UG_INPUT_SCRIPTS value of $CMU_PATH/etc/cmuserver.conf"
echo "         Please check manually."
sed -i -e 's/^CMU_DYNAMIC_UG_INPUT_SCRIPTS/#CMU_DYNAMIC_UG_INPUT_SCRIPTS/g' $CMU_PATH/etc/cmuserver.conf
echo "# Univa Grid Engine Dynamic User Defined Host Group for Grid Engine jobs" >> $CMU_PATH/etc/cmuserver.conf
echo "CMU_DYNAMIC_UG_INPUT_SCRIPTS=$DIR/scripts/JobHostList.sh" >> $CMU_PATH/etc/cmuserver.conf

# Set path to UGE cell and CMU installation in the uge_settings.sh file which
# is used by some scripts.
cp ./scripts/uge_settings.sh_template ./scripts/uge_settings.sh
chmod +x ./scripts/uge_settings.sh
sed -i -e 's@UGEPATH@'"$SGE_ROOT"'@g' ./scripts/uge_settings.sh
sed -i -e 's@UGECELL@'"$SGE_CELL"'@g' ./scripts/uge_settings.sh
CMU_BIN_PATH=$CMU_PATH/bin
sed -i -e 's@CMUPATH@'"$CMU_BIN_PATH"'@g' ./scripts/uge_settings.sh

# set UGE path in template scripts
cp ./scripts/startup_execd.sh_template ./scripts/startup_execd.sh
chmod +x ./scripts/startup_execd.sh
sed -i -e 's@UGEPATH@'"$SGE_ROOT"'@g' ./scripts/startup_execd.sh
sed -i -e 's@UGECELL@'"$SGE_CELL"'@g' ./scripts/startup_execd.sh

cp ./scripts/startup_qmaster.sh_template ./scripts/startup_qmaster.sh
chmod +x ./scripts/startup_qmaster.sh
sed -i -e 's@UGEPATH@'"$SGE_ROOT"'@g' ./scripts/startup_qmaster.sh
sed -i -e 's@UGECELL@'"$SGE_CELL"'@g' ./scripts/startup_qmaster.sh

cp ./scripts/JobHostList.sh_template ./scripts/JobHostList.sh
chmod +x ./scripts/JobHostList.sh
sed -i -e 's@UGEPATH@'"$SGE_ROOT"'@g' ./scripts/JobHostList.sh

cp ./scripts/collect_gridengine_metrics.sh_template ./scripts/collect_gridengine_metrics.sh
chmod +x ./scripts/collect_gridengine_metrics.sh
sed -i -e 's@UGEPATH@'"$SGE_ROOT"'@g' ./scripts/collect_gridengine_metrics.sh
sed -i -e 's@CMUPATH@'"$CMU_BIN_PATH"'@g' ./scripts/collect_gridengine_metrics.sh

cp ./scripts/migrate_master.sh_template ./scripts/migrate_master.sh
chmod +x ./scripts/migrate_master.sh
sed -i -e 's@UGEPATH@'"$SGE_ROOT"'@g' ./scripts/migrate_master.sh
sed -i -e 's@UGECELL@'"$SGE_CELL"'@g' ./scripts/migrate_master.sh

cp ./scripts/create_restore_backup.sh_template ./scripts/create_restore_backup.sh
chmod +x ./scripts/create_restore_backup.sh
sed -i -e 's@UGEPATH@'"$SGE_ROOT"'@g' ./scripts/create_restore_backup.sh
sed -i -e 's@UGECELL@'"$SGE_CELL"'@g' ./scripts/create_restore_backup.sh

echo "Installation finished. Please restart CMU service."

