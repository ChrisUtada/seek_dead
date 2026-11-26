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
	for rr in 3:
		_duel.grid[rr][0] = load(String(syms[rr]))
		_duel.grid_elem[rr][0] = "none"
		_duel.reel_system._set_grid_src(rr, 0, "iron_sword")
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

	# T8 A/B（无竞争落线）：iron_slash + burn + burn；对照组不注册 W07，实验组注册 W07。
	# burn+burn 不满足 W06（需要两张 damage），也不满足 W01（需要 damage/fire），
	# 因此对照组应零 equipment 牌谱命中，W07 是唯一变量。
	var ps_orig = _duel._pattern_system
	var ps_ctrl = preload("res://scripts/battle/pattern_system.gd").new()
	for p in ps_orig.all_patterns():
		if String(p.id) != "W07":
			ps_ctrl.register(p)
	var ab_syms: Array = [SY_BLADE, SY_FLAME_A, SY_FLAME_A]
	var seed_ab: int = _duel._reward_system._loot.seed_value()
	_duel._pattern_system = ps_ctrl
	var ctrl: Dictionary = _apply_patterns_only(ab_syms)
	_duel._pattern_system = ps_orig
	_duel._reward_system._loot.reset_run(seed_ab)
	var exp: Dictionary = _apply_patterns_only(ab_syms)
	# A2 无竞争前提：对照组零命中、实验组 W07 命中（必须显式断言）
	_check(String(ctrl.get("pattern_weapon", "")) == "",
		"T8 对照组无 equipment 牌谱命中（pattern_weapon=%s）" % String(ctrl.get("pattern_weapon", "")))
	_check(String(exp.get("pattern_weapon", "")) == "W07",
		"T8 实验组命中 W07（pattern_weapon=%s）" % String(exp.get("pattern_weapon", "")))
	# A3 burn +1，其余字段相同
	_check(_burn(exp) == _burn(ctrl) + 1,
		"T8 实验组 burn == 对照组 +1（A=%d B=%d）" % [_burn(ctrl), _burn(exp)])
	# T8 清理：armor/charge 曾作为「从上个用例继承的值」出现在比较里，不具判别力。
	# 现在比较字段只保留牌谱层真实写入的键；真实 enemy_armor / charge_points 在 T9 全量对照里验证。
	_duel.enemy_armor = 10
	_duel.charge_points = 0
	var keys: Array = ["dmg", "shield", "heal", "triple", "pattern_skill"]
	var same := true
	var diff_txt: Array[String] = []
	for k in keys:
		if str(ctrl.get(k)) != str(exp.get(k)):
			same = false
			diff_txt.append("%s: %s→%s" % [k, str(ctrl.get(k)), str(exp.get(k))])
	_check(same, "T8 牌谱层字段（dmg/shield/heal/triple/skill）相同（差异 %s）" % str(diff_txt))
	var banners_b: Array = exp.get("pending_banners", []) as Array
	_check(banners_b.size() == 1 and String((banners_b[0] as Dictionary).get("text", "")).contains("强化燃刃"),
		"T8 实验组说明行恰为 W07 一条（实测 %d 条）" % banners_b.size())
	Debug.log("T3BCOM|AB burn+burn: pattern_weapon A=%s B=%s dmg=%s→%s burn=%d→%d banners A=%d B=%d" % [
		String(ctrl.get("pattern_weapon", "")), String(exp.get("pattern_weapon", "")),
		str(ctrl.get("dmg")), str(exp.get("dmg")),
		_burn(ctrl), _burn(exp), (ctrl.get("pending_banners", []) as Array).size(), banners_b.size()])

	await _t9_full_settle(ps_orig, ps_ctrl, seed_ab)
	_guard_w07_beats_w06(ps_orig)
	_guard_unlock_paths(ps_orig)


# B1：W07 与 W06 同时满足的落线（iron_slash + burn + fire_slash，来源全 iron_sword）：
# resolve_equipment 必须选 W07，且 W06 不生效（§5 设计后果的回归锁）。
func _guard_w07_beats_w06(ps) -> void:
	_duel._pattern_system = ps
	_duel.selected_loadout.clear()
	_duel.selected_loadout.append(IRON_SWORD)
	_duel.selected_loadout.append("res://resources/weapon_templates/dagger.tres")
	_duel._build_pool(_duel.selected_loadout)
	_duel._sync_pattern_source_meta()
	var syms: Array = [SY_BLADE, SY_FLAME_A, SY_FLAME_B]
	var acc: Dictionary = _apply_patterns_only(syms)
	_check(String(acc.get("pattern_weapon", "")) == "W07",
		"B1 W07/W06 同层时选中 W07（实测 %s）" % String(acc.get("pattern_weapon", "")))
	# W06 的 effect_params.damage_mult=1.2 不得出现：其专属说明行不存在
	var w06_line := false
	for ln in (acc.get("lines", []) as Array):
		if String(ln).contains("无锋磨砺") or String(ln).contains("+20%"):
			w06_line = true
	_check(not w06_line, "B1 W06 未生效（无其说明行）")


