@echo off
REM ============================================================================
REM One-click smoke entry: run all regression suites after changes.
REM Usage: run_smoke.bat [godot console exe]
REM   default: D:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe
REM Exit code: 0 = all green, 1 = any failure. Logs go to %TEMP%\smoke_*.log
REM Suites: L0 intent gating / L0 boss loot theme / L1 lint / L2+L3 full smoke /
REM Save safety: user:// is redirected to %TEMP%\seek_dead_smoke_appdata so no
REM             test can read or write the real lobby_data.json. Wiped each run.
REM ============================================================================
setlocal
del /q "%TEMP%\smoke_*.log" 2>nul
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

echo [1/58] L0 intent act-gating regression ...
"%GODOT%" --headless --fixed-fps 60 --path . --script res://tests/p0a_intent_act_gate_test.gd > "%TEMP%\smoke_p0a.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_p0a.log
) else (
  echo   ok
)
echo [2/58] L0 boss loot theme regression ...
"%GODOT%" --headless --fixed-fps 60 --path . --script res://tests/p0b_boss_loot_theme_test.gd > "%TEMP%\smoke_p0b.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_p0b.log
) else (
  echo   ok
)

echo [3/58] L1 content and math lint ...
"%GODOT%" --headless --fixed-fps 60 --path . --script res://tests/smoke_lint.gd > "%TEMP%\smoke_lint.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lint.log
) else (
  echo   ok
)

echo [4/58] L2+L3 full-run smoke and boss phase probes, about 40s ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/smoke_root.tscn > "%TEMP%\smoke_full.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_full.log
) else (
  echo   ok
)
findstr /C:"SMOKE|RESULT" "%TEMP%\smoke_full.log"

echo [5/58] T8 drop channels regression, about 60s ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/t8_drops_test.tscn > "%TEMP%\smoke_t8.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_t8.log
) else (
  echo   ok
)

echo [6/58] T7 acquisition weighting regression, about 60s ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/t7_acquisition_test.tscn > "%TEMP%\smoke_t7.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_t7.log
) else (
  echo   ok
)


echo [7/58] curriculum mini-mechanics regression ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/curriculum_test.tscn > "%TEMP%\smoke_curr.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_curr.log
) else (
  echo   ok
)


echo [8/58] charge gating micro-probe ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/charge_rule_test.tscn > "%TEMP%\smoke_chg.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_chg.log
) else (
  echo   ok
)

echo [9/58] M1 reward reach / prepick / collection / preview / telemetry ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m1_reward_reach_test.tscn > "%TEMP%\smoke_m1.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m1.log
) else (
  echo   ok
)

echo [10/58] M2 growth / perk choices / hooks ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m2_growth_test.tscn > "%TEMP%\smoke_m2.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m2.log
) else (
  echo   ok
)

echo [11/58] M2-02 weapon mastery / imprints ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m2_weapon_test.tscn > "%TEMP%\smoke_m2w.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m2w.log
) else (
  echo   ok
)

echo [12/58] M3 entity / symbol art binding ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m3_binding_test.tscn > "%TEMP%\smoke_m3b.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m3b.log
) else (
  echo   ok
)

echo [13/58] M4-01 ACT1 demo config / whitelist / growth coverage ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m4_demo_test.tscn > "%TEMP%\smoke_m4.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m4.log
) else (
  echo   ok
)

echo [14/58] P1 reel readability presets / visual stop / buffer / telemetry ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/p1_readability_test.tscn > "%TEMP%\smoke_p1.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_p1.log
) else (
  echo   ok
)

echo [15/58] M1 post-battle: same-tier loot three-choice then growth phase / queue / boss carryover ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m1_post_battle_test.tscn > "%TEMP%\smoke_m1pb.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m1pb.log
) else (
  echo   ok
)

echo [16/58] G6-01 career achievements / one-time unlock / old save ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m4_career_test.tscn > "%TEMP%\smoke_m4career.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m4career.log
) else (
  echo   ok
)

echo [17/58] G6-04 codex detail / sources / uses / mastery / imprints ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g6_codex_test.tscn > "%TEMP%\smoke_g6codex.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g6codex.log
) else (
  echo   ok
)

echo [18/58] G6-05 forge styles / 4 weapons / tradeoffs / real reel diff ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g6_forge_test.tscn > "%TEMP%\smoke_g6forge.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g6forge.log
) else (
  echo   ok
)

echo [19/58] G5 run journal / JSON + prefilled record ...
REM Needs --runlog because the journal only writes files in the export build or with this flag;
REM user:// is redirected to %TEMP% at the top, so nothing here can touch the real save.
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g5_journal_test.tscn -- --runlog > "%TEMP%\smoke_g5journal.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g5journal.log
) else (
  echo   ok
)
echo [20/58] G8 loadout screen layout / card fit / bottom bar / dialogs ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g8_loadout_layout_test.tscn > "%TEMP%\smoke_g8layout.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g8layout.log
) else (
  echo   ok
)

