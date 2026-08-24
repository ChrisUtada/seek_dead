class_name LoadoutSystem
extends RefCounted

# T22：平衡常量收敛于 BalanceConfig（balance_config.tres）
const BALANCE = preload("res://resources/config/balance_config.tres")

# 整备勾选 / 槽位上限与成长 / 拥有池读取——从 duel_controller.gd 抽出。
#
# 由 controller 在 _ready 处实例化并注入：LoadoutSystem.new(ctrl)。
# 约定（与 docs/[已完成]duel_controller拆分方案B.md 步骤5一致，延续步骤1–4 的写法）：
# - 勾选状态 selected_loadout / selected_consumables / selected_charms / selected_skills 与槽位上限
#   loadout_max / skill_max / charm_max 仍由 controller 持有，本子系统经 _ctrl.xxx 读写（方案B §4 状态归属表）。
# - @export 常量（SLOT_INIT / CHARM_CAP / UNCAPPED / LOADOUT_MIN 等）留 controller，
#   本子系统动态读 _ctrl.xxx（RefCounted 无法在 Inspector 编辑）。
# - P2 架构还债（2026-08-24）推翻旧「战斗强耦合留 controller」决策：_confirm_loadout / _apply_charms /
#   _full_reset / _reset_run_state 迁入本子系统（controller 留单行转发器）；charm_* 战斗字段仍由 controller 持有，经 _ctrl 读写。
# - ctrl 标类型 DuelController（已加 class_name），成员访问获得编译期检查。

var _ctrl: DuelController          # DuelController 实例（类型标注，编译期检查）

func _init(ctrl: DuelController) -> void:
	_ctrl = ctrl


# ---------------------------------------------------------------------------
# 整备勾选
# ---------------------------------------------------------------------------

func on_card_toggled(card: Dictionary) -> void:
	var cat = card.kind
	var arr = sel_arr(cat)
	if card["selected"]:
		card["selected"] = false
		arr.erase(card["path"])
	else:
		if arr.size() >= cat_max(cat):
			_ctrl.hud._log("%s已达上限 %d" % [cat_name(cat), cat_max(cat)])
			return
		card["selected"] = true
		arr.append(card["path"])
	_ctrl.hud._update_loadout_cards_visual()
	_ctrl.hud._update_loadout_count()
	_ctrl.invalidate_state()


func sel_arr(cat: String) -> Array:
	match cat:
		"weapon":  return _ctrl.selected_loadout
		"active":  return _ctrl.selected_consumables
		"passive": return _ctrl.selected_charms
		"skill":    return _ctrl.selected_skills
	return []


# 该类【当前】上限（随商店「买即开槽」成长）
func cat_max(cat: String) -> int:
	match cat:
		"weapon":  return _ctrl.loadout_max
		"active":  return int(BALANCE.slot_init["active"])   # 整备勾选上限 = 1（腰带容量见 CONSUMABLE_CAP）
		"passive": return _ctrl.charm_max
		"skill":    return _ctrl.skill_max
	return 0


# 该类【天花板】（当前上限的成长终点）。返回 UNCAPPED(-1) 表示无天花板（进池类）。
func cat_cap(cat: String) -> int:
	match cat:
		"weapon":  return 2   # 2026-08-07 用户拍板：武器上限 2（主手+副手），商店不可买第 3 把
		"skill":    return 3   # 2026-08-10 用户拍板：技能槽硬上限 3（初始 1 → 商店买到 3 封顶）——防技能符号无限挤占主输出带子（武器硬限 2 的不对称稀释，见 docs/[已完成]整备结构_技能槽上限与频率规范.md）
		"active":  return int(BALANCE.slot_init["active"])   # 整备天花板 = 1（消耗品不「买即开槽」，改为腰带追加，容量见 CONSUMABLE_CAP）
		"passive": return _ctrl.CHARM_CAP
	return 0


# 该类是否还能继续「买即开槽」（无天花板恒为 true）
func can_grow_slot(cat: String) -> bool:
	var ceiling = cat_cap(cat)
	return ceiling == _ctrl.UNCAPPED or cat_max(cat) < ceiling


