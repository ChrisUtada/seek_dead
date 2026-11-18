extends Node

const OUT_DEFAULT := "res://.workbuddy/full_run"
const SEEDS_DEFAULT := [111, 333, 555, 777, 999, 1234]
const STRATEGIES_DEFAULT := ["tactical"]
var OUT := OUT_DEFAULT
var SEEDS: Array = SEEDS_DEFAULT
var STRATEGIES: Array = STRATEGIES_DEFAULT
var TIME_SCALE := 40.0
var duel: DuelController
var initial_save: Dictionary = {}
var results: Array = []
var mech_stats: Dictionary = {}   # 机制使用率：一局内各机制触发/出现计数

func _bump(key: String, n: int = 1) -> void:
	mech_stats[key] = int(mech_stats.get(key, 0)) + n


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
		elif arg.begins_with("--speed="):
			TIME_SCALE = float(arg.substr(8))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Engine.time_scale = TIME_SCALE   # 加速全部timer/动画演出（await create_timer 受此影响）
	initial_save = SaveSystem.load_lobby_data().duplicate(true)
	duel = load("res://scenes/duel/duel.tscn").instantiate() as DuelController
	duel.demo_config.enabled = false   # 关闭demo限制，跑完整三幕
	duel.demo_config.act_only = false
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
	mech_stats = {}
	if strategy == "dot":
		# DoT 流派验证：强制装备两把自带 DoT 符号的武器（火+光）
		duel.selected_loadout.assign([
			"res://resources/weapon_templates/fire_sword.tres",
			"res://resources/weapon_templates/holy_sword.tres",
		])
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
			var is_boss_offer := false
			for c in duel.reward_choices:
				if String(c.get("kind", "")).begins_with("boss_"):
					is_boss_offer = true
					break
			if is_boss_offer:
				# BOSS 战利品：优先领遗物（否则跳过会导致遗物/信物/图鉴全 0，机制使用率失真）
				var pick = duel.reward_choices[0]
				for c in duel.reward_choices:
					if String(c.get("kind", "")) == "boss_relic":
						pick = c
						break
				duel._on_boss_reward_chosen(pick)
			elif duel.room_flow.post_battle_active:
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
				var room_trait := ""
				var room_summary := ""
				if duel.current_room != null:
					room_trait = String(duel.current_room.gimmick_params.get("trait", ""))
					room_summary = String(duel.current_room.mechanic_summary)
				current = {"name": duel.enemy_name, "kind": duel.current_room.kind, "hp_start": duel.player_hp,
					"enemy_hp_start": duel.enemy_hp, "turns": 0, "hp_end": duel.player_hp, "finished": false,
					"trait": room_trait, "mechanic_summary": room_summary,
					"armor_start": int(duel.enemy_armor), "armor_max_start": int(duel.enemy_armor_max),
					"frost_start": int(duel.player_frost), "jam_start": int(duel.pending_jam_reel),
					"turn_log": []}
				if duel.current_room.kind == "boss": result["boss"] = duel.enemy_name
			if strategy == "tactical": _use_consumables()
			var error: String = await _play_turn(strategy, current)
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
	# 遗物/收集品统计
	result["relics_run"] = int(duel.run_relics.size())
	result["charms_owned"] = int(duel.selected_charms.size())
	if duel._codex != null:
		var c = duel._codex
		result["codex"] = {
			"weapon": "%d/%d" % [c.owned_count("weapon"), c.total_count("weapon")],
			"skill": "%d/%d" % [c.owned_count("skill"), c.total_count("skill")],
			"charm": "%d/%d" % [c.owned_count("charm"), c.total_count("charm")],
		}
	mech_stats["relics_owned_max"] = int(duel.run_relics.size())
	result["mech"] = mech_stats
	return result


