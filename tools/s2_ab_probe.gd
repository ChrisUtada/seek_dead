extends Node

# S2 实测 · A/B 两层只读探针（2026-11-21）
# 基于 full_run_probe 的回合驱动；只采集不改玩法/武器/敌人/断言。
# profiles 从 --profiles=<json文件> 读，格式：
#   {"profiles":[{"name":"A_absolute_zero","loadout":[路径,路径],"skills":[],"charms":[],
#                 "second_weapon_fixed":true,"max_rooms":6}, ...]}
# 每个 profile × 每 seed 跑一局，奖励阶段可强制跳过武器替换（A 层固定配装）。
# 输出：每 profile+seed 一个 JSON，落 --out 目录。
# 运行：Godot --headless --path . res://tools/s2_ab_probe.tscn -- --out=<dir> --profiles=<json> --seeds=111,333
# 输出前缀 S2AB|

const MATCHER := preload("res://scripts/battle/pattern_matcher.gd")
const OUT_DEFAULT := "user://runs/s2_deepen"
var OUT := OUT_DEFAULT
var SEEDS := [111, 333, 555, 777, 999, 1234]
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
		print("S2AB|NO_PROFILES")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Engine.time_scale = TIME_SCALE
	duel = load("res://scenes/duel/duel.tscn").instantiate() as DuelController
	duel.demo_config.enabled = false
	duel.demo_config.act_only = false
	add_child(duel)
	await _wait(0.35)
	var all := []
	for prof in profiles:
		for run_seed in SEEDS:
			var r := await _run_one(prof, int(run_seed))
			all.append(r)
			_write_json(OUT + "/" + String(prof["name"]) + "_" + str(run_seed) + ".json", r)
			print("S2AB|%s|%d|terminal=%s|rooms=%d|turns=%d|dmg=%d|shield=%.1f" % [
				String(prof["name"]), run_seed, str(r["terminal"]), int(r["rooms"].size()),
				int(r["turns"]), int(r["damage_taken"]), float(r.get("shield_total", 0.0))])
	_write_json(OUT + "/summary.json", {"generated_at": Time.get_datetime_string_from_system(),
		"seeds": SEEDS, "profiles": profiles, "runs": all})
	print("S2AB|RESULT_OK runs=%d" % all.size())
	get_tree().quit(0)