# 天花板的显示文本（无天花板显示 ∞），供日志与 UI 复用
func cap_text(cat: String) -> String:
	var ceiling = cat_cap(cat)
	return "∞" if ceiling == _ctrl.UNCAPPED else str(ceiling)


# 「买即开槽」：把该类当前上限 +1（有天花板则不越过）
func grow_slot(cat: String) -> void:
	var ceiling = cat_cap(cat)
	match cat:
		"weapon":  _ctrl.loadout_max = (_ctrl.loadout_max + 1 if ceiling == _ctrl.UNCAPPED else min(_ctrl.loadout_max + 1, ceiling))
		"skill":   _ctrl.skill_max   = (_ctrl.skill_max + 1 if ceiling == _ctrl.UNCAPPED else min(_ctrl.skill_max + 1, ceiling))
		"passive": _ctrl.charm_max   = min(_ctrl.charm_max + 1, ceiling)
	_ctrl.invalidate_state()


func cat_name(cat: String) -> String:
	match cat:
		"weapon":  return "武器"
		"active":  return "消耗品"
		"passive": return "护符"
		"skill":    return "技能"
	return cat


func owned_arr(kind: String) -> Array:
	# 整备屏/商店读取拥有池（盘外跨局）。skills 暂用全池（待扩 owned_skills）。
	match kind:
		"weapon":  return _ctrl.meta["owned_weapons"]
		"passive": return _ctrl.meta["owned_charms"]
		"active":  return _ctrl.meta["owned_consumables"]
		"skill":   return _ctrl.SKILL_POOL
		_:         return []


# ---------------------------------------------------------------------------
# P2 架构还债（2026-08-24）：整备确认 / 护符被动 / 局重置（自 duel_controller 迁入）
# ---------------------------------------------------------------------------

# 整备确认：勾选清单 → 腰带实例化 → 开新局。低于最小携带数直接忽略（UI 已拦截，此处兜底）。
func confirm_loadout() -> void:
	if _ctrl.selected_loadout.size() < _ctrl.LOADOUT_MIN:
		return
	# 消耗品：整备确认时把去重勾选清单实例化为腰带格（每格独立 charges；允许后续商店重复购买同类）
	# 泛型数组属性跨对象只能 clear()/assign()，不能整体赋 []（运行时类型检查会拒绝）
	_ctrl.consumable_slots.clear()
	for path in _ctrl.selected_consumables:
		var cd: Resource = load(path)
		if cd != null:
			_ctrl._consumable_uid += 1
			_ctrl.consumable_slots.append({"path": path, "item_id": cd.item_id, "charges": cd.charges, "uid": "c%d" % _ctrl._consumable_uid})
	_ctrl.hud._hide_loadout_screen()
	full_reset()
	_ctrl.invalidate_state()   # consumable_slots 已重实例化


