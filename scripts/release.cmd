@echo off
setlocal
rem Resolve Git for Windows Bash so Windows' WSL launcher cannot shadow it.
for /f "delims=" %%G in ('git --exec-path') do set "GIT_EXEC_PATH_DIR=%%G"
if not defined GIT_EXEC_PATH_DIR (
  echo Git for Windows is required. >&2
  exit /b 1
)
for %%G in ("%GIT_EXEC_PATH_DIR%\..\..\..\bin\bash.exe") do set "GIT_BASH=%%~fG"
if not exist "%GIT_BASH%" (
  echo Git for Windows Bash was not found. >&2
  exit /b 1
)
"%GIT_BASH%" "%~dp0release.sh" %*
endlocal & exit /b %ERRORLEVEL%
