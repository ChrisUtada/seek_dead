extends Node

# ============================================================================
# 全怪物个性机制 · Step 6 · 对策有效性与无装备可通关 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/counterplay_test.tscn
#
# 依据：docs/全怪物个性机制设计与制作计划_2026-11-12.md Step 6 出口 / §11 第 5、6 条
#   §11-5「至少两种应对真实有效」；§11-6「无净化/特定装备时仍能完成战斗」
#   Step 6 出口「装备提供选择而非门票；玩家没有特定装备也能完成；新机制没有制造新的单一最优解」
#
# 覆盖：
#   A. 9 个玩家侧减益：效果真实生效 / 文案 ≥2 条应对 / 装备通道真实解除 /
#      无装备通道（自动到期、破甲、换符号、按序停列、重新积累）真实解除或恢复；
#   B. 4 类转轮干扰意图：可净化 + 净化药剂真实抵消；不净化时意图生效但一回合仍能推进；
#   C. 61 个房间全量：无消耗品 / 无护符 / 无技能的基础 Build 逐房跑到 WON（不软锁）；
#   D. 代表房双 Build：无装备 Build 与带对策装备 Build 都能通关，装备不成为唯一最优解。
#
# 纪律：本测试只验证既有实现的应对通道，不改任何产品代码、资源或平衡数值。
#       GOD_HP 只作用于测试实例，用于把判定聚焦在「是否因缺装备被软锁」而非随机死亡。
# ============================================================================

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const PURIFY_POTION := "res://resources/consumables/purify_potion.tres"
const CLEANSE_POTION := "res://resources/consumables/cleanse_potion.tres"
const SEED := 20261114
const GOD_HP := 1000000
const ROOM_TURN_BUDGET := 400
const TURN_FRAME_GUARD := 900
const INTERFERENCE_INTENTS := ["jam", "lock", "chaos", "auto_stop"]
const DUAL_BUILD_ROOMS := ["窃语咒师", "腐化史莱姆", "勇者的阴影"]

var _checks := 0
var _fails := 0
var _duel: DuelController
var _save_backup := {}
var _have_save := false
var _meta_backup := {}
var _room_results: Array[String] = []


