extends Node

# ============================================================================
# W-01A 专项：武器奖励显示与行为语义
# docs/Seek_Dead_统一设计基线与总体进度_2026-11-22.md §T1.1
#
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/w01a_weapon_reward_semantics_test.tscn
# 隔离：必须由外部覆盖 APPDATA 到临时目录后再运行，绝不触碰真实存档。
#
# 目标：复核 acquire → RewardDefinition → RewardPresentation → 卡面的完整映射；
#       武器卡继承真实品质；区分武器获取/仓库换装/持有状态；覆盖四档品质与不同来源。
#       只修显示与语义，不调出现率或数值。
# ============================================================================

const W_COMMON := "res://resources/weapon_templates/dagger.tres"
const W_UNCOMMON := "res://resources/weapon_templates/cinder_cleaver.tres"
const W_RARE := "res://resources/weapon_templates/frost_blade.tres"   # 需确认存在
const W_EPIC := "res://resources/weapon_templates/absolute_zero.tres"

var _fails := 0
var _checks := 0
var _duel: DuelController


func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	_duel = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(_duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_duel.demo_config.enabled = false
	_duel._confirm_loadout()
	await get_tree().process_frame
	_run()
	_finish()


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _true_rarity(path: String) -> String:
	var w: Resource = load(path)
	return String(w.get("rarity")) if w != null and w.has_method("get") else ""


func _def_by_effect(defs: Array, effect_id: String) -> RewardDefinition:
	for d in defs:
		if d is RewardDefinition and d.first_effect_id() == effect_id:
			return d
	return null


func _run() -> void:
	_test_swap_rarity_inherit()
	_test_acquire_rarity_inherit()
	_test_old_replace_rarity_inherit()
	_test_effective_draw_weight_decoupled()
	_test_presentation_mapping()
	_test_semantics_distinct()
	_test_needs_replace()
	_test_same_seed_draft_deterministic()


# 1：本局仓库换装（weapon_swap）卡面品质必须继承真实武器稀有度
func _test_swap_rarity_inherit() -> void:
	_duel.run_weapon_inventory = [W_COMMON, W_UNCOMMON, W_RARE, W_EPIC]
	var defs: Array = _duel._reward_system._make_weapon_swap_defs()
	_check(defs.size() >= 3, "swap 生成至少 3 张候选（实测 %d）" % defs.size())
	var covered: Dictionary = {}
	for dd in defs:
		if not (dd is RewardDefinition):
			continue
		var path: String = String((dd as RewardDefinition).effects[0].get("params", {}).get("weapon_path", ""))
		var expect: String = _true_rarity(path)
		covered[expect] = true
		_check((dd as RewardDefinition).rarity == expect,
			"swap 卡继承真实品质 %s → %s（实测 %s）" % [path.get_file(), expect, (dd as RewardDefinition).rarity])
	# 确认覆盖多档不同品质（证明不是统一硬编码某一档）
	_check(covered.size() >= 2,
		"swap 覆盖多档真实品质（实测 %s）" % str(covered.keys()))


# 2：新武器获取（weapon_acquire）卡面品质继承真实稀有度（F-01 已修，回归保护）
func _test_acquire_rarity_inherit() -> void:
	# 局外 owned 临时设为含 epic/rare 的武器，本局仓库置空使 acquire 命中
	var saved := (_duel.meta.get("owned_weapons", []) as Array).duplicate()
	_duel.meta["owned_weapons"] = [W_EPIC]
	_duel.run_weapon_inventory = []
	var defs: Array = _duel._reward_system._make_weapon_acquire_defs()
	if not defs.is_empty():
		var d: RewardDefinition = defs[0]
		_check(d.rarity == _true_rarity(W_EPIC),
			"acquire 卡继承真实品质 epic（实测 %s）" % d.rarity)
	else:
		_check(false, "acquire 候选为空（构造失败）")
	_duel.meta["owned_weapons"] = saved


# 2b：旧换装路径（weapon_replace，持有状态卡）也继承真实品质
func _test_old_replace_rarity_inherit() -> void:
	var saved := (_duel.meta.get("owned_weapons", []) as Array).duplicate()
	_duel.meta["owned_weapons"] = [W_EPIC]
	_duel.selected_loadout = []   # 清空装备使 owned 武器成为未装备候选
	var defs: Array = _duel._reward_system._make_weapon_defs()
	if not defs.is_empty():
		var d: RewardDefinition = defs[0]
		var path: String = String(d.effects[0].get("params", {}).get("weapon_path", ""))
		_check(d.rarity == _true_rarity(path),
			"旧换装卡继承真实品质 %s → %s（实测 %s）" % [path.get_file(), _true_rarity(path), d.rarity])
	else:
		_check(false, "旧换装候选为空（构造失败）")
	_duel.meta["owned_weapons"] = saved


# 2c：显示品质与实际抽取权重解耦——有效权重保持修改前原值（不只看 base_weight）
func _test_effective_draw_weight_decoupled() -> void:
	var common_mult: float = float(CategoryResolver.RARITY_DRAW_MULT["common"])
	var uncommon_mult: float = float(CategoryResolver.RARITY_DRAW_MULT["uncommon"])
	# weapon_swap：显示继承真实品质，但有效权重 = 原 common 换装卡 = base_weight × 1.0
	_duel.run_weapon_inventory = [W_UNCOMMON, W_RARE, W_EPIC]
	var swaps: Array = _duel._reward_system._make_weapon_swap_defs()
	for dd in swaps:
		if not (dd is RewardDefinition):
			continue
		var d: RewardDefinition = dd
		var path: String = String(d.effects[0].get("params", {}).get("weapon_path", ""))
		var expect: float = maxf(0.01, float(d.base_weight) * common_mult)
		var actual: float = CategoryResolver.effective_draw_weight(d)
		_check(absf(actual - expect) < 0.0001 and d.rarity != "common",
			"swap 有效权重保持原 common 口径、卡面为真品质 %s（rarity=%s weight=%.4f 期望 %.4f）" % [
				path.get_file(), d.rarity, actual, expect])

	# 旧 weapon_replace：显示继承真实品质，但有效权重 = 原 uncommon 卡 = base_weight × (20/70)
	var saved := (_duel.meta.get("owned_weapons", []) as Array).duplicate()
	_duel.meta["owned_weapons"] = [W_EPIC]
	_duel.selected_loadout = []
	var replaces: Array = _duel._reward_system._make_weapon_defs()
	if not replaces.is_empty():
		var rd: RewardDefinition = replaces[0]
		var r_expect: float = maxf(0.01, float(rd.base_weight) * uncommon_mult)
		var r_actual: float = CategoryResolver.effective_draw_weight(rd)
		_check(absf(r_actual - r_expect) < 0.0001 and rd.rarity != "uncommon",
			"旧 replace 有效权重保持原 uncommon 口径、卡面为真品质（rarity=%s weight=%.4f 期望 %.4f）" % [
				rd.rarity, r_actual, r_expect])
	else:
		_check(false, "旧 replace 候选为空（构造失败）")
	_duel.meta["owned_weapons"] = saved

	# base_weight 未被改动（区分：base_weight 未改 ≠ 有效权重未改）
	var any_swap: RewardDefinition = swaps[0] if not swaps.is_empty() else null
	if any_swap != null:
		_check(is_equal_approx(float(any_swap.base_weight), 1.0),
			"swap base_weight 仍为 1.0（实测 %.3f）" % float(any_swap.base_weight))


# 3：RewardPresentation 把 def.rarity 正确映射为 quality/quality_name（四档）
func _test_presentation_mapping() -> void:
	var map := {"common": "普通", "uncommon": "进阶", "rare": "稀有", "epic": "传说"}
	for q in ["common", "uncommon", "rare", "epic"]:
		var def := RewardDefinition.new()
		def.id = "test_" + q
		def.name = "测试武器"
		def.desc = "测试"
		def.rarity = q
		def.effects = [{"effect_id": "weapon_acquire", "params": {"weapon_path": W_EPIC}}]
		var opt: Dictionary = RewardPresentation.definition_to_option(def, _duel)
		_check(String(opt.get("quality", "")) == q, "presentation quality=%s（实测 %s）" % [q, String(opt.get("quality", ""))])
		_check(String(opt.get("quality_name", "")) == map[q], "presentation quality_name=%s（实测 %s）" % [map[q], String(opt.get("quality_name", ""))])


# 4：三类武器语义区分（获取/换装/持有）——name/desc/tags/effect_id 不同
func _test_semantics_distinct() -> void:
	var d_swap := RewardDefinition.new()
	d_swap.id = "s"; d_swap.name = "本局仓库换装"; d_swap.desc = "换上"; d_swap.rarity = "common"
	d_swap.effects = [{"effect_id": "weapon_swap", "params": {"weapon_path": W_COMMON}}]
	d_swap.tags = ["weapon", "swap", "run_inventory"]
	var d_acq := RewardDefinition.new()
	d_acq.id = "a"; d_acq.name = "新武器"; d_acq.desc = "获得"; d_acq.rarity = "epic"
	d_acq.effects = [{"effect_id": "weapon_acquire", "params": {"weapon_path": W_EPIC}}]
	d_acq.tags = ["weapon", "acquire", "new_drop"]
	var o_swap := RewardPresentation.definition_to_option(d_swap, _duel)
	var o_acq := RewardPresentation.definition_to_option(d_acq, _duel)
	_check(String(o_swap.get("effect_id", "")) == "weapon_swap" and String(o_acq.get("effect_id", "")) == "weapon_acquire",
		"语义 effect_id 区分 swap/acquire")
	_check(String(d_swap.name) != String(d_acq.name), "语义 name 区分换装/获取")
	_check((o_swap.get("tags", []) as Array).has("swap") and (o_acq.get("tags", []) as Array).has("acquire"),
		"语义 tags 区分 swap/acquire")


# 5：槽满时 needs_replace 标记（持有/换装状态）
func _test_needs_replace() -> void:
	var saved: Array = _duel.selected_loadout.duplicate()
	while _duel.selected_loadout.size() < _duel._loadout_system.cat_cap("weapon"):
		_duel.selected_loadout.append(W_COMMON)
	var def := RewardDefinition.new()
	def.id = "nr"; def.name = "武器"; def.desc = "换上"; def.rarity = "uncommon"
	def.effects = [{"effect_id": "weapon_swap", "params": {"weapon_path": W_UNCOMMON}}]
	var opt := RewardPresentation.definition_to_option(def, _duel)
	_check(bool(opt.get("needs_replace", false)), "槽满时 needs_replace=true（触发替换层）")
	_duel.selected_loadout = saved


# 同种子同输入：Draft 卡序列与有效权重必须完全一致（证明 RNG/分布未被权重解耦改变）
func _test_same_seed_draft_deterministic() -> void:
	var snap := RunStateAnalyzer.capture(_duel)
	var extra: Array = _duel._reward_system._draft_extra()
	var c1 := DraftComposer.new(20261122)
	var c2 := DraftComposer.new(20261122)
	var d1 = c1.compose(snap, 3, false, extra, false)
	var d2 = c2.compose(snap, 3, false, extra, false)
	var ids1: Array = []
	var ids2: Array = []
	for r in (d1.rewards as Array):
		ids1.append(String((r as RewardDefinition).id))
	for r in (d2.rewards as Array):
		ids2.append(String((r as RewardDefinition).id))
	_check(ids1 == ids2, "同种子 Draft 卡序列一致（%s vs %s）" % [str(ids1), str(ids2)])
	var w1: Array = []
	var w2: Array = []
	for r in (d1.rewards as Array):
		w1.append(CategoryResolver.effective_draw_weight(r as RewardDefinition))
	for r in (d2.rewards as Array):
		w2.append(CategoryResolver.effective_draw_weight(r as RewardDefinition))
	_check(w1 == w2, "同种子 Draft 有效权重序列一致（%s vs %s）" % [str(w1), str(w2)])


func _finish() -> void:
	print("---")
	print("W01A RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
