extends Node

# ============================================================================
# T0-3 专项：事件取消、放弃与支付能力（docs/Seek_Dead_T0_当前缺陷返工与执行指令_2026-11-22.md §4）
#
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t0_event_semantics_test.tscn
# 隔离：必须由外部覆盖 APPDATA 到临时目录后再运行，绝不触碰真实存档。
#
# 目标语义：
#   取消 = 留在事件页、不结算、不推进，之后仍可选择；
#   放弃 = 不获得、不支付、推进；
#   合法选项 = 应用一次收益/代价后推进；
#   支付不足 = 选项禁用并说明原因（不展示到点击才失败）；
#   无合法选项 = 明确空状态并允许继续；
#   取消与放弃不得共用含义相反的按钮文案。
#
# 本测试只用 HUD 真实按钮 + 控制器公开状态驱动，不引用尚不存在的方法名，
# 以便修改前可编译运行、真实暴露缺陷。
# ============================================================================

const COIN_PACT := {"special_kind": "event", "id": "coin_pact", "options": [
	{"label": "付金币换最大生命", "give": "gold", "give_amount": 25, "get": "maxhp", "get_amount": 8},
	{"label": "拒绝交易", "give": "", "give_amount": 0, "get": "", "get_amount": 0}]}
const BLOOD_PACT := {"special_kind": "event", "id": "blood_pact", "options": [
	{"label": "献祭生命换金币", "give": "hp", "give_amount": 15, "get": "gold", "get_amount": 30},
	{"label": "拒绝交易", "give": "", "give_amount": 0, "get": "", "get_amount": 0}]}

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
	_duel.shop_run_seed = 20261123
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


func _enter_event(params: Dictionary) -> void:
	_duel.room_index = 2
	_duel._linear_special_done = false
	var r: RoomData = _duel.ROOMS[2]
	r.kind = "event"
	r.gimmick_params = params
	_duel.start_room_data(r, 2)


# 收集事件弹层所有按钮 [{text, disabled, btn}]
func _special_buttons() -> Array:
	var out: Array = []
	var hud = _duel.hud
	if hud._special_dialog == null or hud._special_vbox == null:
		return out
	for c in hud._special_vbox.get_children():
		if c is Button:
			out.append({"text": String((c as Button).text), "disabled": (c as Button).disabled, "btn": c})
	return out


func _button_by_keyword(keyword: String) -> Dictionary:
	for b in _special_buttons():
		if String(b["text"]).contains(keyword):
			return b
	return {}


func _press_button(b: Dictionary) -> void:
	if not b.is_empty() and not bool(b["disabled"]):
		(b["btn"] as Button).pressed.emit()


func _labels_text() -> String:
	var out := ""
	var hud = _duel.hud
	if hud._special_dialog == null or hud._special_vbox == null:
		return out
	for c in hud._special_vbox.get_children():
		if c is Label:
			out += String((c as Label).text) + "\n"
	return out


func _run() -> void:
	_test_legal_and_refuse()
	_test_gold_shortage()
	_test_hp_shortage()
	_test_exact_boundary()
	_test_cancel_then_choose()
	_test_cancel_then_abandon()
	_test_hp_boundary()
	_test_abandon()
	_test_empty_options()
	_test_shortage_guard_no_advance()
	_test_no_battle_reward()


# 合法支付 + 拒绝交易 + 重复点击
func _test_legal_and_refuse() -> void:
	_duel.gold = 100
	var hp_max0: int = _duel.player_hp_max
	_enter_event(COIN_PACT)
	var pay: Dictionary = _button_by_keyword("付金币换最大生命")
	_check(not pay.is_empty() and not bool(pay.get("disabled", true)), "合法 支付选项可用")
	_press_button(pay)
	_check(_duel.gold == 75, "合法 金币 -25（实测 %d）" % (_duel.gold - 100))
	_check(_duel.player_hp_max == hp_max0 + 8, "合法 最大生命 +8（实测 %d）" % (_duel.player_hp_max - hp_max0))
	_check(_duel._linear_special_done, "合法 结算一次后置守卫")
	var g_once: int = _duel.gold
	_duel._linear_event_choose(0)   # 重复点击
	_check(_duel.gold == g_once, "合法 重复点击不重复扣款（实测 %d）" % (_duel.gold - 100))


