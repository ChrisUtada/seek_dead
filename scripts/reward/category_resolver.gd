class_name CategoryResolver
extends RefCounted

# 2026-11-19 P0.1 · 奖励类别解析与权重归一化（V1.1 §3 定案）。
# 职责：按一级类别分组合法候选、归一化可用类别权重、按权重抽类别。
# 不负责具体奖励效果、不做情境评分（避免系统替玩家决策）。
#
# 权重只用于"抽哪个类别"，类别内具体奖励仍由 Composer 按 base_weight 抽取。
# 全部按当前有效候选动态计算——无候选的类别权重移除并重新归一化（V1.1 §3.2）。

# 2026-11-19 修复：类别内抽卡需叠加稀有度梯度（V1.1 §4.2：common 70% / uncommon 25% / rare 5%）。
# 此前所有卡 base_weight=1.0、rarity 不参与抽取，导致卡池构成（rare5/uncommon4/common3）
# 直接决定出现率 → common 仅 15%、uncommon 64%，与梯度颠倒。
# 系数按目标比例归一化（common=1.0 基准）：uncommon=25/70, rare=5/70。
const RARITY_DRAW_MULT := {
	"common": 1.0,
	"uncommon": 20.0 / 70.0,
	"rare": 5.0 / 70.0,
	"epic": 5.0 / 70.0,
}

# 一级类别初始权重（V1.1 §3.1 定案）
# 2026-11-19：rule_mod 随"签名全解锁"删除全部规则卡后零候选，权重由 §3.2 自动剔除；
# 权重数值暂不重分配，待重构策划案审查后再定（见 docs/牌谱定位与策划案一致性分析）。
const CATEGORY_WEIGHT := {
	"symbol_mod": 25.0,
	"rule_mod": 25.0,
	"reel_control": 15.0,
	"weapon": 12.0,
	"skill": 8.0,
	"survival_resource": 10.0,
	"signature": 5.0,
}

# 关闭的类别：签名（全解锁无习得）、rule_mod（规则卡全删）。
# P1.1①：weapon 已启用（动态武器替换卡），从禁用列表移除。
const P0_DISABLED_CATEGORIES := ["signature", "rule_mod"]

var _rng: RandomNumberGenerator


func _init(rng: RandomNumberGenerator = null) -> void:
	_rng = rng if rng != null else RandomNumberGenerator.new()


# 按类别分组合法候选。返回 {category -> Array[RewardDefinition]}。
# 空 category 的候选归入 ""（通用），由 Composer 决定如何处理。
static func group_by_category(defs: Array) -> Dictionary:
	var groups: Dictionary = {}
	for d in defs:
		if not (d is RewardDefinition):
			continue
		var cat: String = d.effective_category()
		if not groups.has(cat):
			groups[cat] = []
		(groups[cat] as Array).append(d)
	return groups


# 计算可用类别权重：过滤掉无候选类别 + P0 关闭类别，剩余按比例归一化到 100。
# 返回 {category -> weight(float)}；总和为 100（无可用类别时返回空）。
func normalized_weights(groups: Dictionary) -> Dictionary:
	var raw: Dictionary = {}
	for cat in CATEGORY_WEIGHT:
		if P0_DISABLED_CATEGORIES.has(cat):
			continue
		var arr: Array = groups.get(cat, [])
		if arr.is_empty():
			continue
		raw[cat] = float(CATEGORY_WEIGHT[cat])
	# 未分类（""）候选按极低权重并入通用池，避免旧资源完全不出现
	var generic: Array = groups.get("", [])
	if not generic.is_empty():
		raw[""] = 5.0
	var total := 0.0
	for w in raw.values():
		total += float(w)
	if total <= 0.0:
		return {}
	var out: Dictionary = {}
	for cat in raw:
		out[cat] = float(raw[cat]) / total * 100.0
	return out


# 按权重抽一个类别。返回类别字符串；无可用类别返回空串。
func draw_category(weights: Dictionary) -> String:
	if weights.is_empty():
		return ""
	var keys: Array = []
	var vals: Array[float] = []
	var total := 0.0
	for cat in weights:
		keys.append(cat)
		var w := float(weights[cat])
		vals.append(w)
		total += w
	if total <= 0.0:
		return ""
	var r := _rng.randf_range(0.0, total)
	var acc := 0.0
	for i in range(keys.size()):
		acc += vals[i]
		if r <= acc:
			return String(keys[i])
	return String(keys[keys.size() - 1])


# 从某类别里按 base_weight 无放回抽一张（调用方维护 used_ids 去重）。
static func draw_from_category(groups: Dictionary, cat: String, used_ids: Dictionary, rng: RandomNumberGenerator) -> RewardDefinition:
	var arr: Array = groups.get(cat, [])
	var candidates: Array[RewardDefinition] = []
	for d in arr:
		if used_ids.has(d.id):
			continue
		candidates.append(d)
	if candidates.is_empty():
		return null
	var weights: Array[float] = []
	for d in candidates:
		# 稀有度梯度 × 卡自身 base_weight（V1.1 §4.2）
		var rmult: float = float(RARITY_DRAW_MULT.get(String(d.rarity), 1.0))
		weights.append(maxf(0.01, float(d.base_weight) * rmult))
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf_range(0.0, total)
	var acc := 0.0
	var idx := candidates.size() - 1
	for i in range(candidates.size()):
		acc += weights[i]
		if r <= acc:
			idx = i
			break
	return candidates[idx]
