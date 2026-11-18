class_name DraftComposer
extends RefCounted

# 战后三选一重构 P1 · 核心④：候选硬过滤 + 组合生成 + 多样性 + 兜底 + RNG。
#
# 由 RewardSystem 在战后调用 compose(snap, count) 生成 DraftResult。
# 本模块持有专用 RNG（不消耗全局/战斗 RNG，项目铁律 10）。
# 免费重抽状态（契约 §2）：每次新 Draft 重置，免费优先于扣费判定。
#
# P1 组合采样（v2.0 §7.6/7.7）：
#   1) 从 eligible 采样若干组候选 draft（每组 count 张）
#   2) 对每组算 DraftScore = ΣOfferValue - SimilarityPenalty + PairSynergyBonus
#                            + ChoiceTensionBonus + Randomness
#   3) 过滤明显失衡组合，从高质量组中带权抽一组（非唯一 Top1，保留探索）
#   4) 多样性约束逐级放宽；兜底永不空屏、不塞假卡

const BASE_PAID_REROLL_COST := 5

# 组合评分权重（可调参数）
const W_SIMILARITY := 4.0      # 同标签惩罚
const W_PAIR_SYNERGY := 2.0    # 组合内真实协同
const W_TENSION := 3.0         # 选择张力（价值梯度）
const W_RANDOM := 1.0          # 受控随机
const DIVERSITY_FACTOR := 0.65 # 同标签软惩罚（不绝对禁用）
const DRAFT_SAMPLES := 6       # 采样候选组数

var _rng := RandomNumberGenerator.new()

# 免费重抽状态（每次 new_draft 重置）
var free_rerolls_remaining: int = 0
var paid_rerolls_used: int = 0
var paid_reroll_cost: int = BASE_PAID_REROLL_COST

# 最近一次 Draft 的调试元数据
var last_debug: Dictionary = {}


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.seed = randi()


# ---------------------------------------------------------------------------
# 公共入口
# ---------------------------------------------------------------------------

# 生成一组 Draft（count 张）。重抽时调 compose 但不 reset（重抽状态由调用方管）。
func compose(snap: RunSnapshot, count: int = 3, debug: bool = false) -> DraftResult:
	var pool := RewardRegistry.load_valid()
	var eligible := _eligible(pool, snap)
	if eligible.is_empty():
		return _fallback(snap, count, "empty_eligible")

	var scores := RewardEvaluator.score_all(eligible, snap, debug)
	var picked := _compose_samples(eligible, scores, snap, count)
	if picked.size() < count:
		var fb := _fallback(snap, count - picked.size(), "insufficient_candidates")
		picked.append_array(fb.rewards)

	var draft := DraftResult.new(picked, _make_draft_id())
	if debug:
		last_debug = {
			"pool_size": pool.size(),
			"eligible_ids": eligible.map(func(d): return d.id),
			"scores": scores,
		}
		draft.debug_metadata = last_debug
	return draft


# 进入新奖励界面：重置重抽状态（契约 §2.2）
func reset_reroll_state(has_free_reroll_reward: bool = false) -> void:
	free_rerolls_remaining = 1 if has_free_reroll_reward else 0
	paid_rerolls_used = 0
	paid_reroll_cost = BASE_PAID_REROLL_COST


# 请求重抽：返回 {"free": bool, "cost": int}；免费优先于扣费
func request_reroll() -> Dictionary:
	if free_rerolls_remaining > 0:
		free_rerolls_remaining -= 1
		return {"free": true, "cost": 0, "ok": true}
	var cost := paid_reroll_cost
	paid_rerolls_used += 1
	paid_reroll_cost = BASE_PAID_REROLL_COST + 5 * paid_rerolls_used
	return {"free": false, "cost": cost, "ok": true}


# ---------------------------------------------------------------------------
# 生成内部
# ---------------------------------------------------------------------------

# 硬过滤：满级/无目标/未解锁/满血治疗无效。硬条件不放宽。
func _eligible(pool: Array, snap: RunSnapshot) -> Array[RewardDefinition]:
	var out: Array[RewardDefinition] = []
	for def in pool:
		if not (def is RewardDefinition):
			continue
		if not def.validate().is_empty():
			continue
		if not _passes_eligibility_rule(def, snap):
			continue
		if def.first_effect_id() == "heal" and snap.hp_ratio() >= 0.999:
			continue
		out.append(def)
	return out


# 规则键名 → 实际判定（P1 只处理常见规则；P2 填卡后扩展）
func _passes_eligibility_rule(def: RewardDefinition, snap: RunSnapshot) -> bool:
	match def.eligibility_rule:
		"": return true
		"not_full_hp": return snap.hp_ratio() < 0.999
		"has_build_fire": return snap.build_state != null and snap.build_state.build_score("fire") > 0
		_: return true


