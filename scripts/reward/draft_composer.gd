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

# 槽位倾向（P1-A：软偏置，不再硬编码顺序）
# 偏好类别的权重乘以 SLOT_BIAS，最终仍按归一化权重抽取；
# 这样保留"Slot A 偏核心 / Slot B 偏战术"的设计意图，但不让 symbol_mod 垄断全部槽位。
const SLOT_PREFERENCE := [
	["symbol_mod", "rule_mod"],              # Slot A 核心成长
	["reel_control", "skill", "rule_mod"],   # Slot B 战术成长
	["symbol_mod", "rule_mod", "reel_control", "skill", "survival_resource"],  # Slot C 开放
]
const SLOT_BIAS := 1.6                      # 偏好类别权重放大系数（软偏置）

# 同质化检查（V1.0 §4.4）：同一组最多同类数
const MAX_SAME_CATEGORY := 2
const SLOT_RETRY_LIMIT := 10        # 单槽重抽上限
const GROUP_RETRY_LIMIT := 3        # 整体重试上限

var _rng := RandomNumberGenerator.new()
var _resolver: CategoryResolver

# 付费重抽递增状态（每次新奖励界面重置）
var paid_rerolls_used: int = 0
var paid_reroll_cost: int = BASE_PAID_REROLL_COST

# G1-D：最近一次重抽是否与上一组完全相同（权威 §6.5「重抽后相同组率」遥测）。
var last_reroll_same_group: bool = false

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

	# 最终合法性复核（保证不空屏、不重复、不超同类）。
	# G1-C：先净化，再从「同一批已过滤合法候选」补足到 count。
	# 旧实现顺序相反（先补后净化），补进来的卡可能被净化剔除 → 静默缩卡。
	picked = _final_validate(picked, count, snap)
	var refill_count := 0
	var refill_shortfall := 0
	if picked.size() < count:
		var need := count - picked.size()
		var exclude := {}
		for d in picked:
			exclude[String(d.id)] = true
		var refill := _pick_distinct(eligible, need, snap, exclude)
		refill_count = refill.size()
		for d in refill:
			picked.append(d)
		# 补齐后再净化一次（防御：确保同类上限/满血仍成立），结果与预期一致
		picked = _final_validate(picked, count, snap)
		# 合法池彻底耗尽时如实记录缺口，供 §6.5 兜底率遥测观测；不造假卡、不放宽过滤
		refill_shortfall = maxi(0, count - picked.size())

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
			"refilled": refill_count,
			"refill_shortfall": refill_shortfall,
		}
		draft.debug_metadata = last_debug
		Debug.log(explain_last())
	return draft


# G1-D：重抽专用入口（权威 §6.5 / G1-7「重抽保持约束并避免相同组合」）。
# 复用完整 compose()（所有硬过滤/保底/同类上限/补足口径均不绕过），重试若干次直到
# 产出的 id 集合与上一组不同；仅当合法组合确实只有一组（重试耗尽仍相同）才接受相同，
# 并置 last_reroll_same_group=true 供 §6.5「重抽后相同组率」遥测观测。
# previous_ids 为上一组展示卡的 id 数组（无序比较：同一组卡换序仍视为相同组合）。
const REROLL_AVOID_LIMIT := 12

func compose_reroll(snap: RunSnapshot, previous_ids: Array, count: int = 3,
		debug: bool = false, extra_defs: Array = [], force_skill: bool = false) -> DraftResult:
	last_reroll_same_group = false
	var prev_set := {}
	for pid in previous_ids:
		prev_set[String(pid)] = true
	var result: DraftResult = null
	for attempt in range(REROLL_AVOID_LIMIT):
		result = compose(snap, count, debug, extra_defs, force_skill)
		if result == null or result.rewards.is_empty():
			break
		if not _same_id_set(result.rewards, prev_set, count):
			break
	# 重试耗尽仍相同（或池空/结果为空）→ 如实接受，并标记相同组
	if result != null and not result.rewards.is_empty() and _same_id_set(result.rewards, prev_set, count):
		last_reroll_same_group = true
	if debug and result != null:
		if result.debug_metadata.is_empty():
			result.debug_metadata = {}
		result.debug_metadata["reroll_same_group"] = last_reroll_same_group
		result.debug_metadata["reroll_avoid_limit"] = REROLL_AVOID_LIMIT
	return result


# 两 id 集合是否相同（顺序无关，且都为 count 张时才比较，避免缩卡误判为相同组）。
func _same_id_set(rewards: Array, prev_set: Dictionary, count: int) -> bool:
	if rewards.size() != count or prev_set.size() != count:
		return false
	for d in rewards:
		if not (d is RewardDefinition) or not prev_set.has(String(d.id)):
			return false
	return true


