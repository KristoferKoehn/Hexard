@echo off
REM Installs the pinned Godot toolchain into tools/godot (git-ignored).
setlocal
set "PSHOST=powershell"
where pwsh >nul 2>nul && set "PSHOST=pwsh"
"%PSHOST%" -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%~dp0install-godot.ps1" %*
exit /b %ERRORLEVEL%
