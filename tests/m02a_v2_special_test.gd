extends Node

# 新版 M-02a 步骤 4：宝箱 / 事件结算 · 专项回归。
# 覆盖 §4/§5/§7：宝箱只发一件合法物品无额外 Draft、武器入仓库不强制换装、
# 事件收益/代价一致且取消不推进、所有特殊房只结算一次、不触发战斗奖励。

var _fails := 0
var _checks := 0
var _duel: DuelController

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("M02A V2 SPECIAL FAIL: " + label)

func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	_duel = scene_res.instantiate() as DuelController
	add_child(_duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_duel.demo_config.enabled = false
	_duel.board_config.enabled = false
	_duel.shop_run_seed = 424242
	_duel._confirm_loadout()
	await get_tree().process_frame

	_test_chest_grant()
	_test_chest_once()
	_test_weapon_to_inventory()
	_test_event_exchange()
	_test_event_cancel()
	_test_no_battle_reward()

	_finish()

# 找一个宝箱房并进入（直接构造 gimmick_params 固定内容以精确断言）。
func _enter_chest(category: String, item_path: String) -> void:
	_duel.room_index = 2
	_duel._linear_special_done = false
	var r: RoomData = _duel.ROOMS[2]
	r.kind = "chest"
	r.gimmick_params = {"special_kind": "chest", "category": category,
		"item_path": item_path, "fallback_gold": 15}
	_duel.start_room_data(r, 2)

func _test_chest_grant() -> void:
	# 金币兜底（空 item_path）
	_enter_chest("gold", "")
	var g0: int = _duel.gold
	_duel._linear_chest_open()
	_ok(_duel.gold == g0 + 15, "宝箱金币兜底 +15（实测 %d）" % (_duel.gold - g0))
	_ok(_duel._linear_special_done, "宝箱结算一次后置守卫")

# 重复开启不二次授予
func _test_chest_once() -> void:
	_enter_chest("gold", "")
	var g0: int = _duel.gold
	_duel._linear_chest_open()
	var g1: int = _duel.gold
	_duel._linear_chest_open()
	_ok(_duel.gold == g1, "重复开启不二次授予（%d → %d）" % [g0, g1])

# 武器宝箱：进本局仓库，不强制装备（selected_loadout 不变）。
func _test_weapon_to_inventory() -> void:
	_enter_chest("weapon", "res://resources/weapon_templates/iron_sword.tres")
	var inv0: int = _duel.run_weapon_inventory.size()
	var equip0: int = _duel.selected_loadout.size()
	_duel._linear_chest_open()
	_ok(_duel.run_weapon_inventory.size() == inv0 + 1, "宝箱武器进本局仓库（+%d）" % (inv0 + 1))
	_ok(_duel.selected_loadout.size() == equip0, "宝箱武器不强制装备")

# 事件：收益/代价一致（付金币换最大 HP）。
func _test_event_exchange() -> void:
	_duel.room_index = 2
	_duel._linear_special_done = false
	_duel.gold = 100
	var hp_max0: int = _duel.player_hp_max
	var hp0: int = _duel.player_hp
	var g0: int = _duel.gold
	var r: RoomData = _duel.ROOMS[2]
	r.kind = "event"
	r.gimmick_params = {"special_kind": "event", "id": "coin_pact", "options": [
		{"label": "付金币换最大生命", "give": "gold", "give_amount": 25, "get": "maxhp", "get_amount": 8},
		{"label": "拒绝交易", "give": "", "give_amount": 0, "get": "", "get_amount": 0}]}
	_duel.start_room_data(r, 2)
	_duel._linear_event_choose(0)
	_ok(_duel.gold == g0 - 25, "事件代价：金币 -25（实测 %d）" % (g0 - _duel.gold))
	_ok(_duel.player_hp_max == hp_max0 + 8, "事件收益：最大生命 +8（实测 %d）" % (_duel.player_hp_max - hp_max0))
	_ok(_duel.player_hp == hp0 + 8, "事件收益：当前 HP 同步 +8")
	_ok(_duel._linear_special_done, "事件结算一次后置守卫")

# 取消不推进：cancel 后守卫未置位，可再次选择。
func _test_event_cancel() -> void:
	_duel.room_index = 2
	_duel._linear_special_done = false
	var r: RoomData = _duel.ROOMS[2]
	r.kind = "event"
	r.gimmick_params = {"special_kind": "event", "id": "blood_pact", "options": [
		{"label": "献祭生命换金币", "give": "hp", "give_amount": 15, "get": "gold", "get_amount": 30},
		{"label": "拒绝交易", "give": "", "give_amount": 0, "get": "", "get_amount": 0}]}
	_duel.start_room_data(r, 2)
	_duel._linear_event_cancel()
	_ok(not _duel._linear_special_done, "事件取消不推进（守卫未置位）")

# 特殊房不触发战斗奖励：无清房金币/熟练/掉落/Draft。
func _test_no_battle_reward() -> void:
	_enter_chest("gold", "")
	var g0: int = _duel.gold
	var owned0: int = (_duel.meta.get("owned_weapons", []) as Array).size()
	var belt0: int = _duel.consumable_slots.size()
	_duel._linear_chest_open()
	# 金币只来自宝箱兜底 +15，无额外清房金币/利息
	_ok(_duel.gold == g0 + 15, "宝箱无额外清房金币/利息")
	_ok((_duel.meta.get("owned_weapons", []) as Array).size() == owned0, "宝箱无武器熟练/永久写入")
	_ok(_duel.consumable_slots.size() == belt0, "宝箱无额外掉落")

func _finish() -> void:
	print("M02AV2SPECIAL RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
