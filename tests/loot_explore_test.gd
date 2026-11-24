extends Node

# ============================================================================
# 四级品质战利品 · Step 5 · 普通 / 精英 / BOSS / 探索来源接入 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/loot_explore_test.tscn
#
# 覆盖（docs/四级品质战利品与大奖池_分步执行计划_2026-11-12.md Step 5）：
# ① 探索资源标签：武器 / 非信物护符 / 消耗品带 chest，BOSS 信物与技能不带；
# ② 探索抽取合法性：类别、幕次、品质、来源标签均合法，永不返回信物；
# ③ 探索品质只读 chest 来源表（武器 act1 分布 ≈ 35/40/22/3，不是普通战表）；
# ④ 同种子可复现：专用 RNG 序列与线性房间构建结果一致；
# ⑤ 线性探索内容冻结：宝箱房型与物品路径在重建前不变；
# ⑥ 探索抽取不消耗全局 RNG；空类别明确返回 ""；
# ⑦ 商店类别序列按幕次确定，且与品质阶梯逐格对齐。
# ============================================================================

const WEAPON_DIR := "res://resources/weapon_templates"
const CHARM_DIR := "res://resources/charms"
const CONSUMABLE_DIR := "res://resources/consumables"
const SKILL_DIR := "res://resources/skills"
const PICKS := 300
const DIST_TRIALS := 10000
const ROOM_SEEDS := 60

var _checks := 0
var _fails := 0


