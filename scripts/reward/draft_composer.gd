class_name DraftComposer
extends RefCounted

# 战后三选一 · 统一奖励生成器（2026-11-19 P0.1 重构，V1.1 §19 定案）。
#
# 由 RewardSystem 在战后调用 compose(snap, count) 生成 DraftResult。
# 本模块持有专用 RNG（不消耗全局/战斗 RNG，项目铁律 10）。
#
# ★ 新生成范式（替代旧 6 组采样 + 评分选组）：
#   候选池查询 → 合法性过滤 → 可用类别权重归一化 → 槽位倾向抽取
#   → 同质化检查 → 替补 → 技艺保底检查 → 最终验证 → 输出 Draft。
#   情境评分（RewardEvaluator）不再参与正式决策，仅保留 debug 展示。
#
# 槽位倾向（V1.0 §4.1）：
#   Slot A 核心：symbol_mod / rule_mod
#   Slot B 战术：reel_control / skill
#   Slot C 开放：任意可用类别

const BASE_PAID_REROLL_COST := 5

# 槽位倾向：优先类别顺序（类别不可用时按权重替补）
const SLOT_PREFERENCE := [
	["symbol_mod", "rule_mod"],              # Slot A 核心成长
	["reel_control", "skill", "rule_mod"],   # Slot B 战术成长
	["symbol_mod", "rule_mod", "reel_control", "skill", "survival_resource", ""],  # Slot C 开放
]

# 同质化检查（V1.0 §4.4）：同一组最多同类数
const MAX_SAME_CATEGORY := 2
const SLOT_RETRY_LIMIT := 10        # 单槽重抽上限
const GROUP_RETRY_LIMIT := 3        # 整体重试上限

var _rng := RandomNumberGenerator.new()
var _resolver: CategoryResolver

# 付费重抽递增状态（每次新奖励界面重置）
var paid_rerolls_used: int = 0
var paid_reroll_cost: int = BASE_PAID_REROLL_COST

# 最近一次 Draft 的调试元数据
var last_debug: Dictionary = {}
var _last_filtered: Array[Dictionary] = []   # [{id, reason}]，仅 debug 时填充
var _last_category_weights: Dictionary = {}
var _last_slot_trace: Array[String] = []


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.seed = randi()
	_resolver = CategoryResolver.new(_rng)


# ---------------------------------------------------------------------------
# 公共入口
# ---------------------------------------------------------------------------

# 生成一组 Draft（count 张）。extra_defs 为保底/外部注入的额外候选（如技艺卡）。
# force_skill: 本次 Draft 是否强制包含至少一张技艺候选（一次性保底，V1.1 §21）。
func compose(snap: RunSnapshot, count: int = 3, debug: bool = false,
		extra_defs: Array = [], force_skill: bool = false) -> DraftResult:
	var pool := RewardRegistry.load_valid()
	var eligible := _eligible(pool, snap)
	# 额外候选（技艺卡）并入池
	for ed in extra_defs:
		if ed is RewardDefinition and ed.enabled and not eligible.has(ed):
			eligible.append(ed)
	_last_slot_trace = []
	if eligible.is_empty():
		return _fallback(snap, count, "empty_eligible")

	var groups := CategoryResolver.group_by_category(eligible)
	var weights := _resolver.normalized_weights(groups)
	_last_category_weights = weights.duplicate()

	var picked := _compose_by_slots(groups, weights, count, extra_defs, force_skill)
	if picked.size() < count:
		var fb := _fallback(snap, count - picked.size(), "insufficient_candidates")
		for f in fb.rewards:
			if not _has_id(picked, f.id):
				picked.append(f)

	# 最终合法性复核（保证不空屏、不重复、不超同类）
	picked = _final_validate(picked, count, snap)

	var draft := DraftResult.new(picked, _make_draft_id())
	if debug:
		last_debug = {
			"draft_id": draft.draft_id,
			"pool_size": pool.size(),
			"eligible_ids": eligible.map(func(d): return d.id),
			"category_weights": weights,
			"slot_trace": _last_slot_trace.duplicate(),
			"scores": RewardEvaluator.score_all(eligible, snap, true),  # 信息性，不参与抽样
			"filtered": _last_filtered.duplicate(true),
			"picked_ids": picked.map(func(d): return d.id),
		}
		draft.debug_metadata = last_debug
		Debug.log(explain_last())
	return draft


# 进入新奖励界面：重置付费重抽递增（价格回到 5）
func reset_reroll_state() -> void:
	paid_rerolls_used = 0
	paid_reroll_cost = BASE_PAID_REROLL_COST


