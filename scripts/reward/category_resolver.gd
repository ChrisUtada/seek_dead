class_name CategoryResolver
extends RefCounted

# 2026-11-19 P0.1 · 奖励类别解析与权重归一化（V1.1 §3 定案）。
# 职责：按一级类别分组合法候选、归一化可用类别权重、按权重抽类别。
# 不负责具体奖励效果、不做情境评分（避免系统替玩家决策）。
#
# 权重只用于"抽哪个类别"，类别内具体奖励仍由 Composer 按 base_weight 抽取。
# 全部按当前有效候选动态计算——无候选的类别权重移除并重新归一化（V1.1 §3.2）。

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
		weights.append(maxf(0.01, float(d.base_weight)))
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
