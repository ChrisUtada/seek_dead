class_name RewardEvaluator
extends RefCounted

# 战后三选一重构 P1 · 核心③：计算奖励的情境价值与协同评分。
#
# 纯函数模块（static），只读 RunSnapshot，不修改任何玩家状态、不依赖 HUD/Shop/Battle。
# 评分分解（v2.0 §7.3）：
#   OfferValue = BaseValue + ContextValue + SynergyValue + NoveltyValue + RiskRewardValue + ProgressionValue
# 各项必须封顶、可解释（v2.0 §18）；禁止 ML 或难以解释的复杂公式。
# 规则键名（def.context_rule / synergy_rule）映射到本文件的规则函数，
# 做到数据驱动——不为每张卡写 if/else（v2.0 §20.4）。

const CAP_BASE := 10.0
const CAP_CONTEXT := 10.0
const CAP_SYNERGY := 8.0
const CAP_NOVELTY := 3.0
const CAP_RISK := 5.0
const CAP_PROGRESSION := 3.0

const EFFECT_HEAL := "heal"


# 返回 {reward_id -> score(float)}，debug 模式下附各项明细。
static func score_all(defs: Array, snap: RunSnapshot, debug: bool = false) -> Dictionary:
	var out: Dictionary = {}
	var detail: Dictionary = {}
	for def in defs:
		if not (def is RewardDefinition):
			continue
		out[def.id] = score(def, snap)
		if debug:
			detail[def.id] = score_breakdown(def, snap)
	if debug:
		out["__detail__"] = detail
	return out


static func score(def: RewardDefinition, snap: RunSnapshot) -> float:
	var b := score_breakdown(def, snap)
	var total := 0.0
	for v in b.values():
		total += float(v)
	return total


static func score_breakdown(def: RewardDefinition, snap: RunSnapshot) -> Dictionary:
	return {
		"base": clampf(float(def.base_value), 0.0, CAP_BASE),
		"context": clampf(_context_value(def, snap), -CAP_CONTEXT, CAP_CONTEXT),
		"synergy": clampf(_synergy_value(def, snap), 0.0, CAP_SYNERGY),
		"novelty": clampf(_novelty_value(def, snap), 0.0, CAP_NOVELTY),
		"risk": clampf(_risk_value(def, snap), -CAP_RISK, CAP_RISK),
		"progression": clampf(_progression_value(def, snap), -CAP_PROGRESSION, CAP_PROGRESSION),
	}


# ---------------------------------------------------------------------------
# 各项评分
# ---------------------------------------------------------------------------

# 情境价值：按 context_rule 分派；默认只对治疗有反应。
static func _context_value(def: RewardDefinition, snap: RunSnapshot) -> float:
	match def.context_rule:
		"", "heal_by_hp": return _heal_context(def, snap)
		"income_by_gold": return _income_context(snap)
		_: return 0.0


# 治疗情境价值（契约 §7.4）：用有效恢复量避免满血浪费；低血高价值但不硬保底。
static func _heal_context(def: RewardDefinition, snap: RunSnapshot) -> float:
	if def.first_effect_id() != EFFECT_HEAL:
		return 0.0
	var hp_max := maxf(1.0, float(snap.survival.get("max_hp", 1)))
	var hp := float(snap.survival.get("current_hp", 0))
	var ratio := clampf(hp / hp_max, 0.0, 1.0)
	var heal_amount := 0.35 * hp_max   # 旧 heal 结算固定 35%（P2 从 params 读实际值）
	var effective_heal := minf(heal_amount, maxf(0.0, hp_max - hp))
	var efficiency := effective_heal / maxf(heal_amount, 0.0001)
	var band := 0.0
	if ratio <= 0.35:
		band = 6.0
	elif ratio <= 0.65:
		band = 3.0
	return band * efficiency


# 经济卡：金币少/临近商店时价值略升，避免无依据抬价。
static func _income_context(snap: RunSnapshot) -> float:
	var gold := snap.gold()
	return 1.0 if gold < 10 else 0.0


# 协同价值：按 synergy_rule 分派；只有与已形成构筑真实联动才加分，禁止同标签无限叠加。
static func _synergy_value(def: RewardDefinition, snap: RunSnapshot) -> float:
	var bs = snap.build_state
	if bs == null:
		return 0.0
	match def.synergy_rule:
		"", "build_tag": return _build_tag_synergy(def, bs)
		"fire": return 2.0 if bs.build_score("fire") >= 4 else 0.0
		_: return 0.0


static func _build_tag_synergy(def: RewardDefinition, bs: RunSnapshot.BuildState) -> float:
	var score := 0.0
	var hit := 0
	for tag in def.tags:
		var t := String(tag)
		if t.begins_with("build.") and bs.has_tag(t) and bs.tag_strength(t) >= 4.0:
			hit += 1
	# 单卡只加一次，不因多标签重复叠加
	if hit > 0:
		score = 2.0
	return score


# 新颖性：未形成的构筑种子给探索分，避免永远只推当前 Build。
static func _novelty_value(def: RewardDefinition, snap: RunSnapshot) -> float:
	var bs = snap.build_state
	if bs == null:
		return 0.0
	var seed_tags := 0
	for tag in def.tags:
		var t := String(tag)
		if t.begins_with("build.") and not bs.has_tag(t):
			seed_tags += 1
	return 1.5 if seed_tags > 0 else 0.0


# 风险收益：有代价的卡按代价大小给补偿分（不能只奖励高风险标签）。
static func _risk_value(def: RewardDefinition, snap: RunSnapshot) -> float:
	if def.risk_cost.is_empty():
		return 0.0
	var cost_score := 0.0
	if def.risk_cost.has("hp"):
		cost_score += absf(float(def.risk_cost.get("hp", 0))) / 5.0
	if def.risk_cost.has("gold"):
		cost_score += absf(float(def.risk_cost.get("gold", 0))) / 20.0
	return minf(cost_score, CAP_RISK)


# 进度价值：前期给成长/构筑种子加分，后期给即时收益加分（简化分段）。
static func _progression_value(def: RewardDefinition, snap: RunSnapshot) -> float:
	var room := snap.room_index()
	# 只有 3 幕结构，room_index 0..24；前 1/3 偏成长，后 1/3 偏即时
	var is_early := room >= 0 and room < 8
	var is_late := room >= 16
	var effect := def.first_effect_id()
	if is_early and effect in ["run_power_bonus", "flame_affinity"]:
		return 1.0
	if is_late and effect in ["heal", "shield_next_battle"]:
		return 1.0
	return 0.0
