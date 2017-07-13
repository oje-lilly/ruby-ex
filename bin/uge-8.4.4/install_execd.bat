@echo off
rem #___INFO__MARK_BEGIN__
rem ###########################################################################
rem #
rem #  The contents of this file are made available subject to the terms of the
rem #  Apache Software License 2.0 ('The License').
rem #  You may not use this file except in compliance with The License.
rem #  You may obtain a copy of The License at
rem #  http://www.apache.org/licenses/LICENSE-2.0.html
rem #
rem #  Copyright (c) 2014 Univa Corporation.
rem #
rem ###########################################################################
rem #___INFO__MARK_END__


rem Note to developers:
rem Make sure all texts fit into a 80x25 character command prompt window!

break on

rem Check if batch extensions are available
rem set errorlevel to a non-zero value
verify other 2>nul

echo starting install_execd.bat >> c:\tmp\install_execd.bat.log 2>&1

rem setlocal sets errorlevel to 1 if extensions are not available
setlocal enabledelayedexpansion enableextensions
if !errorlevel! == 1 (
   rem exit if extensions are not available
   echo It seems that the batch script extensions are not installed or enabled.
   echo This install script needs these extensions to work.
   endlocal
   exit /b 1
)

rem we don't want the UGE clients to print debug info
set SGE_DEBUG_LEVEL=
set SGE_ND=

rem clear "global" variables we use in this script
set "AUTO="
set "AUTO_CONF_FILE="
set "UNINSTALL="
set "DO_ELEVATED_TASKS="
set "INSTALL_STARTER=false"

rem get my own hostname
call :proc_get_hostname MY_HOSTNAME

rem check command line arguments
rem this function sets the variables AUTO, AUTO_CONF_FILE and UNINSTALL
call :proc_parse_command_line %*

if "!DO_ELEVATED_TASKS!" == "true" (
   call :proc_do_elevated_tasks
) else if "!AUTO!" == "true" (
   call :proc_automatic_installation
) else if "!UNINSTALL!" == "true" (
   call :proc_interactive_uninstallation
) else if "!UNINSTALL!" == "false" (
   call :proc_interactive_installation
) else (
   echo Got unknown or invalid options...
)
exit /b !errorlevel!


rem ============================================================================
rem = Elevated tasks
rem ============================================================================
rem ----------------------------------------------------------------------------
rem proc_do_elevated_tasks
rem
rem Run the tasks that need elevated local Administrator permissions.
rem
rem modifies   nothing
rem returns    nothing
rem ----------------------------------------------------------------------------
:proc_do_elevated_tasks
   set "ret=0"

   call :proc_check_elevation
   if not !errorlevel! == 0 (
      echo.
      echo This installer sub-process is not running with elevated
      echo local Adminstrator permissions!
      echo Please follow the instructions in the main installation window again!
      echo.
      if "!AUTO!" == "false" (
         call :proc_wait_for_enter
      ) else (
         echo not running in elevated mode^^! >> c:\tmp\install_execd.bat.log 2>&1
      )
      set "ret=1"
   ) else (
      if "!UNINSTALL!" == "false" (
         if "!AUTO!" == "true" (
            rem automatic instalation

            call :proc_install_job_starter_service
            call :proc_set_perflib_permissions

            if "!INSTALL_STARTER!" == "true" (
               set "ADD_TO_RC=true"
               call :proc_install_starter_service
            )
         ) else (
            rem interactive installation

            rem copy and install the job starter service from C:\tmp to C:\Windows
            call :proc_install_job_starter_service

            if "!INSTALL_STARTER!" == "true" (
               rem if wanted by the user, copy and install the execd starter service
               call :proc_install_starter_service
            )
            rem setting perflib permission to allow UGE admin user to read load values
            call :proc_set_perflib_permissions
         )
      ) else (
         rem interactive uninstallation

         call :proc_remove_starter_service
      )

      if not "!AUTO!" == "true" (
         call :proc_wait_for_enter
      ) else (
         echo finished elevated tasks. >> c:\tmp\install_execd.bat.log 2>&1
      )
   )

   rem set errorlevel to 0
   ver >nul
   exit /b !ret!

rem ============================================================================
rem = Automatic installation
rem ============================================================================
:proc_automatic_installation
   setlocal enabledelayedexpansion enableextensions

   echo starting automatic installation
   call :proc_read_autoconf_file !AUTO_CONF_FILE!

   rem now we know where our UGE binaries are located, set a variable to qconf:
   set "QCONF=!MY_WIN_SGE_ROOT!\bin\win-x86\qconf.exe"
   set "ADMINRUN=!MY_WIN_SGE_ROOT!\utilbin\win-x86\adminrun.exe"

   rem check if pthreadVC2.dll is copied to C:\Windows
   call :proc_copy_my_files_to_tmp
   set "PATH=c:\tmp;%PATH%"

   rem set the variables needed to run qconf
   set "SGE_ROOT=!MY_WIN_SGE_ROOT!"
   set "SGE_CELL=!MY_SGE_CELL!"
   set "SGE_QMASTER_PORT=!MY_SGE_QMASTER_PORT!"
   set "SGE_EXECD_PORT=!MY_SGE_EXECD_PORT!"
   set "SGE_CLUSTER_NAME=!MY_SGE_CLUSTER_NAME!"

   rem we need the path_map file to use any UGE binary
   call :proc_write_path_map_file !MY_WIN_SGE_ROOT!\!MY_SGE_CELL!\common\path_map

   rem check if this host is an admin host - stop if not
   call :proc_check_hostname_resolving

   call :proc_write_settings_bat !MY_WIN_SGE_ROOT!\!MY_SGE_CELL!\common\settings.bat
   call :proc_write_sgeexecd_bat !MY_WIN_SGE_ROOT!\!MY_SGE_CELL!\common\sgeexecd.bat
   call :proc_create_local_config

   rem start this in elevated mode
   if "!MY_SGE_QMASTER_PORT!" == "" (
      set "sge_qmaster_port_param=0"
   ) else (
      set "sge_qmaster_port_param=!MY_SGE_QMASTER_PORT!"
   )
   set "adminrun_args=cmd.exe /c c:\tmp\install_execd.bat -elevated-tasks install true install_starter !ADD_TO_RC! auto !AUTO_CONF_FILE! !MY_WIN_SGE_ROOT! !MY_SGE_CELL! !sge_qmaster_port_param! %USERDOMAIN% %USERNAME% !g_sge_admin_pass!"
   call :proc_start_elevated !adminrun_args!
   set "adminrun_ars="

   call :proc_add_to_all_q

   if "!ADD_TO_RC!" == "false" (
      rem if we have no UGE Starter Service installed, we need to start the execd manually
      echo.
      echo Starting the execution daemon now.
      echo.
      call :proc_start_execd
   )
   call :proc_delete_my_files_from_tmp

   echo automatic installation finished >> c:\tmp\install_execd.bat.log 2>&1

   endlocal
   exit /b

