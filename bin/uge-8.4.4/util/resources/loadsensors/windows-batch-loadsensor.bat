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

rem
rem example for a Windows batch load sensor script
rem

rem enable variable expansion at run time, not at parse time
setlocal enabledelayedexpansion

rem get name of this host
for /f %%i in ('hostname') do set "hostname=%%i"

set "do_sensor_loop=1"
:while_sensor_loop
   rem read from stdin
   set /p input=

   if "!input!" == "quit" (
      rem quit the load sensor loop
      set "do_sensor_loop=0"
   ) else (
      rem send mark for begin of load report
      echo begin

      rem send fake load value in format:
      rem hostname:load_value_name:load_value
      echo !hostname!:windows_test_load:1.23456

      rem send mark for end of load report
      echo end
   )
   rem do next loop?
   if "%do_sensor_loop%" == "1" goto :while_sensor_loop

rem exit the script, but exit the command interpreter only if it is not interactive
exit /b 0

