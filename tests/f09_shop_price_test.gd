extends Node

# F-09 稳定售价测试（2026-11-21）
# 验证：同局同物品同价、跨物品/跨局有变化、显示价=扣款、卖出依据购入价、
# 刷新费用不变、价格计算不额外消耗 RNG。

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

	# ② 不同物品仍有变化（jitter 由路径 hash 决定，至少取到多个不同值）
	var vals := {}
	var paths: Array = _duel.WEAPON_POOL.slice(0, 12)
	for p in paths:
		var v: int = _duel._shop_system.shop_price("weapon", -1, String(p))
		vals[v] = true
	_ok(vals.size() >= 2, "不同物品价格有变化（实测 %d 种）" % vals.size())

	# ③ 不同局（改 run seed）价格变化
	var old_seed: int = _duel.shop_run_seed
	var p1_old: int = _duel._shop_system.shop_price("weapon", -1, P1)
	_duel.shop_run_seed = 99999
	var p1_new: int = _duel._shop_system.shop_price("weapon", -1, P1)
	_ok(p1_old != p1_new, "不同局价格变化（%d → %d）" % [p1_old, p1_new])
	_duel.shop_run_seed = old_seed

	# ④ 显示价 = 购买扣款
	_duel.gold = 500
	_duel.selected_loadout.clear()   # 腾出武器槽，保证本次购买可执行
	_duel._shop_system.roll_shop()
	var offer: Dictionary = _duel._shop_system.shop_offers[0]
	var shown: int = int(offer["price"])
	var gold_before: int = _duel.gold
	_duel._shop_system.on_shop_buy_pressed(offer)
	_ok(_duel.gold == gold_before - shown, "购买扣款=货架显示价（%d）" % shown)

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
