extends Node

# ============================================================================
# Step 5 · BOSS 节奏补强 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/boss_rhythm_test.tscn
#
# 覆盖：
# ① 13 个 BOSS 的脚本 / 幕 / 机制摘要齐全，摘要写明真实恢复窗与应对；
# ② 每个 BOSS 至少一个「高压 → 恢复」窗口：恢复窗口为真、标题不是通用占位；
# ③ 四元组与替换：呓语锁轮由呓语教徒/迷宫低语者共享但 P2 行为不同；
# ④ 勇者的阴影：投影生效、P3 血锁不可绕过、三条和解路径各自通关；
# ⑤ 除勇者的阴影 P3 外无锁血。
# ============================================================================

const EXPECTED := {
	"冰封铁瓮": ["rust_armor_gimmick", 1, "熔铸间隙", "破甲"],
	"碎裂石像鬼": ["glass_cannon_gimmick", 1, "石翼展开", "展开"],
	"酸蚀恶鬼": ["acid_bomb_gimmick", 1, "毒囊暴露", "不挂毒"],
	"茧居石雕": ["cocoon_cycle_gimmick", 1, "茧壳开合", "甲0"],
	"呓语教徒": ["whisper_lock_gimmick", 2, "锁轮间隙", "不追加"],
	"迷宫低语者": ["whisper_lock_gimmick", 2, "锁轮间隙", "乱权"],
	"躁怒元素使": ["bipolar_phase_gimmick", 2, "情绪低垂", "不注废"],
	"天平审判官": ["compulsion_rule_gimmick", 2, "律法间隙", "不宣告新律法"],
	"无名虚空": ["emotional_vacuum_gimmick", 2, "麻木静默", "不注废"],
	"深渊监视者": ["abyss_erosion_gimmick", 3, "深渊喘息", "不追加注废"],
	"碎裂魔王": ["split_ego_gimmick", 3, "人格僵直", "不叠甲"],
	"耻辱审判官": ["shame_counter_gimmick", 3, "审判间隙", "不剥盾"],
	"勇者的阴影": ["shadow_projection_gimmick", 3, "", "和解"],
}

const HEAL := "res://resources/symbols/heal.tres"
const DAMAGE_A := "res://resources/symbols/fire_slash.tres"
const DAMAGE_B := "res://resources/symbols/bolt_shot.tres"
const DAMAGE_C := "res://resources/symbols/iron_slash.tres"

var _checks := 0
var _fails := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	var duel: DuelController = await _boot()
	if duel == null:
		print("RESULT FAIL (boot)")
		get_tree().quit(2)
		return

	_check(EXPECTED.size() == 13, "样本表覆盖全部 13 个 BOSS")
	for nm in EXPECTED:
		var exp: Array = EXPECTED[nm]
		var r := _room_by_name(duel, nm)
		_check(r != null, "找到 BOSS %s" % nm)
		if r == null:
			continue
		_check(String(r.kind) == "boss" and int(r.act) == int(exp[1]),
			"%s 是 ACT%d BOSS" % [nm, int(exp[1])])
		var sn: String = r.gimmick_script.resource_path.get_file().get_basename() if r.gimmick_script != null else ""
		_check(sn == String(exp[0]), "%s 使用 %s（实测 %s）" % [nm, exp[0], sn])
		_check(not r.gimmick_params.is_empty(), "%s 参数非空" % nm)
		_check(String(r.mechanic_summary) != "", "%s 有真实机制摘要" % nm)
		_check(String(r.mechanic_summary).contains(String(exp[3])),
			"%s 摘要写明关键窗口/应对「%s」" % [nm, exp[3]])
		_start_room(duel, r)
		var g = duel.current_gimmick
		_check(g != null, "%s 实例化机制" % nm)
		if g == null:
			continue
		if nm == "勇者的阴影":
			_shadow_checks(duel, g)
		else:
			_check(int(g.hp_floor(duel)) == -1, "%s 无锁血下限" % nm)
			_recovery_check(duel, g, nm, String(exp[2]))

	_test_whisper_differentiation(duel)
	_test_act_pools(duel)

	SaveSystem.reset_lobby_data()
	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


# ---------------------------------------------------------------------------
# 每个 BOSS 的「高压 → 恢复」真实窗口
# ---------------------------------------------------------------------------

