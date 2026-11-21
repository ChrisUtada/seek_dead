extends Node

# ============================================================================
# P0.1 统一奖励生成器测试（headless，2026-11-19）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/p01_generator_test.tscn
#
# 覆盖（V1.1 §14）：
# ① RewardDefinition 新字段兼容（category/effect_family/enabled 缺省值）
# ② effective_category() 推断：旧资源按 tags/effect_id 归类
# ③ CategoryResolver 分组、权重归一化（关闭类别权重重分配）
# ④ DraftComposer compose 返回 3 张合法、无重复、同类≤2
# ⑤ 槽位倾向：Slot A 优先核心成长类别
# ⑥ 同质化检查：同组不出现 3 张同类别
# ⑦ 保底强制技艺（force_skill=true）注入技艺候选
# ⑧ 1000 组连续生成压力测试：成功率/数量/去重/同类限制/类别分布
# 不启动 DuelController（纯生成器测试）。
# ============================================================================

var _fails := 0
var _checks := 0


func _ready() -> void:
	_run()


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("P0.1 FAIL: " + label)


func _snap(hp_ratio: float = 1.0) -> RunSnapshot:
	var s := RunSnapshot.new()
	s.survival = {"current_hp": int(hp_ratio * 100), "max_hp": 100, "hp_ratio": hp_ratio}
	s.economy = {"gold": 20}
	s.progression = {"room_index": 1, "act": 1, "room_kind": "normal"}
	return s


