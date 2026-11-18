class_name RewardResolver
extends RefCounted

# 战后三选一重构 P0 · 核心⑤：验证所选奖励并分发到现有结算接口。
#
# 硬约束（契约 §1.2 / B.2）：
# - 只分发，不复制原有奖励效果代码；旧结算接口不适配时做 Adapter，禁止另写一套状态修改。
# - 必须返回 RewardApplyResult（成功/失败/摘要/原因），禁止"卡消失但效果没执行"。
# - 不依赖旧抽选器（LootOffer/GrowthLootOffer），只依赖旧结算接口。
#
# 当前 4 张种子卡的 effect_id 分发：三个复用项（heal/shield/power）委托现有结算，
# 一个新效果（flame_affinity）写本局构筑状态。
# 原第 5 张「幸运余波」已删除：免费重抽不产生构筑价值，且与战斗内重转消耗品重复。

var _ctrl: DuelController
var _draft_composer: DraftComposer = null   # 预留：未来需要访问 Draft 状态的奖励


func _init(ctrl: DuelController) -> void:
	_ctrl = ctrl


func bind_composer(composer: DraftComposer) -> void:
	_draft_composer = composer


# 主入口：验证 → 分发 → 返回结果。
func resolve(reward: RewardDefinition) -> DraftResult.RewardApplyResult:
	if reward == null:
		return DraftResult.RewardApplyResult.failure("", "", "null_reward")
	var errors := reward.validate()
	if not errors.is_empty():
		return DraftResult.RewardApplyResult.failure(reward.id, reward.first_effect_id(), "invalid_definition:" + str(errors))

	# 多效果卡：逐个分发，任一失败即整体失败（当前 4 张种子卡均为单效果）
	var last: DraftResult.RewardApplyResult = null
	for effect in reward.effects:
		var eid := String(effect.get("effect_id", ""))
		var params: Dictionary = effect.get("params", {})
		last = _dispatch(reward.id, eid, params)
		if last == null or not last.ok:
			return last if last != null else DraftResult.RewardApplyResult.failure(reward.id, eid, "dispatch_null")
	return last if last != null else DraftResult.RewardApplyResult.failure(reward.id, "", "no_effects")


func _dispatch(reward_id: String, effect_id: String, params: Dictionary) -> DraftResult.RewardApplyResult:
	match effect_id:
		"heal":
			return _apply_existing_heal(reward_id, params)
		"shield_next_battle":
			return _apply_existing_shield(reward_id, params)
		"run_power_bonus":
			return _apply_existing_power(reward_id, params)
		"flame_affinity":
			return _apply_flame_affinity(reward_id, params)
		_:
			return DraftResult.RewardApplyResult.failure(reward_id, effect_id, "unknown_effect_id")


# ===== 复用现有结算（只调接口，不复制逻辑） =====
# 三个复用项统一委托 reward_system._apply_loot_option(opt)，走其 kind 分发
# （reward_system:463 → _apply_growth_option:500）。Resolver 不自己改玩家状态。
# 这是契约 §1.2 要求的 Adapter：把新 effect_id 翻译成旧 opt 格式。

func _delegate(kind: String, params: Dictionary) -> Dictionary:
	var opt := {"kind": kind}
	if params.has("amount"):
		opt["amount"] = int(params.get("amount", 0))
	return _ctrl._reward_system._apply_loot_option(opt)


func _to_result(res: Dictionary, reward_id: String, effect_id: String, ok_msg_key: String) -> DraftResult.RewardApplyResult:
	if not bool(res.get("ok", false)):
		return DraftResult.RewardApplyResult.failure(reward_id, effect_id, String(res.get("reason", "delegate_failed")))
	var amount := int(res.get("amount", 0))
	return DraftResult.RewardApplyResult.success(reward_id, effect_id, ok_msg_key % amount)


func _apply_existing_heal(reward_id: String, params: Dictionary) -> DraftResult.RewardApplyResult:
	# 旧 heal 分支固定按 max_hp*35% 结算（reward_system:552），不接受自定义 amount。
	# 因此 params 里的 pct 在 P0 不生效——这是复用旧结算的既有行为，不是 bug。
	if float(_ctrl.player_hp) >= float(_ctrl.player_hp_max):
		return DraftResult.RewardApplyResult.failure(reward_id, "heal", "full_hp")
	return _to_result(_delegate("heal", {}), reward_id, "heal", "回血 +%d")


func _apply_existing_shield(reward_id: String, params: Dictionary) -> DraftResult.RewardApplyResult:
	# 旧 shield 分支：run_shield_next += amount（reward_system:543）
	if not params.has("amount"):
		return DraftResult.RewardApplyResult.failure(reward_id, "shield_next_battle", "missing_amount")
	return _to_result(_delegate("shield", params), reward_id, "shield_next_battle", "下房护盾 +%d")


func _apply_existing_power(reward_id: String, params: Dictionary) -> DraftResult.RewardApplyResult:
	# 旧结算的伤害加成走 conversion 分支（reward_system:565）：
	# opt = {"kind":"conversion", "power":n} → run_power_bonus += n（combat_system:844 聚合）。
	# 不能用 {"kind":"power"}（_apply_growth_option 无此分支，会返回 unknown_growth）。
	if not params.has("amount"):
		return DraftResult.RewardApplyResult.failure(reward_id, "run_power_bonus", "missing_amount")
	var res: Dictionary = _ctrl._reward_system._apply_loot_option({
		"kind": "conversion", "power": int(params.get("amount", 0))
	})
	if not bool(res.get("ok", false)):
		return DraftResult.RewardApplyResult.failure(reward_id, "run_power_bonus", String(res.get("reason", "delegate_failed")))
	# conversion 返回的是 power 字段，不是 amount
	return DraftResult.RewardApplyResult.success(reward_id, "run_power_bonus", "本局伤害 +%d" % int(res.get("power", 0)))


# ===== 新效果（P0 状态登记，P1/P3 接入实际系统） =====

func _apply_flame_affinity(reward_id: String, params: Dictionary) -> DraftResult.RewardApplyResult:
	# P3：写入本局元素构筑计数，RunStateAnalyzer 下次 capture 时据此推导 element.fire/build.fire
	var amount := int(params.get("amount", 1))
	if amount <= 0:
		return DraftResult.RewardApplyResult.failure(reward_id, "flame_affinity", "invalid_amount")
	var elem := String(params.get("element", "fire"))
	_ctrl.element_affinity[elem] = int(_ctrl.element_affinity.get(elem, 0)) + amount
	var r := DraftResult.RewardApplyResult.success(reward_id, "flame_affinity", "%s构筑 +%d" % [elem, amount])
	r.state_updates["element_affinity"] = _ctrl.element_affinity.duplicate(true)
	return r

