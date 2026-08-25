@echo off
REM ============================================================================
REM One-click smoke entry: run all regression suites after changes.
REM Usage: run_smoke.bat [godot console exe]
REM   default: .workbuddy\godot_tmp\Godot_v4.7-stable_win64_console.exe
REM Exit code: 0 = all green, 1 = any failure. Logs go to %TEMP%\smoke_*.log
REM Suites: L0 intent gating / L0 boss loot theme / L1 lint / L2+L3 full smoke /
REM         T8 drops / T7 acquisition weighting
REM ============================================================================
setlocal
set "GODOT=%~1"
if "%GODOT%"=="" set "GODOT=%~dp0.workbuddy\godot_tmp\Godot_v4.7-stable_win64_console.exe"
if not exist "%GODOT%" (
  echo [smoke] Godot exe not found: %GODOT%
  exit /b 1
)
set FAIL=0
cd /d "%~dp0"

echo [1/7] L0 intent act-gating regression ...
"%GODOT%" --headless --fixed-fps 60 --path . --script res://tests/p0a_intent_act_gate_test.gd > "%TEMP%\smoke_p0a.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_p0a.log
) else (
  echo   ok
)
echo [2/7] L0 boss loot theme regression ...
"%GODOT%" --headless --fixed-fps 60 --path . --script res://tests/p0b_boss_loot_theme_test.gd > "%TEMP%\smoke_p0b.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_p0b.log
) else (
  echo   ok
)

echo [3/7] L1 content and math lint ...
"%GODOT%" --headless --fixed-fps 60 --path . --script res://tests/smoke_lint.gd > "%TEMP%\smoke_lint.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lint.log
) else (
  echo   ok
)

echo [4/7] L2+L3 full-run smoke and boss phase probes, about 40s ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/smoke_root.tscn > "%TEMP%\smoke_full.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_full.log
) else (
  echo   ok
)
findstr /C:"SMOKE|RESULT" "%TEMP%\smoke_full.log"

echo [5/7] T8 drop channels regression, about 60s ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/t8_drops_test.tscn > "%TEMP%\smoke_t8.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_t8.log
) else (
  echo   ok
)

echo [6/7] T7 acquisition weighting regression, about 60s ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/t7_acquisition_test.tscn > "%TEMP%\smoke_t7.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_t7.log
) else (
  echo   ok
)


echo [7/7] curriculum mini-mechanics regression ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/curriculum_test.tscn > "%TEMP%\smoke_curr.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_curr.log
) else (
  echo   ok
)

if "%FAIL%"=="1" (
  echo [smoke] RESULT: FAIL
  exit /b 1
)
echo [smoke] RESULT: ALL GREEN
exit /b 0
