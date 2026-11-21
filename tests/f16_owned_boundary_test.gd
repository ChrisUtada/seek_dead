extends Node

# F-16 边界：局外已拥有、当前未装备 → 商店仍显示"已拥有"并禁止重复购买（2026-11-21）
# 口径：武器/护符/技能为永久收藏唯一，商店判据须查 meta.owned_*，不只看当前装备。

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

	# 选一把局外已拥有、但当前未装备的武器
	var candidate: String = ""
	for p in _duel.meta.get("owned_weapons", []):
		if not _duel.selected_loadout.has(String(p)):
			candidate = String(p)
			break
	_ok(candidate != "", "存在局外已拥有但未装备的武器")
	if candidate == "":
		_finish(); return

	# 确认当前未装备（sel_arr 不含它）
	_ok(not _duel.selected_loadout.has(candidate), "该武器当前未装备（sel_arr 不含）")

	# 商店卡应标"已拥有"并禁用
	var offer := {"path": candidate, "kind": "weapon", "name": "局外已拥有武器", "price": 10, "sold": false}
	var card: Button = _duel.hud._cards.shop_card(offer)
	_ok(card.disabled, "局外已拥有但未装备 → 商店卡禁用")
	var status: String = String((card.get_node("Center/VBox/StatusLabel") as Label).text)
	_ok(status.contains("已拥有"), "商店卡显示已拥有（%s）" % status)

	# 点击不扣款、不重复写入
	_duel.gold = 500
	var gold_before: int = _duel.gold
	var owned_before: int = (_duel.meta.get("owned_weapons", []) as Array).size()
	_duel._shop_system.on_shop_buy_pressed(offer)
	_ok(_duel.gold == gold_before, "点击局外已拥有武器不扣款")
	_ok((_duel.meta.get("owned_weapons", []) as Array).size() == owned_before,
		"不重复写入 owned_weapons")

	_finish()

func _finish() -> void:
	print("F16BOUNDARY RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