# 金币不足：选项禁用并说明，拒绝交易仍可用
func _test_gold_shortage() -> void:
	_duel.gold = 10
	_enter_event(COIN_PACT)
	var pay: Dictionary = _button_by_keyword("付金币换最大生命")
	_check(not pay.is_empty(), "金币不足 支付选项仍显示")
	_check(bool(pay.get("disabled", false)), "金币不足 支付选项被禁用")
	_check(String(pay.get("text", "")).contains("不足"), "金币不足 选项说明原因（实测：%s）" % String(pay.get("text", "")))
	var refuse: Dictionary = _button_by_keyword("拒绝交易")
	_check(not refuse.is_empty() and not bool(refuse.get("disabled", true)), "金币不足 拒绝交易仍可用")
	var g0: int = _duel.gold
	_press_button(refuse)
	_check(_duel.gold == g0, "金币不足 拒绝交易不扣款")
	_check(_duel._linear_special_done, "金币不足 拒绝交易推进")


# 生命不足：支付选项禁用并说明
func _test_hp_shortage() -> void:
	_duel.player_hp = 10
	_duel.player_hp_max = 100
	_enter_event(BLOOD_PACT)
	var pay: Dictionary = _button_by_keyword("献祭生命换金币")
	_check(not pay.is_empty(), "生命不足 支付选项仍显示")
	_check(bool(pay.get("disabled", false)), "生命不足 支付选项被禁用")
	_check(String(pay.get("text", "")).contains("不足"), "生命不足 选项说明原因（实测：%s）" % String(pay.get("text", "")))


# 边界：金币恰好等于代价应允许；金币少 1 点应禁用
func _test_exact_boundary() -> void:
	_duel.gold = 25
	_enter_event(COIN_PACT)
	var pay: Dictionary = _button_by_keyword("付金币换最大生命")
	_check(not pay.is_empty() and not bool(pay.get("disabled", true)), "金币恰好等于代价 选项可用")
	_press_button(pay)
	_check(_duel.gold == 0, "金币恰好等于代价 支付后为 0（实测 %d）" % _duel.gold)
	_duel.gold = 24
	_enter_event(COIN_PACT)
	var pay2: Dictionary = _button_by_keyword("付金币换最大生命")
	_check(bool(pay2.get("disabled", false)), "金币少 1 点 选项禁用")


# 取消：留在事件页、不结算、不推进，之后仍可选择
func _test_cancel_then_choose() -> void:
	_duel.gold = 100
	_enter_event(COIN_PACT)
	var cancel: Dictionary = _button_by_keyword("取消")
	_check(not cancel.is_empty(), "取消 找到取消按钮")
	_check(not String(cancel.get("text", "")).contains("继续"), "取消 按钮文案不含「继续」（避免语义混淆，实测：%s）" % String(cancel.get("text", "")))
	var g0: int = _duel.gold
	_press_button(cancel)
	_check(not _duel._linear_special_done, "取消 不推进（守卫未置位）")
	_check(_duel.gold == g0, "取消 不扣款")
	_check(_duel.hud._special_dialog.visible, "取消 事件弹层仍可见（留在事件页）")
	# 取消后仍可选择
	var pay: Dictionary = _button_by_keyword("付金币换最大生命")
	_check(not pay.is_empty() and not bool(pay.get("disabled", true)), "取消后 支付选项仍可选择")
	_press_button(pay)
	_check(_duel._linear_special_done, "取消后选择 正常结算推进")


# 审查修正②：取消后放弃入口仍存在、可用；点击后不扣资源、不发收益、推进且不重复领取
func _test_cancel_then_abandon() -> void:
	_duel.gold = 100
	var hp_max0: int = _duel.player_hp_max
	_enter_event(COIN_PACT)
	var cancel: Dictionary = _button_by_keyword("取消")
	_press_button(cancel)
	_check(_duel.hud._special_dialog.visible, "取消后放弃 仍在事件页")
	var abandon: Dictionary = _button_by_keyword("放弃")
	_check(not abandon.is_empty(), "取消后放弃 放弃按钮仍存在")
	_check(not bool(abandon.get("disabled", true)), "取消后放弃 放弃按钮可用")
	var g0: int = _duel.gold
	_press_button(abandon)
	_check(_duel.gold == g0, "取消后放弃 不扣资源（金币不变）")
	_check(_duel.player_hp_max == hp_max0, "取消后放弃 不发收益（最大生命不变）")
	_check(_duel._linear_special_done, "取消后放弃 正常推进（守卫置位）")
	_duel._linear_event_choose(0)
	_check(_duel.gold == g0, "取消后放弃 不能再次领取（不重复扣款/发放）")


