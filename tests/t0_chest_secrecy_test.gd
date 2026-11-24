extends Node

# ============================================================================
# T0-2 专项：宝箱保密、揭示与随机隔离（docs/Seek_Dead_T0_当前缺陷返工与执行指令_2026-11-22.md §3）
#
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t0_chest_secrecy_test.tscn
# 隔离：必须由外部覆盖 APPDATA 到临时目录后再运行，绝不触碰真实存档。
#
# 必测场景（文档 §3）：
#   A. 开启前 UI 不含物品名称、品质或效果。
#   B. 开启后 UI 展示的物品与实际获得一致。
#   C. 同种子、同输入下类型和内容可复现。
#   D. 宝箱生成前后全局 RNG 序列不被类别洗牌污染。
#   E. 武器/护符/消耗品/金币兜底各有真实结算覆盖。
#   F. 重复开启/确认不重复发奖、不软锁。
#
# 本测试只用 UI 元素文本 + 控制器公开状态驱动，不引用尚不存在的方法名，
# 以便修改前可编译运行、真实暴露缺陷。
# ============================================================================

const WEAPON_PATH := "res://resources/weapon_templates/iron_sword.tres"
const CHARM_PATH := "res://resources/charms/guard_charm.tres"
const CONSUMABLE_PATH := "res://resources/consumables/heal_potion.tres"

var _fails := 0
var _checks := 0
var _duel: DuelController


