extends RefCounted

# ============================================================================
# PatternEffects —— 牌谱效果执行（2026-11-15，转轮凑牌 Step 2）
# 方案：docs/转轮凑牌战斗重构_24种牌型与制作执行方案_2026-11-15.md §6
#
# 铁律：
#   1. 所有效果只写「本轮累计器」acc，不重新调用符号结算、不递归触发自身；
#   2. 追加伤害一律进 acc["dmg"] / acc["pierce"]，不再经过 contribute；
#   3. 每条效果都要在 acc["lines"] 留一行，让玩家看得见为什么多了这一下。
#
# Step 2 实装范围：S01–S03、S05、S06（S04 依赖毒层标准结算的口径，见 TODO）。
# ============================================================================

const EFFECT_LABELS := {
	"flame_resonance": "烈焰共鸣",
	"frost_seal": "霜封连携",
	"venom_burst": "毒爆连携",
	"holy_volley": "黎明圣辉",
	"shadow_execution": "暗影处刑",
	"plain_grind": "无锋磨砺",
	"frostfire_dual": "冰火二重（签名候选）",
	"power_support": "增伤术式",
	"defense_support": "防御术式",
	"recovery_support": "恢复术式",
}


static func apply(acc: Dictionary, pattern, ctx: Dictionary) -> void:
	var eid := String(pattern.effect_id)
	match eid:
		"flame_resonance":
			_flame_resonance(acc, pattern, ctx)
		"frostfire_dual":
			_frostfire_dual(acc, pattern, ctx)
		"holy_volley":
			_holy_volley(acc, pattern, ctx)
		"venom_burst":
			_venom_burst(acc, pattern, ctx)
		"frost_seal":
			_frost_seal(acc, pattern, ctx)
		"shadow_execution":
			_shadow_execution(acc, pattern, ctx)
		"plain_grind":
			_plain_grind(acc, pattern, ctx)
		"power_support":
			_power_support(acc, pattern, ctx)
		"defense_support":
			_defense_support(acc, pattern, ctx)
		"recovery_support":
			_recovery_support(acc, pattern, ctx)
		_:
			return
	if acc.has("lines"):
		acc["lines"].append("   ✦ 牌谱「%s」已触发" % String(pattern.name))


# S01：本轮火系伤害 +25%；燃烧额外 +1 层。
# 「火系伤害」取 dmg_by_elem.fire（含穿透部分），加成只写入 acc["dmg"]，不重算。
static func _flame_resonance(acc: Dictionary, pattern, _ctx: Dictionary) -> void:
	var mult := float(pattern.effect_params.get("damage_mult", 1.25))
	var fire := float((acc["dmg_by_elem"] as Dictionary).get("fire", 0.0))
	if fire > 0.0 and mult > 1.0:
		var bonus := fire * (mult - 1.0)
		acc["dmg"] = float(acc["dmg"]) + bonus
		if acc.has("lines"):
			acc["lines"].append("   🔥 烈焰共鸣：火系伤害 +%d%%（+%d）" % [
				int(round((mult - 1.0) * 100.0)), int(round(bonus))])
	_add_status(acc, "burn", int(pattern.effect_params.get("burn_extra", 0)))


# S02：火、冰伤害的 20% 转穿透；燃烧与霜冻各 +1 层。
# 只从「真正进了 acc["dmg"] 的那部分」转移，避免把本来就在 pierce 里的伤害算两次。
static func _frostfire_dual(acc: Dictionary, pattern, _ctx: Dictionary) -> void:
	var ratio := float(pattern.effect_params.get("pierce_ratio", 0.2))
	var bucket: Dictionary = acc["dmg_bucket_by_elem"]
	var moved := 0.0
	for e in ["fire", "ice"]:
		var part := float(bucket.get(e, 0.0))
		if part <= 0.0:
			continue
		var take := part * ratio
		bucket[e] = part - take
		acc["dmg"] = float(acc["dmg"]) - take
		moved += take
	if moved > 0.0:
		acc["pierce"] = float(acc["pierce"]) + moved
		if acc.has("lines"):
			acc["lines"].append("   ❄️ 冰火二重：火冰伤害 %d%% 转穿透（%d）" % [
				int(round(ratio * 100.0)), int(round(moved))])
	_add_status(acc, "burn", int(pattern.effect_params.get("burn_extra", 0)))
	_add_status(acc, "frost", int(pattern.effect_params.get("frost_extra", 0)))


