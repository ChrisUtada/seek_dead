extends Node

# ============================================================================
# M1-01 武器奖励可达性 · headless 回归（场景入口，工程约束同 t8_drops）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/m1_reward_reach_test.tscn
#
# 覆盖（docs/统一落地执行计划.md M1-01）：
# ① 候选池：幕一不出武器；幕二/幕三满双武器时武器卡仍入池（不再被槽位前置拦截）
# ② 展示前预确定：武器卡 payload 指向具体未装备武器，确认后不再二次随机
# ③ 空槽：奖励武器进本局配装 + 写局外收藏
# ④ 满槽：选择武器卡 → 替换弹层 → 替换后旧武器移除、新武器入槽入收藏
# ⑤ BOSS 主题武器在满双武器时仍可作为候选
# ⑥ 精英动态位在满双武器时仍可出武器
# ⑦ 卖出不低于双武器下限（loadout_min=2）
# ============================================================================

const TRIALS := 60

var _fails := 0
var _checks := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var duel: DuelController = await _boot()
	if duel == null:
		print("RESULT FAIL (boot)")
		get_tree().quit(2)
		return

	_test_pool_gating(duel)
	_test_roll_prepick(duel)
	_test_apply_free_slot(duel)
	_test_full_slot_replace(duel)
	_test_boss_weapons_when_full(duel)
	_test_elite_weapon_when_full(duel)
	_test_sell_guard(duel)

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()   # 构建本局房间序列（ROOMS 为空时 act 默认 1，无法测幕二/三）
	await get_tree().process_frame
	return duel


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _room_index_of(duel: DuelController, act: int, kind: String) -> int:
	for i in range(duel.ROOMS.size()):
		var r: RoomData = duel.ROOMS[i]
		if r.act == act and r.kind == kind and not r.final_boss:
			return i
	return 0


func _fill_two_weapons(duel: DuelController) -> void:
	duel.selected_loadout.clear()
	duel.loadout_max = 2
	for i in range(min(2, duel.WEAPON_POOL.size())):
		duel.selected_loadout.append(duel.WEAPON_POOL[i])
	duel._build_pool(duel.selected_loadout)


func _payload_only(duel: DuelController, path: String) -> void:
	duel._reward_system.choice_payloads.clear()
	duel._reward_system.choice_payloads.append({"kind": "weapon", "path": path, "title": "武器 · 测试", "desc": "测试"})


# ① 候选池闸门：幕一排除，幕二/三保留（与武器槽占用无关）
func _test_pool_gating(duel: DuelController) -> void:
	_fill_two_weapons(duel)
	var p1: Array = duel._reward_system.build_reward_pool(1)
	var p2: Array = duel._reward_system.build_reward_pool(2)
	var p3: Array = duel._reward_system.build_reward_pool(3)
	_check(p1.filter(func(rw): return rw.id == "weapon").is_empty(), "幕一候选池不含武器")
	_check(not p2.filter(func(rw): return rw.id == "weapon").is_empty(), "幕二满双武器时武器仍在候选池")
	_check(not p3.filter(func(rw): return rw.id == "weapon").is_empty(), "幕三满双武器时武器仍在候选池")


# ② roll_rewards 产出的武器卡带已确定 payload；幕一不会出现
func _test_roll_prepick(duel: DuelController) -> void:
	_fill_two_weapons(duel)
	duel.room_index = _room_index_of(duel, 1, "normal")
	var act1_weapon := false
	for i in range(10):
		for rw in duel._reward_system.roll_rewards():
			if rw.id == "weapon":
				act1_weapon = true
	_check(not act1_weapon, "幕一 10 次 roll 不出武器卡")

	duel.room_index = _room_index_of(duel, 2, "normal")
	var saw := false
	var payload_ok := true
	for i in range(TRIALS):
		var choices: Array = duel._reward_system.roll_rewards()
		for j in range(choices.size()):
			if choices[j].id != "weapon":
				continue
			saw = true
			var pl: Dictionary = duel._reward_system.payload_at(j)
			if pl.is_empty():
				payload_ok = false
				continue
			var path := String(pl.get("path", ""))
			var wd: WeaponData = load(path)
			if path == "" or duel.selected_loadout.has(path) or wd == null:
				payload_ok = false
			elif not String(pl.get("title", "")).contains(wd.weapon_name):
				payload_ok = false
			break
		if saw:
			break
	_check(saw, "幕二 %d 次 roll 内出现武器卡" % TRIALS)
	_check(payload_ok, "武器卡 payload 指向具体未装备武器且标题含武器名")


