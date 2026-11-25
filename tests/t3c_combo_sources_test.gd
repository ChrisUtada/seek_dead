extends Node

# ============================================================================
# T3-3 C 轮第 3 步：组合面板「本轮来源」分解验收
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t3c_combo_sources_test.tscn
# 覆盖：
#   D1 假 acc：build_sources 行数 / label / value；source_dmg 与 dmg_by_elem 求和不变；
#      空 acc 返回空；build_sources 不修改传入 last_acc。
#   D2 真实 evaluate 的 last_settlement_acc：非空且所有 value >= 0。
#   D3 面板：给 sources 时出现「本轮来源」区段且行数一致；不给时不出现。
# ============================================================================

const PANEL_SCENE := "res://scenes/ui/combo_panel.tscn"
const IRON_SWORD := "res://resources/weapon_templates/iron_sword.tres"
const DAGGER := "res://resources/weapon_templates/dagger.tres"
const SY_BLADE := "res://resources/symbols/iron_slash.tres"
const SY_BURN := "res://resources/symbols/burn.tres"
const SY_FIRE := "res://resources/symbols/fire_slash.tres"

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

	_test_fake_acc()
	_test_panel_render()
	await _test_real_evaluate()

	print("T3CSRC|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _find_label(rows: Array[Dictionary], label: String) -> Dictionary:
	for r in rows:
		if String(r.get("label", "")) == label:
			return r
	return {}


func _sum_values(d: Dictionary) -> float:
	var s := 0.0
	for k in d:
		s += float(d[k])
	return s


# D1：假 acc 契约
func _test_fake_acc() -> void:
	var acc := {
		"source_dmg": {"iron_sword": 12.0, "burn": 8.0},
		"dmg_by_elem": {"none": 12.0, "fire": 8.0},
		"pattern_status": {"burn": 1},
	}
	var before: Dictionary = acc.duplicate(true)
	var rows: Array[Dictionary] = ComboCatalog.build_sources(acc)

	_check(rows.size() == 3, "假 acc 产出 3 行（2 伤害 + 1 状态，实测 %d）" % rows.size())
	var dmg_row: Dictionary = _find_label(rows, "iron_sword")
	_check(String(dmg_row.get("kind", "")) == "damage", "iron_sword 行 kind=damage")
	_check(int(dmg_row.get("value", -1)) == 12, "iron_sword value=12（实测 %s）" % str(dmg_row.get("value", null)))
	var burn_dmg: Dictionary = _find_label(rows, "burn")
	_check(String(burn_dmg.get("kind", "")) == "damage" and int(burn_dmg.get("value", -1)) == 8,
		"burn 伤害行 value=8（实测 %s）" % str(burn_dmg.get("value", null)))
	var st: Dictionary = _find_label(rows, "燃烧")
	_check(String(st.get("kind", "")) == "status" and int(st.get("value", -1)) == 1,
		"pattern_status burn → 燃烧 +1 层（实测 %s/%s）" % [String(st.get("label", "")), str(st.get("value", null))])

	# 不变量：source_dmg 与 dmg_by_elem 在 _apply 里同源累加，求和一致
	var s_src: float = _sum_values(acc["source_dmg"])
	var s_elem: float = _sum_values(acc["dmg_by_elem"])
	_check(is_equal_approx(s_src, s_elem), "sum(source_dmg)=%s == sum(dmg_by_elem)=%s" % [str(s_src), str(s_elem)])

	# 空 acc → 空数组（不产生 "0 伤害" 噪声行）
	var empty_rows: Array[Dictionary] = ComboCatalog.build_sources({})
	_check(empty_rows.is_empty(), "空 acc 返回空数组（实测 %d）" % empty_rows.size())

	# 只读：不修改传入 last_acc
	ComboCatalog.build_sources(acc)
	_check(acc == before, "build_sources 不修改传入 last_acc")


# D3：面板渲染「本轮来源」区段
func _test_panel_render() -> void:
	var rows: Array[Dictionary] = [
		{"id": "W07", "name": "强化燃刃", "group": "main", "priority": 20,
			"unlocked": true, "matched_now": true, "condition_text": "火焰×2", "contribution_text": ""},
	]
	var sources: Array[Dictionary] = ComboCatalog.build_sources({
		"source_dmg": {"iron_sword": 12.0},
		"pattern_status": {"burn": 1},
	})
	var seed0: int = _duel._reward_system._loot.seed_value()
	var hp0: int = int(_duel.enemy_hp)
	var charge0: int = int(_duel.charge_points)
	var turn0: int = int(_duel.turn_count)
	_panel.open(rows, sources)
	_check(_panel.rendered_texts.has("本轮来源"), "给 sources 时出现「本轮来源」区段")
	_check(_panel.rendered_source_texts.size() == sources.size(),
		"来源区行数 == sources 行数（%d/%d）" % [_panel.rendered_source_texts.size(), sources.size()])
	_check(not _panel.rendered_source_texts.is_empty() and _panel.rendered_source_texts[0].contains("iron_sword")
		and _panel.rendered_source_texts[0].contains("12"),
		"首行包含标签与数值（实测 %s）" % (_panel.rendered_source_texts[0] if not _panel.rendered_source_texts.is_empty() else "<empty>"))
	_check(_duel._reward_system._loot.seed_value() == seed0, "打开来源面板不消耗 RNG（seed %d）" % seed0)
	_check(int(_duel.enemy_hp) == hp0, "打开来源面板不改 enemy_hp（%d）" % hp0)
	_check(int(_duel.charge_points) == charge0, "打开来源面板不改 charge_points（%d）" % charge0)
	_check(int(_duel.turn_count) == turn0, "打开来源面板不推进回合（turn %d）" % turn0)
	_panel.close()

	_panel.open(rows)
	_check(not _panel.rendered_texts.has("本轮来源"), "不给 sources 时不出现「本轮来源」区段")
	_check(_panel.rendered_source_texts.is_empty(), "不给 sources 时来源行数为 0")
	_panel.close()


# D2：真实 evaluate 快照
func _test_real_evaluate() -> void:
	_duel.selected_loadout.clear()
	_duel.selected_loadout.append(IRON_SWORD)
	_duel.selected_loadout.append(DAGGER)
	_duel._build_pool(_duel.selected_loadout)
	_duel._sync_pattern_source_meta()
	_duel.frozen_cols.clear()
	var syms: Array = [SY_BLADE, SY_BURN, SY_FIRE]
	for rr in 3:
		_duel.grid[rr][0] = load(String(syms[rr]))
		_duel.grid_elem[rr][0] = "none"
		_duel.reel_system._set_grid_src(rr, 0, "iron_sword")
	_duel.enemy_hp = 3000
	_duel.enemy_hp_max = 3000
	_duel.enemy_armor = 10
	_duel.enemy_status.clear()
	_duel.player_hp = _duel.player_hp_max
	_duel.player_shield = 0
	_duel.charge_points = 0
	_duel.turn_count += 1
	_duel.enemy_intent.clear()
	seed(12345)
	await _duel.combat.evaluate()

	var acc: Dictionary = _duel.last_settlement_acc
	var rows: Array[Dictionary] = ComboCatalog.build_sources(acc)
	_check(not rows.is_empty(), "真实 evaluate 快照产出非空来源（实测 %d 行）" % rows.size())
	var all_non_negative := true
	var kinds := {}
	for r in rows:
		if int(r.get("value", 0)) < 0:
			all_non_negative = false
		kinds[String(r.get("kind", ""))] = true
	_check(all_non_negative, "真实来源所有 value >= 0")
	_check(kinds.has("damage") and kinds.has("status") and kinds.has("pattern"),
		"真实来源覆盖 damage/status/pattern（实测 %s）" % str(kinds.keys()))
	_check(_find_label(rows, "强化燃刃").size() > 0, "真实来源含牌谱「强化燃刃」行")
