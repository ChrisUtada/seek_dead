class_name DraftComposer
extends RefCounted

# 战后三选一重构 P0 · 核心④：候选硬过滤 + 组合生成 + 多样性 + 兜底 + RNG。
#
# 由 RewardSystem 在战后调用 compose(ctrl, count) 生成 DraftResult。
# 本模块持有专用 RNG（不消耗全局/战斗 RNG，项目铁律 10）。
# 免费重抽状态（契约 §2）：每次新 Draft 重置，免费优先于扣费判定；
#   「与付费重抽共用刷新入口」由 RewardSystem 调用 compose() 实现，
#   本模块只提供 consume_free_reroll() / free_rerolls_remaining。
#
# P0 范围：过滤与组合的框架 + 兜底逻辑可运行；评分接 RewardEvaluator。

const BASE_PAID_REROLL_COST := 5

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

# 生成一组 Draft（count 张）。每次调用 = 新 Draft → 免费重抽次数重置由调用方
# 在「进入奖励界面」时调 reset_reroll_state()；重抽时调 compose 但不重置。
func compose(snap: RunSnapshot, count: int = 3, debug: bool = false) -> DraftResult:
	var pool := RewardRegistry.load_valid()
	var eligible := _eligible(pool, snap)
	if eligible.is_empty():
		return _fallback(snap, count, "empty_eligible")

	var scores := RewardEvaluator.score_all(eligible, snap, debug)
	var picked := _compose_pick(eligible, scores, snap, count)
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


# 请求重抽：返回 {"free": bool, "cost": int}；调用方据此决定是否扣费。
# 免费优先：只要免费次数 >0 就不扣费、不动付费计数。
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

# 硬过滤：已满级/无目标/重复无收益/未解锁（P0 先做基础过滤，规则键名对接 P1）。
func _eligible(pool: Array, snap: RunSnapshot) -> Array[RewardDefinition]:
	var out: Array[RewardDefinition] = []
	for def in pool:
		if not (def is RewardDefinition):
			continue
		if not def.validate().is_empty():
			continue
		# 满血时治疗无效（v2.0 §7.4 / 契约：满血无效过滤）
		if def.first_effect_id() == "heal" and snap.hp_ratio() >= 0.999:
			continue
		out.append(def)
	return out


# 组合采样（P0 简版）：按评分加权无放回抽 count 张，带轻度同标签惩罚。
# P1 升级为「采样多组 → 组合评分 → 带权抽一组」（v2.0 §7.6/7.7）。
func _compose_pick(eligible: Array, scores: Dictionary, snap: RunSnapshot, count: int) -> Array[RewardDefinition]:
	var remaining := eligible.duplicate()
	var out: Array[RewardDefinition] = []
	var used_tags := {}
	while out.size() < count and not remaining.is_empty():
		var weights: Array[float] = []
		for def in remaining:
			var w := maxf(0.01, float(scores.get(def.id, 1.0)))
			# 同标签软惩罚（diversity_factor，不绝对禁用）
			for tag in def.tags:
				if used_tags.has(tag):
					w *= 0.65
					break
			weights.append(w)
		var idx := _weighted_index(weights)
		var chosen: RewardDefinition = remaining[idx]
		out.append(chosen)
		for tag in chosen.tags:
			used_tags[tag] = true
		remaining.remove_at(idx)
	return out


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


# 兜底：返回已验证有效、当前有用的奖励；绝不空屏、绝不塞假卡（v2.0 §7.8）。
# P0：从 pool 里取前 count 张通过基础校验的非治疗卡；P1 用专门标记的 fallback 卡。
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