# 记一次付费重抽：递增下次价格（实际扣费由 reward_system 负责）
func note_paid_reroll() -> void:
	paid_rerolls_used += 1
	paid_reroll_cost = BASE_PAID_REROLL_COST + 5 * paid_rerolls_used


# ---------------------------------------------------------------------------
# 核心生成：槽位倾向 + 同质化 + 替补
# ---------------------------------------------------------------------------

func _compose_by_slots(groups: Dictionary, weights: Dictionary, count: int,
		extra_defs: Array, force_skill: bool) -> Array[RewardDefinition]:
	var out: Array[RewardDefinition] = []
	var used_ids := {}
	var cat_count := {}

	for slot in range(count):
		var pref: Array = SLOT_PREFERENCE[mini(slot, SLOT_PREFERENCE.size() - 1)]
		var chosen: RewardDefinition = null

		# 保底强制技艺：Slot A 之外的槽优先塞一张技艺（不占用核心成长槽）
		if force_skill and slot > 0 and not _has_category_id(out, "skill"):
			chosen = _draw_skill(groups, used_ids)
			if chosen != null:
				_last_slot_trace.append("slot%d:force_skill" % slot)

		if chosen == null:
			chosen = _draw_for_slot(pref, groups, weights, used_ids, cat_count)

		if chosen == null:
			# 替补：从全部合法候选中按权重抽（不严格遵循槽位倾向）
			chosen = _draw_any(groups, weights, used_ids, cat_count)
			if chosen != null:
				_last_slot_trace.append("slot%d:fallback_any" % slot)

		if chosen != null:
			out.append(chosen)
			used_ids[chosen.id] = true
			var cat := chosen.effective_category()
			cat_count[cat] = int(cat_count.get(cat, 0)) + 1
			if _last_slot_trace.size() <= slot:
				_last_slot_trace.append("slot%d:%s/%s" % [slot, cat, chosen.id])

	# 保底最后兜底：若强制技艺仍未满足，替换最后一个非核心槽
	if force_skill and not _has_category_id(out, "skill"):
		var skill := _draw_skill(groups, used_ids)
		if skill != null and out.size() > 1:
			var replace_idx := out.size() - 1
			var old := out[replace_idx]
			used_ids.erase(old.id)
			out[replace_idx] = skill
			used_ids[skill.id] = true
			_last_slot_trace.append("force_skill_replace:%s->%s" % [old.id, skill.id])
	return out


# 按槽位倾向抽：依次尝试优先类别，跳过已超同类数的类别
func _draw_for_slot(pref: Array, groups: Dictionary, weights: Dictionary,
		used_ids: Dictionary, cat_count: Dictionary) -> RewardDefinition:
	for cat in pref:
		if cat == "":
			continue
		if int(cat_count.get(cat, 0)) >= MAX_SAME_CATEGORY:
			continue
		if (groups.get(cat, []) as Array).is_empty():
			continue
		var d := CategoryResolver.draw_from_category(groups, cat, used_ids, _rng)
		if d != null:
			return d
	return null


# 从全部可用类别按归一化权重抽一张（替补用）
func _draw_any(groups: Dictionary, weights: Dictionary, used_ids: Dictionary,
		cat_count: Dictionary) -> RewardDefinition:
	for attempt in range(SLOT_RETRY_LIMIT):
		var cat := _resolver.draw_category(weights)
		if cat == "":
			break
		if int(cat_count.get(cat, 0)) >= MAX_SAME_CATEGORY:
			continue
		var d := CategoryResolver.draw_from_category(groups, cat, used_ids, _rng)
		if d != null:
			return d
	return null


# 强制技艺候选（来自 extra_defs / skill 类别）
func _draw_skill(groups: Dictionary, used_ids: Dictionary) -> RewardDefinition:
	var skill_defs: Array = groups.get("skill", [])
	for d in skill_defs:
		if not used_ids.has(d.id):
			return d
	return null


# 最终复核：去重、同类数、保留 count 张
func _final_validate(picked: Array, count: int, snap: RunSnapshot) -> Array[RewardDefinition]:
	var out: Array[RewardDefinition] = []
	var seen := {}
	var cat_count := {}
	for d in picked:
		if out.size() >= count:
			break
		if not (d is RewardDefinition) or seen.has(d.id):
			continue
		# 满血治疗二次过滤（状态可能在生成中变化）
		if d.first_effect_id() == "heal" and snap.hp_ratio() >= 0.999:
			continue
		var cat: String = d.effective_category()
		if int(cat_count.get(cat, 0)) >= MAX_SAME_CATEGORY:
			continue
		out.append(d)
		seen[d.id] = true
		cat_count[cat] = int(cat_count.get(cat, 0)) + 1
	return out


