extends Node

# ============================================================================
# T3-3 C 轮第 4 步：第三格只读「组合预览」验收
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t3c_combo_preview_test.tscn
# 覆盖：
#   D1 纯函数：base=[iron_slash,burn] + 候选 fire_slash → W07；guard → 无 W07；
#      每个候选都有行；空候选 → 空结果；调用前后 seed/hp/charge/frozen_cols/grid 不变。
#   D2 面板：给 preview_rows 时出现「第三格预览」且行数一致；不给时不出现。
#   C3 接线：间歇期前两列已停时，点入口把预览行传给面板；未锁两格时该区段不出现。
# ============================================================================

const PANEL_SCENE := "res://scenes/ui/combo_panel.tscn"
const IRON_SWORD := "res://resources/weapon_templates/iron_sword.tres"
const DAGGER := "res://resources/weapon_templates/dagger.tres"
const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"
const DUELING_SABER := "res://resources/weapon_templates/dueling_saber.tres"
const GUARD_SKILL := "res://resources/skills/guard.tres"
const SY_BLADE := "res://resources/symbols/iron_slash.tres"
const SY_BURN := "res://resources/symbols/burn.tres"
const SY_FIRE := "res://resources/symbols/fire_slash.tres"
const SY_GUARD := "res://resources/symbols/guard.tres"
const SY_DAGGER_SLASH := "res://resources/symbols/dagger_slash.tres"

var _fails := 0
var _checks := 0
var _duel: DuelController
var _panel: ComboPanel


