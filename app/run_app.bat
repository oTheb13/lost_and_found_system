@echo off
REM First run creates a venv and installs packages, then starts the app.
cd /d "%~dp0"
set PY=python
where python >nul 2>nul || set PY=py
if not exist venv (
  %PY% -m venv venv
)
call venv\Scripts\activate
pip install -r requirements.txt
echo.
echo Starting LFMS at http://127.0.0.1:5000  (Ctrl+C to stop)
python app.py
pause
