extends Node

# ============================================================================
# Step 1 共用触发与 debuff 模块 · headless 回归（2026-11-12）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/step1_module_test.tscn
#
# 覆盖（真实 DuelController + CombatSystem + ReelSystem + ConsumableSystem）：
#   A. 9 个减益定义完整（名称/图标/类型/持续/应对），且都有解除路径
#   B. 数值结算：虚弱 -20% / 易伤 +25% / 腐蚀 -25% 护盾 / 禁疗 -50% 治疗 / 吸能 -2
#   C. 操作类：目盲隐藏预览 / 缠绕限制停列顺序（自动停轮不受限）
#   D. 反噬：连续同符号扣小额代价（不致死、每回合一次），换符号立即结束
#   E. 剥增益：移除一个增益；无增益时安全空放
#   F. 持续与结束：转轮前施加本回合生效、结算中施加下回合起算、1/2 回合到期、腐蚀破甲解除
#   G. 净化 / 清净分工：只解各自类别，互不越界
#   H. 共用触发模块：入场 / 首次转轮前 / 首次受击 / 周期 / 首次破甲 / 阶段，均只触发一次
#   I. 首次提示与 HUD 状态行；全程不消耗全局 RNG
# ============================================================================

const HEAL_POTION := "res://resources/consumables/heal_potion.tres"
const CLEANSE_POTION := "res://resources/consumables/cleanse_potion.tres"
const PURIFY_POTION := "res://resources/consumables/purify_potion.tres"
const TriggerKit = preload("res://scripts/battle/gimmicks/trigger_kit.gd")

var _checks := 0
var _fails := 0
var _save_backup := {}
var _have_save := false


