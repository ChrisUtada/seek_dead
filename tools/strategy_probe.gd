extends Node

const OUT_DEFAULT := "res://docs/baseline/2026-11-11_strategy_probe"
const SEEDS_DEFAULT := [111, 333]
const STRATEGIES_DEFAULT := ["baseline", "tactical", "aim_only"]
var OUT := OUT_DEFAULT
var SEEDS: Array = SEEDS_DEFAULT
var STRATEGIES: Array = STRATEGIES_DEFAULT
var duel: DuelController
var initial_save: Dictionary = {}
var results: Array = []


func _ready() -> void:
	# 2026-11-11 Step 1：命令行可指定输出目录 / 种子 / 策略，避免每轮改探针：
	#   -- --out=res://docs/baseline/xxx --seeds=111,333 --strategies=aim_only,tactical
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			OUT = arg.substr(6)
		elif arg.begins_with("--seeds="):
			SEEDS = _parse_ints(arg.substr(8))
		elif arg.begins_with("--strategies="):
			STRATEGIES = arg.substr(13).split(",", false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	initial_save = SaveSystem.load_lobby_data().duplicate(true)
	duel = load("res://scenes/duel/duel.tscn").instantiate() as DuelController
	duel.demo_config.enabled = true
	add_child(duel)
	await _wait(0.35)
	for strategy in STRATEGIES:
		for run_seed in SEEDS:
			var result: Dictionary = await _run_one(strategy, run_seed)
			results.append(result)
			_write_json("%s/%s_%d.json" % [OUT, strategy, run_seed], result)
			print("STRATEGY_RUN|%s|%d|%s|rooms=%d|turns=%d|damage=%d|boss=%s" % [strategy, run_seed, result["terminal"], result["rooms"].size(), result["turns"], result["damage_taken"], result["boss"]])
	_write_json(OUT + "/summary.json", {"runs": results, "method": "same seed/loadout/rewards; readable only; baseline fixed interval/no consumable vs tactical target/consumable",
		"balance": {"counter_burst_pct": DuelController.BALANCE.counter_burst_pct, "heal_line_mults": DuelController.BALANCE.heal_line_mults}})
	print("STRATEGY_PROBE|DONE|%d" % results.size())
	get_tree().quit()


func _run_one(strategy: String, run_seed: int) -> Dictionary:
	seed(run_seed)
	duel.readability.apply_preset("readable")
	duel._confirm_loadout()
	await _wait(0.15)
	var result := {"strategy": strategy, "seed": run_seed, "terminal": "RUNNING", "rooms": [], "boss": "", "errors": []}
	var current := {}
	var last_key := ""
	var frames := 0
	while frames < 40000:
		frames += 1
		if duel.hud._replace_dialog != null and duel.hud._replace_dialog.visible:
			# 满双武器时选择武器奖励会弹替换层。此前探针一律取消，导致同一奖励被反复选中而卡死
			# （第 7 房精英后的「阻塞」即此路径）。按真实玩家行为替换第一把武器后继续。
			if not duel.selected_loadout.is_empty():
				duel.hud._on_replace_chosen(String(duel.selected_loadout[0]))
			else:
				duel.hud._on_replace_cancelled()
			await get_tree().process_frame
			continue
		if duel.hud.meta_screen.visible:
			result["terminal"] = "WON_GAME"
			duel._on_meta_choice_chosen({"kind": "anvil", "path": ""})
			break
		if duel.game_state == DuelController.FlowState.LOST:
			result["terminal"] = "LOST"
			_end_room(result, current)
			duel._on_overlay_button_pressed()
			break
		if duel.in_interroom:
			duel._on_next_room_pressed()
			await get_tree().process_frame
			continue
		if duel.game_state == DuelController.FlowState.WON:
			_end_room(result, current)
			if duel.room_flow.post_battle_active:
				if duel.room_flow.post_battle_has_growth():
					duel.room_flow.auto_pick_post_battle(["growth"])
				else:
					duel.room_flow.auto_pick_post_battle(["build", "supply"])
			else:
				duel._on_reward_skip_pressed()
			await get_tree().process_frame
			continue
		if duel.hud.shop_screen_is_open():
			duel._on_shop_leave_pressed()
			await get_tree().process_frame
			continue
		if duel.game_state == DuelController.FlowState.PLAYING and not duel.in_loadout:
			var key := "%d:%s" % [duel.room_index, duel.enemy_name]
			if key != last_key:
				last_key = key
				current = {"name": duel.enemy_name, "kind": duel.current_room.kind, "hp_start": duel.player_hp,
					"enemy_hp_start": duel.enemy_hp, "turns": 0, "hp_end": duel.player_hp, "finished": false}
				if duel.current_room.kind == "boss": result["boss"] = duel.enemy_name
			if strategy == "tactical": _use_consumables()
			var error: String = await _play_turn(strategy)
			if error != "OK":
				result["errors"].append(error)
				result["terminal"] = error
				break
		else:
			await get_tree().process_frame
	if result["terminal"] == "RUNNING": result["terminal"] = "FRAME_TIMEOUT"
	var telemetry: Dictionary = duel._telemetry.summary()
	result["turns"] = telemetry["turns"]
	result["triples"] = telemetry["triples"]
	result["damage_taken"] = telemetry["damage_taken"]
	result["damage_blocked"] = telemetry["damage_blocked"]
	result["enemy_attacks"] = telemetry["enemy_attacks"]
	result["target_hits"] = telemetry["target_hits"]
	result["stop_total"] = telemetry["stop_total"]
	result["target_hit_rate"] = telemetry["target_hit_rate"]
	result["buffer_queues"] = telemetry["buffer_queues"]
	result["weapon_swaps"] = telemetry["weapon_swaps"]
	result["counter_triples"] = telemetry["counter_triples"]
	result["counter_burst_damage"] = telemetry["counter_burst_damage"]
	result["heal_total"] = telemetry["heal_total"]
	result["heal_overflow_shield"] = telemetry["heal_overflow_shield"]
	result["consumable_uses"] = telemetry["consumable_uses"]
	result["growth"] = {"summary": duel.growth.summary_line(), "mastery": duel.mastery.summary_line()}
	return result


func _end_room(result: Dictionary, current: Dictionary) -> void:
	if current.is_empty() or bool(current.get("finished", false)): return
	current["finished"] = true
	current["turns"] = duel.turn_count
	current["hp_end"] = duel.player_hp
	(result["rooms"] as Array).append(current)


func _play_turn(strategy: String) -> String:
	duel._on_spin_pressed()
	var frames := 0
	while frames < 1200:
		frames += 1
		if duel.reel_system.spinning:
			if strategy == "baseline":
				if frames % 8 == 0: duel._on_spin_button_pressed()
			else:
				var reel := _next_reel()
				if reel >= 0:
					var strip: Array = duel.reel_system.reel_strips[reel]
					var vi: int = duel.hud.visual_center_index(reel)
					if vi >= 0 and vi < strip.size():
						var path := String(strip[vi][0].resource_path)
						if path == duel.readability.target_symbol_path or frames > 360:
							duel._on_reel_clicked(reel)
		elif not duel._busy:
			return "OK"
		await get_tree().process_frame
	return "TURN_TIMEOUT"


func _next_reel() -> int:
	for r in range(duel.reel_system.reel_stopped.size()):
		if not duel.reel_system.reel_stopped[r] and not duel.reel_system.has_pending_stop(r):
			return r
	return -1


func _use_consumables() -> void:
	if duel.player_hp < int(duel.player_hp_max * 0.45) and _use_effect("heal"):
		return
	if duel.pending_jam_reel >= 0 or duel.pending_lock_reel >= 0 or duel.pending_chaos or duel.pending_auto_stop:
		_use_effect("purify")


func _use_effect(effect: String) -> bool:
	for item in duel.consumable_slots:
		var data: Resource = load(item["path"])
		if data != null and data.effect == effect:
			duel.consumable_system.use(item["uid"])
			return true
	return false


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(data, "  "))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _parse_ints(text: String) -> Array:
	var out: Array = []
	for part in text.split(",", false):
		out.append(int(part.strip_edges()))
	return out
