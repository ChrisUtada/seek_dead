extends Node

# ============================================================================
# T1.5 / N-09 商店武器限频专项（契约返工后）
#
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t15_shop_weapon_quota_test.tscn
# 隔离：必须由外部覆盖 APPDATA 到临时目录后再运行，绝不触碰真实存档。
#
# 新契约（返工后）：
# - 无自由定向系统（方向选择行/weapon_focus/定向过滤/空池提示全部移除）。
# - 每房货架 4 格（1 武器 + 消耗品 + 技能 + 护符/随机构筑）。
# - 每幕最多 2 次武器候选机会（按实际生成计数，跳过也算）。
# - reroll 冻结武器对象与价格、不重复计配额；其他类别正常刷新；同种子可复现。
# ============================================================================

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
	_duel._confirm_loadout()
	await get_tree().process_frame
	await _run()
	_finish()


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _weapon_offers() -> Array:
	var out: Array = []
	for o in _duel._shop_system.shop_offers:
		if String(o.get("kind", "")) == "weapon":
			out.append(o)
	return out


func _run() -> void:
	_test_no_focus_entry()
	_test_shelf_four_slots()
	_test_quota_per_act()
	_test_reroll_freezes_weapons()
	_test_quota_reset_on_act_change()
	_test_non_weapon_available()
	_test_determinism()


# ① 无自由定向入口：方向选择行/空状态提示节点不存在，weapon_focus 字段已移除
func _test_no_focus_entry() -> void:
	var shop = _duel.hud.shop_screen
	_check(shop != null, "商店屏存在")
	if shop != null:
		var row = shop.get_node_or_null("Margin/Content/BuyPanel/WeaponFocusRow")
		_check(row == null, "方向选择行已移除（实测 %s）" % ("存在" if row != null else "不存在"))
		var hint = shop.get_node_or_null("Margin/Content/BuyPanel/WeaponFocusEmptyHint")
		_check(hint == null, "空池提示节点已移除（实测 %s）" % ("存在" if hint != null else "不存在"))
	# 生产系统不再有 weapon_focus 字段（用反射确认，避免死代码残留）
	var sys = _duel._shop_system
	_check(not ("weapon_focus" in sys), "shop_system 无 weapon_focus 字段")
	_check(not ("focus_no_weapon" in sys), "shop_system 无 focus_no_weapon 字段")


# ② 每房货架最多 4 格（新契约）
func _test_shelf_four_slots() -> void:
	_duel._shop_system.reset_run()
	_duel.current_act = 1
	for i in 3:
		_duel.room_index = i
		seed(7002 + i)
		_duel._shop_system.roll_shop()
		var n: int = _duel._shop_system.shop_offers.size()
		_check(n <= 4, "房%d 货架 ≤4 格（实测 %d）" % [i, n])


# ③ 每幕最多 2 次武器候选机会
func _test_quota_per_act() -> void:
	_duel._shop_system.reset_run()
	_duel.current_act = 1
	seed(7001)
	var total_weapon: int = 0
	for i in 12:   # 模拟一幕内 12 个不同房间进商店（每房首次 roll 才计配额）
		_duel.room_index = i
		_duel._shop_system.roll_shop()
		total_weapon += _weapon_offers().size()
	_check(total_weapon == _duel._shop_system.ACT_WEAPON_QUOTA,
		"每幕武器候选总数 = 配额 2（实测 %d）" % total_weapon)
	_check(_duel._shop_system.weapon_quota_used == _duel._shop_system.ACT_WEAPON_QUOTA,
		"配额计数 = 2（实测 %d）" % _duel._shop_system.weapon_quota_used)


# ④ reroll 不刷新武器对象（path + price 冻结）、不重复计配额
func _test_reroll_freezes_weapons() -> void:
	_duel._shop_system.reset_run()
	_duel.current_act = 1
	_duel.room_index = 0
	_duel.gold = 500
	seed(7004)
	_duel._shop_system.roll_shop()
	var before: Array = []
	for o in _weapon_offers():
		before.append({"path": String(o["path"]), "price": int(o["price"])})
	_check(not before.is_empty(), "前置：货架有武器候选（%d）" % before.size())
	var quota_before: int = _duel._shop_system.weapon_quota_used
	_duel._shop_system.on_shop_reroll_pressed()
	var after: Array = []
	for o in _weapon_offers():
		after.append({"path": String(o["path"]), "price": int(o["price"])})
	_check(after == before, "reroll 后武器对象与价格完全不变（%s vs %s）" % [str(before), str(after)])
	_check(_duel._shop_system.weapon_quota_used == quota_before,
		"reroll 不重复计入武器配额（%d → %d）" % [quota_before, _duel._shop_system.weapon_quota_used])


# ⑤ 换幕后配额重置
func _test_quota_reset_on_act_change() -> void:
	_duel._shop_system.reset_run()
	_duel.current_act = 1
	seed(7003)
	for i in 6:
		_duel.room_index = i
		_duel._shop_system.roll_shop()
	_check(_duel._shop_system.weapon_quota_used == _duel._shop_system.ACT_WEAPON_QUOTA,
		"ACT1 配额已用尽（%d）" % _duel._shop_system.weapon_quota_used)
	_duel.current_act = 2
	_duel.room_index = 8
	_duel._shop_system.roll_shop()
	_check(_duel._shop_system.quota_act == 2, "计数幕号切到 2（实测 %d）" % _duel._shop_system.quota_act)
	var fresh: int = _weapon_offers().size()
	_check(_duel._shop_system.weapon_quota_used == fresh and fresh <= _duel._shop_system.ACT_WEAPON_QUOTA,
		"换幕后配额重置（本次生成 %d 把，计数 %d）" % [fresh, _duel._shop_system.weapon_quota_used])


# ⑥ 其他类别商品仍可获得（含配额用尽后）
func _test_non_weapon_available() -> void:
	_duel._shop_system.reset_run()
	_duel.current_act = 1
	seed(7005)
	for i in 6:
		_duel.room_index = i
		_duel._shop_system.roll_shop()
	var offers: Array = _duel._shop_system.shop_offers
	var kinds: Dictionary = {}
	for o in offers:
		kinds[String(o.get("kind", ""))] = true
	_check(offers.size() >= 3, "配额用尽后货架仍有商品（实测 %d 格）" % offers.size())
	_check(kinds.has("active") or kinds.has("skill") or kinds.has("passive"),
		"配额用尽后仍有非武器商品（实测类别 %s）" % str(kinds.keys()))
	_check(not kinds.has("weapon"), "配额用尽后无武器格（实测类别 %s）" % str(kinds.keys()))


# ⑦ 同种子同输入可复现（同房重复 roll 货架稳定）
func _test_determinism() -> void:
	_duel._shop_system.reset_run()
	_duel.current_act = 1
	_duel.room_index = 0
	# 用 loot 池专用 RNG 重置到同一种子（与 T7 同口径；seed() 只重置全局 RNG，不影响 _loot._rng）
	_duel._reward_system._loot.reset_run(7006)
	_duel._shop_system.roll_shop()
	var a: Array = []
	for o in _duel._shop_system.shop_offers:
		a.append(String(o.get("path", "")))
	_duel._reward_system._loot.reset_run(7006)
	_duel._shop_system.roll_shop()
	var b: Array = []
	for o in _duel._shop_system.shop_offers:
		b.append(String(o.get("path", "")))
	_check(a == b, "同种子同输入货架可复现（%s vs %s）" % [str(a), str(b)])


func _finish() -> void:
	print("---")
	print("T15QUOTA RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
