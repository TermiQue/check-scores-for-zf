@echo off
chcp 65001 >nul
title 正方成绩检查服务 - 停止
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows-stop.ps1"
set "SCRIPT_EXIT=%ERRORLEVEL%"
echo.
if "%SCRIPT_EXIT%"=="0" (
    echo 停止流程已结束，按任意键关闭窗口。
) else (
    echo 停止过程中发生错误，按任意键关闭窗口。
)
pause >nul
exit /b %SCRIPT_EXIT%
