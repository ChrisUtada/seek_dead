extends Node

# ============================================================================
# P1.1① 武器替换接入 draft 测试（2026-11-19）
# 覆盖：
# ① weapon 类别启用且能生成武器卡
# ② 空槽武器卡经 Resolver 直接装备
# ③ 槽满武器卡 view 标 needs_replace + path
# ④ settle_loot_replace 的 draft 分支成功替换
# ============================================================================

var _fails := 0
var _checks := 0


func _ready() -> void:
	await _run()


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("P1.1① FAIL: " + label)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	return duel


func _run() -> void:
	var duel := await _boot()
	if duel == null:
		push_error("boot failed")
		get_tree().quit(2)
		return
	var rs = duel._reward_system

	# ① weapon 卡构造（从已拥有未装备武器）
	var defs: Array = rs._make_weapon_defs()
	_ok(not defs.is_empty(), "weapon defs generated (got %d)" % defs.size())
	var wdef = defs[0]
	_ok(String(wdef.effective_category()) == "weapon", "weapon def category=weapon")
	_ok(wdef.first_effect_id() == "weapon_replace", "weapon def effect=weapon_replace")

	# ② 空槽武器卡：Resolver 直接装备
	var extra: Array = [wdef]
	var view: Dictionary = rs.build_loot_offer("normal", 1, {"growth_only": true})
	# build_loot_offer 会自行加 extra，这里测 Resolver 直接 resolve
	var loadout_before: int = duel.selected_loadout.size()
	var res = rs._draft_resolver.resolve(wdef)
	if loadout_before < duel._loadout_system.cat_cap("weapon"):
		_ok(res.ok, "empty-slot weapon resolve ok: %s" % res.reason)
		_ok(duel.selected_loadout.size() == loadout_before + 1, "weapon equipped to empty slot")
	else:
		_ok(not res.ok and res.reason == "needs_replace", "full-slot weapon returns needs_replace")

	# ③ 槽满 view 标 needs_replace + path
	# 构造一个槽满场景：填满武器槽
	while duel.selected_loadout.size() < duel._loadout_system.cat_cap("weapon"):
		var more: Array = rs._make_weapon_defs()
		if more.is_empty():
			break
		var slot_res = rs._draft_resolver.resolve(more[0])
		if not slot_res.ok:
			break
	var full_defs: Array = rs._make_weapon_defs()
	if not full_defs.is_empty() and duel.selected_loadout.size() >= duel._loadout_system.cat_cap("weapon"):
		var opt: Dictionary = RewardPresentation.definition_to_option(full_defs[0], duel)
		_ok(bool(opt.get("needs_replace", false)), "full-slot weapon option needs_replace")
		_ok(String(opt.get("path", "")) != "", "weapon option has path")

		# ④ settle_loot_replace draft 分支：构造 draft 含该武器卡并替换
		var snap = RunStateAnalyzer.capture(duel)
		var fake_draft: DraftResult = rs._draft_composer.compose(snap, 3, false, [full_defs[0]], false)
		rs._draft_result = fake_draft
		rs._draft_active = true
		rs._loot_settled = false
		# 找到武器卡在 draft 里的 index
		var windex: int = -1
		for i in range(fake_draft.rewards.size()):
			if fake_draft.rewards[i].first_effect_id() == "weapon_replace":
				windex = i
				break
		if windex >= 0:
			var old_path: String = duel.selected_loadout[0]
			var new_path: String = duel.selected_loadout[1] if duel.selected_loadout.size() > 1 else ""
			# 用一个未装备的武器作为候选
			var cand: String = String(full_defs[0].effects[0]["params"].get("weapon_path", ""))
			if cand != "" and cand != old_path:
				var rr: Dictionary = rs.settle_loot_replace(windex, old_path)
				_ok(bool(rr.get("ok", false)), "draft replace ok: %s" % str(rr.get("reason", "")))
				_ok(duel.selected_loadout.has(cand), "new weapon equipped after replace")
				_ok(not duel.selected_loadout.has(old_path), "old weapon removed")

	print("P11WEAPON RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
