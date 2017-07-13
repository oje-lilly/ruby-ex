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

if "%1" == "0" (
   set "SGE_DEBUG_LEVEL=" & set "SGE_ND="
) else if "%1" == "1" (
   set "SGE_DEBUG_LEVEL=2 0 0 0 0 0 0 0" & set "SGE_ND=true"
) else if "%1" == "2" (
   set "SGE_DEBUG_LEVEL=3 0 0 0 0 0 0 0" & set "SGE_ND=true"
) else if "%1" == "3" (
   set "SGE_DEBUG_LEVEL=2 2 0 0 0 0 2 0" & set "SGE_ND=true"
) else if "%1" == "4" (
   set "SGE_DEBUG_LEVEL=3 3 0 0 0 0 3 0" & set "SGE_ND=true"
) else if "%1" == "5" (
   set "SGE_DEBUG_LEVEL=3 0 0 3 0 0 3 0" & set "SGE_ND=true"
) else if "%1" == "6" (
   set "SGE_DEBUG_LEVEL=32 32 32 0 0 32 32 0" & set "SGE_ND=true"
) else if "%1" == "7" (
   echo dl: %1 is a still unused debugging level
) else if "%1" == "8" (
   echo dl: %1 is a still unused debugging level
) else if "%1" == "9" (
   set "SGE_DEBUG_LEVEL=2 2 2 0 0 0 0 0" & set "SGE_ND=true"
) else if "%1" == "10" (
   set "SGE_DEBUG_LEVEL=3 3 3 0 0 0 0 3" & set "SGE_ND=true"
) else (
   echo usage: dl ^<debugging_level^> ^[indent_width^]
   echo        debugging_level 0 - 10
   echo        indent_width    0 - 3
)

if not "%2" == "" (
   set "SGE_DEBUG_INDENT_WIDTH=%2"
) else (
   set SGE_DEBUG_INDENT_WIDTH=
)

