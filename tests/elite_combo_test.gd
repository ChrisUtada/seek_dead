extends Node

# ============================================================================
# Step 4 · 精英组合补强 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/elite_combo_test.tscn
#
# 覆盖：
# ① 12 个精英各自绑定正确脚本、非空 params / 可见 mechanic_summary；
# ② 四元组（触发 / 效果 / 应对）两两不同，替换项不再复用深渊侵蚀；
# ③ 每只精英的真实压力—恢复节奏与关键结算（破甲解冻、爆炸停毒、剥增益、注废、
#    周期自损、三连反制、锁定同列、补甲锁列、重击自损、目盲/锁轮交替）；
# ④ 高爆发仍可直接击杀，不引入锁血。
# ============================================================================

const EXPECTED := {
	"寒铁精英": ["rust_armor_gimmick", 1, "每3回合", "叠甲+冻结", "火/破甲/清净"],
	"毒疫术士": ["acid_bomb_gimmick", 1, "每回合+12层", "挂毒+爆炸后停毒2回合", "清净/抢攻"],
	"锈铁傀儡": ["rust_armor_gimmick", 1, "每3回合", "补甲+冻结+腐蚀", "破甲/恢复/清净"],
	"腐殖巨蠕": ["acid_bomb_gimmick", 1, "每4回合+挂毒", "剥增益+停毒", "提前用增益/清净/爆发"],
	"深渊咒师": ["whisper_lock_gimmick", 2, "每4回合", "锁列+强化攻击+注1废铁", "净化/利用锁符"],
	"炎爆群王": ["bipolar_phase_gimmick", 2, "每3回合+HP阈值", "P1自损高攻/P2切冰补甲", "抢攻/火系/破甲"],
	"深渊咏者": ["whisper_lock_gimmick", 2, "每4回合锁同列", "三连反制后减攻", "净化/主动三连"],
	"邪颂祭司": ["acid_bomb_gimmick", 2, "每4回合+挂毒", "自损5%换额外毒", "逼自损/清净"],
	"终末庄家": ["sleight_gimmick", 3, "每3回合注废", "注废+反噬", "换符号/净化/窗口爆发"],
	"圣盾守关": ["shield_warden_gimmick", 3, "入场+每4回合", "补甲+锁列", "破甲/净化/间隙输出"],
	"湮灭领主": ["annihilation_lord_gimmick", 3, "每4回合", "重击+自损8%", "防御/利用恢复窗"],
	"终焉守望": ["final_watcher_gimmick", 3, "每2回合交替", "目盲/锁轮+低血重击", "看当前格/净化/恢复窗"],
}

