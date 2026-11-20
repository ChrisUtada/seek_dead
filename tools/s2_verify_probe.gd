extends Node

# S2 三项验证探针（2026-11-21）：攻守穿透赔付 / 霜封定向凑牌 / 严格单变量破甲。
# 只采集不改玩法/武器/回路赔付/全局数值；通过探针子类捕获 acc（不改共享 CombatSystem）。
# 运行：Godot --headless --path . res://tools/s2_verify_probe.tscn -- --out=<dir> --mode=flow|frostsig|breakvar --profiles=<json> --seeds=111,333

# —— 探针 Combat 子类：捕获每次结算的 acc ——
class ProbeCombat extends CombatSystem:
	var probe_acc: Array = []
	func _apply_circuits(acc: Dictionary, counts: Dictionary) -> void:
		super._apply_circuits(acc, counts)
		var src_keys: Array = []
		for k in counts:
			var d: Array = counts[k]
			if d.size() > 3 and d[3] is Dictionary:
				for s in d[3]: src_keys.append(String(s))
		probe_acc.append({
			"diag_pierce_keys": (_ctrl._item_pierce_map.keys() if _ctrl._item_pierce_map is Dictionary else []),
			"diag_source_keys": src_keys,
			"shield": float(acc.get("shield", 0.0)),
			"shield_gain": int(acc.get("shield_gain", 0)),
			"pierce": float(acc.get("pierce", 0.0)),
			"dmg": float(acc.get("dmg", 0.0)),
			"total_damage": float(acc.get("total_damage", 0.0)),
			"pattern_equipment": String(acc.get("pattern_equipment", "")),
			"pattern_signature": String(acc.get("pattern_signature", "")),
			"pattern_match_ids": _ids_of(acc.get("pattern_match", {})),
			"triple": bool(acc.get("triple", false)),
			"armor_broken": bool(acc.get("armor_broken", false)),
			"lines": _filter_lines(acc.get("lines", [])),
		})
	func _ids_of(m: Variant) -> Array:
		var out: Array = []
		if not (m is Dictionary): return out
		var pats: Variant = m.get("patterns", [])
		if pats is Array:
			for p in pats:
				if p is Dictionary: out.append(String(p.get("id", "")))
				elif p != null and "id" in p: out.append(String(p.id))
		return out
	func _filter_lines(lines: Variant) -> Array:
		var out: Array = []
		if lines is Array:
			for l in lines:
				var s := String(l)
				if s.contains("回路") or s.contains("穿透") or s.contains("牌谱") or s.contains("攻守"):
					out.append(s)
		return out

var OUT := "user://runs/s2_verify"
var MODE := "flow"
var SEEDS := [111, 333, 555]
var profiles: Array = []
var duel: DuelController
var combat_probe: ProbeCombat

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
	Engine.time_scale = 40.0
	duel = load("res://scenes/duel/duel.tscn").instantiate() as DuelController
	duel.demo_config.enabled = false; duel.demo_config.act_only = false
	add_child(duel)
	await _wait(0.35)
	# 替换 combat 为探针子类（捕获 acc）
	combat_probe = ProbeCombat.new(duel)
	duel.combat = combat_probe
	var all := []
	match MODE:
		"flow": all = await _run_flow()
		"frostsig": all = await _run_frostsig()
		"breakvar": all = await _run_breakvar()
		_: print("S2VER|UNKNOWN " + MODE)
	_write_json(OUT + "/summary_" + MODE + ".json", {"generated_at": Time.get_datetime_string_from_system(),
		"mode": MODE, "seeds": SEEDS, "note": "三项验证：只采集不调参", "runs": all})
	print("S2VER|RESULT_OK mode=%s runs=%d" % [MODE, all.size()])
	get_tree().quit(0)

func _setup(prof: Dictionary) -> void:
	seed(int(prof.get("_seed", 111)))
	duel._reset_run_state()
	combat_probe.probe_acc.clear()
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

func _run_turn(target: String, col2_diff: bool = false) -> void:
	duel._on_spin_pressed()
	var frames := 0
	while frames < 600:
		frames += 1
		if duel.reel_system.spinning:
			var r := _next_reel()
			if r >= 0 and not duel.reel_system.reel_stopped[r] and not duel.reel_system.is_absorbing(r):
				var strip: Array = duel.reel_system.reel_strips[r]
				if not strip.is_empty():
					var idx := 0
					for i in range(strip.size()):
						if target != "" and String(strip[i][0].resource_path) == target: idx = i; break
					if col2_diff and r == 2:
						for i in range(strip.size()):
							var s: Resource = strip[i][0]
							if s != null and String(s.resource_path) != target: idx = i; break
					duel.reel_system.reel_cursor[r] = idx
					duel.reel_system.lock_reel(r, false, "player")
		elif not duel._busy: break
		await get_tree().process_frame

func _next_reel() -> int:
	for r in range(duel.reel_system.reel_stopped.size()):
		if not duel.reel_system.reel_stopped[r] and not duel.reel_system.has_pending_stop(r): return r
	return -1

