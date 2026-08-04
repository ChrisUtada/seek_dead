class_name BattleMath
extends RefCounted
# 纯结算数学（P0 抽取自 duel_controller.gd）
# 设计：所有函数只进参数、出返回值，不碰 hud / 节点 / UI。
# 调用方（DuelController）保留同名薄包装，零行为变化，可单独 F6 验证数值一致。
# 详见 docs/代码审查与优化建议.md「问题1 / 阶段 P0」。

# —— 加法型增益聚合（按 effect 汇总 player_buffs）——
static func buff_sum(player_buffs: Dictionary, effect: String) -> float:
	var v := 0.0
	for sym in player_buffs.keys():
		if sym.buff_effect == effect:
			v += sym.buff_value
	return v

static func buff_power(player_buffs: Dictionary) -> float:
	return buff_sum(player_buffs, "power")

static func buff_shield(player_buffs: Dictionary) -> float:
	return buff_sum(player_buffs, "shield")

static func buff_regen(player_buffs: Dictionary) -> float:
	return buff_sum(player_buffs, "regen")

# 乘法型增益（多个同时生效则连乘）
static func buff_damage_mult(player_buffs: Dictionary) -> float:
	var m := 1.0
	for sym in player_buffs.keys():
		if sym.buff_effect == "damage_mult":
			m *= sym.buff_value
	return m

static func buff_summary(player_buffs: Dictionary) -> String:
	if player_buffs.is_empty():
		return "无"
	var parts: Array = []
	for sym in player_buffs.keys():
		parts.append("%s%d" % [sym.label, int(player_buffs[sym])])
	return " ".join(parts)

static func buff_effect_name(effect: String) -> String:
	match effect:
		"power":       return "伤害符号加成"
		"shield":      return "每回合护盾"
		"regen":       return "每回合回血"
		"damage_mult": return "总伤害倍率"
		_:             return effect

# —— 本局全局乘区聚合 ——
static func agg_power_flat(run_power_bonus: int, charm_power_bonus: int, player_buffs: Dictionary, gold_upgrades: Dictionary, power_step: int) -> float:
	return float(run_power_bonus) + float(charm_power_bonus) + buff_power(player_buffs) + float(gold_upgrades["power"]) * power_step

static func agg_shield(player_buffs: Dictionary, charm_shield_trickle: int) -> float:
	return buff_shield(player_buffs) + float(charm_shield_trickle)

static func agg_regen(player_buffs: Dictionary, charm_heal_trickle: int) -> float:
	return buff_regen(player_buffs) + float(charm_heal_trickle)

static func agg_damage_mult(charm_damage_mult: float, player_buffs: Dictionary, gold_upgrades: Dictionary, joker_step: float, joker_cap_factor: float) -> float:
	var j: float = 1.0 + min(float(gold_upgrades["joker"]) * joker_step, joker_cap_factor - 1.0)
	return charm_damage_mult * buff_damage_mult(player_buffs) * j

static func agg_symbol_weight_mod(run_symbol_bonus: Dictionary, sym) -> float:
	return float(run_symbol_bonus.get(sym.resource_path, 0.0))

# —— 状态符号查询（基于 pool）——
static func status_base(pool: Array, type_str: String) -> float:
	for p in pool:
		var d: SymbolData = p[0]
		if d.kind == "status" and d.status_type == type_str:
			return d.base
	return 0.0

static func status_element(pool: Array, st: String) -> String:
	for p in pool:
		var d: SymbolData = p[0]
		if d.kind == "status" and d.status_type == st:
			return d.element
	return "none"

static func status_summary(stacks: Dictionary, status_names: Dictionary) -> String:
	var parts: Array = []
	for st in stacks.keys():
		parts.append("%s+%d" % [status_names.get(st, st), stacks[st]])
	return "/".join(parts)