# 供外部 Provider 用本模块 RNG 取随机索引（不消耗全局 RNG，工程铁律 10）。
func pick_index(size: int) -> int:
	if size <= 0:
		return 0
	return _rng.randi() % size


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
			# P1-A：按权重+槽位软偏置抽类别，并优先覆盖组内未出现的类别（多样性）
			# 稀有度梯度由 CategoryResolver 的 RARITY_DRAW_MULT 在类别内生效（避免类别失衡）
			chosen = _draw_weighted_with_diversity(pref, groups, weights, used_ids, cat_count)

		if chosen == null:
			# 兜底替补：从全部合法候选中按权重抽
			chosen = _draw_any(groups, weights, used_ids, cat_count)
			if chosen != null:
				_last_slot_trace.append("slot%d:fallback_any" % slot)

		if chosen != null:
			out.append(chosen)
			used_ids[chosen.id] = true
			var cat: String = chosen.effective_category()
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


# P1-A：按「归一化权重 × 槽位软偏置 × 多样性因子」抽类别，再从该类别抽卡。
# 多样性因子：组内尚未出现的类别权重 ×(1+DIVERSITY_BONUS)，已出现的类别不放大，
# 让 survival 等低权重类别也能进入三选一，而不是被 symbol_mod 垄断。
const DIVERSITY_BONUS := 1.5

func _draw_weighted_with_diversity(pref: Array, groups: Dictionary, weights: Dictionary,
		used_ids: Dictionary, cat_count: Dictionary) -> RewardDefinition:
	var cats: Array = []
	var vals: Array[float] = []
	var total := 0.0
	for cat in weights:
		var arr: Array = groups.get(cat, [])
		if arr.is_empty():
			continue
		if int(cat_count.get(cat, 0)) >= MAX_SAME_CATEGORY:
			continue
		var w := float(weights[cat])
		if pref.has(cat):
			w *= SLOT_BIAS
		if int(cat_count.get(cat, 0)) == 0:
			w *= (1.0 + DIVERSITY_BONUS)   # 组内未出现 → 放大
		cats.append(cat)
		vals.append(w)
		total += w
	if total <= 0.0:
		return null
	var r := _rng.randf_range(0.0, total)
	var acc := 0.0
	var picked: String = ""
	for i in range(cats.size()):
		acc += vals[i]
		if r <= acc:
			picked = String(cats[i])
			break
	if picked == "":
		picked = String(cats[cats.size() - 1])
	return CategoryResolver.draw_from_category(groups, picked, used_ids, _rng)


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

# 2026-11-19：本局已获得的奖励 id 集合（由 RewardSystem 传入），用于生成期过滤，
# 避免"已选过的操控/技艺卡再次出现在三选一，选中才报 already_owned"。
var _owned_ids: Dictionary = {}


func set_owned_ids(ids: Array) -> void:
	_owned_ids = {}
	for id in ids:
		_owned_ids[String(id)] = true


# 硬过滤：满级/无目标/未解锁/满血治疗无效。硬条件不放宽。
func _eligible(pool: Array, snap: RunSnapshot) -> Array[RewardDefinition]:
	_last_filtered = []
	var out: Array[RewardDefinition] = []
	for def in pool:
		if not (def is RewardDefinition):
			continue
		if _owned_ids.has(def.id):
			_last_filtered.append({"id": def.id, "reason": "already_owned"})
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
	var refill := int(last_debug.get("refilled", 0))
	var shortfall := int(last_debug.get("refill_shortfall", 0))
	if refill > 0 or shortfall > 0:
		lines.append("  补足：补入 %d 张，合法池缺口 %d 张" % [refill, shortfall])
	lines.append("  入选：%s" % str(last_debug.get("picked_ids", [])))
	return "\n".join(lines)


# 兜底：复用与正式池完全相同的硬过滤（G1-C），绝不空屏、绝不假卡。
# 旧实现只查 enabled + 满血治疗，会放回「已拥有 / validate 失败 / eligibility 不满足」的卡；
# 现在统一走 _eligible，杜绝两套过滤口径漂移。
func _fallback(snap: RunSnapshot, count: int, reason: String) -> DraftResult:
	var eligible := _eligible(RewardRegistry.load_valid(), snap)
	var out := _pick_distinct(eligible, count, snap)
	var draft := DraftResult.new(out, _make_draft_id())
	draft.debug_metadata = {"fallback_reason": reason}
	return draft


# 从已过滤的合法候选里按序取 count 张：去重 + 同类上限（兜底/补足共用的硬约束）。
# 输入必须已经过 _eligible，本函数不再重复 enabled/owned/validate/eligibility 检查，
# 但保留满血治疗与同类上限这两项「生成中状态可能变化」的防御。
func _pick_distinct(eligible: Array, count: int, snap: RunSnapshot,
		exclude_ids: Dictionary = {}) -> Array[RewardDefinition]:
	var out: Array[RewardDefinition] = []
	var seen := {}
	var cat_count := {}
	for def in eligible:
		if out.size() >= count:
			break
		if not (def is RewardDefinition):
			continue
		var id := String(def.id)
		if seen.has(id) or exclude_ids.has(id):
			continue
		if def.first_effect_id() == "heal" and snap.hp_ratio() >= 0.999:
			continue
		var cat: String = def.effective_category()
		if int(cat_count.get(cat, 0)) >= MAX_SAME_CATEGORY:
			continue
		out.append(def)
		seen[id] = true
		cat_count[cat] = int(cat_count.get(cat, 0)) + 1
	return out


func _make_draft_id() -> String:
	return "draft_%d" % _rng.randi()