func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	_duel = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(_duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_duel.demo_config.enabled = false
	_duel._confirm_loadout()
	_duel.reel_system._timer.stop()
	_panel = (load(PANEL_SCENE) as PackedScene).instantiate() as ComboPanel
	add_child(_panel)
	await get_tree().process_frame

	_test_pure()
	_test_fire_loadout()
	_test_skill_candidate()
	_test_candidate_dedupe()
	_test_panel()
	await _test_wiring()

	print("T3CPREVIEW|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _card(path: String, source: String = "iron_sword") -> Dictionary:
	return {
		"sym": load(path), "element": "none", "source": source,
		"source_kind": "weapon" if source != "" else "resource",
		"source_element": "none", "skill_role": "", "valid": true,
	}


# 候选卡：与实盘同源（card_meta 解析 source_kind/source_element/skill_role），
# 额外带展示用 path/name。
func _candidate_card(path: String, element: String, source: String) -> Dictionary:
	var sym = load(path)
	var card: Dictionary = ComboCatalog.MATCHER.card_meta(_duel, sym, element, source)
	card["path"] = path
	card["name"] = String(sym.name) if sym != null and String(sym.name) != "" \
		else path.get_file().get_basename()
	return card


func _preview(base: Array, candidates: Array[Dictionary]) -> Array[Dictionary]:
	return ComboCatalog.preview_third_slot(
		base, candidates, _duel._pattern_system, Callable(_duel, "_pattern_tag_of"))


func _find_candidate(rows: Array[Dictionary], path: String) -> Dictionary:
	for r in rows:
		if String(r.get("candidate", "")) == path:
			return r
	return {}


func _matched_ids(row: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for m in (row.get("matched", []) as Array):
		if m is Dictionary:
			out.append(String((m as Dictionary).get("id", "")))
	return out


# D1：纯函数契约 + 只读证明
func _test_pure() -> void:
	# 先固定配装（铁剑），让 candidate 的 card_meta 能解析 weapon 来源；
	# 同时清掉技能，避免守备被误判成 skill 来源。
	_setup_case([IRON_SWORD], [], [SY_BLADE, SY_BURN, SY_BLADE], "iron_sword")
	var base: Array = [_card(SY_BLADE), _card(SY_BURN)]
	var candidates: Array[Dictionary] = [
		_candidate_card(SY_FIRE, "none", "iron_sword"),
		_candidate_card(SY_GUARD, "none", ""),
	]

	var seed0: int = _duel._reward_system._loot.seed_value()
	var hp0: int = int(_duel.enemy_hp)
	var charge0: int = int(_duel.charge_points)
	var frozen0: Array = _duel.frozen_cols.duplicate()
	var grid0: Array = []
	for c in 3:
		grid0.append(String(_duel.grid[c][0].resource_path))

	var rows: Array[Dictionary] = _preview(base, candidates)

	_check(rows.size() == 2, "每个候选都有行（2/实测 %d）" % rows.size())
	var fire_row: Dictionary = _find_candidate(rows, SY_FIRE)
	_check(not fire_row.is_empty(), "候选 fire_slash 有行")
	_check(_matched_ids(fire_row).has("W07"),
		"base[铁斩,燃] + 火斩 → 命中 W07（实测 %s）" % str(_matched_ids(fire_row)))
	# C3 铁剑/中性来源回归：火斩作为候选仍命中 W06（与修复前一致）
	_check(_matched_ids(fire_row).has("W06"),
		"base[铁斩,燃] + 火斩 → 命中 W06（实测 %s）" % str(_matched_ids(fire_row)))
	var w07 := {}
	for m in (fire_row.get("matched", []) as Array):
		if m is Dictionary and String((m as Dictionary).get("id", "")) == "W07":
			w07 = m
	_check(String(w07.get("name", "")) == "强化燃刃" and String(w07.get("group", "")) == "main",
		"W07 行 name=强化燃刃 / group=main（实测 %s/%s）" % [String(w07.get("name", "")), String(w07.get("group", ""))])
	_check(String(fire_row.get("candidate_name", "")) == "火斩",
		"候选名取 SymbolData.name（实测 %s）" % String(fire_row.get("candidate_name", "")))

	var guard_row: Dictionary = _find_candidate(rows, SY_GUARD)
	_check(not _matched_ids(guard_row).has("W07"), "base + 守备 不命中 W07")
	_check((guard_row.get("matched", []) as Array).is_empty(),
		"base + 守备 → 无组合（实测 %s）" % str(_matched_ids(guard_row)))

	var empty_cands: Array[Dictionary] = []
	var empty_rows: Array[Dictionary] = _preview(base, empty_cands)
	_check(empty_rows.is_empty(), "候选列表为空 → 空结果")

	_check(_duel._reward_system._loot.seed_value() == seed0, "纯函数不消耗 RNG（seed %d）" % seed0)
	_check(int(_duel.enemy_hp) == hp0, "纯函数不改 enemy_hp（%d）" % hp0)
	_check(int(_duel.charge_points) == charge0, "纯函数不改 charge_points（%d）" % charge0)
	_check(_duel.frozen_cols == frozen0, "纯函数不改 frozen_cols（%s）" % str(frozen0))
	var grid_same := true
	for c in 3:
		if String(_duel.grid[c][0].resource_path) != String(grid0[c]):
			grid_same = false
	_check(grid_same, "纯函数不改 grid（%s）" % str(grid0))


# 重建配装池并铺三格：前两格为已锁真卡（来源 src），第三格为预览列占位。
func _setup_case(weapons: Array, skills: Array, base: Array, src: String) -> void:
	_duel.selected_loadout.clear()
	for w in weapons:
		_duel.selected_loadout.append(String(w))
	_duel.selected_skills.clear()
	for s in skills:
		_duel.selected_skills.append(String(s))
	_duel._build_pool(_duel.selected_loadout)
	_duel.frozen_cols.clear()
	for c in 3:
		var path := String(base[mini(c, base.size() - 1)])
		_duel.grid[c][0] = load(path)
		_duel.grid_elem[c][0] = "none"
		_duel.reel_system._set_grid_src(c, 0, src if c < 2 else "")
	_duel.reel_system.reel_stopped = [true, true, false]


# C1：火焰武器配装——候选火斩应按真实来源（fire_sword/fire）命中 W01，而非误报 W06。
func _test_fire_loadout() -> void:
	_setup_case([FIRE_SWORD, IRON_SWORD], [], [SY_BLADE, SY_BURN, SY_BLADE], "iron_sword")
	var rows: Array[Dictionary] = _duel._combo_preview_rows()
	var row: Dictionary = _find_candidate(rows, SY_FIRE)
	var ids := _matched_ids(row)
	print("  C1 ids=%s" % str(ids))
	_check(ids.has("W01"), "C1 火焰配装：候选火斩命中 W01（实测 %s）" % str(ids))
	_check(not ids.has("W06"), "C1 火焰配装：候选火斩不误报 W06（实测 %s）" % str(ids))


# C2：技能符号候选——守备应判为 source_kind=skill / skill_role=shield，命中 T02。
func _test_skill_candidate() -> void:
	_setup_case([IRON_SWORD], [GUARD_SKILL], [SY_BLADE, SY_BURN, SY_BLADE], "iron_sword")
	var rows: Array[Dictionary] = _duel._combo_preview_rows()
	var row: Dictionary = _find_candidate(rows, SY_GUARD)
	var ids := _matched_ids(row)
	print("  C2 ids=%s" % str(ids))
	_check(ids.has("T02"), "C2 技能候选：守备（skill/shield）命中 T02（实测 %s）" % str(ids))


# C5：候选去重——同一符号来自两把武器时只出一行。
func _test_candidate_dedupe() -> void:
	_setup_case([DAGGER, DUELING_SABER], [], [SY_BLADE, SY_BURN, SY_BLADE], "iron_sword")
	var rows: Array[Dictionary] = _duel._combo_preview_rows()
	var n := 0
	for r in rows:
		if String(r.get("candidate", "")) == SY_DAGGER_SLASH:
			n += 1
	_check(n == 1, "C5 同一符号来自两把武器只出一行（dagger_slash 行数=%d）" % n)
	# 池级去重：候选元数据列表里同一 path 只出现一次。
	var seen := {}
	var dup := ""
	for c in _duel._pool_symbol_candidates():
		var path := String(c.get("path", ""))
		if seen.has(path):
			dup = path
		seen[path] = true
	_check(dup == "", "C5 候选元数据按 path 去重（重复=%s / 共 %d 条）" % [dup, seen.size()])


# D2：面板「第三格预览」区段
func _test_panel() -> void:
	var rows: Array[Dictionary] = [
		{"id": "W07", "name": "强化燃刃", "group": "main", "priority": 20,
			"unlocked": true, "matched_now": false, "condition_text": "火焰×2", "contribution_text": ""},
	]
	var preview: Array[Dictionary] = _preview([_card(SY_BLADE), _card(SY_BURN)],
		[_candidate_card(SY_FIRE, "none", "iron_sword"), _candidate_card(SY_GUARD, "none", "")])
	_panel.open(rows, [], preview)
	_check(_panel.rendered_texts.has("第三格预览"), "给 preview_rows 时出现「第三格预览」区段")
	_check(_panel.rendered_preview_texts.size() == preview.size(),
		"预览区行数 == 候选数（%d/%d）" % [_panel.rendered_preview_texts.size(), preview.size()])
	var fire_txt := ""
	var guard_txt := ""
	for t in _panel.rendered_preview_texts:
		if t.begins_with("火斩："):
			fire_txt = t
		if t.begins_with("守备："):
			guard_txt = t
	_check(fire_txt.begins_with("火斩：") and fire_txt.contains("强化燃刃"),
		"火斩行含命中组合名（实测 %s）" % fire_txt)
	_check(guard_txt.ends_with("无组合"), "守备行显示「无组合」（实测 %s）" % guard_txt)
	_panel.close()

	_panel.open(rows)
	_check(not _panel.rendered_texts.has("第三格预览"), "不给 preview_rows 时不出现「第三格预览」")
	_check(_panel.rendered_preview_texts.is_empty(), "不给 preview_rows 时预览行数为 0")
	_panel.close()


# C3：真实入口接线（前两列已停 → 预览；未锁两格 → 不显示）
func _test_wiring() -> void:
	_duel.selected_loadout.clear()
	_duel.selected_loadout.append(IRON_SWORD)
	_duel.selected_loadout.append(DAGGER)
	_duel._build_pool(_duel.selected_loadout)
	_duel._sync_pattern_source_meta()
	_duel.frozen_cols.clear()
	for c in 3:
		var sym := SY_BLADE if c == 0 else (SY_BURN if c == 1 else SY_GUARD)
		_duel.grid[c][0] = load(sym)
		_duel.grid_elem[c][0] = "none"
		_duel.reel_system._set_grid_src(c, 0, "iron_sword")
	_duel._enter_interroom(false)
	await get_tree().process_frame

	# 未锁两格：第三列为开放列 → 不显示预览区
	_duel.reel_system.reel_stopped = [true, false, false]
	_duel.hud.interroom_combo_btn.pressed.emit()
	await get_tree().process_frame
	_check(not _duel.hud.combo_panel.rendered_texts.has("第三格预览"),
		"未锁两格时面板不显示「第三格预览」")
	_duel.hud.combo_panel.close()

	# 已锁两格：前两列已停 → 第三列候选预览
	_duel.reel_system.reel_stopped = [true, true, false]
	var expect := _duel._preview_candidate_cards()
	_duel.hud.interroom_combo_btn.pressed.emit()
	await get_tree().process_frame
	_check(_duel.hud.combo_panel.rendered_texts.has("第三格预览"),
		"已锁两格时面板出现「第三格预览」")
	_check(_duel.hud.combo_panel.rendered_preview_texts.size() == expect.size(),
		"接线预览行数 == 当前池候选数（%d/%d）" % [
			_duel.hud.combo_panel.rendered_preview_texts.size(), expect.size()])
	_duel.hud.combo_panel.close()