# P1 核心：采样多组 → 组合评分 → 带权抽一组。
func _compose_samples(eligible: Array, scores: Dictionary, snap: RunSnapshot, count: int) -> Array[RewardDefinition]:
	var best: Array[RewardDefinition] = []

	for sample_i in range(DRAFT_SAMPLES):
		var group := _sample_group(eligible, scores, count)
		if group.size() < count:
			continue
		var gs := _draft_score(group, scores)
		# 过滤明显失衡组合（同质化严重且无价值梯度）
		if float(gs.get("similarity", 0.0)) > W_SIMILARITY and float(gs.get("tension", 0.0)) <= 0.0:
			continue
		# 带权抽：用得分构造权重，非唯一 Top1
		var weight := maxf(0.01, float(gs.get("total", 0.0)))
		if sample_i == 0 or _rng.randf() < weight / (weight + 1.0):
			best = group

	if not best.is_empty():
		return best

	# 所有采样都被过滤 → 放宽软约束，直接按评分抽一组
	return _sample_group(eligible, scores, count)


# 采样一组：按评分加权无放回抽 count 张，带同标签软惩罚。
func _sample_group(eligible: Array, scores: Dictionary, count: int) -> Array[RewardDefinition]:
	var remaining := eligible.duplicate()
	var out: Array[RewardDefinition] = []
	var used_tags := {}
	while out.size() < count and not remaining.is_empty():
		var weights: Array[float] = []
		for def in remaining:
			var w := maxf(0.01, float(scores.get(def.id, 1.0)))
			for tag in def.tags:
				if used_tags.has(tag):
					w *= DIVERSITY_FACTOR
					break
			weights.append(w)
		var idx := _weighted_index(weights)
		var chosen: RewardDefinition = remaining[idx]
		out.append(chosen)
		for tag in chosen.tags:
			used_tags[tag] = true
		remaining.remove_at(idx)
	return out


# 组合评分（v2.0 §7.6）
func _draft_score(group: Array, scores: Dictionary) -> Dictionary:
	var card_total := 0.0
	var tag_count := {}
	var vals: Array[float] = []
	for def in group:
		var v := float(scores.get(def.id, 1.0))
		vals.append(v)
		card_total += v
		for tag in def.tags:
			tag_count[tag] = int(tag_count.get(tag, 0)) + 1

	# 相似度惩罚：同标签出现 >1 次累加
	var similarity := 0.0
	for t in tag_count:
		var n := int(tag_count[t])
		if n > 1:
			similarity += float(n - 1)
	similarity *= W_SIMILARITY

	# 组合协同：≥2 个不同 build.* 标签给小奖励（简化版，P3 接真实协同矩阵）
	var pair_synergy := 0.0
	var build_tags := []
	for t in tag_count:
		if String(t).begins_with("build."):
			build_tags.append(t)
	if build_tags.size() >= 2:
		pair_synergy = W_PAIR_SYNERGY

	# 选择张力：价值有梯度说明有取舍；全等或悬殊都扣分
	var tension := 0.0
	if vals.size() >= 2:
		vals.sort()
		var spread := vals[vals.size() - 1] - vals[0]
		tension = W_TENSION if spread > 1.0 else 0.0

	var randomness := _rng.randf_range(0.0, W_RANDOM)
	var total := card_total - similarity + pair_synergy + tension + randomness
	return {
		"total": total, "similarity": similarity,
		"pair_synergy": pair_synergy, "tension": tension, "randomness": randomness,
	}


func _weighted_index(weights: Array[float]) -> int:
	var total := 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return 0
	var r := _rng.randf_range(0.0, total)
	var acc := 0.0
	for i in range(weights.size()):
		acc += weights[i]
		if r <= acc:
			return i
	return weights.size() - 1


# 兜底：已验证有效、当前有用的奖励；绝不空屏、绝不假卡（v2.0 §7.8）。
func _fallback(snap: RunSnapshot, count: int, reason: String) -> DraftResult:
	var pool := RewardRegistry.load_valid()
	var out: Array[RewardDefinition] = []
	for def in pool:
		if out.size() >= count:
			break
		if def.first_effect_id() == "heal" and snap.hp_ratio() >= 0.999:
			continue
		out.append(def)
	var draft := DraftResult.new(out, _make_draft_id())
	draft.debug_metadata = {"fallback_reason": reason}
	return draft


func _make_draft_id() -> String:
	return "draft_%d" % _rng.randi()
