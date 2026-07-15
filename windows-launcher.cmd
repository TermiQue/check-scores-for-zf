@echo off
chcp 65001 >nul
title 正方成绩检查服务启动器
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows-launcher.ps1" %*
set "SCRIPT_EXIT=%ERRORLEVEL%"
echo.
if "%SCRIPT_EXIT%"=="0" (
    echo 启动器已结束，按任意键关闭窗口。
) else (
    echo 操作未成功完成，按任意键关闭窗口。
)
pause >nul
exit /b %SCRIPT_EXIT%
