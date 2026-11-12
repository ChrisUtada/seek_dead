@echo off
REM ============================================================================
REM One-click smoke entry: run all regression suites after changes.
REM Usage: run_smoke.bat [godot console exe]
REM   default: D:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe
REM Exit code: 0 = all green, 1 = any failure. Logs go to %TEMP%\smoke_*.log
REM Suites: L0 intent gating / L0 boss loot theme / L1 lint / L2+L3 full smoke /
REM         T8 drops / T7 acquisition weighting / curriculum / charge / M1 reward suite / M2 growth / M2 weapon mastery / M3 binding suites / M4 demo config / P1 readability / M1 post-battle / M2 ACT1 board / M4 career / G6 codex / G6 forge / G5 run journal / G8 loadout layout / G7-A three-act chain / G7-B active strip-trim / G8-05 four-screen layout / G7-C skill collection semantics / G7-D decision depth / Mine grid Step 1-3 content, numbers, confirm and retreat / Normal enemy early traits / Elite-BOSS rhythm windows / Grid controlled templates / Reel clock Step 1 continuous time and landing / Reel absorb Step 2 deferred stop and settle / Reel pacing Step 3 speed, stagger and spin duration / Reel feedback Step 4 stop-cell pulse, tiered colors and combo cap / Step 1 shared triggers and debuffs / Step 4 elite combos / Step 5 boss rhythm
REM Save safety: user:// is redirected to %TEMP%\seek_dead_smoke_appdata so no
REM             test can read or write the real lobby_data.json. Wiped each run.
REM ============================================================================
setlocal
set "GODOT=%~1"
if not defined SD_SMOKE_APPDATA set "SD_SMOKE_APPDATA=%TEMP%\seek_dead_smoke_appdata"
if exist "%SD_SMOKE_APPDATA%" rmdir /s /q "%SD_SMOKE_APPDATA%" 2>nul
mkdir "%SD_SMOKE_APPDATA%" 2>nul
set "APPDATA=%SD_SMOKE_APPDATA%"
if "%GODOT%"=="" set "GODOT=D:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe"
if not exist "%GODOT%" (
  echo [smoke] Godot exe not found: %GODOT%
  exit /b 1
)
set FAIL=0
cd /d "%~dp0"

echo [1/37] L0 intent act-gating regression ...
"%GODOT%" --headless --fixed-fps 60 --path . --script res://tests/p0a_intent_act_gate_test.gd > "%TEMP%\smoke_p0a.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_p0a.log
) else (
  echo   ok
)
echo [2/37] L0 boss loot theme regression ...
"%GODOT%" --headless --fixed-fps 60 --path . --script res://tests/p0b_boss_loot_theme_test.gd > "%TEMP%\smoke_p0b.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_p0b.log
) else (
  echo   ok
)

echo [3/37] L1 content and math lint ...
"%GODOT%" --headless --fixed-fps 60 --path . --script res://tests/smoke_lint.gd > "%TEMP%\smoke_lint.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lint.log
) else (
  echo   ok
)

echo [4/37] L2+L3 full-run smoke and boss phase probes, about 40s ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/smoke_root.tscn > "%TEMP%\smoke_full.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_full.log
) else (
  echo   ok
)
findstr /C:"SMOKE|RESULT" "%TEMP%\smoke_full.log"

echo [5/37] T8 drop channels regression, about 60s ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/t8_drops_test.tscn > "%TEMP%\smoke_t8.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_t8.log
) else (
  echo   ok
)

echo [6/37] T7 acquisition weighting regression, about 60s ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/t7_acquisition_test.tscn > "%TEMP%\smoke_t7.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_t7.log
) else (
  echo   ok
)


echo [7/37] curriculum mini-mechanics regression ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/curriculum_test.tscn > "%TEMP%\smoke_curr.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_curr.log
) else (
  echo   ok
)


echo [8/37] charge gating micro-probe ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/charge_rule_test.tscn > "%TEMP%\smoke_chg.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_chg.log
) else (
  echo   ok
)

echo [9/37] M1 reward reach / prepick / collection / preview / telemetry ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m1_reward_reach_test.tscn > "%TEMP%\smoke_m1.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m1.log
) else (
  echo   ok
)

echo [10/37] M2 growth / perk choices / hooks ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m2_growth_test.tscn > "%TEMP%\smoke_m2.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m2.log
) else (
  echo   ok
)

echo [11/37] M2-02 weapon mastery / imprints ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m2_weapon_test.tscn > "%TEMP%\smoke_m2w.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m2w.log
) else (
  echo   ok
)

echo [12/37] M3 entity / symbol art binding ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m3_binding_test.tscn > "%TEMP%\smoke_m3b.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m3b.log
) else (
  echo   ok
)

echo [13/37] M4-01 ACT1 demo config / whitelist / growth coverage ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m4_demo_test.tscn > "%TEMP%\smoke_m4.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m4.log
) else (
  echo   ok
)

echo [14/37] P1 reel readability presets / visual stop / buffer / telemetry ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/p1_readability_test.tscn > "%TEMP%\smoke_p1.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_p1.log
) else (
  echo   ok
)

echo [15/37] M1 post-battle growth slots / queue / boss carryover ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m1_post_battle_test.tscn > "%TEMP%\smoke_m1pb.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m1pb.log
) else (
  echo   ok
)

