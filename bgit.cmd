@echo off
setlocal

REM bgit Windows shim: requires Git for Windows (bash.exe) or WSL bash in PATH.

set "SCRIPT_DIR=%~dp0"

where bash >nul 2>nul
if errorlevel 1 (
  echo bash not found in PATH. 1>&2
  echo Install Git for Windows and run from Git Bash, or install WSL. 1>&2
  exit /b 1
)

bash "%SCRIPT_DIR%bin\bgit" %*