# 结算护符被动（整局生效）：每次开房/换装重算全部 charm_* 字段（含混合护符负面效果与乘区封顶）。
func apply_charms() -> void:
	_ctrl.charm_power_bonus = 0
	_ctrl.charm_room_shield = 0
	_ctrl.charm_interf_resist = 0
	_ctrl.charm_damage_mult = 1.0
	_ctrl.charm_shield_trickle = 0
	_ctrl.charm_heal_trickle = 0
	_ctrl.charm_pierce_chance = 0.0
	_ctrl.charm_element_boost = 0.0
	_ctrl.charm_status_boost = 1.0
	_ctrl.charm_dot_reduce = 0
	_ctrl.charm_thorns = 0.0
	_ctrl.charm_dot_amp = 0
	_ctrl.charm_free_reroll = 0
	_ctrl.charm_charge_start = 0
	_ctrl.charm_first_hit = 1.0
	for path in _ctrl.selected_charms:
		var cd: Resource = load(path)
		if cd == null:
			continue
		match cd.effect:
			"damage_bonus":         _ctrl.charm_power_bonus += cd.value
			"room_shield":          _ctrl.charm_room_shield += cd.value
			"interference_resist":  _ctrl.charm_interf_resist += cd.value
			"shield":               _ctrl.charm_shield_trickle += cd.value   # 守备护符：每回合护盾涓流
			"heal":                _ctrl.charm_heal_trickle += cd.value    # 回春护符：每回合回复
			"damage_mult":
				_ctrl.charm_damage_mult *= cd.mult_value   # 护符乘数增值（封顶在循环后）
			"armor_pierce":          _ctrl.charm_pierce_chance = max(_ctrl.charm_pierce_chance, cd.mult_value)   # 破甲护符（T2）：取最高穿透概率
			"element_boost":         _ctrl.charm_element_boost += cd.mult_value                            # 元素优势护符（T2）：克制倍率加法叠加
			"status_boost":          _ctrl.charm_status_boost *= cd.mult_value                             # 状态护符（T2）：DoT 乘数
			"dot_reduce":           _ctrl.charm_dot_reduce += cd.value                                    # 蚀毒壁垒护符（2026-08-09）：玩家侧挂毒量 -N/回合
			"thorns":               _ctrl.charm_thorns = max(_ctrl.charm_thorns, cd.mult_value)                 # 石屑之心（信物）：反弹比例取最高
			"dot_amp":              _ctrl.charm_dot_amp += cd.value                                       # 毒腺囊（信物）：挂 DoT 层数 +N
			"free_reroll":          _ctrl.charm_free_reroll += cd.value                                   # 迷宫回声（信物）：免费货架刷新次数
			"charge_start":         _ctrl.charm_charge_start += cd.value                                  # 深渊凝视（信物）：每回合开始充能 +N
			"first_hit":            _ctrl.charm_first_hit = max(_ctrl.charm_first_hit, cd.mult_value)           # 碎片王冠（信物）：首击倍率取最高
		# 混合护符的负面效果（未来卡用）：与正面同枚举、加成型数值取反、乘区型乘 downside_mult
		if cd.downside_effect != "":
			match cd.downside_effect:
				"damage_bonus":         _ctrl.charm_power_bonus -= cd.downside_value
				"room_shield":          _ctrl.charm_room_shield -= cd.downside_value
				"interference_resist":  _ctrl.charm_interf_resist -= cd.downside_value
				"shield":               _ctrl.charm_shield_trickle -= cd.downside_value
				"heal":                _ctrl.charm_heal_trickle -= cd.downside_value
				"damage_mult":          _ctrl.charm_damage_mult *= cd.downside_mult
				"armor_pierce":         _ctrl.charm_pierce_chance = max(0.0, _ctrl.charm_pierce_chance - cd.downside_value / 100.0)
				"element_boost":        _ctrl.charm_element_boost = max(0.0, _ctrl.charm_element_boost - cd.downside_mult)
				"status_boost":         _ctrl.charm_status_boost = max(1.0, _ctrl.charm_status_boost - (1.0 - cd.downside_mult))
				"dot_reduce":           _ctrl.charm_dot_reduce = max(0, _ctrl.charm_dot_reduce - cd.downside_value)
				"thorns":               _ctrl.charm_thorns = max(0.0, _ctrl.charm_thorns - cd.downside_mult)
				"dot_amp":              _ctrl.charm_dot_amp = max(0, _ctrl.charm_dot_amp - cd.downside_value)
				"free_reroll":          _ctrl.charm_free_reroll = max(0, _ctrl.charm_free_reroll - cd.downside_value)
				"charge_start":         _ctrl.charm_charge_start = max(0, _ctrl.charm_charge_start - cd.downside_value)
				"first_hit":            _ctrl.charm_first_hit = max(1.0, _ctrl.charm_first_hit - (1.0 - cd.downside_mult))
	# 总护符乘区硬上限（防失控膨胀）
	_ctrl.charm_damage_mult = min(_ctrl.charm_damage_mult, BALANCE.charm_mult_cap)
	var charm_log = "护符已装配：伤害+%d / 开局护盾+%d / 每回合护盾+%d / 每回合回血+%d / 抗扰+%d" % [_ctrl.charm_power_bonus, _ctrl.charm_room_shield, _ctrl.charm_shield_trickle, _ctrl.charm_heal_trickle, _ctrl.charm_interf_resist]
	if _ctrl.charm_damage_mult != 1.0:
		charm_log += " / 伤害×%s" % ElementCounter.fmt_mult(_ctrl.charm_damage_mult)
	if _ctrl.charm_pierce_chance > 0.0:
		charm_log += " / 破甲穿透 %d%%" % int(_ctrl.charm_pierce_chance * 100)
	if _ctrl.charm_element_boost > 0.0:
		charm_log += " / 元素优势+%s" % ElementCounter.fmt_mult(_ctrl.charm_element_boost)
	if _ctrl.charm_status_boost != 1.0:
		charm_log += " / 状态×%s" % ElementCounter.fmt_mult(_ctrl.charm_status_boost)
	if _ctrl.charm_dot_reduce > 0:
		charm_log += " / 蚀毒壁垒（挂毒量-%d/回合）" % _ctrl.charm_dot_reduce
	if _ctrl.charm_thorns > 0.0:
		charm_log += " / 荆棘反弹 %d%%" % int(_ctrl.charm_thorns * 100)
	if _ctrl.charm_dot_amp > 0:
		charm_log += " / 挂毒层+%d" % _ctrl.charm_dot_amp
	if _ctrl.charm_free_reroll > 0:
		charm_log += " / 免费刷新×%d" % _ctrl.charm_free_reroll
	if _ctrl.charm_charge_start > 0:
		charm_log += " / 充能+%d/回合" % _ctrl.charm_charge_start
	if _ctrl.charm_first_hit != 1.0:
		charm_log += " / 首击×%s" % ElementCounter.fmt_mult(_ctrl.charm_first_hit)
	_ctrl.hud._log(charm_log)
	_ctrl.invalidate_state()


