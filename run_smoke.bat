@echo off
REM ============================================================================
REM One-click smoke entry: run all regression suites after changes.
REM Usage: run_smoke.bat [godot console exe]
REM   default: D:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe
REM Exit code: 0 = all green, 1 = any failure. Logs go to %TEMP%\smoke_*.log
REM Suites: L0 intent gating / L0 boss loot theme / L1 lint / L2+L3 full smoke /
REM         T8 drops / T7 acquisition weighting / curriculum / charge / M1 reward suite / M2 growth / M2 weapon mastery / M3 binding suites / M4 demo config / P1 readability / M1 post-battle / M2 ACT1 board / M4 career / G6 codex / G6 forge / G5 run journal / G8 loadout layout / G7-A three-act chain / G7-B active strip-trim / G8-05 four-screen layout / G7-C skill collection semantics / G7-D decision depth / Mine grid Step 1-3 content, numbers, confirm and retreat / Normal enemy early traits / Elite-BOSS rhythm windows / Grid controlled templates / Reel clock Step 1 continuous time and landing / Reel absorb Step 2 deferred stop and settle / Reel pacing Step 3 speed, stagger and spin duration / Reel feedback Step 4 stop-cell pulse, tiered colors and combo cap / Step 1 shared triggers and debuffs / Step 4 elite combos / Step 5 boss rhythm / Step 1 loot taxonomy / Reel shared-symbol sources / Weapon archetypes and combo rules / Step 2 loot frequency independence / Step 3 loot source table and pool / Step 4 loot offer three-choice / Step 5 loot exploration source and shop categories / Step 6 duplicate mastery and codex source / Step 7 loot UI display and interaction / Step 8 loot balance statistics and family paths / Step 6 monster counterplay two valid counters and bare-build clears / Growth loot choices and real effects / Map grid Step 1 14x9 greybox and route reachability / Map Step 0.5 act chain and dev gate / Map Step 0.5 node registry and loot sources / Map grid builder adjacency and room bindings / Map Step 2 movement, wait, revisit, camera and save-restore / Map Step 3 patrol cycles, next-step preview and boss reachability / Map Step 4 armor-break trap trigger, armor preview and one-shot settle
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

echo [1/56] L0 intent act-gating regression ...
"%GODOT%" --headless --fixed-fps 60 --path . --script res://tests/p0a_intent_act_gate_test.gd > "%TEMP%\smoke_p0a.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_p0a.log
) else (
  echo   ok
)
echo [2/56] L0 boss loot theme regression ...
"%GODOT%" --headless --fixed-fps 60 --path . --script res://tests/p0b_boss_loot_theme_test.gd > "%TEMP%\smoke_p0b.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_p0b.log
) else (
  echo   ok
)

echo [3/56] L1 content and math lint ...
"%GODOT%" --headless --fixed-fps 60 --path . --script res://tests/smoke_lint.gd > "%TEMP%\smoke_lint.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lint.log
) else (
  echo   ok
)

echo [4/56] L2+L3 full-run smoke and boss phase probes, about 40s ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/smoke_root.tscn > "%TEMP%\smoke_full.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_full.log
) else (
  echo   ok
)
findstr /C:"SMOKE|RESULT" "%TEMP%\smoke_full.log"

echo [5/56] T8 drop channels regression, about 60s ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/t8_drops_test.tscn > "%TEMP%\smoke_t8.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_t8.log
) else (
  echo   ok
)

echo [6/56] T7 acquisition weighting regression, about 60s ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/t7_acquisition_test.tscn > "%TEMP%\smoke_t7.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_t7.log
) else (
  echo   ok
)


echo [7/56] curriculum mini-mechanics regression ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/curriculum_test.tscn > "%TEMP%\smoke_curr.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_curr.log
) else (
  echo   ok
)


echo [8/56] charge gating micro-probe ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/charge_rule_test.tscn > "%TEMP%\smoke_chg.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_chg.log
) else (
  echo   ok
)