func _recovery_check(duel: DuelController, g, nm: String, title: String) -> void:
	match nm:
		"冰封铁瓮":
			g.on_turn_begin(duel)
			_check(String(g.rhythm_window(duel)) == "爆发", "冰封铁瓮：第2回合爆发")
			g.on_turn_begin(duel)
			_check(String(g.rhythm_window(duel)) == "恢复", "冰封铁瓮：爆发后次回合恢复")
		"碎裂石像鬼":
			duel.player_hp = 1000
			duel.player_hp_max = 1000
			duel.player_shield = 0
			g.on_damaged(duel, 20)
			var hp_after: int = int(duel.player_hp)
			_check(hp_after < 1000, "碎裂石像鬼：受击反弹落地（-%d）" % (1000 - hp_after))
			g.on_turn_begin(duel)
			_check(g.recovery_window(duel), "碎裂石像鬼：反弹后次回合石翼展开")
			g.on_damaged(duel, 20)
			_check(int(duel.player_hp) == hp_after, "碎裂石像鬼：展开回合不再反弹")
		"酸蚀恶鬼":
			duel.player_hp = 1000
			duel.player_hp_max = 1000
			duel.player_shield = 0
			duel.player_status = {"poison": 10}
			g.on_turn_begin(duel)
			_check(g.recovery_window(duel), "酸蚀恶鬼：10层爆炸后毒囊暴露")
			_check(int(duel.player_status.get("poison", 0)) == 0, "酸蚀恶鬼：爆炸清零毒层")
			g.on_turn_begin(duel)
			_check(int(duel.player_status.get("poison", 0)) == 0, "酸蚀恶鬼：暴露回合停止挂毒")
			g.on_turn_begin(duel)
			_check(int(duel.player_status.get("poison", 0)) > 0, "酸蚀恶鬼：暴露结束恢复挂毒")
		"茧居石雕":
			for i in 3:
				g.on_turn_begin(duel)
			_check(g.recovery_window(duel), "茧居石雕：第4回合开合窗口")
			_check(int(duel.enemy_armor) == 0, "茧居石雕：开合甲归零")
			_check(String(duel.enemy_intent.get("type", "")) == "heavy", "茧居石雕：开合强制重击")
		"呓语教徒":
			g.on_turn_begin(duel)
			_check(int(duel.pending_lock_reel) >= 0, "呓语教徒：第2回合先锁1列（D6 与迷宫错位）")
			duel.pending_lock_reel = -1   # 模拟真实 spin 结束清空
			g.on_turn_begin(duel)
			_check(g.recovery_window(duel), "呓语教徒：锁轮后次回合恢复")
			_check(int(duel.pending_lock_reel) == -1, "呓语教徒：恢复回合不追加锁轮")
		"迷宫低语者":
			for i in 2:
				g.on_turn_begin(duel)
			_check(int(duel.pending_lock_reel) >= 0, "迷宫低语者：每3回合锁1列")
			g.on_turn_begin(duel)
			_check(g.recovery_window(duel), "迷宫低语者：锁轮后次回合恢复")
			duel.enemy_hp = int(float(duel.enemy_hp_max) * 0.49)
			g.on_damaged(duel, 0)
			g._chaos_chance = 1.0
			g.on_turn_begin(duel)
			_check(duel.pending_chaos, "迷宫低语者：P2 非恢复回合可乱权")
			duel.pending_chaos = false
			for i in 6:
				duel.pending_chaos = false
				g.on_turn_begin(duel)
				if g.recovery_window(duel):
					_check(not duel.pending_chaos, "迷宫低语者：恢复回合不追加乱权")
					break
		"躁怒元素使":
			duel.enemy_hp_max = 1000
			duel.enemy_hp = 490
			g.on_damaged(duel, 0)
			g.on_turn_begin(duel)
			_check(g.recovery_window(duel), "躁怒元素使：P2 转换首回合恢复")
			_check(String(duel.enemy_intent.get("type", "")) != "jam", "躁怒元素使：恢复回合不注废")
		"天平审判官":
			g._rule_pool = ["all_damage"]
			g._rule_every = 2
			g.on_turn_begin(duel)
			_check(String(duel.enemy_intent.get("type", "")) == "rule", "天平审判官：第2回合宣告律法")
			_fill_damage_row(duel)
			g.on_turn_resolved(duel)
			_check(is_equal_approx(float(duel.boss_atk_mult), 0.5), "天平审判官：达成律法攻击×0.5")
			g.on_turn_begin(duel)
			_check(g.recovery_window(duel), "天平审判官：达成后下一回合律法间隙")
		"无名虚空":
			duel.enemy_hp_max = 1000
			duel.enemy_hp = 490
			g.on_damaged(duel, 0)
			g.on_turn_begin(duel)
			_check(bool(g._recovery_pending), "无名虚空：P2 技能出池后安排静默拍")
			g.on_turn_begin(duel)
			_check(g.recovery_window(duel), "无名虚空：出池后下一回合麻木静默")
			_check(is_equal_approx(float(duel.boss_atk_mult), 0.6), "无名虚空：静默回合攻击降低")
		"深渊监视者":
			g._phase2 = true
			g._phase2_flashback_chance = 1.0
			g.on_turn_begin(duel)
			_check(g.consume_flashback(), "深渊监视者：P2 闪回强制重转")
			var trash_before: int = int(duel.boss_trash)
			g.on_turn_begin(duel)
			_check(g.recovery_window(duel), "深渊监视者：强制重转后次回合喘息")
			_check(int(duel.boss_trash) == trash_before, "深渊监视者：喘息回合不追加注废")
		"碎裂魔王":
			duel.enemy_hp_max = 1000
			duel.enemy_hp = 650
			g.on_damaged(duel, 0)
			var armor_before: int = int(duel.enemy_armor)
			g.on_turn_begin(duel)
			_check(g.recovery_window(duel), "碎裂魔王：P2 转换首回合僵直")
			_check(int(duel.enemy_armor) == armor_before, "碎裂魔王：僵直回合不叠甲")
			duel.enemy_hp = 320
			g.on_damaged(duel, 0)
			duel.player_status = {}
			g.on_turn_begin(duel)
			_check(g.recovery_window(duel), "碎裂魔王：P3 转换首回合僵直")
			_check(int(duel.player_status.get("poison", 0)) == 0, "碎裂魔王：僵直回合不挂新毒")
		"耻辱审判官":
			duel.enemy_hp_max = 1000
			duel.enemy_hp = 650
			g.on_damaged(duel, 0)
			duel.player_shield = 10
			g.on_turn_begin(duel)
			_check(int(duel.player_shield) == 0, "耻辱审判官：P2 剥盾")
			duel.player_shield = 10
			g.on_turn_begin(duel)
			_check(g.recovery_window(duel), "耻辱审判官：剥盾后下一回合不再剥盾")
			_check(int(duel.player_shield) == 10, "耻辱审判官：间隙回合保留护盾")
			duel.enemy_hp = 320
			g.on_damaged(duel, 0)
			_check(int(g._sins) == 0, "耻辱审判官：P3 入场罪业清算归零")
	if title != "":
		_check(String(g.recovery_title(duel)) == title,
			"%s 恢复标题真实（实测 %s）" % [nm, String(g.recovery_title(duel))])


