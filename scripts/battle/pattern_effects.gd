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
	"frostfire_dual": "冰火二重",
	"holy_volley": "黎明圣辉",
	"venom_burst": "毒爆连携",
	"shield_bash": "盾击连携",
	"arcane_loop": "奥术回路",
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
		"shield_bash":
			_shield_bash(acc, pattern, ctx)
		"arcane_loop":
			_arcane_loop(acc, pattern, ctx)
		"venom_burst":
			_venom_burst(acc, pattern, ctx)
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


# S05：额外 +8 护盾；随后造成本轮实际护盾获得量 50% 的伤害。
# 「实际护盾获得量」= acc["shield"]（已由 _phase_defense 与盾符号累计）。
static func _shield_bash(acc: Dictionary, pattern, _ctx: Dictionary) -> void:
	var flat := float(pattern.effect_params.get("shield_flat", 8.0))
	var ratio := float(pattern.effect_params.get("damage_ratio", 0.5))
	acc["shield"] = float(acc["shield"]) + flat
	var gained := float(acc["shield"])
	var dmg := gained * ratio
	if dmg > 0.0:
		acc["dmg"] = float(acc["dmg"]) + dmg
	if acc.has("lines"):
		acc["lines"].append("   🛡 盾击连携：护盾 +%d，转伤害 %d（护盾量 %d ×%d%%）" % [
			int(round(flat)), int(round(dmg)), int(round(gained)), int(round(ratio * 100.0))])


# S06：充能 +2；若因此充满，本次元素爆发伤害 +25%。
# 爆炸加成标记由元素爆发流程读取（acc["burst_bonus"]），不在本阶段直接结算。
static func _arcane_loop(acc: Dictionary, pattern, ctx: Dictionary) -> void:
	var charge := int(pattern.effect_params.get("charge", 2))
	var ctrl = ctx.get("ctrl")
	if ctrl == null or charge <= 0:
		return
	var before := int(ctrl.charge_points)
	ctrl.charge_points = before + charge
	var cap := int(ctrl.CHARGE_MAX) if ctrl.get("CHARGE_MAX") != null else before + charge
	if before < cap and int(ctrl.charge_points) >= cap:
		acc["burst_bonus"] = float(acc.get("burst_bonus", 1.0)) * float(pattern.effect_params.get("burst_mult", 1.25))
		if acc.has("lines"):
			acc["lines"].append("   ✨ 奥术回路：充能 +%d 并充满，元素爆发 +%d%%" % [
				charge, int(round((float(pattern.effect_params.get("burst_mult", 1.25)) - 1.0) * 100.0))])
	else:
		if acc.has("lines"):
			acc["lines"].append("   ✨ 奥术回路：充能 +%d" % charge)


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
