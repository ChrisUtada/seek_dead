extends Node

# ============================================================================
# P0 · 成长对照组战斗基线探针（docs/转轮目押_成长与减带优化_执行方案.md §10 P0）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/p0_growth_baseline.tscn
# 单组复跑：在命令末尾加 -- --only=G3_buff3（不要把参数放在 -- 之前）。
#
# 四组对照（同一配装、同一 40 种子、同一 ACT1 8 房）：
#   G0 无成长 / G1 仅锋铸 / G2 仅调律 / G3 技能 Buff（haste+rage+calm，无成长）
# 配装固定为异元素双武器 fire_sword + ice_staff，腰带 2 支基础治疗药剂。
# bot 行为与 m2_balance_probe 一致：任何有效符号（含 buff）即停；低血自动喝药；奖励跳过武器。
# 目的不是预测真人，而是固定「成长类型」这一变量，给 P1/P2 提供同口径对照。
# 输出行前缀 P0GROW|，末尾 P0GROW|SUMMARY 为四组汇总。
# ============================================================================

const SCENARIOS := [
	{"id": "G0_no_growth", "growth": false, "mastery": false, "skills": [], "imprint": ""},
	{"id": "G1_forge",     "growth": false, "mastery": true,  "skills": [], "imprint": "forge"},
	{"id": "G2_tune",      "growth": false, "mastery": true,  "skills": [], "imprint": "tune"},
	{"id": "G3_buff3",     "growth": false, "mastery": false, "skills": ["haste", "rage", "calm"], "imprint": ""},
]
const SEEDS := [1000, 1007, 1014, 1021, 1028, 1035, 1042, 1049, 1056, 1063, 1070, 1077, 1084, 1091, 1098, 1105, 1112, 1119, 1126, 1133, 1140, 1147, 1154, 1161, 1168, 1175, 1182, 1189, 1196, 1203, 1210, 1217, 1224, 1231, 1238, 1245, 1252, 1259, 1266, 1273]
const ACT1_ROOMS := 8
const TURN_BUDGET := 400
const HEAL_THRESHOLD := 0.4
const WEAPONS := ["fire_sword", "ice_staff"]
const SKILL_DIR := "res://resources/skills/"

var _fails := 0
var _checks := 0
var _agg := {}   # scenario id -> 累计
var _t0 := 0
var _save_backup := {}
var _have_save_backup := false
var _only := ""   # --only=G3_buff3 可只跑单组（复跑 Buff 组时用）


func _ready() -> void:
	# 探针只读战斗，但奖励/铁砧会经 MetaStore 落盘；先快照 lobby 数据，结束后原样还原。
	_save_backup = SaveSystem.load_lobby_data().duplicate(true)
	_have_save_backup = true
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--only="):
			_only = String(a).trim_prefix("--only=")
	_t0 = Time.get_ticks_msec()
	_run()


