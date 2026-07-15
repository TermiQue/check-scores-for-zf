@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows-launcher.ps1" %*
set "SCRIPT_EXIT=%ERRORLEVEL%"
if not "%SCRIPT_EXIT%"=="0" (
    echo.
    pause
)
endlocal & exit /b %SCRIPT_EXIT%
