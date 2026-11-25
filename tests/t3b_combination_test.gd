extends Node

# ============================================================================
# T3-3B C1：首个主组合「强化燃刃」W07 单变量验收（T1–T8）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t3b_combination_test.tscn
# 口径：结构断言 + 同 Build A/B 对照，不做平衡结论；不启动完整战斗（直调 _apply_patterns）。
# ============================================================================

const IRON_SWORD := "res://resources/weapon_templates/iron_sword.tres"
const SY_BLADE := "res://resources/symbols/iron_slash.tres"
const SY_FLAME_A := "res://resources/symbols/burn.tres"
const SY_FLAME_B := "res://resources/symbols/fire_slash.tres"
const SY_GUARD := "res://resources/symbols/guard.tres"
const SY_FROST := "res://resources/symbols/frost.tres"

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
	_duel.reel_system._timer.stop()
	await _run()
	print("T3BCOM|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


# 设置 3 格（sym 路径数组），来源统一用 iron_sword，再跑 _apply_patterns
func _apply(syms: Array, with_sword: bool = true) -> Dictionary:
	_duel.selected_loadout.clear()
	if with_sword:
		_duel.selected_loadout.append(IRON_SWORD)
		_duel.selected_loadout.append("res://resources/weapon_templates/dagger.tres")
	else:
		_duel.selected_loadout.append("res://resources/weapon_templates/dagger.tres")
		_duel.selected_loadout.append("res://resources/weapon_templates/short_sword.tres")
	_duel._build_pool(_duel.selected_loadout)
	_duel._sync_pattern_source_meta()
	_duel.frozen_cols.clear()
	for r in 3:
		_duel.grid[r][0] = load(String(syms[r]))
		_duel.grid_elem[r][0] = "none"
		_duel.reel_system._set_grid_src(r, 0, "iron_sword" if with_sword else "dagger")
	var acc: Dictionary = _duel.combat._new_acc()
	_duel.combat._reset_turn_state()
	acc["counts"] = _duel.combat._phase_symbols(acc)
	_duel.combat._apply_patterns(acc)
	return acc


# 只跑牌谱层（不跑 _phase_symbols，避免其 RNG/洗牌干扰 A/B 对照）
func _apply_patterns_only(syms: Array) -> Dictionary:
	var acc: Dictionary = _duel.combat._new_acc()
	_duel.combat._reset_turn_state()
	_duel.combat._apply_patterns(acc)
	return acc


func _burn(acc: Dictionary) -> int:
	var ps: Dictionary = acc.get("pattern_status", {})
	return int(ps.get("burn", 0))


func _w(acc: Dictionary) -> String:
	return String(acc.get("pattern_weapon", ""))


func _run() -> void:
	# T1 正触发：iron_sword + blade + flame + flame
	var a: Dictionary = _apply([SY_BLADE, SY_FLAME_A, SY_FLAME_B])
	_check(_w(a) == "W07", "T1 W07 命中（实测 %s）" % _w(a))
	_check(_burn(a) == 1, "T1 pattern_status.burn == 1（实测 %d）" % _burn(a))

	# T2 顺序等价：三种排列结果一致
	var b: Dictionary = _apply([SY_FLAME_A, SY_BLADE, SY_FLAME_B])
	var c: Dictionary = _apply([SY_FLAME_B, SY_FLAME_A, SY_BLADE])
	_check(_w(b) == "W07" and _w(c) == "W07", "T2 三种排列都命中 W07")
	_check(_burn(b) == 1 and _burn(c) == 1, "T2 三种排列 burn 层数一致（1/1/1）")

	# T3 反向
	var r1: Dictionary = _apply([SY_BLADE, SY_FLAME_A, SY_FROST])
	_check(_w(r1) != "W07", "T3 blade+flame×1+其他 不触发（实测 %s）" % _w(r1))
	var r2b: Dictionary = _apply([SY_FLAME_A, SY_FLAME_B, "res://resources/symbols/flame_special.tres"])
	_check(_w(r2b) != "W07", "T3 flame×3 无 blade 不触发（实测 %s）" % _w(r2b))
	var r3: Dictionary = _apply([SY_BLADE, SY_BLADE, SY_FLAME_A])
	_check(_w(r3) != "W07", "T3 blade×2+flame×1 不触发（实测 %s）" % _w(r3))
	var r4: Dictionary = _apply([SY_BLADE, SY_FLAME_A, SY_FLAME_B], false)
	_check(_w(r4) != "W07", "T3 未装备 iron_sword 不触发（实测 %s）" % _w(r4))
	# T4 每 SPIN 上限：resolve_equipment 只返回一条；W07(20) > W01(10)
	# 先把 loadout 恢复成含 iron_sword，确保 W07 在解锁集中
	_duel.selected_loadout.clear()
	_duel.selected_loadout.append(IRON_SWORD)
	_duel.selected_loadout.append("res://resources/weapon_templates/dagger.tres")
	var w_pool: Array = _duel._pattern_system.by_track("weapon_attack")
	var unlocked: Array = _duel._pattern_system.unlocked_patterns(_duel.selected_loadout.duplicate(), _duel._pattern_tag_of)
	var cards: Array = []
	for rr in 3:
		cards.append({
			"sym": load(String([SY_BLADE, SY_FLAME_A, SY_FLAME_B][rr])),
			"element": "fire", "source_kind": "weapon", "source_element": "fire", "skill_role": "",
		})
	var hits: Array = PATTERN_LIB.match_rules(cards, w_pool)
	_check(hits.size() >= 2, "T4 W01 与 W07 同时命中（实测 %d 条）" % hits.size())
	var pick = _duel._pattern_system.resolve_equipment(hits, unlocked)
	_check(pick != null and String(pick.id) == "W07", "T4 resolve_equipment 只返回 W07（实测 %s）" % (String(pick.id) if pick != null else "null"))
	_check(_burn(a) == 1, "T4 只结算一条，burn 不叠加（实测 %d）" % _burn(a))

	# T5 主辅不双算：技能 T02 + W07 同回合，各自一次，burn 不重复
	_duel.selected_skills.clear()
	_duel.selected_skills.append("res://resources/skills/guard.tres")
	var t5: Dictionary = _apply([SY_BLADE, SY_FLAME_A, SY_FLAME_B])
	_check(String(t5.get("pattern_weapon", "")) == "W07", "T5 W07 命中")
	_check(_burn(t5) == 1, "T5 burn 只 +1，不因 T02 重复（实测 %d）" % _burn(t5))
	_check(String(t5.get("pattern_skill", "")) == "T02" or String(t5.get("pattern_skill", "")) == "",
		"T5 技能轨独立裁决（实测 %s）" % String(t5.get("pattern_skill", "")))

	# T6 RNG：结算前后战利品 seed 不变
	var seed_before: int = _duel._reward_system._loot.seed_value()
	var _t6: Dictionary = _apply([SY_BLADE, SY_FLAME_A, SY_FLAME_B])
	_check(_duel._reward_system._loot.seed_value() == seed_before, "T6 战利品 RNG seed 不变（%d）" % seed_before)

	# T7 基础口径不变：三连/破甲/护甲消耗（结构断言，本轮不改这些路径）
	_duel.enemy_armor = 10
	var _before_armor: int = _duel.enemy_armor
	var dmg_pierce: float = _duel.combat.apply_enemy_damage(7, false)
	_check(dmg_pierce == 7.0 and _duel.enemy_armor == _before_armor - 7,
		"T7 铁剑破甲口径不变（护甲 %d→%d）" % [_before_armor, _duel.enemy_armor])

	# T8 A/B：对照组不注册 W07，实验组注册 W07；同落线同种子
	var ps_orig = _duel._pattern_system
	var ps_ctrl = preload("res://scripts/battle/pattern_system.gd").new()
	for p in ps_orig.all_patterns():
		if String(p.id) != "W07":
			ps_ctrl.register(p)
	_duel._pattern_system = ps_ctrl
	var seed_ab: int = _duel._reward_system._loot.seed_value()
	var ctrl: Dictionary = _apply_patterns_only([SY_BLADE, SY_FLAME_A, SY_FLAME_B])
	_duel._pattern_system = ps_orig
	_duel._reward_system._loot.reset_run(seed_ab)
	var exp: Dictionary = _apply_patterns_only([SY_BLADE, SY_FLAME_A, SY_FLAME_B])
	var keys: Array = ["dmg", "shield", "heal", "charge_points", "triple", "pattern_skill"]
	var same := true
	var diff_txt: Array[String] = []
	for k in keys:
		if str(ctrl.get(k)) != str(exp.get(k)):
			same = false
			diff_txt.append("%s: %s→%s" % [k, str(ctrl.get(k)), str(exp.get(k))])
	_check(same, "T8 A/B 伤害/护盾/治疗/充能/三连完全一致（差异 %s）" % str(diff_txt))
	_check(_burn(ctrl) == 0 and _burn(exp) == 1,
		"T8 实验组仅多 1 层燃烧（A=%d B=%d）" % [_burn(ctrl), _burn(exp)])
	var banners_b: Array = exp.get("pending_banners", []) as Array
	_check(banners_b.size() == 1 and String((banners_b[0] as Dictionary).get("text", "")).contains("强化燃刃"),
		"T8 实验组说明行恰为 W07 一条（实测 %d 条，%s）" % [banners_b.size(), str(banners_b)])
	# A/B 差值表打印供回报
	Debug.log("T3BCOM|BANNERS A=%s B=%s" % [str(ctrl.get("pending_banners", [])), str(exp.get("pending_banners", []))])
	Debug.log("T3BCOM|AB dmg=%s→%s armor=%s→%s charge=%s→%s burn=%d→%d lines=%d→%d" % [
		str(ctrl.get("dmg")), str(exp.get("dmg")),
		str(_duel.enemy_armor), str(_duel.enemy_armor),
		str(ctrl.get("charge_points")), str(exp.get("charge_points")),
		_burn(ctrl), _burn(exp), (ctrl.get("pending_banners", []) as Array).size(), banners_b.size()])


const PATTERN_LIB = preload("res://scripts/battle/pattern_matcher.gd")