echo [21/58] G5 six-route slice: ACT1 core circuits / acquisition / trigger ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g5_routes_slice_test.tscn > "%TEMP%\smoke_g5routes.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g5routes.log
) else (
  echo   ok
)

echo [22/58] G7-B B1/B2 active strip-trim rules / preview = real band / per-act cap ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g7b_trim_test.tscn > "%TEMP%\smoke_g7btrim.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g7btrim.log
) else (
  echo   ok
)

echo [23/58] G8-05 shop / reward / anvil+codex / meta screen layout ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g8_screens_layout_test.tscn > "%TEMP%\smoke_g8screens.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g8screens.log
) else (
  echo   ok
)

echo [24/58] G7-C skill collection semantics (owned_skills / anvil+shop / codex) ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g7c_skills_test.tscn > "%TEMP%\smoke_g7cskills.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g7cskills.log
) else (
  echo   ok
)

echo [25/58] G7-D decision depth: situation + real counters / telemetry / elite-BOSS rhythm ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g7d_decision_test.tscn > "%TEMP%\smoke_g7ddecision.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g7ddecision.log
) else (
  echo   ok
)

echo [26/58] Normal enemy early traits / one trait each / no HP lock ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/normal_trait_test.tscn > "%TEMP%\smoke_normaltrait.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_normaltrait.log
) else (
  echo   ok
)

echo [27/58] Reel clock Step 1: continuous position / landing / fps independence / no RNG ...
"%GODOT%" --headless --fixed-fps 60 --path . --script res://tests/reel_clock_test.gd > "%TEMP%\smoke_reelclock.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_reelclock.log
) else (
  echo   ok
)

echo [28/58] Reel absorb Step 2: deferred stop / settle once / manual-auto / RNG ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/reel_absorb_test.tscn > "%TEMP%\smoke_reelabsorb.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_reelabsorb.log
) else (
  echo   ok
)

echo [29/58] Reel pacing Step 3: cruise 8-10 / cap 10-12 / auto-stop stagger / spin duration ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/reel_pacing_test.tscn > "%TEMP%\smoke_reelpacing.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_reelpacing.log
) else (
  echo   ok
)

echo [30/58] Reel feedback Step 4: stop-cell pulse / tiered colors / combo cap / no input block ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/reel_feedback_test.tscn > "%TEMP%\smoke_reelfeedback.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_reelfeedback.log
) else (
  echo   ok
)

echo [31/58] Step 1 shared triggers / debuffs: weak-vulnerable-corrode-drain-healblock-blind-entangle-backlash-strip / purify-cleanse split / no RNG ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/step1_module_test.tscn > "%TEMP%\smoke_step1.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_step1.log
) else (
  echo   ok
)

echo [32/58] Step 4 elite combos: per-elite pressure/recovery / D1-D4 differentiation / summaries / no HP lock ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/elite_combo_test.tscn > "%TEMP%\smoke_elitecombo.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_elitecombo.log
) else (
  echo   ok
)

echo [33/58] Step 5 boss rhythm: 13 bosses / real recovery window / act pools / shadow reconciliation ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/boss_rhythm_test.tscn > "%TEMP%\smoke_bossrhythm.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_bossrhythm.log
) else (
  echo   ok
)

echo [34/58] Step 1 loot taxonomy: 200 items / families / sources / high-tier mechanics / base entries ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/item_taxonomy_test.tscn > "%TEMP%\smoke_taxonomy.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_taxonomy.log
) else (
  echo   ok
)

echo [35/58] Reel shared-symbol sources: family cell budget / full weapon icons / source damage-crit-pierce / combo charge once ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/reel_source_test.tscn > "%TEMP%\smoke_reelsource.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_reelsource.log
) else (
  echo   ok
)

echo [36/58] Weapon archetypes: source-family-element combos / light combo / heavy armor break / ranged pierce / magic charge-status ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/weapon_archetype_test.tscn > "%TEMP%\smoke_weaponarch.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_weaponarch.log
) else (
  echo   ok
)

echo [37/58] Step 2 loot frequency: rarity never changes cells / old rare-epic cap removed / infusion-strip / mastery keeps rarity ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/loot_frequency_test.tscn > "%TEMP%\smoke_lootfreq.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lootfreq.log
) else (
  echo   ok
)

echo [38/58] Step 3 loot source table and pool: per-source quality weights / legality filters / same-tier roll / RNG isolation / shop ladder ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/loot_source_pool_test.tscn > "%TEMP%\smoke_lootpool.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lootpool.log
) else (
  echo   ok
)

echo [39/58] Step 4 loot offer: exactly three same-tier options / two purposes / frozen conversions / reroll keeps quality / skip frozen ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/loot_offer_test.tscn > "%TEMP%\smoke_lootoffer.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lootoffer.log
) else (
  echo   ok
)

echo [40/58] Step 5 loot explore: chest tags / source table legality / frozen linear room items / shop category ladder ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/loot_explore_test.tscn > "%TEMP%\smoke_lootexplore.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lootexplore.log
) else (
  echo   ok
)

