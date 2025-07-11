@ECHO OFF

SET "PROJECT_ROOT=%~dp0"
SET "SCRIPT_PATH=%PROJECT_ROOT%app\ADVFileManager\ADVFileManager.ps1"
ECHO %SCRIPT_PATH%
ECHO.
ECHO.

ECHO Press key to continue ...
PAUSE
ECHO.
ECHO.
ECHO --- START ADVFileManager ---
powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT_PATH%"

pause