func _load_profiles(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("S2AB: cannot read profiles " + path)
		return []
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK:
		push_error("S2AB: parse profiles fail")
		return []
	var d: Variant = j.data
	if d is Dictionary: return d.get("profiles", [])
	if d is Array: return d
	return []

func _run_one(prof: Dictionary, run_seed: int) -> Dictionary:
	seed(run_seed)
	duel._reset_run_state()
	var loadout: Array = prof.get("loadout", [])
	duel.selected_loadout.clear()
	for p in loadout: duel.selected_loadout.append(String(p))
	duel.selected_skills.clear()
	for p in prof.get("skills", []): duel.selected_skills.append(String(p))
	duel.selected_charms.clear()
	for p in prof.get("charms", []): duel.selected_charms.append(String(p))
	duel.readability.apply_preset("readable")
	duel._confirm_loadout()
	# 回路配置：B 层专属构筑启用对应回路（A 层留空，隔离武器本身）
	if duel.circuit_system != null:
		for cid in prof.get("circuits", []):
			duel.circuit_system.acquire(String(cid))
			duel.circuit_system.equip(String(cid))
	await _wait(0.15)
	var max_rooms := int(prof.get("max_rooms", 6))
	var fix_second := bool(prof.get("second_weapon_fixed", false))
	var res := {"profile": String(prof["name"]), "seed": run_seed, "terminal": "RUNNING",
		"rooms": [], "turns": 0, "damage_taken": 0, "shield_total": 0.0,
		"core_triggers": {}, "frost_trace": [], "errors": []}
	var frames := 0
	var last_key := ""
	var current := {}
	while frames < 40000 and res["rooms"].size() < max_rooms:
		frames += 1
		if duel.hud._replace_dialog != null and duel.hud._replace_dialog.visible:
			# A 层固定配装：一律取消替换，保持配装不变
			duel.hud._on_replace_cancelled()
			await get_tree().process_frame
			continue
		if duel.hud.meta_screen.visible:
			res["terminal"] = "WON_GAME"; break
		if duel.game_state == DuelController.FlowState.LOST:
			res["terminal"] = "LOST"; _end_room(res, current)
			duel._on_overlay_button_pressed(); break
		if duel.in_interroom:
			duel._on_next_room_pressed(); await get_tree().process_frame; continue
		if duel.game_state == DuelController.FlowState.WON:
			_end_room(res, current)
			# 奖励：一律跳过武器（保持 A 层配装固定；B 层也不随机替换，避免混入换装差异）
			duel._on_reward_skip_pressed()
			await get_tree().process_frame
			continue
		if duel.hud.shop_screen_is_open():
			duel._on_shop_leave_pressed(); await get_tree().process_frame; continue
		if duel.game_state == DuelController.FlowState.PLAYING and not duel.in_loadout:
			var key := "%d:%s" % [duel.room_index, duel.enemy_name]
			if key != last_key:
				last_key = key
				var kind := ""
				if duel.current_room != null: kind = String(duel.current_room.kind)
				current = {"name": duel.enemy_name, "kind": kind,
					"hp_start": duel.player_hp, "enemy_hp_start": duel.enemy_hp,
					"armor_start": int(duel.enemy_armor), "turns": 0, "turn_log": []}
			var err := await _play_turn(current, run_seed)
			if err != "OK":
				res["errors"].append(err); res["terminal"] = err; break
		else:
			await get_tree().process_frame
	if res["terminal"] == "RUNNING": res["terminal"] = "ROOM_LIMIT"
	res["damage_taken"] = _sum_field(res["rooms"], "dmg_taken")
	res["shield_total"] = _sum_field(res["rooms"], "shield_total")
	return res

func _play_turn(current: Dictionary, run_seed: int) -> String:
	var rec := {"turn": int(duel.turn_count), "armor": int(duel.enemy_armor),
		"enemy_hp": int(duel.enemy_hp), "hp": int(duel.player_hp),
		"frost": int(duel.player_frost)}
	duel._on_spin_pressed()
	var frames := 0
	while frames < 600:
		frames += 1
		if duel.reel_system.spinning:
			var r := _next_reel()
			if r >= 0 and not duel.reel_system.reel_stopped[r] and not duel.reel_system.is_absorbing(r):
				var strip: Array = duel.reel_system.reel_strips[r]
				if not strip.is_empty():
					var target: String = String(duel.readability.target_symbol_path)
					var idx := 0
					for i in range(strip.size()):
						if String(strip[i][0].resource_path) == target: idx = i; break
					duel.reel_system.reel_cursor[r] = idx
					duel.reel_system.lock_reel(r, false, "player")
		elif not duel._busy:
			_finish_turn(current, rec)
			return "OK"
		await get_tree().process_frame
	_finish_turn(current, rec)
	return "TURN_TIMEOUT"

func _next_reel() -> int:
	for r in range(duel.reel_system.reel_stopped.size()):
		if not duel.reel_system.reel_stopped[r] and not duel.reel_system.has_pending_stop(r):
			return r
	return -1

func _finish_turn(current: Dictionary, rec: Dictionary) -> void:
	rec["armor_end"] = int(duel.enemy_armor)
	rec["enemy_hp_end"] = int(duel.enemy_hp)
	rec["hp_end"] = int(duel.player_hp)
	rec["frost_end"] = int(duel.player_frost)
	rec["dmg_taken"] = int(rec["hp"]) - int(rec["hp_end"])
	rec["hp_damage"] = maxi(0, int(rec["enemy_hp"]) - int(rec["enemy_hp_end"]))
	rec["shield"] = float(duel.player_shield)
	(current["turn_log"] as Array).append(rec)
	current["turns"] = int(current["turns"]) + 1

func _end_room(res: Dictionary, current: Dictionary) -> void:
	if current.is_empty(): return
	var turns: Array = current["turn_log"]
	var hp_dmg := 0
	var dmg_taken := 0
	var shield_peak := 0.0
	var frost_sum := 0.0
	for t in turns:
		hp_dmg += int(t.get("hp_damage", 0))
		dmg_taken += int(t.get("dmg_taken", 0))
		shield_peak = maxf(shield_peak, float(t.get("shield", 0.0)))
		frost_sum += float(t.get("frost", 0))
	current["hp_damage"] = hp_dmg
	current["dmg_taken"] = dmg_taken
	current["shield_total"] = shield_peak
	current["frost_avg"] = (frost_sum / maxf(1.0, float(turns.size())))
	current["ttk_turns"] = int(current["turns"])
	(res["rooms"] as Array).append(current)
	res["turns"] = int(res["turns"]) + int(current["turns"])
	# 回路触发统计：从 circuit.log 累计各 id 触发次数
	if duel.circuit_system != null:
		for entry in duel.circuit_system.log:
			var cid := String(entry.get("id", ""))
			if cid != "":
				res["core_triggers"][cid] = int(res["core_triggers"].get(cid, 0)) + 1

func _sum_field(rooms: Array, field: String) -> float:
	var s := 0.0
	for r in rooms: s += float(r.get(field, 0))
	return s

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify(data, "  "))
