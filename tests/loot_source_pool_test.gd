extends Node

# ============================================================================
# 四级品质战利品 · Step 3 · 来源品质表与统一候选池 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/loot_source_pool_test.tscn
#
# 覆盖（docs/四级品质战利品与大奖池_分步执行计划_2026-11-12.md Step 3）：
# ① 来源表：每行权重合计 100；normal/elite/boss/chest 走随机品质，shop/anvil/event 明确不随机；
#    非法来源/幕次返回明确原因；10k 抽样分布 = 权重表（±2pp）；
# ② 候选池合法性：source_tags / act_min~act_max / 类别 / 主题 / 排除 / 信物开关；
# ③ 同层抽取：roll 结果品质与物品 rarity 一致；roll_n 同层无放回；短层/空层返回明确原因；
# ④ 专用 RNG：固定种子可复现，且不消耗全局/地图 RNG；
# ⑤ 商店确定性阶梯：品质多重集 == loot_shop_ladder，跨格无重复。
# 本套件不启动战斗场景；LootPool 用 null controller（demo 白名单默认放行）。
# ============================================================================

const TRIALS := 10000
const SEED := 20261113

var _checks := 0
var _fails := 0


func _ready() -> void:
	_test_source_table()
	_test_distribution()
	_test_candidates_legality()
	_test_same_tier_rolls()
	_test_rng_isolation()
	_test_shop_ladder()
	print("---")
	print("LOOTPOOL|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


# ---------------------------------------------------------------------------
# ① 来源表
# ---------------------------------------------------------------------------

func _test_source_table() -> void:
	for source in LootSourceTable.BATTLES:
		for act in [1, 2, 3]:
			var res: Dictionary = LootSourceTable.weights_for(source, act)
			_check(bool(res["ok"]), "%s act%d 来源行可读" % [source, act])
			var total := 0
			for q in LootSourceTable.QUALITIES:
				total += int((res["weights"] as Dictionary).get(q, 0))
			_check(total == 100, "%s act%d 权重合计 100（实测 %d）" % [source, act, total])
	_check(LootSourceTable.uses_random_quality("normal"), "normal 走随机品质")
	_check(LootSourceTable.uses_random_quality("chest"), "chest 走随机品质")
	_check(not LootSourceTable.uses_random_quality("shop"), "shop 不走随机品质（确定性阶梯）")
	_check(not LootSourceTable.uses_random_quality("anvil"), "anvil 不走来源表")
	var bad_source: Dictionary = LootSourceTable.weights_for("mystery", 1)
	_check(not bool(bad_source["ok"]) and String(bad_source["reason"]) == "invalid_source",
		"非法来源原因明确（%s）" % bad_source["reason"])
	var bad_act: Dictionary = LootSourceTable.weights_for("normal", 4)
	_check(not bool(bad_act["ok"]) and String(bad_act["reason"]) == "invalid_act",
		"非法幕次原因明确（%s）" % bad_act["reason"])
	var event_res: Dictionary = LootSourceTable.weights_for("event", 1)
	_check(not bool(event_res["ok"]) and String(event_res["reason"]) == "not_random:event",
		"特殊事件未配置返回 not_random（%s）" % event_res["reason"])
	_check(LootSourceTable.shop_tiers(1).size() == 6 and LootSourceTable.shop_tiers(3).size() == 6,
		"商店阶梯 act1/act3 各 6 格")
	_check(LootSourceTable.shop_tiers(4).is_empty(), "商店阶梯非法幕次返回空")


# 纯来源表抽样（不经候选池），验证权重换算正确。
func _test_distribution() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for source in LootSourceTable.BATTLES:
		var weights: Dictionary = LootSourceTable.weights_for(source, 1)["weights"]
		var tally := {"common": 0, "uncommon": 0, "rare": 0, "epic": 0}
		for i in TRIALS:
			var q: String = LootSourceTable.roll_quality(source, 1, rng)
			tally[q] = int(tally.get(q, 0)) + 1
		for q in LootSourceTable.QUALITIES:
			var exp: float = float(weights.get(q, 0)) / 100.0
			var obs: float = float(tally[q]) / float(TRIALS)
			_check(absf(obs - exp) <= 0.02,
				"%s %s 分布 %.3f ≈ 表 %.3f" % [source, q, obs, exp])


# ---------------------------------------------------------------------------
# ② 候选池合法性
# ---------------------------------------------------------------------------

func _test_candidates_legality() -> void:
	var pool := LootPool.new()
	pool.reset_run(SEED)

	var weapons: Dictionary = pool.candidates("normal", 1, {"category": "weapon"})
	_check(bool(weapons["ok"]) and not (weapons["items"] as Array).is_empty(),
		"normal act1 武器候选非空")
	var all_tagged := true
	var all_act_legal := true
	var all_weapon := true
	for p in weapons["items"]:
		var res: Resource = load(String(p))
		if res == null:
			all_weapon = false
			continue
		var tags: Variant = res.get("source_tags")
		if not (tags is Array and "normal" in tags):
			all_tagged = false
		if int(res.get("act_min")) > 1 or int(res.get("act_max")) < 1:
			all_act_legal = false
		if not (res is WeaponData):
			all_weapon = false
	_check(all_tagged, "候选全部带 normal 来源标签")
	_check(all_act_legal, "候选全部在 act1 合法区间")
	_check(all_weapon, "category=weapon 只返回武器")

	var theme := ["res://resources/weapon_templates/fire_sword.tres",
		"res://resources/weapon_templates/ice_gun.tres"]
	var themed: Dictionary = pool.candidates("normal", 1, {"category": "weapon", "theme": theme})
	var theme_ok := (themed["items"] as Array).size() == theme.size()
	for p in themed["items"]:
		if not theme.has(String(p)):
			theme_ok = false
	_check(theme_ok, "主题白名单只返回池内物品（%d）" % (themed["items"] as Array).size())

	var excluded: Dictionary = pool.candidates("normal", 1, {
		"category": "weapon", "theme": theme, "exclude": [theme[0]]})
	_check((excluded["items"] as Array).size() == 1
		and String((excluded["items"] as Array)[0]) == String(theme[1]),
		"exclude 精确排除指定路径")

	var empty_theme: Dictionary = pool.candidates("boss", 1, {"category": "weapon", "theme": []})
	_check(not bool(empty_theme["ok"]) and String(empty_theme["reason"]) == "empty_theme",
		"空主题池返回 empty_theme（%s）" % empty_theme["reason"])

	var mixed: Dictionary = pool.candidates("normal", 1, {"category": ["weapon", "skill"]})
	var only_two := true
	for p in mixed["items"]:
		var kind := _kind_of(String(p))
		if kind != "weapon" and kind != "skill":
			only_two = false
	_check(only_two, "类别数组只返回指定类别")

	var no_relic: Dictionary = pool.candidates("boss", 1, {"category": "passive"})
	var relic_leak := 0
	for p in no_relic["items"]:
		if String(p).get_file().contains("_relic"):
			relic_leak += 1
	_check(relic_leak == 0, "默认不返回 BOSS 信物（泄漏 %d）" % relic_leak)

	var with_relic: Dictionary = pool.candidates("boss", 1, {
		"category": "passive", "include_relics": true})
	var relics := 0
	for p in with_relic["items"]:
		if String(p).get_file().contains("_relic"):
			relics += 1
	_check(relics > 0, "include_relics=true 时信物进入候选（%d）" % relics)

	var chest: Dictionary = pool.candidates("chest", 1, {})
	_check(String(chest["reason"]) == "no_candidates",
		"chest 暂无标签物品 → no_candidates（Step 5 补内容）")


func _kind_of(path: String) -> String:
	var res: Resource = load(path)
	if res is WeaponData:
		return "weapon"
	if res is SkillData:
		return "skill"
	if res is ItemData:
		return String(res.category)
	return ""


# ---------------------------------------------------------------------------
# ③ 同层抽取
# ---------------------------------------------------------------------------

func _test_same_tier_rolls() -> void:
	var pool := LootPool.new()
	pool.reset_run(SEED)

	var tier_mismatch := 0
	var relic_leak := 0
	for i in 2000:
		var res: Dictionary = pool.roll("elite", 2, {"category": "passive"})
		if not bool(res.get("ok", false)):
			tier_mismatch += 1
			continue
		var item: Resource = load(String(res["path"]))
		if String(item.get("rarity")) != String(res["quality"]):
			tier_mismatch += 1
		if String(res["path"]).get_file().contains("_relic"):
			relic_leak += 1
	_check(tier_mismatch == 0, "roll 结果品质与物品 rarity 一致（偏差 %d）" % tier_mismatch)
	_check(relic_leak == 0, "roll 默认不含信物（泄漏 %d）" % relic_leak)

	var dup := 0
	var mismatch := 0
	for i in 500:
		var res: Dictionary = pool.roll_n("normal", 1, 3, {"category": "weapon"})
		if not bool(res.get("ok", false)):
			continue
		var paths: Array = res["paths"]
		var seen := {}
		for p in paths:
			if seen.has(String(p)):
				dup += 1
			seen[String(p)] = true
			var item: Resource = load(String(p))
			if String(item.get("rarity")) != String(res["quality"]):
				mismatch += 1
	_check(dup == 0, "roll_n 同层无放回（重复 %d）" % dup)
	_check(mismatch == 0, "roll_n 所有候选同品质（偏差 %d）" % mismatch)

	# boss 主题池里 epic 只有 1 件 → 短层必须显式报告，而不是跨品质补位
	var one_epic := ["res://resources/weapon_templates/flame_staff.tres"]
	var short: Dictionary = pool.roll_n("boss", 1, 3, {
		"category": "weapon", "theme": one_epic}, "epic")
	_check(bool(short["ok"]) and int(short["count"]) == 1
		and String(short["reason"]) == "short_tier",
		"同层不足 n 返回 short_tier（count=%d）" % short["count"])

	var empty: Dictionary = pool.roll("elite", 1, {"category": "passive"}, "epic")
	_check(not bool(empty["ok"]) and String(empty["reason"]) == "empty_tier",
		"act1 精英护符无 epic → empty_tier（%s）" % empty["reason"])

	var forced: Dictionary = pool.roll("normal", 1, {"category": "weapon"}, "rare")
	_check(bool(forced["ok"]) and String(forced["quality"]) == "rare",
		"forced_quality 精确进入该层")

	var not_random: Dictionary = pool.roll("shop", 1, {"category": "weapon"})
	_check(not bool(not_random["ok"]) and String(not_random["reason"]) == "source_not_random:shop",
		"shop 不随机品质（%s）" % not_random["reason"])


# ---------------------------------------------------------------------------
# ④ RNG 隔离与可复现
# ---------------------------------------------------------------------------

func _test_rng_isolation() -> void:
	var pool := LootPool.new()   # 构造时会取一次全局种子，先于下面的播种
	seed(7777)
	var before := randi()
	seed(7777)
	pool.reset_run(SEED)
	for i in 300:
		pool.roll("normal", 1, {"category": "weapon"})
	var after := randi()
	_check(before == after, "LootPool 抽取不消耗全局 RNG")

	var a := LootPool.new()
	a.reset_run(31337)
	var b := LootPool.new()
	b.reset_run(31337)
	var seq_a: Array = []
	var seq_b: Array = []
	for i in 50:
		seq_a.append(String(a.roll("elite", 2, {"category": "passive"})["path"]))
		seq_b.append(String(b.roll("elite", 2, {"category": "passive"})["path"]))
	_check(seq_a == seq_b, "同种子两条专用流序列一致")

	var c := LootPool.new()
	c.reset_run(99991)
	var seq_c: Array = []
	for i in 50:
		seq_c.append(String(c.roll("elite", 2, {"category": "passive"})["path"]))
	_check(seq_a != seq_c, "不同种子序列不同")


# ---------------------------------------------------------------------------
# ⑤ 商店确定性阶梯
# ---------------------------------------------------------------------------

func _test_shop_ladder() -> void:
	var pool := LootPool.new()
	pool.reset_run(SEED)
	for act in [1, 2, 3]:
		var tiers: Array = LootSourceTable.shop_tiers(act)
		var out: Array = pool.roll_ladder(act, tiers)
		_check(out.size() == 6, "act%d 阶梯返回 6 格（%d）" % [act, out.size()])
		var want := {}
		for q in tiers:
			want[String(q)] = int(want.get(String(q), 0)) + 1
		var got := {}
		var paths := {}
		var dup := 0
		var all_ok := true
		for slot in out:
			if not bool(slot.get("ok", false)):
				all_ok = false
				continue
			var p := String(slot["path"])
			if paths.has(p):
				dup += 1
			paths[p] = true
			var item: Resource = load(p)
			var q := String(item.get("rarity"))
			got[q] = int(got.get(q, 0)) + 1
		_check(all_ok, "act%d 阶梯每格都有货" % act)
		_check(dup == 0, "act%d 阶梯跨格无重复" % act)
		var same := true
		for q in LootSourceTable.QUALITIES:
			if int(want.get(q, 0)) != int(got.get(q, 0)):
				same = false
		_check(same, "act%d 阶梯品质多重集一致" % act)


# ---------------------------------------------------------------------------

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("PASS  ", label)
	else:
		_fails += 1
		printerr("FAIL  ", label)