# 整局重置：新局状态清零 + 抽房 + 建池 + 开首房（_confirm_loadout 入口）。
func full_reset() -> void:
	reset_run_state()
	_ctrl.ROOMS = _ctrl._build_run()
	_ctrl._build_pool(_ctrl.selected_loadout)
	_ctrl._start_room(0)
	_ctrl.invalidate_state()


# 新一局公共状态重置（不含开战）：full_reset 与战败回整备共用——槽位成长/金币/商店/奖励回到初始，
# 避免战败后整备页显示上局商店扩槽的上限（突破限制错觉）。
func reset_run_state() -> void:
	_ctrl._anvil_system.reset_run()   # 本局铁砧点数 drip 累计清零
	_ctrl.train_points = 0            # ⚠ 已废弃字段清零（训练点系统 2026-08-14 移除，保留字段兼容旧存档）
	# 2026-08-14 fix：新一局生命上限回基础值——体魄/局内奖励（maxhp/maxhp_heal）不跨局，
	# 否则战败回整备再出发时 player_hp_max 沿用上局膨胀值（曾出现 280+/100 的"HP 未重置"）。
	_ctrl.player_hp_max = int(BALANCE.player_hp_base)
	_ctrl.player_hp = _ctrl.player_hp_max
	_ctrl.in_interroom = false                     # opt-in 商店：新一局不可能处于房间歇态
	_ctrl.gold = 4                                 # S6：新一局金币清零（每局清零，见 §11）
	# 新一局四类槽位回到初始配额（商店「买即开槽」可再逐步扩至各自天花板）
	_ctrl.loadout_max = int(_ctrl.SLOT_INIT["weapon"])
	_ctrl.skill_max = int(_ctrl.SLOT_INIT["skill"])
	_ctrl.charm_max = int(_ctrl.SLOT_INIT["passive"])
	_ctrl._shop_system.reset_run()   # 商店状态清零（购入价记录 + 金币升级等级）
	_ctrl._reward_system.reset_run()   # 本局加成层清零（符号灌注 / 伤害加成 / 下一房护盾）
	_ctrl.invalidate_state()