echo [9/56] M1 reward reach / prepick / collection / preview / telemetry ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m1_reward_reach_test.tscn > "%TEMP%\smoke_m1.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m1.log
) else (
  echo   ok
)

echo [10/56] M2 growth / perk choices / hooks ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m2_growth_test.tscn > "%TEMP%\smoke_m2.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m2.log
) else (
  echo   ok
)

echo [11/56] M2-02 weapon mastery / imprints ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m2_weapon_test.tscn > "%TEMP%\smoke_m2w.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m2w.log
) else (
  echo   ok
)

echo [12/56] M3 entity / symbol art binding ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m3_binding_test.tscn > "%TEMP%\smoke_m3b.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m3b.log
) else (
  echo   ok
)

echo [13/56] M4-01 ACT1 demo config / whitelist / growth coverage ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m4_demo_test.tscn > "%TEMP%\smoke_m4.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m4.log
) else (
  echo   ok
)

echo [14/56] P1 reel readability presets / visual stop / buffer / telemetry ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/p1_readability_test.tscn > "%TEMP%\smoke_p1.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_p1.log
) else (
  echo   ok
)

echo [15/56] M1 post-battle: same-tier loot three-choice then growth phase / queue / boss carryover ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m1_post_battle_test.tscn > "%TEMP%\smoke_m1pb.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m1pb.log
) else (
  echo   ok
)

echo [16/56] M2 ACT1 board topology / 1D3 / nodes / full run ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m2_board_test.tscn > "%TEMP%\smoke_m2board.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m2board.log
) else (
  echo   ok
)

echo [17/56] G6-01 career achievements / one-time unlock / old save ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/m4_career_test.tscn > "%TEMP%\smoke_m4career.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_m4career.log
) else (
  echo   ok
)

echo [18/56] G6-04 codex detail / sources / uses / mastery / imprints ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g6_codex_test.tscn > "%TEMP%\smoke_g6codex.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g6codex.log
) else (
  echo   ok
)

echo [19/56] G6-05 forge styles / 4 weapons / tradeoffs / real reel diff ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g6_forge_test.tscn > "%TEMP%\smoke_g6forge.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g6forge.log
) else (
  echo   ok
)

echo [20/56] G5 run journal / JSON + prefilled record ...
REM Needs --runlog because the journal only writes files in the export build or with this flag;
REM user:// is redirected to %TEMP% at the top, so nothing here can touch the real save.
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g5_journal_test.tscn -- --runlog > "%TEMP%\smoke_g5journal.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g5journal.log
) else (
  echo   ok
)
echo [21/56] G8 loadout screen layout / card fit / bottom bar / dialogs ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g8_loadout_layout_test.tscn > "%TEMP%\smoke_g8layout.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g8layout.log
) else (
  echo   ok
)

echo [22/56] G7-A S4 three-act chain / per-act boards / state carryover ... about 70s
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g7_run3_test.tscn > "%TEMP%\smoke_g7run3.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g7run3.log
) else (
  echo   ok
)

echo [23/56] G7-B B1/B2 active strip-trim rules / preview = real band / per-act cap ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g7b_trim_test.tscn > "%TEMP%\smoke_g7btrim.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g7btrim.log
) else (
  echo   ok
)

echo [24/56] G8-05 shop / reward / anvil+codex / meta screen layout ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g8_screens_layout_test.tscn > "%TEMP%\smoke_g8screens.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g8screens.log
) else (
  echo   ok
)

echo [25/56] G7-C skill collection semantics (owned_skills / anvil+shop / codex) ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g7c_skills_test.tscn > "%TEMP%\smoke_g7cskills.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g7cskills.log
) else (
  echo   ok
)

echo [26/56] G7-D decision depth: situation + real counters / telemetry / elite-BOSS rhythm ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g7d_decision_test.tscn > "%TEMP%\smoke_g7ddecision.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_g7ddecision.log
) else (
  echo   ok
)