func _make_room(prof: Dictionary, kind: String) -> RoomData:
	var r := RoomData.new()
	r.name = "verify_" + kind
	r.hp = int(prof.get("hp", 350)); r.atk = int(prof.get("atk", 18))
	r.armor = int(prof.get("armor", 0)); r.element = String(prof.get("element", "none"))
	r.kind = kind; r.act = int(prof.get("act", 1))
	return r

# ============ mode flow：攻守转换穿透赔付 ============
func _run_flow() -> Array:
	var out := []
	for prof in profiles:
		for run_seed in SEEDS:
			prof["_seed"] = run_seed
			_setup(prof)
			duel.start_room_data(_make_room(prof, "normal"), 0)
			await _wait(0.15)
			var res := {"profile": String(prof["name"]), "seed": run_seed, "mode": "flow",
				"has_circuit": (duel.circuit_system != null and duel.circuit_system.equipped.has("circuit_damage_shield")),
				"spins": [], "terminal": "RUNNING"}
			var max_turns := int(prof.get("max_turns", 8))
			for t in range(max_turns):
				var hp0 := int(duel.enemy_hp)
				var armor0 := int(duel.enemy_armor)
				await _run_turn(String(duel.readability.target_symbol_path))
				var accs = combat_probe.probe_acc.duplicate()
				if not accs.is_empty():
					var a: Dictionary = accs[-1]
					(res["spins"] as Array).append({
						"turn": t + 1, "shield": a.get("shield"), "shield_gain": a.get("shield_gain"),
						"pierce": a.get("pierce"), "dmg": a.get("dmg"), "lines": a.get("lines"),
						"hp_before": hp0, "hp_after": int(duel.enemy_hp),
						"armor_before": armor0, "armor_after": int(duel.enemy_armor)})
				if duel.game_state != DuelController.FlowState.PLAYING: break
			res["terminal"] = "WON" if duel.game_state == DuelController.FlowState.WON else ("LOST" if duel.game_state == DuelController.FlowState.LOST else "TURN_LIMIT")
			out.append(res)
			_write_json(OUT + "/flow_%s_%d.json" % [String(prof["name"]), run_seed], res)
			var pierce_sum := 0.0
			for sp in res["spins"]: pierce_sum += float(sp.get("pierce", 0.0))
			print("S2VER|flow|%s|%d|circuit=%s|spins=%d|pierce_sum=%.1f|lines_has_damage_shield=%s" % [
				String(prof["name"]), run_seed, str(res["has_circuit"]), (res["spins"] as Array).size(),
				pierce_sum, str(_any_line(res["spins"], "攻守"))])
	return out

func _any_line(spins: Array, needle: String) -> bool:
	for sp in spins:
		for l in sp.get("lines", []):
			if String(l).contains(needle): return true
	return false

# ============ mode frostsig：霜封签名四阶段 ============
func _run_frostsig() -> Array:
	var out := []
	for prof in profiles:
		for run_seed in SEEDS:
			prof["_seed"] = run_seed
			_setup(prof)
			duel.start_room_data(_make_room(prof, prof.get("room_kind", "elite")), 0)
			await _wait(0.15)
			var res := {"profile": String(prof["name"]), "seed": run_seed, "mode": "frostsig",
				"spins": [], "phase_count": {"no_combo": 0, "base_hit_no_sig": 0, "sig_no_threshold": 0, "frost_seal_fired": 0},
				"terminal": "RUNNING"}
			var max_turns := int(prof.get("max_turns", 12))
			for t in range(max_turns):
				var frost_before := int(duel.enemy_status.get("frost", 0)) if duel.enemy_status is Dictionary else 0
				await _run_turn_seek(String(duel.readability.target_symbol_path), frost_before)
				var accs = combat_probe.probe_acc.duplicate()
				if not accs.is_empty():
					var a: Dictionary = accs[-1]
					var frost_after := int(duel.enemy_status.get("frost", 0)) if duel.enemy_status is Dictionary else 0
					var pat_match: Array = a.get("pattern_match_ids", [])
					var base_hit := pat_match.has("W02") or String(a.get("pattern_equipment", "")).begins_with("W02")
					var sig := String(a.get("pattern_signature", ""))
					var seal_fired := float(duel._pattern_enemy_atk_mult) < 1.0
					var phase := "no_combo"
					if seal_fired: phase = "frost_seal_fired"
					elif base_hit and sig == "": phase = "base_hit_no_sig"
					elif base_hit and sig != "": phase = "sig_no_threshold"
					res["phase_count"][phase] = int(res["phase_count"][phase]) + 1
					(res["spins"] as Array).append({"turn": t + 1,
						"frost_before": frost_before, "frost_after": frost_after,
						"pattern_match": pat_match, "pattern_equipment": a.get("pattern_equipment"),
						"pattern_signature": sig, "seal_fired": seal_fired,
						"pattern_atk_mult": float(duel._pattern_enemy_atk_mult), "phase": phase})
				if duel.game_state != DuelController.FlowState.PLAYING: break
			res["terminal"] = "WON" if duel.game_state == DuelController.FlowState.WON else ("LOST" if duel.game_state == DuelController.FlowState.LOST else "TURN_LIMIT")
			out.append(res)
			_write_json(OUT + "/frostsig_%s_%d.json" % [String(prof["name"]), run_seed], res)
			print("S2VER|frostsig|%s|%d|phases=%s|terminal=%s" % [
				String(prof["name"]), run_seed, str(res["phase_count"]), str(res["terminal"])])
	return out

