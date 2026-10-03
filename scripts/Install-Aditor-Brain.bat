@echo off
title Aditor Brain setup
echo.
echo   Aditor Brain
echo   Setting up your shared knowledge vault. Nothing to type.
echo.
REM Runs bootstrap.ps1 bundled next to this file in the same download.
REM Keep both files together in the unzipped folder.
if not exist "%~dp0bootstrap.ps1" (
  echo   Could not find bootstrap.ps1 next to this installer.
  echo   Keep both files together in the unzipped folder, then try again,
  echo   or check the README for help.
  echo.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1"
echo.
echo   You can close this window.
echo.
pause
