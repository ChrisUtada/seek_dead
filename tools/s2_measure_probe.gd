extends Node

# S2 修正测量探针（2026-11-21）：只采集不改玩法/武器/回路赔付/全局数值。
# mode: shield(护盾对账) / frost(霜冻bot+签名) / break(真实RoomData破甲) / pair(对子收益归因)
# 运行：Godot --headless --path . res://tools/s2_measure_probe.tscn -- --out=<dir> --mode=<mode> --profiles=<json> --seeds=111,333
# 输出前缀 S2MEAS|

var OUT := "user://runs/s2_measure"
var MODE := "shield"
var SEEDS := [111, 333, 555]
var profiles: Array = []
var TIME_SCALE := 40.0
var duel: DuelController

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var s := String(arg)
		if s.begins_with("--out="): OUT = s.substr(6)
		elif s.begins_with("--mode="): MODE = s.substr(7)
		elif s.begins_with("--seeds="):
			SEEDS = []
			for p in s.substr(8).split(",", false): SEEDS.append(int(String(p).strip_edges()))
		elif s.begins_with("--profiles="): profiles = _load_profiles(s.substr(11))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Engine.time_scale = TIME_SCALE
	duel = load("res://scenes/duel/duel.tscn").instantiate() as DuelController
	duel.demo_config.enabled = false; duel.demo_config.act_only = false
	add_child(duel)
	await _wait(0.35)
	var all := []
	match MODE:
		"shield": all = await _run_shield()
		"frost": all = await _run_frost()
		"break": all = await _run_break()
		"pair": all = await _run_pair()
		_: print("S2MEAS|UNKNOWN_MODE " + MODE)
	_write_json(OUT + "/summary_" + MODE + ".json", {"generated_at": Time.get_datetime_string_from_system(),
		"mode": MODE, "seeds": SEEDS, "note": "修正测量：只采集不调参", "runs": all})
	print("S2MEAS|RESULT_OK mode=%s runs=%d" % [MODE, all.size()])
	get_tree().quit(0)

func _setup(prof: Dictionary) -> void:
	seed(int(prof.get("_seed", 111)))
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