# B2：未装备 iron_sword 时即使三符号类别凑齐，W07 也不命中（unlock_paths 生效）
func _guard_unlock_paths(ps) -> void:
	_duel._pattern_system = ps
	var a: Dictionary = _apply([SY_BLADE, SY_FLAME_A, SY_FLAME_B], false)
	_check(not _duel.selected_loadout.has(IRON_SWORD), "B2 配装确实不含 iron_sword")
	_check(String(a.get("pattern_weapon", "")) != "W07",
		"B2 未装备 iron_sword 时 W07 不命中（实测 %s）" % String(a.get("pattern_weapon", "")))


# T9：同种子、同落线，各跑一次完整 evaluate()；比较终态，唯一差异应为敌人 burn +1。
func _t9_full_settle(ps_orig, ps_ctrl, seed_ab: int) -> void:
	var syms: Array = [SY_BLADE, SY_FLAME_A, SY_FLAME_A]
	var setup := func() -> void:
		seed(12345)   # 全局 RNG 与 loot RNG 都固定，保证两次 evaluate 的落线/洗牌同序列
		_duel.selected_loadout.clear()
		_duel.selected_loadout.append(IRON_SWORD)
		_duel.selected_loadout.append("res://resources/weapon_templates/dagger.tres")
		_duel._build_pool(_duel.selected_loadout)
		_duel._sync_pattern_source_meta()
		_duel.frozen_cols.clear()
		for rr in 3:
			_duel.grid[rr][0] = load(String(syms[rr]))
			_duel.grid_elem[rr][0] = "none"
			_duel.reel_system._set_grid_src(rr, 0, "iron_sword")
		_duel.enemy_hp = 300
		_duel.enemy_hp_max = 300
		_duel.enemy_armor = 10
		_duel.enemy_status.clear()
		_duel.player_hp = _duel.player_hp_max
		_duel.player_shield = 0
		_duel.charge_points = 0
		_duel.turn_count = 1
		_duel.enemy_intent.clear()
		_duel._reward_system._loot.reset_run(seed_ab)

	setup.call()
	_duel._pattern_system = ps_ctrl
	var seed_a0: int = _duel._reward_system._loot.seed_value()
	await _duel.combat.evaluate()
	var a := {
		"hp": _duel.enemy_hp, "armor": _duel.enemy_armor, "charge": _duel.charge_points,
		"shield": _duel.player_shield, "heal": _duel.player_hp,
		"burn": int(_duel.enemy_status.get("burn", 0)),
	}
	var seed_a1: int = _duel._reward_system._loot.seed_value()

	setup.call()
	_duel._pattern_system = ps_orig
	var seed_b0: int = _duel._reward_system._loot.seed_value()
	await _duel.combat.evaluate()
	var b := {
		"hp": _duel.enemy_hp, "armor": _duel.enemy_armor, "charge": _duel.charge_points,
		"shield": _duel.player_shield, "heal": _duel.player_hp,
		"burn": int(_duel.enemy_status.get("burn", 0)),
	}
	var seed_b1: int = _duel._reward_system._loot.seed_value()

	_check(seed_a0 == seed_a1 and seed_b0 == seed_b1 and seed_a0 == seed_b0,
		"T9 战利品 RNG seed 前后一致（A %d→%d，B %d→%d）" % [seed_a0, seed_a1, seed_b0, seed_b1])
	var keys: Array = ["hp", "armor", "charge", "shield", "heal"]
	var diffs: Array[String] = []
	for k in keys:
		if str(a[k]) != str(b[k]):
			diffs.append("%s: %s→%s" % [k, str(a[k]), str(b[k])])
	_check(diffs.is_empty(), "T9 全量结算除燃烧外零差异（差异 %s）" % str(diffs))
	_check(int(b["burn"]) == int(a["burn"]) + 1,
		"T9 实验组敌人 burn == 对照组 +1（A=%d B=%d）" % [int(a["burn"]), int(b["burn"])])
	Debug.log("T3BCOM|T9 hp=%s→%s armor=%s→%s charge=%s→%s shield=%s→%s hp_player=%s→%s burn=%d→%d seed=%d" % [
		str(a["hp"]), str(b["hp"]), str(a["armor"]), str(b["armor"]),
		str(a["charge"]), str(b["charge"]), str(a["shield"]), str(b["shield"]),
		str(a["heal"]), str(b["heal"]), int(a["burn"]), int(b["burn"]), seed_a0])


const PATTERN_LIB = preload("res://scripts/battle/pattern_matcher.gd")
