extends Node

# ============================================================================
# 四级品质战利品 · Step 6 · 重复转化、成长队列与图鉴 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/loot_growth_test.tscn
#
# 覆盖（docs/四级品质战利品与大奖池_分步执行计划_2026-11-12.md Step 6）：
# ① 本局已装备武器的重复候选 → 同层熟练转化（不是金币），展示值 = 结算值；
# ② 重复转化只执行一次：重复结算 / 重抽 / 回访不会二次加熟练或二次发奖；
# ③ 已选成长只生效一次；未选铭印与待选技艺在结算后清空，重抽不重复发放；
# ④ 重复护符 / 满腰带 → 既有金币转化；普通授予只发一次；
# ⑤ 图鉴记录实际获得与来源：owned_* + item_sources 带 loot_source，来源文案一致；
# ⑥ 最高熟练写入图鉴；已收藏物品仍可作为本局候选。
# ============================================================================

const FLAME_STAFF := "res://resources/weapon_templates/flame_staff.tres"
const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"
const ICE_GUN := "res://resources/weapon_templates/ice_gun.tres"

var _checks := 0
var _fails := 0


func _ready() -> void:
	await _run()
	print("---")
	print("LOOTGROWTH|RESULT %s (checks=%d fails=%d)"
		% ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	await get_tree().process_frame
	var duel: DuelController = await _boot()
	if duel == null:
		print("LOOTGROWTH|RESULT FAIL (boot)")
		get_tree().quit(2)
		return
	_test_duplicate_mastery_payload(duel)
	_test_settle_once(duel)
	_test_reroll_no_growth(duel)
	_test_conversion_and_skip_once(duel)
	_test_item_grant_codex(duel)
	_test_duplicate_charm_gold(duel)
	_test_full_belt_gold(duel)
	_test_failed_settle_not_consumed(duel)
	_test_codex_best_mastery(duel)


func _boot() -> DuelController:
	var duel: DuelController = load("res://scenes/duel/duel.tscn").instantiate()
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	return duel


func _item_options(options: Array) -> Array:
	var out: Array = []
	for o in options:
		if String(o.get("kind", "")) == "item":
			out.append(o)
	return out


func _option_index(options: Array, key: String, value: Variant) -> int:
	for i in range(options.size()):
		if String(options[i].get(key, "")) == String(value):
			return i
	return -1


func _conversion_index(options: Array, conv: String) -> int:
	for i in range(options.size()):
		var o: Dictionary = options[i]
		if String(o.get("kind", "")) == "conversion" and String(o.get("conversion", "")) == conv:
			return i
	return -1


func _common_charm(duel: DuelController) -> String:
	for p in duel.ITEM_POOL:
		var s := String(p)
		if s.get_file().contains("_relic"):
			continue
		var d: Resource = load(s)
		if d is ItemData and String(d.category) == "passive" and String(d.rarity) == "common":
			return s
	return ""


func _rarity_of(path: String) -> String:
	var res: Resource = load(path)
	return String(res.get("rarity")) if res != null and res.get("rarity") != null else ""


# ---------------------------------------------------------------------------
# ① 重复武器 payload = 熟练，不是金币
# ---------------------------------------------------------------------------

func _test_duplicate_mastery_payload(duel: DuelController) -> void:
	seed(46001)
	duel._reset_run_state()
	duel.selected_loadout.clear()
	duel.selected_loadout.assign([FLAME_STAFF])
	var res: Dictionary = duel._reward_system.build_loot_offer("boss", 1,
		{"theme": [FLAME_STAFF], "categories": ["weapon"]}, "epic")
	var items := _item_options(res["options"])
	var want := int(DuelController.BALANCE.loot_duplicate_mastery.get("epic", 0))
	_check(items.size() == 1 and String(items[0]["grant"]) == "mastery",
		"已装备武器候选标记为熟练转化（%d 项）" % items.size())
	_check(items.size() == 1 and int(items[0].get("mastery", 0)) == want,
		"熟练转化数值 = epic 配置 +%d（实测 %d）" % [want, int(items[0].get("mastery", -1))])
	_check(items.size() == 1 and String(items[0].get("title", "")).find("熟练") >= 0,
		"重复武器展示文案包含「熟练」")
	duel.selected_loadout.clear()


# ---------------------------------------------------------------------------
# ② 重复转化只执行一次
# ---------------------------------------------------------------------------

func _test_settle_once(duel: DuelController) -> void:
	seed(46002)
	duel._reset_run_state()
	duel.selected_loadout.clear()
	duel.selected_loadout.assign([FLAME_STAFF])
	var points0: int = int(duel.mastery.mastery.get(FLAME_STAFF, 0))
	var owed0: int = duel.mastery.owed.size()
	var res: Dictionary = duel._reward_system.build_loot_offer("boss", 1,
		{"theme": [FLAME_STAFF], "categories": ["weapon"]}, "epic")
	var idx := _option_index(res["options"], "grant", "mastery")
	_check(idx >= 0, "找到熟练转化选项")
	if idx < 0:
		return
	var settled: Dictionary = duel._reward_system.settle_loot_offer(idx)
	var want := int(DuelController.BALANCE.loot_duplicate_mastery.get("epic", 0))
	_check(bool(settled.get("ok", false)) and String(settled.get("kind", "")) == "mastery"
		and int(settled.get("mastery", 0)) == want,
		"结算重复武器 → 熟练 +%d" % want)
	_check(int(duel.mastery.mastery.get(FLAME_STAFF, 0)) == points0 + want,
		"熟练累计 = 展示值（%d → %d）" % [points0, int(duel.mastery.mastery.get(FLAME_STAFF, 0))])
	_check(duel.mastery.owed.is_empty(), "跨 R2 后未选铭印随结算清空（%d → 0）" % owed0)
	var again: Dictionary = duel._reward_system.settle_loot_offer(idx)
	_check(not bool(again.get("ok", true)) and String(again.get("reason", "")) == "already_settled",
		"重复结算返回 already_settled")
	_check(int(duel.mastery.mastery.get(FLAME_STAFF, 0)) == points0 + want
		and duel.mastery.owed.is_empty(), "重复结算不二次加熟练 / 不重复欠铭印")
	duel.selected_loadout.clear()


# ---------------------------------------------------------------------------
# ③ 重抽不碰成长队列
# ---------------------------------------------------------------------------

func _test_reroll_no_growth(duel: DuelController) -> void:
	seed(46003)
	duel._reset_run_state()
	duel.gold = 10000
	duel.selected_loadout.clear()
	duel.selected_loadout.assign([FLAME_STAFF])
	var points0: int = int(duel.mastery.mastery.get(FLAME_STAFF, 0))
	var owed0: int = duel.mastery.owed.size()
	var picks0: int = int(duel.growth.pending_picks)
	var res: Dictionary = duel._reward_system.build_loot_offer("boss", 1,
		{"theme": [FLAME_STAFF], "categories": ["weapon"]}, "epic")
	var last: Dictionary = res
	for i in 20:
		last = duel._reward_system.reroll_loot_offer()
	_check(int(duel.mastery.mastery.get(FLAME_STAFF, 0)) == points0
		and duel.mastery.owed.size() == owed0
		and int(duel.growth.pending_picks) == picks0,
		"20 次重抽不改变熟练 / 欠铭印 / 待选技艺")
	# 重抽后结算当前展示的选项：仍然只结算一次
	var now_idx := _option_index(last.get("options", []), "grant", "mastery")
	var settled: Dictionary = duel._reward_system.settle_loot_offer(now_idx)
	_check(bool(settled.get("ok", false)) and int(duel.mastery.mastery.get(FLAME_STAFF, 0)) == points0
		+ int(DuelController.BALANCE.loot_duplicate_mastery.get("epic", 0)),
		"重抽后结算仍按展示值推进成长")
	duel.selected_loadout.clear()


# ---------------------------------------------------------------------------
# ④ 同层转化 / 跳过只结算一次
# ---------------------------------------------------------------------------

func _test_conversion_and_skip_once(duel: DuelController) -> void:
	seed(46004)
	duel._reset_run_state()
	duel.selected_loadout.clear()
	duel.selected_loadout.assign([FLAME_STAFF])
	var res: Dictionary = duel._reward_system.build_loot_offer("boss", 1,
		{"theme": [FLAME_STAFF], "categories": ["weapon"]}, "epic")
	var pidx := _conversion_index(res["options"], "power")
	var power0: int = int(duel._reward_system.run_power_bonus)
	var want_p := int(DuelController.BALANCE.loot_conversion_power.get("epic", 0))
	var ps: Dictionary = duel._reward_system.settle_loot_offer(pidx)
	_check(bool(ps.get("ok", false)) and int(duel._reward_system.run_power_bonus) == power0 + want_p,
		"同层强化结算 +%d" % want_p)
	_check(not bool(duel._reward_system.settle_loot_offer(pidx).get("ok", true)),
		"同层强化重复结算被拒绝")

	var res2: Dictionary = duel._reward_system.build_loot_offer("boss", 1,
		{"theme": [FLAME_STAFF], "categories": ["weapon"]}, "epic")
	var gidx := _conversion_index(res2["options"], "gold")
	var gold0: int = duel.gold
	var want_g := int(DuelController.BALANCE.loot_conversion_gold.get("epic", 0))
	duel._reward_system.settle_loot_offer(gidx)
	_check(duel.gold == gold0 + want_g, "同层金币转化结算 +%d" % want_g)

	var res3: Dictionary = duel._reward_system.build_loot_offer("boss", 1,
		{"theme": [FLAME_STAFF], "categories": ["weapon"]}, "epic")
	var gold1: int = duel.gold
	var power1: int = int(duel._reward_system.run_power_bonus)
	var sk: Dictionary = duel._reward_system.settle_loot_skip()
	_check(bool(sk.get("ok", false)) and duel.gold == gold1
		and int(duel._reward_system.run_power_bonus) == power1,
		"免费跳过不发放金币、强化或物品")
	_check(not bool(duel._reward_system.settle_loot_skip().get("ok", true)),
		"重复跳过被拒绝")
	duel.selected_loadout.clear()


# ---------------------------------------------------------------------------
# ⑤ 普通授予：只发一次，并写入图鉴与真实来源
# ---------------------------------------------------------------------------

func _test_item_grant_codex(duel: DuelController) -> void:
	seed(46005)
	duel._reset_run_state()
	duel.selected_loadout.clear()
	duel.selected_charms.clear()
	duel.consumable_slots.clear()
	var res: Dictionary = duel._reward_system.build_loot_offer("normal", 1,
		{"categories": ["weapon"]}, "common")
	var idx := _option_index(res["options"], "grant", "item")
	_check(idx >= 0, "普通战利品包含可授予武器")
	if idx < 0:
		return
	var path := String(res["options"][idx]["path"])
	var settled: Dictionary = duel._reward_system.settle_loot_offer(idx)
	_check(bool(settled.get("ok", false)) and duel.selected_loadout.has(path),
		"结算后武器进入转轮带（%s）" % path.get_file().get_basename())
	_check(duel.meta["owned_weapons"].has(path), "武器写入图鉴 owned_weapons")
	var src: Array = (duel.meta["item_sources"].get(path, []) as Array)
	var last: Dictionary = src[src.size() - 1] if not src.is_empty() else {}
	_check(String(last.get("loot_source", "")) == "normal",
		"来源记录 loot_source = normal（实测 %s）" % String(last.get("loot_source", "")))
	var lines: Array[String] = duel._codex.source_lines(path)
	_check(not lines.is_empty() and lines[0].find("普通战利品") >= 0,
		"图鉴来源文案与获得通道一致（%s）" % (lines[0] if not lines.is_empty() else ""))
	var count_after: int = duel.selected_loadout.size()
	var again: Dictionary = duel._reward_system.settle_loot_offer(idx)
	_check(not bool(again.get("ok", true)) and duel.selected_loadout.size() == count_after,
		"重复结算不重复授予")
	duel.selected_loadout.clear()


# ---------------------------------------------------------------------------
# ⑥ 重复护符 → 金币（既有资源）
# ---------------------------------------------------------------------------

func _test_duplicate_charm_gold(duel: DuelController) -> void:
	seed(46006)
	duel._reset_run_state()
	var charm := _common_charm(duel)
	if charm == "":
		_fail("缺少 common 护符样本")
		return
	duel.selected_charms.clear()
	duel.selected_charms.assign([charm])
	var res: Dictionary = duel._reward_system.build_loot_offer("elite", 2,
		{"theme": [charm], "categories": ["passive"]}, "common")
	var items := _item_options(res["options"])
	_check(items.size() == 1 and String(items[0]["grant"]) == "gold",
		"已带护符候选标记为金币转化")
	var idx := _option_index(res["options"], "grant", "gold")
	var gold0: int = duel.gold
	var want := int(DuelController.BALANCE.loot_conversion_gold.get("common", 0))
	duel._reward_system.settle_loot_offer(idx)
	_check(duel.gold == gold0 + want, "重复护符结算金币 +%d" % want)
	duel.selected_charms.clear()


# ---------------------------------------------------------------------------
# ⑦ 满腰带 → 金币（既有资源）
# ---------------------------------------------------------------------------

func _test_full_belt_gold(duel: DuelController) -> void:
	seed(46007)
	duel._reset_run_state()
	duel.consumable_slots.clear()
	for i in duel.CONSUMABLE_CAP:
		duel.consumable_slots.append({"path": "", "item_id": "filler", "charges": 1, "uid": "f%d" % i})
	var res: Dictionary = duel._reward_system.build_loot_offer("normal", 1,
		{"categories": ["active"]}, "common")
	var idx := _option_index(res["options"], "grant", "gold")
	var gold0: int = duel.gold
	var want := int(DuelController.BALANCE.loot_conversion_gold.get("common", 0))
	var settled: Dictionary = duel._reward_system.settle_loot_offer(idx)
	_check(idx >= 0 and bool(settled.get("ok", false)) and duel.gold == gold0 + want,
		"满腰带结算金币 +%d" % want)
	duel.consumable_slots.clear()


# ---------------------------------------------------------------------------
# ⑧ 结算失败不消耗结算机会
# ---------------------------------------------------------------------------

func _test_failed_settle_not_consumed(duel: DuelController) -> void:
	seed(46008)
	duel._reset_run_state()
	duel.selected_loadout.clear()
	# 填满武器槽，但不包含目标候选 → payload 仍是 item + needs_replace
	duel.selected_loadout.assign([FIRE_SWORD, ICE_GUN])
	var res: Dictionary = duel._reward_system.build_loot_offer("normal", 1,
		{"categories": ["weapon"], "exclude": [FIRE_SWORD, ICE_GUN]}, "common")
	var idx := -1
	for i in range(res["options"].size()):
		var o: Dictionary = res["options"][i]
		if String(o.get("kind", "")) == "item" and String(o.get("grant", "")) == "item":
			idx = i
			break
	_check(idx >= 0 and bool(res["options"][idx].get("needs_replace", false)),
		"满槽候选冻结 needs_replace")
	if idx < 0:
		return
	var fail: Dictionary = duel._reward_system.settle_loot_offer(idx)
	_check(not bool(fail.get("ok", true)) and String(fail.get("reason", "")) == "needs_replace",
		"满槽直接结算返回 needs_replace")
	duel.selected_loadout.pop_back()
	var ok: Dictionary = duel._reward_system.settle_loot_offer(idx)
	_check(bool(ok.get("ok", false)), "失败后腾出槽位仍可结算（未消耗结算机会）")
	duel.selected_loadout.clear()


# ---------------------------------------------------------------------------
# ⑨ 最高熟练写入图鉴
# ---------------------------------------------------------------------------

func _test_codex_best_mastery(duel: DuelController) -> void:
	seed(46009)
	duel._reset_run_state()
	duel.selected_loadout.clear()
	duel.selected_loadout.assign([FLAME_STAFF])
	duel.mastery.grant_points(FLAME_STAFF, 5)
	duel._codex.record_run(duel.mastery)
	_check(duel._codex.best_rank_of(FLAME_STAFF) >= 2,
		"图鉴记录最高 R 等级（R%d）" % duel._codex.best_rank_of(FLAME_STAFF))
	_check(duel._codex.best_mastery_of(FLAME_STAFF) >= 5,
		"图鉴记录最高熟练点数（%d）" % duel._codex.best_mastery_of(FLAME_STAFF))


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("PASS  ", label)
	else:
		_fails += 1
		printerr("FAIL  ", label)


func _fail(label: String) -> void:
	_checks += 1
	_fails += 1
	printerr("FAIL  ", label)
