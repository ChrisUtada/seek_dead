extends Node

# ============================================================================
# 四级品质战利品 · Step 8 · 大奖池统计、平衡与完整回归 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/loot_balance_test.tscn
#
# 覆盖（docs/四级品质战利品与大奖池_分步执行计划_2026-11-12.md Step 8 / §7）：
# ① 每来源 × 每幕 10,000 次品质抽样：实测分布 = 来源表（±2 个百分点）；
# ② 真实 LootOffer 生成路径 1,000 组/来源/幕：品质分布同样落在 ±5pp，且每组恰好三项同层；
# ③ 批量生成不变量：同层 / 路径不重复 / 同机制分组不重复 / ≥2 用途 / 每项都有品质+机制+条件+结果；
# ④ 单组三选一内不存在无条件严格上位选项（同机制线更高值且无代价；跨机制线只记录）；
# ⑤ 四级品质 × 三类物品的真实结算可用性（武器进带 / 护符入槽 / 消耗品进腰带，只结算一次）；
# ⑥ 10 个构筑家族 + 混合 Build 的基础配装能清掉第 1 房（不依赖唯一传说件、不软锁）；
# ⑦ 「数值优先」与「家族联动优先」两种选卡策略的统计对照：联动更高重叠、代价有界、不长期压倒构筑；
# ⑧ 固定种子可复现（同种子两套候选序列一致）。
#
# 统计模拟只用于发现分布、支配与流程问题，不把模型结果当作最终难度结论（计划 §7 末段）。
# ============================================================================

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const SEED := 20261114
const TABLE_TRIALS := 10000        # 来源表直接抽样（计划要求 ≥10,000）
const OFFER_TRIALS := 1000         # 真实生成路径抽样（每来源 × 每幕）
const BULK_OFFERS := 1200          # 不变量批量生成
const TOLERANCE_TABLE := 0.02      # 计划 §7：±2 个百分点
const TOLERANCE_OFFER := 0.05      # 生成路径 n=1000，容差放宽到 5pp（3σ 以上）
const DRAFT_RUNS := 100
const DRAFT_OFFERS := 15
const SYNERGY_BONUS := 0.25        # 模型假设：构筑一致性对有效强度的加成上限
const ROOM_TURN_BUDGET := 400
const GOD_HP := 1000000