echo [41/58] Step 6 loot growth: duplicate weapon mastery / settle once / growth queue untouched / codex source ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/loot_growth_test.tscn > "%TEMP%\smoke_lootgrowth.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lootgrowth.log
) else (
  echo   ok
)

echo [42/58] Step 7 loot UI: four-tier labels and colors / same-tier cards / reroll / replace / defer / no double grant ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/loot_ui_test.tscn > "%TEMP%\smoke_lootui.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lootui.log
) else (
  echo   ok
)

echo [43/58] Step 8 loot balance: source distribution 10k / offer invariants / dominance / tier usability / family paths / draft policies ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/loot_balance_test.tscn > "%TEMP%\smoke_lootbal.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lootbal.log
) else (
  echo   ok
)

echo [44/58] Step 6 monster counterplay: two valid counters per pressure / 61 bare-build clears / dual builds ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/counterplay_test.tscn > "%TEMP%\smoke_counterplay.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_counterplay.log
) else (
  echo   ok
)

echo [45/58] Growth loot: no direct gear / mastery-symbol-perk-hp-shield-heal / reroll cost / free skip / explore-boss items ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/growth_loot_offer_test.tscn > "%TEMP%\smoke_growthloot.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_growthloot.log
) else (
  echo   ok
)

echo [46/58] Weapon slot growth: general imprints follow slot / swap inherits / no copy / tune stays on weapon ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/weapon_slot_growth_test.tscn > "%TEMP%\smoke_slotgrowth.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_slotgrowth.log
) else (
  echo   ok
)

echo [47/58] Boss loot quality: empty-tier fallback / same-quality group / forced tier / exclude fallback / real boss entry ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/boss_loot_quality_test.tscn > "%TEMP%\smoke_bossquality.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_bossquality.log
) else (
  echo   ok
)

echo [48/58] Pattern system: G01-G03 / W01-W06 / T01-T03 / signatures / banner / tray / effect settlement ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/pattern_matcher_test.tscn > "%TEMP%\smoke_patternmatch.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_patternmatch.log
) else (
  echo   ok
)

echo [49/58] Pattern flow baseline: stop-then-settle / no post-settle swap window / single settle entry ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/pattern_flow_test.tscn > "%TEMP%\smoke_patternflow.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_patternflow.log
) else (
  echo   ok
)

echo [50/58] Pattern sample run: builds x 300 rounds trigger rate / 1000-round composition rate / three enemy tiers ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/pattern_sample_run_test.tscn > "%TEMP%\smoke_patternsample.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_patternsample.log
) else (
  echo   ok
)

echo [51/58] Pattern reachability: 2 weapons + 1 skill + 1 charm / 12 contents real Build examples / negatives ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/pattern_reachability_test.tscn > "%TEMP%\smoke_patternreach.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_patternreach.log
) else (
  echo   ok
)

echo [52/58] T3 no-status pattern contract: no rule depends on status symbols (fire batch) ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/t3_no_status_pattern_contract_test.tscn > "%TEMP%\smoke_t3nostatus.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_t3nostatus.log
) else (
  echo   ok
)

echo [53/58] M-02b chapter head info: name / portrait / element / weakness disclosure ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m02b_chapter_info_test.tscn > "%TEMP%\smoke_m02binfo.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m02binfo.log
) else (
  echo   ok
)

echo [54/58] M-02b chapter flow: linear act / room count / boss match ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m02b_chapter_flow_test.tscn > "%TEMP%\smoke_m02bflow.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m02bflow.log
) else (
  echo   ok
)

echo [55/58] M-02b chapter run / boss match consistency ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m02b_chapter_run_boss_match_test.tscn > "%TEMP%\smoke_m02bmatch.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m02bmatch.log
) else (
  echo   ok
)

echo [56/58] T19 mercy contract: per-turn gold / no jam merge / no reroll drift ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/t19_mercy_contract_test.tscn > "%TEMP%\smoke_t19mercy.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_t19mercy.log
) else (
  echo   ok
)

echo [57/58] G4 circuit reachability: default loadout reachable set / empty pool / why-not-triggered priority / report ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g4_reachability_test.tscn > "%TEMP%\smoke_g4reach.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g4reach.log
) else (
  echo   ok
)

echo [58/58] T3 no-status weapon contract: formal weapons with status symbols == 15-item whitelist ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/t3_no_status_weapon_contract_test.tscn > "%TEMP%\smoke_t3noweapon.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_t3noweapon.log
) else (
  echo   ok
)

echo [logcheck] scanning %TEMP%\smoke_*.log for SCRIPT ERROR / RESULT FAIL ...
powershell -NoProfile -ExecutionPolicy Bypass -File tools\check_smoke_logs.ps1 -LogDir "%TEMP%"
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- SCRIPT ERROR / RESULT FAIL found in smoke logs, see above
)

if "%FAIL%"=="1" (
  echo [smoke] RESULT: FAIL
  exit /b 1
)
echo [smoke] RESULT: ALL GREEN
exit /b 0

