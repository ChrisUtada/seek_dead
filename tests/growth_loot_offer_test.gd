extends Node

const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"
const ICE_STAFF := "res://resources/weapon_templates/ice_staff.tres"
const FLAME_STAFF := "res://resources/weapon_templates/flame_staff.tres"
const GROWTH_KINDS := ["mastery", "symbol", "perk", "maxhp", "shield", "heal", "queued_growth"]

var _checks := 0
var _fails := 0
var _duel: DuelController


func _ready() -> void:
	await _boot()
	_test_growth_structure()
	_test_each_growth_effect()
	_test_reroll_skip_and_sources()
	_test_r4_no_training()
	print("---")
	print("GROWTHLOOT|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> void:
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


# 方案 §4.6：R4 满级后再加熟练不产生任何解锁，训练候选不得再出现。
func _test_r4_no_training() -> void:
	_offer()   # 确保成长候选实例已建立
	_duel.mastery.grant_points(FIRE_SWORD, 12)
	_check(int(_duel.mastery.r_level(FIRE_SWORD)) == 4, "火焰剑已到 R4")
	var cands: Array = _duel._reward_system._loot_offer._growth_candidates()
	var has_fire := false
	for c in cands:
		if String(c.get("kind", "")) == "mastery" and String(c.get("path", "")) == FIRE_SWORD:
			has_fire = true
	_check(not has_fire, "R4 满级武器不再产出训练候选")
	var has_staff := false
	for c in cands:
		if String(c.get("kind", "")) == "mastery" and String(c.get("path", "")) == ICE_STAFF:
			has_staff = true
	_check(has_staff, "未满级的另一把仍保留训练候选")


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("GROWTHLOOT|FAIL|" + msg)


func _offer(kind: String = "") -> Dictionary:
	for i in 40:
		var view: Dictionary = _duel._reward_system.build_loot_offer("normal", 1, {"growth_only": true}, "common")
		if kind == "":
			return view
		for opt in view.get("options", []):
			if String(opt.get("kind", "")) == kind:
				return view
	return {}


func _index_of(view: Dictionary, kind: String) -> int:
	var opts: Array = view.get("options", [])
	for i in range(opts.size()):
		if String(opts[i].get("kind", "")) == kind:
			return i
	return -1


func _test_growth_structure() -> void:
	var view: Dictionary = _offer()
	_check(bool(view.get("growth_only", false)), "普通战明确标记为成长三选一")
	var opts: Array = view.get("options", [])
	_check(opts.size() == 3, "成长奖励固定三项")
	var kinds := {}
	var has_item := false
	for opt in opts:
		var kind := String(opt.get("kind", ""))
		kinds[kind] = true
		if kind == "item":
			has_item = true
		if kind not in GROWTH_KINDS and kind != "conversion":
			_check(false, "出现未知成长类型：" + kind)
	_check(not has_item, "普通战不直接授予武器、护符或消耗品")
	_check(kinds.size() >= 2, "成长候选至少覆盖两种用途")


func _test_each_growth_effect() -> void:
	var view: Dictionary = _offer("mastery")
	var idx := _index_of(view, "mastery")
	var points0 := int(_duel.mastery.mastery.get(FIRE_SWORD, 0)
		+ _duel.mastery.mastery.get(ICE_STAFF, 0))
	var weapon_count := _duel.selected_loadout.size()
	var res: Dictionary = _duel._reward_system.settle_loot_offer(idx)
	var points1 := int(_duel.mastery.mastery.get(FIRE_SWORD, 0)
		+ _duel.mastery.mastery.get(ICE_STAFF, 0))
	_check(bool(res.get("ok", false)) and points1 > points0 and _duel.selected_loadout.size() == weapon_count,
		"武器训练真实增加熟练且不新增武器")

	view = _offer("symbol")
	idx = _index_of(view, "symbol")
	var opt: Dictionary = _duel._reward_system.loot_offer_option(idx)
	var before := int(opt.get("before", 0))
	var after := int(opt.get("after", 0))
	res = _duel._reward_system.settle_loot_offer(idx)
	_check(bool(res.get("ok", false)) and after > before
		and int(res.get("after", 0)) == after, "符号灌注按预览真实增加带格数")

	view = _offer("perk")
	idx = _index_of(view, "perk")
	opt = _duel._reward_system.loot_offer_option(idx)
	res = _duel._reward_system.settle_loot_offer(idx)
	_check(bool(res.get("ok", false)) and _duel.growth.perk_ids.has(String(opt.get("perk_id", ""))),
		"技艺直接习得")

	view = _offer("maxhp")
	idx = _index_of(view, "maxhp")
	var hp0 := int(_duel.player_hp)
	var max0 := int(_duel.player_hp_max)
	res = _duel._reward_system.settle_loot_offer(idx)
	_check(bool(res.get("ok", false)) and int(_duel.player_hp_max) == max0 + 5
		and int(_duel.player_hp) == hp0 + 5, "最大HP与当前HP同时增加")

	view = _offer("shield")
	idx = _index_of(view, "shield")
	var shield0 := int(_duel._reward_system.run_shield_next)
	res = _duel._reward_system.settle_loot_offer(idx)
	_check(bool(res.get("ok", false)) and int(_duel._reward_system.run_shield_next) == shield0 + 8,
		"守望增加下一场战斗开局护盾")

	_duel.player_hp = 50
	var heal_expected: int = 50 + int(_duel.player_hp_max * 0.35)
	view = _offer("heal")
	idx = _index_of(view, "heal")
	res = _duel._reward_system.settle_loot_offer(idx)
	_check(bool(res.get("ok", false)) and int(_duel.player_hp) == heal_expected, "未满血时休整恢复35%生命")


func _test_reroll_skip_and_sources() -> void:
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
