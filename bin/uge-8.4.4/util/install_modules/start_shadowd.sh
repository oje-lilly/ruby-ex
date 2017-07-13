#!/bin/sh

. $SGE_ROOT/$SGE_CELL/common/settings.sh
SGE_ARCH=`$SGE_ROOT/util/arch`

if [ $SGE_ARCH != "darwin-x64" -a $SGE_ARCH != "darwin-x86" ]; then
   $SGE_ROOT/bin/$SGE_ARCH/sge_shadowd &
else
   # when execd was installed the old way then start normal
   if [ -f $RC_PREFIX/$RC_DIR.$SGE_CLUSTER_NAME/$RC_FILE ]; then
      $SGE_ROOT/bin/$SGE_ARCH/sge_shadowd &
      return
   fi

   # have to create launchd script
   echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version=\"1.0\">
<dict>
   <key>Label</key>
   <string>com.univa.gridengine.$SGE_CLUSTER_NAME.sgeshadowd</string>
   <key>Program</key>
   <string>$SGE_ROOT/bin/$SGE_ARCH/sge_shadowd</string>
   <key>RunAtLoad</key>
   <true/>
   <key>EnvironmentVariables</key>
   <dict><key>SGE_ROOT</key>
      <string>$SGE_ROOT</string>
      <key>SGE_CELL</key>
      <string>$SGE_CELL</string>
      <key>SGE_CLUSTER_NAME</key>
      <string>$SGE_CLUSTER_NAME</string>
      <key>SGE_EXECD_PORT</key>
      <string>$SGE_EXECD_PORT</string>
      <key>SGE_QMASTER_PORT</key>
      <string>$SGE_QMASTER_PORT</string>
      <key>SGE_ND</key>
      <string>1</string>
      <key>DYLD_LIBRARY_PATH</key>
      <string>$SGE_ROOT/lib/$SGE_ARCH</string></dict>
   <key>StandardErrorPath</key>
   <string>/dev/null</string>
   <key>StandardOutPath</key>
   <string>/dev/null</string>
   <key>KeepAlive</key>
   <false/>
</dict>
</plist>
" > /Library/LaunchDaemons/com.univa.gridengine.$SGE_CLUSTER_NAME.sgeshadowd.plist

 # and start it
 launchctl load -F /Library/LaunchDaemons/com.univa.gridengine.$SGE_CLUSTER_NAME.sgeshadowd.plist
 launchctl start com.univa.gridengine.$SGE_CLUSTER_NAME.sgeshadowd
fi