# S03：追加一次穿透齐射 = 两件来源武器「当前基础攻击」之和 × 50%。
# 来源武器从解锁条件的两条路径取，攻击读 weapon_power（已含槽位成长）。
static func _holy_volley(acc: Dictionary, pattern, ctx: Dictionary) -> void:
	var ratio := float(pattern.effect_params.get("attack_ratio", 0.5))
	var ctrl = ctx.get("ctrl")
	if ctrl == null:
		return
	var total_atk := 0.0
	for p in pattern.unlock_paths:
		total_atk += float(ctrl.weapon_power(String(p)))
	if total_atk <= 0.0:
		return
	var extra := total_atk * ratio
	acc["pierce"] = float(acc["pierce"]) + extra
	if acc.has("lines"):
		acc["lines"].append("   🌅 黎明圣辉：追加穿透齐射 %d（攻击和 %d ×%d%%）" % [
			int(round(extra)), int(round(total_atk)), int(round(ratio * 100.0))])


# W02 霜封连携：霜冻 +2；目标已有至少 threshold 层霜冻时，本次敌方攻击 ×mult。
# 「敌方攻击 ×0.8」写进 controller 的回合乘区，由 enemy_deal_damage 这个唯一闸口读取。
static func _frost_seal(acc: Dictionary, pattern, ctx: Dictionary) -> void:
	_add_status(acc, "frost", int(pattern.effect_params.get("frost_extra", 2)))
	var ctrl = ctx.get("ctrl")
	if ctrl == null:
		return
	var now := int(ctrl.enemy_status.get("frost", 0)) + int(pattern.effect_params.get("frost_extra", 2))
	var threshold := int(pattern.effect_params.get("threshold", 4))
	if now < threshold:
		return
	var mult := float(pattern.effect_params.get("enemy_atk_mult", 0.8))
	ctrl._pattern_enemy_atk_mult = float(ctrl._pattern_enemy_atk_mult) * mult
	if acc.has("lines"):
		acc["lines"].append("   ❄ 霜封连携：霜冻 %d 层（≥%d），本次敌方攻击 ×%d%%" % [
			now, threshold, int(round(mult * 100.0))])


# W05 暗影处刑：两张暗系伤害的 20% 转穿透；目标 HP 低于 35% 时提高到 35%。
# 只从「真正进了 acc["dmg"] 的暗伤害」里搬，避免与已在 pierce 的部分重复。
static func _shadow_execution(acc: Dictionary, pattern, ctx: Dictionary) -> void:
	var ctrl = ctx.get("ctrl")
	if ctrl == null:
		return
	var bucket: Dictionary = acc["dmg_bucket_by_elem"]
	var dark := float(bucket.get("dark", 0.0))
	if dark <= 0.0:
		return
	var hp_max := float(ctrl.enemy_hp_max)
	var ratio := float(pattern.effect_params.get("pierce_ratio", 0.2))
	var exec_th := float(pattern.effect_params.get("exec_threshold", 0.35))
	if hp_max > 0.0 and float(ctrl.enemy_hp) / hp_max < exec_th:
		ratio = float(pattern.effect_params.get("exec_ratio", 0.35))
	var take := dark * ratio
	bucket["dark"] = dark - take
	acc["dmg"] = float(acc["dmg"]) - take
	acc["pierce"] = float(acc["pierce"]) + take
	if acc.has("lines"):
		acc["lines"].append("   🌑 暗影处刑：暗系伤害 %d%% 转穿透（%d）" % [
			int(round(ratio * 100.0)), int(round(take))])