func _ready() -> void:
	_save_backup = SaveSystem.load_lobby_data().duplicate(true)
	_have_save = true
	await _run()
	_restore_save()
	print("---")
	print("STEP1|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _restore_save() -> void:
	if not _have_save:
		return
	SaveSystem.save_lobby_data(_save_backup)
	SaveSystem.flush_lobby_data()


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("STEP1|FAIL|" + msg)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	var out: Array[String] = []
	for w in ["fire_sword", "holy_sword"]:
		for p in duel.WEAPON_POOL:
			if p.ends_with(w + ".tres"):
				out.append(p)
				break
	duel.selected_loadout.assign(out)
	duel.selected_consumables.clear()
	duel.selected_charms.clear()
	duel.selected_skills.clear()
	duel._confirm_loadout()
	return duel


# 每个用例前把战斗状态收回到可预测基线（不改任何平衡数值）。
func _fresh(duel: DuelController) -> void:
	if duel.debuffs != null:
		duel.debuffs.reset()
	duel.player_buffs.clear()
	duel.player_shield = 0
	duel.player_hp_max = 1000
	duel.player_hp = 1000
	duel.player_frost = 0
	duel.player_status = {}
	duel.enemy_armor = 0
	duel.enemy_armor_max = 0
	duel.enemy_hp_max = 10000
	duel.enemy_hp = 10000
	duel.charge_points = 0
	duel.current_gimmick = null
	duel.assault_next_spin = 1
	duel.charm_damage_mult = 1.0
	duel.charm_shield_trickle = 0
	duel.charm_heal_trickle = 0
	duel.deprived_level = 0
	duel._reward_system.run_power_bonus = 0
	duel.growth.perk_ids.clear()
	duel.readability.apply_preset("control")   # 关掉输入缓冲/视觉落点，避免用例被延迟按停干扰
	duel.pending_jam_reel = -1
	duel.pending_lock_reel = -1
	duel.pending_chaos = false
	duel.pending_auto_stop = false
	duel.frozen_cols.clear()


func _attack_damage(duel: DuelController, amount: float) -> int:
	var acc: Dictionary = duel.combat._new_acc()
	acc["dmg"] = amount
	var before: int = int(duel.enemy_hp)
	await duel.combat._phase_attack({}, acc)
	return before - int(duel.enemy_hp)


func _run() -> void:
	var duel: DuelController = await _boot()

	# —— A. 定义完整性 ——
	var ids := ["weak", "vulnerable", "corrode", "drain", "heal_block", "blind", "entangle", "backlash", "strip"]
	var all_ok := true
	for id in ids:
		var d: Dictionary = duel.debuffs.DEFS.get(id, {})
		if d.is_empty() or String(d.get("name", "")) == "" or String(d.get("icon", "")) == "" \
				or String(d.get("desc", "")) == "" or String(d.get("counter", "")) == "":
			all_ok = false
			print("STEP1|INFO|定义缺失：", id)
	_check(all_ok, "9 个减益定义均含名称/图标/效果/应对")
	_check(String(duel.debuffs.DEFS["weak"]["kind"]) == "status"
		and String(duel.debuffs.DEFS["blind"]["kind"]) == "interference"
		and String(duel.debuffs.DEFS["drain"]["kind"]) == "instant", "减益分类正确（status / interference / instant）")

	# —— B1. 虚弱：伤害 -20%（真实 _phase_attack 结算）——
	_fresh(duel)
	duel.turn_count = 10
	var base_dmg: int = await _attack_damage(duel, 1000.0)
	_fresh(duel)
	duel.turn_count = 10
	duel.apply_debuff("weak", 1)
	duel.enemy_hp_max = 10000
	duel.enemy_hp = 10000
	var weak_dmg: int = await _attack_damage(duel, 1000.0)
	_check(weak_dmg == int(base_dmg * 0.8),
		"虚弱：伤害 = 基线 ×0.8（实测 %d / %d）" % [weak_dmg, base_dmg])

	# —— B2. 易伤：敌人攻击 +25% ——
	_fresh(duel)
	duel.enemy_atk = 100
	duel.combat.enemy_deal_damage(100)
	var plain_hit: int = 1000 - int(duel.player_hp)
	_fresh(duel)
	duel.apply_debuff("vulnerable", 2)
	duel.combat.enemy_deal_damage(100)
	var vuln_hit: int = 1000 - int(duel.player_hp)
	_check(plain_hit == 100, "基线承伤 = 100（实测 %d）" % plain_hit)
	_check(vuln_hit == 125, "易伤：承伤 ×1.25（实测 %d）" % vuln_hit)

	# —— B3. 腐蚀：护盾收益 -25%，破甲解除 ——
	_fresh(duel)
	var shield_acc: Dictionary = duel.combat._new_acc()
	shield_acc["shield"] = 100
	await duel.combat._phase_defense(shield_acc)
	_check(int(duel.player_shield) == 100, "基线护盾 = 100（实测 %d）" % int(duel.player_shield))
	_fresh(duel)
	duel.apply_debuff("corrode")
	shield_acc = duel.combat._new_acc()
	shield_acc["shield"] = 100
	await duel.combat._phase_defense(shield_acc)
	_check(int(duel.player_shield) == 75, "腐蚀：护盾收益 ×0.75（实测 %d）" % int(duel.player_shield))
	duel.enemy_armor = 30
	duel.combat.on_counter("special")
	_check(not duel.debuffs.has("corrode"), "破甲（护甲清零）后腐蚀立即解除")
	_check(int(duel.enemy_armor) == 0, "破甲路径本身照常清甲")

	# —— B4. 禁疗：治疗 -50%（符号与消耗品两条路径）——
	_fresh(duel)
	duel.player_hp = 500
	var heal_acc: Dictionary = duel.combat._new_acc()
	heal_acc["heal"] = 100
	await duel.combat._phase_defense(heal_acc)
	_check(int(duel.player_hp) == 600, "基线治疗 = +100（实测 +%d）" % (int(duel.player_hp) - 500))
	_fresh(duel)
	duel.apply_debuff("heal_block", 1)
	duel.player_hp = 500
	heal_acc = duel.combat._new_acc()
	heal_acc["heal"] = 100
	await duel.combat._phase_defense(heal_acc)
	_check(int(duel.player_hp) == 550, "禁疗：治疗 ×0.5（实测 +%d）" % (int(duel.player_hp) - 500))
	duel.player_hp = 500
	duel.consumable_system.use_heal(load(HEAL_POTION))
	_check(int(duel.player_hp) == 515, "禁疗：治疗药剂 30 → 15（实测 %d）" % (int(duel.player_hp) - 500))

	# —— B5. 吸能：充能 -2，不低于 0 ——
	_fresh(duel)
	duel.charge_points = 5
	duel.apply_debuff("drain")
	_check(int(duel.charge_points) == 3, "吸能：充能 5 → 3（实测 %d）" % int(duel.charge_points))
	duel.charge_points = 1
	duel.apply_debuff("drain")
	_check(int(duel.charge_points) == 0, "吸能：充能不低于 0（实测 %d）" % int(duel.charge_points))

	# —— C1. 目盲：隐藏预览行 ——
	_fresh(duel)
	duel.readability.apply_preset("readable")
	var rs = duel.reel_system
	rs.begin_spin()
	rs._timer.stop()
	duel.hud._refresh_p1_previews()
	var preview_plain: bool = duel.hud.p1_preview_row.visible
	duel.apply_debuff("blind", 2)
	duel.hud._refresh_p1_previews()
	var preview_blind: bool = duel.hud.p1_preview_row.visible
	_check(preview_plain, "正常状态显示后续预览行")
	_check(not preview_blind, "目盲：隐藏后续预览")
	_check(duel.debuffs.preview_hidden(), "目盲提供统一的 preview_hidden() 查询")
	rs.finish_spin()

	# —— C2. 缠绕：手动停列必须按顺序；自动停轮不受限 ——
	_fresh(duel)
	duel.apply_debuff("entangle", 1, 1, {"order": "ltr"})
	rs.begin_spin()
	rs._timer.stop()
	rs.lock_reel(2)
	_check(not rs.is_absorbing(2) and not rs.reel_stopped[2], "缠绕：越序按停第 3 列被拒绝")
	rs.lock_reel(0)
	_check(rs.is_absorbing(0), "缠绕：允许按顺序停第 1 列")
	await get_tree().create_timer(0.45).timeout
	_check(rs.reel_stopped[0], "缠绕：第 1 列落子")
	rs.lock_reel(2)
	_check(not rs.is_absorbing(2), "缠绕：第 2 列未停时仍拒绝第 3 列")
	rs.lock_reel(1)
	await get_tree().create_timer(0.45).timeout
	_check(rs.reel_stopped[1], "缠绕：第 2 列落子")
	rs.lock_reel(2)
	await get_tree().create_timer(0.45).timeout
	_check(rs.reel_stopped[2], "缠绕：按顺序可依次停完三列（不软锁）")
	rs.finish_spin()
	# 自动停轮（forced）绕过顺序限制，避免夺轮/冻结叠加时死锁
	_fresh(duel)
	duel.apply_debuff("entangle", 1)
	rs.begin_spin()
	rs._timer.stop()
	rs.lock_reel(2, false, "forced")
	_check(rs.is_absorbing(2) or rs.reel_stopped[2], "缠绕：自动停轮不受停列顺序限制")
	rs.finish_spin()
	# 空格「停下一列」必须自动选中方向要求的那一列，不能反复撞被拒绝的列（Step 3 软锁修复）
	_fresh(duel)
	duel.apply_debuff("entangle", 1, 1, {"order": "rtl"})
	rs.begin_spin()
	rs._timer.stop()
	rs.stop_next_reel()
	_check(rs.is_absorbing(2) and not rs.is_absorbing(0), "缠绕 rtl：空格先停第 3 列（不会卡死）")
	await get_tree().create_timer(0.45).timeout
	rs.stop_next_reel()
	_check(rs.is_absorbing(1), "缠绕 rtl：下一次空格停第 2 列")
	await get_tree().create_timer(0.45).timeout
	rs.stop_next_reel()
	_check(rs.is_absorbing(0), "缠绕 rtl：最后一次空格停第 1 列")
	rs.finish_spin()

	# —— D. 反噬：连续同符号代价，换符号即结束 ——
	_fresh(duel)
	duel.turn_count = 7
	duel.debuffs.note_turn_symbols(duel, ["res://sym_a.tres", "res://sym_b.tres"])
	duel.apply_debuff("backlash", 1)
	duel.player_hp = 1000
	duel.turn_count = 8
	duel.debuffs.note_turn_symbols(duel, ["res://sym_a.tres"])
	_check(int(duel.player_hp) == 980, "反噬：连续同符号代价 2%% maxHP（实测 -%d）" % (1000 - int(duel.player_hp)))
	duel.debuffs.note_turn_symbols(duel, ["res://sym_a.tres"])
	_check(int(duel.player_hp) == 980, "反噬：同一回合不重复扣")
	duel.turn_count = 9
	duel.debuffs.note_turn_symbols(duel, ["res://sym_c.tres"])
	_check(not duel.debuffs.has("backlash"), "反噬：换符号后立即结束")
	duel.player_hp = 1
	duel.turn_count = 10
	duel.debuffs.note_turn_symbols(duel, ["res://sym_c.tres"])
	duel.apply_debuff("backlash", 1)
	duel.turn_count = 11
	duel.debuffs.note_turn_symbols(duel, ["res://sym_c.tres"])
	_check(int(duel.player_hp) >= 1, "反噬：代价不会直接致死（不制造死局）")

	# —— E. 剥增益 ——
	_fresh(duel)
	var sym := SymbolData.new()
	sym.label = "✦"
	sym.name = "测试增益"
	duel.player_buffs[sym] = 3
	duel.apply_debuff("strip")
	_check(duel.player_buffs.is_empty(), "剥增益：移除一个当前增益")
	duel.apply_debuff("strip")
	_check(duel.player_buffs.is_empty(), "剥增益：无增益时安全空放")

	# —— F. 持续与结束 ——
	# 新语义（Step 3 修正）：转轮前施加 → 本回合就吃一次，回合末 -1；
	# 结算中/敌人回合施加 → 从下一回合开始算，回合末不扣。
	_fresh(duel)
	duel.turn_count = 3
	duel.turn_resolved = false          # 回合开始相位（入场/回合钩子）
	duel.apply_debuff("weak", 1)
	duel.debuffs.tick_turn_end(duel)
	_check(not duel.debuffs.has("weak"), "1 回合减益：转轮前施加，本回合用完即结束")
	duel.turn_resolved = true           # 结算相位（受击/三连/破甲钩子）
	duel.apply_debuff("weak", 1)
	duel.debuffs.tick_turn_end(duel)
	_check(duel.debuffs.has("weak"), "1 回合减益：结算中施加，当回合末不扣")
	duel.turn_count = 4
	duel.turn_resolved = false
	duel.debuffs.tick_turn_end(duel)
	_check(not duel.debuffs.has("weak"), "1 回合减益：结算中施加，下回合末结束")
	duel.turn_resolved = true
	duel.apply_debuff("vulnerable", 2)
	duel.debuffs.tick_turn_end(duel)
	_check(duel.debuffs.has("vulnerable"), "2 回合减益：施加当回合末仍在")
	duel.turn_count = 5
	duel.turn_resolved = false
	duel.debuffs.tick_turn_end(duel)
	_check(duel.debuffs.has("vulnerable"), "2 回合减益：第 1 次倒计时后仍在")
	duel.turn_count = 6
	duel.debuffs.tick_turn_end(duel)
	_check(not duel.debuffs.has("vulnerable"), "2 回合减益：第 2 个回合末结束")
	duel.apply_debuff("corrode")
	duel.turn_count = 7
	duel.debuffs.tick_turn_end(duel)
	duel.turn_count = 8
	duel.debuffs.tick_turn_end(duel)
	_check(duel.debuffs.has("corrode"), "腐蚀：长时间持续，不按普通回合数衰减")
	var never_persist := true
	for id in ids:
		if String(duel.debuffs.DEFS[id]["kind"]) == "status" and id != "corrode":
			var t: int = int(duel.debuffs.DEFS[id].get("turns", 1))
			if t > 2:
				never_persist = false
	_check(never_persist, "除腐蚀（破甲/清净解除）外，状态类减益均在 ≤2 回合内自动结束")

	# —— G. 净化 / 清净分工 ——
	_fresh(duel)
	duel.apply_debuff("weak", 1)
	duel.apply_debuff("blind", 2)
	var purged: Array[String] = duel.debuffs.clear_interference(duel)
	_check(purged.has("目盲"), "净化：解除目盲（转轮干扰类）")
	_check(duel.debuffs.has("weak"), "净化：不越界解除虚弱（状态类）")
	var cleaned: Array[String] = duel.debuffs.clear_status(duel)
	_check(cleaned.has("虚弱"), "清净：解除虚弱（状态类）")
	_check(not duel.debuffs.has("blind"), "清净：不解转轮干扰（目盲已由净化解除）")
	# 真实消耗品路径保持原有反馈前缀
	_fresh(duel)
	duel.enemy_intent = {"data": duel.status_system.intent_def("jam"), "type": "jam", "value": 0}
	duel.apply_debuff("blind", 2)
	duel.consumable_system.use_purify(load(PURIFY_POTION))
	_check(not duel.debuffs.has("blind"), "净化药剂：同时解除目盲")
	_check(String(duel.hud.feedback_label.text).contains("净化：抵消注废"), "净化药剂：保留「净化：抵消注废」反馈")
	_fresh(duel)
	duel.apply_debuff("weak", 1)
	duel.apply_debuff("corrode")
	duel.consumable_system.use_cleanse(load(CLEANSE_POTION))
	_check(not duel.debuffs.has("weak") and not duel.debuffs.has("corrode"), "清净药剂：解除虚弱与腐蚀")
	_check(String(duel.hud.feedback_label.text).contains("清净："), "清净药剂：反馈标明解除内容")

	# —— H. 共用触发模块 ——
	_fresh(duel)
	var kit = TriggerKit.new({"triggers": [
		{"on": "enter", "debuff": "blind", "turns": 2},
		{"on": "first_spin", "debuff": "weak", "turns": 1},
		{"on": "first_hit", "debuff": "vulnerable", "turns": 2},
		{"on": "every", "n": 3, "debuff": "heal_block", "turns": 1},
		{"on": "armor_break", "debuff": "strip"},
		{"on": "phase", "hp": 0.4, "debuff": "drain"},
	]})
	duel.turn_count = 0
	_check(kit.fire("enter", duel) == 1 and duel.debuffs.has("blind"), "触发：入场生效")
	_check(kit.fire("enter", duel) == 0, "触发：入场只执行一次")
	duel.turn_count = 1
	_check(kit.fire("first_spin", duel) == 1 and duel.debuffs.has("weak"), "触发：首次转轮前生效")
	_check(kit.fire("first_spin", duel) == 0, "触发：首次转轮前只执行一次")
	_check(kit.fire("first_hit", duel) == 1 and duel.debuffs.has("vulnerable"), "触发：首次受击生效")
	_check(kit.fire("first_hit", duel) == 0, "触发：首次受击只执行一次")
	duel.turn_count = 2
	_check(kit.fire("every", duel) == 0, "触发：周期未到不触发")
	duel.turn_count = 3
	_check(kit.fire("every", duel) == 1 and duel.debuffs.has("heal_block"), "触发：周期（每 3 回合）生效")
	_check(kit.fire("every", duel) == 0, "触发：同一回合不重复触发")
	duel.enemy_hp_max = 100
	duel.enemy_hp = 100
	_check(kit.fire("phase", duel) == 0, "触发：阶段未到不触发")
	duel.enemy_hp = 39
	duel.charge_points = 5
	_check(kit.fire("phase", duel) == 1 and int(duel.charge_points) == 3, "触发：阶段（HP 40% 以下）生效且吸能落地")
	_check(kit.fire("phase", duel) == 0, "触发：同一阶段只执行一次")
	duel.player_buffs.clear()
	duel.player_buffs[sym] = 2
	_check(kit.fire("armor_break", duel) == 1 and duel.player_buffs.is_empty(), "触发：首次破甲生效（剥增益）")
	_check(kit.fire("armor_break", duel) == 0, "触发：首次破甲只执行一次")
	_check(kit.entry_count() == 6, "触发表解析：6 条全部接受")

	# —— I. HUD 提示 + 全局 RNG ——
	_fresh(duel)
	duel.apply_debuff("weak", 1)
	duel.apply_debuff("blind", 2)
	duel.apply_debuff("vulnerable", 2)
	var summary: String = duel.debuff_summary()
	_check(summary.contains("💢虚弱") and summary.contains("🌫目盲") and summary.contains("🩸易伤"),
		"HUD 状态行包含减益图标与名称（%s）" % summary)
	var detail: String = duel.debuffs.detail_text()
	_check(detail.contains("应对："), "HUD tooltip 含应对提示")
	duel.hud._refresh_meta()
	_check(String(duel.hud.player_buff_label.text).contains("💢虚弱"), "HUD 玩家状态行显示减益")
	seed(20261112)
	var expected: Array = []
	for _i in 16:
		expected.append(randi())
	seed(20261112)
	duel.debuffs.reset()
	duel.apply_debuff("weak", 1)
	duel.apply_debuff("vulnerable", 2)
	duel.apply_debuff("corrode")
	duel.apply_debuff("drain")
	duel.apply_debuff("blind", 2)
	duel.apply_debuff("entangle", 1)
	duel.apply_debuff("heal_block", 1)
	duel.apply_debuff("strip")
	duel.turn_count = 20
	duel.debuffs.tick_turn_end(duel)
	var _s: String = duel.debuffs.summary()
	var _d: String = duel.debuffs.detail_text()
	duel.hud._refresh_meta()
	duel.debuffs.clear_status(duel)
	duel.debuffs.clear_interference(duel)
	var after: Array = []
	for _i in 16:
		after.append(randi())
	_check(expected == after, "减益施加/计时/提示/HUD 全程不消耗全局 RNG")