func _has_id(arr: Array, id: String) -> bool:
	for d in arr:
		if d is RewardDefinition and d.id == id:
			return true
	return false


func _has_category_id(arr: Array, cat: String) -> bool:
	for d in arr:
		if d is RewardDefinition and d.effective_category() == cat:
			return true
	return false


# ---------------------------------------------------------------------------
# 合法性过滤 / 调试 / 兜底
# ---------------------------------------------------------------------------

# 硬过滤：满级/无目标/未解锁/满血治疗无效。硬条件不放宽。
func _eligible(pool: Array, snap: RunSnapshot) -> Array[RewardDefinition]:
	_last_filtered = []
	var out: Array[RewardDefinition] = []
	for def in pool:
		if not (def is RewardDefinition):
			continue
		if not def.enabled:
			_last_filtered.append({"id": def.id, "reason": "disabled"})
			continue
		if not def.validate().is_empty():
			_last_filtered.append({"id": def.id, "reason": "invalid_definition"})
			continue
		if not _passes_eligibility_rule(def, snap):
			_last_filtered.append({"id": def.id, "reason": "eligibility_rule:" + def.eligibility_rule})
			continue
		if def.first_effect_id() == "heal" and snap.hp_ratio() >= 0.999:
			_last_filtered.append({"id": def.id, "reason": "full_hp"})
			continue
		out.append(def)
	return out


# 规则键名 → 实际判定（沿用现有 RewardEvaluator 的规则，P0 不扩展）
func _passes_eligibility_rule(def: RewardDefinition, snap: RunSnapshot) -> bool:
	match def.eligibility_rule:
		"": return true
		"not_full_hp": return snap.hp_ratio() < 0.999
		"has_build_fire": return snap.build_state != null and snap.build_state.build_score("fire") > 0
		_: return true


# 把 last_debug 格式化成可读文本（debug 构建输出）
func explain_last() -> String:
	if last_debug.is_empty():
		return "[Draft explain] 无调试数据（compose 时传 debug=true）"
	var lines: Array[String] = []
	lines.append("[Draft explain] draft=%s" % str(last_debug.get("draft_id", "")))
	lines.append("  候选池 %d 张 → 有效 %d 张 → 选出 %d 张" % [
		int(last_debug.get("pool_size", 0)),
		(last_debug.get("eligible_ids", []) as Array).size(),
		(last_debug.get("picked_ids", []) as Array).size(),
	])
	var cw: Dictionary = last_debug.get("category_weights", {})
	var cw_parts: Array[String] = []
	for cat in cw:
		cw_parts.append("%s=%.1f%%" % [str(cat), float(cw[cat])])
	lines.append("  类别权重：%s" % " ".join(cw_parts))
	for s in (last_debug.get("slot_trace", []) as Array):
		lines.append("  · %s" % str(s))
	# 评分明细：RewardEvaluator 在 debug 下仍计算（仅展示，不参与决策，V1.1 §19）
	var scores = last_debug.get("scores", {})
	if scores is Dictionary:
		var detail = scores.get("__detail__", {})
		if detail is Dictionary:
			for id in detail:
				if id is String:
					lines.append("  ✓ %s 评分明细 %s" % [id, str(detail[id])])
	var filtered: Array = last_debug.get("filtered", [])
	for f in filtered:
		if f is Dictionary:
			lines.append("  ✗ 过滤 %s：%s" % [str(f.get("id", "")), str(f.get("reason", ""))])
	lines.append("  入选：%s" % str(last_debug.get("picked_ids", [])))
	return "\n".join(lines)


# 兜底：已验证有效、当前有用的奖励；绝不空屏、绝不假卡
func _fallback(snap: RunSnapshot, count: int, reason: String) -> DraftResult:
	var pool := RewardRegistry.load_valid()
	var out: Array[RewardDefinition] = []
	for def in pool:
		if out.size() >= count:
			break
		if not def.enabled:
			continue
		if def.first_effect_id() == "heal" and snap.hp_ratio() >= 0.999:
			continue
		out.append(def)
	var draft := DraftResult.new(out, _make_draft_id())
	draft.debug_metadata = {"fallback_reason": reason}
	return draft


func _make_draft_id() -> String:
	return "draft_%d" % _rng.randi()