func _run() -> void:
	_test_definition_fields()
	_test_category_inference()
	_test_resolver()
	_test_compose_basic()
	_test_slot_preference()
	_test_homogeneity()
	_test_force_skill()
	_test_g1c_fallback_filter()
	_test_g1c_refill_no_owned()
	_test_g1d_reroll_no_same_group()
	_test_g1d_reroll_exhausted_allows_same()
	_test_stress_1000()
	print("P01GEN RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_definition_fields() -> void:
	var d := RewardDefinition.new()
	_ok(d.category == "" and d.effect_family == "" and d.enabled, "new fields have compat defaults")
	_ok(d.effective_effect_family() != "", "effective_effect_family falls back to first effect id")


func _test_category_inference() -> void:
	var d := RewardDefinition.new()
	# 技艺
	d.tags = ["growth.perk"]
	d.effects = [{"effect_id": "pick_perk", "params": {"id": "tough"}}]
	_ok(d.effective_category() == "skill", "perk def -> skill category")
	# 签名
	d.tags = ["discovery.signature"]
	d.effects = [{"effect_id": "learn_signature", "params": {"signature_id": "X"}}]
	_ok(d.effective_category() == "signature", "signature def -> signature category")
	# 生存
	d.tags = ["survival.heal"]
	d.effects = [{"effect_id": "heal", "params": {"pct": 0.3}}]
	_ok(d.effective_category() == "survival_resource", "heal def -> survival_resource")
	# 显式 category 优先
	d.category = "reel_control"
	_ok(d.effective_category() == "reel_control", "explicit category wins")


func _test_resolver() -> void:
	var groups := {
		"symbol_mod": [RewardDefinition.new(), RewardDefinition.new()],
		"skill": [RewardDefinition.new()],
		"signature": [RewardDefinition.new()],
	}
	var r := CategoryResolver.new()
	var w := r.normalized_weights(groups)
	var total := 0.0
	for c in w:
		total += float(w[c])
	_ok(absf(total - 100.0) < 0.01, "weights normalized to 100")
	_ok(not w.has("signature"), "P0-disabled signature removed from weights")
	_ok(w.has("symbol_mod") and w.has("skill"), "available categories kept")


func _test_compose_basic() -> void:
	var c := DraftComposer.new(1234)
	var draft: DraftResult = c.compose(_snap(0.5), 3, true)
	_ok(draft is DraftResult, "compose returns DraftResult")
	_ok(draft.rewards.size() == 3, "compose returns 3 cards")
	var ids := {}
	var cats := {}
	for d in draft.rewards:
		_ok(not ids.has(d.id), "no duplicate reward id: %s" % d.id)
		ids[d.id] = true
		var cat := d.effective_category()
		cats[cat] = int(cats.get(cat, 0)) + 1
	for cat in cats:
		_ok(int(cats[cat]) <= 2, "category %s count <= 2" % cat)


func _test_slot_preference() -> void:
	# 多次生成，统计 Slot A（第1张）核心类别（symbol_mod/rule_mod）出现率应 > 其他
	var c := DraftComposer.new(777)
	var core_count := 0
	var trials := 60
	for i in range(trials):
		var draft: DraftResult = c.compose(_snap(1.0), 3, false)
		if draft.rewards.size() > 0:
			var cat := draft.rewards[0].effective_category()
			if cat in ["symbol_mod", "rule_mod"]:
				core_count += 1
	_ok(core_count > trials / 2, "Slot A mostly core growth (%d/%d)" % [core_count, trials])


func _test_homogeneity() -> void:
	var c := DraftComposer.new(555)
	for i in range(40):
		var draft: DraftResult = c.compose(_snap(1.0), 3, false)
		var cats := {}
		for d in draft.rewards:
			var cat := d.effective_category()
			cats[cat] = int(cats.get(cat, 0)) + 1
		var max_same := 0
		for cat in cats:
			max_same = maxi(max_same, int(cats[cat]))
		if max_same > 2:
			_ok(false, "no 3-same-category group (trial %d, %s)" % [i, str(cats)])
			return
	_ok(true, "no 3-same-category group across 40 drafts")


func _test_force_skill() -> void:
	var c := DraftComposer.new(888)
	var perk := RewardDefinition.new()
	perk.id = "perk_tough"
	perk.name = "坚韧"
	perk.rarity = "uncommon"
	perk.effects = [{"effect_id": "pick_perk", "params": {"id": "tough"}}]
	perk.category = "skill"
	perk.effect_family = "perk"
	var draft: DraftResult = c.compose(_snap(1.0), 3, false, [perk], true)
	var has_skill := false
	for d in draft.rewards:
		if d.effective_category() == "skill":
			has_skill = true
	_ok(has_skill, "force_skill injects a skill candidate")


# G1-C：Fallback 复用完整过滤，不得放回「已拥有 / 满血治疗」卡。
func _test_g1c_fallback_filter() -> void:
	var c := DraftComposer.new(4242)
	# owned 掉两张 reel_control，满血快照 → heal 卡(seed_battle_ready)也应被过滤
	c.set_owned_ids(["control_mercy", "control_slow_ramp"])
	var fb: DraftResult = c._fallback(_snap(1.0), 3, "g1c_test")
	var ids := {}
	for d in fb.rewards:
		ids[String(d.id)] = true
	_ok(not ids.has("control_mercy"), "fallback excludes owned control_mercy")
	_ok(not ids.has("control_slow_ramp"), "fallback excludes owned control_slow_ramp")
	_ok(not ids.has("seed_battle_ready"), "fallback excludes full-hp heal card")
	# 五张共鸣卡(disabled)任何情况都不得进兜底
	for rid in ["seed_flame_resonance", "seed_frost_resonance", "seed_lumen_resonance", "seed_venom_resonance", "seed_void_resonance"]:
		_ok(not ids.has(rid), "fallback excludes disabled %s" % rid)


# G1-C：主流程「先净化后补足」，补足不得绕过 owned/disabled/满血过滤，且恰好补到 count。
func _test_g1c_refill_no_owned() -> void:
	var c := DraftComposer.new(9393)
	var owned := ["control_mercy", "control_slow_ramp", "seed_gold_cache"]
	c.set_owned_ids(owned)
	var draft: DraftResult = c.compose(_snap(1.0), 3, true)
	# 满血 → heal 卡(seed_battle_ready)过滤；owned 3 张过滤；disabled 过滤（含 S3-1a 退出的 seed_edge_polish）
	# 合法池缩小后由兜底补足到 3（不静默减少候选、不造无效卡）→ 应恰好补足到 3
	_ok(draft.rewards.size() == 3, "refill reaches 3 cards (got %d)" % draft.rewards.size())
	var ids := {}
	for d in draft.rewards:
		ids[String(d.id)] = true
	for oid in owned:
		_ok(not ids.has(oid), "compose excludes owned %s" % oid)
	_ok(not ids.has("seed_battle_ready"), "compose excludes full-hp heal card")
	_ok(ids.size() == draft.rewards.size(), "compose draft has no duplicate ids")


# G1-D：重抽去同组。合法池充足时，重抽结果 id 集合必须与上一组不同（权威 §6.5）。
# 连续多次重抽，任一相同即判失败；不同组断言针对「无序集合」使用 sorted 比较。
func _test_g1d_reroll_no_same_group() -> void:
	var c := DraftComposer.new(31415)
	var cur: DraftResult = c.compose(_snap(0.5), 3, false)
	var prev_ids: Array = []
	for d in cur.rewards:
		prev_ids.append(String(d.id))
	_ok(prev_ids.size() == 3, "g1d seed group has 3 cards")
	var repeats := 0
	for i in range(40):
		cur = c.compose_reroll(_snap(0.5), prev_ids, 3, false)
		var next_ids: Array = []
		for d in cur.rewards:
			next_ids.append(String(d.id))
		next_ids.sort()
		var cmp: Array = prev_ids.duplicate()
		cmp.sort()
		if next_ids == cmp:
			repeats += 1
		_ok(not c.last_reroll_same_group, "g1d reroll%d not flagged same_group (pool ample)" % i)
		prev_ids = next_ids
	_ok(repeats == 0, "g1d 40 rerolls never returned identical group (repeats=%d)" % repeats)


# G1-D：合法组合确实只有一组时（owned+满血后仅剩 3 张），允许相同并标记 same_group，
# 如实记录供遥测观测；不得空屏、不得缩卡、不得造假卡。
func _test_g1d_reroll_exhausted_allows_same() -> void:
	var c := DraftComposer.new(27182)
	var owned := ["control_mercy", "control_slow_ramp", "seed_gold_cache"]
	c.set_owned_ids(owned)
	var first: DraftResult = c.compose(_snap(1.0), 3, false)
	_ok(first.rewards.size() == 3, "exhausted pool still yields 3 cards")
	var prev_ids: Array = []
	for d in first.rewards:
		prev_ids.append(String(d.id))
	var again: DraftResult = c.compose_reroll(_snap(1.0), prev_ids, 3, false)
	_ok(again.rewards.size() == 3, "exhausted reroll no shrink (got %d)" % again.rewards.size())
	# G5-3：rule_mod 6 张回路卡进池后，此 owned 组合下池不再耗尽，重抽能拿到不同组合，
	# same_group 应为 false（这是正确行为，不是缺陷）。断言改为验证标志与真实组合一致：
	# 若重抽 id 集合与首次相同则必须 true，不同则必须 false。
	var prev_set := {}
	for pid in prev_ids:
		prev_set[String(pid)] = true
	var is_same := true
	for d in again.rewards:
		if not prev_set.has(String(d.id)):
			is_same = false
			break
	_ok(c.last_reroll_same_group == is_same,
		"reroll same_group 标志与实际组合一致（same=%s flag=%s）" % [str(is_same), str(c.last_reroll_same_group)])
	var ids := {}
	for d in again.rewards:
		ids[String(d.id)] = true
	for oid in owned:
		_ok(not ids.has(oid), "exhausted reroll excludes owned %s" % oid)
	_ok(not ids.has("seed_battle_ready"), "exhausted reroll excludes full-hp heal")


func _test_stress_1000() -> void:
	var c := DraftComposer.new(20261119)
	var bad_count := 0
	var cat_dist := {}
	for i in range(1000):
		var draft: DraftResult = c.compose(_snap(0.4 + float(i % 6) * 0.1), 3, false)
		if draft.rewards.size() != 3:
			bad_count += 1
			continue
		var ids := {}
		var cats := {}
		for d in draft.rewards:
			ids[d.id] = true
			var cat := d.effective_category()
			cats[cat] = int(cats.get(cat, 0)) + 1
			cat_dist[cat] = int(cat_dist.get(cat, 0)) + 1
		if ids.size() != 3:
			bad_count += 1
		for cat in cats:
			if int(cats[cat]) > 2:
				bad_count += 1
	_ok(bad_count == 0, "1000 drafts all valid (bad=%d)" % bad_count)
	_ok(cat_dist.has("symbol_mod") or cat_dist.has("rule_mod"), "core categories present in distribution")
