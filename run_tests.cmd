@echo off
REM Runs Hexard's headless core test suite.
REM
REM This wrapper exists because PowerShell's execution policy blocks unsigned
REM .ps1 files on some machines; we pass a per-process bypass instead of asking
REM anyone to weaken their machine-wide policy.
setlocal
set "PSHOST=powershell"
where pwsh >nul 2>nul && set "PSHOST=pwsh"
"%PSHOST%" -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%~dp0run_tests.ps1" %*
exit /b %ERRORLEVEL%
