extends Node

# ============================================================================
# 普通怪早期特性 · headless 回归（Step 4 建立；Step 2 ACT1；Step 3 ACT2/ACT3）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/normal_trait_test.tscn
#
# 覆盖：
# ① 36 只普通怪（ACT1/2/3 各 12）各挂且只挂 1 个早期特性（normal_trait_gimmick）；
# ② 特性在「入场 / 首次转轮前 / 首次受击 / 首次破甲 / 周期 / HP 阈值」就能看到；
# ③ 每只怪效果真实结算（重击 / 双段 / 穿透 / 补甲 / 缠绕 / 易伤 / 灼烧 / 吸能 / 回声…）；
# ④ 不加锁血 / 强制复活 / 阶段变化：hp_floor = -1，高爆发仍可直接击杀；
# ⑤ 每只怪 mechanic_summary 非空；36 个 trait 无重复。
# ============================================================================

const EXPECTED := {
	# —— ACT1 ——
	"重锤蛮兵": ["charge", 1],
	"毒壳壁垒": ["shell", 1],
	"窃语咒师": ["jam_open", 1],
	"辉光游侠": ["first_hit_ward", 1],
	"冰锋群蝠": ["frost_open", 1],
	"暗影诡匠": ["lock_open", 1],
	"腐化史莱姆": ["poison_hit", 1],
	"裂石像": ["break_skip", 1],
	"余烬傀儡": ["ember_heal", 1],
	"寒鳞蝠": ["frost_hit", 1],
	"锈盲蝠": ["rust_jam", 1],
	"毒孢菌": ["spore", 1],
	# —— ACT2 ——
	"暮色蛮兵": ["periodic_heavy", 2],
	"铁臂蛮兵": ["first_hit_heavy", 2],
	"圣壳壁垒": ["armor_regen", 2],
	"石壳壁垒": ["break_heavy", 2],
	"毒雾术士": ["chaos_open", 2],
	"暗行游侠": ["blind_open", 2],
	"炎锋群蝠": ["double_light", 2],
	"迷面诡匠": ["shift_hit", 2],
	"迷魂灯笼": ["auto_stop_cycle", 2],
	"亵渎书吏": ["backlash_triple", 2],
	"暗影信徒": ["sacrifice_heavy", 2],
	"虚空低语者": ["echo_half", 2],
	# —— ACT3 ——
	"辉铁蛮兵": ["weak_open", 3],
	"深渊蛮兵": ["heavy_pause", 3],
	"熔壳壁垒": ["burn_on_hit", 3],
	"黑曜壁垒": ["armor_periodic", 3],
	"霜语术士": ["frost_two_cycle", 3],
	"圣辉游侠": ["pierce_heavy", 3],
	"毒针群蝠": ["double_poison", 3],
	"深渊诡匠": ["drain_cycle", 3],
	"湮灭使徒": ["big_heavy_self", 3],
	"坍缩星核": ["vulnerable_phase", 3],
	"裂界游魂": ["entangle_cycle", 3],
	"虚空回响": ["echo_full", 3],
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

	_check(EXPECTED.size() == 36, "样本表覆盖 ACT1/ACT2/ACT3 全部 36 只普通怪")
	var seen_traits := {}
	for tid in EXPECTED.values():
		seen_traits[tid[0]] = true
	_check(seen_traits.size() == 36, "36 个 trait 互不重复（每只怪一个特性）")

	var per_act := {1: 0, 2: 0, 3: 0}
	for r in duel.ALL_ROOMS:
		if String(r.kind) == "normal":
			var a := int(r.act)
			per_act[a] = int(per_act.get(a, 0)) + 1
	for a in [1, 2, 3]:
		_check(int(per_act[a]) == 12, "房间池中 ACT%d 普通怪 = 12（实测 %d）" % [a, int(per_act[a])])

	for monster in EXPECTED:
		var trait_id := String(EXPECTED[monster][0])
		var act := int(EXPECTED[monster][1])
		var r := _room_by_name(duel, monster)
		_check(r != null, "找到普通怪 %s" % monster)
		if r == null:
			continue
		_check(String(r.kind) == "normal" and int(r.act) == act, "%s 是 ACT%d 普通怪" % [monster, act])
		_check(String(r.gimmick_params.get("trait", "")) == trait_id, "%s 只配置 trait=%s" % [monster, trait_id])
		_check(not r.gimmick_params.has("triggers") and r.gimmick_params.size() <= 3,
			"%s 没有叠加多机制（params=%d）" % [monster, r.gimmick_params.size()])
		_check(String(r.mechanic_summary) != "", "%s 有可见机制摘要" % monster)
		_start_room(duel, r)
		var g = duel.current_gimmick
		_check(g != null, "%s 实例化特性" % monster)
		if g == null:
			continue
		_check(g.get_script().resource_path.get_file() == "normal_trait_gimmick.gd",
			"%s 使用普通特性脚本" % monster)
		_check(int(g.hp_floor(duel)) == -1, "%s 无锁血下限" % monster)
		_check(not bool(g.recovery_window(duel)), "%s 不是精英式恢复窗口" % monster)
		_behavior(duel, g, monster, trait_id)

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _behavior(duel: DuelController, g, monster: String, trait_id: String) -> void:
	match trait_id:
		"shell":
			_check(int(duel.enemy_armor) == 20 and int(duel.enemy_armor_max) == 20,
				"毒壳壁垒入场即有 20 护甲")
			for i in 3:
				g.on_turn_begin(duel)
			_check(int(duel.enemy_armor) == 20, "硬壳不随回合叠加")
		"frost_open":
			_check(int(duel.player_frost) == 1, "冰锋群蝠首回合冻结 1 列（转轮前可见）")
			duel.turn_flow.begin_player_turn()
			_check(int(duel.player_frost) == 0, "冻结次回合自消，不形成永久封锁")
		"jam_open":
			_check(int(duel.pending_jam_reel) == 0, "窃语咒师首次转轮前注废第 1 列")
			duel.pending_jam_reel = -1
			duel.turn_flow.begin_player_turn()
			_check(int(duel.pending_jam_reel) == -1, "注废只触发一次，不逐回合叠加")
		"first_hit_ward":
			_check(int(duel.enemy_armor) == 0, "辉光游侠开局无护甲")
			g.on_damaged(duel, 7)
			_check(int(duel.enemy_armor) == 10, "首次受击后获得 10 护甲")
			g.on_damaged(duel, 7)
			_check(int(duel.enemy_armor) == 10, "护体只触发一次")
			duel.enemy_hp = 5
			duel.combat.apply_enemy_damage(999.0, false)
			duel.apply_enemy_hp_floor()
			_check(int(duel.enemy_hp) <= 0, "高爆发可直接击杀（无锁血 / 复活）")
		"charge":
			_check(String(duel.enemy_intent.get("type", "")) == "heavy",
				"重锤蛮兵入场蓄力：首个意图为重击")
			_check(int(duel.enemy_intent.get("value", 0)) > int(duel.enemy_atk),
				"蓄力重击数值高于普通攻击（%d）" % int(duel.enemy_intent.get("value", 0)))
			g.on_turn_begin(duel)
			_check(String(duel.enemy_intent.get("type", "")) == "heavy", "蓄力不会在重击未打出前重置")
		"lock_open":
			var lc := int(duel.pending_lock_reel)
			_check(lc >= 0 and lc < 3, "暗影诡匠首次转轮前锁定一列（第 %d 列）" % (lc + 1))
			duel.pending_lock_reel = -1
			duel.turn_flow.begin_player_turn()
			_check(int(duel.pending_lock_reel) == -1, "锁列只触发一次")
		"rust_jam":
			g.on_damaged(duel, 5)
			var rc := int(duel.pending_jam_reel)
			_check(rc >= 0 and rc < 3, "锈盲蝠首次受击后注废一列（第 %d 列）" % (rc + 1))
			duel.pending_jam_reel = -1
			g.on_damaged(duel, 5)
			_check(int(duel.pending_jam_reel) == -1, "注废只触发一次")
		"poison_hit":
			duel.player_status = {}
			g.on_damaged(duel, 5)
			_check(int(duel.player_status.get("poison", 0)) == 1, "腐化史莱姆首次受击使玩家中毒 1 层")
			duel.player_hp = 1000
			duel.player_hp_max = 1000
			duel.player_shield = 0
			duel.turn_flow.begin_player_turn()
			_check(int(duel.player_hp) == 998, "中毒回合开始结算 2 点（实测 -%d）" % (1000 - int(duel.player_hp)))
			_check(int(duel.player_status.get("poison", 0)) == 0, "中毒每回合 -1 层，不会永久挂住")
		"break_skip":
			duel.enemy_armor = 20
			duel.enemy_armor_max = 20
			duel.combat.on_counter("special")
			_check(int(duel.enemy_armor) == 0, "裂石像被破甲（护甲清零）")
			_check(int(duel.enemy_stunned) == 1, "破甲后下一次行动失效")
			duel.enemy_intent = {"data": null, "type": "heavy", "value": 50}
			duel.player_hp = 1000
			duel.player_hp_max = 1000
			duel.player_shield = 0
			duel.enemy_system.take_turn()
			_check(int(duel.player_hp) == 1000, "失效行动不造成伤害（输出窗口）")
			_check(int(duel.enemy_stunned) == 0, "行动失效只消耗一次")
			duel.combat.on_counter("special")
			_check(int(duel.enemy_stunned) == 0, "重复破甲不叠加行动失效")
		"ember_heal":
			duel.enemy_hp_max = 100
			duel.enemy_hp = 50
			duel.turn_damage_elems.clear()
			duel.turn_damage_elems.append("fire")
			g.on_damaged(duel, 10)
			_check(int(duel.enemy_hp) == 56, "余烬傀儡受火伤回复 6 HP（实测 %d）" % int(duel.enemy_hp))
			g.on_damaged(duel, 10)
			_check(int(duel.enemy_hp) == 56, "每回合只回一次")
			duel.turn_count += 1
			duel.turn_damage_elems.clear()
			duel.turn_damage_elems.append("ice")
			g.on_damaged(duel, 10)
			_check(int(duel.enemy_hp) == 56, "非火系伤害不触发回复")
		"frost_hit":
			duel.enemy_status = {}
			g.on_damaged(duel, 5)
			g.on_damaged(duel, 5)
			_check(int(duel.enemy_status.get("frost", 0)) == 2, "寒鳞蝠每次受击获得 1 层霜（共 2 层）")
			duel.player_hp = 1000
			duel.player_hp_max = 1000
			duel.player_shield = 0
			duel.combat.enemy_deal_damage(100)
			_check(int(duel.player_hp) == 940, "2 层霜使下一次攻击 -40%%（实测 -%d）" % (1000 - int(duel.player_hp)))
		"spore":
			duel.player_status = {}
			duel.enemy_hp_max = 100
			duel.enemy_hp = 60
			g.on_damaged(duel, 5)
			_check(int(duel.player_status.get("poison", 0)) == 0, "毒孢菌 HP > 50% 时不触发")
			duel.enemy_hp = 40
			g.on_damaged(duel, 5)
			_check(int(duel.player_status.get("poison", 0)) == 2, "HP 首次低于 50% 时中毒 2 层")
			duel.enemy_hp = 30
			g.on_damaged(duel, 5)
			_check(int(duel.player_status.get("poison", 0)) == 2, "毒孢只触发一次")
		# —— ACT2 ——
		"periodic_heavy":
			_set_turn(duel, 2)
			duel.enemy_intent = {"data": duel.status_system.intent_def("attack"), "type": "attack", "value": int(duel.enemy_atk)}
			g.on_turn_begin(duel)
			_check(String(duel.enemy_intent.get("type", "")) == "attack", "暮色蛮兵非周期回合不改写意图")
			_set_turn(duel, 3)
			g.on_turn_begin(duel)
			_check(String(duel.enemy_intent.get("type", "")) == "heavy", "第 3 回合改为重击")
		"first_hit_heavy":
			duel.enemy_intent = {"data": duel.status_system.intent_def("attack"), "type": "attack", "value": int(duel.enemy_atk)}
			g.on_damaged(duel, 5)
			_check(String(duel.enemy_intent.get("type", "")) == "heavy", "铁臂蛮兵首次受击后本次行动改为重击")
			duel.enemy_intent = {"data": duel.status_system.intent_def("attack"), "type": "attack", "value": int(duel.enemy_atk)}
			g.on_damaged(duel, 5)
			_check(String(duel.enemy_intent.get("type", "")) == "attack", "铁臂反击只触发一次")
		"armor_regen":
			_set_turn(duel, 1)
			duel.enemy_armor = 10
			duel.enemy_armor_max = 10
			g.on_armor_break(duel)
			_set_turn(duel, 2)
			g.on_turn_begin(duel)
			_check(int(duel.enemy_armor) == 10, "圣壳壁垒破甲后 2 回合内不立即补甲")
			_set_turn(duel, 3)
			g.on_turn_begin(duel)
			_check(int(duel.enemy_armor) == 18, "第 2 回合末补回 8 护甲（实测 %d）" % int(duel.enemy_armor))
			g.on_armor_break(duel)
			_set_turn(duel, 6)
			g.on_turn_begin(duel)
			_check(int(duel.enemy_armor) == 18, "补甲只触发一次")
		"break_heavy":
			duel.enemy_intent = {"data": duel.status_system.intent_def("attack"), "type": "attack", "value": int(duel.enemy_atk)}
			g.on_armor_break(duel)
			_check(String(duel.enemy_intent.get("type", "")) == "heavy", "石壳壁垒首次破甲后本次行动改为重击")
		"chaos_open":
			_check(bool(duel.pending_chaos), "毒雾术士入场乱权标记生效")
			var strips_ok := duel.reel_system.reel_strips.size() == 3
			for st in duel.reel_system.reel_strips:
				if st.is_empty():
					strips_ok = false
			_check(strips_ok, "乱权后三列转轮带完整（内容不变，顺序重排）")
			duel.pending_chaos = false
		"blind_open":
			_check(duel.debuffs.has("blind") and duel.debuffs.turns_left("blind") == 2,
				"暗行游侠入场目盲 2 回合")
			_check(duel.debuffs.preview_hidden(), "目盲隐藏后续预览（当前格仍可见）")
		"double_light":
			_set_turn(duel, 3)
			g.on_turn_begin(duel)
			var dv := int(round(float(duel.enemy_atk) * 0.6))
			_check(String(duel.enemy_intent.get("type", "")) == "attack"
				and int(duel.enemy_intent.get("value", 0)) == dv,
				"炎锋群蝠每 3 回合改为攻击（%d）" % int(duel.enemy_intent.get("value", 0)))
			_check(duel.enemy_extra_attacks.size() == 1
				and int(duel.enemy_extra_attacks[0].get("value", 0)) == dv,
				"双段：追加一次同数值攻击")
			duel.enemy_extra_attacks.clear()
		"shift_hit":
			var syms: Array = []
			for i in 3:
				var s := SymbolData.new()
				s.label = ["A", "B", "C"][i]
				s.name = "测试%d" % i
				duel.grid[i][0] = s
				duel.grid_elem[i][0] = "none"
				syms.append(s)
			g.on_damaged(duel, 5)
			_check(duel.grid[0][0] == syms[2] and duel.grid[1][0] == syms[0] and duel.grid[2][0] == syms[1],
				"迷面诡匠：三列符号位序平移一位（内容不变）")
			g.on_damaged(duel, 5)
			_check(duel.grid[0][0] == syms[2], "位序平移只触发一次")
		"auto_stop_cycle":
			duel.pending_auto_stop = false
			_set_turn(duel, 3)
			g.on_turn_begin(duel)
			_check(bool(duel.pending_auto_stop), "迷魂灯笼每 3 回合夺轮（下轮自动停止）")
			duel.pending_auto_stop = false
		"backlash_triple":
			g.on_special_triple(duel)
			_check(duel.debuffs.has("backlash") and duel.debuffs.turns_left("backlash") == 1,
				"亵渎书吏：玩家首次三连后下回合反噬 1 回合")
			g.on_special_triple(duel)
			_check(duel.debuffs.turns_left("backlash") == 1, "反噬只施加一次（不叠加层数）")
			duel.debuffs.clear_status(duel)
		"sacrifice_heavy":
			_set_turn(duel, 4)
			duel.enemy_hp_max = 1000
			duel.enemy_hp = 1000
			g.on_turn_begin(duel)
			_check(int(duel.enemy_hp) == 960, "暗影信徒每 4 回合自损 4%%（实测 -%d）" % (1000 - int(duel.enemy_hp)))
			_check(String(duel.enemy_intent.get("type", "")) == "heavy", "献祭后本次行动为重击")
		"echo_half":
			duel.last_enemy_intent = {"data": null, "type": "heavy", "value": 100}
			_set_turn(duel, 3)
			g.on_turn_begin(duel)
			_check(String(duel.enemy_intent.get("type", "")) == "heavy"
				and int(duel.enemy_intent.get("value", 0)) == 50,
				"虚空低语者：以 50%% 数值重复上一行动（实测 %d）" % int(duel.enemy_intent.get("value", 0)))
		# —— ACT3 ——
		"weak_open":
			_check(duel.debuffs.has("weak") and duel.debuffs.turns_left("weak") == 1,
				"辉铁蛮兵入场虚弱 1 回合")
			_check(is_equal_approx(duel.debuffs.damage_mult(), 0.8), "虚弱使攻击收益 -20%")
		"heavy_pause":
			_set_turn(duel, 2)
			g.on_turn_begin(duel)
			_check(String(duel.enemy_intent.get("type", "")) == "heavy", "深渊蛮兵每 2 回合重击")
			g.on_armor_break(duel)
			_set_turn(duel, 4)
			duel.enemy_intent = {"data": duel.status_system.intent_def("attack"), "type": "attack", "value": int(duel.enemy_atk)}
			g.on_turn_begin(duel)
			_check(String(duel.enemy_intent.get("type", "")) == "attack", "破甲后下一次重击延后一轮")
			_set_turn(duel, 6)
			g.on_turn_begin(duel)
			_check(String(duel.enemy_intent.get("type", "")) == "heavy", "延后一轮后恢复重击周期")
		"burn_on_hit":
			duel.player_status = {}
			duel.enemy_armor = 10
			duel.enemy_armor_max = 10
			_set_turn(duel, 10)
			g.on_damaged(duel, 5)
			_check(int(duel.player_status.get("burn", 0)) == 1, "熔壳壁垒：有甲时首次受击灼烧 +1")
			g.on_damaged(duel, 5)
			_check(int(duel.player_status.get("burn", 0)) == 1, "同一回合只触发一次")
			duel.player_hp = 1000
			duel.player_hp_max = 1000
			duel.player_shield = 0
			_set_turn(duel, 11)
			g.on_turn_begin(duel)
			_check(int(duel.player_hp) == 998, "灼烧回合开始结算 2 点（实测 -%d）" % (1000 - int(duel.player_hp)))
			_check(int(duel.player_status.get("burn", 0)) == 0, "灼烧每回合 -1 层，不会永久挂住")
			duel.enemy_armor = 0
			_set_turn(duel, 12)
			g.on_damaged(duel, 5)
			_check(int(duel.player_status.get("burn", 0)) == 0, "破甲后不再触发灼烧")
		"armor_periodic":
			duel.enemy_armor = 10
			duel.enemy_armor_max = 10
			_set_turn(duel, 4)
			g.on_turn_begin(duel)
			_check(int(duel.enemy_armor) == 20, "黑曜壁垒每 4 回合补 10 甲（实测 %d）" % int(duel.enemy_armor))
		"frost_two_cycle":
			duel.player_frost = 0
			_set_turn(duel, 3)
			g.on_turn_begin(duel)
			_check(int(duel.player_frost) == 2, "霜语术士每 3 回合冻结 2 列")
			duel.player_frost = 0
		"pierce_heavy":
			_set_turn(duel, 3)
			g.on_turn_begin(duel)
			_check(String(duel.enemy_intent.get("type", "")) == "heavy", "圣辉游侠每 3 回合重击")
			_check(is_equal_approx(float(duel.enemy_attack_pierce_pct), 0.25), "重击附带 25% 穿透护盾")
			duel.player_hp = 1000
			duel.player_hp_max = 1000
			duel.player_shield = 500
			duel.enemy_system.take_turn()
			_check(int(duel.player_shield) < 500 and int(duel.player_hp) < 1000, "穿透：护盾与 HP 同时受损")
		"double_poison":
			_set_turn(duel, 3)
			g.on_turn_begin(duel)
			var pv := int(round(float(duel.enemy_atk) * 0.6))
			_check(String(duel.enemy_intent.get("type", "")) == "attack"
				and int(duel.enemy_intent.get("value", 0)) == pv, "毒针群蝠双段攻击（%d）" % pv)
			_check(int(duel.enemy_attack_poison) == 1 and duel.enemy_extra_attacks.size() == 1,
				"两段各附 1 层毒")
			duel.player_status = {}
			duel.player_hp = 1000
			duel.player_hp_max = 1000
			duel.player_shield = 0
			duel.enemy_status = {}
			duel.enemy_system.take_turn()
			_check(int(duel.player_status.get("poison", 0)) == 2, "结算后玩家共 2 层毒")
			_check(int(duel.player_hp) == 1000 - pv * 2, "双段共造成 %d 伤害（实测 %d）" % [pv * 2, 1000 - int(duel.player_hp)])
		"drain_cycle":
			duel.charge_points = 5
			_set_turn(duel, 3)
			g.on_turn_begin(duel)
			_check(int(duel.charge_points) == 3, "深渊诡匠每 3 回合吸能 -2（实测 %d）" % int(duel.charge_points))
		"big_heavy_self":
			_set_turn(duel, 4)
			duel.enemy_hp_max = 1000
			duel.enemy_hp = 1000
			duel.player_hp = 1000
			duel.player_hp_max = 1000
			duel.player_shield = 0
			g.on_turn_begin(duel)
			var hv := int(round(float(duel.enemy_atk) * 2.5))
			_check(String(duel.enemy_intent.get("type", "")) == "heavy"
				and int(duel.enemy_intent.get("value", 0)) == hv, "湮灭使徒 250%% 重击（%d）" % hv)
			_check(int(duel.enemy_self_damage_after) == 30, "重击后自损 3%%（%d）" % int(duel.enemy_self_damage_after))
			duel.enemy_system.take_turn()
			_check(int(duel.enemy_hp) == 970, "行动结束后自损落地（剩余 %d）" % int(duel.enemy_hp))
		"vulnerable_phase":
			duel.enemy_hp_max = 100
			duel.enemy_hp = 45
			g.on_damaged(duel, 5)
			_check(not duel.debuffs.has("vulnerable"), "坍缩星核 HP > 40% 时不触发")
			duel.enemy_hp = 39
			g.on_damaged(duel, 5)
			_check(duel.debuffs.has("vulnerable") and duel.debuffs.turns_left("vulnerable") == 2,
				"HP 首次低于 40%% 时易伤 2 回合")
			duel.debuffs.clear_status(duel)
		"entangle_cycle":
			_set_turn(duel, 3)
			g.on_turn_begin(duel)
			_check(duel.debuffs.has("entangle") and duel.debuffs.entangle_order() == "ltr",
				"裂界游魂每 3 回合缠绕（首次从左到右）")
			_set_turn(duel, 6)
			g.on_turn_begin(duel)
			_check(duel.debuffs.entangle_order() == "rtl", "缠绕方向逐次交替（第二次从右到左）")
			duel.debuffs.clear_interference(duel)
		"echo_full":
			duel.last_enemy_intent = {"data": null, "type": "attack", "value": 77}
			_set_turn(duel, 4)
			g.on_turn_begin(duel)
			_check(String(duel.enemy_intent.get("type", "")) == "attack"
				and int(duel.enemy_intent.get("value", 0)) == 77,
				"虚空回响：完整重复上一行动（77）")


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


func _set_turn(duel: DuelController, n: int) -> void:
	duel.turn_count = n


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
