@echo off
REM ============================================================================
REM Summary report for Seek Dead ACT1 auto-recorded runs (needs Python 3).
REM Double-click: summarize %APPDATA% runs dir.
REM Or drop a runs folder / pass args: this bat forwards them to the script.
REM Read-only: touches run_*.json only, never lobby_data.json.
REM NOTE: keep this file ASCII-only - cmd parses it in the OEM codepage.
REM ============================================================================
setlocal
cd /d "%~dp0"
chcp 65001 >nul
set "PYTHONIOENCODING=utf-8"
where py >nul 2>nul
if not errorlevel 1 (
  py -3 "tools\run_summary_report.py" %*
  goto done
)
where python >nul 2>nul
if not errorlevel 1 (
  python "tools\run_summary_report.py" %*
  goto done
)
echo [summary] Python 3 not found (py / python not on PATH).
echo           Install Python 3, then run: python tools\run_summary_report.py
:done
echo.
pause
