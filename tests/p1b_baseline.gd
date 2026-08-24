extends Node

# ============================================================================
# P1-B 平衡基线数据采集探针（场景入口；工程约束同 smoke_root——--script 模式编译不了 controller 链）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/p1b_baseline.tscn
#
# Part A 静态 ante 曲线：3 个种子各 _build_run 一局，逐房记录 hp/atk 缩放与绝对值；
#        同时输出 ATK 备选曲线（act 1.46→1.30 / room 1.10→1.06）对照列，供拍板。
# Part B 公平局遥测：仅神血（伤害原生）打完整局，逐房记录击杀回合数 / 承伤 / 金币。
# 输出行前缀 BASE|（CURVE/TELEMETRY/SUMMARY），供基线文档转录。
# ============================================================================

const GOD_HP := 1000000
const TURN_BUDGET := 400
const SEEDS := [7, 77, 777]

var _t0 := 0
var _fails := 0
var _checks := 0


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	_run()


func _run() -> void:
	await get_tree().process_frame
	var duel: DuelController = await _boot()
	if duel == null:
		print("BASE|RESULT FAIL (boot)")
		get_tree().quit(2)
		return

	await _part_a_static_curves(duel)
	await _part_b_fair_telemetry(duel)

	print("---")
	print("BASE|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_setup_loadout(duel)
	return duel


func _setup_loadout(duel: DuelController) -> void:
	duel.selected_loadout.assign(_pick_weapons(duel))
	duel.selected_consumables.clear()
	for want in ["heal_potion", "purify_potion"]:
		for p in duel.ITEM_POOL:
			if p.ends_with(want + ".tres"):
				duel.selected_consumables.append(p)
				break
	duel.selected_consumables.assign(duel.selected_consumables.slice(0, 2))
	duel.selected_charms.clear()
	if not duel.ITEM_POOL.is_empty():
		duel.selected_charms.append(duel.ITEM_POOL[0])
	duel.selected_skills.clear()
	if not duel.SKILL_POOL.is_empty():
		duel.selected_skills.append(duel.SKILL_POOL[0])
	duel._confirm_loadout()


func _pick_weapons(duel: DuelController) -> Array[String]:
	var out: Array[String] = []
	for want in ["fire_sword", "holy_sword"]:
		for p in duel.WEAPON_POOL:
			if p.ends_with(want + ".tres"):
				out.append(p)
				break
	return out


# ---------------------------------------------------------------- Part A

func _part_a_static_curves(duel: DuelController) -> void:
	print("BASE|CURVE|idx|act|kind|ria|hp_mult|atk_mult|hp_abs|atk_abs|armor|atk_alt_130_106")
	for seed_v in SEEDS:
		seed(int(seed_v))
		duel._reset_run_state()
		duel.ROOMS = duel._build_run()
		var n := duel.ROOMS.size()
		_check(n >= 25, "seed%d 房序列 ≥25（%d）" % [int(seed_v), n])
		var sum_by_act := {1: {"hp": [], "atk": []}, 2: {"hp": [], "atk": []}, 3: {"hp": [], "atk": []}}
		for idx in n:
			var r: RoomData = duel.ROOMS[idx]
			var s: Dictionary = duel._ante_scale(r, idx)
			var base_hp := float(r.hp if r.hp > 0 else (r.archetype.hp_base if r.archetype != null else 0))
			var base_atk := float(r.atk if r.atk > 0 else (r.archetype.atk_base if r.archetype != null else 0))
			var base_armor := int(r.armor if r.armor > 0 else (r.archetype.armor_base if r.archetype != null else 0))
			var hp_abs := int(round(base_hp * s["hp_scale"]))
			var atk_abs := int(round(base_atk * s["atk_scale"]))
			var atk_alt := int(round(base_atk * pow(1.30, r.act - 1) * pow(1.06, _ria_of(duel, idx))))
			sum_by_act[int(r.act)]["hp"].append(s["hp_scale"])
			sum_by_act[int(r.act)]["atk"].append(s["atk_scale"])
			if seed_v == SEEDS[0]:
				print("BASE|CURVE|%d|%d|%s|%d|%.3f|%.3f|%d|%d|%d|%d" % [
					idx + 1, r.act, r.kind, _ria_of(duel, idx), s["hp_scale"], s["atk_scale"],
					hp_abs, atk_abs, base_armor, atk_alt])
		for act in sum_by_act.keys():
			var hp_arr: Array = sum_by_act[act]["hp"]
			var atk_arr: Array = sum_by_act[act]["atk"]
			if hp_arr.is_empty():
				continue
			print("BASE|ACTMEAN|seed%d|act%d|hp_mean=%.2f|atk_mean=%.2f|hp_span=%.2f-%.2f" % [
				int(seed_v), int(act), _mean(hp_arr), _mean(atk_arr), hp_arr.min(), hp_arr.max()])


func _ria_of(duel: DuelController, idx: int) -> int:
	var a: int = duel.ROOMS[idx].act
	var ria := -1
	for i in idx + 1:
		if duel.ROOMS[i].act == a:
			ria += 1
	return ria


func _mean(arr: Array) -> float:
	var v := 0.0
	for x in arr:
		v += float(x)
	return v / maxf(1.0, float(arr.size()))


# ---------------------------------------------------------------- Part B

func _part_b_fair_telemetry(duel: DuelController) -> void:
	seed(303)
	_setup_loadout(duel)
	_god_hp(duel)
	var res := await _drive_run(duel)
	_check(res["terminal"] == "WON_GAME" or int(res["rooms_won"]) >= 24,
		"遥测局覆盖 ≥24 房（terminal=%s won=%d）" % [res["terminal"], int(res["rooms_won"])])


func _drive_run(duel: DuelController) -> Dictionary:
	var out := {"terminal": "NONE", "rooms_won": 0}
	var room_turns := 0
	var last_room := -999
	var just_won := false
	var dmg_taken_room := 0
	var last_hp := int(duel.player_hp)
	while not _deadline_hit():
		if duel.game_state == DuelController.FlowState.LOST:
			_print_telemetry(duel, room_turns, dmg_taken_room)
			duel._on_overlay_button_pressed()
			await get_tree().process_frame
			out["terminal"] = "LOST"
			break
		if duel.game_state == DuelController.FlowState.WON:
			if not just_won:
				out["rooms_won"] = duel.room_index + 1
				_print_telemetry(duel, room_turns, dmg_taken_room)
				duel._on_reward_skip_pressed()
				await get_tree().process_frame
				if duel.in_interroom:
					just_won = true
				elif duel._is_run_final(duel.room_index):
					out["terminal"] = "WON_GAME"
					break
				else:
					out["terminal"] = "BROKEN"
					break
			else:
				just_won = false
				duel._on_next_room_pressed()
				await get_tree().process_frame
				room_turns = 0
				dmg_taken_room = 0
				last_room = -999
				_god_hp(duel)
			continue
		if duel.in_interroom:
			out["terminal"] = "BROKEN"
			break
		if duel.room_index != last_room:
			last_room = duel.room_index
			room_turns = 0
			dmg_taken_room = 0
			last_hp = int(duel.player_hp)
		room_turns += 1
		if room_turns > TURN_BUDGET:
			_fail("遥测局回合超预算（房%d）" % (duel.room_index + 1))
			out["terminal"] = "STUCK"
			break
		_auto_consume(duel)
		var t: String = await _play_one_turn(duel)
		if t != "OK":
			out["terminal"] = t
			break
		if duel.game_state == DuelController.FlowState.PLAYING and duel.player_hp < last_hp:
			dmg_taken_room += last_hp - int(duel.player_hp)
		last_hp = int(duel.player_hp)
		duel.player_hp = GOD_HP if duel.game_state != DuelController.FlowState.PLAYING else mini(GOD_HP, maxi(duel.player_hp, GOD_HP / 2))   # 半血自动回满：专注 TTK 而非生存
	if _deadline_hit():
		out["terminal"] = "DEADLINE"
	return out


func _print_telemetry(duel: DuelController, turns: int, dmg: int) -> void:
	var outcome := "won" if duel.game_state == DuelController.FlowState.WON else ("lost" if duel.game_state == DuelController.FlowState.LOST else "?")
	print("BASE|TELEMETRY|%d|%s|%s|act%d|turns=%d|dmg_taken=%d|gold=%d%s" % [
		duel.room_index + 1, duel.enemy_name, duel.ROOMS[duel.room_index].kind,
		int(duel.ROOMS[duel.room_index].act), turns, dmg, int(duel.gold),
		"|peaceful" if duel.peaceful_win else ""])
	if outcome == "lost":
		print("BASE|TELEMETRY_NOTE|死亡于上述房间")


func _play_one_turn(duel: DuelController) -> String:
	duel._on_spin_pressed()
	while not _deadline_hit():
		if duel.reel_system.spinning:
			duel._on_spin_button_pressed()
		elif not duel._busy:
			return "OK"
		await get_tree().process_frame
	return "DEADLINE"


func _auto_consume(duel: DuelController) -> void:
	var interfered: bool = duel.pending_jam_reel >= 0 or duel.pending_lock_reel >= 0 \
		or duel.pending_chaos or duel.pending_auto_stop
	if interfered:
		for it in duel.consumable_slots:
			var item: Resource = load(it["path"])
			if item != null and item.effect == "purify":
				duel.consumable_system.use(it["uid"])
				return


func _god_hp(duel: DuelController) -> void:
	duel.player_hp_max = GOD_HP
	duel.player_hp = GOD_HP


# ---------------------------------------------------------------- 工具

func _deadline_hit() -> bool:
	return Time.get_ticks_msec() - _t0 > 300000


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("PASS  ", label)
	else:
		_fails += 1
		printerr("FAIL  ", label)


func _fail(label: String) -> void:
	_checks += 1
	_fails += 1
	printerr("FAIL  ", label)