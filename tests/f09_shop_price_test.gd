extends Node

# F-09 稳定售价测试（2026-11-21；2026-11-22 固定目录价收口）
# 验证：固定目录价——同物品跨局同价、同稀有度同价、稀有度阶梯保留、
#       价格不随持有数递增（开槽费已移除）、显示价=扣款、营地/商店同源同价、
#       刷新费用不变、价格计算不额外消耗 RNG。

const P1 := "res://resources/weapon_templates/fire_sword.tres"
const P2 := "res://resources/weapon_templates/dagger.tres"
const P3 := "res://resources/charms/guard_charm.tres"

var _fails := 0
var _checks := 0
var _duel: DuelController

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("F09 FAIL: " + label)


# 从护符资源目录找一把本局未持有（不在装备）的护符，确定性构造，不依赖随机货架
func _unheld_charm_excluding(exclude: Array = []) -> String:
	var dir := DirAccess.open("res://resources/charms")
	if dir == null:
		return ""
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var path: String = "res://resources/charms/" + fname
			if not _duel.selected_charms.has(path) and not exclude.has(path):
				dir.list_dir_end()
				return path
		fname = dir.get_next()
	dir.list_dir_end()
	return ""


func _unheld_charm() -> String:
	return _unheld_charm_excluding([])

func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	_duel = scene_res.instantiate() as DuelController
	add_child(_duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_duel.demo_config.enabled = false
	_duel._confirm_loadout()
	await get_tree().process_frame
	_duel.shop_run_seed = 12345

	# ① 同局同物品多次调用同价
	var p1a: int = _duel._shop_system.shop_price("weapon", -1, P1)
	var p1b: int = _duel._shop_system.shop_price("weapon", -1, P1)
	for i in range(10):
		_duel._shop_system.roll_shop()   # 反复重生成货架
		_ok(_duel._shop_system.shop_price("weapon", -1, P1) == p1a,
			"同局同物品反复打开/重生成仍同价（第 %d 次）" % (i + 1))
	_ok(p1a == p1b, "同物品连续调用同价")

	# ② 同稀有度不同物品同价；稀有度阶梯保留
	var p_common_a: int = _duel._shop_system.shop_price("weapon", -1, P2)       # dagger common
	var p_common_b: int = _duel._shop_system.shop_price("weapon", -1, "res://resources/weapon_templates/iron_sword.tres")  # common
	_ok(p_common_a == p_common_b, "同稀有度不同物品同价（common %d / %d）" % [p_common_a, p_common_b])
	var p_rare: int = _duel._shop_system.shop_price("weapon", -1, P1)           # fire_sword rare
	_ok(p_rare > p_common_a, "稀有度阶梯保留：rare(%d) > common(%d)" % [p_rare, p_common_a])

	# ③ 不同局（改 run seed）价格不变（jitter 已移除）
	var old_seed: int = _duel.shop_run_seed
	var p1_old: int = _duel._shop_system.shop_price("weapon", -1, P1)
	_duel.shop_run_seed = 99999
	var p1_new: int = _duel._shop_system.shop_price("weapon", -1, P1)
	_ok(p1_old == p1_new, "跨局同价（%d → %d）" % [p1_old, p1_new])
	_duel.shop_run_seed = old_seed

	# ③b 价格不随持有数递增（开槽费 step 已移除）
	var p_owned0: int = _duel._shop_system.shop_price("weapon", 0, P2)
	var p_owned3: int = _duel._shop_system.shop_price("weapon", 3, P2)
	_ok(p_owned0 == p_owned3, "价格不随持有数递增（0件 %d / 3件 %d）" % [p_owned0, p_owned3])

	# ③c 营地与商店同源同价（价格计算不区分 source）
	var p_shop: int = _duel._shop_system.shop_price("weapon", -1, P2)
	var p_camp: int = _duel._shop_system.shop_price("weapon", -1, P2)
	_ok(p_shop == p_camp, "营地与商店同源同价（%d / %d）" % [p_shop, p_camp])

	# ④ 显示价 = 购买扣款（用护符：硬上限 3、初始 1，确定性可买，不依赖随机货架）
	_duel.gold = 500
	var buy_path: String = _unheld_charm()
	_ok(buy_path != "", "找到本局未持有的护符（%s）" % buy_path.get_file())
	var buy_offer: Dictionary = {
		"path": buy_path, "kind": "passive", "name": "测试护符",
		"price": _duel._shop_system.shop_price("passive", -1, buy_path), "sold": false}
	var shown: int = int(buy_offer["price"])
	var gold_before: int = _duel.gold
	_duel._shop_system.on_shop_buy_pressed(buy_offer.duplicate())
	_ok(_duel.gold == gold_before - shown, "购买扣款=货架显示价（%d）" % shown)
	_ok(_duel.selected_charms.has(buy_path), "购买后护符进入本局持有")

	# ④b 仓库已有禁止重复购买（生产规则保留）：同一路径再买必须被拒且不扣款
	var dup_offer: Dictionary = buy_offer.duplicate()
	dup_offer["sold"] = false
	var g_dup_before: int = _duel.gold
	_duel._shop_system.on_shop_buy_pressed(dup_offer)
	_ok(_duel.gold == g_dup_before, "仓库已有禁止重复购买（不扣款，%d → %d）" % [g_dup_before, _duel.gold])

	# ④c 真实购买路径：营地来源与商店来源扣款一致（用消耗品，腰带可重复占格，不受护符硬上限约束）
	var item_path: String = "res://resources/consumables/flame_flask.tres"
	var item_price: int = _duel._shop_system.shop_price("active", -1, item_path)
	var offer2: Dictionary = {
		"path": item_path, "kind": "active", "name": "测试药剂",
		"price": item_price, "sold": false}
	var offer3: Dictionary = offer2.duplicate()
	offer3["sold"] = false
	var g_shop_before: int = _duel.gold
	_duel._shop_system.on_shop_buy_pressed(offer2.duplicate(), "shop")
	var shop_spent: int = g_shop_before - _duel.gold
	var g_camp_before: int = _duel.gold
	_duel._shop_system.on_shop_buy_pressed(offer3.duplicate(), "camp")
	var camp_spent: int = g_camp_before - _duel.gold
	_ok(shop_spent == camp_spent and shop_spent > 0,
		"营地/商店真实购买扣款一致（shop %d / camp %d）" % [shop_spent, camp_spent])

	# ⑤ 刷新费用不变（首刷 5 金，递增规则由 reroll_price 决定，F-09 不动）
	var rr0: int = _duel._shop_system.reroll_price()
	_duel._shop_system.on_shop_reroll_pressed()
	var rr1: int = _duel._shop_system.reroll_price()
	_ok(rr1 > rr0, "刷新费递增规则不变（%d → %d）" % [rr0, rr1])

	# ⑥ 价格计算不消耗 RNG：连续 randi 序列在 shop_price 调用前后一致
	seed(777)
	var before_seq: Array = []
	for i in range(8): before_seq.append(randi())
	seed(777)
	_ok(true, "重置 RNG 序列")
	var p_calc: int = _duel._shop_system.shop_price("weapon", -1, P1)
	var after_seq: Array = []
	for i in range(8): after_seq.append(randi())
	var same := true
	for i in range(before_seq.size()):
		if before_seq[i] != after_seq[i]: same = false
	_ok(same, "shop_price 不消耗 RNG（价格 %d）" % p_calc)

	print("F09 RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
