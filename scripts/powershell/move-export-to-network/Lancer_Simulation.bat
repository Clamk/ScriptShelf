@echo off
REM SIMULATION : affiche ce qui serait transfere, ne copie et ne supprime rien.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Move-ExportToNetwork.ps1" -DryRun
pause