# ③ 空槽：进配装 + 写入收藏
func _test_apply_free_slot(duel: DuelController) -> void:
	_fill_two_weapons(duel)
	duel.selected_loadout.erase(duel.selected_loadout[1])
	var new_p := ""
	for p in duel.WEAPON_POOL:
		if not duel.selected_loadout.has(p):
			new_p = p
			break
	duel.meta["owned_weapons"].erase(new_p)
	_payload_only(duel, new_p)
	duel._reward_system.apply_reward("weapon", 0)
	_check(duel.selected_loadout.has(new_p), "空槽奖励武器进入本局配装")
	_check(duel.selected_loadout.size() == 2, "配装回到双武器")
	_check(duel.meta["owned_weapons"].has(new_p), "新武器写入局外收藏 owned_weapons")


# ④ 满槽：替换弹层 + 替换结果
func _test_full_slot_replace(duel: DuelController) -> void:
	_fill_two_weapons(duel)
	var new_p := ""
	for p in duel.WEAPON_POOL:
		if not duel.selected_loadout.has(p):
			new_p = p
			break
	var old_p: String = duel.selected_loadout[0]
	duel.meta["owned_weapons"].erase(new_p)
	duel.reward_is_boss = false
	duel.reward_choices = [duel._reward_system._find_reward("weapon")]
	_payload_only(duel, new_p)
	duel._on_reward_chosen("weapon", 0)
	_check(duel.hud._replace_dialog != null and duel.hud._replace_dialog.visible, "满槽选武器卡弹出替换弹层")
	duel.hud._on_replace_chosen(old_p)
	_check(not duel.selected_loadout.has(old_p), "替换后旧武器移出配装")
	_check(duel.selected_loadout.has(new_p), "替换后新武器进入配装")
	_check(duel.selected_loadout.size() == 2, "替换后仍为双武器")
	_check(duel.meta["owned_weapons"].has(new_p), "替换获得的新武器写入局外收藏")


# ⑤ BOSS 主题武器：满双武器仍作为候选
func _test_boss_weapons_when_full(duel: DuelController) -> void:
	_fill_two_weapons(duel)
	var urn: RoomData = null
	for r in duel.ALL_ROOMS:
		if r.final_boss == false and r.kind == "boss" and r.boss_reward_weapons.size() >= 2:
			urn = r
			break
	_check(urn != null, "找到带主题武器池的 BOSS 房")
	if urn == null:
		return
	var saw := false
	for i in range(20):
		for c in duel._reward_system.roll_boss_rewards(urn):
			if String(c.get("kind", "")) == "boss_weapon":
				saw = true
				_check(not duel.selected_loadout.has(String(c.get("path", ""))), "BOSS 武器候选不重复已装备武器")
				break
		if saw:
			break
	_check(saw, "满双武器时 BOSS 主题武器仍出现在候选中")


# ⑥ 精英动态位：满双武器仍可出武器
func _test_elite_weapon_when_full(duel: DuelController) -> void:
	_fill_two_weapons(duel)
	duel.room_index = _room_index_of(duel, 2, "elite")
	var saw := false
	for i in range(TRIALS):
		for rw in duel._reward_system.roll_elite_rewards():
			if rw.id == "weapon":
				saw = true
				break
		if saw:
			break
	_check(saw, "满双武器时精英动态位仍可出现武器")


# ⑦ 卖出下限
func _test_sell_guard(duel: DuelController) -> void:
	_fill_two_weapons(duel)
	var before := duel.selected_loadout.size()
	duel._on_shop_sell_pressed(duel.selected_loadout[0], "weapon")
	_check(duel.selected_loadout.size() == before, "双武器时无法卖出低于下限")