echo [16/37] M2 ACT1 board topology / 1D3 / nodes / full run ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m2_board_test.tscn > "%TEMP%\smoke_m2board.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m2board.log
) else (
  echo   ok
)

echo [17/37] G6-01 career achievements / one-time unlock / old save ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m4_career_test.tscn > "%TEMP%\smoke_m4career.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m4career.log
) else (
  echo   ok
)

echo [18/37] G6-04 codex detail / sources / uses / mastery / imprints ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g6_codex_test.tscn > "%TEMP%\smoke_g6codex.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g6codex.log
) else (
  echo   ok
)

echo [19/37] G6-05 forge styles / 4 weapons / tradeoffs / real reel diff ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g6_forge_test.tscn > "%TEMP%\smoke_g6forge.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g6forge.log
) else (
  echo   ok
)

echo [20/37] G5 run journal / JSON + prefilled record ...
REM Needs --runlog because the journal only writes files in the export build or with this flag;
REM user:// is redirected to %TEMP% at the top, so nothing here can touch the real save.
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g5_journal_test.tscn -- --runlog > "%TEMP%\smoke_g5journal.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g5journal.log
) else (
  echo   ok
)
echo [21/37] G8 loadout screen layout / card fit / bottom bar / dialogs ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g8_loadout_layout_test.tscn > "%TEMP%\smoke_g8layout.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g8layout.log
) else (
  echo   ok
)

echo [22/37] G7-A S4 three-act chain / per-act boards / state carryover ... about 70s
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g7_run3_test.tscn > "%TEMP%\smoke_g7run3.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g7run3.log
) else (
  echo   ok
)

echo [23/37] G7-B B1/B2 active strip-trim rules / preview = real band / per-act cap ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g7b_trim_test.tscn > "%TEMP%\smoke_g7btrim.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g7btrim.log
) else (
  echo   ok
)

echo [24/37] G8-05 shop / reward / anvil+codex / meta screen layout ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g8_screens_layout_test.tscn > "%TEMP%\smoke_g8screens.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g8screens.log
) else (
  echo   ok
)

echo [25/37] G7-C skill collection semantics (owned_skills / anvil+shop / codex) ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g7c_skills_test.tscn > "%TEMP%\smoke_g7cskills.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g7cskills.log
) else (
  echo   ok
)

echo [26/37] G7-D decision depth: situation + real counters / telemetry / elite-BOSS rhythm ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g7d_decision_test.tscn > "%TEMP%\smoke_g7ddecision.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g7ddecision.log
) else (
  echo   ok
)

echo [27/37] Mine grid Step 1-3 content / numbers / reveal / boss-elite confirm / build-retreat ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/mine_grid_test.tscn > "%TEMP%\smoke_minegrid.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_minegrid.log
) else (
  echo   ok
)
echo [28/37] Normal enemy early traits / one trait each / no HP lock ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/normal_trait_test.tscn > "%TEMP%\smoke_normaltrait.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_normaltrait.log
) else (
  echo   ok
)

echo [29/37] Elite/BOSS rhythm windows: windup-burst-recovery / multi-answer hints / board samples ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/rhythm_windows_test.tscn > "%TEMP%\smoke_rhythm.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_rhythm.log
) else (
  echo   ok
)

echo [30/37] Grid controlled templates: 3 layouts / threat band / inferable route / seed rotation ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/grid_templates_test.tscn > "%TEMP%\smoke_gridtemplates.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_gridtemplates.log
) else (
  echo   ok
)

echo [31/37] Reel clock Step 1: continuous position / landing / fps independence / no RNG ...
"%GODOT%" --headless --fixed-fps 60 --path . --script res://tests/reel_clock_test.gd > "%TEMP%\smoke_reelclock.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_reelclock.log
) else (
  echo   ok
)

echo [32/37] Reel absorb Step 2: deferred stop / settle once / manual-auto / RNG ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/reel_absorb_test.tscn > "%TEMP%\smoke_reelabsorb.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_reelabsorb.log
) else (
  echo   ok
)

echo [33/37] Reel pacing Step 3: cruise 8-10 / cap 10-12 / auto-stop stagger / spin duration ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/reel_pacing_test.tscn > "%TEMP%\smoke_reelpacing.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_reelpacing.log
) else (
  echo   ok
)

echo [34/37] Reel feedback Step 4: stop-cell pulse / tiered colors / combo cap / no input block ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/reel_feedback_test.tscn > "%TEMP%\smoke_reelfeedback.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_reelfeedback.log
) else (
  echo   ok
)

echo [35/37] Step 1 shared triggers / debuffs: weak-vulnerable-corrode-drain-healblock-blind-entangle-backlash-strip / purify-cleanse split / no RNG ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/step1_module_test.tscn > "%TEMP%\smoke_step1.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_step1.log
) else (
  echo   ok
)

echo [36/37] Step 4 elite combos: per-elite pressure/recovery / D1-D4 differentiation / summaries / no HP lock ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/elite_combo_test.tscn > "%TEMP%\smoke_elitecombo.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_elitecombo.log
) else (
  echo   ok
)

echo [37/37] Step 5 boss rhythm: 13 bosses / real recovery window / act pools / shadow reconciliation ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/boss_rhythm_test.tscn > "%TEMP%\smoke_bossrhythm.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_bossrhythm.log
) else (
  echo   ok
)

if "%FAIL%"=="1" (
  echo [smoke] RESULT: FAIL
  exit /b 1
)
echo [smoke] RESULT: ALL GREEN
exit /b 0