# ---------------------------------------------------------------------------
# 勇者的阴影：投影 + 和解 + 血锁
# ---------------------------------------------------------------------------

func _shadow_checks(duel: DuelController, g) -> void:
	_check(g._instances.size() == 10, "勇者的阴影：10 个投影机制已实例化")
	g.on_turn_begin(duel)
	_check(bool(g._projected), "勇者的阴影：P1 每2回合投影生效")
	duel.enemy_hp_max = 1000
	duel.enemy_hp = 650
	g.on_damaged(duel, 0)
	_check(bool(g._phase2), "勇者的阴影：HP<66% 进入深渊镜像")
	duel.enemy_hp = 190
	g.on_damaged(duel, 0)
	_check(bool(g._phase3), "勇者的阴影：HP<20% 进入终极和解")
	_check(int(g.hp_floor(duel)) == 1, "勇者的阴影：P3 血锁下限 1")
	_check(String(duel.enemy_intent.get("type", "")) == "none", "勇者的阴影：P3 放下武器（意图 none）")
	duel.enemy_hp = 0
	duel.apply_enemy_hp_floor()
	_check(int(duel.enemy_hp) == 1, "勇者的阴影：旁路扣血被血锁收口")

	# 和解路径 a：任意三连
	_start_room(duel, _room_by_name(duel, "勇者的阴影"))
	g = duel.current_gimmick
	_to_p3(duel, g)
	g.on_special_triple(duel)
	_check(bool(duel.peaceful_win), "勇者的阴影：三连达成和解")
	# 和解路径 b：转出治疗符号
	_start_room(duel, _room_by_name(duel, "勇者的阴影"))
	g = duel.current_gimmick
	_to_p3(duel, g)
	duel.grid[0][0] = load(HEAL)
	g.on_turn_resolved(duel)
	_check(bool(duel.peaceful_win), "勇者的阴影：治疗符号达成和解")
	# 和解路径 c：恢复/净化类消耗品
	_start_room(duel, _room_by_name(duel, "勇者的阴影"))
	g = duel.current_gimmick
	_to_p3(duel, g)
	g.on_consumable_used(duel, "cleanse")
	_check(bool(duel.peaceful_win), "勇者的阴影：清净消耗品达成和解")
	# 非恢复类消耗品不触发
	_start_room(duel, _room_by_name(duel, "勇者的阴影"))
	g = duel.current_gimmick
	_to_p3(duel, g)
	g.on_consumable_used(duel, "attack")
	_check(not bool(duel.peaceful_win), "勇者的阴影：攻击消耗品不触发和解")


