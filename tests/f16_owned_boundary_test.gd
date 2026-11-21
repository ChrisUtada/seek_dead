extends Node

# F-16 边界（2026-11-22 语义修正）：局外解锁 ≠ 本局持有；商店只看当前装备 + 本局仓库。
# 三个真实反例：
#   ① 上局解锁、本局未持有 → 可以购买（卡面不禁用、购买扣款并直接装备）
#   ② 本局仓库已有但未装备 → 显示"仓库已有"、禁止重复购买（直接调购买函数也拒绝）
#   ③ 当前已装备 → 显示"已装备"、禁止购买
# 修复前本文件断言相反（局外已拥有→禁购），属错误层级，已反转。

var _fails := 0
var _checks := 0
var _duel: DuelController

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("F16 BOUNDARY FAIL: " + label)

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
	_duel.gold = 500

	# ②③ 需要已装备武器；① 需空武器槽，放最后（会临时缩槽）。
	_test_in_inventory_not_equipped()
	_test_equipped()
	_test_unlocked_but_not_held_can_buy()

	_finish()

# ① 局外已拥有、本局未持有：可以购买（卡面不禁用、购买成功入本局仓库）。
func _test_unlocked_but_not_held_can_buy() -> void:
	var candidate: String = ""
	for p in _duel.meta.get("owned_weapons", []):
		if not _duel.selected_loadout.has(String(p)) and not _duel.run_weapon_inventory.has(String(p)):
			candidate = String(p)
			break
	_ok(candidate != "", "存在局外已拥有但本局未持有的武器")
	if candidate == "":
		return
	# 腾出武器槽（本测试只验证持有判据，不受 2/2 天花板干扰）
	while _duel.selected_loadout.size() > 1:
		_duel.selected_loadout.pop_back()
	var offer := {"path": candidate, "kind": "weapon", "name": "局外解锁武器", "price": 10, "sold": false}
	var card: Button = _duel.hud._cards.shop_card(offer)
	_ok(not card.disabled, "局外已拥有但本局未持有 → 商店卡可购买（不被禁用）")
	var status: String = String((card.get_node("Center/VBox/StatusLabel") as Label).text)
	_ok(not status.contains("已拥有") and not status.contains("已装备"), "卡面不误标已拥有（%s）" % status)
	var gold_before: int = _duel.gold
	_duel._shop_system.on_shop_buy_pressed(offer)
	_ok(_duel.gold == gold_before - 10, "购买局外已拥有武器扣款")
	_ok(_duel.selected_loadout.has(candidate), "购买后进入本局持有（直接装备）")

# ② 本局仓库已有但未装备：显示"仓库已有"、禁止重复购买（直接调购买函数也拒绝）。
func _test_in_inventory_not_equipped() -> void:
	var candidate: String = ""
	for p in _duel.run_weapon_inventory:
		if not _duel.selected_loadout.has(String(p)):
			candidate = String(p)
			break
	if candidate == "":
		# 构造：取一把局外池武器塞进本局仓库
		for p in _duel.WEAPON_POOL:
			if not _duel.selected_loadout.has(String(p)) and not _duel.run_weapon_inventory.has(String(p)):
				candidate = String(p)
				_duel.run_weapon_inventory.append(candidate)
				break
	_ok(candidate != "", "存在本局仓库已有但未装备的武器")
	if candidate == "":
		return
	var offer := {"path": candidate, "kind": "weapon", "name": "仓库已有武器", "price": 10, "sold": false}
	var card: Button = _duel.hud._cards.shop_card(offer)
	_ok(card.disabled, "仓库已有未装备 → 商店卡禁用")
	var status: String = String((card.get_node("Center/VBox/StatusLabel") as Label).text)
	_ok(status.contains("仓库已有"), "卡面显示仓库已有（%s）" % status)
	var gold_before: int = _duel.gold
	_duel._shop_system.on_shop_buy_pressed(offer)
	_ok(_duel.gold == gold_before, "直接调购买函数也拒绝仓库已有（不扣款）")

# ③ 当前已装备：显示"已装备"、禁止购买。
func _test_equipped() -> void:
	var p: String = _duel.selected_loadout[0]
	var offer := {"path": p, "kind": "weapon", "name": "已装备武器", "price": 10, "sold": false}
	var card: Button = _duel.hud._cards.shop_card(offer)
	_ok(card.disabled, "已装备 → 商店卡禁用")
	var status: String = String((card.get_node("Center/VBox/StatusLabel") as Label).text)
	_ok(status.contains("已装备"), "卡面显示已装备（%s）" % status)
	var gold_before: int = _duel.gold
	_duel._shop_system.on_shop_buy_pressed(offer)
	_ok(_duel.gold == gold_before, "直接调购买函数也拒绝已装备（不扣款）")

func _finish() -> void:
	print("F16BOUNDARY RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
