class_name RewardEvaluator
extends RefCounted

# 战后三选一重构 P0 · 核心③：计算奖励的情境价值与协同评分。
#
# 纯函数模块（static），只读 RunSnapshot，不修改任何玩家状态、不依赖 HUD/Shop/Battle。
# 评分分解（v2.0 §7.3）：
#   OfferValue = BaseValue + ContextValue + SynergyValue + NoveltyValue + RiskRewardValue + ProgressionValue
# P0 范围：实现评分框架 + 治疗情境价值（验证用）；其余各项先给中性默认值，P1/P3 填充。
# 各项必须封顶，避免分数失控（v2.0 §18）。

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
		var s := score(def, snap)
		out[def.id] = s
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
	var base := clampf(float(def.base_value), 0.0, CAP_BASE)
	var context := _context_value(def, snap)
	var synergy := _synergy_value(def, snap)
	var novelty := 0.0    # P1：未见过的标签给探索分
	var risk := 0.0       # P1：risk_cost 权衡
	var progression := 0.0  # P3：房间阶段修正
	return {
		"base": base,
		"context": clampf(context, -CAP_CONTEXT, CAP_CONTEXT),
		"synergy": clampf(synergy, 0.0, CAP_SYNERGY),
		"novelty": clampf(novelty, 0.0, CAP_NOVELTY),
		"risk": clampf(risk, -CAP_RISK, CAP_RISK),
		"progression": clampf(progression, -CAP_PROGRESSION, CAP_PROGRESSION),
	}


# 治疗情境价值（契约 §7.4 / v2.0 §7.4）：
# 用有效恢复量避免满血浪费；低血时保持高价值，但不写成"必出回血"硬规则。
static func _context_value(def: RewardDefinition, snap: RunSnapshot) -> float:
	var effect_id := def.first_effect_id()
	if effect_id != EFFECT_HEAL:
		return 0.0
	var hp_max := maxf(1.0, float(snap.survival.get("max_hp", 1)))
	var hp := float(snap.survival.get("current_hp", 0))
	var ratio := clampf(hp / hp_max, 0.0, 1.0)
	# 假设治疗量 35%（旧 heal.tres 基准），P1 应从 effect_params 读取实际值
	var heal_amount := 0.35 * hp_max
	var effective_heal := minf(heal_amount, maxf(0.0, hp_max - hp))
	var efficiency := effective_heal / maxf(heal_amount, 0.0001)
	# 分段：0–35% 高、35–65% 中高、65–100% 低到中；再乘有效率
	var band := 0.0
	if ratio <= 0.35:
		band = 6.0
	elif ratio <= 0.65:
		band = 3.0
	else:
		band = 0.0
	return band * efficiency


static func _synergy_value(def: RewardDefinition, snap: RunSnapshot) -> float:
	# P3：仅当奖励标签与 BuildState 已形成标签真实联动时加分，禁止同标签重复无限叠加。
	var score := 0.0
	var bs = snap.build_state
	if bs == null:
		return 0.0
	for tag in def.tags:
		var t := String(tag)
		if t.begins_with("build.") and bs.has_tag(t) and bs.tag_strength(t) >= 4.0:
			score += 2.0
	return score
