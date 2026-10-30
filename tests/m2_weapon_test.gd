extends Node

# ============================================================================
# M2-02 武器熟练 R1–R4 与铭印 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/m2_weapon_test.tscn
#
# 覆盖（docs/M0-02_样板范围.md §2）：
# ① 熟练：仅本房有效结算的已装备样板武器获得；普通 +1 / 精英 +2 / BOSS +2（基础 1 + 额外 1）；每房上限 3（保险）
# ② R 等级：R2 @3、R3 @7、R4 @12；跨过 R2 / R3 各欠一次铭印，R4 不欠
# ③ 铭印候选：锋铸恒在（≤2 次）；调律仅在真实改变格数时出现，且达上限后不再出现
# ④ 锋铸：基础攻击 +2（经 build_pool 写入武器攻击力映射），不改共享 .tres
# ⑤ 调律：主符号（权重最高）池内权重 +1，带子格数由同一口径（build_strips）计算
# ⑥ 流程：房间胜利后欠选铭印 → 三选一弹层 → 选完才进房间间歇；bot 自动选亦走同一路径
# 测试结束还原 meta（不污染玩家真实存档）。
# ============================================================================

const FIRE := "res://resources/weapon_templates/fire_sword.tres"
const DAGGER := "res://resources/weapon_templates/dagger.tres"
const BURN := "res://resources/symbols/burn.tres"
const DAGGER_SLASH := "res://resources/symbols/dagger_slash.tres"
const FIRE_SLASH := "res://resources/symbols/fire_slash.tres"

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
	var meta_backup: Dictionary = duel.meta.duplicate(true)

	_test_mastery_gain(duel)
	_test_r_levels_and_owed(duel)
	_test_imprint_candidates(duel)
	_test_forge_applies(duel)
	_test_tune_applies(duel)
	_test_offer_queue(duel)

	duel.mastery.reset_run()
	duel.meta.clear()
	for k in meta_backup:
		duel.meta[k] = meta_backup[k]
	duel._meta_store.save_meta()

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	return duel


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


# 本测试的装备：火焰剑 + 匕首（两把样板武器），状态清零。
func _equip(duel: DuelController) -> void:
	duel.selected_loadout.clear()
	duel.selected_loadout.append(FIRE)
	duel.selected_loadout.append(DAGGER)
	duel.mastery.reset_run()
	duel.mastery.reset_room()
	duel.reel_system.build_pool(duel.selected_loadout)


# 本房「火焰剑的符号」结算一次（模拟 combat evaluate 的有效结算点）
func _settle_fire(duel: DuelController) -> void:
	duel.mastery.note_settle(BURN)


func _test_mastery_gain(duel: DuelController) -> void:
	_equip(duel)
	_settle_fire(duel)
	duel.mastery.settle_room("normal")
	_check(duel.mastery.mastery.get(FIRE, 0) == 1, "普通房有效结算：火焰剑 +1 熟练")
	_check(duel.mastery.mastery.get(DAGGER, 0) == 0, "未结算的匕首不获得熟练")
	duel.mastery.reset_room()
	_settle_fire(duel)
	duel.mastery.settle_room("elite")
	_check(duel.mastery.mastery.get(FIRE, 0) == 3, "精英房额外 +1：本房 +2（累计 3）")
	duel.mastery.reset_room()
	_settle_fire(duel)
	duel.mastery.settle_room("boss")
	_check(duel.mastery.mastery.get(FIRE, 0) == 5, "BOSS 房额外 +1：本房 +2（累计 5）")
	duel.mastery.reset_room()
	_settle_fire(duel)
	duel.mastery.settle_room("normal")
	_check(duel.mastery.mastery.get(FIRE, 0) == 6, "下一房重新计数（累计 6）")
	# 未装备的样板武器即使有结算也不获得熟练
	duel.selected_loadout.erase(DAGGER)
	duel.mastery.reset_room()
	duel.mastery.note_settle(DAGGER_SLASH)
	duel.mastery.settle_room("boss")
	_check(duel.mastery.mastery.get(DAGGER, 0) == 0, "未装备的武器不获得熟练")
	duel.selected_loadout.append(DAGGER)


func _test_r_levels_and_owed(duel: DuelController) -> void:
	_equip(duel)
	var m = duel.mastery
	_check(m.r_level(FIRE) == 1, "新局火焰剑 R1")
	m.mastery[FIRE] = 2
	m.reset_room()
	_settle_fire(duel)
	m.settle_room("normal")
	_check(m.r_level(FIRE) == 2 and m.owed.count(FIRE) == 1, "累计 3 → R2，欠 1 次铭印")
	m.reset_room()
	m.mastery[FIRE] = 6
	m.reset_room()
	_settle_fire(duel)
	m.settle_room("normal")
	_check(m.r_level(FIRE) == 3 and m.owed.count(FIRE) == 2, "累计 7 → R3，再欠 1 次铭印")
	m.mastery[FIRE] = 10
	m.reset_room()
	_settle_fire(duel)
	m.settle_room("normal")
	_check(m.r_level(FIRE) == 3 and m.owed.count(FIRE) == 2, "累计 11 仍为 R3")
	m.reset_room()
	_settle_fire(duel)
	m.settle_room("normal")
	_check(m.r_level(FIRE) == 4 and m.owed.count(FIRE) == 2, "累计 12 → R4，R4 不再欠铭印")
	m.reset_run()


