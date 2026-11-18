class_name DraftComposer
extends RefCounted

# 战后三选一重构 · 核心④：候选硬过滤 + 组合生成 + 多样性 + 兜底 + RNG。
#
# 由 RewardSystem 在战后调用 compose(snap, count) 生成 DraftResult。
# 本模块持有专用 RNG（不消耗全局/战斗 RNG，项目铁律 10）。
#
# ★ 采样模型（经典 roguelike 最佳实践，2026-11-18 重构）：
#   - 出现率由稀有度决定（RARITY_WEIGHT），rare/epic 真正稀有；
#   - 情境评分只做硬过滤（满血滤回血等）与信息性展示，不参与抽样——
#     避免"系统替玩家决策"（低血必出回血，玩家失去权衡乐趣）；
#   - 保留组合多样性（同标签软惩罚）与兜底。
# 这修正了 P0-P4 时期"评分直接当权重、rarity 是死字段"的根本问题。

const BASE_PAID_REROLL_COST := 5

# 稀有度出现权重（common 高、epic 极低）——经典四档梯度
const RARITY_WEIGHT := {
	"common": 60.0, "uncommon": 30.0, "rare": 9.0, "epic": 1.0
}
const DEFAULT_RARITY_WEIGHT := 1.0

# 组合评分权重（可调参数）
const W_SIMILARITY := 1.5      # 同标签惩罚（不再用评分梯度，权重下调）
const W_PAIR_SYNERGY := 2.0    # 组合内真实协同
const W_TENSION := 3.0         # 稀有度梯度张力（有稀有卡=有取舍）
const W_RANDOM := 1.0          # 受控随机
const DIVERSITY_FACTOR := 0.65 # 同标签软惩罚（不绝对禁用）
const DRAFT_SAMPLES := 6       # 采样候选组数

var _rng := RandomNumberGenerator.new()

# 付费重抽递增状态（每次新奖励界面重置）
var paid_rerolls_used: int = 0
var paid_reroll_cost: int = BASE_PAID_REROLL_COST

# 最近一次 Draft 的调试元数据
var last_debug: Dictionary = {}
var _last_filtered: Array[Dictionary] = []   # [{id, reason}]，仅 debug 时填充


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

	# 采样只看稀有度，不看情境评分；评分仅在 debug 下计算用于展示
	var picked := _compose_samples(eligible, snap, count)
	if picked.size() < count:
		var fb := _fallback(snap, count - picked.size(), "insufficient_candidates")
		picked.append_array(fb.rewards)

	var draft := DraftResult.new(picked, _make_draft_id())
	if debug:
		last_debug = {
			"draft_id": draft.draft_id,
			"pool_size": pool.size(),
			"eligible_ids": eligible.map(func(d): return d.id),
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
# 生成内部
# ---------------------------------------------------------------------------

# 硬过滤：满级/无目标/未解锁/满血治疗无效。硬条件不放宽。
func _eligible(pool: Array, snap: RunSnapshot) -> Array[RewardDefinition]:
	_last_filtered = []
	var out: Array[RewardDefinition] = []
	for def in pool:
		if not (def is RewardDefinition):
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


# P4：把 last_debug 格式化成可读文本，解释候选为何出现/被过滤/被选。
# 只在 debug 构建输出（Debug.log 在 release 自动静默）。
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
	var filtered: Array = last_debug.get("filtered", [])
	for f in filtered:
		if f is Dictionary:
			lines.append("  ✗ 过滤 %s：%s" % [str(f.get("id", "")), str(f.get("reason", ""))])
	var scores = last_debug.get("scores", {})
	if scores is Dictionary:
		var detail = scores.get("__detail__", {})
		if detail is Dictionary:
			for id in detail:
				if id is String:
					lines.append("  ✓ %s 评分明细 %s" % [id, str(detail[id])])
	lines.append("  入选：%s" % str(last_debug.get("picked_ids", [])))
	return "\n".join(lines)


# 规则键名 → 实际判定（P1 只处理常见规则；P2 填卡后扩展）
func _passes_eligibility_rule(def: RewardDefinition, snap: RunSnapshot) -> bool:
	match def.eligibility_rule:
		"": return true
		"not_full_hp": return snap.hp_ratio() < 0.999
		"has_build_fire": return snap.build_state != null and snap.build_state.build_score("fire") > 0
		_: return true


# 核心：采样多组 → 组合评分 → 带权抽一组。权重全来自稀有度，不用情境评分。
func _compose_samples(eligible: Array, snap: RunSnapshot, count: int) -> Array[RewardDefinition]:
	var best: Array[RewardDefinition] = []

	for sample_i in range(DRAFT_SAMPLES):
		var group := _sample_group(eligible, count)
		if group.size() < count:
			continue
		var gs := _draft_score(group)
		# 过滤明显失衡组合（同质化严重且无稀有度梯度）
		if float(gs.get("similarity", 0.0)) > W_SIMILARITY and float(gs.get("tension", 0.0)) <= 0.0:
			continue
		var weight := maxf(0.01, float(gs.get("total", 0.0)))
		if sample_i == 0 or _rng.randf() < weight / (weight + 1.0):
			best = group

	if not best.is_empty():
		return best
	return _sample_group(eligible, count)


# 采样一组：按稀有度权重无放回抽 count 张，带同标签软惩罚。
func _sample_group(eligible: Array, count: int) -> Array[RewardDefinition]:
	var remaining := eligible.duplicate()
	var out: Array[RewardDefinition] = []
	var used_tags := {}
	while out.size() < count and not remaining.is_empty():
		var weights: Array[float] = []
		for def in remaining:
			var w := rarity_weight(def)
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


# 单卡稀有度权重（供采样与组合评分共用）
static func rarity_weight(def: RewardDefinition) -> float:
	return float(RARITY_WEIGHT.get(def.rarity, DEFAULT_RARITY_WEIGHT))


# 组合评分：稀有度梯度 + 多样性 + 协同 + 张力 + 随机。
# 情境评分完全不参与——避免系统替玩家做决策。
func _draft_score(group: Array) -> Dictionary:
	var rarity_total := 0.0
	var tag_count := {}
	var rvals: Array[float] = []
	for def in group:
		var rw := rarity_weight(def)
		rvals.append(rw)
		rarity_total += rw
		for tag in def.tags:
			tag_count[tag] = int(tag_count.get(tag, 0)) + 1

	# 相似度惩罚：同标签出现 >1 次累加
	var similarity := 0.0
	for t in tag_count:
		var n := int(tag_count[t])
		if n > 1:
			similarity += float(n - 1)
	similarity *= W_SIMILARITY

	# 组合协同：≥2 个不同 build.* 标签给小奖励
	var pair_synergy := 0.0
	var build_tags := []
	for t in tag_count:
		if String(t).begins_with("build."):
			build_tags.append(t)
	if build_tags.size() >= 2:
		pair_synergy = W_PAIR_SYNERGY

	# 选择张力：稀有度有梯度（有稀有卡=有取舍）；全 common 则无张力
	var tension := 0.0
	if rvals.size() >= 2:
		rvals.sort()
		var spread := rvals[rvals.size() - 1] - rvals[0]
		tension = W_TENSION if spread >= 5.0 else 0.0

	var randomness := _rng.randf_range(0.0, W_RANDOM)
	var total := rarity_total * 0.1 - similarity + pair_synergy + tension + randomness
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