echo [27/56] Mine grid Step 1-3 content / numbers / reveal / boss-elite confirm / build-retreat ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/mine_grid_test.tscn > "%TEMP%\smoke_minegrid.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_minegrid.log
) else (
  echo   ok
)
echo [28/56] Normal enemy early traits / one trait each / no HP lock ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/normal_trait_test.tscn > "%TEMP%\smoke_normaltrait.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_normaltrait.log
) else (
  echo   ok
)

echo [29/56] Elite/BOSS rhythm windows: windup-burst-recovery / multi-answer hints / board samples ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/rhythm_windows_test.tscn > "%TEMP%\smoke_rhythm.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_rhythm.log
) else (
  echo   ok
)

echo [30/56] Grid controlled templates: 3 layouts / threat band / inferable route / seed rotation ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/grid_templates_test.tscn > "%TEMP%\smoke_gridtemplates.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_gridtemplates.log
) else (
  echo   ok
)

echo [31/56] Reel clock Step 1: continuous position / landing / fps independence / no RNG ...
"%GODOT%" --headless --fixed-fps 60 --path . --script res://tests/reel_clock_test.gd > "%TEMP%\smoke_reelclock.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_reelclock.log
) else (
  echo   ok
)

echo [32/56] Reel absorb Step 2: deferred stop / settle once / manual-auto / RNG ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/reel_absorb_test.tscn > "%TEMP%\smoke_reelabsorb.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_reelabsorb.log
) else (
  echo   ok
)

echo [33/56] Reel pacing Step 3: cruise 8-10 / cap 10-12 / auto-stop stagger / spin duration ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/reel_pacing_test.tscn > "%TEMP%\smoke_reelpacing.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_reelpacing.log
) else (
  echo   ok
)

echo [34/56] Reel feedback Step 4: stop-cell pulse / tiered colors / combo cap / no input block ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/reel_feedback_test.tscn > "%TEMP%\smoke_reelfeedback.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_reelfeedback.log
) else (
  echo   ok
)

echo [35/56] Step 1 shared triggers / debuffs: weak-vulnerable-corrode-drain-healblock-blind-entangle-backlash-strip / purify-cleanse split / no RNG ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/step1_module_test.tscn > "%TEMP%\smoke_step1.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_step1.log
) else (
  echo   ok
)

echo [36/56] Step 4 elite combos: per-elite pressure/recovery / D1-D4 differentiation / summaries / no HP lock ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/elite_combo_test.tscn > "%TEMP%\smoke_elitecombo.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_elitecombo.log
) else (
  echo   ok
)

echo [37/56] Step 5 boss rhythm: 13 bosses / real recovery window / act pools / shadow reconciliation ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/boss_rhythm_test.tscn > "%TEMP%\smoke_bossrhythm.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_bossrhythm.log
) else (
  echo   ok
)

echo [38/56] Step 1 loot taxonomy: 200 items / families / sources / high-tier mechanics / base entries ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/item_taxonomy_test.tscn > "%TEMP%\smoke_taxonomy.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_taxonomy.log
) else (
  echo   ok
)

echo [39/56] Reel shared-symbol sources: family cell budget / full weapon icons / source damage-crit-pierce / combo charge once ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/reel_source_test.tscn > "%TEMP%\smoke_reelsource.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_reelsource.log
) else (
  echo   ok
)

echo [40/56] Weapon archetypes: source-family-element combos / light combo / heavy armor break / ranged pierce / magic charge-status ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/weapon_archetype_test.tscn > "%TEMP%\smoke_weaponarch.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_weaponarch.log
) else (
  echo   ok
)

echo [41/56] Step 2 loot frequency: rarity never changes cells / old rare-epic cap removed / infusion-strip / mastery keeps rarity ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/loot_frequency_test.tscn > "%TEMP%\smoke_lootfreq.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lootfreq.log
) else (
  echo   ok
)

echo [42/56] Step 3 loot source table and pool: per-source quality weights / legality filters / same-tier roll / RNG isolation / shop ladder ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/loot_source_pool_test.tscn > "%TEMP%\smoke_lootpool.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lootpool.log
) else (
  echo   ok
)