# frost_pattern_seek：主动凑 W02 完整牌型 frost + ice damage + weapon 来源。
# 三列分工：col0 选 frost 状态符号，col1 选 ice damage 符号，col2 任意（武器来源）。
func _run_turn_seek(target: String, frost_before: int) -> void:
	duel._on_spin_pressed()
	var frames := 0
	while frames < 600:
		frames += 1
		if duel.reel_system.spinning:
			var r := _next_reel()
			if r >= 0 and not duel.reel_system.reel_stopped[r] and not duel.reel_system.is_absorbing(r):
				var strip: Array = duel.reel_system.reel_strips[r]
				if not strip.is_empty():
					var idx := 0
					for i in range(strip.size()):
						if String(strip[i][0].resource_path) == target: idx = i; break
					# W02 牌型分工：col0=frost，col1=ice damage，col2=任意
					if r == 0:
						for i in range(strip.size()):
							var s: Resource = strip[i][0]
							if s != null and String(s.get("status_type")) == "frost": idx = i; break
					elif r == 1:
						for i in range(strip.size()):
							var s: Resource = strip[i][0]
							if s != null and String(s.get("kind")) == "damage" and String(s.get("element")) == "ice": idx = i; break
					duel.reel_system.reel_cursor[r] = idx
					duel.reel_system.lock_reel(r, false, "player")
		elif not duel._busy: break
		await get_tree().process_frame

# ============ mode breakvar：严格单变量破甲对照（运行时 _item_pierce_map 开关） ============
func _run_breakvar() -> Array:
	var out := []
	for prof in profiles:
		for run_seed in SEEDS:
			prof["_seed"] = run_seed
			_setup(prof)
			duel.start_room_data(_make_room(prof, "normal"), 0)
			await _wait(0.15)
			# 单变量：start_room_data 会按 WeaponData 重建 pierce_map，必须在其后覆盖。
			# 仅切 pierce_map（不修改共享 WeaponData）。同时清掉 HEAVY 兜底来源，确保唯一差异是 pierce。
			var pierce_on := bool(prof.get("pierce_on", true))
			var sym_path := String(prof.get("pierce_symbol_path", ""))
			duel._item_pierce_map.clear()
			duel._source_archetype_map.clear()   # 消除重武器三连破甲兜底
			if sym_path != "" and pierce_on:
				# 符号来源于武器，pierce_map 的 key 是 source_key(sym, weapon_path)
				duel._item_pierce_map[sym_path] = true
				duel._item_pierce_at[sym_path] = 3
				for wp2 in duel.selected_loadout:
					# grid_src 存的是武器 basename（如 "ice_gun"），非完整路径
					var src_id := String(wp2).get_file().get_basename()
					var k := ReelSystem.source_key(sym_path, src_id)
					duel._item_pierce_map[k] = true
					duel._item_pierce_at[k] = 3
			var res := {"profile": String(prof["name"]), "seed": run_seed, "mode": "breakvar",
				"pierce_on": pierce_on, "actual_armor": int(duel.enemy_armor),
				"spins": [], "terminal": "RUNNING"}
			var max_turns := int(prof.get("max_turns", 8))
			for t in range(max_turns):
				var armor0 := int(duel.enemy_armor)
				await _run_turn(String(duel.readability.target_symbol_path))
				var accs = combat_probe.probe_acc.duplicate()
				if not accs.is_empty():
					var a: Dictionary = accs[-1]
					(res["spins"] as Array).append({"turn": t + 1,
						"armor_before": armor0, "armor_after": int(duel.enemy_armor),
						"armor_broken": a.get("armor_broken"), "triple": a.get("triple"),
						"dmg": a.get("dmg"), "pierce": a.get("pierce"), "hp_after": int(duel.enemy_hp),
						"diag_pierce_keys": a.get("diag_pierce_keys"), "diag_source_keys": a.get("diag_source_keys")})
				if duel.game_state != DuelController.FlowState.PLAYING: break
			res["terminal"] = "WON" if duel.game_state == DuelController.FlowState.WON else ("LOST" if duel.game_state == DuelController.FlowState.LOST else "TURN_LIMIT")
			res["ttk_turns"] = len(res["spins"])
			out.append(res)
			_write_json(OUT + "/breakvar_%s_%d.json" % [String(prof["name"]), run_seed], res)
			var broken := false
			for sp in res["spins"]:
				if bool(sp.get("armor_broken")): broken = true
			print("S2VER|breakvar|%s|%d|pierce=%s|armor=%d|broken=%s|ttk=%d" % [
				String(prof["name"]), run_seed, str(pierce_on), int(res["actual_armor"]),
				str(broken), int(res["ttk_turns"])])
	return out

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify(data, "  "))
