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
rem script to build windows-exe-loadsensor.exe from the windows-exe-loadsensor.c
rem source file
rem

echo.
echo This script builds "windows-exe-loadsensor.exe" from the source file
echo "windows-exe-loadsensor.c". It was tested to build with Microsoft
echo VisualStudio 2010, but it should build with most older and all newer
echo versions as well.
echo.

nmake /f windows-exe-loadsensor-makefile

if %ERRORLEVEL%==9009 (
   echo.
   echo Didn't find "nmake" in PATH, is VisualStudio installed?
   echo.
)

if %ERRORLEVEL%==0 (
   echo.
   echo "windows-exe-loadsensor.exe" was built successfully!
   echo.
)

exit /b 0

