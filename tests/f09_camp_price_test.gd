extends Node

# ============================================================================
# F-09 营地价格验收（真实 _camp_offer / _camp_buy 链）
#
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/f09_camp_price_test.tscn
# 隔离：必须由外部覆盖 APPDATA 到临时目录后再运行，绝不触碰真实存档。
#
# 目标：营地补给走真实链时，报价（_camp_offer.price）、应付（shop_price 目录价）、
#       实际扣款三者一致；固定目录价下营地与商店同源同价。
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
	_duel.board_config.enabled = true
	_duel.board.generate(_duel.board_config)
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


# 从护符目录找一把本局未持有的护符（确定性，不依赖随机货架）
func _unheld_charm(exclude: Array = []) -> String:
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


# 真实营地链：报价 = 目录价，应付 = 报价，实际扣款 = 报价
func _test_camp_buy_chain() -> void:
	_duel.gold = 500
	# 用护符（hard cap 3、初始 1，营地链不会弹武器替换层）
	var path: String = _unheld_charm()
	_check(path != "", "找到营地可购买护符（%s）" % path.get_file())
	if path == "":
		return
	# 真实 _camp_offer 生成报价
	var offer: Dictionary = _duel._camp_offer(path, "passive")
	var quoted: int = int(offer.get("price", -1))
	var catalog: int = _duel._shop_system.shop_price("passive", -1, path)
	_check(quoted == catalog, "营地报价 = 固定目录价（报价 %d / 目录价 %d）" % [quoted, catalog])
	# 真实 _camp_buy 扣款
	var gold_before: int = _duel.gold
	_duel._camp_buy(offer.duplicate())
	var spent: int = gold_before - _duel.gold
	_check(spent > 0, "营地购买实际扣款（%d）" % spent)
	_check(spent == quoted, "应付报价 = 实际扣款（报价 %d / 扣款 %d）" % [quoted, spent])


# 营地与商店同源：同一物品在两条真实路径下扣款一致
func _test_camp_shop_same_price() -> void:
	_duel.gold = 500
	var path: String = _unheld_charm()
	if path == "":
		_check(false, "找不到可购买护符")
		return
	var camp_offer: Dictionary = _duel._camp_offer(path, "passive")
	var shop_offer: Dictionary = {
		"path": path, "kind": "passive", "name": "测试",
		"price": _duel._shop_system.shop_price("passive", -1, path), "sold": false}
	_check(int(camp_offer["price"]) == int(shop_offer["price"]),
		"营地/商店同一物品报价一致（%d / %d）" % [int(camp_offer["price"]), int(shop_offer["price"])])


func _run() -> void:
	_test_camp_buy_chain()
	_test_camp_shop_same_price()


func _finish() -> void:
	print("---")
	print("F09CAMP RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
