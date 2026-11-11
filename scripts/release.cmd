@echo off
rem Windows entry point: forwards arguments to release.sh (runs under Git Bash).
rem Usage (CMD / PowerShell):
rem   scripts\release.cmd 2.1.1 docs\next-release.md
rem Requires: Git for Windows installed (bash.exe on PATH).
setlocal
set "SCRIPT_DIR=%~dp0"
bash "%SCRIPT_DIR%release.sh" %*
endlocal & exit /b %ERRORLEVEL%