func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	_duel = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(_duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_duel.demo_config.enabled = false
	_duel.shop_run_seed = 20261122
	_duel._confirm_loadout()
	await get_tree().process_frame
	_run()
	_finish()


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


# 进入宝箱房（直接构造固定内容，精确断言展示与结算一致）
func _enter_chest(category: String, item_path: String, fallback_gold: int = 15) -> void:
	_duel.room_index = 2
	_duel._linear_special_done = false
	var r: RoomData = _duel.ROOMS[2]
	r.kind = "chest"
	r.gimmick_params = {"special_kind": "chest", "category": category,
		"item_path": item_path, "fallback_gold": fallback_gold}
	_duel.start_room_data(r, 2)


# 收集特殊房弹层所有 Label 文本
func _special_labels_text() -> String:
	var out := ""
	var hud = _duel.hud
	if hud._special_dialog == null or hud._special_vbox == null:
		return out
	for c in hud._special_vbox.get_children():
		if c is Label:
			out += String((c as Label).text) + "\n"
	return out


# 在特殊房弹层中找文本含 keyword 的按钮并触发
func _press_special_button(keyword: String) -> bool:
	var hud = _duel.hud
	if hud._special_dialog == null or hud._special_vbox == null:
		return false
	for c in hud._special_vbox.get_children():
		if c is Button and String((c as Button).text).contains(keyword):
			(c as Button).pressed.emit()
			return true
	return false


func _run() -> void:
	_test_rng_isolation()
	_test_no_leak_before_open()
	_test_determinism()
	_test_reveal_stage_no_early_settle()
	_test_reveal_matches_grant()
	_test_repeat_confirm_once()
	_test_all_category_settlement()


# D：全局 RNG 不被类别洗牌污染（精确定位到 _freeze_chest）
func _test_rng_isolation() -> void:
	var baseline: Array[int] = []
	seed(20261122)
	for _i in 6:
		baseline.append(randi())
	var after: Array[int] = []
	seed(20261122)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	_duel.run_setup._freeze_chest(1, rng)   # 当前实现会 cat.shuffle() 用全局 RNG
	for _i in 6:
		after.append(randi())
	_check(baseline == after, "D 宝箱生成不污染全局 RNG 序列（基准 %s，实测 %s）" % [str(baseline), str(after)])


# A：开启前 UI 不含物品名/品质/效果
func _test_no_leak_before_open() -> void:
	_enter_chest("weapon", WEAPON_PATH)
	var txt: String = _special_labels_text()
	var leaked_name: bool = txt.contains("铁") or txt.contains("剑") or txt.contains("sword")
	var leaked_quality: bool = (txt.contains("普通") or txt.contains("精良") or txt.contains("稀有")
		or txt.contains("史诗") or txt.to_lower().contains("rare") or txt.to_lower().contains("epic"))
	var leaked_effect: bool = txt.contains("获得") or txt.contains("效果") or txt.contains("+")
	_check(not leaked_name, "A 开启前 UI 不含物品名（实测文本：%s）" % txt.replace("\n", " | "))
	_check(not leaked_quality, "A 开启前 UI 不含品质")
	_check(not leaked_effect, "A 开启前 UI 不含效果/获得描述")


# C：同种子同输入可复现
func _test_determinism() -> void:
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 918273
	var a: Dictionary = _duel.run_setup._freeze_chest(2, rng1)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 918273
	var b: Dictionary = _duel.run_setup._freeze_chest(2, rng2)
	_check(a == b, "C 同种子同输入冻结内容一致（%s vs %s）" % [str(a), str(b)])


# 揭示阶段：点「开启宝箱」后不得立即结算，且应出现揭示弹层
func _test_reveal_stage_no_early_settle() -> void:
	_enter_chest("gold", "", 15)
	var g0: int = _duel.gold
	_check(_press_special_button("开启"), "揭示 找到「开启宝箱」按钮")
	_check(not _duel._linear_special_done, "揭示 点开启后尚未结算")
	_check(_duel.gold == g0, "揭示 点开启后金币未提前入账（实测 %d）" % (_duel.gold - g0))
	_check(_duel.hud._special_dialog.visible, "揭示 揭示弹层可见")


# B：揭示展示的物品与实际获得一致
func _test_reveal_matches_grant() -> void:
	_enter_chest("weapon", WEAPON_PATH)
	_check(_press_special_button("开启"), "B 找到开启按钮")
	var reveal_txt: String = _special_labels_text()
	_check(reveal_txt.contains("铁") or reveal_txt.contains("剑") or reveal_txt.contains("sword"),
		"B 开启后揭示展示实际物品（实测文本：%s）" % reveal_txt.replace("\n", " | "))
	var inv_before: int = _duel.run_weapon_inventory.size()
	_check(_press_special_button("确认"), "B 找到确认继续按钮")
	_check(_duel.run_weapon_inventory.size() == inv_before + 1, "B 确认后实际获得该物品入仓")
	_check(_duel.run_weapon_inventory.has(WEAPON_PATH), "B 入仓物品与揭示物品同源（含 %s）" % WEAPON_PATH)
	_check(_duel._linear_special_done, "B 确认后结算完成")


# F：重复确认不重复发奖、不软锁
func _test_repeat_confirm_once() -> void:
	_enter_chest("gold", "", 15)
	var g0: int = _duel.gold
	_press_special_button("开启")
	var g_reveal: int = _duel.gold
	_check(g_reveal == g0, "F 揭示阶段不发奖")
	var found: bool = _press_special_button("确认")
	_check(found, "F 找到确认按钮")
	var g_once: int = _duel.gold
	_check(g_once == g0 + 15, "F 确认只发一次 +15（实测 %d）" % (g_once - g0))
	_press_special_button("确认")   # 二次确认（按钮可能已隐藏）
	_press_special_button("开启")   # 误触开启
	_check(_duel.gold == g_once, "F 重复确认/开启不重复发奖（实测 %d）" % (_duel.gold - g0))
	_check(_duel._linear_special_done, "F 结算守卫置位（不软锁）")


# E：武器/护符/消耗品/金币兜底各有真实结算覆盖（全部走真实 HUD 揭示→确认链）
func _test_all_category_settlement() -> void:
	# 消耗品：入腰带（走 HUD 链）
	_enter_chest("active", CONSUMABLE_PATH)
	var belt0: int = _duel.consumable_slots.size()
	_press_special_button("开启")
	_press_special_button("确认")
	_check(_duel.consumable_slots.size() == belt0 + 1, "E 消耗品宝箱真实入腰带（%d→%d）" % [belt0, _duel.consumable_slots.size()])

	# 护符：入槽并生效（走 HUD 链）
	_duel.selected_charms.clear()
	_duel._apply_charms()
	_enter_chest("passive", CHARM_PATH)
	_press_special_button("开启")
	_press_special_button("确认")
	_check(_duel.selected_charms.has(CHARM_PATH), "E 护符宝箱真实入槽")

	# 金币兜底：只发一次（走 HUD 链）
	_enter_chest("gold", "", 15)
	var g0: int = _duel.gold
	_press_special_button("开启")
	_press_special_button("确认")
	_check(_duel.gold == g0 + 15, "E 金币兜底真实 +15（实测 %d）" % (_duel.gold - g0))

	# 武器：入仓不强制换装（走 HUD 链）
	# 动态选一把本局仓库里没有的武器，避免前面场景已入仓导致去重不计 +1。
	var fresh_weapon: String = _unowned_weapon()
	_check(fresh_weapon != "", "E 找到未持有的武器用于宝箱（%s）" % fresh_weapon)
	if fresh_weapon != "":
		_enter_chest("weapon", fresh_weapon)
		var inv0: int = _duel.run_weapon_inventory.size()
		var equip0: int = _duel.selected_loadout.size()
		_press_special_button("开启")
		_press_special_button("确认")
		_check(_duel.run_weapon_inventory.size() == inv0 + 1, "E 武器真实入仓")
		_check(_duel.selected_loadout.size() == equip0, "E 武器不强制换装")


# 动态找一把本局仓库里没有的武器路径
func _unowned_weapon() -> String:
	var dir := DirAccess.open("res://resources/weapon_templates")
	if dir == null:
		return ""
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var path: String = "res://resources/weapon_templates/" + file_name
			if not _duel.run_weapon_inventory.has(path):
				dir.list_dir_end()
				return path
		file_name = dir.get_next()
	dir.list_dir_end()
	return ""


func _finish() -> void:
	print("---")
	print("T0-2 RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
