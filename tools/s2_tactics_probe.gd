extends Node

# S2 实测 · 确定性战术 bot + 针对性场景探针（2026-11-21）
# 只读工具：按 profile 指定的战术策略与敌人场景跑固定种子战斗，采集分解数据。
# 策略（确定性战术 bot，非真人）：perfect / frost_control / weakness / tri_color / pair_seek / defense
# 场景：low_armor / high_armor / light_weak / dark_weak / high_freq / heavy_hit / high_pressure
# 输出：每 profile+seed+场景一个 JSON + summary；前缀 S2TAC|
# 运行：Godot --headless --path . res://tools/s2_tactics_probe.tscn -- --out=<dir> --profiles=<json> --seeds=111,333

var OUT := "user://runs/s2_tactics"
var SEEDS := [111, 333, 555]
var profiles: Array = []
var TIME_SCALE := 40.0
var duel: DuelController

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var s := String(arg)
		if s.begins_with("--out="): OUT = s.substr(6)
		elif s.begins_with("--seeds="):
			SEEDS = []
			for p in s.substr(8).split(",", false): SEEDS.append(int(String(p).strip_edges()))
		elif s.begins_with("--profiles="): profiles = _load_profiles(s.substr(11))
	if profiles.is_empty():
		print("S2TAC|NO_PROFILES"); get_tree().quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Engine.time_scale = TIME_SCALE
	duel = load("res://scenes/duel/duel.tscn").instantiate() as DuelController
	duel.demo_config.enabled = false; duel.demo_config.act_only = false
	add_child(duel)
	await _wait(0.35)
	var all := []
	for prof in profiles:
		var scenarios: Array = prof.get("scenarios", ["high_pressure"])
		for scen in scenarios:
			for run_seed in SEEDS:
				var r := await _run_one(prof, String(scen), int(run_seed))
				all.append(r)
				_write_json(OUT + "/%s_%s_%d.json" % [String(prof["name"]), String(scen), run_seed], r)
				print("S2TAC|%s|%s|%d|terminal=%s|turns=%d|raw=%d|blocked=%d|dealt=%d|shield_waste=%d" % [
					String(prof["name"]), String(scen), run_seed, str(r["terminal"]),
					int(r["turns"]), int(r["raw_attack"]), int(r["blocked"]),
					int(r["hp_damage_taken"]), int(r["shield_waste"])])
	_write_json(OUT + "/summary.json", {"generated_at": Time.get_datetime_string_from_system(),
		"seeds": SEEDS, "operation_note": "确定性战术bot，非真人；只验证机制上限", "runs": all})
	print("S2TAC|RESULT_OK runs=%d" % all.size())
	get_tree().quit(0)

