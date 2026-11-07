@echo off
REM Lanceur double-clic. Ajouter "-DryRun" apres le .ps1 pour une simulation.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Move-ExportToNetwork.ps1"
pause