# W06 无锋磨砺：本轮无元素武器伤害 +20%。
# 「至少两个来源」在条件层暂未强制（solver 只保证不同牌），这里用 source_dmg 记录参与来源数。
static func _plain_grind(acc: Dictionary, pattern, _ctx: Dictionary) -> void:
	var mult := float(pattern.effect_params.get("damage_mult", 1.2))
	var none_dmg := float((acc["dmg_by_elem"] as Dictionary).get("none", 0.0))
	if none_dmg <= 0.0 or mult <= 1.0:
		return
	var bonus := none_dmg * (mult - 1.0)
	acc["dmg"] = float(acc["dmg"]) + bonus
	if acc.has("lines"):
		acc["lines"].append("   ⚔ 无锋磨砺：无元素伤害 +%d%%（+%d）" % [
			int(round((mult - 1.0) * 100.0)), int(round(bonus))])


# S04：中毒 +2 层；立即造成一次相当于标准毒结算 50% 的伤害，不消耗毒层。
#
# 「标准毒结算」的真实口径在 CombatSystem.tick_status()：
#     每跳 = 层数 × status_base("poison") × 元素倍率 × 状态护符乘区
# 这里按同一公式算「这次如果 tick 会打多少」，取 50% 作为即时伤害。
# 与 tick 的一处差别必须写明：tick 是 enemy_hp -= dot（完全裸伤害），而本效果走
# acc["pierce"]，会照常吃本轮强袭/增益/虚弱乘区——它是一次「穿透伤害」，
# 不是绕过结算的直扣。
static func _venom_burst(acc: Dictionary, pattern, ctx: Dictionary) -> void:
	var extra := int(pattern.effect_params.get("poison_extra", 2))
	_add_status(acc, "poison", extra)
	var ctrl = ctx.get("ctrl")
	if ctrl == null or ctrl.status_system == null:
		return
	var base := float(ctrl.status_system.status_base("poison"))
	if base <= 0.0:
		return
	# 结算时的层数 = 敌人现有毒层 + 本次新增（与 tick 读的 enemy_status 同源）
	var cur := int(ctrl.enemy_status.get("poison", 0))
	var total_stacks := cur + extra
	if total_stacks <= 0:
		return
	var mult: float = ElementCounter.multiplier("poison", String(ctrl.enemy_element))
	var boost := 1.0
	if int(ctrl.deprived_level) < 1:
		boost = float(ctrl.charm_status_boost)
	var full := float(total_stacks) * base * mult * boost
	var instant := full * float(pattern.effect_params.get("instant_ratio", 0.5))
	if instant <= 0.0:
		return
	acc["pierce"] = float(acc["pierce"]) + instant
	if acc.has("lines"):
		acc["lines"].append("   ☠ 毒爆连携：中毒 +%d 层，立即结算 %d（毒 tick %d ×%d%%，不消耗毒层）" % [
			extra, int(round(instant)), int(round(full)),
			int(round(float(pattern.effect_params.get("instant_ratio", 0.5)) * 100.0))])


