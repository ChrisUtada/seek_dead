@echo off
REM ============================================================================
REM One-click smoke entry: run all regression suites after changes.
REM Usage: run_smoke.bat [godot console exe]
REM   default: D:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe
REM Exit code: 0 = all green, 1 = any failure. Logs go to %TEMP%\smoke_*.log
REM Suites: L0 intent gating / L0 boss loot theme / L1 lint / L2+L3 full smoke /
REM         T8 drops / T7 acquisition weighting / curriculum / charge / M1 reward suite / M2 growth / M2 weapon mastery suites
REM ============================================================================
setlocal
set "GODOT=%~1"
if "%GODOT%"=="" set "GODOT=D:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe"
if not exist "%GODOT%" (
  echo [smoke] Godot exe not found: %GODOT%
  exit /b 1
)
set FAIL=0
cd /d "%~dp0"

echo [1/11] L0 intent act-gating regression ...
"%GODOT%" --headless --fixed-fps 60 --path . --script res://tests/p0a_intent_act_gate_test.gd > "%TEMP%\smoke_p0a.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_p0a.log
) else (
  echo   ok
)
echo [2/11] L0 boss loot theme regression ...
"%GODOT%" --headless --fixed-fps 60 --path . --script res://tests/p0b_boss_loot_theme_test.gd > "%TEMP%\smoke_p0b.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_p0b.log
) else (
  echo   ok
)

echo [3/11] L1 content and math lint ...
"%GODOT%" --headless --fixed-fps 60 --path . --script res://tests/smoke_lint.gd > "%TEMP%\smoke_lint.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lint.log
) else (
  echo   ok
)

echo [4/11] L2+L3 full-run smoke and boss phase probes, about 40s ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/smoke_root.tscn > "%TEMP%\smoke_full.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_full.log
) else (
  echo   ok
)
findstr /C:"SMOKE|RESULT" "%TEMP%\smoke_full.log"

echo [5/11] T8 drop channels regression, about 60s ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/t8_drops_test.tscn > "%TEMP%\smoke_t8.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_t8.log
) else (
  echo   ok
)

echo [6/11] T7 acquisition weighting regression, about 60s ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/t7_acquisition_test.tscn > "%TEMP%\smoke_t7.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_t7.log
) else (
  echo   ok
)


echo [7/11] curriculum mini-mechanics regression ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/curriculum_test.tscn > "%TEMP%\smoke_curr.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_curr.log
) else (
  echo   ok
)


echo [8/11] charge gating micro-probe ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/charge_rule_test.tscn > "%TEMP%\smoke_chg.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_chg.log
) else (
  echo   ok
)

echo [9/11] M1 reward reach / prepick / collection / preview / telemetry ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m1_reward_reach_test.tscn > "%TEMP%\smoke_m1.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m1.log
) else (
  echo   ok
)

echo [10/11] M2 growth / perk choices / hooks ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m2_growth_test.tscn > "%TEMP%\smoke_m2.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m2.log
) else (
  echo   ok
)

echo [11/11] M2-02 weapon mastery / imprints ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m2_weapon_test.tscn > "%TEMP%\smoke_m2w.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m2w.log
) else (
  echo   ok
)

if "%FAIL%"=="1" (
  echo [smoke] RESULT: FAIL
  exit /b 1
)
echo [smoke] RESULT: ALL GREEN
exit /b 0

