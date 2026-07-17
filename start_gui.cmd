@echo off
setlocal
set "ROOT=%~dp0"
set "APP=%ROOT%runtime\flutter-windows\voicetransl_flutter.exe"
set "WORKER=%ROOT%asmr_worker.py"
set "PYTHON=%ROOT%.venv\Scripts\python.exe"

if not exist "%APP%" (
    echo Flutter GUI build not found.
    echo Run update_gui.cmd after the GitHub Actions workflow succeeds.
    pause
    exit /b 1
)
if not exist "%WORKER%" (
    echo Python worker not found: %WORKER%
    pause
    exit /b 1
)
if not exist "%PYTHON%" (
    echo Project Python environment not found: %PYTHON%
    echo Run scripts\setup_local_runtime.ps1 first.
    pause
    exit /b 1
)

set "VOICETRANSL_WORKER=%WORKER%"
set "VOICETRANSL_PYTHON=%PYTHON%"
pushd "%ROOT%"
start "" "%APP%"
popd
