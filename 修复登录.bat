@echo off
rem ASCII-only on purpose: cmd.exe parses .bat with the OEM codepage (936 on
rem Chinese Windows), so UTF-8 Chinese in here would become garbage paths.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix-auth.ps1"
echo.
pause