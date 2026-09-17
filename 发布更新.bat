@echo off
rem ASCII-only on purpose: cmd.exe parses .bat with the OEM codepage (936 on
rem Chinese Windows), so UTF-8 Chinese in here becomes garbage paths.
rem All Chinese prompts live in publish.ps1 (UTF-8 with BOM).
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1" -Prompt
echo.
pause