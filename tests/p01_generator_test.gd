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