rem ============================================================================
rem = Interactive installation
rem ============================================================================
rem ----------------------------------------------------------------------------
rem proc_interactive_installation
rem
rem Does the interactive execd installation
rem
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_interactive_installation
   setlocal enabledelayedexpansion enableextensions

   rem ----------------------------------------------------------------------------
   rem - Welcome screen
   rem ----------------------------------------------------------------------------

   cls
   echo.
   echo Welcome to the Grid Engine execution host installation
   echo ------------------------------------------------------
   echo.
   echo If you haven't installed the Grid Engine qmaster host yet, you must execute
   echo this step ^(with ^>install_qmaster^<^) prior the execution host installation.
   echo For a successful installation you need a running Grid Engine qmaster. It is
   echo also neccesary that this host is an administrative host.
   echo.
   echo You can verify your current list of administrative hosts with
   echo the command:
   echo.
   echo # qconf -sh
   echo.
   echo You can add an administrative host with the command:
   echo.
   echo # qconf -ah ^<hostname^>
   echo.
   call :proc_wait_for_enter

   rem ----------------------------------------------------------------------------
   rem - SGE_ROOT
   rem ----------------------------------------------------------------------------

   cls
   echo.
   echo Checking $SGE_ROOT directory
   echo ----------------------------
   echo.

   set "do_loop=true"
   :while_check_sge_root
      rem let the user enter SGGE_ROOT
      set ANSWER=

      if "%SGE_ROOT%" == "" (
         echo The Grid Engine root directory is not set!
         echo Please enter a correct path for SGE_ROOT in DOS or UNC notation
         echo or hit ^<RETURN^> to use the default.
         echo ^(If the directory is network mounted, using the UNC notation is preferred^).
         echo.
         echo Please note: If a mounted share is used ^(e.g. "X:\sge_root"^), the execution
         echo daemon cannot be started automatically at host boot time^^! Please use an UNC
         echo path ^(e.g. "\\server\share\sge_root"^) instead^^!
         echo.

         set "FULL_SCRIPT_PATH=%~f0"
         call :proc_get_installer_basename !FULL_SCRIPT_PATH! current_dir
         set "ANSWER=!current_dir!"
         set /p ANSWER="[!current_dir!] >> "

         rem empty/invalid answers will be handled later
         set "MY_WIN_SGE_ROOT=!ANSWER!"
         set "SGE_ROOT=!MY_WIN_SGE_ROOT!"
      ) else (
         echo The Grid Engine root directory in DOS or UNC notation is:
         echo.
         echo   $SGE_ROOT = %SGE_ROOT%
         echo.
         echo Please note: If this directory is located on a mounted share ^(e.g. "X:\sge_root"^),
         echo the execution daemon cannot be started automatically at host boot time^^! Please use
         echo the equivalent UNC path ^(e.g. "\\server\share\sge_root"^) instead^^!
         echo.
         echo If this directory is not correct ^(e.g. it may contain an automounter
         echo prefix^) enter the correct path to this directory or hit ^<RETURN^>

         set "ANSWER=%SGE_ROOT%"
         set /p ANSWER="to use default [%SGE_ROOT%] >> "
         set "MY_WIN_SGE_ROOT=!ANSWER!"
      )

      rem check if this dir exists
      call :proc_is_dir_valid "!MY_WIN_SGE_ROOT!"
      if !errorlevel! == 0 (
         rem directory doesn't exist
         echo.
         echo The directory
         echo !MY_WIN_SGE_ROOT!
         echo cannot be read! Either the directory is wrong, or the current user
         echo doesn't have the permissions to read it.
         echo.
         set MY_WIN_SGE_ROOT=
      )

      rem now MY_WIN_SGE_ROOT should be set properly - if not, ask again
      if "!MY_WIN_SGE_ROOT!" == "" (
         echo.
         echo.
      ) else (
         set "do_loop=false"
      )
   if "!do_loop!" == "true" goto :while_check_sge_root

   echo.
   echo Your $SGE_ROOT directory in DOS or UNC notation:
   echo !MY_WIN_SGE_ROOT!
   echo.

   call :proc_wait_for_enter

   rem now we know where our UGE binaries are located, set a variable to qconf:
   set "QCONF=!MY_WIN_SGE_ROOT!\bin\win-x86\qconf.exe"
   set "ADMINRUN=!MY_WIN_SGE_ROOT!\utilbin\win-x86\adminrun.exe"

   rem make sure SGE_ROOT is set
   set "SGE_ROOT=!MY_WIN_SGE_ROOT!"

   rem ----------------------------------------------------------------------------
   rem - SGE_CELL
   rem ----------------------------------------------------------------------------

   cls
   echo.
   echo Grid Engine cells
   echo -----------------
   echo.
   echo Please enter cell name which you used for the sge_qmaster

   set ANSWER=default
   set /p ANSWER="installation or press <RETURN> to use [default] >> "
   set "MY_SGE_CELL=!ANSWER!"

   rem check if the default dir exists
   call :proc_is_dir_valid "!MY_WIN_SGE_ROOT!\!MY_SGE_CELL!"
   if !errorlevel! == 0 (
      echo Obviously there was no sge_master installation yet^^!
      echo Call ^>install_qmaster^<
      echo on the machine which shall run the sge_qmaster
      endlocal
      exit /b 1
   ) else (
      echo Using cell: ^>!MY_SGE_CELL!^<
      echo.
      set "SGE_CELL=!MY_SGE_CELL!"
   )

   rem parse the contents of the settings.sh and the boostrap file
   set "SETTINGS_SH_PATH=!MY_WIN_SGE_ROOT!\!MY_SGE_CELL!\common\settings.sh"
   set "BOOTSTRAP_PATH=!MY_WIN_SGE_ROOT!\!MY_SGE_CELL!\common\bootstrap"
   call :proc_read_settings_sh !SETTINGS_SH_PATH!
   call :proc_read_bootstrap !BOOTSTRAP_PATH!

   call :proc_copy_my_files_to_tmp


   rem set path to find the pthreadVC2.dll in c:\tmp
   set "PATH=c:\tmp;%PATH%"

   call :proc_wait_for_enter

   rem ----------------------------------------------------------------------------
   rem - UGE admin user
   rem ----------------------------------------------------------------------------

   cls
   echo.
   echo Univa Grid Engine admin user
   echo ----------------------------
   echo.
   echo In the bootstrap file, the "admin_user" is defined as
   echo   ^>^>%bootstrap_admin_user%^<^<
   echo.
   echo The current user is
   echo   ^>^>%USERDOMAIN%\%USERNAME%^<^<
   echo.
   set "do_error_exit=true"
   if /i !bootstrap_admin_user! == %USERNAME% (
      echo Is this the user you want to use as the Univa Grid Engine admin user
      set "ANSWER=y"
      set /p ANSWER="on the current host? (y/n) [y] >> "
      if /i "!ANSWER!" == "y" (
         echo.
         echo Using the current user as Univa Grid Engine admin user.
         echo.
         set "do_error_exit=false"
      ) else (
         echo.
         echo Please start the installation again as the user you want to use as
         echo the Univa Grid Engine admin user!
         echo.
      )
   ) else (
      echo.
      echo The user names do not match^^! Please start the installation again as
      echo the Univa Grid Engine admin user!
      echo.
   )
   if "!do_error_exit!" == "true" call :proc_error_exit 2>nul

   call :proc_wait_for_enter

   rem ----------------------------------------------------------------------------
   rem - SGE_EXECD_PORT
   rem ----------------------------------------------------------------------------
   call :proc_check_execd_port

   rem ----------------------------------------------------------------------------
   rem - Explain path_map file
   rem ----------------------------------------------------------------------------

   :do_explain_path_map_file
   cls
   echo.
   echo Defining path mappings between UNIX and Windows
   echo -----------------------------------------------
   echo.
   echo This execution daemon will get sent several paths from the QMaster.
   echo Because the QMaster knows only UNIX paths, the execution daemon will
   echo have to translate these paths from UNIX to Windows format.
   echo.
   echo This can't be done fully automatic, because mount points etc. usually
   echo differ between UNIX and Windows. The execution daemon needs to know
   echo some base paths in order to translate all paths.
   echo.
   echo These base paths are the users home directory, a temporary directory
   echo and the directory where the certificates can be found.
   echo.
   echo These paths will be defined in the next steps
   echo.
   call :proc_wait_for_enter


   rem ----------------------------------------------------------------------------
   rem - Check for previous installations
   rem ----------------------------------------------------------------------------

   set "skip_further_interactive_part=false"
   if exist !MY_WIN_SGE_ROOT!\!MY_SGE_CELL!\common\path_map (
      cls
      echo.
      echo Checking for already available path mapping data
      echo ------------------------------------------------
      echo.
      echo Reading ^>path_map^< file from
      echo !MY_WIN_SGE_ROOT!\!MY_SGE_CELL!\common

      call :proc_read_path_map_file !MY_WIN_SGE_ROOT!\!MY_SGE_CELL!\common\path_map

      echo.
      echo The existing path_map file contains these paths:
      echo.
      call :proc_echo_path_map
      echo.
      echo Shall we use these paths ^(y^) or do you want to enter new ones ^(n^)?
      set "ANSWER=y"
      set /p ANSWER="(y/n) [y] >> "

      if /i "!ANSWER!" == "y" (
         set "skip_further_interactive_part=true"
         echo.
         echo Using these paths.
         echo.
      ) else (
         echo.
         echo You chose to enter new paths.
         echo.
      )
      call :proc_wait_for_enter
   )

   rem we got all info from the old path_map file, no need to ask the user again
   if "!skip_further_interactive_part!" == "true" goto label_after_path_mappings

   rem ----------------------------------------------------------------------------
   rem - Define sgeCA path map
   rem ----------------------------------------------------------------------------

   set "do_loop=true"
   :while_sgeCA_dir_loop
      cls
      echo.
      echo Defining the mapping of the ^>sgeCA^< directory
      echo ---------------------------------------------
      echo.
      echo During QMaster installation, the certificates to encrypt and decrypt
      echo the Windows user passwords were created on the QMaster host in the directory
      if "!MY_SGE_QMASTER_PORT!" == "" (
         echo /var/sgeCA/sge_qmaster
      ) else (
         echo /var/sgeCA/port!MY_SGE_QMASTER_PORT!
      )
      echo.
      echo This directory must be available on this Windows execution host. It can
      echo be made available either via a network share or by copying it to this host.
      echo.
      echo Please enter the path of the ^>sgeCA^< directory on the QMaster host
      set ANSWER=/var/sgeCA
      set /p ANSWER="or press <RETURN> to use [/var/sgeCA] >> "
      set MY_UNIX_SGECA_DIR=!ANSWER!

      echo.
      echo Please enter the DOS/UNC path of the ^>sgeCA^< directory on this Windows host
      set ANSWER=
      set /p ANSWER=">> "
      call :proc_is_dir_valid "!ANSWER!"
      if !errorlevel! == 0 (
         echo.
         echo Please specify a valid and existing directory!
         echo.
      ) else (
         set MY_WIN_SGECA_DIR=!ANSWER!
         set "do_loop=false"
         echo.
      )
      call :proc_wait_for_enter
      if "!do_loop!" == "true" goto :while_sgeCA_dir_loop


   rem ----------------------------------------------------------------------------
   rem - Define home dir path map
   rem ----------------------------------------------------------------------------

   set "do_loop=true"
   :while_home_dir_loop
      cls
      echo.
      echo Defining the mapping of the users home directory
      echo ------------------------------------------------
      echo.
      echo Please specify the users home base directory, e.g. "/home" and not
      echo "/home/jdoe", both for the UNIX and the Windows path.
      echo.
      echo The users home directory paths should point to the same directory
      echo on UNIX and Windows.  If they point to two different directories,
      echo most of the execution host functionality will work, but it can also
      echo cause problems.
      echo.
      echo Please enter the users home dir on the QMaster host in UNIX notation

      set ANSWER=/home
      set /p ANSWER="or press <RETURN> to use [/home] >> "
      set MY_UNIX_HOME_DIR=!ANSWER!

      echo.
      echo Please enter the users home dir on this Windows host in DOS/UNC notation
      set ANSWER=
      set /p ANSWER=">> "
      call :proc_is_dir_valid "!ANSWER!"
      if !errorlevel! == 0 (
         echo.
         echo Please specify a valid and existing directory!
         echo.
      ) else (
         set MY_WIN_HOME_DIR=!ANSWER!
         set "do_loop=false"
         echo.
      )
      call :proc_wait_for_enter
      if "!do_loop!" == "true" goto :while_home_dir_loop


   rem ----------------------------------------------------------------------------
   rem - Define temporary directory path map
   rem ----------------------------------------------------------------------------

   set "do_loop=true"
   :while_tmp_dir_loop
      cls
      echo.
      echo Defining the mapping of the temporary directories
      echo -------------------------------------------------
      echo.
      echo The paths of the temporary directory on UNIX and Windows can point to
      echo two different directories, the execution daemon just needs to know both
      echo paths. Please specify the base directory also here.
      echo.
      echo ^^!^^! On the Windows host, this directory currently must be the directory
      echo     "C:\tmp" and it must be writeable for all users ^^!^^!
      echo.
      echo Please enter the tmp dir on the UNIX hosts in UNIX notation

      set ANSWER=/tmp
      set /p ANSWER="or press <RETURN> to use [/tmp] >> "
      set MY_UNIX_TMP_DIR=!ANSWER!

      echo.
      set ANSWER=
      echo Please enter the tmp dir on this Windows host in DOS/UNC notation
      set /p ANSWER=">> "
      call :proc_is_dir_valid "!ANSWER!"
      if !errorlevel! == 0 (
         echo.
         echo Please specify a valid and existing directory!
         echo.
      ) else (
         set MY_WIN_TMP_DIR=!ANSWER!
         set "do_loop=false"
         echo.
      )
      call :proc_wait_for_enter
      if "!do_loop!" == "true" goto :while_tmp_dir_loop


   rem ----------------------------------------------------------------------------
   rem - Define execd spool dir
   rem ----------------------------------------------------------------------------

   set "do_loop=true"
   :while_enter_execd_spool_dir
      cls
      echo.
      echo Execd spool directory configuration
      echo -----------------------------------
      echo.

      call :proc_get_execd_spool_dir_from_conf !MY_HOSTNAME! LOCAL_UNIX_EXECD_SPOOL

      if "!LOCAL_UNIX_EXECD_SPOOL!" == "" (
         echo Please define a spool directory for this execution host.
         echo.
         echo ATTENTION: On Windows systems, the spool directory MUST be located
         echo on a local disk. If you install an execution daemon on a Windows system
         echo without a local spool directory, the execution host is unusable.
         echo.
         echo Please enter the spool directory in DOS/UNC notation
         set ANSWER=
         set /p ANSWER=">> "
         echo.
         call :proc_is_dir_valid "!ANSWER!"
         if !errorlevel! == 0 (
            echo.
            echo Please specify a valid and existing directory!
            echo.
         ) else (
            set "do_loop=false"
            set MY_WIN_EXECD_SPOOL=!ANSWER!
            echo Your execd spool directory in DOS/UNC notation:
            echo !MY_WIN_EXECD_SPOOL!
            echo.
            set do_loop=false
         )
      ) else (
         echo The local configuration of the execution host already exists in the QMaster.
         echo ^(Use "qconf -sconf !MY_HOSTNAME!" to see it.^)
         echo.
         echo This installer needs to overwrite it in order to continue. Do you want to

         set ANSWER=y
         set /p ANSWER="overwrite the existing local configuration? (y/n) ('n' will abort) [y] >> "
         if /i not "!ANSWER!" == "y" (
            endlocal
            exit /b 1
         )

         echo.
         echo Removing the old local configuration of execution host !MY_HOSTNAME!
         rem set errorlevel to 0
         ver > nul
         !QCONF! -dconf !MY_HOSTNAME!
         echo.
      )
      call :proc_wait_for_enter
      if "!do_loop!" == "true" goto :while_enter_execd_spool_dir

   rem this gets always set to the same value
   set "MY_UNIX_EXECD_SPOOL=/execd_spool_dir/win-x86/placeholder"


   rem ----------------------------------------------------------------------------
   rem - Show and confirm path mappings
   rem ----------------------------------------------------------------------------

   cls
   echo.
   echo Confirming path mappings
   echo ------------------------
   echo.
   echo These path  mappings will be saved:
   echo.
   call :proc_echo_path_map
   echo.
   set ANSWER=y
   set /p ANSWER="Use these paths (y) or enter them again (n)? (y/n) [y] >> "
   if /i "!ANSWER!" == "n" (
      rem !!!! this jumps back to the "Defining path mappings" mask !!!!
      goto :do_explain_path_map_file
   )

   call :proc_write_path_map_file !MY_WIN_SGE_ROOT!\!MY_SGE_CELL!\common\path_map

   echo.
   echo path_map file successfully created^^!
   echo.
   call :proc_wait_for_enter