func _load_profiles(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return []
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK: return []
	var d: Variant = j.data
	if d is Dictionary: return d.get("profiles", [])
	return []

# ============ mode shield：护盾逐回合对账 ============
func _run_shield() -> Array:
	var out := []
	for prof in profiles:
		for run_seed in SEEDS:
			prof["_seed"] = run_seed
			_setup(prof)
			duel.start_room_data(_make_room(prof, "normal"), 0)
			await _wait(0.15)
			var res := {"profile": String(prof["name"]), "seed": run_seed, "mode": "shield",
				"turns": 0, "rows": [], "terminal": "RUNNING", "circuit_triggers": {},
				"shield_carry_rooms": 0, "shield_cap_found": false, "decay_found": false}
			var max_turns := int(prof.get("max_turns", 12))
			var frames := 0
			while frames < 20000 and int(res["turns"]) < max_turns:
				frames += 1
				if duel.game_state == DuelController.FlowState.LOST: res["terminal"] = "LOST"; break
				if duel.game_state == DuelController.FlowState.WON: res["terminal"] = "WON"; break
				if duel.game_state == DuelController.FlowState.PLAYING and not duel.in_loadout:
					var err := await _play_turn_detailed(String(prof.get("strategy", "defense")), res)
					if err != "OK": res["terminal"] = err; break
				else: await get_tree().process_frame
			if res["terminal"] == "RUNNING": res["terminal"] = "TURN_LIMIT"
			out.append(res)
			_write_json(OUT + "/shield_%s_%d.json" % [String(prof["name"]), run_seed], res)
			print("S2MEAS|shield|%s|%d|rows=%d|sum_gain=%d|sum_block=%d|end_remaining=%d|circuits=%s" % [
				String(prof["name"]), run_seed, (res["rows"] as Array).size(),
				_sum(res["rows"], "gain"), _sum(res["rows"], "blocked"),
				int(res["rows"][-1].get("remaining", 0)) if not (res["rows"] as Array).is_empty() else 0,
				str(res["circuit_triggers"])])
	return out

# 逐回合护盾对账：期初 + 新增 - 格挡 - 清除 = 期末
func _play_turn_detailed(strategy: String, res: Dictionary) -> String:
	var begin_shield := int(duel.player_shield)
	var tele_raw0 := 0; var tele_block0 := 0
	if duel._telemetry != null:
		tele_raw0 = int(duel._telemetry.enemy_attacks)
		tele_block0 = int(duel._telemetry.damage_blocked)
	duel._on_spin_pressed()
	var frames := 0
	while frames < 600:
		frames += 1
		if duel.reel_system.spinning:
			var r := _next_reel()
			if r >= 0 and not duel.reel_system.reel_stopped[r] and not duel.reel_system.is_absorbing(r):
				var strip: Array = duel.reel_system.reel_strips[r]
				if not strip.is_empty():
					duel.reel_system.reel_cursor[r] = _pick_index(strategy, strip, r)
					duel.reel_system.lock_reel(r, false, "player")
		elif not duel._busy: break
		await get_tree().process_frame
	var end_shield := int(duel.player_shield)
	var raw := 0; var blocked := 0
	if duel._telemetry != null:
		raw = int(duel._telemetry.enemy_attacks) - tele_raw0
		blocked = int(duel._telemetry.damage_blocked) - tele_block0
	# 对账：期初 + 本回合新增 − 实际格挡 = 期末（房内无过期清除时）。
	# 新增由 期末−期初+格挡 反推；"未消耗/浪费"= 期末剩余护盾（战斗结束仍挂着的部分）。
	var implied_gain := end_shield - begin_shield + blocked
	(res["rows"] as Array).append({"turn": int(res["turns"]) + 1,
		"begin": begin_shield, "end": end_shield, "blocked": blocked,
		"gain": implied_gain, "remaining": end_shield, "raw_attack": raw,
		"hp_end": int(duel.player_hp)})
	res["turns"] = int(res["turns"]) + 1
	if duel.circuit_system != null:
		for e in duel.circuit_system.log:
			var cid := String(e.get("id", ""))
			if cid != "": res["circuit_triggers"][cid] = int(res["circuit_triggers"].get(cid, 0)) + 1
	return "OK"

# ============ mode frost：修正 bot + 签名核查 ============
func _run_frost() -> Array:
	var out := []
	for prof in profiles:
		for run_seed in SEEDS:
			prof["_seed"] = run_seed
			_setup(prof)
			duel.start_room_data(_make_room(prof, prof.get("room_kind", "elite")), 0)
			await _wait(0.15)
			# 签名核查：两冰前置 + W02 + SIG_W02_* 是否真实解锁/生效
			var sig_info := _check_signature(prof)
			var res := {"profile": String(prof["name"]), "seed": run_seed, "mode": "frost",
				"signature": sig_info, "turns": 0, "rows": [], "terminal": "RUNNING",
				"hp_damage": 0, "enemy_frost_sum": 0.0, "waste_stacks": 0}
			var max_turns := int(prof.get("max_turns", 14))
			var frames := 0
			while frames < 20000 and int(res["turns"]) < max_turns:
				frames += 1
				if duel.game_state == DuelController.FlowState.LOST: res["terminal"] = "LOST"; break
				if duel.game_state == DuelController.FlowState.WON: res["terminal"] = "WON"; break
				if duel.game_state == DuelController.FlowState.PLAYING and not duel.in_loadout:
					var err := await _play_turn_frost(String(prof.get("strategy", "frost_hold")), res)
					if err != "OK": res["terminal"] = err; break
				else: await get_tree().process_frame
			if res["terminal"] == "RUNNING": res["terminal"] = "TURN_LIMIT"
			out.append(res)
			_write_json(OUT + "/frost_%s_%d.json" % [String(prof["name"]), run_seed], res)
			print("S2MEAS|frost|%s|%d|terminal=%s|sig_ok=%s|frost_avg=%.1f|waste=%d|hp_dmg=%d" % [
				String(prof["name"]), run_seed, str(res["terminal"]),
				str(sig_info.get("sig_unlocked", false)),
				float(res["enemy_frost_sum"]) / maxf(1.0, float(res["turns"])),
				int(res["waste_stacks"]), int(res["hp_damage"])])
	return out

func _check_signature(prof: Dictionary) -> Dictionary:
	var loadout: Array = []
	for p in prof.get("loadout", []): loadout.append(String(p))
	var tag_of := Callable(duel, "_pattern_tag_of")
	var unlocked: Array = duel._pattern_system.unlocked_patterns(loadout, tag_of)
	var ids: Array = []
	for p in unlocked:
		if p == null: continue
		ids.append(String(p.id))
	# 检查 W02 与两个签名是否解锁（find_signature 需 cards，空数组表示仅看解锁链）
	var w02 := ids.has("W02")
	var sig_zero := ids.has("SIG_W02_ZERO")
	var sig_icegun := ids.has("SIG_W02_ICEGUN")
	return {"unlocked_ids": ids, "w02": w02, "sig_zero": sig_zero, "sig_icegun": sig_icegun,
		"two_ice": loadout.size() >= 2 and _all_ice(loadout),
		"sig_unlocked": sig_zero or sig_icegun}

func _all_ice(loadout: Array) -> bool:
	for p in loadout:
		var wd: Resource = load(String(p))
		if wd == null or String(wd.get("element")) != "ice": return false
	return true

# 修正 bot：达到维持阈值后切伤害，不持续堆层；记录超阈值浪费层数
func _play_turn_frost(strategy: String, res: Dictionary) -> String:
	var hp0 := int(duel.enemy_hp)
	var frost_before := int(duel.enemy_status.get("frost", 0)) if duel.enemy_status is Dictionary else 0
	duel._on_spin_pressed()
	var frames := 0
	while frames < 600:
		frames += 1
		if duel.reel_system.spinning:
			var r := _next_reel()
			if r >= 0 and not duel.reel_system.reel_stopped[r] and not duel.reel_system.is_absorbing(r):
				var strip: Array = duel.reel_system.reel_strips[r]
				if not strip.is_empty():
					var target := String(duel.readability.target_symbol_path)
					var idx := 0
					for i in range(strip.size()):
						if String(strip[i][0].resource_path) == target: idx = i; break
					if strategy == "frost_hold" and frost_before >= 3:
						# 达维持阈值后切伤害：优先 damage 符号
						for i in range(strip.size()):
							var s: Resource = strip[i][0]
							if s != null and String(s.get("kind")) == "damage": idx = i; break
					elif strategy == "frost_hold":
						for i in range(strip.size()):
							var s: Resource = strip[i][0]
							if s != null and String(s.get("status_type")) == "frost": idx = i; break
					duel.reel_system.reel_cursor[r] = idx
					duel.reel_system.lock_reel(r, false, "player")
		elif not duel._busy: break
		await get_tree().process_frame
	var frost_after := int(duel.enemy_status.get("frost", 0)) if duel.enemy_status is Dictionary else 0
	var eff_cap := 3  # frost 减攻上限：每层0.2，上限0.5 → 有效阈值≈3层
	if frost_after > eff_cap: res["waste_stacks"] = int(res["waste_stacks"]) + (frost_after - eff_cap)
	res["enemy_frost_sum"] = float(res["enemy_frost_sum"]) + float(frost_after)
	res["hp_damage"] = int(res["hp_damage"]) + maxi(0, hp0 - int(duel.enemy_hp))
	(res["rows"] as Array).append({"turn": int(res["turns"]) + 1,
		"frost_before": frost_before, "frost_after": frost_after,
		"hp_damage": maxi(0, hp0 - int(duel.enemy_hp)),
		"pattern_atk_mult": float(duel._pattern_enemy_atk_mult)})
	res["turns"] = int(res["turns"]) + 1
	return "OK"

# ============ mode break：真实 RoomData 破甲重测 ============
func _run_break() -> Array:
	var out := []
	for prof in profiles:
		for run_seed in SEEDS:
			prof["_seed"] = run_seed
			_setup(prof)
			var room := _make_room(prof, "normal")
			duel.start_room_data(room, 0)
			await _wait(0.15)
			# 开战后断言实际护甲符合场景（评审要求）
			var armor_ok := int(duel.enemy_armor) == int(prof.get("armor", 0))
			var res := {"profile": String(prof["name"]), "seed": run_seed, "mode": "break",
				"scenario_armor": int(prof.get("armor", 0)), "actual_armor": int(duel.enemy_armor),
				"armor_scenario_ok": armor_ok, "actual_hp": int(duel.enemy_hp),
				"actual_atk": int(duel.enemy_atk), "turns": 0, "rows": [], "terminal": "RUNNING",
				"break_turn": -1, "ttk_turns": 0, "hp_damage": 0}
			var max_turns := int(prof.get("max_turns", 12))
			var frames := 0
			while frames < 20000 and int(res["turns"]) < max_turns:
				frames += 1
				if duel.game_state == DuelController.FlowState.LOST: res["terminal"] = "LOST"; break
				if duel.game_state == DuelController.FlowState.WON: res["terminal"] = "WON"; break
				if duel.game_state == DuelController.FlowState.PLAYING and not duel.in_loadout:
					var err := await _play_turn_break(res)
					if err != "OK": res["terminal"] = err; break
				else: await get_tree().process_frame
			if res["terminal"] == "RUNNING": res["terminal"] = "TURN_LIMIT"
			res["ttk_turns"] = int(res["turns"])
			out.append(res)
			_write_json(OUT + "/break_%s_%d.json" % [String(prof["name"]), run_seed], res)
			print("S2MEAS|break|%s|%d|armor_ok=%s|act_armor=%d|break_turn=%d|ttk=%d|terminal=%s" % [
				String(prof["name"]), run_seed, str(armor_ok), int(res["actual_armor"]),
				int(res["break_turn"]), int(res["ttk_turns"]), str(res["terminal"])])
	return out

func _play_turn_break(res: Dictionary) -> String:
	var hp0 := int(duel.enemy_hp)
	var armor0 := int(duel.enemy_armor)
	duel._on_spin_pressed()
	var frames := 0
	while frames < 600:
		frames += 1
		if duel.reel_system.spinning:
			var r := _next_reel()
			if r >= 0 and not duel.reel_system.reel_stopped[r] and not duel.reel_system.is_absorbing(r):
				var strip: Array = duel.reel_system.reel_strips[r]
				if not strip.is_empty():
					var target := String(duel.readability.target_symbol_path)
					var idx := 0
					for i in range(strip.size()):
						if String(strip[i][0].resource_path) == target: idx = i; break
					duel.reel_system.reel_cursor[r] = idx
					duel.reel_system.lock_reel(r, false, "player")
		elif not duel._busy: break
		await get_tree().process_frame
	var armor1 := int(duel.enemy_armor)
	if int(res["break_turn"]) < 0 and armor0 > 0 and armor1 == 0:
		res["break_turn"] = int(res["turns"]) + 1
	var dmg := maxi(0, hp0 - int(duel.enemy_hp))
	res["hp_damage"] = int(res["hp_damage"]) + dmg
	(res["rows"] as Array).append({"turn": int(res["turns"]) + 1,
		"armor_before": armor0, "armor_after": armor1, "hp_damage": dmg})
	res["turns"] = int(res["turns"]) + 1
	return "OK"

# ============ mode pair：对子收益归因 ============
func _run_pair() -> Array:
	var out := []
	for prof in profiles:
		for run_seed in SEEDS:
			prof["_seed"] = run_seed
			_setup(prof)
			duel.start_room_data(_make_room(prof, "normal"), 0)
			await _wait(0.15)
			var res := {"profile": String(prof["name"]), "seed": run_seed, "mode": "pair",
				"has_pair_circuit": (duel.circuit_system != null and duel.circuit_system.equipped.has("circuit_pair")),
				"turns": 0, "rows": [], "terminal": "RUNNING",
				"pair_spin_count": 0, "pair_bonus_damage": 0, "triple_count": 0, "hp_damage": 0}
			var max_turns := int(prof.get("max_turns", 12))
			var frames := 0
			while frames < 20000 and int(res["turns"]) < max_turns:
				frames += 1
				if duel.game_state == DuelController.FlowState.LOST: res["terminal"] = "LOST"; break
				if duel.game_state == DuelController.FlowState.WON: res["terminal"] = "WON"; break
				if duel.game_state == DuelController.FlowState.PLAYING and not duel.in_loadout:
					var err := await _play_turn_pair(res)
					if err != "OK": res["terminal"] = err; break
				else: await get_tree().process_frame
			if res["terminal"] == "RUNNING": res["terminal"] = "TURN_LIMIT"
			res["ttk_turns"] = int(res["turns"])
			out.append(res)
			_write_json(OUT + "/pair_%s_%d.json" % [String(prof["name"]), run_seed], res)
			print("S2MEAS|pair|%s|%d|has_circuit=%s|pair_spins=%d|bonus=%d|triple=%d|ttk=%d" % [
				String(prof["name"]), run_seed, str(res["has_pair_circuit"]),
				int(res["pair_spin_count"]), int(res["pair_bonus_damage"]),
				int(res["triple_count"]), int(res["ttk_turns"])])
	return out

func _play_turn_pair(res: Dictionary) -> String:
	var hp0 := int(duel.enemy_hp)
	# 触发前电路 log 长度（用于识别本回合新增触发）
	var log0 := 0
	if duel.circuit_system != null: log0 = duel.circuit_system.log.size()
	duel._on_spin_pressed()
	var frames := 0
	while frames < 600:
		frames += 1
		if duel.reel_system.spinning:
			var r := _next_reel()
			if r >= 0 and not duel.reel_system.reel_stopped[r] and not duel.reel_system.is_absorbing(r):
				var strip: Array = duel.reel_system.reel_strips[r]
				if not strip.is_empty():
					# 对子主动策略：col 0/1 选目标伤害族，col 2 选不同族符号 → 制造"两同一异"落点
					var target := String(duel.readability.target_symbol_path)
					var idx := 0
					if r <= 1:
						for i in range(strip.size()):
							if String(strip[i][0].resource_path) == target: idx = i; break
					else:
						# 第三列选与目标不同的符号（任意 kind）
						for i in range(strip.size()):
							var s: Resource = strip[i][0]
							if s != null and String(s.resource_path) != target: idx = i; break
					duel.reel_system.reel_cursor[r] = idx
					duel.reel_system.lock_reel(r, false, "player")
		elif not duel._busy: break
		await get_tree().process_frame
	# 本回合对子触发次数（读取本回合新增 log）
	var pair_fired := 0
	if duel.circuit_system != null:
		for i in range(log0, duel.circuit_system.log.size()):
			if String(duel.circuit_system.log[i].get("id", "")) == "circuit_pair": pair_fired += 1
	var dmg := maxi(0, hp0 - int(duel.enemy_hp))
	var triple_this := bool(duel._last_triple)
	if pair_fired > 0:
		res["pair_spin_count"] = int(res["pair_spin_count"]) + 1
		# 观测值：对子 SPIN 的基础非三连伤害（含回路赔付），需与"无回路"对照分离出回路新增赔付
		res["pair_bonus_damage"] = int(res["pair_bonus_damage"]) + dmg
	if triple_this:
		res["triple_count"] = int(res["triple_count"]) + 1
	(res["rows"] as Array).append({"turn": int(res["turns"]) + 1,
		"pair_fired": pair_fired, "hp_damage": dmg, "triple": triple_this})
	res["turns"] = int(res["turns"]) + 1
	return "OK"

# ============ 公共辅助 ============
func _make_room(prof: Dictionary, kind: String) -> RoomData:
	var r := RoomData.new()
	r.name = "probe_" + kind
	r.hp = int(prof.get("hp", 350))
	r.atk = int(prof.get("atk", 20))
	r.armor = int(prof.get("armor", 0))
	r.element = String(prof.get("element", "none"))
	r.kind = kind
	r.act = int(prof.get("act", 1))
	return r

func _pick_index(strategy: String, strip: Array, col: int) -> int:
	var target := String(duel.readability.target_symbol_path)
	var fallback := 0
	for i in range(strip.size()):
		if String(strip[i][0].resource_path) == target: fallback = i; break
	if strategy == "defense" and duel.boss_atk_mult >= 1.5:
		for i in range(strip.size()):
			var s: Resource = strip[i][0]
			if s != null and String(s.get("kind")) == "shield": return i
	return fallback

func _next_reel() -> int:
	for r in range(duel.reel_system.reel_stopped.size()):
		if not duel.reel_system.reel_stopped[r] and not duel.reel_system.has_pending_stop(r): return r
	return -1

func _sum(rows: Array, field: String) -> int:
	var s := 0
	for r in rows: s += int(r.get(field, 0))
	return s

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify(data, "  "))
