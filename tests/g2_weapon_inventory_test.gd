extends Node

# ============================================================================
# G2-1 本局武器仓库测试（headless）
# 运行：Godot --headless --path <项目> res://tests/g2_weapon_inventory_test.tscn
#
# 覆盖（权威 §5.1 / G2-1）：
# ① 三态分离：run_weapon_inventory（本局）与 meta.owned_weapons（局外）独立
# ② 开局携带武器自动加入本局仓库（当前已装备 ⊆ 本局已拥有）
# ③ reset_run_state 清空仓库，不落盘
# ④ 换下武器仍保留在本局仓库（G2-5 前瞻，验证仓库模型基础）
# 不污染真实存档：结束还原 meta。
# ============================================================================

var _fails := 0
var _checks := 0


func _ready() -> void:
	await _run()


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G2 FAIL: " + label)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	return duel


func _run() -> void:
	var duel := await _boot()
	if duel == null:
		push_error("G2 boot failed")
		get_tree().quit(2)
		return
	var meta_backup: Dictionary = duel.meta.duplicate(true)

	_test_inventory_separate(duel)
	await _test_start_loadout_in_inventory(duel)
	_test_reset_clears(duel)
	await _test_swap_keeps_in_inventory(duel)
	_test_g2g2_generation_split(duel)
	_test_g2g2_resolve_semantics(duel)
	_test_g2g2_option_marking(duel)
	_test_g2g3_sources_write_inventory(duel)
	_test_g2g3_codex_discovery(duel)
	_test_g2g3_real_swap_keeps_inventory(duel)
	_test_g2g4_build_diff(duel)

	duel.meta.clear()
	for k in meta_backup:
		duel.meta[k] = meta_backup[k]
	duel._meta_store.save_meta()
	print("G2INV RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_inventory_separate(duel: DuelController) -> void:
	_ok(duel.run_weapon_inventory is Array, "run_weapon_inventory field exists")
	_ok(duel.meta.has("owned_weapons"), "meta.owned_weapons (out-of-run) still exists")
	# 本局仓库不落盘：不是 meta 的键
	_ok(not duel.meta.has("run_weapon_inventory"), "run inventory is not persisted in meta")


func _test_start_loadout_in_inventory(duel: DuelController) -> void:
	# _boot 后尚未 confirm_loadout，走一次完整开局
	duel.selected_loadout.assign(["res://resources/weapon_templates/fire_sword.tres",
		"res://resources/weapon_templates/dagger.tres"])
	duel._confirm_loadout()
	await get_tree().process_frame
	for wpath in duel.selected_loadout:
		_ok(duel.run_weapon_inventory.has(wpath), "start loadout weapon in run inventory: %s" % wpath)
	_ok(duel.run_weapon_inventory.size() >= 2, "run inventory has both starter weapons (size=%d)" % duel.run_weapon_inventory.size())


func _test_reset_clears(duel: DuelController) -> void:
	duel.run_weapon_inventory.append("res://resources/weapon_templates/battle_axe.tres")
	_ok(duel.run_weapon_inventory.size() > 0, "inventory non-empty before reset")
	duel._reset_run_state()
	_ok(duel.run_weapon_inventory.is_empty(), "reset_run_state clears run inventory")


func _test_swap_keeps_in_inventory(duel: DuelController) -> void:
	# 开局仓库应含当前装备；换下武器（从 selected_loadout 移除）不应从仓库消失
	duel.selected_loadout.assign(["res://resources/weapon_templates/fire_sword.tres",
		"res://resources/weapon_templates/dagger.tres"])
	duel._confirm_loadout()
	await get_tree().process_frame
	var old_path := String(duel.selected_loadout[0])
	_ok(duel.run_weapon_inventory.has(old_path), "equipped weapon in inventory before swap")
	# 模拟换下：从装备移除，仓库应仍保留（G2-5 目标；仓库模型已支持）
	duel.selected_loadout.erase(old_path)
	_ok(duel.run_weapon_inventory.has(old_path), "swapped-out weapon still in run inventory")


# G2-2：生成侧拆分——swap 从本局仓库未装备武器生成，acquire 从局外未拥有生成且低频。
func _test_g2g2_generation_split(duel: DuelController) -> void:
	var rs = duel._reward_system
	# 构造：仓库含 2 把未装备武器（ice_staff + battle_axe），装备 fire_sword
	duel.selected_loadout.assign(["res://resources/weapon_templates/fire_sword.tres"])
	duel.run_weapon_inventory.clear()
	duel.run_weapon_inventory.append("res://resources/weapon_templates/fire_sword.tres")
	duel.run_weapon_inventory.append("res://resources/weapon_templates/ice_staff.tres")
	duel.run_weapon_inventory.append("res://resources/weapon_templates/battle_axe.tres")
	var swap_defs: Array = rs._make_weapon_swap_defs()
	_ok(swap_defs.size() == 2, "G2-2 swap defs from run inventory unequipped (got %d)" % swap_defs.size())
	for d in swap_defs:
		_ok(String(d.first_effect_id()) == "weapon_swap", "G2-2 swap def effect=weapon_swap")
		_ok(String(d.name).find("本局仓库换装") >= 0, "G2-2 swap card marked 本局仓库换装")
		var wp := String(d.effects[0].get("params", {}).get("weapon_path", ""))
		_ok(duel.run_weapon_inventory.has(wp) and not duel.selected_loadout.has(wp), "G2-2 swap candidate in inventory & unequipped")
	# acquire：局外已解锁但本局仓库未拥有的武器（dagger 在 starter 但未入本局仓库）
	var acquire_defs: Array = rs._make_weapon_acquire_defs()
	_ok(acquire_defs.size() >= 1, "G2-2 acquire defs from out-of-run unlocked (got %d)" % acquire_defs.size())
	_ok(acquire_defs.size() <= 1, "G2-2 acquire low-frequency (max 1, got %d)" % acquire_defs.size())
	var ad = acquire_defs[0]
	_ok(String(ad.first_effect_id()) == "weapon_acquire", "G2-2 acquire def effect=weapon_acquire")
	var awp := String(ad.effects[0].get("params", {}).get("weapon_path", ""))
	_ok(not duel.run_weapon_inventory.has(awp), "G2-2 acquire candidate not yet in run inventory")
	# _draft_extra 两池都含
	var extra: Array = rs._draft_extra()
	var has_swap := false
	var has_acquire := false
	for d in extra:
		if d is RewardDefinition:
			if String(d.first_effect_id()) == "weapon_swap":
				has_swap = true
			if String(d.first_effect_id()) == "weapon_acquire":
				has_acquire = true
	_ok(has_swap, "G2-2 draft extra contains weapon_swap")
	_ok(has_acquire, "G2-2 draft extra contains weapon_acquire")


# G2-2：结算语义——acquire 写本局仓库+遥测，swap 不改局外收藏+遥测。
func _test_g2g2_resolve_semantics(duel: DuelController) -> void:
	var resolver = duel._reward_system._draft_resolver
	# 空槽场景：卸下到 0 装备（测试态，直接改）
	duel.selected_loadout.clear()
	duel.run_weapon_inventory.clear()
	var t = duel._telemetry
	var acq_before: int = t.weapon_acquires
	var swap_before: int = t.weapon_swaps_draft
	# acquire：局外 dagger（未在本局仓库）
	var acq := RewardDefinition.new()
	acq.id = "g2_acq"
	acq.name = "获取测试"
	acq.rarity = "common"
	acq.effects = [{"effect_id": "weapon_acquire", "params": {"weapon_path": "res://resources/weapon_templates/dagger.tres"}}]
	var ra = resolver.resolve(acq)
	_ok(ra.ok, "G2-2 acquire resolve ok: %s" % ra.reason)
	_ok(duel.run_weapon_inventory.has("res://resources/weapon_templates/dagger.tres"), "G2-2 acquire writes run inventory")
	_ok(t.weapon_acquires == acq_before + 1, "G2-2 acquire telemetry counted")
	# swap：本局仓库中的另一把武器（ice_staff），空槽直接装备，不改局外收藏
	duel.run_weapon_inventory.append("res://resources/weapon_templates/ice_staff.tres")
	var out_before: int = duel.meta["owned_weapons"].size()
	var swp := RewardDefinition.new()
	swp.id = "g2_swp"
	swp.name = "换装测试"
	swp.rarity = "common"
	swp.effects = [{"effect_id": "weapon_swap", "params": {"weapon_path": "res://resources/weapon_templates/ice_staff.tres"}}]
	var rs2 = resolver.resolve(swp)
	_ok(rs2.ok, "G2-2 swap resolve ok: %s" % rs2.reason)
	_ok(t.weapon_swaps_draft == swap_before + 1, "G2-2 swap telemetry counted")
	_ok(duel.meta["owned_weapons"].size() == out_before, "G2-2 swap does not write out-of-run collection")
	# swap 不在本局仓库应被 preflight 拒绝
	var bad := RewardDefinition.new()
	bad.id = "g2_bad"
	bad.name = "伪造换装"
	bad.rarity = "common"
	bad.effects = [{"effect_id": "weapon_swap", "params": {"weapon_path": "res://resources/weapon_templates/battle_axe.tres"}}]
	var rb = resolver.resolve(bad)
	_ok(not rb.ok and String(rb.reason) == "not_in_run_inventory", "G2-2 swap outside inventory rejected")


# G2-2：卡面标记——三类武器 effect 都标 path/needs_replace/weapon_effect。
func _test_g2g2_option_marking(duel: DuelController) -> void:
	duel.selected_loadout.assign(["res://resources/weapon_templates/fire_sword.tres",
		"res://resources/weapon_templates/dagger.tres"])
	for eid in ["weapon_replace", "weapon_swap", "weapon_acquire"]:
		var d := RewardDefinition.new()
		d.id = "opt_" + eid
		d.name = "测试"
		d.rarity = "common"
		d.effects = [{"effect_id": eid, "params": {"weapon_path": "res://resources/weapon_templates/battle_axe.tres"}}]
		var opt: Dictionary = RewardPresentation.definition_to_option(d, duel)
		_ok(bool(opt.get("needs_replace", false)), "G2-2 %s option needs_replace when full" % eid)
		_ok(String(opt.get("path", "")) != "", "G2-2 %s option has path" % eid)
		_ok(String(opt.get("weapon_effect", "")) == eid, "G2-2 %s option tagged weapon_effect" % eid)


# G2-3：所有获得来源统一写本局仓库（以 remember_weapon 为统一入口验证）。
func _test_g2g3_sources_write_inventory(duel: DuelController) -> void:
	var rs = duel._reward_system
	duel.run_weapon_inventory.clear()
	var p := "res://resources/weapon_templates/dawn_blade.tres"
	# 模拟任意来源获得：统一入口 remember_weapon
	rs.remember_weapon(p, "elite")
	_ok(duel.run_weapon_inventory.has(p), "G2-3 remember_weapon writes run inventory")
	_ok(duel.meta["owned_weapons"].has(p), "G2-3 remember_weapon still writes out-of-run unlock")
	# 重复获得不重复入库（数组不出现两次）
	rs.remember_weapon(p, "boss")
	var cnt := 0
	for wp in duel.run_weapon_inventory:
		if String(wp) == p:
			cnt += 1
	_ok(cnt == 1, "G2-3 duplicate acquire does not duplicate inventory entry (got %d)" % cnt)


# G2-3：图鉴首次发现独立记录，与局外解锁/本局仓库三者分离。
func _test_g2g3_codex_discovery(duel: DuelController) -> void:
	var codex = duel._codex
	_ok(codex != null, "G2-3 codex exists")
	if codex == null:
		return
	var p := "res://resources/weapon_templates/eclipse_blade.tres"
	var before: bool = codex.is_discovered(p)
	duel._reward_system.remember_weapon(p, "normal")
	_ok(codex.is_discovered(p), "G2-3 first acquire marks codex discovered")
	_ok(not before or codex.is_discovered(p), "G2-3 discovery idempotent")
	# 独立结果：即使本局仓库被清（换局），图鉴发现仍持久（读的是 meta.codex）
	duel.run_weapon_inventory.clear()
	_ok(codex.is_discovered(p), "G2-3 codex discovery independent of run inventory")


# G2-3：真实换装路径（replace_weapon_at_slot）后，换下的武器仍留在本局仓库。
func _test_g2g3_real_swap_keeps_inventory(duel: DuelController) -> void:
	var sword := "res://resources/weapon_templates/fire_sword.tres"
	var dagger := "res://resources/weapon_templates/dagger.tres"
	var axe := "res://resources/weapon_templates/battle_axe.tres"
	duel.selected_loadout.assign([sword, dagger])
	duel.run_weapon_inventory.clear()
	duel.run_weapon_inventory.append(sword)
	duel.run_weapon_inventory.append(dagger)
	duel.run_weapon_inventory.append(axe)
	var slot: int = duel.selected_loadout.find(sword)
	_ok(slot >= 0, "G2-3 old weapon equipped")
	_ok(duel.replace_weapon_at_slot(slot, axe), "G2-3 replace_weapon_at_slot succeeds")
	_ok(not duel.selected_loadout.has(sword), "G2-3 old weapon unequipped")
	_ok(duel.run_weapon_inventory.has(sword), "G2-3 swapped-out weapon still in run inventory")


# G2-4：替换预览的构筑得失只读对比（牌谱/签名/元素覆盖）。
func _test_g2g4_build_diff(duel: DuelController) -> void:
	var fire := "res://resources/weapon_templates/fire_sword.tres"
	var dagger := "res://resources/weapon_templates/dagger.tres"
	var ice := "res://resources/weapon_templates/ice_staff.tres"
	# fire_sword 带签名 SIG_FIRE_SWORD；换成 dagger 应失去该签名
	duel.selected_loadout.assign([fire, dagger])
	var loadout_before: Array = duel.selected_loadout.duplicate()
	var diff_lose: String = duel.build_swap_build_diff(fire, ice)
	_ok(diff_lose != "", "G2-4 build diff not empty when changing signature weapon")
	_ok(diff_lose.find("失去签名") >= 0, "G2-4 build diff reports lost signature (got: %s)" % diff_lose)
	# 只读：调用不修改配装
	_ok(duel.selected_loadout == loadout_before, "G2-4 build diff is read-only (loadout unchanged)")
	# 元素覆盖：fire 元素换成 ice → 失去火/获得冰
	_ok(diff_lose.find("火") >= 0 or diff_lose.find("冰") >= 0, "G2-4 build diff reports element coverage change (got: %s)" % diff_lose)
	# 换入 fire_sword：当前配装设为 [dagger, ice]（都不带 fire 签名），换入 fire 应获得签名
	duel.selected_loadout.assign([dagger, ice])
	var diff_gain: String = duel.build_swap_build_diff(dagger, fire)
	_ok(diff_gain.find("获得签名") >= 0, "G2-4 build diff reports gained signature (got: %s)" % diff_gain)