func _load_profiles(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return []
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK: return []
	var d: Variant = j.data
	if d is Dictionary: return d.get("profiles", [])
	return []

func _run_one(prof: Dictionary, scen: String, run_seed: int) -> Dictionary:
	seed(run_seed)
	duel._reset_run_state()
	duel.selected_loadout.clear()
	for p in prof.get("loadout", []): duel.selected_loadout.append(String(p))
	duel.selected_skills.clear()
	for p in prof.get("skills", []): duel.selected_skills.append(String(p))
	duel.selected_charms.clear()
	for p in prof.get("charms", []): duel.selected_charms.append(String(p))
	duel.readability.apply_preset("readable")
	duel._confirm_loadout()
	if duel.circuit_system != null:
		for cid in prof.get("circuits", []):
			duel.circuit_system.acquire(String(cid)); duel.circuit_system.equip(String(cid))
	_apply_scenario(scen)
	await _wait(0.15)
	var res := {"profile": String(prof["name"]), "strategy": String(prof.get("strategy", "perfect")),
		"scenario": scen, "seed": run_seed, "terminal": "RUNNING", "turns": 0,
		"raw_attack": 0, "blocked": 0, "hp_damage_taken": 0, "shield_waste": 0,
		"shield_peak": 0, "shield_end": 0, "frost_max": 0, "frost_sum": 0.0,
		"enemy_frost_max": 0, "enemy_frost_sum": 0.0,
		"frost_seal_turns": 0, "frost_seal_mult_min": 0.0,
		"circuit_triggers": {}, "pattern_triggers": {}, "errors": []}
	var frames := 0
	while frames < 30000 and int(res["turns"]) < int(prof.get("max_turns", 14)):
		frames += 1
		if duel.hud.meta_screen.visible: res["terminal"] = "WON_GAME"; break
		if duel.game_state == DuelController.FlowState.LOST: res["terminal"] = "LOST"; break
		if duel.hud.shop_screen_is_open(): duel._on_shop_leave_pressed(); await get_tree().process_frame; continue
		if duel.game_state == DuelController.FlowState.WON:
			# 单房间专项：胜利即结束，不推进多房（避免战利品/幕间状态机卡死）
			res["terminal"] = "WON"
			break
		if duel.hud._replace_dialog != null and duel.hud._replace_dialog.visible:
			duel.hud._on_replace_cancelled(); await get_tree().process_frame; continue
		if duel.in_interroom: duel._on_next_room_pressed(); await get_tree().process_frame; continue
		if duel.game_state == DuelController.FlowState.PLAYING and not duel.in_loadout:
			var err := await _play_turn(String(prof.get("strategy", "perfect")), res, run_seed)
			if err != "OK": res["errors"].append(err); res["terminal"] = err; break
		else:
			await get_tree().process_frame
	if res["terminal"] == "RUNNING": res["terminal"] = "TURN_LIMIT"
	if duel._telemetry != null:
		res["raw_attack"] = int(duel._telemetry.enemy_attacks)
		res["blocked"] = int(duel._telemetry.damage_blocked)
		res["hp_damage_taken"] = int(duel._telemetry.damage_taken)
	res["shield_end"] = int(duel.player_shield)
	if int(res["turns"]) > 0: res["frost_avg"] = float(res["frost_sum"]) / float(res["turns"])
	return res

func _apply_scenario(scen: String) -> void:
	# 固定敌人场景：控制 HP/护甲/攻击/弱点；不修改任何资源文件，只设运行时字段
	match scen:
		"low_armor":
			duel.enemy_hp = 300; duel.enemy_hp_max = 300; duel.enemy_armor = 0; duel.enemy_armor_max = 0
		"high_armor":
			duel.enemy_hp = 300; duel.enemy_hp_max = 300; duel.enemy_armor = 120; duel.enemy_armor_max = 120
		"light_weak":
			duel.enemy_hp = 320; duel.enemy_hp_max = 320; duel.enemy_element = "dark"  # 光克暗
		"dark_weak":
			duel.enemy_hp = 320; duel.enemy_hp_max = 320; duel.enemy_element = "light" # 暗克光
		"high_freq":
			duel.enemy_hp = 400; duel.enemy_hp_max = 400; duel.boss_atk_mult = 0.5  # 高频弱攻近似：低伤多回合由 max_turns 控制
		"heavy_hit":
			duel.enemy_hp = 400; duel.enemy_hp_max = 400; duel.boss_atk_mult = 2.0  # 低频重击近似
		"high_pressure":
			duel.enemy_hp = 500; duel.enemy_hp_max = 500; duel.boss_atk_mult = 1.2
		_:
			duel.enemy_hp = 400; duel.enemy_hp_max = 400
	duel.player_hp = duel.player_hp_max
	duel._busy = false

func _play_turn(strategy: String, res: Dictionary, run_seed: int) -> String:
	duel._on_spin_pressed()
	var frames := 0
	while frames < 600:
		frames += 1
		if duel.reel_system.spinning:
			var r := _next_reel()
			if r >= 0 and not duel.reel_system.reel_stopped[r] and not duel.reel_system.is_absorbing(r):
				var strip: Array = duel.reel_system.reel_strips[r]
				if not strip.is_empty():
					var idx := _pick_index(strategy, strip, r, res, run_seed)
					duel.reel_system.reel_cursor[r] = idx
					duel.reel_system.lock_reel(r, false, "player")
		elif not duel._busy:
			_finish_turn(res)
			return "OK"
		await get_tree().process_frame
	_finish_turn(res)
	return "TURN_TIMEOUT"

func _pick_index(strategy: String, strip: Array, col: int, res: Dictionary, run_seed: int) -> int:
	var target := String(duel.readability.target_symbol_path)
	var fallback := 0
	for i in range(strip.size()):
		if String(strip[i][0].resource_path) == target: fallback = i; break
	match strategy:
		"frost_control":
			# 霜冻控制：优先 frost 状态符号（至阈值），否则目标符号
			for i in range(strip.size()):
				var s: Resource = strip[i][0]
				if s != null and String(s.kind) == "status" and String(s.status_type) == "frost": return i
			return fallback
		"weakness":
			# 弱点切换：按敌人弱点选克制元素符号（敌人 dark→光符号，敌人 light→暗符号）
			var want: String = ""
			if duel.enemy_element == "dark": want = "light"
			elif duel.enemy_element == "light": want = "dark"
			if want != "":
				for i in range(strip.size()):
					var s: Resource = strip[i][0]
					if s != null and String(s.element) == want and String(s.kind) == "damage": return i
			return fallback
		"tri_color":
			# 异色：按列指定暗/光/火目标
			var wants: Array = ["dark", "light", "fire"]
			var want: String = String(wants[col % 3])
			for i in range(strip.size()):
				var s: Resource = strip[i][0]
				if s != null and String(s.element) == want: return i
			return fallback
		"pair_seek":
			# 对子：优先与目标符号同族的另一格（两同一异）——简化为选目标符号
			return fallback
		"defense":
			# 防御：重击前优先护盾符号，其余目标符号
			if duel.boss_atk_mult >= 1.5:
				for i in range(strip.size()):
					var s: Resource = strip[i][0]
					if s != null and String(s.kind) == "shield": return i
			return fallback
		_:
			return fallback

func _finish_turn(res: Dictionary) -> void:
	res["turns"] = int(res["turns"]) + 1
	var shield := int(duel.player_shield)
	res["shield_peak"] = maxi(int(res["shield_peak"]), shield)
	var frost := int(duel.player_frost)
	res["frost_max"] = maxi(int(res["frost_max"]), frost)
	res["frost_sum"] = float(res["frost_sum"]) + float(frost)
	# 敌人霜冻层数（削攻来源）与霜封削攻倍率（评审要求记录削攻兑现，不统计虚假 DoT）
	var enemy_frost := 0
	if duel.enemy_status is Dictionary:
		enemy_frost = int(duel.enemy_status.get("frost", 0))
	res["enemy_frost_max"] = maxi(int(res["enemy_frost_max"]), enemy_frost)
	res["enemy_frost_sum"] = float(res["enemy_frost_sum"]) + float(enemy_frost)
	var pm: float = float(duel._pattern_enemy_atk_mult)
	if pm < 1.0:
		res["frost_seal_turns"] = int(res["frost_seal_turns"]) + 1
		res["frost_seal_mult_min"] = minf(float(res["frost_seal_mult_min"]), pm) if float(res["frost_seal_mult_min"]) > 0.0 else pm
	if duel.circuit_system != null:
		for e in duel.circuit_system.log:
			var cid := String(e.get("id", ""))
			if cid != "": res["circuit_triggers"][cid] = int(res["circuit_triggers"].get(cid, 0)) + 1

func _next_reel() -> int:
	for r in range(duel.reel_system.reel_stopped.size()):
		if not duel.reel_system.reel_stopped[r] and not duel.reel_system.has_pending_stop(r): return r
	return -1

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify(data, "  "))
