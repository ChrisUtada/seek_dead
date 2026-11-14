extends Node

# ============================================================================
# 四级品质战利品 · Step 4 · 同层三选一与冻结 payload · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/loot_offer_test.tscn
#
# 覆盖（docs/四级品质战利品与大奖池_分步执行计划_2026-11-12.md Step 4）：
# ① 每组恰好 3 项，同品质层，路径不重复，至少两种用途；
# ② 每项都有真实可结算效果：物品授予 / 重复转金币 / 同层转化（金币或伤害）；
# ③ 同层不足时用同层转化补齐，不跨品质；空主题池也有 3 项合法出口；
# ④ 重复装备、满腰带、满护符槽 → 展示为同层金币转化；
# ⑤ 重抽沿用品质层并递增收费；跳过固定免费且零收益；
# ⑥ 生成与重抽不消耗全局/地图 RNG。
# ============================================================================

const FLAME_STAFF := "res://resources/weapon_templates/flame_staff.tres"
const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"
const ICE_GUN := "res://resources/weapon_templates/ice_gun.tres"
const ICE_STAFF := "res://resources/weapon_templates/ice_staff.tres"
const BUILDS := 40
const REROLLS := 30

var _checks := 0
var _fails := 0


func _ready() -> void:
	await _run()
	print("---")
	print("LOOTOFFER|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	await get_tree().process_frame
	var duel: DuelController = await _boot()
	if duel == null:
		print("LOOTOFFER|RESULT FAIL (boot)")
		get_tree().quit(2)
		return
	_test_same_tier_three(duel)
	_test_short_tier_conversions(duel)
	_test_duplicate_and_overflow(duel)
	_test_needs_replace(duel)
	_test_empty_theme(duel)
	_test_reroll_keeps_quality(duel)
	_test_skip_frozen(duel)
	_test_owned_not_filtered(duel)
	_test_freeze_snapshot(duel)
	_test_rng_isolation(duel)


func _boot() -> DuelController:
	var duel: DuelController = load("res://scenes/duel/duel.tscn").instantiate()
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	return duel


func _rarity_of(path: String) -> String:
	var res: Resource = load(path)
	return String(res.get("rarity")) if res != null and res.get("rarity") != null else "common"


func _item_paths(options: Array) -> Array:
	var out: Array = []
	for o in options:
		if String(o.get("kind", "")) == "item":
			out.append(String(o.get("path", "")))
	return out


func _item_options(options: Array) -> Array:
	var out: Array = []
	for o in options:
		if String(o.get("kind", "")) == "item":
			out.append(o)
	return out


func _roles(options: Array) -> Dictionary:
	var out := {}
	for o in options:
		out[String(o.get("purpose", ""))] = true
	return out


func _has_real_effect(o: Dictionary) -> bool:
	if String(o.get("kind", "")) == "item":
		if String(o.get("path", "")) == "":
			return false
		if String(o.get("grant", "")) == "gold":
			return int(o.get("gold", 0)) > 0
		return true
	return int(o.get("gold", 0)) > 0 or int(o.get("power", 0)) > 0


# ① 三来源 × 三幕：恰好 3 项、同层、不重复、两种用途、文案与效果完整
func _test_same_tier_three(duel: DuelController) -> void:
	seed(43001)
	duel._reset_run_state()
	var bad_size := 0
	var bad_quality := 0
	var dup := 0
	var bad_roles := 0
	var bad_text := 0
	var bad_effect := 0
	var builds := 0
	for source in ["normal", "elite", "boss"]:
		for act in [1, 2, 3]:
			for i in BUILDS:
				var res: Dictionary = duel._reward_system.build_loot_offer(source, act, {})
				builds += 1
				if not bool(res.get("ok", false)):
					bad_size += 1
					continue
				var options: Array = res["options"]
				var q := String(res["quality"])
				if options.size() != 3:
					bad_size += 1
				var seen := {}
				for o in options:
					if String(o.get("kind", "")) == "item":
						var p := String(o["path"])
						if _rarity_of(p) != q:
							bad_quality += 1
						if seen.has(p):
							dup += 1
						seen[p] = true
					if String(o.get("title", "")) == "" or String(o.get("desc", "")) == "":
						bad_text += 1
					if not _has_real_effect(o):
						bad_effect += 1
				if _roles(options).size() < 2:
					bad_roles += 1
	_check(bad_size == 0, "每组恰好 3 项（%d 组，异常 %d）" % [builds, bad_size])
	_check(bad_quality == 0, "物品候选全部同品质（越层 %d）" % bad_quality)
	_check(dup == 0, "同组路径不重复（重复 %d）" % dup)
	_check(bad_roles == 0, "每组至少两种用途（异常 %d）" % bad_roles)
	_check(bad_text == 0, "每项标题/描述非空（空项 %d）" % bad_text)
	_check(bad_effect == 0, "每项都有真实可结算效果（空效果 %d）" % bad_effect)

	# 同层分组充足时（normal act1）三项应尽量来自不同 unique_group，避免换皮。
	var group_dup := 0
	for i in BUILDS:
		var res: Dictionary = duel._reward_system.build_loot_offer("normal", 1, {})
		var groups := {}
		for o in res.get("options", []):
			if String(o.get("kind", "")) != "item":
				continue
			var g := String(o.get("unique_group", ""))
			if g == "":
				continue
			if groups.has(g):
				group_dup += 1
			groups[g] = true
	_check(group_dup == 0, "同组 unique_group 不重复（重复 %d）" % group_dup)


# ② 同层不足 3 项：用同层转化补齐，不跨品质
func _test_short_tier_conversions(duel: DuelController) -> void:
	seed(43002)
	duel._reset_run_state()
	duel.selected_loadout.clear()
	var res: Dictionary = duel._reward_system.build_loot_offer("boss", 1,
		{"theme": [FLAME_STAFF]}, "epic")
	_check(bool(res.get("ok", false)) and String(res["quality"]) == "epic",
		"短层组仍定在 epic")
	var options: Array = res["options"]
	_check(options.size() == 3, "短层补齐到 3 项（%d）" % options.size())
	var items := _item_options(options)
	_check(items.size() == 1 and String(items[0]["path"]) == FLAME_STAFF,
		"短层只出 1 件真实物品（%d）" % items.size())
	var conversions := 0
	var conv_power := 0
	for o in options:
		if String(o.get("kind", "")) == "conversion":
			conversions += 1
			if String(o.get("conversion", "")) == "power":
				conv_power += 1
			if String(o.get("quality", "")) != "epic":
				_check(false, "转化项品质必须同为 epic")
	_check(conversions == 2, "短层用 2 项同层转化补齐（%d）" % conversions)
	_check(conv_power >= 1, "转化覆盖伤害强化（power %d）" % conv_power)


# ③ 重复装备 / 满腰带 / 满护符槽 → 熟练或金币转化
func _test_duplicate_and_overflow(duel: DuelController) -> void:
	seed(43003)
	duel._reset_run_state()
	duel.selected_loadout.clear()
	duel.selected_loadout.assign([FLAME_STAFF])
	var dup_res: Dictionary = duel._reward_system.build_loot_offer("boss", 1,
		{"theme": [FLAME_STAFF]}, "epic")
	var dup_items := _item_options(dup_res["options"])
	_check(dup_items.size() == 1 and String(dup_items[0]["grant"]) == "mastery"
		and int(dup_items[0]["mastery"]) > 0,
		"已装备武器展示为同层熟练转化")
	duel.selected_loadout.clear()

	duel.consumable_slots.clear()
	for i in duel.CONSUMABLE_CAP:
		duel.consumable_slots.append({"path": "", "item_id": "filler", "charges": 1, "uid": "f%d" % i})
	var belt_res: Dictionary = duel._reward_system.build_loot_offer("normal", 1,
		{"categories": ["active"]}, "common")
	var belt_items := _item_options(belt_res["options"])
	var belt_gold := 0
	for o in belt_items:
		if String(o.get("grant", "")) == "gold":
			belt_gold += 1
	_check(belt_items.size() > 0 and belt_gold == belt_items.size(),
		"腰带满时 active 候选全部转金币（%d/%d）" % [belt_gold, belt_items.size()])
	duel.consumable_slots.clear()

	duel.selected_charms.clear()
	duel.charm_max = duel.CHARM_CAP   # 触顶：不能再开槽，候选必须转金币
	var passive_paths := []
	for p in duel.ITEM_POOL:
		var d: Resource = load(p)
		if d != null and String(d.get("category")) == "passive" and not String(p).contains("_relic"):
			passive_paths.append(String(p))
		if passive_paths.size() >= duel._loadout_system.cat_max("passive"):
			break
	duel.selected_charms.assign(passive_paths)
	var charm_res: Dictionary = duel._reward_system.build_loot_offer("elite", 2,
		{"categories": ["passive"]}, "rare")
	var charm_items := _item_options(charm_res["options"])
	var charm_gold := 0
	for o in charm_items:
		if String(o.get("grant", "")) == "gold":
			charm_gold += 1
	_check(charm_items.size() > 0 and charm_gold == charm_items.size(),
		"护符槽满时 passive 候选全部转金币（%d/%d）" % [charm_gold, charm_items.size()])
	duel.selected_charms.clear()


# ③b 武器槽满时，新武器候选冻结「必须替换」标记（替换对象由玩家在确认层选择）
func _test_needs_replace(duel: DuelController) -> void:
	seed(43010)
	duel._reset_run_state()
	duel.selected_loadout.assign([FIRE_SWORD, ICE_GUN])
	var res: Dictionary = duel._reward_system.build_loot_offer("normal", 1,
		{"theme": [FIRE_SWORD, ICE_GUN, ICE_STAFF], "categories": ["weapon"]}, "rare")
	var found := false
	for o in _item_options(res["options"]):
		if String(o["path"]) == ICE_STAFF:
			found = String(o["grant"]) == "item" and bool(o.get("needs_replace", false))
	_check(found, "武器槽满时新武器候选冻结 needs_replace")
	duel.selected_loadout.clear()


# ④ 空主题池：仍有 3 项同层合法出口
func _test_empty_theme(duel: DuelController) -> void:
	seed(43004)
	duel._reset_run_state()
	var res: Dictionary = duel._reward_system.build_loot_offer("boss", 1,
		{"theme": []}, "rare")
	_check(bool(res.get("ok", false)) and String(res["quality"]) == "rare",
		"空主题池仍定层（rare）")
	var options: Array = res["options"]
	_check(options.size() == 3, "空主题池补齐到 3 项（%d）" % options.size())
	var all_conv := true
	for o in options:
		if String(o.get("kind", "")) != "conversion" or not _has_real_effect(o):
			all_conv = false
	_check(all_conv, "空主题池全部为同层转化")


# ⑤ 重抽沿用品质，并按 5/10/15…收费；跳过保持免费
func _test_reroll_keeps_quality(duel: DuelController) -> void:
	seed(43005)
	duel._reset_run_state()
	duel.gold = 10000
	var res: Dictionary = duel._reward_system.build_loot_offer("elite", 2, {}, "rare")
	var q := String(res["quality"])
	var skip0: Dictionary = res["skip"]
	var first := _item_paths(res["options"])
	var changed := false
	var bad_q := 0
	var spent := 0
	for i in REROLLS:
		var r: Dictionary = duel._reward_system.reroll_loot_offer()
		spent += 5 * (i + 1)
		if String(r["quality"]) != q:
			bad_q += 1
		for o in r["options"]:
			if String(o.get("kind", "")) == "item" and _rarity_of(String(o["path"])) != q:
				bad_q += 1
		if _item_paths(r["options"]) != first:
			changed = true
	_check(bad_q == 0, "重抽不改变品质层（越层 %d）" % bad_q)
	_check(changed, "重抽能换出不同候选")
	_check(duel._reward_system.loot_offer_skip() == skip0, "重抽不改变免费跳过")
	_check(duel.gold == 10000 - spent, "30 次重抽按递增价格累计扣费 %d" % spent)
	_check(int(duel._reward_system.loot_offer_view().get("reroll_cost", 0)) == 5 * (REROLLS + 1),
		"按钮数据展示下一次递增费用（实际 %d / 预期 %d）" % [int(duel._reward_system.loot_offer_view().get("reroll_cost", 0)), 5 * (REROLLS + 1)])
	duel.gold = 0
	var denied: Dictionary = duel._reward_system.reroll_loot_offer()
	_check(not bool(denied.get("ok", true)) and String(denied.get("reason", "")) == "insufficient_gold"
		and duel.gold == 0, "金币不足时拒绝重抽且不扣费")


# ⑥ 跳过免费且不发奖励
func _test_skip_frozen(duel: DuelController) -> void:
	seed(43006)
	duel._reset_run_state()
	for q in LootSourceTable.QUALITIES:
		var res: Dictionary = duel._reward_system.build_loot_offer("normal", 1, {}, q)
		var skip: Dictionary = res["skip"]
		_check(String(skip.get("kind", "")) == "skip" and int(skip.get("gold", -1)) == 0
			and int(skip.get("power", -1)) == 0,
			"%s 跳过为免费且收益为0" % q)
		_check(String(skip.get("title", "")) != "" and String(skip.get("desc", "")) != "",
			"免费跳过有展示文案")


# ⑦ 图鉴已解锁 ≠ 本局重复：未装备的已解锁武器仍是正常物品候选
func _test_owned_not_filtered(duel: DuelController) -> void:
	seed(43007)
	duel._reset_run_state()
	duel.selected_loadout.clear()
	if not duel.meta["owned_weapons"].has(FLAME_STAFF):
		duel.meta["owned_weapons"].append(FLAME_STAFF)
	var res: Dictionary = duel._reward_system.build_loot_offer("boss", 1,
		{"theme": [FLAME_STAFF]}, "epic")
	var items := _item_options(res["options"])
	_check(items.size() == 1 and String(items[0]["grant"]) == "item",
		"图鉴已解锁但本局未装备 → 仍按物品候选")
	duel.selected_loadout.clear()


# ⑧ 冻结：重抽不修改已返回的候选与跳过收益
func _test_freeze_snapshot(duel: DuelController) -> void:
	seed(43008)
	duel._reset_run_state()
	duel.gold = 5
	var res: Dictionary = duel._reward_system.build_loot_offer("normal", 1, {}, "common")
	var snap: Array = (res["options"] as Array).duplicate(true)
	var skip_snap: Dictionary = (res["skip"] as Dictionary).duplicate(true)
	duel._reward_system.reroll_loot_offer()
	_check(res["options"] == snap, "重抽不修改已返回的冻结候选")
	_check(res["skip"] == skip_snap, "重抽不修改已返回的跳过收益")


# ⑨ 生成/重抽不消耗全局 RNG
func _test_rng_isolation(duel: DuelController) -> void:
	seed(43009)
	var before := randi()
	seed(43009)
	for i in 200:
		duel._reward_system.build_loot_offer("normal", 1, {})
	var after := randi()
	_check(before == after, "LootOffer 生成不消耗全局 RNG")


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("PASS  ", label)
	else:
		_fails += 1
		printerr("FAIL  ", label)
