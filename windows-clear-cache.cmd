@echo off
chcp 65001 >nul
title 正方成绩检查服务 - 隐私清除
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows-clear-cache.ps1" %*
set "SCRIPT_EXIT=%ERRORLEVEL%"
echo.
if "%SCRIPT_EXIT%"=="0" (
    echo 隐私清除流程已结束，按任意键关闭窗口。
) else (
    echo 隐私清除未完整完成，按任意键关闭窗口。
)
pause >nul
exit /b %SCRIPT_EXIT%
