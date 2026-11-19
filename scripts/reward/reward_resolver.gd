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
		"run_symbol_bonus":
			return _apply_existing_symbol_weight(reward_id, params)
		"gold_add":
			return _apply_existing_gold(reward_id, params)
		"pattern_bonus":
			return _apply_pattern_bonus(reward_id, params)
		"reel_control":
			return _apply_reel_control(reward_id, params)
		"symbol_effect_bonus":
			return _apply_symbol_effect_bonus(reward_id, params)
		"weapon_replace":
			return _apply_weapon_replace(reward_id, params)
		"flame_affinity":
			return _apply_flame_affinity(reward_id, params)
		"pick_perk":
			return _apply_pick_perk(reward_id, params)
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


# 符号权重强化（2026-11-19 P0.2）：复用 reward_system 的 "symbol" 结算入口。
# params: {"path": "res://resources/symbols/*.tres", "weight": int}
# 契约：只分发不复制逻辑——合法性（符号存在/weight>0/格数变化）与转轮重建都在旧入口里。
func _apply_existing_symbol_weight(reward_id: String, params: Dictionary) -> DraftResult.RewardApplyResult:
	var path := String(params.get("path", ""))
	var weight := int(params.get("weight", 0))
	if path.is_empty() or weight <= 0:
		return DraftResult.RewardApplyResult.failure(reward_id, "run_symbol_bonus", "invalid_params")
	var res: Dictionary = _ctrl._reward_system._apply_loot_option({
		"kind": "symbol", "path": path, "weight": weight
	})
	if not bool(res.get("ok", false)):
		return DraftResult.RewardApplyResult.failure(reward_id, "run_symbol_bonus", String(res.get("reason", "delegate_failed")))
	var before := int(res.get("before", 0))
	var after := int(res.get("after", 0))
	var r := DraftResult.RewardApplyResult.success(
		reward_id, "run_symbol_bonus", "符号权重 +%d（%d→%d 格）" % [weight, before, after])
	r.state_updates["symbol_path"] = path
	r.state_updates["symbol_cells"] = [before, after]
	return r


# 金币奖励（2026-11-19 P0.2）：复用 reward_system 的 "item"/grant=gold 结算入口。
func _apply_existing_gold(reward_id: String, params: Dictionary) -> DraftResult.RewardApplyResult:
	var amount := int(params.get("amount", 0))
	if amount <= 0:
		return DraftResult.RewardApplyResult.failure(reward_id, "gold_add", "invalid_amount")
	# item 分支要求 path 非空（仅作键，grant=gold 时不读取实际资源）
	var res: Dictionary = _ctrl._reward_system._apply_loot_option({
		"kind": "item", "path": "gold", "grant": "gold", "gold": amount
	})
	if not bool(res.get("ok", false)):
		return DraftResult.RewardApplyResult.failure(reward_id, "gold_add", String(res.get("reason", "delegate_failed")))
	var r := DraftResult.RewardApplyResult.success(reward_id, "gold_add", "金币 +%d" % amount)
	r.state_updates["gold"] = _ctrl.gold
	return r


# 牌谱规则强化（P1-B）：写本局 pattern_param_overrides，不修改共享 .tres。
# params: {"pattern_id": "...", "param": "damage_mult", "delta": 0.25}
# PatternEffects.apply 每回合读覆盖并合并到 effect_params。
func _apply_pattern_bonus(reward_id: String, params: Dictionary) -> DraftResult.RewardApplyResult:
	var pid := String(params.get("pattern_id", ""))
	var param_key := String(params.get("param", ""))
	var delta := float(params.get("delta", 0.0))
	if pid.is_empty() or param_key.is_empty() or is_zero_approx(delta):
		return DraftResult.RewardApplyResult.failure(reward_id, "pattern_bonus", "invalid_params")
	# 校验 pattern_id 存在（避免无效覆盖污染字典）
	if _ctrl._pattern_system == null or _ctrl._pattern_system.get_pattern(pid) == null:
		return DraftResult.RewardApplyResult.failure(reward_id, "pattern_bonus", "unknown_pattern")
	var per_pattern: Dictionary = _ctrl.pattern_param_overrides.get(pid, {})
	per_pattern[param_key] = float(per_pattern.get(param_key, 0.0)) + delta
	_ctrl.pattern_param_overrides[pid] = per_pattern
	var r := DraftResult.RewardApplyResult.success(
		reward_id, "pattern_bonus", "牌谱强化：%s %s %+.2f" % [pid, param_key, delta])
	r.state_updates["pattern_param_overrides"] = _ctrl.pattern_param_overrides.duplicate(true)
	return r


