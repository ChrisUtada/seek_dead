extends Node

# ============================================================================
# 成长三选一生成/结算流程回归（2026-11-20 现代化重写）
# 旧版基于 mastery/symbol/perk/maxhp/... 枚举；G5/G7-C 奖励定义重构后统一为
# kind="reward_definition" + id/effect_id（见 reward_resolver）。本测试验证等价流程：
#   ① 结构合法（成长限定三选一、字段完整、不直接给装备）
#   ② 候选可结算（每个候选都能成功 settle；效果真实性由 p02/reward_p2 专项覆盖）
#   ③ 重抽/跳过行为
#   ④ 宝箱/BOSS 池仍提供装备
#   ⑤ R4 满级武器不再产出训练候选
# ============================================================================

const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"
const ICE_STAFF := "res://resources/weapon_templates/ice_staff.tres"
const FLAME_STAFF := "res://resources/weapon_templates/flame_staff.tres"

var _checks := 0
var _fails := 0
var _duel: DuelController


func _ready() -> void:
	await _boot()
	_test_growth_structure()
	_test_candidates_settle()
	_test_reroll_skip_and_sources()
	_test_r4_no_training()
	print("---")
	print("GROWTHLOOT|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> void:
	if _duel != null and is_instance_valid(_duel):
		_duel.queue_free()
	_duel = load("res://scenes/duel/duel.tscn").instantiate()
	add_child(_duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_duel.selected_loadout.assign([FIRE_SWORD, ICE_STAFF])
	_duel.selected_consumables.clear()
	_duel.selected_charms.clear()
	_duel.selected_skills.clear()
	_duel._confirm_loadout()
	_duel.growth.perk_ids.clear()
	_duel.gold = 10000


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("GROWTHLOOT|FAIL|" + msg)


func _offer() -> Dictionary:
	for i in 40:
		var view: Dictionary = _duel._reward_system.build_loot_offer("normal", 1, {"growth_only": true}, "common")
		if not view.is_empty():
			return view
	return {}


func _test_growth_structure() -> void:
	var view: Dictionary = _offer()
	_check(bool(view.get("growth_only", false)), "普通战明确标记为成长三选一")
	var opts: Array = view.get("options", [])
	_check(opts.size() == 3, "成长奖励固定三项")
	var has_item := false
	for opt in opts:
		var kind := String(opt.get("kind", ""))
		if kind == "item":
			has_item = true
		if kind == "reward_definition":
			_check(String(opt.get("id", "")) != "", "成长候选带 id")
			_check(String(opt.get("effect_id", "")) != "", "成长候选带 effect_id")
			_check(opt.has("result") and opt.has("condition"), "成长候选带结果/条件文案")
		else:
			_check(false, "未知成长类型：" + kind)
	_check(not has_item, "普通战不直接授予武器、护符或消耗品")


# 新系统一组三选一只能结算一次；每个候选单独开一组验证可结算
func _test_candidates_settle() -> void:
	for i in range(3):
		await _boot()   # 每组结算互相独立（一组三选一只能结算一次）
		var view: Dictionary = _offer()
		var opts: Array = view.get("options", [])
		if i >= opts.size():
			break
		var opt: Dictionary = opts[i]
		var res: Dictionary = _duel._reward_system.settle_loot_offer(i)
		_check(bool(res.get("ok", false)), "候选 %d（%s）结算成功（%s）" % [
			i, String(opt.get("id", "")), String(res.get("reason", ""))])
		if i == 0:
			_check(_duel._reward_system.settle_loot_offer(0).get("ok") == false, "同组不可二次结算")


func _test_reroll_skip_and_sources() -> void:
	await _boot()
	var view: Dictionary = _offer()
	var q := String(view.get("quality", ""))
	var next: Dictionary = _duel._reward_system.reroll_loot_offer()
	_check(String(next.get("quality", "")) == q and int(next.get("reroll_cost", 0)) == 10
		and bool(next.get("growth_only", false)), "成长重抽保持品质、成长标记和下一次费用")
	var gold0 := int(_duel.gold)
	var power0 := int(_duel._reward_system.run_power_bonus)
	var skipped: Dictionary = _duel._reward_system.settle_loot_skip()
	_check(bool(skipped.get("ok", false)) and int(_duel.gold) == gold0
		and int(_duel._reward_system.run_power_bonus) == power0, "免费跳过不发收益")

	var chest: Dictionary = _duel._reward_system.build_loot_offer("chest", 1, {}, "common")
	var chest_items := 0
	for opt in chest.get("options", []):
		if String(opt.get("kind", "")) == "item":
			chest_items += 1
	_check(chest_items > 0 and not bool(chest.get("growth_only", false)), "探索宝箱仍提供装备而非成长限定")

	var boss: Dictionary = _duel._reward_system.build_loot_offer("boss", 1,
		{"theme": [FLAME_STAFF], "categories": ["weapon"]}, "epic")
	var boss_item := false
	for opt in boss.get("options", []):
		if String(opt.get("kind", "")) == "item" and String(opt.get("path", "")) == FLAME_STAFF:
			boss_item = true
	_check(boss_item, "BOSS主题池仍保留专属武器")


func _test_r4_no_training() -> void:
	await _boot()
	_offer()
	_duel.mastery.grant_points(FIRE_SWORD, 12)
	_check(int(_duel.mastery.r_level(FIRE_SWORD)) == 4, "火焰剑已到 R4")
	# 新口径：训练候选 id 形如 mastery_<weapon>，effect_id 含 mastery
	var view: Dictionary = _offer()
	var has_fire := false
	var has_staff := false
	for opt in view.get("options", []):
		var oid := String(opt.get("id", ""))
		var eid := String(opt.get("effect_id", ""))
		if eid.contains("mastery") or oid.begins_with("mastery"):
			if oid.contains("fire_sword"):
				has_fire = true
			if oid.contains("ice_staff"):
				has_staff = true
	_check(not has_fire, "R4 满级武器不再产出训练候选")
	_check(has_staff, "未满级武器可产出训练候选（若本次抽到）")
