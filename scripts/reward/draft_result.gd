class_name DraftResult
extends RefCounted

# 战后三选一重构 P0：一次 Draft 生成的产物。
# rewards 里是 RewardDefinition（展示与结算共用同一份实例，参数已在生成前冻结，
# 避免玩家看到卡后选择时效果再随机变化，v2.0 §14.2）。

var rewards: Array[RewardDefinition] = []
var draft_id: String = ""
var debug_metadata: Dictionary = {}   # 评分/过滤原因/组合分，仅 Debug 用


func _init(p_rewards: Array[RewardDefinition] = [], p_draft_id: String = "") -> void:
	rewards = p_rewards
	draft_id = p_draft_id


func is_valid() -> bool:
	return rewards.size() > 0 and not draft_id.is_empty()


func size() -> int:
	return rewards.size()


# ===== RewardApplyResult：Resolver 执行结果 =====
class RewardApplyResult:
	extends RefCounted

	var ok: bool = false
	var reward_id: String = ""
	var effect_id: String = ""
	var summary: String = ""      # 实际执行效果摘要
	var reason: String = ""       # 失败原因（ok=false 时）
	var state_updates: Dictionary = {}   # 需要更新的 Run/Build State（契约 §14.3）

	static func success(p_reward_id: String, p_effect_id: String, p_summary: String = "") -> RewardApplyResult:
		var r := RewardApplyResult.new()
		r.ok = true
		r.reward_id = p_reward_id
		r.effect_id = p_effect_id
		r.summary = p_summary
		return r

	static func failure(p_reward_id: String, p_effect_id: String, p_reason: String) -> RewardApplyResult:
		var r := RewardApplyResult.new()
		r.ok = false
		r.reward_id = p_reward_id
		r.effect_id = p_effect_id
		r.reason = p_reason
		return r
