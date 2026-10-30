extends Node

# ============================================================================
# M2-04 ACT1 样板平衡探针（headless，确定性种子）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/m2_balance_probe.tscn
#
# 五组对照（docs/统一落地执行计划.md M2-04）：
#   S0 无成长旧基线 / S1 只有角色成长 / S2 只有武器成长 / S3 完整成长（异元素双武器）
#   S4 完整成长（同元素双武器）
# 非上帝模式：承伤跨房保留，仅在剩余 HP < 40% 时自动使用一支回复药（bot 行为固定）。
# 只统计 ACT1（房 1–8）：首次成长出现房号、成长屏次数、选择数、房间回合数（TTK 代理）、承伤、死亡。
# 不可 headless 度量的项（停留时间、玩家能否复述成长方向）留给真人评测，见文档。
# 输出行前缀 M2BAL|，末尾 M2BAL|SUMMARY 为各组汇总。
# ============================================================================

const SCENARIOS := [
	{"id": "S0_no_growth", "pair": "ice", "growth": false, "mastery": false},
	{"id": "S1_char_only", "pair": "ice", "growth": true, "mastery": false},
	{"id": "S2_weapon_only", "pair": "ice", "growth": false, "mastery": true},
	{"id": "S3_full_diff", "pair": "ice", "growth": true, "mastery": true},
	{"id": "S4_full_same", "pair": "fire", "growth": true, "mastery": true},
	{"id": "S5_same_no_growth", "pair": "fire", "growth": false, "mastery": false},
]
const SEEDS := [1000, 1007, 1014, 1021, 1028, 1035, 1042, 1049, 1056, 1063, 1070, 1077, 1084, 1091, 1098, 1105, 1112, 1119, 1126, 1133, 1140, 1147, 1154, 1161, 1168, 1175, 1182, 1189, 1196, 1203, 1210, 1217, 1224, 1231, 1238, 1245, 1252, 1259, 1266, 1273]
const ACT1_ROOMS := 8
const TURN_BUDGET := 400
const HEAL_THRESHOLD := 0.4

var _fails := 0
var _checks := 0
var _agg := {}   # scenario id -> 累计
var _t0 := 0


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	_run()


func _run() -> void:
	await get_tree().process_frame
	for sc in SCENARIOS:
		_agg[sc["id"]] = {"runs": 0, "first_offer": [], "offers": [], "picks": [], "ttk": [], "dmg": [], "act1_clear": 0, "act1_death": 0, "death_rooms": []}
		for seed_v in SEEDS:
			await _one_run(sc, int(seed_v))
	_print_summary()
	print("---")
	print("M2BAL|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


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
	_setup_loadout(duel, String(sc["pair"]))
	var res := await _drive(duel, String(sc["id"]), seed_v)
	var a: Dictionary = _agg[sc["id"]]
	a["runs"] += 1
	a["first_offer"].append(res["first_offer"])
	a["offers"].append(res["offers"])
	a["picks"].append(res["picks"])
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


func _setup_loadout(duel: DuelController, pair: String) -> void:
	var want: Array = ["fire_sword", "ice_staff"] if pair == "ice" else ["fire_sword", "flame_staff"]
	var out: Array[String] = []
	for w in want:
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
	duel.selected_skills.clear()
	duel._confirm_loadout()


func _drive(duel: DuelController, sid: String, seed_v: int) -> Dictionary:
	var res := {"first_offer": -1, "offers": 0, "picks": 0, "ttk_sum": 0, "ttk_n": 0, "dmg_sum": 0,
		"act1_clear": false, "death_room": -1}
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
					var before: int = _growth_count(duel)
					_choose_growth(duel)
					if is_act1:
						res["picks"] += _growth_count(duel) - before
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


# 已习得成长项数（技艺 + 铭印次数），用于统计本次结算的选择数。
func _growth_count(duel: DuelController) -> int:
	var n: int = duel.growth.perk_ids.size()
	for path in duel.mastery.imprints:
		var im: Dictionary = duel.mastery.imprints[path]
		n += int(im["forge"]) + int(duel.mastery._tune_count(path))
	return n


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
	print("M2BAL|ROOM|%s|%d|%d|%s|%s|turns=%d|dmg=%d|hp=%d/%d|%s" % [sid, seed_v, duel.room_index + 1,
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
		var a: Dictionary = _agg[sc["id"]]
		var firsts := []
		for f in a["first_offer"]:
			if int(f) > 0:
				firsts.append(f)
		print("M2BAL|SUMMARY|%s|runs=%d|act1_clear=%d|act1_death=%d|death_rooms=%s|first_offer_mean=%.2f(n=%d)|offers_mean=%.2f|picks_mean=%.2f|ttk_mean=%.2f|dmg_per_room_mean=%.2f" % [
			sc["id"], int(a["runs"]), int(a["act1_clear"]), int(a["act1_death"]), str(a["death_rooms"]),
			_mean(firsts), firsts.size(), _mean(a["offers"]), _mean(a["picks"]), _mean(a["ttk"]), _mean(a["dmg"])])
	print("M2BAL|SUMMARY|note=选择率/停留时间需真人评测；本探针 bot 固定取首项")


# bot 策略（非真人，仅为让对照不被「瞬停」扭曲）：
# - 奖励：取首个非武器项（武器需替换弹层，bot 不处理）；全为武器则跳过。
# - 停轮：落在攻击 / 状态 / 回复 / 特殊符号上即停，或转满 40 跳强制停。
# - 成长：技艺优先坚韧（生存），铭印优先锋铸（攻击）；否则取首项。
# - 商店：不逛（未建模）。
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


func _choose_growth(duel: DuelController) -> void:
	var picked := {}
	for sec in duel.room_flow._offer_sections:
		var ch: Array = sec["choices"]
		var pick: String = String(ch[0]["id"])
		var want: String = "tough" if sec["key"] == "perk" else "forge"
		for c in ch:
			if String(c["id"]) == want:
				pick = want
		picked[sec["key"]] = pick
	duel.hud.hide_growth_picker()
	duel.room_flow._offer_sections = []
	duel.room_flow._apply_settlement(picked)


func _should_stop(duel: DuelController) -> bool:
	var rs = duel.reel_system
	if rs._spin_ticks >= 40:
		return true
	for r in range(DuelController.REELS):
		if not rs.reel_stopped[r]:
			var sym = duel.grid[r][0]
			return sym.kind in ["damage", "status", "heal", "special"]
	return true