func _run() -> void:
	await get_tree().process_frame
	for sc in SCENARIOS:
		if _only != "" and String(sc["id"]) != _only:
			continue
		_agg[sc["id"]] = {"runs": 0, "first_offer": [], "offers": [], "picks": [],
			"forge": [], "tune": [], "ttk": [], "dmg": [], "act1_clear": 0,
			"act1_death": 0, "death_rooms": []}
		for seed_v in SEEDS:
			await _one_run(sc, int(seed_v))
	_print_summary()
	_restore_save()
	print("---")
	print("P0GROW|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _restore_save() -> void:
	if not _have_save_backup:
		return
	SaveSystem.save_lobby_data(_save_backup)
	SaveSystem.flush_lobby_data()


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	return duel


func _one_run(sc: Dictionary, seed_v: int) -> void:
	seed(seed_v)
	var duel: DuelController = await _boot()
	duel.growth.enabled = bool(sc["growth"])
	duel.mastery.enabled = bool(sc["mastery"])
	_setup_loadout(duel, sc["skills"])
	var res := await _drive(duel, String(sc["id"]), seed_v, String(sc["imprint"]))
	var a: Dictionary = _agg[sc["id"]]
	a["runs"] += 1
	a["first_offer"].append(res["first_offer"])
	a["offers"].append(res["offers"])
	a["picks"].append(res["picks"])
	a["forge"].append(res["forge"])
	a["tune"].append(res["tune"])
	if res["ttk_n"] > 0:
		a["ttk"].append(float(res["ttk_sum"]) / float(res["ttk_n"]))
		a["dmg"].append(float(res["dmg_sum"]) / float(res["ttk_n"]))
	if res["act1_clear"]:
		a["act1_clear"] += 1
	if res["death_room"] >= 0 and res["death_room"] < ACT1_ROOMS:
		a["act1_death"] += 1
		a["death_rooms"].append(res["death_room"] + 1)
	duel.queue_free()
	await get_tree().process_frame


func _setup_loadout(duel: DuelController, skills: Array) -> void:
	var out: Array[String] = []
	for w in WEAPONS:
		for p in duel.WEAPON_POOL:
			if p.ends_with(w + ".tres"):
				out.append(p)
				break
	duel.selected_loadout.assign(out)
	duel.selected_consumables.clear()
	for p in duel.ITEM_POOL:
		if p.ends_with("heal_potion.tres"):
			duel.selected_consumables.append(p)
			duel.selected_consumables.append(p)
			break
	duel.selected_charms.clear()
	var sk: Array[String] = []
	for s in skills:
		sk.append(SKILL_DIR + String(s) + ".tres")
	duel.selected_skills.assign(sk)
	if sk.size() > duel.skill_max:
		duel.skill_max = sk.size()   # 对照组允许一次带满 3 技能（正式局需商店开槽）
	duel._confirm_loadout()


func _drive(duel: DuelController, sid: String, seed_v: int, imprint: String) -> Dictionary:
	var res := {"first_offer": -1, "offers": 0, "picks": 0, "forge": 0, "tune": 0,
		"ttk_sum": 0, "ttk_n": 0, "dmg_sum": 0, "act1_clear": false, "death_room": -1}
	var room_turns := 0
	var last_room := -999
	var dmg_room := 0
	var last_hp := int(duel.player_hp)
	var just_won := false
	while Time.get_ticks_msec() - _t0 < 3000000:
		if duel.game_state == DuelController.FlowState.LOST:
			res["death_room"] = duel.room_index
			_log_room(sid, seed_v, duel, room_turns, dmg_room, "lost")
			break
		if duel.game_state == DuelController.FlowState.WON:
			if not just_won:
				var idx: int = duel.room_index
				var is_act1: bool = int(duel.ROOMS[idx].act) == 1
				if is_act1:
					res["ttk_sum"] += room_turns
					res["ttk_n"] += 1
					res["dmg_sum"] += dmg_room
				_log_room(sid, seed_v, duel, room_turns, dmg_room, "won")
				_take_reward(duel)
				await get_tree().process_frame
				if duel.room_flow.growth_pick_pending():
					if is_act1:
						res["offers"] += 1
						if res["first_offer"] < 0:
							res["first_offer"] = idx + 1
					var before: Dictionary = _imprint_counts(duel)
					_choose_growth(duel, imprint)
					var after: Dictionary = _imprint_counts(duel)
					res["forge"] += int(after["forge"]) - int(before["forge"])
					res["tune"] += int(after["tune"]) - int(before["tune"])
					res["picks"] += int(after["forge"]) - int(before["forge"]) + int(after["tune"]) - int(before["tune"])
				if idx + 1 >= ACT1_ROOMS:
					res["act1_clear"] = true
					break
				if duel.in_interroom:
					just_won = true
				else:
					break
			else:
				just_won = false
				duel._on_next_room_pressed()
				await get_tree().process_frame
				room_turns = 0
				dmg_room = 0
				last_room = -999
			continue
		if duel.in_interroom:
			break
		if duel.room_index != last_room:
			last_room = duel.room_index
			room_turns = 0
			dmg_room = 0
			last_hp = int(duel.player_hp)
		room_turns += 1
		if room_turns > TURN_BUDGET:
			break
		_auto_heal(duel)
		await _play_one_turn(duel)
		if duel.game_state == DuelController.FlowState.PLAYING and duel.player_hp < last_hp:
			dmg_room += last_hp - int(duel.player_hp)
		last_hp = int(duel.player_hp)
	return res


func _imprint_counts(duel: DuelController) -> Dictionary:
	var forge := 0
	var tune := 0
	for path in duel.mastery.imprints:
		var im: Dictionary = duel.mastery.imprints[path]
		forge += int(im["forge"])
		tune += int(duel.mastery._tune_count(path))
	return {"forge": forge, "tune": tune}


func _auto_heal(duel: DuelController) -> void:
	if float(duel.player_hp) >= HEAL_THRESHOLD * float(duel.player_hp_max):
		return
	for it in duel.consumable_slots:
		var item: Resource = load(it["path"])
		if item != null and item.effect == "heal":
			duel.consumable_system.use(it["uid"])
			return


func _play_one_turn(duel: DuelController) -> void:
	duel._on_spin_pressed()
	while Time.get_ticks_msec() - _t0 < 3000000:
		if duel.reel_system.spinning:
			if _should_stop(duel):
				duel._on_spin_button_pressed()
		elif not duel._busy:
			return
		await get_tree().process_frame


func _log_room(sid: String, seed_v: int, duel: DuelController, turns: int, dmg: int, outcome: String) -> void:
	var r = duel.ROOMS[duel.room_index]
	if int(r.act) != 1:
		return
	print("P0GROW|ROOM|%s|%d|%d|%s|%s|turns=%d|dmg=%d|hp=%d/%d|%s" % [sid, seed_v, duel.room_index + 1,
		r.kind, duel.enemy_name, turns, dmg, int(duel.player_hp), int(duel.player_hp_max), outcome])


func _mean(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var s := 0.0
	for v in arr:
		s += float(v)
	return s / float(arr.size())


func _print_summary() -> void:
	for sc in SCENARIOS:
		if not _agg.has(sc["id"]):
			continue
		var a: Dictionary = _agg[sc["id"]]
		var firsts := []
		for f in a["first_offer"]:
			if int(f) > 0:
				firsts.append(f)
		print("P0GROW|SUMMARY|%s|runs=%d|act1_clear=%d|act1_death=%d|death_rooms=%s|first_offer_mean=%.2f(n=%d)|offers_mean=%.2f|picks_mean=%.2f|forge_mean=%.2f|tune_mean=%.2f|ttk_mean=%.2f|dmg_per_room_mean=%.2f" % [
			sc["id"], int(a["runs"]), int(a["act1_clear"]), int(a["act1_death"]), str(a["death_rooms"]),
			_mean(firsts), firsts.size(), _mean(a["offers"]), _mean(a["picks"]),
			_mean(a["forge"]), _mean(a["tune"]), _mean(a["ttk"]), _mean(a["dmg"])])
	print("P0GROW|SUMMARY|note=bot 固定任何有效符号即停；仅用于成长类型对照，不代表真人停中率")


# 成长选择：按对照组只取指定铭印；拿不到就跳过该组（不混入另一类成长）。
# 技艺（growth）在本探针全部关闭，不处理 perk。
func _choose_growth(duel: DuelController, imprint: String) -> void:
	var picked := {}
	for sec in duel.room_flow._offer_sections:
		if String(sec["key"]) == "perk":
			continue
		for c in sec["choices"]:
			if String(c["id"]) == imprint:
				picked[sec["key"]] = imprint
				break
	duel.hud.hide_growth_picker()
	duel.room_flow._offer_sections = []
	duel.room_flow._apply_settlement(picked)


func _take_reward(duel: DuelController) -> void:
	if duel.reward_is_boss:
		for c in duel.reward_choices:
			if String(c.get("kind", "")) != "boss_weapon":
				duel._on_boss_reward_chosen(c)
				return
	else:
		for i in range(duel.reward_choices.size()):
			var rw = duel.reward_choices[i]
			if String(rw.id) != "weapon":
				duel._on_reward_chosen(String(rw.id), i)
				return
	duel._on_reward_skip_pressed()


func _should_stop(duel: DuelController) -> bool:
	var rs = duel.reel_system
	if rs._spin_ticks >= 40:
		return true
	for r in range(DuelController.REELS):
		if not rs.reel_stopped[r]:
			var sym = duel.grid[r][0]
			# 必须包含 buff：否则技能 Buff 符号永远不会落地，G3 会退化成纯稀释组。
			return sym.kind in ["damage", "status", "heal", "special", "buff"]
	return true