var _checks := 0
var _fails := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var duel: DuelController = await _boot()
	if duel == null:
		print("RESULT FAIL (boot)")
		get_tree().quit(2)
		return

	_check(EXPECTED.size() == 12, "样本表覆盖全部 12 个精英")
	var tuples := {}
	for nm in EXPECTED:
		var e: Array = EXPECTED[nm]
		tuples["%s|%s|%s" % [e[2], e[3], e[4]]] = true
	_check(tuples.size() == 12, "12 个精英的触发/效果/应对四元组两两不同")

	for nm in EXPECTED:
		var exp: Array = EXPECTED[nm]
		var r := _room_by_name(duel, nm)
		_check(r != null, "找到精英 %s" % nm)
		if r == null:
			continue
		_check(String(r.kind) == "elite" and int(r.act) == int(exp[1]), "%s 是 ACT%d 精英" % [nm, int(exp[1])])
		var script_name: String = r.gimmick_script.resource_path.get_file().get_basename() if r.gimmick_script != null else ""
		_check(script_name == String(exp[0]), "%s 使用 %s（实测 %s）" % [nm, exp[0], script_name])
		_check(not r.gimmick_params.is_empty(), "%s 参数非空" % nm)
		_check(String(r.mechanic_summary) != "", "%s 有真实机制摘要（确认层可见）" % nm)
		_check(script_name != "abyss_erosion_gimmick" or nm == "深渊监视者",
			"%s 不再错误复用深渊侵蚀" % nm)
		_start_room(duel, r)
		var g = duel.current_gimmick
		_check(g != null, "%s 实例化机制" % nm)
		if g == null:
			continue
		_check(int(g.hp_floor(duel)) == -1, "%s 无锁血下限" % nm)
		_behavior(duel, g, nm)

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _behavior(duel: DuelController, g, nm: String) -> void:
	match nm:
		"寒铁精英":
			_check(int(duel.enemy_armor) == 0, "寒铁精英第 1 回合蓄势不叠甲")
			g.on_turn_begin(duel)
			_check(int(duel.enemy_armor) == 4, "第 2 回合叠 4 甲（实测 %d）" % int(duel.enemy_armor))
			_check(int(duel.player_frost) >= 1, "爆发回合冻结 1 列")
			duel.enemy_armor = 0
			g.on_armor_break(duel)
			_check(int(duel.player_frost) == 0, "D1：破甲立即解除冻结（BOSS 保留到次回合）")
		"毒疫术士":
			duel.player_hp = 1000
			duel.player_hp_max = 1000
			duel.player_shield = 0
			duel.player_status = {"poison": 12}
			g.on_turn_begin(duel)
			_check(int(duel.player_status.get("poison", 0)) == 0, "12 层毒触发爆炸并清零")
			_check(int(duel.player_hp) < 1000, "爆炸造成伤害（实测 -%d）" % (1000 - int(duel.player_hp)))
			g.on_turn_begin(duel)
			g.on_turn_begin(duel)
			_check(int(duel.player_status.get("poison", 0)) == 0, "D2：爆炸后停毒 2 回合")
			g.on_turn_begin(duel)
			_check(int(duel.player_status.get("poison", 0)) == 1, "恢复窗结束重新挂毒 1 层")
		"锈铁傀儡":
			var base_armor: int = int(duel.enemy_armor)
			g.on_turn_begin(duel)
			g.on_turn_begin(duel)
			_check(int(duel.enemy_armor) == base_armor + 4,
				"锈铁傀儡第 3 回合补 4 甲（实测 +%d）" % (int(duel.enemy_armor) - base_armor))
			_check(duel.debuffs.has("corrode"), "补甲同时附加腐蚀（护盾收益降低）")
			duel.enemy_armor = 5
			duel.combat.on_counter("special")
			_check(int(duel.enemy_armor) == 0 and not duel.debuffs.has("corrode"), "破甲解除腐蚀")
		"腐殖巨蠕":
			var sym := SymbolData.new()
			sym.label = "✦"
			sym.name = "测试增益"
			duel.player_buffs[sym] = 3
			duel.player_status = {}
			for i in 3:
				g.on_turn_begin(duel)
			_check(duel.player_buffs.is_empty(), "第 4 回合剥走 1 个玩家增益")
			var stacks_after: int = int(duel.player_status.get("poison", 0))
			g.on_turn_begin(duel)
			_check(int(duel.player_status.get("poison", 0)) == stacks_after, "剥增益后一回合停止挂毒")
		"深渊咒师":
			var sizes: Array[int] = []
			for st in duel.reel_system.reel_strips:
				sizes.append(st.size())
			for i in 4:
				g.on_turn_begin(duel)
			var col: int = int(duel.pending_lock_reel)
			_check(col >= 0 and col < 3, "第 4 回合锁定 1 列")
			_check(duel.reel_system.reel_strips[col].size() == sizes[col] + 1,
				"D4：锁列同时向该列注入 1 废铁（带长 +1）")
		"炎爆群王":
			duel.enemy_hp_max = 1000
			duel.enemy_hp = 1000
			g.on_turn_begin(duel)
			_check(int(duel.enemy_hp) == 1000, "P1 周期未到不自损")
			g.on_turn_begin(duel)
			_check(int(duel.enemy_hp) == 970, "D3：每 3 回合自损 3%%（实测 -%d）" % (1000 - int(duel.enemy_hp)))
		"深渊咏者":
			duel.enemy_atk = 20
			for i in 4:
				g.on_turn_begin(duel)
			var lc: int = int(duel.pending_lock_reel)
			_check(lc >= 0 and lc < 3, "每 4 回合锁同一列（本次第 %d 列）" % (lc + 1))
			var sym2 := SymbolData.new()
			sym2.label = "A"
			sym2.name = "测试A"
			for rr in 3:
				duel.grid[rr][0] = sym2
			g.on_special_triple(duel)
			duel.turn_count += 1
			g.on_turn_begin(duel)
			_check(is_equal_approx(float(duel.boss_atk_mult), 0.7), "锁定符号三连后下一回合攻击 ×0.7（实测 %s）" % duel.boss_atk_mult)
		"邪颂祭司":
			duel.enemy_hp_max = 1000
			duel.enemy_hp = 1000
			duel.player_status = {}
			duel.player_hp = 1000
			duel.player_hp_max = 1000
			duel.player_shield = 0
			for i in 3:
				g.on_turn_begin(duel)
			_check(int(duel.enemy_hp) == 950, "每 4 回合自损 5%%（实测 %d）" % int(duel.enemy_hp))
			_check(int(duel.player_status.get("poison", 0)) == 5, "自损换额外毒层（3 回合常驻 + 2 额外 = 5）")
		"终末庄家":
			for i in 3:
				g.on_turn_begin(duel)
			_check(int(duel.pending_jam_reel) >= 0, "第 3 回合注废 1 列")
			_check(duel.debuffs.has("backlash"), "注废同时施加反噬")
			_check(duel.debuffs.turns_left("backlash") == 2, "反噬持续 2 回合")
		"圣盾守关":
			var base_shield: int = int(duel.enemy_armor)
			_check(base_shield >= 20, "入场护甲成立（含行为族基础甲 %d）" % base_shield)
			for i in 3:
				g.on_turn_begin(duel)
			_check(int(duel.enemy_armor) == base_shield + 10,
				"第 4 回合补 10 甲（实测 +%d）" % (int(duel.enemy_armor) - base_shield))
			_check(int(duel.pending_lock_reel) >= 0 and int(duel.pending_lock_reel) < 3, "同回合锁 1 列")
		"湮灭领主":
			duel.enemy_hp_max = 1000
			duel.enemy_hp = 1000
			duel.enemy_atk = 20
			duel.player_hp = 1000
			duel.player_hp_max = 1000
			duel.player_shield = 0
			for i in 3:
				g.on_turn_begin(duel)
			_check(String(duel.enemy_intent.get("type", "")) == "heavy", "第 4 回合改为重击")
			_check(int(duel.enemy_self_damage_after) == 80, "重击附带 8%% 自损（%d）" % int(duel.enemy_self_damage_after))
			duel.enemy_system.take_turn()
			_check(int(duel.enemy_hp) == 920, "行动后自损落地（剩余 %d）" % int(duel.enemy_hp))
			g.on_turn_begin(duel)
			_check(is_equal_approx(float(duel.boss_atk_mult), 0.7), "次回合减攻进入恢复窗")
		"终焉守望":
			duel.enemy_hp_max = 1000
			duel.enemy_hp = 1000
			_check(not duel.debuffs.has("blind"), "第 1 回合不干扰")
			g.on_turn_begin(duel)
			_check(duel.debuffs.has("blind"), "第 2 回合目盲")
			duel.debuffs.clear_interference(duel)
			g.on_turn_begin(duel)
			_check(int(duel.pending_lock_reel) == -1, "第 3 回合恢复（不追加干扰）")
			g.on_turn_begin(duel)
			_check(int(duel.pending_lock_reel) >= 0, "第 4 回合改为锁轮（交替）")
			duel.enemy_hp = 400
			g.on_turn_begin(duel)
			g.on_turn_begin(duel)
			_check(String(duel.enemy_intent.get("type", "")) == "heavy", "HP<50%% 后干扰回合追加重击")


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
