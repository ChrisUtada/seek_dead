class_name ConsumableSystem
extends RefCounted

# consumable_system — 消耗品使用系统（2026-08-09 从 duel_controller 拆分）
#
# 职责：腰带槽位守卫/定位/扣次、按 effect 分发效果（purify/heal/assault/reroll/element）、
# 空槽移除与面板刷新。
# 新增消耗品效果 = 在此文件加一个 use_xxx() 函数 + match 一行，controller 零改动。
#
# 状态共享：consumable_slots / enemy_intent / player_frost / player_hp / assault_next_spin /
# room_element_mult 等仍由 DuelController 持有，本系统经 _ctrl 读写（与 shop/reward 同模式）；
# 跨系统调用（重转 _free_spin、精华注入 _build_pool/reel_system）走 _ctrl。

var _ctrl  # DuelController


func _init(ctrl) -> void:
	_ctrl = ctrl


# 战斗中使用消耗品（HUD 腰带格点击入口：hud.consumable_used -> controller -> 本方法）
func use(uid: String) -> void:
	if _ctrl.in_loadout or _ctrl.in_interroom or _ctrl.game_state != DuelController.FlowState.PLAYING or _ctrl._busy:
		return
	var target = -1
	for i in range(_ctrl.consumable_slots.size()):
		if _ctrl.consumable_slots[i]["uid"] == uid:
			target = i
			break
	if target < 0:
		return
	var slot = _ctrl.consumable_slots[target]
	if slot["charges"] <= 0:
		_ctrl.hud._log("「%s」已用尽" % slot["item_id"])
		return
	var data: Resource = load(slot["path"])
	if data == null:
		return
	slot["charges"] -= 1
	match data.effect:
		"purify":  use_purify(data)
		"cleanse": use_cleanse(data)
		"heal":    use_heal(data)
		"assault": use_assault(data)
		"reroll":  await use_reroll(data)
		"element": use_element(data)
	# 勇者的阴影 P3 和解检测（heal/purify/cleanse 消耗品使用通知；显式判空）
	if _ctrl.current_gimmick != null:
		_ctrl.current_gimmick.on_consumable_used(_ctrl, str(data.effect))
	refresh_panel()
	if slot["charges"] <= 0:
		_ctrl.consumable_slots.remove_at(target)
		refresh_panel()   # 4 cell 永远在位，只刷状态；charges=0 槽位自动变空
		_ctrl.hud._log("「%s」已用尽，移出腰带（可于商店补给）" % slot["item_id"])
	_ctrl.hud._refresh_meta()


# 净化药剂（2026-08-09 职责收敛）：只抵消敌人干扰意图（T20：IntentData.purifiable）。
# 玩家侧状态（frost 冻结 / DoT 毒层）改由清净药剂（cleanse）解——净化不再跨「BOSS 侧 / 玩家侧」双职责。
func use_purify(data: Resource) -> void:
	var it_data: IntentData = _ctrl.enemy_intent.get("data")
	var purifiable: bool = it_data.purifiable if it_data != null else _ctrl.enemy_intent.get("type") in ["jam", "lock", "chaos"]
	if purifiable:
		var t = _ctrl.enemy_intent.get("type")
		_ctrl.enemy_intent = {"data": null, "type": "none", "value": 0}
		_ctrl.hud._log("净化药剂：抵消了敌人的%s" % _ctrl._intent_name(t))
	else:
		_ctrl.hud._log("净化药剂：当前无干扰意图可清除")


# 清净药剂（2026-08-09 新增）：解除玩家自身负面状态——frost 冻结解冻 + DoT 毒层清零。
# 职责单一：只作用于玩家侧，与净化药剂（敌人意图）分工。
func use_cleanse(data: Resource) -> void:
	var cleaned_any := false
	if _ctrl.player_frost > 0:
		_ctrl.player_frost = 0
		_ctrl.frozen_cols.clear()   # 动态 _ctrl 访问下不能直接赋 []（untyped 数组赋 typed Array[int] 字段会运行时类型错误）
		_ctrl.hud._log("清净药剂：驱散寒霜，冻结转轮恢复！")
		cleaned_any = true
	if int(_ctrl.player_status.get("poison", 0)) > 0:
		_ctrl.player_status["poison"] = 0
		_ctrl.hud._log("清净药剂：驱散酸蚀，毒层清零！")
		cleaned_any = true
	if not cleaned_any:
		_ctrl.hud._log("清净药剂：当前无寒霜/酸蚀可清除")


func use_heal(data: Resource) -> void:
	_ctrl.player_hp = mini(_ctrl.player_hp_max, _ctrl.player_hp + data.value)
	_ctrl.hud._log("治疗药剂：回复 %d HP（现 %d）" % [data.value, _ctrl.player_hp])


func use_assault(data: Resource) -> void:
	_ctrl.assault_next_spin = data.value
	_ctrl.hud._log("强袭药剂：下一次转轮伤害 ×%d" % data.value)


func use_reroll(data: Resource) -> void:
	# value = 重转次数（重转卷轴 1；赦免令 2——连转洗盘，天平审判官律法解）
	var times: int = maxi(1, int(data.value))
	_ctrl.hud._log("重转卷轴：免费重转 %d 次！" % times)
	for i in times:
		await _ctrl._free_spin()


# 元素精华：本房间内向转轮池注入对应元素攻击符号（多一种攻击方式），新房间失效
func use_element(data: Resource) -> void:
	if DuelController.ESSENCE_SYMBOLS.has(data.element):
		_ctrl.room_element_mult[data.element] = true
		_ctrl.hud._log("元素精华（%s）：转轮注入%s系攻击符号「%s」！" % [data.item_name, ElementCounter.label(data.element), DuelController.ESSENCE_SYMBOLS[data.element].name])
		_ctrl.hud._popup("✨%s符号入池" % ElementCounter.label(data.element), ElementCounter.color(data.element), _ctrl.hud._player_sprite_anchor())
		_ctrl._build_pool(_ctrl.selected_loadout)
		_ctrl.reel_system.build_strips()
		_ctrl.reel_system.reset_grid()
		_ctrl.hud._refresh_meta()


func refresh_panel() -> void:
	_ctrl.hud._refresh_consumable_panel()
