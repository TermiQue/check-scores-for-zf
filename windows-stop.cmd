@echo off
cd /d "%~dp0"
echo 正在停止成绩检查器和 EasyConnect 容器...
docker compose -f "%~dp0compose.easyconnect.yml" down
if errorlevel 1 pause