func _test_imprint_candidates(duel: DuelController) -> void:
	_equip(duel)
	var m = duel.mastery
	var ids := []
	for c in m.imprint_choices(FIRE):
		ids.append(c["id"])
	_check(ids.has("forge"), "锋铸恒在候选中（未达上限）")
	for c in m.imprint_choices(FIRE):
		if c["id"] == "forge":
			_check(c["desc"] == "基础攻击 18 → 20", "锋铸描述给出当前 → 升级后基础攻击")
	_check(m.tune_target(FIRE).get("sym", "") == FIRE_SLASH, "调律目标 = 权重最高且 +1 真实改变格数者（燃烧 5→6 不改格；火斩 3→4 改格）")
	_check(ids.has("tune"), "调律在真实改变格数时出现（火焰剑）")
	for c in m.imprint_choices(FIRE):
		if c["id"] == "tune":
			_check(c["desc"].find("格") >= 0, "调律描述包含真实格数变化")
	m.imprints[FIRE] = {"forge": 2, "tune": {FIRE_SLASH: 2}}
	ids.clear()
	for c in m.imprint_choices(FIRE):
		ids.append(c["id"])
	_check(ids.is_empty(), "同一铭印各 2 次达上限后不再出现候选")
	m.imprints.clear()


func _test_forge_applies(duel: DuelController) -> void:
	_equip(duel)
	var m = duel.mastery
	m.owed.append(FIRE)
	_check(m.choose(FIRE, "forge"), "选择锋铸成功")
	_check(m.forge_bonus(FIRE) == 2, "锋铸：基础攻击加成 +2")
	_check(m.owed.count(FIRE) == 0, "选定后消耗一次欠选")
	duel.reel_system.build_pool(duel.selected_loadout)
	_check(int(duel._weapon_power_map.get(BURN, 0)) == 20, "锋铸写入攻击力映射：18 → 20")
	var fire_res: WeaponData = load(FIRE)
	_check(fire_res.base_power == 18, "共享 .tres 的 base_power 未被修改")
	m.imprints.clear()
	duel.reel_system.build_pool(duel.selected_loadout)


func _test_tune_applies(duel: DuelController) -> void:
	_equip(duel)
	var m = duel.mastery
	m.owed.append(FIRE)
	_check(m.choose(FIRE, "tune"), "选择调律成功")
	_check(m.tune_map().get(FIRE, {}).get(FIRE_SLASH, 0) == 1, "调律：目标符号火斩 +1")
	duel.reel_system.build_pool(duel.selected_loadout)
	var w_fs := -1.0
	for it in duel.pool_items:
		if it["name"] == "火焰剑":
			for s in it["syms"]:
				if s[0].resource_path == FIRE_SLASH:
					w_fs = float(s[1])
	_check(is_equal_approx(w_fs, 4.0), "池内火焰剑火斩权重 3 → 4")
	m.imprints.clear()
	duel.reel_system.build_pool(duel.selected_loadout)


func _test_offer_queue(duel: DuelController) -> void:
	_equip(duel)
	var m = duel.mastery
	# 选一间普通房（避免升级带入技艺三选一，单独验证铭印队列）
	var idx := 0
	for i in range(duel.ROOMS.size()):
		if duel.ROOMS[i].kind == "normal":
			idx = i
			break
	duel.room_index = idx
	duel.growth.reset_run()
	duel.in_interroom = false
	m.mastery[FIRE] = 2
	m.reset_room()
	_settle_fire(duel)
	duel.room_flow.finish_room(Callable(), false)
	_check(m.owed.has(FIRE), "房间胜利后火焰剑 R2 欠铭印")
	_check(duel.hud._growth_picker != null and duel.hud._growth_picker.visible, "欠铭印时弹出三选一")
	_check(duel.room_flow.growth_pick_pending(), "三选一队列待处理")
	_check(not duel.in_interroom, "铭印未选完前不进入房间间歇")
	duel.room_flow.auto_pick_growth()
	_check(int(m.imprints[FIRE]["forge"]) + m._tune_count(FIRE) == 1, "选定后写入一次铭印")
	_check(m.owed.is_empty(), "欠选队列清空")
	_check(duel.in_interroom, "选完铭印后进入房间间歇")
	_check(not duel.room_flow.growth_pick_pending(), "队列结束后无待选")
	m.reset_run()
	duel.hud.set_interroom_enabled(false)
	duel.in_interroom = false