func _ready() -> void:
	await _run()
	print("---")
	print("LOOTEXPLORE|RESULT %s (checks=%d fails=%d)"
		% ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	await get_tree().process_frame
	var duel: DuelController = await _boot()
	if duel == null:
		print("LOOTEXPLORE|RESULT FAIL (boot)")
		get_tree().quit(2)
		return
	_test_tag_coverage()
	_test_pick_legality(duel)
	_test_chest_distribution(duel)
	_test_same_seed_repro(duel)
	_test_frozen_linear_content(duel)
	_test_rng_isolation(duel)
	_test_empty_category(duel)
	_test_shop_category_config()


func _boot() -> DuelController:
	var duel: DuelController = load("res://scenes/duel/duel.tscn").instantiate()
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	return duel


func _tags(path: String) -> Array:
	var res: Resource = load(path)
	if res == null:
		return []
	var raw: Variant = res.get("source_tags")
	return raw if raw is Array else []


func _rarity_of(path: String) -> String:
	var res: Resource = load(path)
	return String(res.get("rarity")) if res != null and res.get("rarity") != null else ""


# ---------------------------------------------------------------------------
# ① 探索资源标签
# ---------------------------------------------------------------------------

func _files(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".tres"):
			out.append(dir_path + "/" + f)
	out.sort()
	return out


func _test_tag_coverage() -> void:
	var weapons := _files(WEAPON_DIR)
	var charms := _files(CHARM_DIR)
	var consumables := _files(CONSUMABLE_DIR)
	var skills := _files(SKILL_DIR)

	var weapon_missing := 0
	for p in weapons:
		if not ("chest" in _tags(String(p))):
			weapon_missing += 1
	_check(weapons.size() > 0 and weapon_missing == 0,
		"全部武器带 chest 标签（%d 件，缺 %d）" % [weapons.size(), weapon_missing])

	var charm_ok := 0
	var charm_bad := 0
	var relic_leak := 0
	for p in charms:
		var s := String(p)
		var is_relic := s.get_file().contains("_relic")
		var has := "chest" in _tags(s)
		if is_relic:
			if has:
				relic_leak += 1
		elif has:
			charm_ok += 1
		else:
			charm_bad += 1
	_check(charm_bad == 0 and charm_ok > 0,
		"非信物护符带 chest 标签（%d 件，缺 %d）" % [charm_ok, charm_bad])
	_check(relic_leak == 0, "BOSS 信物不带 chest 标签（泄漏 %d）" % relic_leak)

	# 2026-11-20 更新：精简剪刀（trim_scissors）是 G7-B 特殊机制道具，
	# 设计上只走商店来源（见 shop_system TRIM_ITEM_PATH），不进宝箱池，故不算遗漏。
	const NO_CHEST_CONSUMABLES := ["trim_scissors.tres"]
	var consumable_missing := 0
	var missing_names: Array[String] = []
	for p in consumables:
		if not ("chest" in _tags(String(p))):
			var fname: String = String(p).get_file()
			if not NO_CHEST_CONSUMABLES.has(fname):
				consumable_missing += 1
				missing_names.append(fname)
	_check(consumables.size() > 0 and consumable_missing == 0,
		"消耗品带 chest 标签（%d 件，缺 %d：%s）" % [consumables.size(), consumable_missing, ", ".join(missing_names)])

	var skill_chest := 0
	for p in skills:
		if "chest" in _tags(String(p)):
			skill_chest += 1
	_check(skill_chest == 0, "技能不进探索来源（误标 %d）" % skill_chest)


# ---------------------------------------------------------------------------
# ② 抽取合法性
# ---------------------------------------------------------------------------

func _test_pick_legality(duel: DuelController) -> void:
	seed(44001)
	duel._reset_run_state()
	var rng := RandomNumberGenerator.new()
	rng.seed = 44001
	var bad := 0
	var empty := 0
	var total := 0
	for cat in ["weapon", "passive", "active"]:
		for act in [1, 2, 3]:
			for i in PICKS:
				var p: String = duel._reward_system.pick_explore_loot(cat, act, rng)
				total += 1
				if p == "":
					empty += 1
					continue
				var res: Resource = load(p)
				if res == null:
					bad += 1
					continue
				if not ("chest" in _tags(p)):
					bad += 1
				elif not (String(res.get("rarity")) in LootSourceTable.QUALITIES):
					bad += 1
				elif act < int(res.get("act_min")) or act > int(res.get("act_max")):
					bad += 1
				elif String(res.get("category")) != cat:
					bad += 1
				elif p.get_file().contains("_relic"):
					bad += 1
	_check(bad == 0 and empty == 0,
		"探索抽取全部合法（%d 次，非法 %d / 空 %d）" % [total, bad, empty])


# ---------------------------------------------------------------------------
# ③ 探索品质只读 chest 来源表
# ---------------------------------------------------------------------------

func _test_chest_distribution(duel: DuelController) -> void:
	seed(44002)
	duel._reset_run_state()
	var rng := RandomNumberGenerator.new()
	rng.seed = 44002
	var tally := {"common": 0, "uncommon": 0, "rare": 0, "epic": 0}
	for i in DIST_TRIALS:
		var p: String = duel._reward_system.pick_explore_loot("weapon", 1, rng)
		var q := _rarity_of(p)
		tally[q] = int(tally.get(q, 0)) + 1
	var chest_row: Dictionary = LootSourceTable.weights_for("chest", 1)
	var weights: Dictionary = chest_row["weights"]
	for q in LootSourceTable.QUALITIES:
		var exp := float(weights.get(q, 0)) / 100.0
		var obs := float(tally.get(q, 0)) / float(DIST_TRIALS)
		_check(absf(obs - exp) <= 0.025,
			"探索武器 %s 占比 %.3f ≈ chest 表 %.3f" % [q, obs, exp])
	# 与普通战表区分：chest rare 22% 明显高于 normal rare 5%。
	var normal_row: Dictionary = LootSourceTable.weights_for("normal", 1)
	var normal_weights: Dictionary = normal_row["weights"]
	var normal_rare := float(normal_weights.get("rare", 0)) / 100.0
	var chest_rare := float(tally.get("rare", 0)) / float(DIST_TRIALS)
	_check(chest_rare > normal_rare + 0.10,
		"探索品质不读普通战表（rare %.3f vs normal %.3f）" % [chest_rare, normal_rare])


# ---------------------------------------------------------------------------
# ④ 同种子可复现（专用 RNG + 线性房间构建）
# ---------------------------------------------------------------------------

func _pick_sequence(duel: DuelController, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array = []
	for cat in ["weapon", "passive", "active"]:
		for i in 12:
			out.append(duel._reward_system.pick_explore_loot(cat, 2, rng))
	return out


func _linear_item_sig(duel: DuelController) -> String:
	var parts: Array[String] = []
	for room in duel.ROOMS:
		if String(room.kind) == "chest":
			parts.append("%s:%d:%s:%s" % [String(room.name), int(room.act),
				String(room.gimmick_params.get("category", "")), String(room.gimmick_params.get("item_path", ""))])
	return "|".join(parts)


func _test_same_seed_repro(duel: DuelController) -> void:
	seed(44003)
	duel._reset_run_state()
	var a := _pick_sequence(duel, 777)
	var b := _pick_sequence(duel, 777)
	_check(a == b and not a.is_empty(), "探索专用 RNG 同种子可复现（%d 次）" % a.size())

	duel.shop_run_seed = 44004
	duel.ROOMS = duel._build_run()
	var sig1 := _linear_item_sig(duel)
	duel.shop_run_seed = 44004
	duel.ROOMS = duel._build_run()
	var sig2 := _linear_item_sig(duel)
	_check(sig1 != "" and sig1 == sig2, "同种子线性探索物品完全可复现")
	duel.shop_run_seed = 44005
	duel.ROOMS = duel._build_run()
	_check(_linear_item_sig(duel) != sig1, "换种子探索内容随之变化")


# ---------------------------------------------------------------------------
# ⑤ 线性内容构建后冻结
# ---------------------------------------------------------------------------

func _test_frozen_linear_content(duel: DuelController) -> void:
	var bad_path := 0
	var relic_leak := 0
	var unstable := 0
	var seen_treasure := 0
	var gold_fallback := 0
	for i in ROOM_SEEDS:
		var s := 45000 + i
		duel.shop_run_seed = s
		duel.ROOMS = duel._build_run()
		var sig1 := _linear_item_sig(duel)
		var frozen: Array = duel.ROOMS.duplicate()
		for room in frozen:
			if String(room.kind) != "chest":
				continue
			seen_treasure += 1
			# run_setup.gd 会产出 category=gold / item_path="" 的兜底宝箱，旧用例同样跳过。
			var cat := String(room.gimmick_params.get("category", ""))
			if cat == "gold" or bool(room.gimmick_params.get("fallback", false)):
				gold_fallback += 1
				continue
			var path := String(room.gimmick_params.get("item_path", ""))
			if String(room.gimmick_params.get("special_kind", "")) != "chest" or path.is_empty() or not ("chest" in _tags(path)):
				bad_path += 1
			if path.get_file().contains("_relic"):
				relic_leak += 1
		duel.shop_run_seed = s
		duel.ROOMS = duel._build_run()
		if _linear_item_sig(duel) != sig1:
			unstable += 1
	_check(bad_path == 0, "线性探索物品全部来自 chest 来源（异常 %d）" % bad_path)
	_check(relic_leak == 0, "线性探索永不冻结 BOSS 信物（泄漏 %d）" % relic_leak)
	_check(unstable == 0, "同种子重建物品路径不变（不稳定 %d / %d）" % [unstable, ROOM_SEEDS])
	_check(seen_treasure > 0, "样本覆盖线性宝箱房（%d）" % seen_treasure)
	print("LOOTEXPLORE|info|金币兜底宝箱已跳过 %d 个（不计入物品路径断言）" % gold_fallback)


# ---------------------------------------------------------------------------
# ⑥ RNG 隔离 / 空类别
# ---------------------------------------------------------------------------

func _test_rng_isolation(duel: DuelController) -> void:
	seed(44005)
	var before := randi()
	seed(44005)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in 200:
		duel._reward_system.pick_explore_loot("weapon", 1, rng)
	var after := randi()
	_check(before == after, "探索抽取不消耗全局 RNG")


func _test_empty_category(duel: DuelController) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	_check(duel._reward_system.pick_explore_loot("skill", 1, rng) == "",
		"技能类别在探索来源为空 → 明确返回空")


# ---------------------------------------------------------------------------
# ⑦ 商店类别确定性
# ---------------------------------------------------------------------------

func _test_shop_category_config() -> void:
	var allowed := ["weapon", "passive", "active", "skill"]
	for act in [1, 2, 3]:
		var cats: Array = LootSourceTable.shop_categories(act)
		var tiers: Array = LootSourceTable.shop_tiers(act)
		# T1.5 返工：货架 4 格，且每幕配置仅 1 个武器格（其余武器机会由 ShopSystem 配额控制）
		var weapon_cnt: int = 0
		for c in cats:
			if String(c) == "weapon":
				weapon_cnt += 1
		var ok := cats.size() == 4 and cats.size() == tiers.size() and weapon_cnt == 1
		if ok:
			for c in cats:
				if not (String(c) in allowed):
					ok = false
		_check(ok, "act%d 商店类别序列 4 格、1 武器格且与品质阶梯对齐" % act)
	_check(LootSourceTable.shop_categories(4).is_empty(), "非法幕次商店类别为空")


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("PASS  ", label)
	else:
		_fails += 1
		printerr("FAIL  ", label)