func _to_p3(duel: DuelController, g) -> void:
	duel.enemy_hp_max = 100
	duel.enemy_hp = 66
	g.on_damaged(duel, 0)
	duel.enemy_hp = 19
	g.on_damaged(duel, 0)


# ---------------------------------------------------------------------------
# 共享脚本的分化与幕池
# ---------------------------------------------------------------------------

func _test_whisper_differentiation(duel: DuelController) -> void:
	var cultist := _room_by_name(duel, "呓语教徒")
	var maze := _room_by_name(duel, "迷宫低语者")
	_check(int(cultist.gimmick_params.get("first_lock_turn", 0)) == 2,
		"D6：呓语教徒首次锁轮提前到第2回合")
	_check(int(maze.gimmick_params.get("first_lock_turn", 0)) == 0,
		"D6：迷宫低语者保持第3回合起锁轮")
	_check(float(cultist.gimmick_params.get("phase2_hp_ratio", 1.0)) == 0.0,
		"呓语教徒：单阶段（phase2_hp_ratio=0）")
	_check(float(maze.gimmick_params.get("phase2_hp_ratio", 0.0)) > 0.0,
		"迷宫低语者：双阶段（phase2_hp_ratio>0）")
	_check(int(maze.gimmick_params.get("phase2_lock_every", 0)) < int(maze.gimmick_params.get("lock_every", 0)),
		"迷宫低语者：P2 锁轮加速")


func _test_act_pools(duel: DuelController) -> void:
	var by_act := {1: 0, 2: 0, 3: 0}
	for r in duel.ALL_ROOMS:
		if r.kind == "boss":
			by_act[int(r.act)] = int(by_act.get(int(r.act), 0)) + 1
	_check(int(by_act[1]) == 4 and int(by_act[2]) == 5 and int(by_act[3]) == 4,
		"BOSS 幕池 4/5/4（实测 %d/%d/%d）" % [int(by_act[1]), int(by_act[2]), int(by_act[3])])


func _fill_damage_row(duel: DuelController) -> void:
	var paths := [DAMAGE_A, DAMAGE_B, DAMAGE_C]
	for r in 3:
		duel.grid[r][0] = load(String(paths[r]))


func _boot() -> DuelController:
	var scene: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.board_config.enabled = false
	duel._confirm_loadout()
	await get_tree().process_frame
	return duel


func _start_room(duel: DuelController, r: RoomData) -> void:
	duel.ROOMS.clear()
	duel.ROOMS.append(r)
	duel.start_room_data(r, 0, 0, false)


func _room_by_name(duel: DuelController, room_name: String) -> RoomData:
	for r in duel.ALL_ROOMS:
		if String(r.name) == room_name:
			return r
	return null


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)