# 滚轴操控：写 controller.reel_controls。
# B方案（2026-11-19）：wide 已移除，改为 slow_ramp（缓速）；snap=±2吸附，mercy=废铁转化。
# params: {"control_id": "trash_reroll"|"mercy"|"slow_ramp"}
func _apply_reel_control(reward_id: String, params: Dictionary) -> DraftResult.RewardApplyResult:
	var cid := String(params.get("control_id", ""))
	if not ["trash_reroll", "mercy", "slow_ramp"].has(cid):
		return DraftResult.RewardApplyResult.failure(reward_id, "reel_control", "invalid_control_id")
	if _ctrl.reel_controls.has(cid):
		return DraftResult.RewardApplyResult.failure(reward_id, "reel_control", "already_owned")
	_ctrl.reel_controls[cid] = true
	var r := DraftResult.RewardApplyResult.success(reward_id, "reel_control", "获得操控「%s」" % cid)
	r.state_updates["reel_controls"] = _ctrl.reel_controls.duplicate(true)
	return r


# 符号效果强化（P1.1②）：写 controller.symbol_effect_overrides，build_pool 重建后重新应用。
# params: {"symbol_path": "...", "effect": "status"|"crit"|"crit_chance"|"power", "delta": 数值}
func _apply_symbol_effect_bonus(reward_id: String, params: Dictionary) -> DraftResult.RewardApplyResult:
	var path := String(params.get("symbol_path", ""))
	var effect_id := String(params.get("effect", ""))
	var delta := float(params.get("delta", 0.0))
	if path.is_empty() or not ["status", "crit", "crit_chance", "power"].has(effect_id) or is_zero_approx(delta):
		return DraftResult.RewardApplyResult.failure(reward_id, "symbol_effect_bonus", "invalid_params")
	# 校验符号资源存在（避免无效覆盖）
	if ResourceLoader.load(path) == null:
		return DraftResult.RewardApplyResult.failure(reward_id, "symbol_effect_bonus", "unknown_symbol")
	var per_sym: Dictionary = _ctrl.symbol_effect_overrides.get(path, {})
	var prev: float = float(per_sym.get(effect_id, 0.0))
	var added: float = delta
	# 累加正负不限；但普通效果都应为正，负向由卡牌自己声明负 delta
	per_sym[effect_id] = prev + added
	_ctrl.symbol_effect_overrides[path] = per_sym
	var r := DraftResult.RewardApplyResult.success(
		reward_id, "symbol_effect_bonus", "符号强化：%s %s %+.2f" % [path.get_file().get_basename(), effect_id, delta])
	r.state_updates["symbol_effect_overrides"] = _ctrl.symbol_effect_overrides.duplicate(true)
	return r


# 武器替换（P1.1①）：空槽直接装备；槽满返回 needs_replace，由 UI 弹替换层走 settle_loot_replace。
# params: {"weapon_path": "..."}
func _apply_weapon_replace(reward_id: String, params: Dictionary) -> DraftResult.RewardApplyResult:
	var p := String(params.get("weapon_path", ""))
	if p.is_empty() or ResourceLoader.load(p) == null:
		return DraftResult.RewardApplyResult.failure(reward_id, "weapon_replace", "invalid_weapon")
	if _ctrl.selected_loadout.has(p):
		return DraftResult.RewardApplyResult.failure(reward_id, "weapon_replace", "already_equipped")
	if _ctrl.selected_loadout.size() < _ctrl._loadout_system.cat_cap("weapon"):
		# 空槽：直接装备
		_ctrl.selected_loadout.append(p)
		_ctrl._build_pool(_ctrl.selected_loadout)
		if _ctrl._telemetry != null:
			_ctrl._telemetry.on_weapon_swap()
		var r0 := DraftResult.RewardApplyResult.success(
			reward_id, "weapon_replace", "装备武器「%s」" % p.get_file().get_basename())
		r0.state_updates["weapon_equipped"] = p
		return r0
	# 槽满：需要玩家在替换弹层选旧武器（由 RewardPresentation 标 needs_replace 触发）
	return DraftResult.RewardApplyResult.failure(reward_id, "weapon_replace", "needs_replace")


# ===== 新效果（P0 状态登记，P1/P3 接入实际系统） =====

func _apply_pick_perk(reward_id: String, params: Dictionary) -> DraftResult.RewardApplyResult:
	# 技艺卡：选中即授予（2026-11-19 技艺改概率注入三选一，pick 不再依赖 pending_picks）。
	# 若技艺已拥有（如重复结算），pick 内部会拒绝，避免重复。
	var perk_id := String(params.get("id", ""))
	if perk_id.is_empty():
		return DraftResult.RewardApplyResult.failure(reward_id, "pick_perk", "invalid_perk_id")
	if _ctrl.growth == null:
		return DraftResult.RewardApplyResult.failure(reward_id, "pick_perk", "growth_missing")
	if not _ctrl.growth.pick(perk_id):
		return DraftResult.RewardApplyResult.failure(reward_id, "pick_perk", "perk_not_available")
	var r := DraftResult.RewardApplyResult.success(reward_id, "pick_perk", "习得技艺「%s」" % _ctrl.growth.perk_name(perk_id))
	r.state_updates["perk_id"] = perk_id
	return r


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


