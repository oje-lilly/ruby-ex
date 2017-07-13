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

echo | set /p ="Here I am. Sleeping now at: "
echo %date% %time%

rem ping a not reachable address
ping 192.0.2.2 -n 1 -w %1000 > nul 2>&1

echo | set /p ="Now it is "
echo %date% %time%