:label_after_path_mappings

   rem ----------------------------------------------------------------------------
   rem - Check hostname resolving - qconf -sh <hostname>
   rem -  - can't be done earlier because qconf needs the path_map file -
   rem ----------------------------------------------------------------------------
   call :proc_check_hostname_resolving


   rem ----------------------------------------------------------------------------
   rem - Create local configuration
   rem ----------------------------------------------------------------------------

   cls
   echo.
   echo Creating local configuration
   echo ----------------------------
   call :proc_create_local_config
   if !errorlevel! == 0 (
      echo Local configuration for host ^>!MY_HOSTNAME!^< created.
      echo.
   ) else (
      echo Failed creating configuration for host ^>!MY_HOSTNAME!^<.
   )

   echo.
   call :proc_wait_for_enter

   rem ----------------------------------------------------------------------------
   rem - Write settings.bat file
   rem ----------------------------------------------------------------------------

   cls
   echo .
   echo Writing settings.bat and sgeexecd.bat file
   echo ------------------------------------------
   echo.
   echo Writing settings.bat file to
   echo ^>!MY_WIN_SGE_ROOT!\!MY_SGE_CELL!\common\^<
   call :proc_write_settings_bat !MY_WIN_SGE_ROOT!\!MY_SGE_CELL!\common\settings.bat
   echo.
   echo Done writing settings.bat file

   echo.
   echo Writing sgeexecd.bat file to
   echo ^>!MY_WIN_SGE_ROOT!\!MY_SGE_CELL!\common\^<
   call :proc_write_sgeexecd_bat !MY_WIN_SGE_ROOT!\!MY_SGE_CELL!\common\sgeexecd.bat
   echo.
   echo Done writing sgeexecd.bat file

   call :proc_wait_for_enter

   rem ----------------------------------------------------------------------------
   rem - Install services
   rem ----------------------------------------------------------------------------

   cls
   echo.
   echo Installing UGE services
   echo -----------------------
   echo.
   echo Do you want to install a service that automatically starts the execution
   set ANSWER=y
   set /p ANSWER="daemon at machine boot time? (y/n) [y] >> "
   if /i "!ANSWER!" == "y" (
      echo The UGE Starter Service will be installed.
      set "INSTALL_STARTER=true"
   ) else (
      echo The UGE Starter Service will NOT be installed.
   )

   echo.
   call :proc_wait_for_enter

   rem ----------------------------------------------------------------------------
   rem - Add to all.q
   rem ----------------------------------------------------------------------------

   cls
   echo.
   echo Adding a queue for this host
   echo ----------------------------
   echo.
   echo We can now add a queue instance for this host:
   echo.
   echo    - it is added to the ^>allhosts^< hostgroup
   echo    - it is made sure the all.q queue instance on this host
   echo      provides at least one slot
   echo.
   echo You do not need to add this host now, but before running jobs on this host
   echo.
   set ANSWER=y
   set /p ANSWER="Do you want to add a default queue instance for this host (y/n) [y] >> "
   if /i "!ANSWER!" == "y" (
      call :proc_add_to_all_q
   )

   call :proc_wait_for_enter

   rem ----------------------------------------------------------------------------
   rem - Performing elevated tasks
   rem ----------------------------------------------------------------------------

   cls
   echo.
   echo Performing tasks with elevated Administrator permissions
   echo --------------------------------------------------------
   echo.
   echo Now several tasks  have to be performed with elevated Administrator permissions.
   echo These tasks are:
   echo a^) Copying these files to c:\Windows in order to make them accessible at boot time:
   echo * pthreadVC2.dll - needed by most UGE executables
   echo * SGE_Starter_Service.exe - starts the execution daemon at boot time
   echo * UGE_JS_Service.exe - does the job execution in the Windows environment
   echo * SGE_Starter.exe - starter method needed for GUI jobs on Windows Vista and later
   echo b^) Installing the SGE_Starter_Service and the UGE_JS_Service
   echo c^) Adding the UGE admin user to the access list of the perflib registry key.
   echo     This registry key provides load values, but is accessible by default only
   echo     by interactive users, not by services.
   echo.
   echo Please enter the Administrator name and password in the Windows User Account
   echo Control dialog box that will pop up now and then follow the steps in the
   echo new cmd window that is going to open. If the dialog box states that it is
   echo already running as this user, please enter the user name and the password,
   echo anyway, just clicking OK won't work!
   echo.
   call :proc_wait_for_enter
   echo.

   rem copy the installer, services and pthreadVC2.dll to tmp, so the elevated Administrator
   rem user without network permissions may use them
   call :proc_copy_my_files_to_tmp

   rem start this in elevated mode
   if "!MY_SGE_QMASTER_PORT!" == "" (
      set "sge_qmaster_port_param=0"
   ) else (
      set "sge_qmaster_port_param=!MY_SGE_QMASTER_PORT!"
   )
   set "adminrun_args=cmd.exe /c c:\tmp\install_execd.bat -elevated-tasks install true install_starter !INSTALL_STARTER! !MY_WIN_SGE_ROOT! !MY_SGE_CELL! !sge_qmaster_port_param! %USERDOMAIN% %USERNAME% !g_sge_admin_pass!"
   call :proc_start_elevated !adminrun_args!
   if !errorlevel! == 0 (
      echo Finished successfully.
   ) else (
      echo Performing these tasks failed^^! Likely executing jobs on this host
      echo will not be possible^^!
   )
   set "adminrun_args="

   rem clean up c:\tmp
   call :proc_delete_my_files_from_tmp

   call :proc_wait_for_enter

   rem ----------------------------------------------------------------------------
   rem - Starting execd
   rem ----------------------------------------------------------------------------

   if "!INSTALL_STARTER!" == "false" (
      cls
      echo.
      echo Starting execution daemon
      echo -------------------------
      echo.
      echo Please wait until the execution daemon is started...
      echo.

      call :proc_start_execd

      echo.
      call :proc_wait_for_enter
   )


   rem ----------------------------------------------------------------------------
   rem - Summary page
   rem ----------------------------------------------------------------------------

   cls
   echo.
   echo Using Grid Engine
   echo -----------------
   echo.
   echo You should now enter the command:
   echo.
   echo    !MY_WIN_SGE_ROOT!\!MY_SGE_CELL!\common\settings.bat
   echo.
   echo This will set or expand the following environment variables:
   echo.
   echo   - SGE_ROOT         ^(always necessary^)
   echo   - SGE_CELL         ^(if you are using a cell other than ^>default^<^)
   echo   - SGE_CLUSTER_NAME ^(just for compatibility^)
   echo   - SGE_QMASTER_PORT ^(if you haven't added the service ^>sge_qmaster^<^)
   echo   - SGE_EXECD_PORT   ^(if you haven't added the service ^>sge_execd^<^)
   echo   - PATH             ^(to find the Grid Engine binaries^)
   echo.

   set ANSWER=
   set /p ANSWER="Hit <RETURN> to end execution daemon installation >> "

   echo.
   echo Your execution daemon installation is now complete.

   endlocal
   exit /b
   rem end of :proc_interactive_installation



rem ============================================================================
rem = Interactive uninstallation
rem ============================================================================
rem ----------------------------------------------------------------------------
rem proc_interactive_uninstallation
rem
rem Does the interactive execd uninstallation
rem
rem modifies   nothing
rem returns    nothing
rem ----------------------------------------------------------------------------
:proc_interactive_uninstallation
   rem ----------------------------------------------------------------------------
   rem - Welcome screen
   rem ----------------------------------------------------------------------------

   setlocal enabledelayedexpansion enableextensions

   cls
   echo Grid Engine uninstallation
   echo --------------------------
   echo.

   if "%SGE_ROOT%" == "" (
      echo %%SGE_ROOT%% is not set^^!
      echo Please set %%SGE_ROOT%% and start the uninstallation again^^!
      call :proc_error_exit 2>nul
   )

   echo You are going to uninstall the execution host %MY_HOSTNAME%^^!
   echo Please enter "q" if you are not sure if you really want to do this!
   echo.
   echo.
   call :proc_wait_for_enter

   set "QCONF=%SGE_ROOT%\bin\win-x86\qconf.exe"
   set "QSTAT=%SGE_ROOT%\bin\win-x86\qstat.exe"
   set "QMOD=%SGE_ROOT%\bin\win-x86\qmod.exe"
   set "ADMINRUN=%SGE_ROOT%\utilbin\win-x86\adminrun.exe"
   set "MY_WIN_SGE_ROOT=%SGE_ROOT%"

   rem ----------------------------------------------------------------------------
   rem - SGE_EXECD_PORT
   rem ----------------------------------------------------------------------------
   call :proc_check_execd_port

   rem ----------------------------------------------------------------------------
   rem - Check hostname resolving - qconf -sh <hostname>
   rem ----------------------------------------------------------------------------
   call :proc_check_hostname_resolving

   cls

   !QCONF! -se !MY_HOSTNAME!
   if !errorlevel! == 0 (
      echo Removing execution host !MY_HOSTNAME! now!
      echo Disabling queues now!
      call :proc_disable_host_queues !MY_HOSTNAME!
      call :proc_suspend_host_queues !MY_HOSTNAME!
      call :proc_suspend_host_jobs !MY_HOSTNAME!
      call :proc_reschedule_host_jobs !MY_HOSTNAME!
      call :proc_stop_execd !MY_HOSTNAME!
      call :proc_remove_host_queues !MY_HOSTNAME!
      call :proc_remove_spool_dir !MY_HOSTNAME!
      call :proc_remove_references !MY_HOSTNAME!
      call :proc_remove_execd !MY_HOSTNAME!

      call :proc_copy_my_files_to_tmp

      if "!SGE_QMASTER_PORT!" == "" (
         set "sge_qmaster_port_param=0"
      ) else (
         set "sge_qmaster_port_param=!SGE_QMASTER_PORT!"
      )
      set "adminrun_args=cmd.exe /c c:\tmp\install_execd.bat -elevated-tasks install false install_starter !INSTALL_STARTER! %SGE_ROOT% %SGE_CELL% !sge_qmaster_port_param! %USERDOMAIN% %USERNAME% !g_sge_admin_pass!"
      call :proc_start_elevated !adminrun_args!
      if not "!errorlevel!" == "0" (
         echo Uninstalling the UGE Starter Service failed^^!
      )
      set "adminrun_args="
      call :proc_delete_my_files_from_tmp
   ) else (
      echo !MY_HOSTNAME! is not an execution host"
   )
   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem ----------------------------------------------------------------------------
rem Procedures
rem ----------------------------------------------------------------------------
rem ----------------------------------------------------------------------------
rem ----------------------------------------------------------------------------
rem proc_disable_host_queues
rem
rem Disable all queue instances that reside on the given host
rem
rem param[in]  %1  The hostname
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_disable_host_queues
   setlocal enabledelayedexpansion enableextensions
   set "exechost=%1"

   rem find all queues where this host is referenced in
   for /f "tokens=1,2 delims=@ " %%1 in ('!QSTAT! -F -l h^=!exechost!') do (
      if "%%2" == "!exechost!" (
         rem disable these queues
         echo Disabling queue %%1 now
         !QMOD! -d %%1@!exechost!
      )
   )
   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_suspend_host_queues
rem
rem Suspend all queue instances that reside on the given host
rem
rem param[in]  %1  The hostname
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_suspend_host_queues
   setlocal enabledelayedexpansion enableextensions
   set "exechost=%1"

   rem find all queues where this host is referenced in
   for /f "tokens=1,2 delims=@ " %%1 in ('!QSTAT! -F -l h^=!exechost!') do (
      if "%%2" == "!exechost!" (
         rem suspend these queues
         echo Suspending queue %%1 now
         !QMOD! -sq %%1@!exechost!
      )
   )
   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_suspend_host_jobs
rem
rem Suspend all jobs that "run" on the given host
rem
rem param[in]  %1  The hostname
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_suspend_host_jobs
   setlocal enabledelayedexpansion enableextensions
   set "exechost=%1"

   rem find all queues where this host is referenced in
   for /f "tokens=1,2 delims=@ " %%1 in ('!QSTAT! -F -l h^=!exechost!') do (
      if "%%2" == "!exechost!" (
         rem suspend all jobs in these queues
         echo Suspending Jobs on queue %%1 now
         !QMOD! -sj %%1@!exechost!
      )
   )
   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_reschedule_host_jobs
rem
rem Reschedule all jobs that "run" on the given host
rem
rem param[in]  %1  The hostname
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_reschedule_host_jobs
   setlocal enabledelayedexpansion enableextensions
   set "exechost=%1"

   rem find all queues where this host is referenced in
   for /f "tokens=1,2 delims=@ " %%1 in ('!QSTAT! -F -l h^=!exechost!') do (
      if "%%2" == "!exechost!" (
         rem reschedule all jobs in these queues
         echo Rescheduling Jobs on queue %%1 now
         !QMOD! -r %%1@!exechost!
      )
   )

   rem find all queues where this host is referenced in
   for /f "tokens=1,2 delims=@ " %%1 in ('!QSTAT! -ne -F -l h^=!exechost!') do (
      if "%%2" == "!exechost!" (
         rem force reschedule all jobs in these queues
         echo There are still running jobs on %%1!
         !QMOD! -f -r %%1@!exechost!
      )
   )

   rem find all queues where this host is referenced in
   for /f "tokens=1,2 delims=@ " %%1 in ('!QSTAT! -ne -F -l h^=!exechost!') do (
      if "%%2" == "!exechost!" (
         rem warn aoubt still running jobs
         echo There are still running jobs on %%1!
         echo To make sure that no data will be lost, the uninstallation
         echo of this execution host stops now!
         echo Please check the running jobs and run uninstall again!
         call :proc_error_exit 2>nul
      )
   )
   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_stop_execd
rem
rem Stop the execd on the given host
rem
rem param[in]  %1  The hostname
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_stop_execd
   setlocal enabledelayedexpansion enableextensions
   set "exechost=%1"

   echo Stopping exec daemon %1 now!
   !QCONF! -ke !exechost!
   call :proc_sleep 1

   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_remove_host_queues
rem
rem Remove the queue instances that reside on the given host
rem
rem param[in]  %1  The hostname
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_remove_host_queues
   setlocal enabledelayedexpansion enableextensions
   set "exechost=%1"

   rem find all queues where this host is referenced in
   for /f "tokens=1,2 delims=@ " %%1 in ('!QSTAT! -F -l h^=!exechost!') do (
      if "%%2" == "!exechost!" (
         rem delete all queue instances of this exec host
         echo Deleting queue %%1

         for /f %%a in ('!QCONF! -shgrpl') do (
            echo Removing host !exechost! from hostgroup %%a
            !QCONF! -dattr hostgroup hostlist !exechost! %%a
         )
      )
   )
   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_remove_spool_dir
rem
rem Remove the execd spool dir on the given host
rem
rem param[in]  %1  The hostname
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_remove_spool_dir
   setlocal enabledelayedexpansion enableextensions
   set "exechost=%1"

   rem on Windows, we have a local execd spool dir that can be found in the path_map file
   for /f "tokens=1,2 delims=, " %%1 in (%SGE_ROOT%\%SGE_CELL%\common\path_map) do (
      if "%%1" == "/execd_spool_dir/win-x86/placeholder" (
         echo Removing local spool directory ^[%%2^]
         rd /s /q %%2\!exechost!
      )
   )
   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_remove_references
rem
rem Remove all references of queues instances that reside on the given host
rem
rem param[in]  %1  The hostname
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_remove_references
   setlocal enabledelayedexpansion enableextensions
   set "exechost=%1"

   for /f %%a in ('!QCONF! -sql') do (
      !QCONF! -purge queue "*" %%a@!exechost!
   )
   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_remove_execd
rem
rem Remove the execd itself
rem
rem param[in]  %1  The hostname
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_remove_execd
   setlocal enabledelayedexpansion enableextensions
   set "exechost=%1"

   echo Removing exec host !exechost! now!
   !QCONF! -ds !exechost!
   call :proc_sleep 1
   !QCONF! -de !exechost!
   call :proc_sleep 1
   !QCONF! -dh !exechost!
   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_remove_starter_service
rem
rem Remove all the Univa Grid Engine Starter Service, the Univa Grid Engine
rem Job Starter Service, the SGE_Starter.exe binary and the pthreadVC2.dll.
rem
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_remove_starter_service
   setlocal enabledelayedexpansion enableextensions
   rem ask user to uninstall starter service
   echo Do you want to uninstall the "Univa Grid Engine Starter Service"
   set "ANSWER=y"
   set /p ANSWER="that starts the execution daemon at system boot time? (y/n) [y] >> "
   if /i "!ANSWER!" == "y" (
      rem uninstall the starter service
      echo.
      echo Uninstalling the "Univa Grid Engine Starter Service".

      rem stop starter service
      net stop "Univa Grid Engine Starter Service"

      rem uninstall the starter service
      %WINDIR%\UGE_Starter_Service.exe -uninstall

      rem delete the starter service binary
      del "%WINDIR%\UGE_Starter_Service.exe"

      echo.
      echo Univa Grid Engine Starter Service successfully uninstalled
   )

   rem ask user to uninstall job starter service
   echo.
   echo.
   echo Do you want to uninstall the "Univa Grid Engine Job Starter Service"
   set "ANSWER=y"
   set /p ANSWER="that starts the jobs in the native Windows envirnment? (y/n) [y] >> "
   if /i "!ANSWER!" == "y" (
      rem uninstall the starter service
      echo.
      echo Uninstalling the "Univa Grid Engine Job Starter Service".

      rem stop job starter service
      net stop "Univa Grid Engine Job Starter Service"

      %WINDIR%\uge_js_service.exe -clear-perflib-perms !g_sge_admin_domain!\!g_sge_admin_user!

      rem uninstall the job starter service
      %WINDIR%\uge_js_service.exe -uninstall

      rem delete the job starter service binary
      del "%WINDIR%\uge_js_service.exe"

      rem delete the pthreadVC2.dll
      del "%WINDIR%\pthreadVC2.dll"

      rem delete SGE_Starter.exe
      del "%WINDIR%\SGE_Starter.exe"

      echo.
      echo Univa Grid Engine Job Starter Service successfully uninstalled
   )
   echo.
   endlocal
   exit /b 0

rem ----------------------------------------------------------------------------
rem proc_check_execd_port
rem
rem Does the "Grid Engine TCP/IP communication service" dialog
rem
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_check_execd_port
   setlocal enabledelayedexpansion enableextensions
   cls
   echo.
   echo Grid Engine TCP/IP communication service
   echo ----------------------------------------
   :while_check_execd_port
      echo.
      set "do_loop=false"

      if not "%SGE_EXECD_PORT%" == "" (
         echo The port for sge_execd.exe is set to
         echo.
         echo   SGE_EXECD_PORT = %SGE_EXECD_PORT%
      ) else (
         call :proc_get_service_by_name sge_execd execd_port_from_service
         call :proc_get_service_by_name sge_qmaster qmaster_port_from_service

         if "!execd_port_from_service!" == "0" (
            echo The port for sge_execd is neither defined in the environment
            echo nor as service.
            echo.
            echo Please add the entries for sge_execd and sge_qmaster to the
            echo services file ^(usually in C:\Windows\system32\drivers\etc^),
            echo the format is the same as in the /etc/services file on UNIX.
            echo.
            echo When the entry is added, hit RETURN to try again.

            set "do_loop=true"
         ) else (
            echo The port for sge_execd is currently set as service.
            echo.
            echo    sge_execd service set to port !execd_port_from_service!
            echo.
         )
         if "!do_loop!" == "false" (
            if "!qmaster_port_from_service!" == "0" (
               echo The port for sge_qmaster is neither defined in the environment
               echo nor as service.
               echo.
               echo Please add the entries for sge_qmaster and sge_execd to the
               echo services file ^(usually in C:\Windows\system32\drivers\etc^),
               echo the format is the same as in the /etc/services file on UNIX.
               echo.
               echo When the entry is added, hit RETURN to try again.

               set "do_loop=true"
            )
         )
      )
      echo.
      call :proc_wait_for_enter
   if "!do_loop!" == "true" goto :while_check_execd_port

   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_check_hostname_resolving
rem
rem Does the "Checking hostname resolving" dialog
rem
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_check_hostname_resolving
   setlocal enabledelayedexpansion enableextensions
   cls
   echo.
   echo Checking hostname resolving
   echo ---------------------------
   echo.

   set do_loop=true
   :while_check_resolving
      rem check if this host is configured as admin host
      set found=false
      for /f "delims=. " %%i in ('!QCONF! -sh') do if /i "%%i" == "!MY_HOSTNAME!" (set found=true)
      if "!found!" == "true" (
         echo This hostname is known at sge_qmaster as an administrative host.
         set do_loop=false
      ) else (
         echo This hostname is not known at sge_qmaster as an administrative host.
         echo.
         echo The name of this host was resolved as ^>!MY_HOSTNAME!^<.
         echo.
         echo If you think that this host has already been added as an administrative
         echo host, the hostname resolving  on this host will most likely differ from
         echo the hostname resolving method on the qmaster machine.
         echo.
         echo Please check and correct the hostname resolving on this host and on the
         echo sge_qmaster machine.
         echo Like on UNIX, there is a ^>hosts^< file on Windows, which is located
         echo in ^>c:\Windows\System32\drivers\etc^<.
         echo.
         echo You can now add this host as an administrative host in a seperate
         echo terminal window and then continue with the installation  procedure.
         echo.
         if "!AUTO!" == "false" (
            set ANSWER=y
            set /p ANSWER="Check again (y/n) ('n' will abort) [y] >> "
         ) else (
            set ANSWER=n
         )
         if /i "!ANSWER!" == "n" (
            call :proc_error_exit 2>nul
         )
      )
   if "!do_loop!" == "true" goto :while_check_resolving

   echo.

   if "!AUTO!" == "false" (
      call :proc_wait_for_enter
   )
   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_parse_command_line
rem
rem Parses the command line arguments.
rem
rem param[in]  all command line arguments. Call this function with argument %*
rem            from main.
rem modifies   AUTO, AUTO_CONF_FILE
rem returns    nothing
rem ----------------------------------------------------------------------------
:proc_parse_command_line
   setlocal enabledelayedexpansion enableextensions
   set "l_AUTO=false"
   set "l_AUTO_CONF_FILE="
   set "l_UNINSTALL=false"
   set "l_DO_ELEVATED_TASKS=false"
   set "l_INSTALL_STARTER=false"
   set "do_parse_command_line=1"

   :while_parse_command_line
      if "%1" == "" (
         rem parsed all arguments, stop parsing
         set "do_parse_command_line=0"
      ) else if "%1" == "-x" (
         rem manually install the execution host
         if "!l_UNINSTALL!" == "true" (
            echo It's not possible to do installation and uninstallation at the same time!
            call :proc_error_exit 2>nul
         ) else (
            rem ok, do manual installation
            shift
         )
      ) else if "%1" == "-auto" (
         rem automatically install the execution host
         if "!l_UNINSTALL!" == "true" (
            echo It's not possible to do automatic installation and uninstallation at the same time!
            call :proc_error_exit 2>nul
         ) else (
            rem -auto <autoinstall_config_file>
            if not exist "%2" (
               rem exit on error
               echo auto install configuration file "%2" does not exist^^!
               call :proc_error_exit 2>nul
            ) else (
               set "l_AUTO=true"
               set "l_AUTO_CONF_FILE=%2"
               shift
               shift
            )
         )
      ) else if "%1" == "-ux" (
         rem unintall the execution host
         if "!l_AUTO!" == "true" (
            echo automatic uninstallation is not supported yet^^!
            call :proc_error_exit 2>nul
         ) else if "%1" == "-x" (
            echo It's not possible to do uninstallation and installation at the same time!
            call :proc_error_exit 2>nul
         ) else (
            set "l_UNINSTALL=true"
            shift
         )
      ) else if "%1" == "-csp" (
         rem CSP mode is not yet supported
         echo CSP mode is not yet supported on win-x86^^!
         call :proc_error_exit 2>nul
      ) else if "%1" == "-creds" (
         rem (local) Administrator domain name password
         set "l_local_Administrator_domain=%2"
         set "l_local_Administrator_name=%3"
         set "l_local_Administrator_pass=%4"
         shift
         shift
         shift
         shift
      ) else if "%1" == "-elevated-tasks" (
         rem the command line is:
         rem install_execd.bat -elevated-tasks  install <true|false>
         rem                   <install_starter <true|false>|auto auto_conf_file>
         rem                   <WIN_SGE_ROOT> <SGE_CELL> <SGE_MASTER_PORT>
         rem                   <SGE admin user domain> <SGE admin user name>
         rem                   <SGE admin user password>

         set "l_DO_ELEVATED_TASKS=true"
         if "%2" == "install" (
            if "%3" == "false" (
               set "l_UNINSTALL=true"
            )
         )
         if "%4" == "install_starter" (
            if "%5" == "true" (
               set "l_INSTALL_STARTER=true"
            )
         )
         if "%6" == "auto" (
            set "l_AUTO=true"
            set "l_AUTO_CONF_FILE=%7"
            call :proc_parse_transferred_variables_auto %*
         ) else (
            call :proc_parse_transferred_variables_no_auto %*
         )
         rem If SGE_QMASTER_PORT is not defined in the envionrment (i.e. /etc/services)
         rem is used, we got l_MY_SGE_QMASTER_PORT=0 from the command line.
         rem Undefine the variable in this case.
         if "!l_MY_SGE_QMASTER_PORT!" == "0" (
            set "l_MY_SGE_QMASTER_PORT="
         )
         rem -elevated-tasks must be the last argument
         set "do_parse_command_line=0"
      ) else if "%1" == "-help" (
         call :proc_print_help_and_exit
      ) else (
         rem unknown option - ignore
         shift
      )
   if "!do_parse_command_line!" == "1" goto :while_parse_command_line

   endlocal & (
      rem these variables are set in the callers context
      set "AUTO=%l_AUTO%"
      set "AUTO_CONF_FILE=%l_AUTO_CONF_FILE%"
      set "UNINSTALL=%l_UNINSTALL%"
      set "DO_ELEVATED_TASKS=%l_DO_ELEVATED_TASKS%"
      set "INSTALL_STARTER=%l_INSTALL_STARTER%"
      set "MY_WIN_SGE_ROOT=%l_MY_WIN_SGE_ROOT%"
      set "MY_SGE_CELL=%l_MY_SGE_CELL%"
      set "MY_SGE_QMASTER_PORT=%l_MY_SGE_QMASTER_PORT%"
      set "g_sge_admin_user=%l_sge_admin_user%"
      set "g_sge_admin_domain=%l_sge_admin_domain%"
      set "g_sge_admin_pass=%l_sge_admin_pass%"
      set "g_local_Administrator_name=%l_local_Administrator_name%"
      set "g_local_Administrator_domain=%l_local_Administrator_domain%"
      set "g_local_Administrator_pass=%l_local_Administrator_pass%"
   )
   exit /b

rem ----------------------------------------------------------------------------
rem proc_parse_transferred_variables_auto
rem
rem Parses variables that are transferred in the command line
rem
rem param[in]  the transferred variables in the command line
rem modifies   see endlocal block
rem returns    nothing
rem ----------------------------------------------------------------------------
:proc_parse_transferred_variables_auto
   setlocal enabledelayedexpansion enableextensions

   set "ll_MY_WIN_SGE_ROOT=%8"
   set "ll_MY_SGE_CELL=%9"
   shift
   set "ll_MY_SGE_QMASTER_PORT=%9"
   shift
   set "ll_sge_admin_domain=%9"
   shift
   set "ll_sge_admin_user=%9"
   shift
   set "ll_sge_admin_pass=%9"

   endlocal & (
      set "l_MY_WIN_SGE_ROOT=%ll_MY_WIN_SGE_ROOT%"
      set "l_MY_SGE_CELL=%ll_MY_SGE_CELL%"
      set "l_MY_SGE_QMASTER_PORT=%ll_MY_SGE_QMASTER_PORT%"
      set "l_sge_admin_domain=%ll_sge_admin_domain%"
      set "l_sge_admin_user=%ll_sge_admin_user%"
      set "l_sge_admin_pass=%ll_sge_admin_pass%"
   )
   exit /b

rem ----------------------------------------------------------------------------
rem proc_parse_transferred_variables_no_auto
rem
rem Parses variables that are transferred in the command line
rem
rem param[in]  the transferred variables in the command line
rem modifies   see endlocal block
rem returns    nothing
rem ----------------------------------------------------------------------------
:proc_parse_transferred_variables_no_auto
   setlocal enabledelayedexpansion enableextensions

   set "ll_MY_WIN_SGE_ROOT=%6"
   set "ll_MY_SGE_CELL=%7"
   set "ll_MY_SGE_QMASTER_PORT=%8"
   set "ll_sge_admin_domain=%9"
   shift
   set "ll_sge_admin_user=%9"
   shift
   set "ll_sge_admin_pass=%9"

   endlocal & (
      set "l_MY_WIN_SGE_ROOT=%ll_MY_WIN_SGE_ROOT%"
      set "l_MY_SGE_CELL=%ll_MY_SGE_CELL%"
      set "l_MY_SGE_QMASTER_PORT=%ll_MY_SGE_QMASTER_PORT%"
      set "l_sge_admin_domain=%ll_sge_admin_domain%"
      set "l_sge_admin_user=%ll_sge_admin_user%"
      set "l_sge_admin_pass=%ll_sge_admin_pass%"
   )
   exit /b


rem ----------------------------------------------------------------------------
rem proc_is_num
rem
rem This function doesn't work yet!!
rem
rem Determine if the string argument is a number.
rem
rem param[in] num_string  the string to test
rem modifies              nothing
rem returns               1 if it's a number, 0 if not
rem ----------------------------------------------------------------------------
:proc_is_num
   setlocal enabledelayedexpansion enableextensions
   rem this function doesn't work yet
   set "num_string=%1"
   set "is_num=0"
   for /f "delims=0123456789" %%i in ("!num_string!") do set "is_num=1"
   exit /b !is_num!

rem ----------------------------------------------------------------------------
rem proc_wait_for_enter
rem
rem Prompts the user to press enter (or 'q' to quit).
rem
rem param[in]  none
rem modifies   nothing
rem returns    nothing, exits if the user enters 'q'.
rem ----------------------------------------------------------------------------
:proc_wait_for_enter
   set "ANSWER="
   set /p ANSWER="Hit <RETURN> to continue (enter 'q' to quit) >> "
   if /i "!ANSWER!" == "q" endlocal & call :proc_error_exit 2>nul
   exit /b

rem ----------------------------------------------------------------------------
rem proc_error_exit
rem
rem Exits the script from a subprocedure.
rem
rem To prevent this function from printing an error message, call it with
rem stderr redirected to nul, e.g.:
rem    call :proc_error_exit 2>nul
rem This redirection cannot be done inside this function.
rem
rem param[in]  none
rem modifies   nothing
rem returns    doesn't return
rem ----------------------------------------------------------------------------
:proc_error_exit
   rem produce a syntax error to stop the batch program immediately
   endlocal
   set "g_user="
   set "g_domain="
   set "g_pass="
   ()
   goto :eof


rem ----------------------------------------------------------------------------
rem proc_is_dir_valid
rem
rem Checks if the given directory exists and if the current user has permissions
rem to read it.
rem
rem param[in] dir_path  path to the directory to check
rem modifies            nothing
rem returns             0 if the directory exists, 1 if it doesn't
rem ----------------------------------------------------------------------------
:proc_is_dir_valid
   setlocal enabledelayedexpansion enableextensions
   set "dir_path=%1"
   set "ret=0"
   rem set errorlevel != 0
   verify other 2>nul

   dir "%dir_path%" > nul 2>&1
   if !errorlevel! == 0 (
      set "ret=1"
   )
   exit /b !ret!

rem ----------------------------------------------------------------------------
rem proc_get_execd_spool_dir_from_conf
rem
rem Call qconf to get the execd_spool_dir config value.
rem
rem param[in] host   if it is empty, gets the config value of the global config,
rem                  if it is a hostname, gets the config value of the host config.
rem param[in] upvar  name of the variable to fill with the config value
rem modifies         nothing
rem returns          nothing
rem ----------------------------------------------------------------------------
:proc_get_execd_spool_dir_from_conf
   setlocal enabledelayedexpansion enableextensions
   set "hostname=%1"
   set "upvar=%2"

   set "l_upvar="
   for /f "tokens=1,2 delims= " %%1 in ('!QCONF! -sconf !hostname! 2^>nul') do (
      if "%%1" == "execd_spool_dir" (
         set "l_upvar=%%2"
      )
   )
   endlocal & (
      rem these variables are set in the callers context
      set "%upvar%=%l_upvar%"
   )
   exit /b

rem ----------------------------------------------------------------------------
rem proc_is_startuser_admin
rem
rem Check if the startuser of this script (i.e. the current user) is an Administrator
rem
rem modifies         nothing
rem returns          1 if the startuse is an Administrator, 0 else.
rem ----------------------------------------------------------------------------
:proc_is_startuser_admin
   rem setlocal enabledelayedexpansion enableextensions
   set "is_admin=0"

   if /i "!USERDOMAIN!" == "!COMPUTERNAME!" (
      rem local user
      for /f "tokens=*" %%a in ('net localgroup Administrators^|find /i "!USERNAME!"') do set is_admin=1
   ) else (
      rem domain user
      for /f "tokens=*" %%a in ('net group /domain "Domain Admins"^|find /i "!USERNAME!"') do set is_admin=1
   )
   exit /b !is_admin!

rem ----------------------------------------------------------------------------
rem proc_echo_path_map
rem
rem Print the current path mappings to stdout
rem
rem param[in] none
rem modifies  nothing
rem returns   nothing
rem ----------------------------------------------------------------------------
:proc_echo_path_map
   setlocal enabledelayedexpansion enableextensions
   echo SGE_ROOT ^(UNIX^):     !MY_UNIX_SGE_ROOT!
   echo SGE_ROOT ^(Windows^):  !MY_WIN_SGE_ROOT!
   echo sgeCA dir ^(UNIX^):    !MY_UNIX_SGECA_DIR!
   echo sgeCA dir ^(Windows^): !MY_WIN_SGECA_DIR!
   echo home dir ^(UNIX^):     !MY_UNIX_HOME_DIR!
   echo home dir ^(Windows^):  !MY_WIN_HOME_DIR!
   echo tmp dir ^(UNIX^):      !MY_UNIX_TMP_DIR!
   echo tmp dir ^(Windows^):   !MY_WIN_TMP_DIR!
   echo execd_spool_dir ^(UNIX^):    !MY_UNIX_EXECD_SPOOL!
   echo execd_spool_dir ^(Windows^): !MY_WIN_EXECD_SPOOL!
   echo.
   echo ^(The execd_spool_dir ^(UNIX^) is a fixed value and must not be changed^^!^)
   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_read_autoconf_file
rem
rem Read values from the auto installer configuration file
rem
rem param[in] auto_conf_file  path to the auto installer configuration file
rem modifies                  MY_UNIX_SGE_ROOT, MY_WIN_SGE_ROOT,
rem                           MY_SGE_QMASTER_PORT, MY_SGE_EXECD_PORT,
rem                           MY_SGE_CELL,
rem                           MY_UNIX_EXECD_SPOOL, MY_WIN_EXECD_SPOOL,
rem                           MY_UNIX_SGECA_DIR, MY_WIN_SGECA_DIR,
rem                           MY_UNIX_HOME_DIR, MY_WIN_HOME_DIR,
rem                           MY_UNIX_TMP_DIR, MY_WIN_TMP_DIR
rem returns                   nothing
rem ----------------------------------------------------------------------------
:proc_read_autoconf_file
   setlocal enabledelayedexpansion enableextensions
   set "AUTO_CONF_FILE=%1"

   call :proc_read_var_from_file !AUTO_CONF_FILE! SGE_ROOT l_MY_UNIX_SGE_ROOT
   call :proc_read_var_from_file !AUTO_CONF_FILE! WIN_SGE_ROOT l_MY_WIN_SGE_ROOT
   call :proc_read_var_from_file !AUTO_CONF_FILE! SGE_QMASTER_PORT l_MY_SGE_QMASTER_PORT
   call :proc_read_var_from_file !AUTO_CONF_FILE! SGE_EXECD_PORT l_MY_SGE_EXECD_PORT
   call :proc_read_var_from_file !AUTO_CONF_FILE! CELL_NAME l_MY_SGE_CELL
   call :proc_read_var_from_file !AUTO_CONF_FILE! SGE_CLUSTER_NAME l_MY_SGE_CLUSTER_NAME
   set "l_MY_UNIX_EXECD_SPOOL=/execd_spool_dir/win-x86/placeholder"
   call :proc_read_var_from_file !AUTO_CONF_FILE! WIN_EXECD_SPOOL_DIR_LOCAL l_MY_WIN_EXECD_SPOOL
   call :proc_read_var_from_file !AUTO_CONF_FILE! UNIX_SGECA_DIR l_MY_UNIX_SGECA_DIR
   call :proc_read_var_from_file !AUTO_CONF_FILE! WIN_SGECA_DIR l_MY_WIN_SGECA_DIR
   call :proc_read_var_from_file !AUTO_CONF_FILE! UNIX_HOME_DIR l_MY_UNIX_HOME_DIR
   call :proc_read_var_from_file !AUTO_CONF_FILE! WIN_HOME_DIR l_MY_WIN_HOME_DIR
   call :proc_read_var_from_file !AUTO_CONF_FILE! UNIX_TMP_DIR l_MY_UNIX_TMP_DIR
   call :proc_read_var_from_file !AUTO_CONF_FILE! WIN_TMP_DIR l_MY_WIN_TMP_DIR
   call :proc_read_var_from_file !AUTO_CONF_FILE! ADD_TO_RC l_ADD_TO_RC
   call :proc_read_var_from_file !AUTO_CONF_FILE! WIN_ADMIN_NAME l_WIN_ADMIN_NAME
   call :proc_read_var_from_file !AUTO_CONF_FILE! WIN_ADMIN_PASSWORD l_WIN_ADMIN_PASSWORD
   call :proc_read_var_from_file !AUTO_CONF_FILE! ADMIN_USER l_ADMIN_USER
   call :proc_read_var_from_file !AUTO_CONF_FILE! ADMIN_PASSWORD l_ADMIN_PASSWORD

   call :proc_split_fqun !l_WIN_ADMIN_NAME! l_domain l_user
   call :proc_split_fqun !l_ADMIN_USER! l_sge_admin_domain l_sge_admin_user

   rem map "." domain to local domain = local host name
   if "!l_domain!" == "." (
      set "l_domain=!MY_HOSTNAME!"
   )
   if "!l_sge_admin_domain!" == "." (
      set "l_sge_admin_domain=!MY_HOSTNAME!"
   )

   set "do_exit=0"
   if "!l_domain!" == "" (
      echo The WIN_ADMIN_NAME is either not specified or without domain^^!
      set do_exit=1
   )
   if "!l_user!" == "" (
      echo The WIN_ADMIN_NAME is either not specified or without domain^^!
      set do_exit=1
   )
   if "!l_sge_admin_domain!" == "" (
      echo The ADMIN_USER is either not specified or without domain^^!
      set do_exit=1
   )
   if "!l_sge_admin_user!" == "" (
      echo The ADMIN_USER is either not specified or without domain^^!
      set do_exit=1
   )
   if !do_exit! == 1 call :proc_error_exit 2>nul

   endlocal & (
      rem these variables are set in the callers context
      set "MY_UNIX_SGE_ROOT=%l_MY_UNIX_SGE_ROOT%"
      set "MY_WIN_SGE_ROOT=%l_MY_WIN_SGE_ROOT%"
      set "MY_SGE_QMASTER_PORT=%l_MY_SGE_QMASTER_PORT%"
      set "MY_SGE_EXECD_PORT=%l_MY_SGE_EXECD_PORT%"
      set "MY_SGE_CELL=%l_MY_SGE_CELL%"
      set "MY_SGE_CLUSTER_NAME=%l_MY_SGE_CLUSTER_NAME%"
      set "MY_UNIX_EXECD_SPOOL=%l_MY_UNIX_EXECD_SPOOL%"
      set "MY_WIN_EXECD_SPOOL=%l_MY_WIN_EXECD_SPOOL%"
      set "MY_UNIX_SGECA_DIR=%l_MY_UNIX_SGECA_DIR%"
      set "MY_WIN_SGECA_DIR=%l_MY_WIN_SGECA_DIR%"
      set "MY_UNIX_HOME_DIR=%l_MY_UNIX_HOME_DIR%"
      set "MY_WIN_HOME_DIR=%l_MY_WIN_HOME_DIR%"
      set "MY_UNIX_TMP_DIR=%l_MY_UNIX_TMP_DIR%"
      set "MY_WIN_TMP_DIR=%l_MY_WIN_TMP_DIR%"
      set "ADD_TO_RC=%l_ADD_TO_RC%"
      set "g_user=%l_user%"
      set "g_domain=%l_domain%"
      set "g_pass=%l_WIN_ADMIN_PASSWORD%"
      set "g_sge_admin_user=%l_sge_admin_user%"
      set "g_sge_admin_domain=%l_sge_admin_domain%"
      set "g_sge_admin_pass=%l_ADMIN_PASSWORD%"
   )
   exit /b

rem ----------------------------------------------------------------------------
rem proc read_settings_sh
rem
rem Parse variables from the $SGE_ROOT/$SGE_CELL/common/settings.sh file
rem
rem param[in] settings_path  path of setting.sh file
rem modifies                 MY_UNIX_SGE_ROOT, MY_SGE_QMASTER_PORT,
rem                          MY_SGE_EXECD_PORT, MY_SGE_CLUSTER_NAME,
rem                          SGE_QMASTER_PORT, SGE_EXECD_PORT, SGE_CLUSTER_NAME
rem returns                  nothing
rem ----------------------------------------------------------------------------
:proc_read_settings_sh
   setlocal enabledelayedexpansion enableextensions
   set "settings_path=%1"

   call :proc_read_var_from_file !settings_path! SGE_ROOT l_MY_UNIX_SGE_ROOT
   call :proc_read_var_from_file !settings_path! SGE_QMASTER_PORT l_MY_SGE_QMASTER_PORT
   call :proc_read_var_from_file !settings_path! SGE_EXECD_PORT l_MY_SGE_EXECD_PORT
   call :proc_read_var_from_file !settings_path! SGE_CLUSTER_NAME l_MY_SGE_CLUSTER_NAME

   endlocal & (
      rem these variables are set in the callers context
      set "MY_UNIX_SGE_ROOT=%l_MY_UNIX_SGE_ROOT%"
      set "MY_SGE_QMASTER_PORT=%l_MY_SGE_QMASTER_PORT%"
      set "MY_SGE_EXECD_PORT=%l_MY_SGE_EXECD_PORT%"
      set "MY_SGE_CLUSTER_NAME=%l_MY_SGE_CLUSTER_NAME%"
      set "SGE_QMASTER_PORT=%l_MY_SGE_QMASTER_PORT%"
      set "SGE_EXECD_PORT=%l_MY_SGE_EXECD_PORT%"
      set "SGE_CLUSTER_NAME=%l_MY_SGE_CLUSTER_NAME%"
   )
   exit /b

rem ----------------------------------------------------------------------------
rem proc read_bootstrap
rem
rem Parse variables from the $SGE_ROOT/$SGE_CELL/common/bootstrap file
rem
rem param[in] bootstrap_path  path of bootstrap file
rem modifies                  bootstrap_admin_user
rem returns                   nothing
rem ----------------------------------------------------------------------------
:proc_read_bootstrap
   setlocal enabledelayedexpansion enableextensions
   set "bootstrap_path=%1"

   call :proc_read_var_from_file !bootstrap_path! admin_user l_bootstrap_admin_user

   endlocal & (
      rem these variables are set in the callers context
      set "bootstrap_admin_user=%l_bootstrap_admin_user%"
   )
   exit /b

rem ----------------------------------------------------------------------------
rem proc_read_path_map_file
rem
rem Read variables from the $SGE_ROOT/$SGE_CELL/common/path_map file
rem
rem param[in] settings_path  path of setting.sh file
rem modifies                 MY_UNIX_SGE_ROOT, MY_SGE_QMASTER_PORT,
rem                          MY_SGE_EXECD_PORT, MY_SGE_CLUSTER_NAME,
rem                          SGE_QMASTER_PORT, SGE_EXECD_PORT, SGE_CLUSTER_NAME
rem returns                  nothing
rem ----------------------------------------------------------------------------
:proc_read_path_map_file
   setlocal enabledelayedexpansion enableextensions
   set "path_map_path=%1"

   set line=1
   for /f "tokens=* delims=" %%a in (!path_map_path!) do (
      for /f "tokens=1,2 delims=," %%1 in ("%%a") do (
         if !line! == 1 (
            set "l_MY_UNIX_SGE_ROOT=%%1"
            set /a line=!line!+1
         ) else if !line! == 2 (
            set "l_MY_UNIX_EXECD_SPOOL=%%1"
            set "l_MY_WIN_EXECD_SPOOL=%%2"
            set /a line=!line!+1
         ) else if !line! == 3 (
            set "l_MY_UNIX_SGECA_DIR=%%1"
            set "l_MY_WIN_SGECA_DIR=%%2"
            set /a line=!line!+1
         ) else if !line! == 4 (
            set "l_MY_UNIX_HOME_DIR=%%1"
            set "l_MY_WIN_HOME_DIR=%%2"
            set /a line=!line!+1
         ) else (
            set "l_MY_UNIX_TMP_DIR=%%1"
            set "l_MY_WIN_TMP_DIR=%%2"
            set /a line=!line!+1
         )
      )
   )
   endlocal & (
      rem these variables are set in the callers context
      set "MY_UNIX_SGE_ROOT=%l_MY_UNIX_SGE_ROOT%"
      set "MY_UNIX_EXECD_SPOOL=%l_MY_UNIX_EXECD_SPOOL%"
      set "MY_WIN_EXECD_SPOOL=%l_MY_WIN_EXECD_SPOOL%"
      set "MY_UNIX_SGECA_DIR=%l_MY_UNIX_SGECA_DIR%"
      set "MY_WIN_SGECA_DIR=%l_MY_WIN_SGECA_DIR%"
      set "MY_UNIX_HOME_DIR=%l_MY_UNIX_HOME_DIR%"
      set "MY_WIN_HOME_DIR=%l_MY_WIN_HOME_DIR%"
      set "MY_UNIX_TMP_DIR=%l_MY_UNIX_TMP_DIR%"
      set "MY_WIN_TMP_DIR=%l_MY_WIN_TMP_DIR%"
   )
   exit /b

rem ----------------------------------------------------------------------------
rem proc_read_var_from_file
rem
rem Read a specific value from a INI style file like settings.sh or autoconf
rem file, i.e. a file where there is one "variable=value" pair in one line, e.g.:
rem SGE_ROOT=/home/sgeadmin/UGE
rem
rem param[in] file            path to the file to read
rem param[in] var_name        name of the variable in the file
rem param[in] upvar           name of the variable that is to hold the value
rem                           from the file
rem modifies                  nothing
rem returns                   0 if the value was read from the file, 1 if not
rem ----------------------------------------------------------------------------
:proc_read_var_from_file
   rem setlocal enabledelayedexpansion enableextensions
   set "ret=1"       rem return value of this function
   set "file=%1"     rem file to read the var from
   set "var_name=%2" rem read this var from the file
   set "upvar=%3"    rem reference of the var to keep the result

   set "l_upvar="

   for /f "tokens=* delims=" %%a in ('findstr /r /c:"^^[ \t]*!var_name!" !file!') do (
      for /f "tokens=1,2 delims=;= " %%1 in ("%%a") do (
         call :proc_unquote %%2 l_upvar
         set "ret=0"
      )
   )
   rem endlocal & (
      rem rem these variables are set in the callers context
      rem set "%upvar%=%l_upvar%"
   rem )
   set "!upvar!=%l_upvar%"
   exit /b !ret!

rem ----------------------------------------------------------------------------
rem proc_unquote
rem
rem Remove surrounding quotes from a string
rem
rem param[in] %1  string to unquote
rem param[in] %2  name of the variable that is to receive the unquoted string
rem modifies      nothing
rem returns       nothing
rem ----------------------------------------------------------------------------
:proc_unquote
   setlocal enabledelayedexpansion enableextensions
   set "l_upvar=%~1"
   endlocal & (
      rem these variables are set in the callers context
      set "%2=%l_upvar%"
   )
   exit /b

rem ----------------------------------------------------------------------------
rem proc_get_cwd
rem
rem Get current working directory
rem
rem param[in] upvar  name of the variable that is to receive the cwd
rem modifies         nothing
rem returns          nothing
rem ----------------------------------------------------------------------------
:proc_get_cwd
   setlocal enabledelayedexpansion enableextensions
   set "upvar=%1"
   set "l_upvar=%cd%"
   endlocal & (
      rem these variables are set in the callers context
      set "%upvar%=%l_upvar%"
   )
   exit /b

rem ----------------------------------------------------------------------------
rem proc_get_installer_basename
rem
rem Get the file name + extension from the full path to this installer script
rem
rem param[in] %1  the full path to this installer script
rem param[in] %2  name of the variable that is to receive the basename
rem modifies      nothing
rem returns       nothing
rem ----------------------------------------------------------------------------
:proc_get_installer_basename
   setlocal enabledelayedexpansion enableextensions
   set "upvar=%2"
   set "l_upvar=%~dp1"
   endlocal & (
      rem these variables are set in the callers context
      set "%upvar%=%l_upvar%"
   )
   exit /b

rem ----------------------------------------------------------------------------
rem proc_write_settings_bat
rem
rem Write the $SGE_ROOT/$SGE_CELL/common/settings.bat file with the currently
rem set values.
rem
rem param[in] settings_bat_path  path to the settings.bat file
rem modifies                     nothing
rem returns                      nothing
rem ----------------------------------------------------------------------------
:proc_write_settings_bat
   setlocal enabledelayedexpansion enableextensions
   set "settings_bat_path=%1"

   call :proc_append_copyright_header !settings_bat_path!

   set "path_str=%%PATH%%;%%SGE_ROOT%%\bin\win-x86;%%SGE_ROOT%%\utilbin\win-x86"
   set "path_str=!path_str!;%%SGE_ROOT%%\lib\win-x86"

   echo @echo off                                    >  !settings_bat_path!
   echo.                                             >> !settings_bat_path!
   echo set "SGE_ROOT=!MY_WIN_SGE_ROOT!"             >> !settings_bat_path!
   echo set "SGE_CELL=!MY_SGE_CELL!"                 >> !settings_bat_path!
   echo set "SGE_CLUSTER_NAME=!MY_SGE_CLUSTER_NAME!" >> !settings_bat_path!
   if not "!MY_SGE_QMASTER_PORT!" == "" (
      echo set "SGE_QMASTER_PORT=!MY_SGE_QMASTER_PORT!" >> !settings_bat_path!
      echo set "SGE_EXECD_PORT=!MY_SGE_EXECD_PORT!"     >> !settings_bat_path!
   )
   echo.                                             >> !settings_bat_path!
   echo set "PATH=!PATH_STR!"                        >> !settings_bat_path!
   echo.                                             >> !settings_bat_path!
   echo echo Univa Grid Engine environment variables successfully set! >> !settings_bat_path!
   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_write_sgeexecd_bat
rem
rem Write the $SGE_ROOT/$SGE_CELL/common/sgeexecd.bat file with the currently
rem set values.
rem
rem param[in] sgeexecd_bat_path  path to the sgeexecd.bat file
rem modifies                     nothing
rem returns                      nothing
rem ----------------------------------------------------------------------------
:proc_write_sgeexecd_bat
   setlocal enabledelayedexpansion enableextensions
   set "sgeexecd_bat_path=%1"

   set "settings_bat_path=!MY_WIN_SGE_ROOT!\!MY_SGE_CELL!\common\settings.bat"

   echo @echo off                                                 > !sgeexecd_bat_path!
   call :proc_append_copyright_header !sgeexecd_bat_path!

   echo.                                                          >> !sgeexecd_bat_path!
   echo call !settings_bat_path! ^>nul 2^>^&1                     >> !sgeexecd_bat_path!
   echo start /b %%SGE_ROOT%%\bin\win-x86\sge_execd.exe           >> !sgeexecd_bat_path!
   echo echo The Univa Grid Engine execution daemon was started.  >> !sgeexecd_bat_path!
   echo exit /b 0                                                 >> !sgeexecd_bat_path!
   endlocal
   exit /b


rem ----------------------------------------------------------------------------
rem proc_append_copyright_header
rem
rem Write the copyright header to the given .bat file
rem
rem param[in] dest_file  path to the .bat file
rem modifies             nothing
rem returns              nothing
rem ----------------------------------------------------------------------------
:proc_append_copyright_header
   setlocal enabledelayedexpansion enableextensions
   set "dest_file=%1"

   echo rem #___INFO__MARK_BEGIN__                                                      >> !dest_file!
   echo rem ########################################################################### >> !dest_file!
   echo rem #                                                                           >> !dest_file!
   echo rem #  The contents of this file are made available subject to the terms of the >> !dest_file!
   echo rem #  Apache Software License 2.0 ^('The License'^).                           >> !dest_file!
   echo rem #  You may not use this file except in compliance with The License.         >> !dest_file!
   echo rem #  You may obtain a copy of The License at                                  >> !dest_file!
   echo rem #  http://www.apache.org/licenses/LICENSE-2.0.html                          >> !dest_file!
   echo rem #                                                                           >> !dest_file!
   echo rem #  Copyright ^(c^) 2014 Univa Corporation.                                  >> !dest_file!
   echo rem #                                                                           >> !dest_file!
   echo rem ########################################################################### >> !dest_file!
   echo rem #___INFO__MARK_END__                                                        >> !dest_file!
   echo.                                                                                >> !dest_file!
   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_write_path_map_file
rem
rem Write the $SGE_ROOT/$SGE_CELL/common/path_map file with the currently
rem set values.
rem
rem param[in] path_map_file  path to the path_map file
rem modifies                 nothing
rem returns                  nothing
rem ----------------------------------------------------------------------------
:proc_write_path_map_file
   setlocal enabledelayedexpansion enableextensions
   set "path_map_file=%1"

   echo !MY_UNIX_SGE_ROOT!, !MY_WIN_SGE_ROOT!       >  !path_map_file!
   echo !MY_UNIX_EXECD_SPOOL!, !MY_WIN_EXECD_SPOOL! >> !path_map_file!
   echo !MY_UNIX_SGECA_DIR!, !MY_WIN_SGECA_DIR!     >> !path_map_file!
   echo !MY_UNIX_HOME_DIR!, !MY_WIN_HOME_DIR!       >> !path_map_file!
   echo !MY_UNIX_TMP_DIR!, !MY_WIN_TMP_DIR!         >> !path_map_file!
   endlocal
   exit /b


rem ----------------------------------------------------------------------------
rem proc_create_local_config
rem
rem Creates the local config for the current host in the QMaster.
rem
rem param[in]  nothing
rem modifies   nothing
rem returns    nothing
rem ----------------------------------------------------------------------------
:proc_create_local_config
   setlocal enabledelayedexpansion enableextensions
   rem check if this host is configured as admin host

   rem delete the temp file if it already exists, its and leftover
   rem from previous installation tries
   if exist %TEMP%\!MY_HOSTNAME! (
      del /f %TEMP%\!MY_HOSTNAME!
   )

   rem create the configuration file
   set "host_conf_file=%TEMP%\!MY_HOSTNAME!"
   echo execd_spool_dir !MY_UNIX_EXECD_SPOOL! > !host_conf_file!

   rem add the content of the temp file as new configuration to UGE
   if "!AUTO!" == "true" (
      !QCONF! -Aconf !host_conf_file! >> c:\tmp\install_execd.bat.log 2>&1
   ) else (
      !QCONF! -Aconf !host_conf_file!
   )

   endlocal
   exit /b errorlevel


rem ----------------------------------------------------------------------------
rem proc_install_job_starter_service
rem
rem Copies the uge_js_service.exe to the %WINDIR% (usually C:\Windows) and
rem installs it as a service
rem
rem This function usually is run as elevated Administrator!
rem
rem param[in]  nothing
rem modifies   nothing
rem returns    nothing
rem ----------------------------------------------------------------------------
:proc_install_job_starter_service
   setlocal enabledelayedexpansion enableextensions

   rem set %errorlevel% to 0
   ver>nul 2>&1

   rem stop the service if it is running
   net stop "Univa Grid Engine Job Starter Service" >nul 2>&1
   if not !errorlevel! == 0 (
      rem errorlevel 2 = service was already stopped
      if not !errorlevel! == 2 (
         echo Stopping the old Job Starter Service failed with exit code !errorlevel!^^!
      ) else (
         echo The old Job Starter Service already was stopped.
      )
   ) else (
      echo The old Job Starter Service was stopped.
      rem give it some time to really stop
      call :proc_sleep 2
   )

   rem copy the new service binaries to "C:\Windows"
   call :proc_copy_file_to_windir c:\tmp\SGE_Starter.exe
   if not !errorlevel! == 0 call :proc_error_exit 2>nul
   call :proc_copy_file_to_windir c:\tmp\uge_js_service.exe
   if not !errorlevel! == 0 call :proc_error_exit 2>nul

   rem copy the pthreadVC2.dll to "C:\Windows"
   call :proc_copy_file_to_windir c:\tmp\pthreadVC2.dll
   if not !errorlevel! == 0 call :proc_error_exit 2>nul

   rem install the service and start it
   set "installation_OK=false"
   %WINDIR%\uge_js_service.exe -install >nul 2>&1
   if !errorlevel! == 0 set installation_OK=true
   if !errorlevel! == 5 set installation_OK=true
   if "!installation_OK!" == "false" (
      echo.
      echo Installing the Job Starter Service failed with exit code !errorlevel!^^!
      echo.
   ) else (
      echo.
      echo Successfully installed the Job Starter Service, now starting it...

      net start "Univa Grid Engine Job Starter Service" >nul 2>&1
      if not !errorlevel! == 0 (
         echo Starting the Job Starter Service failed with exit code !errorlevel!^^!
      ) else (
         echo The new Job Starter Service is started.
      )
   )
   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_set_perflib_permissions
rem
rem Add the installing user to the ACL list of the perflib registry key
rem
rem This function usually is run as elevated Administrator!
rem
rem param[in]  nothing
rem modifies   nothing
rem returns    nothing
rem ----------------------------------------------------------------------------
:proc_set_perflib_permissions
   setlocal enabledelayedexpansion enableextensions

   rem set %errorlevel% to 0
   ver>nul 2>&1

   echo Setting perflib registry key permissions for user !g_sge_admin_domain!\!g_sge_admin_user!
   %WINDIR%\uge_js_service.exe -set-perflib-perms !g_sge_admin_domain!\!g_sge_admin_user!

   if not !errorlevel! == 0 (
      echo Couldn't add the UGE admin user to the "perflib" registry key access list^^!
      echo Probably, the execution daemon will not be able to report load values.
   )

   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_install_starter_service
rem
rem Copies the UGE_Starter_Service.exe to the %WINDIR% (usually C:\Windows) and
rem installs it as a service
rem
rem param[in]  nothing
rem modifies   nothing
rem returns    nothing
rem ----------------------------------------------------------------------------
:proc_install_starter_service
   setlocal enabledelayedexpansion enableextensions

   rem set %errorlevel% to 0
   ver>nul 2>&1

   rem stop the service if it is running
   net stop "Univa Grid Engine Starter Service" >nul 2>&1
   if not !errorlevel! == 0 (
      rem errorlevel 2 = service was already stopped
      if not !errorlevel! == 2 (
         echo Stopping the old Starter Service failed with exit code !errorlevel!^^!
      ) else (
         echo The old Starter Service already was stopped.
      )
   ) else (
      echo The old Starter Service was stopped.
      rem give it some time to really stop
      call :proc_sleep 2
   )

   rem copy the new service binary to "C:\Windows"
   call :proc_copy_file_to_windir c:\tmp\UGE_Starter_Service.exe
   if not !errorlevel! == 0 call :proc_error_exit 2>nul

   if not "!AUTO!" == "true" (
      if "g_sge_admin_user" == "" (
         set "g_sge_admin_user=%USERNAME%"
         set "g_sge_admin_domain=%USERDOMAIN%"
      )
      rem we need to install the SGE_Starter_Service as the SGE admin user
      echo.
      echo In order to install the Starter Service as the UGE admin user
      echo ^>!g_sge_admin_domain!\!g_sge_admin_user!^<
      echo the password is needed:
      echo.
      call :proc_ask_for_sge_admin_user_password
   )

   rem install the service and start it
   set installation_OK=false

   %WINDIR%\UGE_Starter_Service.exe -install !g_sge_admin_domain!\!g_sge_admin_user! !g_sge_admin_pass!
   if !errorlevel! == 0 set installation_OK=true
   if !errorlevel! == 5 set installation_OK=true
   if "!installation_OK!" == "false" (
      echo.
      echo Installing the Starter Service failed with exit code !errorlevel!^^!
      echo.
   ) else (
      rem the service is now installed or it already was installed
      echo.
      echo Successfully installed the Starter Service, now going to add
      echo this installation to it's registry key.
      echo.

      rem store the $SGE_CELL path and port in the registry to find the execd at boot time
      if "!MY_SGE_QMASTER_PORT!" == "" (
         set "sge_qmaster_port_param=0"
      ) else (
         set "sge_qmaster_port_param=!MY_SGE_QMASTER_PORT!"
      )
      %WINDIR%\UGE_Starter_Service.exe -add !sge_qmaster_port_param! !MY_WIN_SGE_ROOT!\!MY_SGE_CELL!
      if not !errorlevel! == 0 (
         echo.
         echo Installing the Starter Service failed with exit code !errorlevel!,
         echo the execution daemon will most likely not be started at system boot time^^!
         echo.
      ) else (
         rem now start the service in order to start the execution daemon
         echo Starting the newly installed Starter Service now.
         net start "Univa Grid Engine Starter Service" >nul 2>&1
         if not !errorlevel! == 0 (
            echo.
            echo Starting the UGE Starter Service failed with exit code !errorlevel!.
            echo Please try to start the Starter Service manually after installation
            echo and check if this succeeds.
            echo.
         ) else (
            echo.
            echo Successfully started the UGE Starter Service, the execution daemon
            echo ^(sge_execd.exe^) should now be started in 60 s and should report
            echo first load at latest two times the configured load_report_interval
            echo later.
            echo.
         )
      )
   )

   set "g_sge_admin_pass="
   set "g_sge_admin_user="
   set "g_sge_admin_domain="

   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_add_to_all_q
rem
rem Adds the current host to the "all.q" queue in the QMaster. To do this, it
rem simply adds the host to the @allhosts hostlist, which is configured in the
rem "hostlist" config value of the all.q.
rem
rem param[in]  nothing
rem modifies   nothing
rem returns    nothing
rem ----------------------------------------------------------------------------
:proc_add_to_all_q
   setlocal enabledelayedexpansion enableextensions

   if "!AUTO!" == "true" (
      !QCONF! -aattr hostgroup hostlist !MY_HOSTNAME! @allhosts  >> c:\tmp\install_execd.bat.log 2>&1
   ) else (
      !QCONF! -aattr hostgroup hostlist !MY_HOSTNAME! @allhosts
   )

   endlocal
   exit /b


rem ----------------------------------------------------------------------------
rem proc_start_execd
rem
rem Starts the execution daemon
rem ----------------------------------------------------------------------------
:proc_start_execd
   setlocal enabledelayedexpansion enableextensions
   ver > nul
   start /b !MY_WIN_SGE_ROOT!\bin\win-x86\sge_execd.exe
   if not !errorlevel! == 0 (
      if "!AUTO!" == "true" (
         echo Starting execution daemon failed! Errorlevel is !errorlevel!  >> c:\tmp\install_execd.bat.log 2>&1
      ) else (
         echo Starting execution daemon failed! Errorlevel is !errorlevel!
      )
   )
   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_get_hostname
rem
rem Gets the name of the current host.
rem
rem param[in]  upvar  The name of the variable that is to receive the hostname.
rem modifies   nothing
rem returns    nothing
rem ----------------------------------------------------------------------------
:proc_get_hostname
   setlocal enabledelayedexpansion enableextensions
   set "upvar=%1"
   set "l_upvar="
   rem get hostname
   for /f "delims=. " %%i in ('hostname') do set "l_upvar=%%i"

   rem make it lowercase
   call :proc_lowercase l_upvar
   endlocal & (
      rem these variables are set in the callers context
      set "%upvar%=%l_upvar%"
   )
   exit /b


rem ----------------------------------------------------------------------------
rem proc_lowercase
rem
rem Turns a string lowercase
rem
rem param[in]  %1  The name of the string to convert
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_lowercase
   for %%i in ("A=a" "B=b" "C=c" "D=d" "E=e" "F=f" "G=g" "H=h" "I=i" "J=j" "K=k" "L=l" "M=m" ^
               "N=n" "O=o" "P=p" "Q=q" "R=r" "S=s" "T=t" "U=u" "V=v" "W=w" "X=x" "Y=y" "Z=z") do (
      call set "%1=%%%1:%%~i%%"
   )
   exit /b

rem ----------------------------------------------------------------------------
rem proc_print_help_and_exit
rem
rem Prints the help text and exits
rem
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_print_help_and_exit
   setlocal enabledelayedexpansion enableextensions
   echo Usage: install_execd.bat ^[-auto ^<filename^>^|-help^]
   echo    -auto     full automatic installation of a single execution host
   echo    -x        install execution host
   echo    -ux       uninstall execution host
   echo    -help     show this help text
   echo.
   call :proc_wait_for_enter
   call :proc_error_exit 2>nul
   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_sleep
rem
rem Sleep for n seconds
rem
rem param[in]  %1  Sleep time in seconds
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_sleep
   setlocal enabledelayedexpansion enableextensions
   set "sleeptime=%1"

   rem ping a not reachable address
   ping 192.0.2.2 -n 1 -w %1000 > nul
   endlocal
   exit /b

rem ----------------------------------------------------------------------------
rem proc_copy_my_files_to_tmp
rem
rem Copy this installer script, the pthreadVC2.dll, getpass.exe and the
rem services to c:\tmp, in order to make it accessible to the elevated
rem local Administrator.
rem
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_copy_my_files_to_tmp
   rem copy the binaries from the $SGE_ROOT dir to c:\tmp, so the local
   rem Administrator can later copy them from c:\tmp to c:\Windows.
   ver >nul
   call :proc_copy_file_to_tmp !MY_WIN_SGE_ROOT!\install_execd.bat
   if not !errorlevel! == 0 call :proc_error_exit 2>nul
   call :proc_copy_file_to_tmp !MY_WIN_SGE_ROOT!\lib\win-x86\pthreadVC2.dll
   if not !errorlevel! == 0 call :proc_error_exit 2>nul
   call :proc_copy_file_to_tmp !MY_WIN_SGE_ROOT!\utilbin\win-x86\uge_js_service.exe
   if not !errorlevel! == 0 call :proc_error_exit 2>nul
   call :proc_copy_file_to_tmp !MY_WIN_SGE_ROOT!\utilbin\win-x86\SGE_Starter.exe
   if not !errorlevel! == 0 call :proc_error_exit 2>nul
   call :proc_copy_file_to_tmp !MY_WIN_SGE_ROOT!\utilbin\win-x86\UGE_Starter_Service.exe
   if not !errorlevel! == 0 call :proc_error_exit 2>nul
   call :proc_copy_file_to_tmp !MY_WIN_SGE_ROOT!\utilbin\win-x86\getpass.exe
   if not !errorlevel! == 0 call :proc_error_exit 2>nul
   exit /b

rem ----------------------------------------------------------------------------
rem proc_delete_my_files_to_tmp
rem
rem Delete this installer script, the pthreadVC2.dll, getpass.exe and the
rem services from c:\tmp.
rem
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_delete_my_files_from_tmp
   del c:\tmp\install_execd.bat >nul 2>&1
   del c:\tmp\pthreadVC2.dll >nul 2>&1
   del c:\tmp\uge_js_service.exe >nul 2>&1
   del c:\tmp\SGE_Starter.exe >nul 2>&1
   del c:\tmp\UGE_Starter_Service.exe >nul 2>&1
   del c:\tmp\getpass.exe >nul 2>&1
   exit /b

rem ----------------------------------------------------------------------------
rem proc_copy_file_to_tmp
rem
rem Copy the given file to c:\tmp
rem
rem @param[in]     %1 full path to the file to copy
rem modifies       nothing
rem returns        0 on success,
rem                1 if the pthreadVC2.dll wasn't found,
rem                2 if copying failed
rem ----------------------------------------------------------------------------
:proc_copy_file_to_tmp
   call :proc_copy_file_to_dir %1 c:\tmp
   set "ret=!errorlevel!"
   exit /b !ret!

rem ----------------------------------------------------------------------------
rem proc_copy_file_to_tmp
rem
rem Copy the given file to the %WINDIR% (usually C:\Windows)
rem
rem @param[in]     %1 full path to the file to copy
rem modifies       nothing
rem returns        0 on success,
rem                1 if the pthreadVC2.dll wasn't found,
rem                2 if copying failed
rem ----------------------------------------------------------------------------
:proc_copy_file_to_windir
   call :proc_copy_file_to_dir %1 %WINDIR%
   set "ret=!errorlevel!"
   exit /b !ret!

rem ----------------------------------------------------------------------------
rem proc_copy_file_to_dir
rem
rem Copy the given file
rem
rem @param[in]     %1 full path to the file to copy
rem @param[in]     %2 the destination directory of the file
rem modifies       nothing
rem returns        0 on success,
rem                1 if the pthreadVC2.dll wasn't found,
rem                2 if copying failed
rem ----------------------------------------------------------------------------
:proc_copy_file_to_dir
   set "ret=0"

   rem try to overwrite files, but don't report an error if it fails.
   if exist "%2\%~nx1" (
      set "existed_before=true"
   )

   if not exist "%1" (
      rem source file doesn't exist
      echo Source file %1 doesn't exist or can't be read^^!
      set "ret=2"
   ) else (
      if not exist "%2" (
         rem destination dir doesn't exist
         echo Destination directory %2 doesn't exist or can't be written to^^!
         set "ret=3"
      ) else (
         rem copy the file
         rem set errorlevel to 0
         ver >nul
         rem the first copy "mounts" the network share, so the second copy
         rem succeeds even if the share was not used recently before
         copy "%1" nul >nul
         ver >nul
         copy "%1" "%2" /y
         if not !errorlevel! == 0 (
            if not "!existed_before!" == "true" (
               rem copying failed
               echo Failed copying %1 to %2^^!
               echo Exit code was !errorlevel!
               set "ret=1"
            )
         )
      )
   )
   exit /b !ret!

rem ----------------------------------------------------------------------------
rem proc_ask_for_user
rem
rem Ask the user for the user name.
rem
rem @param[out] %1  the user name
rem modifies        nothing
rem returns         nothing
rem ----------------------------------------------------------------------------
:proc_ask_for_user
   setlocal enabledelayedexpansion enableextensions
   set "var_user=%1"

   :while_ask_user
      set "ANSWER="
      set /p ANSWER="Please enter the user name (without domain): "
      if /i "!ANSWER!" == "" (
         echo Please enter a valid user name^^!
      ) else (
         set "l_user=!ANSWER!"
      )
      if "!l_user!" == "" goto :while_ask_user

   endlocal & (
      set "%var_user%=%l_user%"
   )
   exit /b

rem ----------------------------------------------------------------------------
rem proc_ask_for_domain
rem
rem Ask the user for the domain.
rem
rem @param[out] %1  the domain
rem modifies        nothing
rem returns         nothing
rem ----------------------------------------------------------------------------
:proc_ask_for_domain
   setlocal enabledelayedexpansion enableextensions
   set "var_domain=%1"

   :while_ask_domain
      set "ANSWER="
      set /p ANSWER="Please enter the domain of this user ('.' for local users): "
      if /i "!ANSWER!" == "" (
         echo Please enter a valid domain name^^!
      ) else (
         set "l_domain=!ANSWER!"
      )
      if "!l_domain!" == "" goto :while_ask_domain

   rem map "." domain to local domain = local host name
   if "!l_domain!" == "." (
      set "l_domain=!MY_HOSTNAME!"
   )

   endlocal & (
      set "%var_domain%=%l_domain%"
   )
   exit /b

rem ----------------------------------------------------------------------------
rem proc_ask_for_password
rem
rem Ask the user for the password.
rem
rem @param[out] %1  the password
rem modifies        nothing
rem returns         nothing
rem ----------------------------------------------------------------------------
:proc_ask_for_password
   setlocal enabledelayedexpansion enableextensions
   set "var_pass=%1"

   :while_ask_pass
      set "GETPASS=c:\tmp\getpass.exe"
      set "ANSWER="
      <nul: set /p ANSWER="Please enter the password of this user: "
      for /f "delims=" %%i in ('!GETPASS!') do set ANSWER=%%i
      if /i "!ANSWER!" == "" (
         echo Please enter a valid password^^!
      ) else (
         set "l_pass=!ANSWER!"
      )
      if "!l_pass!" == "" goto :while_ask_pass

      echo.
      set "ANSWER="
      <nul: set /p ANSWER="Please enter the password of this user again: "
      for /f "delims=" %%i in ('!GETPASS!') do set ANSWER=%%i
      if /i not "!ANSWER!" == "!l_pass!" (
         echo.
         echo The passwords do not match ^^!
         echo.
         set "l_pass="
      )
      if "!l_pass!" == "" goto :while_ask_pass
      echo.

   set "ANSWER="
   endlocal & (
      set "%var_pass%=%l_pass%"
   )
   exit /b

rem ----------------------------------------------------------------------------
rem proc_ask_for_credentials
rem
rem Ask the user for credentials, i.e. username and password, of a specific user.
rem
rem modifies       g_user, g_domain, g_pass
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_ask_for_credentials
   setlocal enabledelayedexpansion enableextensions

   set "l_domain="
   set "l_user="
   set "l_pass="

   call :proc_ask_for_user l_user
   call :proc_ask_for_domain l_domain
   call :proc_ask_for_password l_pass

   endlocal & (
      rem these variables are set in the callers context
      set "g_user=%l_user%"
      set "g_domain=%l_domain%"
      set "g_pass=%l_pass%"
   )
   exit /b


rem ----------------------------------------------------------------------------
rem proc_ask_for_sge_admin_user_password
rem
rem Ask the user for the password.
rem
rem modifies       g_sge_admin_pass
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_ask_for_sge_admin_user_password
   setlocal enabledelayedexpansion enableextensions

   set "l_pass="
   call :proc_ask_for_password l_pass

   endlocal & (
      rem these variables are set in the callers context
      set "g_sge_admin_pass=%l_pass%"
   )
   exit /b

rem ----------------------------------------------------------------------------
rem proc_split_fqun
rem
rem Split a full qualified user name into domain and user.
rem
rem param[in]  %1  the full qualified user name
rem param[out] %2  reference to the domain variable
rem param[out] %3  reference to the user name variable
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_split_fqun
   setlocal enabledelayedexpansion enableextensions

   set "fqun=%1"
   set "var_domain=%2"
   set "var_user=%3"

   for /f "tokens=1,2 delims=\" %%1 in ("!fqun!") do (
      set "domain=%%1"
      set "user=%%2"
   )

   endlocal & (
      set "%var_domain%=%domain%"
      set "%var_user%=%user%"
   )
   exit /b

rem ----------------------------------------------------------------------------
rem proc_query_local_Administrator_credentials
rem
rem Ask the user for the credentials of a local Administrator user
rem
rem modifies       nothing
rem returns        nothing
rem ----------------------------------------------------------------------------
:proc_query_local_Administrator_credentials
   rem ----------------------------------------------------------------------------
   rem - Local Administrator credentials
   rem ----------------------------------------------------------------------------
   set "g_user="
   set "g_domain="
   set "g_pass="

   cls
   echo.
   echo Local Administrator credentials
   echo -------------------------------
   echo.
   echo In order to do the below tasks, this installer needs to execute certain
   echo operations as a user that has the permissions to write to the
   echo %%WINDIR%% directory and to change the access list of a registry key.
   echo This user usually is the local Administrator or a member of the local
   echo Administrators group, but may - depending on your setup - also be
   echo a different user.
   echo.
   echo These tasks have to be done as such a user:
   echo * copy the following files to %%WINDIR%%
   echo   ^(%WINDIR%^):
   echo   - UGE_Starter_Service.exe  - starts the execution daemon at boot time
   echo   - UGE_JS_Service.exe       - does the real execution of jobs
   echo   - UGE_Starter.exe          - needed to start jobs on Vista and later
   echo   - pthreadVC2.dll           - needed by many Univa Grid Engine executables
   echo.
   echo * add the current user to the list of users that have access to
   echo   the "perflib" registry that provides load values
   echo.

   call :proc_ask_for_credentials

   echo.
   echo Using user !g_domain!\!g_user! to perform these tasks.
   echo.
   call :proc_wait_for_enter
   exit /b

rem ----------------------------------------------------------------------------
rem proc_check_elevation
rem
rem Check if the current process has elevated local Administrator privileges.
rem
rem modifies       nothing
rem returns        0 if the current process is elevated, 1 if not
rem ----------------------------------------------------------------------------
:proc_check_elevation
   set "ret=0"
   net session >nul 2>&1
   if not !errorlevel! == 0 set "ret=1"
   exit /b !ret!


rem ----------------------------------------------------------------------------
rem proc_start_elevation
rem
rem Start this script again in elevated mode.
rem The installer starts itself to do the tasks that have to be done in
rem elevated mode. It uses the adminrun.exe binary to request the elevated mode
rem - if User Account Control is disabled, the system will do nothing, so
rem this function then asks for the credentials of a local Administrator user.
rem
rem param[in]  %*  the argument list needed to start this script in elevated
rem                mode - see the command line parsing function for details.
rem modifies       nothing
rem returns        0 if the elevated tasks were completed successfully, 1 if not
rem ----------------------------------------------------------------------------
:proc_start_elevated
   set "adminrun_args=%*"
   set "admin_credentials="

   if not "!g_local_Administrator_name!" == "" (
      set "admin_credentials=-u !g_local_Administrator_name! -d !g_local_Administrator_domain! -p !g_local_Administrator_pass!"
   )

   :while_not_elevated
      set "do_loop=0"

      rem set errorlevel to 0
      ver >nul

      !ADMINRUN! !admin_credentials! !adminrun_args!
      set "ret=!errorlevel!"

      if "!AUTO!" == "true" (
         if not !ret! == 0 (
            echo !ADMINRUN! failed wit errorlevel !ret! >> c:\tmp\install_execd.bat.log 2>&1
         ) else (
            echo !ADMINRUN! succeeded >> c:\tmp\install_execd.bat.log 2>&1
         )
      )

      if !ret! == 1 (
         set "do_loop=true"

         echo The installer is not runningin elevated mode, is the
         set "ANSWER=y"
         set /p ANSWER="Windows User Accout Control (UAC) disabled? (y|n) [y] >> "
         if "!ANSWER!" == "y" (
            echo.
            echo Then please enter the username and the password of a local Administrator:
            call :proc_ask_for_credentials
            echo.
            echo Using user !g_domain!\!g_user! to perform these tasks.
            echo.

            set "admin_credentials=-u !g_user! -d !g_domain! -p !g_pass!"
         )
      )
      if "!AUTO!" == "false" (
         call :proc_wait_for_enter
      )
      if "!do_loop!" == "true" goto :while_not_elevated

   set "admin_credentials="
   exit /b !ret!

rem ----------------------------------------------------------------------------
rem proc_get_service_by_name
rem
rem Read the port of a specific service from %WINDIR%\sytem32\drivers\etc\services
rem
rem param[in]  %1  Name of the service
rem param[out] %2  Name of the variable where the port shall be written to
rem                -1 in case of an invalid service name (arg1)
rem                 0 if the service can not be found in the services file
rem modifies   nothing
rem returns    nothing
rem ----------------------------------------------------------------------------
:proc_get_service_by_name
   setlocal enabledelayedexpansion enableextensions

   set "service_name=%1"
   set "upvar=%2"
   set "param_ok=0"
   set "ret=-1"

   if "!service_name!" == "sge_execd" set "param_ok=1"
   if "!service_name!" == "sge_qmaster" set "param_ok=1"

   if "!param_ok!" == "1" (
      set "ret=0"
      set "GETSERV=%SGE_ROOT%\utilbin\win-x86\getservbyname"
      for /f "tokens=1,2 delims= " %%1 in ('!GETSERV! !service_name!') do (
         if "%%1" == "!service_name!" (
            set "ret=%%2"
         )
      )
   )
   endlocal & (
      rem these variables are set in the callers context
      set "%upvar%=%ret%"
   )
   exit /b