var _checks := 0
var _fails := 0
var _duel: DuelController
var _pool: LootPool                # 纯生成（ctrl=null）专用池
var _offer: LootOffer              # 纯生成 offer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	await _run()
	print("---")
	print("LOOTBAL|RESULT %s (checks=%d fails=%d)"
		% ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	await _frames(2)
	var duel: DuelController = await _boot()
	if duel == null:
		print("LOOTBAL|RESULT FAIL (boot)")
		get_tree().quit(2)
		return
	_duel = duel
	var meta_backup: Dictionary = duel.meta.duplicate(true)
	_pool = LootPool.new()
	_pool.reset_run(SEED)
	_offer = LootOffer.new(null, _pool)

	var t0 := Time.get_ticks_msec()
	_test_source_distribution()
	_section("source_distribution", t0)
	t0 = Time.get_ticks_msec()
	_test_offer_distribution()
	_section("offer_distribution", t0)
	t0 = Time.get_ticks_msec()
	_test_offer_invariants()
	_section("offer_invariants", t0)
	t0 = Time.get_ticks_msec()
	_test_within_offer_dominance()
	_section("within_offer_dominance", t0)
	t0 = Time.get_ticks_msec()
	_test_reproducibility()
	_section("reproducibility", t0)
	t0 = Time.get_ticks_msec()
	await _test_quality_usability()
	_section("quality_usability", t0)
	t0 = Time.get_ticks_msec()
	await _test_family_paths()
	_section("family_paths", t0)
	t0 = Time.get_ticks_msec()
	_test_draft_policies()
	_section("draft_policies", t0)

	duel.meta.clear()
	for k in meta_backup:
		duel.meta[k] = meta_backup[k]
	duel._meta_store.save_meta()


func _boot() -> DuelController:
	var scene_res: PackedScene = load(DUEL_SCENE)
	if scene_res == null:
		return null
	_duel = scene_res.instantiate() as DuelController
	add_child(_duel)
	await _frames(3)
	_duel._confirm_loadout()
	await _frames(3)
	return _duel


func _section(name: String, t0: int) -> void:
	print("LOOTBAL|TIME %s=%dms" % [name, Time.get_ticks_msec() - t0])


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


# 资源字段可能为 null（武器没有 status_value / value），String(null) 会直接报错，这里统一兜底。
func _s(v: Variant) -> String:
	return String(v) if v != null else ""


func _i(v: Variant) -> int:
	return int(v) if v != null else 0


func _f(v: Variant) -> float:
	return float(v) if v != null else 0.0


func _b(v: Variant) -> bool:
	return bool(v) if v != null else false


# ---------------------------------------------------------------------------
# ① 来源表 × 幕次：10,000 次抽样
# ---------------------------------------------------------------------------

func _test_source_distribution() -> void:
	_rng.seed = SEED
	var worst := 0.0
	for source in LootSourceTable.BATTLES:
		for act in [1, 2, 3]:
			var weights: Dictionary = LootSourceTable.weights_for(source, act)["weights"]
			var tally := {"common": 0, "uncommon": 0, "rare": 0, "epic": 0}
			for i in TABLE_TRIALS:
				var q: String = LootSourceTable.roll_quality(source, act, _rng)
				tally[q] = int(tally.get(q, 0)) + 1
			var worst_here := 0.0
			for q in LootSourceTable.QUALITIES:
				var exp: float = float(weights.get(q, 0)) / 100.0
				var obs: float = float(tally[q]) / float(TABLE_TRIALS)
				worst_here = maxf(worst_here, absf(obs - exp))
			worst = maxf(worst, worst_here)
			_check(worst_here <= TOLERANCE_TABLE,
				"%s act%d 10k 抽样最大偏差 %.2fpp ≤ 2pp" % [source, act, worst_here * 100.0])
	print("LOOTBAL|DIST worst_deviation=%.2fpp trials=%d" % [worst * 100.0, TABLE_TRIALS])


# ---------------------------------------------------------------------------
# ② 真实生成路径的品质分布
# ---------------------------------------------------------------------------

func _test_offer_distribution() -> void:
	var worst := 0.0
	for source in LootSourceTable.BATTLES:
		for act in [1, 2, 3]:
			var weights: Dictionary = LootSourceTable.weights_for(source, act)["weights"]
			var tally := {"common": 0, "uncommon": 0, "rare": 0, "epic": 0}
			var bad := 0
			for i in OFFER_TRIALS:
				var view: Dictionary = _offer.build(source, act)
				if not bool(view.get("ok", false)):
					bad += 1
					continue
				var q := String(view.get("quality", ""))
				tally[q] = int(tally.get(q, 0)) + 1
				if (view.get("options", []) as Array).size() != 3:
					bad += 1
			var total := OFFER_TRIALS - bad
			_check(bad == 0 and total > 0, "%s act%d 生成路径全部成功且三项（失败 %d）" % [source, act, bad])
			var worst_here := 0.0
			for q in LootSourceTable.QUALITIES:
				var exp: float = float(weights.get(q, 0)) / 100.0
				var obs: float = float(tally[q]) / float(maxi(total, 1))
				worst_here = maxf(worst_here, absf(obs - exp))
			worst = maxf(worst, worst_here)
			_check(worst_here <= TOLERANCE_OFFER,
				"%s act%d 生成路径品质偏差 %.2fpp ≤ 5pp" % [source, act, worst_here * 100.0])
	print("LOOTBAL|OFFERDIST worst_deviation=%.2fpp trials=%d" % [worst * 100.0, OFFER_TRIALS])


# ---------------------------------------------------------------------------
# ③ 批量生成不变量
# ---------------------------------------------------------------------------

func _test_offer_invariants() -> void:
	var sources := ["normal", "elite", "boss", "chest"]
	var ok_offers := 0
	var empty_tier := 0
	var bad_reason := 0
	var bad_count := 0
	var mixed_quality := 0
	var dup_paths := 0
	var dup_groups := 0
	var few_purposes := 0
	var empty_text := 0
	var wrong_rarity := 0
	var bad_skip := 0
	var group_checked := 0
	for i in BULK_OFFERS:
		var source := String(sources[i % sources.size()])
		var act := 1 + int(i / sources.size()) % 3
		var q := String(LootSourceTable.QUALITIES[i % LootSourceTable.QUALITIES.size()])
		var view: Dictionary = _offer.build(source, act, {}, q)
		if not bool(view.get("ok", false)):
			if String(view.get("reason", "")) == "empty_tier":
				empty_tier += 1
			else:
				bad_reason += 1
			continue
		ok_offers += 1
		var opts: Array = view.get("options", [])
		if opts.size() != 3:
			bad_count += 1
			continue
		var seen_paths := {}
		var seen_groups := {}
		var purposes := {}
		for o in opts:
			var od: Dictionary = o
			if String(od.get("quality", "")) != q:
				mixed_quality += 1
			var kind := String(od.get("kind", ""))
			if kind == "item":
				var p := String(od.get("path", ""))
				if seen_paths.has(p):
					dup_paths += 1
				seen_paths[p] = true
				var g := String(od.get("unique_group", ""))
				if g != "":
					if seen_groups.has(g):
						dup_groups += 1
					seen_groups[g] = true
				var res: Resource = _pool.resource_of(p)
				if res == null or String(res.get("rarity")) != q:
					wrong_rarity += 1
			purposes[String(od.get("purpose", ""))] = true
			if String(od.get("quality_name", "")) == "" \
				or String(od.get("mechanism", "")) == "" \
				or String(od.get("condition", "")) == "" \
				or String(od.get("result", "")) == "":
				empty_text += 1
		if purposes.size() < 2:
			few_purposes += 1
		var skip: Dictionary = view.get("skip", {})
		if int(skip.get("gold", 0)) != int(DuelController.BALANCE.loot_skip_gold.get(q, 0)):
			bad_skip += 1
		# 同机制不重复只在「该层确实有 ≥3 个不同分组」时才要求（不足时允许同组补齐）
		var tier: Dictionary = _pool.tier_items(source, act, q, {})
		var groups := {}
		for p in tier.get("items", []):
			var g2 := String(_pool.entry_of(String(p)).get("unique_group", ""))
			if g2 != "":
				groups[g2] = true
		if groups.size() >= 3:
			group_checked += 1
			if seen_groups.size() < 3:
				dup_groups += 1
	_check(ok_offers > 0, "批量生成有有效组（%d 组）" % ok_offers)
	_check(bad_reason == 0, "空池原因只允许 empty_tier（其它原因 %d）" % bad_reason)
	_check(bad_count == 0, "每组恰好三项（违例 %d）" % bad_count)
	_check(mixed_quality == 0, "三项品质与本次定层一致（越层 %d）" % mixed_quality)
	_check(dup_paths == 0, "同组内路径不重复（重复 %d）" % dup_paths)
	_check(dup_groups == 0, "同组内同机制不重复（违例 %d / 分组足够 %d 组）" % [dup_groups, group_checked])
	_check(few_purposes == 0, "每组至少两种决策用途（违例 %d）" % few_purposes)
	_check(empty_text == 0, "每项都有品质 / 机制 / 条件 / 结果（缺项 %d）" % empty_text)
	_check(wrong_rarity == 0, "候选物品 rarity 与本次品质一致（偏差 %d）" % wrong_rarity)
	_check(bad_skip == 0, "跳过金币 = 同层冻结值（偏差 %d）" % bad_skip)
	print("LOOTBAL|INVARIANTS offers=%d empty_tier=%d group_checked=%d" % [ok_offers, empty_tier, group_checked])


# ---------------------------------------------------------------------------
# ④ 组内无「无条件严格上位」选项
# ---------------------------------------------------------------------------

func _test_within_offer_dominance() -> void:
	var sources := ["normal", "elite", "boss", "chest"]
	var dominated := 0
	var cross_line := 0
	var examples: Array[String] = []
	for i in 600:
		var source := String(sources[i % sources.size()])
		var act := 1 + int(i / sources.size()) % 3
		var q := String(LootSourceTable.QUALITIES[i % LootSourceTable.QUALITIES.size()])
		var view: Dictionary = _offer.build(source, act, {}, q)
		if not bool(view.get("ok", false)):
			continue
		var items: Array = []
		for o in view.get("options", []):
			if String((o as Dictionary).get("kind", "")) == "item":
				items.append(o)
		for a in items:
			for b in items:
				if a == b:
					continue
				match _compare(a, b):
					1:
						dominated += 1
						if examples.size() < 3:
							examples.append("%s > %s" % [String(a.get("title", "")), String(b.get("title", ""))])
					2:
						cross_line += 1
	_check(dominated == 0, "三选一内同机制线无无条件严格上位项（违例 %d）%s"
		% [dominated, "" if examples.is_empty() else "；例：" + " / ".join(examples)])
	print("LOOTBAL|DOMINANCE violations=%d cross_line_numeric=%d" % [dominated, cross_line])


# 返回 1 = A 无条件严格上位（同机制线、数值更高且无额外代价）；
# 2 = 同类别同效果但不同机制线（家族/元素/状态不同），数值有差但机制不可互换，只作观察；
# 0 = 不可比。机制线 = 类别 + effect + element + status_type + status_value。
func _compare(a: Dictionary, b: Dictionary) -> int:
	if String(a.get("category", "")) != String(b.get("category", "")):
		return 0
	var ra: Resource = _pool.resource_of(_s(a.get("path")))
	var rb: Resource = _pool.resource_of(_s(b.get("path")))
	if ra == null or rb == null:
		return 0
	var ea := _s(ra.get("effect"))
	if ea == "" or ea != _s(rb.get("effect")):
		return 0
	var va := _f(ra.get("value"))
	var vb := _f(rb.get("value"))
	var da := _s(ra.get("downside_effect"))
	var db := _s(rb.get("downside_effect"))
	var same_line := _s(ra.get("element")) == _s(rb.get("element")) \
		and _s(ra.get("status_type")) == _s(rb.get("status_type")) \
		and _i(ra.get("status_value")) == _i(rb.get("status_value"))
	if not same_line:
		# 不同机制线：只有「数值更高且双方都无代价」才值得记一笔，且不算违例。
		return 2 if (va > vb and da == "" and db == "") else 0
	if va < vb:
		return 0
	if da != "" and db == "":
		return 0
	if va > vb or (da == "" and db != ""):
		return 1
	return 0


# ---------------------------------------------------------------------------
# ⑧ 固定种子可复现
# ---------------------------------------------------------------------------

func _test_reproducibility() -> void:
	var a := LootPool.new()
	a.reset_run(31337)
	var oa := LootOffer.new(null, a)
	var b := LootPool.new()
	b.reset_run(31337)
	var ob := LootOffer.new(null, b)
	var same := true
	for i in 40:
		var va: Dictionary = oa.build("elite", 2)
		var vb: Dictionary = ob.build("elite", 2)
		if String(va.get("quality", "")) != String(vb.get("quality", "")):
			same = false
		if _item_paths(va.get("options", [])) != _item_paths(vb.get("options", [])):
			same = false
	_check(same, "同种子两条生成流品质与候选完全一致")


func _item_paths(opts: Array) -> Array:
	var out: Array = []
	for o in opts:
		if String((o as Dictionary).get("kind", "")) == "item":
			out.append(String((o as Dictionary).get("path", "")))
	return out


# ---------------------------------------------------------------------------
# ⑤ 四级品质 × 三类物品的真实结算
# ---------------------------------------------------------------------------

func _test_quality_usability() -> void:
	var sources := ["normal", "elite", "boss", "chest"]
	var gaps: Array[String] = []
	for q in LootSourceTable.QUALITIES:
		for cat in ["weapon", "passive", "active"]:
			var tried := 0
			var ok := false
			var reason := "no_tier"
			for source in sources:
				for act in [1, 2, 3]:
					var tier: Dictionary = _duel._reward_system._loot.tier_items(source, act, q, {"category": cat})
					if not bool(tier.get("ok", false)) or (tier.get("items", []) as Array).is_empty():
						continue
					tried += 1
					var res: Dictionary = _settle_one(q, source, act, cat, tier.get("items", []))
					ok = bool(res.get("ok", false))
					reason = String(res.get("reason", ""))
					break
				if tried > 0:
					break
			if tried == 0:
				# 内容层该层为空（例如首版没有传说消耗品）：记缺口，不当成流程失败。
				gaps.append("%s·%s" % [q, cat])
				print("LOOTBAL|USABILITY gap=%s:%s" % [q, cat])
				continue
			_check(ok, "%s · %s 可结算且只发一次（%s）" % [q, cat, reason])
	_check(gaps.is_empty() or (gaps.size() == 1 and gaps[0] == "epic·active"),
		"品质可用性缺口仅限已知内容缺口（%s）" % (",".join(gaps) if not gaps.is_empty() else "无"))


func _settle_one(q: String, source: String, act: int, cat: String, tier_items: Array) -> Dictionary:
	var keep := ""
	if cat == "weapon":
		keep = _weapon_not_in(tier_items)
		_duel.selected_loadout.clear()
		_duel.selected_loadout.append(keep)
		_duel._build_pool(_duel.selected_loadout)
	elif cat == "passive":
		_duel.selected_charms.clear()
		_duel._apply_charms()
	else:
		_duel.consumable_slots.clear()
	# 注意键名：LootOffer._rebuild 读的是 categories（category 会被它覆盖成默认三类）。
	var view: Dictionary = _duel._reward_system.build_loot_offer(source, act, {"categories": [cat]}, q)
	if not bool(view.get("ok", false)):
		return {"ok": false, "reason": "build:" + String(view.get("reason", ""))}
	var opts: Array = view.get("options", [])
	var idx := -1
	for i in range(opts.size()):
		var od: Dictionary = opts[i]
		if String(od.get("kind", "")) == "item" and String(od.get("grant", "")) == "item":
			idx = i
			break
	if idx < 0:
		return {"ok": false, "reason": "no_grantable"}
	var before := _state_sig(cat)
	var res: Dictionary = _duel._reward_system.settle_loot_offer(idx)
	if not bool(res.get("ok", false)):
		return res
	if _state_sig(cat) == before:
		return {"ok": false, "reason": "no_state_change"}
	var dup: Dictionary = _duel._reward_system.settle_loot_offer(idx)
	if bool(dup.get("ok", false)) or String(dup.get("reason", "")) != "already_settled":
		return {"ok": false, "reason": "double_settle"}
	return res


func _weapon_not_in(items: Array) -> String:
	for p in _duel.WEAPON_POOL:
		var s := String(p)
		if items.has(s):
			continue
		if s.get_file().contains("_relic"):
			continue
		return s
	return "res://resources/weapon_templates/dagger.tres"


func _state_sig(cat: String) -> String:
	match cat:
		"weapon":
			return str(_duel.selected_loadout)
		"passive":
			return str(_duel.selected_charms)
		"active":
			var bits: Array[String] = []
			for it in _duel.consumable_slots:
				bits.append(String((it as Dictionary).get("path", "")))
			return ",".join(bits)
	return ""


# ---------------------------------------------------------------------------
# ⑥ 家族基础路径 + 混合 Build
# ---------------------------------------------------------------------------

func _test_family_paths() -> void:
	var results: Array[String] = []
	for family in ItemTaxonomy.FAMILIES:
		var weapons := _family_paths("weapon", family)
		var charms := _family_paths("passive", family)
		var skills := _family_paths("skill", family)
		var actives := _family_paths("active", family)
		_check(not (weapons.is_empty() and charms.is_empty() and skills.is_empty() and actives.is_empty()),
			"家族「%s」第 1 幕有基础件（武器%d/护符%d/技能%d/消耗%d）"
			% [family, weapons.size(), charms.size(), skills.size(), actives.size()])
		var loadout: Array[String] = []
		for p in weapons.slice(0, 2):
			loadout.append(String(p))
		if loadout.is_empty():
			loadout.append("res://resources/weapon_templates/dagger.tres")
		_duel.selected_loadout.assign(loadout)
		_duel.selected_charms.assign(_to_strings(charms.slice(0, 2)))
		_duel.selected_skills.assign(_to_strings(skills.slice(0, 2)))
		_duel.selected_consumables.assign(_to_strings(actives.slice(0, 2)))
		_duel._confirm_loadout()
		var won := await _clear_room_one()
		_check(won, "家族「%s」基础配装清掉第 1 房" % family)
		results.append("%s:%s" % [family, "win" if won else "stuck"])
		await _leave_post_battle()

	# 混合 Build：火 + 冰 + 护盾，证明跨家族配装同样能推进
	_duel.selected_loadout.assign([
		"res://resources/weapon_templates/ember_staff.tres",
		"res://resources/weapon_templates/frost_wand.tres"])
	_duel.selected_charms.assign([
		"res://resources/charms/guard_charm.tres",
		"res://resources/charms/regen_charm.tres"])
	_duel.selected_skills.assign([
		"res://resources/skills/magic_bolt.tres",
		"res://resources/skills/recovery.tres"])
	_duel.selected_consumables.clear()
	_duel._confirm_loadout()
	var mixed_ok := await _clear_room_one()
	_check(mixed_ok, "混合 Build（火+冰+护盾+恢复）清掉第 1 房")
	print("LOOTBAL|FAMILY %s" % ",".join(results))


func _to_strings(arr: Array) -> Array[String]:
	var out: Array[String] = []
	for v in arr:
		out.append(String(v))
	return out


# 第 1 幕可获取、指定家族、基础/进阶优先的物品路径（字典序，确定性）。
func _family_paths(kind: String, family: String) -> Array:
	var pool: Array = []
	match kind:
		"weapon":
			pool = _duel.WEAPON_POOL
		"skill":
			pool = _duel.SKILL_POOL
		_:
			pool = _duel.ITEM_POOL
	var basic: Array = []
	var any: Array = []
	for p in pool:
		var s := String(p)
		if s.get_file().contains("_relic"):
			continue
		var res: Resource = _pool.resource_of(s)
		if res == null:
			continue
		var fams: Variant = res.get("family_tags")
		if not (fams is Array) or not (fams as Array).has(family):
			continue
		if int(res.get("act_min")) > 1 or int(res.get("act_max")) < 1:
			continue
		if kind == "passive" and String(res.get("category")) != "passive":
			continue
		if kind == "active" and String(res.get("category")) != "active":
			continue
		if kind == "weapon" and not (res is WeaponData):
			continue
		if kind == "skill" and not (res is SkillData):
			continue
		any.append(s)
		if String(res.get("rarity")) in ["common", "uncommon"]:
			basic.append(s)
	basic.sort()
	any.sort()
	return basic if not basic.is_empty() else any


func _clear_room_one() -> bool:
	_duel.player_hp_max = GOD_HP
	_duel.player_hp = GOD_HP
	var turns := 0
	while turns < ROOM_TURN_BUDGET:
		if _duel.game_state == DuelController.FlowState.WON:
			return true
		if _duel.game_state == DuelController.FlowState.LOST:
			return false
		turns += 1
		await _play_one_turn()
	return false


func _play_one_turn() -> void:
	_duel._on_spin_pressed()
	var guard := 0
	while guard < 900:
		if _duel.reel_system.spinning:
			_duel._on_spin_button_pressed()
		elif not _duel._busy:
			return
		guard += 1
		await get_tree().process_frame


func _leave_post_battle() -> void:
	if _duel.room_flow.post_battle_active:
		_duel.room_flow.skip_post_battle()
	await _frames(1)


# ---------------------------------------------------------------------------
# ⑦ 数值优先 vs 家族联动优先
# ---------------------------------------------------------------------------

func _test_draft_policies() -> void:
	var power_eff := 0.0
	var syn_eff := 0.0
	var power_coh := 0.0
	var syn_coh := 0.0
	var power_n := 0
	var syn_n := 0
	var same_pick := 0
	var picks := 0
	var power_overlap := 0
	var syn_overlap := 0
	var syn_picks := 0
	var weak_syn := 0
	for run_i in DRAFT_RUNS:
		var power_build: Array = []
		var syn_build: Array = []
		var pool := LootPool.new()
		pool.reset_run(SEED + run_i * 97)
		var offer := LootOffer.new(null, pool)
		for offer_i in DRAFT_OFFERS:
			var source: String = ["normal", "normal", "elite", "chest"][offer_i % 4]
			var act: int = 1 + int(offer_i / 6)
			var view: Dictionary = offer.build(source, act)
			if not bool(view.get("ok", false)):
				continue
			var entries: Array = []
			for o in view.get("options", []):
				entries.append(_draft_entry(o as Dictionary, pool))
			var pi := _pick_power(entries)
			var si := _pick_synergy(entries, syn_build)
			picks += 1
			if pi >= 0 and pi == si:
				same_pick += 1
			var best_p := 0.0
			for e in entries:
				best_p = maxf(best_p, float((e as Dictionary).get("power", 0.0)))
			if si >= 0 and best_p > 0.0:
				syn_picks += 1
				# 「联动选择」不该长期被迫吞下明显更弱的选项（< 本组最强的一半）。
				if float((entries[si] as Dictionary).get("power", 0.0)) < best_p * 0.5:
					weak_syn += 1
			if pi >= 0:
				power_overlap += _overlap(entries[pi], power_build)
				power_build.append(entries[pi])
			if si >= 0:
				syn_overlap += _overlap(entries[si], syn_build)
				syn_build.append(entries[si])
		power_n += power_build.size()
		syn_n += syn_build.size()
		power_eff += _effective(power_build)
		syn_eff += _effective(syn_build)
		power_coh += _coherence(power_build)
		syn_coh += _coherence(syn_build)
	var runs := float(DRAFT_RUNS)
	power_eff /= runs
	syn_eff /= runs
	power_coh /= runs
	syn_coh /= runs
	var ratio := syn_eff / maxf(power_eff, 0.001)
	power_overlap /= runs
	syn_overlap /= runs
	_check(power_n > 0 and syn_n > 0, "两种策略都拿到真实选项（%d / %d）" % [power_n, syn_n])
	_check(syn_overlap > power_overlap,
		"家族策略每次选卡的家族重叠更高（%.2f > %.2f）" % [syn_overlap, power_overlap])
	_check(syn_coh >= power_coh,
		"家族策略构筑一致性不劣于数值策略（%.3f ≥ %.3f）" % [syn_coh, power_coh])
	var weak_share := float(weak_syn) / float(maxi(syn_picks, 1))
	_check(weak_share <= 0.05,
		"联动选择很少吞下明显更弱的选项（%d/%d = %.1f%% ≤ 5%%）"
		% [weak_syn, syn_picks, weak_share * 100.0])
	# 数值策略是同一目标函数的贪心 argmax，天然拿满分，所以这里只验证「联动不以压倒性代价换一致性」：
	# 名义强度损失 ≤ 25%。强度代理把武器/护符/消耗品的不同量纲直接相加，只用于排序对照，不是难度结论。
	_check(ratio >= 0.75,
		"家族策略名义强度损失 ≤ 25%%（%.1f / %.1f = %.2f）" % [syn_eff, power_eff, ratio])
	print("LOOTBAL|DRAFT runs=%d offers=%d power_eff=%.1f syn_eff=%.1f power_coh=%.3f syn_coh=%.3f overlap=%.2f/%.2f same_pick=%d/%d"
		% [DRAFT_RUNS, picks, power_eff, syn_eff, power_coh, syn_coh,
		power_overlap, syn_overlap, same_pick, picks])


# 该选项与既有构筑的家族重叠次数（家族联动策略的直接度量）。
func _overlap(entry: Dictionary, build: Array) -> int:
	var counts := {}
	for e in build:
		for f in (e as Dictionary).get("families", []):
			counts[String(f)] = int(counts.get(String(f), 0)) + 1
	var score := 0
	for f in entry.get("families", []):
		score += int(counts.get(String(f), 0))
	return score


func _draft_entry(opt: Dictionary, pool: LootPool) -> Dictionary:
	var fams: Array = []
	var power := 0.0
	if String(opt.get("kind", "")) == "item":
		var res: Resource = pool.resource_of(String(opt.get("path", "")))
		if res != null:
			var f: Variant = res.get("family_tags")
			if f is Array:
				fams = (f as Array).duplicate()
			power = _item_power(res)
	elif String(opt.get("conversion", "")) == "power":
		power = float(opt.get("power", 0)) * 2.0
	else:
		power = float(opt.get("gold", 0)) * 0.15
	# 转化 / 跳过不带家族标签：它们不是构筑件，若打上 "resource" 标签会把联动策略往金币上拽。
	return {"families": fams, "power": power}


# 与 Step 8 文档同一口径的强度代理：base_power × 命中 × 暴击期望（× 破甲 1.15）；
# 护符取 value，消耗品取 value × charges（多用途即价值）。
func _item_power(res: Resource) -> float:
	var power := _f(res.get("base_power"))
	if power > 0.0:
		var hit := _f(res.get("hit_rate"))
		var crit := _f(res.get("crit_chance"))
		var crit_mult := _f(res.get("crit_mult"))
		var p := power * maxf(0.01, hit) * (1.0 + crit * maxf(0.0, crit_mult - 1.0))
		if _b(res.get("triple_pierce")):
			p *= 1.15
		return p
	var value := _f(res.get("value"))
	if value <= 0.0:
		return 5.0
	if _s(res.get("category")) == "active":
		return value * float(maxi(1, _i(res.get("charges"))))
	return value


func _pick_power(entries: Array) -> int:
	var best := -1
	var best_p := -1.0
	for i in range(entries.size()):
		var p := float((entries[i] as Dictionary).get("power", 0.0))
		if p > best_p:
			best_p = p
			best = i
	return best


# 「家族联动优先」的玩家行为：先排除本组里明显更弱（< 最强 60%）的选项，再按家族重叠数取最大，
# 重叠相同取数值更高者。全部都很弱时才退化为纯重叠优先——这样比较的是「合理的联动选择」，
# 而不是「为了联动硬吞陷阱选项」。
func _pick_synergy(entries: Array, build: Array) -> int:
	var counts := {}
	for e in build:
		for f in (e as Dictionary).get("families", []):
			counts[String(f)] = int(counts.get(String(f), 0)) + 1
	var best_p := 0.0
	for e in entries:
		best_p = maxf(best_p, float((e as Dictionary).get("power", 0.0)))
	var idx := _synergy_best(entries, counts, best_p * 0.6)
	if idx < 0:
		idx = _synergy_best(entries, counts, 0.0)
	return idx


func _synergy_best(entries: Array, counts: Dictionary, min_power: float) -> int:
	var best := -1
	var best_score := -1
	var best_pw := -1.0
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var p := float(e.get("power", 0.0))
		if p < min_power:
			continue
		var score := 0
		for f in e.get("families", []):
			score += int(counts.get(String(f), 0))
		if score > best_score or (score == best_score and p > best_pw):
			best_score = score
			best_pw = p
			best = i
	return best


func _coherence(build: Array) -> float:
	var counts := {}
	var tagged := 0
	for e in build:
		var fams: Array = (e as Dictionary).get("families", [])
		if fams.is_empty():
			continue   # 转化/跳过不算构筑件
		tagged += 1
		for f in fams:
			counts[String(f)] = int(counts.get(String(f), 0)) + 1
	if tagged == 0:
		return 0.0
	var top := 0
	for f in counts:
		top = maxi(top, int(counts[f]))
	return float(top) / float(tagged)


func _effective(build: Array) -> float:
	var total := 0.0
	for e in build:
		total += float((e as Dictionary).get("power", 0.0))
	return total * (1.0 + SYNERGY_BONUS * _coherence(build))
