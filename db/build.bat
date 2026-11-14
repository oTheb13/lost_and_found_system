@echo off
REM Rebuilds the local 'lfms' database from the 0*.sql files. DEV ONLY (drops the DB first).
cd /d "%~dp0"
set MYSQL=C:\xampp\mysql\bin\mysql.exe
if not exist "%MYSQL%" (
  echo Could not find %MYSQL%
  echo Edit the MYSQL line in this file to match your XAMPP install folder.
  pause
  exit /b 1
)
for %%f in (0*.sql) do (
  echo Running %%f
  "%MYSQL%" -u root < "%%f"
  if errorlevel 1 (
    echo FAILED on %%f. Is MySQL started in the XAMPP Control Panel?
    pause
    exit /b 1
  )
)
echo Done: database 'lfms' rebuilt.
pause