# T01 增伤术式：本轮**武器**伤害 +15%；不强化技能伤害，不复制武器牌谱。
# 技能伤害从 source_dmg 里按「符号是否属于技能」筛出来扣掉，只对武器部分加成。
static func _power_support(acc: Dictionary, pattern, ctx: Dictionary) -> void:
	var ctrl = ctx.get("ctrl")
	if ctrl == null:
		return
	var total := 0.0
	for e in (acc["dmg_by_elem"] as Dictionary):
		total += float(acc["dmg_by_elem"][e])
	var skill_sum := 0.0
	for k in (acc["source_dmg"] as Dictionary):
		if ctrl._skill_sym_kind != null and ctrl._skill_sym_kind.has(String(k)):
			skill_sum += float(acc["source_dmg"][k])
	var weapon_dmg := maxf(0.0, total - skill_sum)
	var mult := float(pattern.effect_params.get("weapon_damage_mult", 1.15))
	if weapon_dmg <= 0.0 or mult <= 1.0:
		return
	var bonus := weapon_dmg * (mult - 1.0)
	acc["dmg"] = float(acc["dmg"]) + bonus
	if acc.has("lines"):
		acc["lines"].append("   ✦ 增伤术式：武器伤害 +%d%%（+%d，技能伤害不计入）" % [
			int(round((mult - 1.0) * 100.0)), int(round(bonus))])


# T02 防御术式：额外护盾；敌方当前是蓄力/重击意图时给更高的值。
static func _defense_support(acc: Dictionary, pattern, ctx: Dictionary) -> void:
	var ctrl = ctx.get("ctrl")
	if ctrl == null:
		return
	var flat := float(pattern.effect_params.get("shield_flat", 8.0))
	var heavy := float(pattern.effect_params.get("shield_heavy", 12.0))
	var t := String(ctrl.enemy_intent.get("type", ""))
	var gain := heavy if (t == "heavy" or t == "charge") else flat
	acc["shield"] = float(acc["shield"]) + gain
	if acc.has("lines"):
		acc["lines"].append("   🛡 防御术式：护盾 +%d（意图 %s）" % [int(round(gain)), t if t != "" else "无"])


# T03 恢复术式：本轮治疗 +25%；HP 不高于 50% 时额外净化一个可净化减益。
# 满血时不应激活 —— 由 CombatSystem 在选牌阶段排除（见 _apply_patterns）。
static func _recovery_support(acc: Dictionary, pattern, ctx: Dictionary) -> void:
	var ctrl = ctx.get("ctrl")
	if ctrl == null:
		return
	var heal := float(acc["heal"])
	var mult := float(pattern.effect_params.get("heal_mult", 1.25))
	if heal > 0.0 and mult > 1.0:
		var bonus := heal * (mult - 1.0)
		acc["heal"] = heal + bonus
		if acc.has("lines"):
			acc["lines"].append("   ✚ 恢复术式：治疗 +%d%%（+%d）" % [
				int(round((mult - 1.0) * 100.0)), int(round(bonus))])
	# 低血线净化：走 debuff_system.purify_one（与消耗品共用同一套优先级）
	var th := float(pattern.effect_params.get("low_hp_threshold", 0.5))
	if float(ctrl.player_hp_max) > 0.0 and float(ctrl.player_hp) / float(ctrl.player_hp_max) <= th:
		var removed := ""
		if ctrl.debuffs != null:
			removed = String(ctrl.debuffs.purify_one(ctrl))
		acc["recovery_purify"] = removed != ""
		if acc.has("lines"):
			if removed != "":
				acc["lines"].append("   ✚ 恢复术式：低血线（≤%d%%），净化「%s」" % [
					int(round(th * 100.0)), ctrl.debuffs.name_of(removed)])
			else:
				acc["lines"].append("   ✚ 恢复术式：低血线（≤%d%%），但没有可净化的减益" % int(round(th * 100.0)))


# 牌谱新增的状态层：写入独立字段，由 CombatSystem 在牌谱结算后统一落地。
# 不能直接写 acc["status_stacks"]——那一份在 _phase_defense 已经落地过了，
# 牌谱阶段再改它不会进入 enemy_status（Step 2 曾因此静默失效）。
static func _add_status(acc: Dictionary, status: String, n: int) -> void:
	if n <= 0:
		return
	if not acc.has("pattern_status"):
		acc["pattern_status"] = {}
	var ps: Dictionary = acc["pattern_status"]
	ps[status] = int(ps.get(status, 0)) + n
