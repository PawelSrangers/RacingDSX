@echo off
rem Double-click to record Forza telemetry. Close RacingDSX first.
set /p NAME=Recording name (e.g. gravel_rally, asphalt):
if "%NAME%"=="" set NAME=session
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0record_forza.ps1" -Name "%NAME%"
pause