echo [43/56] Step 4 loot offer: exactly three same-tier options / two purposes / frozen conversions / reroll keeps quality / skip frozen ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/loot_offer_test.tscn > "%TEMP%\smoke_lootoffer.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lootoffer.log
) else (
  echo   ok
)

echo [44/56] Step 5 loot explore: chest tags / source table legality / frozen board items / shop category ladder ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/loot_explore_test.tscn > "%TEMP%\smoke_lootexplore.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lootexplore.log
) else (
  echo   ok
)

echo [45/56] Step 6 loot growth: duplicate weapon mastery / settle once / growth queue untouched / codex source ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/loot_growth_test.tscn > "%TEMP%\smoke_lootgrowth.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lootgrowth.log
) else (
  echo   ok
)

echo [46/56] Step 7 loot UI: four-tier labels and colors / same-tier cards / reroll / replace / defer / no double grant ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/loot_ui_test.tscn > "%TEMP%\smoke_lootui.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lootui.log
) else (
  echo   ok
)

echo [47/56] Step 8 loot balance: source distribution 10k / offer invariants / dominance / tier usability / family paths / draft policies ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/loot_balance_test.tscn > "%TEMP%\smoke_lootbal.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_lootbal.log
) else (
  echo   ok
)

echo [48/56] Step 6 monster counterplay: two valid counters per pressure / 61 bare-build clears / dual builds ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/counterplay_test.tscn > "%TEMP%\smoke_counterplay.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_counterplay.log
) else (
  echo   ok
)

echo [49/56] Growth loot: no direct gear / mastery-symbol-perk-hp-shield-heal / reroll cost / free skip / explore-boss items ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/growth_loot_offer_test.tscn > "%TEMP%\smoke_growthloot.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_growthloot.log
) else (
  echo   ok
)

echo [50/56] Map grid Step 1: 14x9 greybox / budget / reachable routes / fixed seed / validate guards ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/map_grid_test.tscn > "%TEMP%\smoke_mapgrid.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_mapgrid.log
) else (
  echo   ok
)

echo [51/56] Map Step 0.5 act chain: config-driven boss final / ACT I-II continue / no ACT IV / dev gate ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/map_act_chain_test.tscn > "%TEMP%\smoke_mapact.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_mapact.log
) else (
  echo   ok
)

echo [52/56] Map Step 0.5 loot explore: node registry / real sources / frozen fields / no double settle ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/map_loot_explore_test.tscn > "%TEMP%\smoke_maploot.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_maploot.log
) else (
  echo   ok
)

echo [53/56] Map grid builder: 61 nodes / bidirectional adjacency / 16 room bindings / fixed seed ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/map_builder_test.tscn > "%TEMP%\smoke_mapbuilder.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_mapbuilder.log
) else (
  echo   ok
)

echo [54/56] Map Step 2 movement: adjacency gate / wait once / revisit no double settle / camera 9x7 / save-restore ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/map_move_test.tscn > "%TEMP%\smoke_mapmove.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_mapmove.log
) else (
  echo   ok
)

echo [55/56] Map Step 3 patrol: frozen cycles / preview matches move / occupy and bump / order / boss never blocked ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/map_patrol_test.tscn > "%TEMP%\smoke_mappatrol.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_mappatrol.log
) else (
  echo   ok
)

echo [56/56] Map Step 4 armor-break trap: trigger once / preview equals combat / no instant kill / player safe ...
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/map_trap_test.tscn > "%TEMP%\smoke_maptrap.log" 2>&1
if errorlevel 1 (
  set FAIL=1
  echo   FAIL -- see %TEMP%\smoke_maptrap.log
) else (
  echo   ok
)

if "%FAIL%"=="1" (
  echo [smoke] RESULT: FAIL
  exit /b 1
)
echo [smoke] RESULT: ALL GREEN
exit /b 0