func _ready() -> void:
	_save_backup = SaveSystem.load_lobby_data().duplicate(true)
	_have_save = true
	seed(SEED)
	await _run()
	_restore_save()
	print("---")
	print("COUNTER|RESULT %s (checks=%d fails=%d)"
		% ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	await _frames(2)
	_duel = await _boot()
	if _duel == null:
		print("COUNTER|RESULT FAIL (boot)")
		get_tree().quit(2)
		return
	_meta_backup = _duel.meta.duplicate(true)

	var t0 := Time.get_ticks_msec()
	_test_debuff_counterplay()
	_section("debuff_counterplay", t0)
	t0 = Time.get_ticks_msec()
	await _test_interference_counterplay()
	_section("interference_counterplay", t0)
	t0 = Time.get_ticks_msec()
	await _test_bare_build_all_rooms()
	_section("bare_build_all_rooms", t0)
	t0 = Time.get_ticks_msec()
	await _test_dual_builds()
	_section("dual_builds", t0)

	_duel.meta.clear()
	for k in _meta_backup:
		_duel.meta[k] = _meta_backup[k]
	_duel._meta_store.save_meta()


func _boot() -> DuelController:
	var scene_res: PackedScene = load(DUEL_SCENE)
	if scene_res == null:
		return null
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await _frames(3)
	duel.board_config.enabled = false
	_bare_build(duel)
	return duel


# 无装备 Build：只有两把基础武器，腰带 / 护符 / 技能全空。
func _bare_build(duel: DuelController) -> void:
	var weapons: Array[String] = []
	for w in ["fire_sword", "holy_sword"]:
		for p in duel.WEAPON_POOL:
			if String(p).ends_with(w + ".tres"):
				weapons.append(String(p))
				break
	duel.selected_loadout.assign(weapons)
	duel.selected_consumables.clear()
	duel.selected_charms.clear()
	duel.selected_skills.clear()
	duel._confirm_loadout()


func _equipped_build(duel: DuelController) -> void:
	_bare_build(duel)
	duel.selected_consumables.assign([PURIFY_POTION, CLEANSE_POTION])
	duel.selected_charms.assign([
		"res://resources/charms/resist_charm.tres",
		"res://resources/charms/guard_charm.tres"])
	duel._confirm_loadout()


# ---------------------------------------------------------------------------
# A. 9 个玩家侧减益 · 双通道应对
# ---------------------------------------------------------------------------

func _test_debuff_counterplay() -> void:
	for id in _duel.debuffs.DEFS.keys():
		var def: Dictionary = _duel.debuffs.DEFS[id]
		var kind := String(def.get("kind", "status"))
		var nm := String(def.get("name", id))
		var counters: PackedStringArray = String(def.get("counter", "")).split(" / ")

		# ① 效果真实生效（不是只写文案）
		_arm(id)
		_check(_effect_active(id), "「%s」施加后效果真实生效" % nm)
		_check(counters.size() >= 2, "「%s」登记 ≥2 条应对（%d 条）" % [nm, counters.size()])
		var free_text := false
		for c in counters:
			if not (String(c).contains("药剂") or String(c).contains("护符")):
				free_text = true
				break
		_check(free_text, "「%s」至少一条应对不依赖装备" % nm)

		# ② 通道一：装备（清净 / 净化药剂）或一次性效果的资源恢复
		_arm(id)
		if kind == "status":
			_duel.consumable_system.use_cleanse(load(CLEANSE_POTION))
			_check(not _duel.debuffs.has(id), "「%s」清净药剂通道解除" % nm)
			_check(not _effect_active(id), "「%s」清净后效果倍率/状态恢复" % nm)
		elif kind == "interference":
			_duel.consumable_system.use_purify(load(PURIFY_POTION))
			_check(not _duel.debuffs.has(id), "「%s」净化药剂通道解除" % nm)
			_check(not _effect_active(id), "「%s」净化后操作限制恢复" % nm)
		else:
			_rebuild_resource(id)
			_check(_effect_recovered(id), "「%s」一次性效果可重新积累/重新获得" % nm)

		# ③ 通道二：不带任何装备的应对（自动到期 / 破甲 / 换符号 / 按序停列 / 不残留）
		_arm(id)
		if kind == "instant":
			_check(not _duel.debuffs.has(id), "「%s」一次性效果不进入计时表" % nm)
			_duel.debuffs.tick_turn_end(_duel)
			_check(not _duel.debuffs.has(id), "「%s」跨回合不残留（无装备可继续）" % nm)
		else:
			var ok := _free_counter(id)
			_check(ok, "「%s」无装备通道解除/规避生效" % nm)
			_check(not _duel.debuffs.has(id), "「%s」无装备通道后不再处于减益中" % nm)
			_check(not _effect_active(id), "「%s」无装备通道后效果确实失效" % nm)

		# ④ 缠绕专属：按序停列是真实可执行的非装备应对
		if id == "entangle":
			_arm("entangle")
			var rs = _duel.reel_system
			rs.begin_spin()
			rs._timer.stop()
			var next_col: int = _duel.debuffs.entangle_next(rs)
			_check(next_col >= 0 and next_col < _duel.REELS,
				"缠绕：按序停列返回合法列（第 %d 列）" % (next_col + 1))
			rs.finish_spin()


# 每个用例前把战斗状态收回到可预测基线（沿用 step1_module_test 的 _fresh 口径）。
func _fresh() -> void:
	if _duel.debuffs != null:
		_duel.debuffs.reset()
	_duel.player_buffs.clear()
	_duel.player_shield = 0
	_duel.player_hp_max = 1000
	_duel.player_hp = 1000
	_duel.player_frost = 0
	_duel.player_status = {}
	_duel.enemy_armor = 0
	_duel.enemy_armor_max = 0
	_duel.enemy_hp_max = 10000
	_duel.enemy_hp = 10000
	_duel.charge_points = 0
	_duel.current_gimmick = null
	_duel.enemy_stunned = 0
	_duel.turn_resolved = false
	_duel.turn_count = 3
	_duel.charm_damage_mult = 1.0


func _arm(id: String) -> void:
	_fresh()
	if id == "drain":
		_duel.charge_points = 5
	elif id == "strip":
		_add_test_buff()
	_duel.apply_debuff(id)


func _add_test_buff() -> void:
	var sym := SymbolData.new()
	sym.label = "✦"
	sym.name = "测试增益"
	_duel.player_buffs[sym] = 3


func _effect_active(id: String) -> bool:
	match id:
		"weak":       return float(_duel.debuffs.damage_mult()) < 1.0
		"vulnerable": return float(_duel.debuffs.taken_mult()) > 1.0
		"corrode":    return float(_duel.debuffs.shield_mult()) < 1.0
		"heal_block": return float(_duel.debuffs.heal_mult()) < 1.0
		"blind":      return bool(_duel.debuffs.preview_hidden())
		"entangle":   return bool(_duel.debuffs.entangle_active())
		"backlash":   return bool(_duel.debuffs.has("backlash"))
		"drain":      return int(_duel.charge_points) < 5
		"strip":      return _duel.player_buffs.is_empty()
	return false


func _effect_recovered(id: String) -> bool:
	if id == "drain":
		return int(_duel.charge_points) >= 5
	if id == "strip":
		return not _duel.player_buffs.is_empty()
	return false


func _rebuild_resource(id: String) -> void:
	if id == "drain":
		_duel.charge_points += 3       # 重新积累充能（操作类应对，不需要装备）
	elif id == "strip":
		_add_test_buff()               # 重新获得增益


# 无装备应对：优先走真实入口（破甲通知 / 换符号），其余走自动到期。
func _free_counter(id: String) -> bool:
	match id:
		"corrode":
			_duel.notify_armor_break()
			return not _duel.debuffs.has("corrode")
		"backlash":
			_duel.turn_count = 4
			_duel.debuffs.note_turn_symbols(_duel, ["res://sym_other.tres"])
			return not _duel.debuffs.has("backlash")
		_:
			for i in range(4):
				_duel.turn_count += 1
				_duel.turn_resolved = false
				_duel.debuffs.tick_turn_end(_duel)
			return not _duel.debuffs.has(id)


# ---------------------------------------------------------------------------
# B. 4 类转轮干扰意图 · 净化通道 / 接受结果通道
# ---------------------------------------------------------------------------

func _test_interference_counterplay() -> void:
	var probe: RoomData = _room_by_name("重锤蛮兵")
	for id in INTERFERENCE_INTENTS:
		_start_probe(probe)
		var it: IntentData = _duel.status_system.intent_def(id)
		_check(it != null, "意图「%s」定义存在" % id)
		if it == null:
			continue
		_check(bool(it.purifiable), "意图「%s」可被净化药剂抵消" % id)
		_check(is_equal_approx(float(it.value_mult), 0.0),
			"意图「%s」不造成直接伤害，接受结果的代价有界" % id)

		# 通道一：净化药剂
		_start_probe(probe)
		_duel.enemy_intent = {"data": it, "type": id, "value": 0}
		_duel.consumable_system.use_purify(load(PURIFY_POTION))
		_check(String(_duel.enemy_intent.get("type", "")) == "none",
			"意图「%s」净化药剂真实抵消" % id)

		# 通道二：不净化，意图生效后仍可完成一整回合
		_start_probe(probe)
		_duel.enemy_intent = {"data": it, "type": id, "value": 0}
		_duel.enemy_system.take_turn()
		_check(_pending_active(id), "意图「%s」不净化时确实生效（非纸面机制）" % id)
		var before: int = int(_duel.turn_count)
		var turn_result: String = await _play_one_turn()
		var advanced: bool = int(_duel.turn_count) > before
		var finished: bool = _duel.game_state == DuelController.FlowState.WON
		_check(turn_result == "OK" and (advanced or finished),
			"意图「%s」无净化仍能完成一回合，不被软锁" % id)


func _pending_active(id: String) -> bool:
	match id:
		"jam":       return int(_duel.pending_jam_reel) >= 0
		"lock":      return int(_duel.pending_lock_reel) >= 0
		"chaos":     return bool(_duel.pending_chaos)
		"auto_stop": return bool(_duel.pending_auto_stop)
	return false


# ---------------------------------------------------------------------------
# C. 61 房 · 无装备 Build 全量通关
# ---------------------------------------------------------------------------

func _test_bare_build_all_rooms() -> void:
	_bare_build(_duel)
	_check(_duel.consumable_slots.is_empty(), "无装备 Build：腰带为空（无净化/清净药剂）")
	_check(_duel.selected_charms.is_empty(), "无装备 Build：护符为空（无抗扰/守备护符）")
	_check(int(_duel.charm_interf_resist) <= 0, "无装备 Build：无抗扰加成")
	var rooms: Array = _duel.ALL_ROOMS.duplicate()
	_check(rooms.size() == 61, "房间全表 61 个（实测 %d）" % rooms.size())
	var won_count := 0
	var worst_turns := 0
	for r in rooms:
		var room: RoomData = r
		_start_room(room)
		_duel.player_hp_max = GOD_HP
		_duel.player_hp = GOD_HP
		var res: Dictionary = await _clear_room()
		var won: bool = bool(res.get("won", false))
		var turns: int = int(res.get("turns", 0))
		if won:
			won_count += 1
			worst_turns = maxi(worst_turns, turns)
		_check(won, "无装备通关「%s」（%d 回合 / 预算 %d）" % [String(room.name), turns, ROOM_TURN_BUDGET])
		_room_results.append("%s:%s%d" % [String(room.name), "win" if won else "stuck", turns])
		await _leave_post_battle()
	print("COUNTER|ROOMS won=%d/%d worst_turns=%d" % [won_count, rooms.size(), worst_turns])
	_check(won_count == rooms.size(), "61/61 房间无装备可通关（装备不是门票）")


# ---------------------------------------------------------------------------
# D. 代表房双 Build · 装备不成为唯一最优解
# ---------------------------------------------------------------------------

func _test_dual_builds() -> void:
	for nm in DUAL_BUILD_ROOMS:
		var room: RoomData = _room_by_name(nm)
		if room == null:
			_check(false, "代表房「%s」存在" % nm)
			continue
		_bare_build(_duel)
		_start_room(room)
		_duel.player_hp_max = GOD_HP
		_duel.player_hp = GOD_HP
		var bare: Dictionary = await _clear_room()
		await _leave_post_battle()
		_equipped_build(_duel)
		_start_room(room)
		_duel.player_hp_max = GOD_HP
		_duel.player_hp = GOD_HP
		var equipped: Dictionary = await _clear_room()
		await _leave_post_battle()
		_check(bool(bare.get("won", false)) and bool(equipped.get("won", false)),
			"「%s」无装备 %d 回合 / 带对策装备 %d 回合，两条路都能通关"
			% [nm, int(bare.get("turns", 0)), int(equipped.get("turns", 0))])


# ---------------------------------------------------------------------------
# 跑局辅助
# ---------------------------------------------------------------------------

func _start_probe(r: RoomData) -> void:
	_start_room(r)
	_duel.player_hp_max = GOD_HP
	_duel.player_hp = GOD_HP
	# 探针房不会被一回合秒杀，保证「完成一回合」判定不被提前 WON 干扰。
	_duel.enemy_hp_max = 10000
	_duel.enemy_hp = 10000


func _start_room(r: RoomData) -> void:
	if r == null:
		return
	_duel.ROOMS.clear()
	_duel.ROOMS.append(r)
	_duel.start_room_data(r, 0, 0, false)


func _room_by_name(nm: String) -> RoomData:
	for r in _duel.ALL_ROOMS:
		if String(r.name) == nm:
			return r
	return null


func _clear_room() -> Dictionary:
	var turns := 0
	while turns < ROOM_TURN_BUDGET:
		if _duel.game_state == DuelController.FlowState.WON:
			return {"won": true, "turns": turns}
		if _duel.game_state == DuelController.FlowState.LOST:
			return {"won": false, "turns": turns}
		turns += 1
		var turn_result: String = await _play_one_turn()
		if turn_result != "OK":
			return {"won": false, "turns": turns}
	if _duel.game_state == DuelController.FlowState.WON:
		return {"won": true, "turns": turns}
	return {"won": false, "turns": turns}


func _play_one_turn() -> String:
	_duel._on_spin_pressed()
	var guard := 0
	while guard < TURN_FRAME_GUARD:
		if _duel.reel_system.spinning:
			_duel._on_spin_button_pressed()
		elif not _duel._busy:
			return "OK"
		guard += 1
		await get_tree().process_frame
	return "TURN_TIMEOUT"


func _leave_post_battle() -> void:
	if _duel.room_flow.post_battle_active:
		_duel.room_flow.skip_post_battle()
	await _frames(1)


# ---------------------------------------------------------------------------
# 通用
# ---------------------------------------------------------------------------

func _restore_save() -> void:
	if not _have_save:
		return
	SaveSystem.save_lobby_data(_save_backup)
	SaveSystem.flush_lobby_data()


func _section(name: String, t0: int) -> void:
	print("COUNTER|TIME %s=%dms" % [name, Time.get_ticks_msec() - t0])


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