func _end_room(result: Dictionary, current: Dictionary) -> void:
	if current.is_empty() or bool(current.get("finished", false)): return
	current["finished"] = true
	current["turns"] = duel.turn_count
	current["hp_end"] = duel.player_hp
	current["armor_end"] = int(duel.enemy_armor)
	# 普通怪特性是否在离房前已经触发（shell 在入场即生效，不置 _done，由 armor_max_start 判定）
	# 用 get("_done") 防御：精英/BOSS gimmick 不一定有该字段。
	current["trait_done"] = (duel.current_gimmick.get("_done") == true) if duel.current_gimmick != null else false
	# Step 3：把逐回合窗口压成摘要，便于直接统计「爆发/恢复是否真的出现」。
	var burst_turns: Array = []
	var recovery_turns: Array = []
	for t in (current.get("turn_log", []) as Array):
		var window := String(t.get("window", ""))
		if window == "爆发": burst_turns.append(int(t.get("turn", 0)))
		elif window == "恢复": recovery_turns.append(int(t.get("turn", 0)))
	current["burst_turns"] = burst_turns
	current["recovery_turns"] = recovery_turns
	current["rhythm_seen"] = not burst_turns.is_empty() and not recovery_turns.is_empty()
	(result["rooms"] as Array).append(current)


func _play_turn(strategy: String, current: Dictionary) -> String:
	# 完美玩家模拟：不依赖视觉目押（高 time_scale 会让目押失真），直接把转轮光标
	# 设到目标符号 index 后 lock_reel(use_visual=false)，100% 精确命中目标 Build 符号。
	# 这样测出的是「最优操作下的通关能力/难度曲线」，而非 AI 的目押水平。
	var turn_rec := {"turn": int(duel.turn_count), "window": "",
		"armor": int(duel.enemy_armor), "frost": int(duel.player_frost),
		"enemy_hp": int(duel.enemy_hp), "hp": int(duel.player_hp)}
	if duel.current_gimmick != null:
		turn_rec["window"] = String(duel.current_gimmick.rhythm_window(duel))
	duel._on_spin_pressed()
	var frames := 0
	var locked := false
	while frames < 300:
		frames += 1
		if duel.reel_system.spinning and not locked:
			locked = true
			var target: String = duel.readability.target_symbol_path
			for r in range(DuelController.REELS):
				if duel.reel_system.reel_stopped[r] or duel.reel_system.is_absorbing(r):
					continue
				var strip: Array = duel.reel_system.reel_strips[r]
				if strip.is_empty():
					continue
				# 找目标符号在本列的 index；dot 策略优先 DoT 状态符号
				var idx := -1
				if strategy == "dot":
					for i in range(strip.size()):
						var sym0: Resource = strip[i][0]
						var kv = sym0.get("kind") if sym0 != null else null
						if kv != null and String(kv) == "status":
							idx = i
							break
				if idx < 0:
					for i in range(strip.size()):
						if String(strip[i][0].resource_path) == target:
							idx = i
							break
				if idx < 0:
					idx = 0
				duel.reel_system.reel_cursor[r] = idx
				duel.reel_system.lock_reel(r, false, "player")
		elif not duel._busy and locked:
			_finish_turn(current, turn_rec)
			return "OK"
		await get_tree().process_frame
	_finish_turn(current, turn_rec)
	return "TURN_TIMEOUT"


func _finish_turn(current: Dictionary, turn_rec: Dictionary) -> void:
	turn_rec["armor_end"] = int(duel.enemy_armor)
	turn_rec["frost_end"] = int(duel.player_frost)
	turn_rec["enemy_hp_end"] = int(duel.enemy_hp)
	turn_rec["hp_end"] = int(duel.player_hp)
	# 机制使用率采样：本回合敌人身上的 DoT 状态 + 上一意图类型 + 遗物数
	for st in duel.enemy_status.keys():
		_bump("dot_" + String(st))
	var li: Dictionary = duel.last_enemy_intent
	if not li.is_empty():
		_bump("intent_" + String(li.get("type", "none")))
	_bump("relics_owned_max", 0)   # 占位，结束时会用实际值覆盖
	(current["turn_log"] as Array).append(turn_rec)


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