# 审查修正③：HP 边界（BLOOD_PACT 代价 15 HP，收益 30 金币）
# HP=16 可用→支付后 HP=1、金币+30；HP=15 禁用（非致死支付）；HP=14 禁用。全走 HUD 按钮。
func _test_hp_boundary() -> void:
	# HP=16，代价 15：可用
	_duel.player_hp = 16
	_duel.player_hp_max = 100
	_duel.gold = 0
	_enter_event(BLOOD_PACT)
	var pay16: Dictionary = _button_by_keyword("献祭生命换金币")
	_check(not pay16.is_empty() and not bool(pay16.get("disabled", true)), "HP边界 HP=16 选项可用")
	_press_button(pay16)
	_check(_duel.player_hp == 1, "HP边界 HP=16 支付后 HP=1（实测 %d）" % _duel.player_hp)
	_check(_duel.gold == 30, "HP边界 HP=16 支付后金币 +30（实测 %d）" % _duel.gold)

	# HP=15，代价 15：恰好等于代价，按非致死支付规则禁用
	_duel.player_hp = 15
	_duel.player_hp_max = 100
	_duel.gold = 0
	_enter_event(BLOOD_PACT)
	var pay15: Dictionary = _button_by_keyword("献祭生命换金币")
	_check(not pay15.is_empty(), "HP边界 HP=15 选项仍显示")
	_check(bool(pay15.get("disabled", false)), "HP边界 HP=15 恰好等于代价 选项禁用")
	_check(String(pay15.get("text", "")).contains("不足"), "HP边界 HP=15 说明不足原因（实测：%s）" % String(pay15.get("text", "")))

	# HP=14，代价 15：禁用
	_duel.player_hp = 14
	_duel.player_hp_max = 100
	_enter_event(BLOOD_PACT)
	var pay14: Dictionary = _button_by_keyword("献祭生命换金币")
	_check(bool(pay14.get("disabled", false)), "HP边界 HP=14 选项禁用")


# 放弃：不获得、不支付、推进；有独立按钮且文案不混淆
func _test_abandon() -> void:
	_duel.gold = 100
	var hp_max0: int = _duel.player_hp_max
	_enter_event(COIN_PACT)
	var abandon: Dictionary = _button_by_keyword("放弃")
	_check(not abandon.is_empty(), "放弃 找到独立的放弃按钮")
	_check(String(abandon.get("text", "")).contains("放弃"), "放弃 按钮文案明确（实测：%s）" % String(abandon.get("text", "")))
	var g0: int = _duel.gold
	_press_button(abandon)
	_check(_duel.gold == g0, "放弃 不支付（金币不变）")
	_check(_duel.player_hp_max == hp_max0, "放弃 不获得（最大生命不变）")
	_check(_duel._linear_special_done, "放弃 推进（守卫置位）")
	# 放弃后不能再次领取
	_duel._linear_event_choose(0)
	_check(_duel.gold == g0, "放弃后 不能再次领取（不重复扣款/发放）")


# 无合法选项：明确空状态并允许继续
func _test_empty_options() -> void:
	_enter_event({"special_kind": "event", "id": "none", "options": [], "empty": true})
	var txt: String = _labels_text() + " "
	for b in _special_buttons():
		txt += String(b["text"]) + " "
	_check(txt.contains("没有合法选项") or txt.contains("空") or txt.contains("继续"), "无选项 显示明确空状态/继续入口（实测：%s）" % txt.replace("\n", " | "))
	var cont: Dictionary = _button_by_keyword("继续")
	if cont.is_empty():
		cont = _button_by_keyword("跳过")
	_check(not cont.is_empty(), "无选项 存在继续/跳过入口")
	_press_button(cont)
	_check(_duel._linear_special_done, "无选项 继续后推进")


# 支付不足的二次守护：不得白白推进（应留下让玩家重选）
func _test_shortage_guard_no_advance() -> void:
	_duel.gold = 10
	_enter_event(COIN_PACT)
	_duel._linear_event_choose(0)   # 绕过 UI 直接触发不足选项
	_check(not _duel._linear_special_done, "支付不足 二次守护不推进（守卫未置位）")
	var g: int = _duel.gold
	_check(g == 10, "支付不足 二次守护不扣款（实测 %d）" % g)
	_check(_duel.hud._special_dialog.visible, "支付不足 事件弹层仍可见（允许重选）")


# 事件不触发战斗结算
func _test_no_battle_reward() -> void:
	_duel.gold = 100
	_enter_event(COIN_PACT)
	var owned0: int = (_duel.meta.get("owned_weapons", []) as Array).size()
	var belt0: int = _duel.consumable_slots.size()
	var g0: int = _duel.gold
	_duel._linear_event_choose(0)
	_check((_duel.meta.get("owned_weapons", []) as Array).size() == owned0, "事件不写 owned/weapons")
	_check(_duel.consumable_slots.size() == belt0, "事件不发掉落/腰带")
	_check(_duel.gold == g0 - 25, "事件金币变化只来自代价（实测 %d）" % (_duel.gold - g0))


func _finish() -> void:
	print("---")
	print("T0-3 RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
