extends Node

# P0-FINAL 真·最终 Boss 致死前置拦截专项测试。
# 仅针对勇者的阴影：任何直击/穿透/DoT/元素爆发致死时先钳 HP=1 并进入 P3，
# 禁止归 0 击杀跳过和解；P3 停攻；三和解路径分别通关；奖励只在和解后出现；
# 不重复触发阶段、不消耗额外 RNG；其他 Boss 直接击杀行为不变。
# 隔离 APPDATA 运行。

const HEAL := "res://resources/symbols/heal.tres"
const POISON := "res://resources/symbols/poison.tres"   # kind=status，唯一无核心符号武器的三连和解通路

var _checks := 0
var _fails := 0

func _ready() -> void:
	await _run()
	print("P0FINAL|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("P0FINAL|FAIL|" + msg)

func _boot() -> DuelController:
	var scene: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	return duel

func _start_room(duel: DuelController, room_name: String):
	for r in duel.ALL_ROOMS:
		if String(r.name) == room_name:
			duel.ROOMS.clear()
			duel.ROOMS.append(r)
			duel.start_room_data(r, 0, 0, false)
			return duel.current_gimmick
	return null

func _run() -> void:
	var duel := await _boot()

	# 场景1：满血巨额直击（穿透）压到 0 → 钳 1、进 P3、不停攻验证
	var g = _start_room(duel, "勇者的阴影")
	duel.enemy_hp_max = 2916
	duel.enemy_hp = 2916
	duel.combat.apply_enemy_damage(99999, true)
	duel.apply_enemy_hp_floor()
	_check(duel.enemy_hp == 1, "满血巨额直击：HP 钳制为 1（不归 0）")
	_check(bool(g._phase2) and bool(g._phase3), "满血巨额直击：P2/P3 均进入")
	_check(String(duel.enemy_intent.get("type", "")) == "none", "满血巨额直击：P3 停攻（意图 none）")
	_check(near_one(duel.boss_atk_mult), "P3：boss_atk_mult 归 1")
	_check(not bool(duel.peaceful_win), "仅进入 P3 不算和解，不直接通关")
	# 阶段切换不重复触发：重复收口不应改变 HP 或阶段标志（幂等，且实现无 RNG 调用）
	var hp_after_first: int = duel.enemy_hp
	duel.apply_enemy_hp_floor()
	duel.apply_enemy_hp_floor()
	_check(duel.enemy_hp == hp_after_first and bool(g._phase3), "重复收口：HP 稳定、阶段不重复触发（无 RNG/幂等）")

	# 场景2：P2 中途直接致死
	_start_room(duel, "勇者的阴影")
	g = duel.current_gimmick
	duel.enemy_hp_max = 2916
	duel.enemy_hp = 600   # 约20.6%，在 P3 阈值之上
	duel.combat.apply_enemy_damage(99999, true)
	duel.apply_enemy_hp_floor()
	_check(duel.enemy_hp == 1, "P2 中途直击致死：HP 钳制为 1")
	_check(bool(g._phase3), "P2 中途直击致死：进入 P3")

	# 场景3：DoT 致死（不调 on_damaged 的旁路）
	_start_room(duel, "勇者的阴影")
	g = duel.current_gimmick
	duel.enemy_hp_max = 2916
	duel.enemy_hp = 600
	duel.enemy_status["burn"] = 500
	duel.combat.tick_status()
	duel.apply_enemy_hp_floor()
	_check(duel.enemy_hp == 1, "DoT 致死：HP 钳制为 1")
	_check(bool(g._phase3), "DoT 致死：进入 P3")

	# 场景4：元素爆发致死（走 evaluate 的 charge 释放路径）
	_start_room(duel, "勇者的阴影")
	g = duel.current_gimmick
	duel.enemy_hp_max = 2916
	duel.enemy_hp = 100   # 低于 burst(=437)，元素爆发一击致死
	duel.charge_points = duel.BALANCE.charge_max
	duel.combat.release_element_burst({"pending_enemy_pops": []})
	duel.apply_enemy_hp_floor()
	_check(duel.enemy_hp == 1, "元素爆发致死：HP 钳制为 1")
	_check(bool(g._phase3), "元素爆发致死：进入 P3")

	# 场景5：三种和解路径分别通关
	# a) 任意三连
	_start_room(duel, "勇者的阴影")
	g = duel.current_gimmick
	_to_p3(duel, g)
	g.on_special_triple(duel)
	_check(bool(duel.peaceful_win), "和解路径 a：任意三连通关")
	_check(duel.game_state == duel.FlowState.WON, "三连后 game_state=WON")
	# b) 治疗符号
	_start_room(duel, "勇者的阴影")
	g = duel.current_gimmick
	_to_p3(duel, g)
	duel.grid[0][0] = load(HEAL)
	g.on_turn_resolved(duel)
	_check(bool(duel.peaceful_win), "和解路径 b：治疗符号通关")
	# c) 恢复/净化消耗品
	_start_room(duel, "勇者的阴影")
	g = duel.current_gimmick
	_to_p3(duel, g)
	g.on_consumable_used(duel, "cleanse")
	_check(bool(duel.peaceful_win), "和解路径 c：净化消耗品通关")
	# 5b) 三列同符号即和解（口径 a 收口）——poison(status) 三列，走 on_turn_resolved。
	# 修前：on_turn_resolved 只认 heal，且 on_special_triple 仅在 acc[triple] 为真时回调
	#（status 三连不设 acc[triple]），故 poison_dagger 进 P3 无解 → 此例应为红。
	_start_room(duel, "勇者的阴影")
	g = duel.current_gimmick
	_to_p3(duel, g)
	for r in duel.REELS:
		duel.grid[r][0] = load(POISON)
	g.on_turn_resolved(duel)
	_check(bool(duel.peaceful_win), "和解口径 a：三列 poison(status) 同符号即和解")
	# 5c) 三列废铁不算和解（排除 trash/gold/miss）
	_start_room(duel, "勇者的阴影")
	g = duel.current_gimmick
	_to_p3(duel, g)
	for r in duel.REELS:
		duel.grid[r][0] = duel.TRASH_SYMBOL
	g.on_turn_resolved(duel)
	_check(not bool(duel.peaceful_win), "和解口径 a：三列废铁不触发和解")
	# 非恢复类不触发
	_start_room(duel, "勇者的阴影")
	g = duel.current_gimmick
	_to_p3(duel, g)
	g.on_consumable_used(duel, "attack")
	_check(not bool(duel.peaceful_win), "攻击消耗品不触发和解")

	# 场景6：和解前不通关/不发奖、和解后只结算一次（幂等）
	_start_room(duel, "勇者的阴影")
	g = duel.current_gimmick
	duel.enemy_hp_max = 2916
	duel.enemy_hp = 2916   # 满血，未进 P3
	_check(duel.game_state == duel.FlowState.PLAYING and not bool(duel.peaceful_win), "未进入 P3：仍在战斗中、无通关标志")
	duel.combat.apply_enemy_damage(99999, true)
	duel.apply_enemy_hp_floor()
	_check(duel.enemy_hp == 1, "致死前置拦截：先钳 1 未死亡")
	_check(duel.game_state == duel.FlowState.PLAYING and not bool(duel.peaceful_win), "进入 P3 但未和解：仍未通关、未发奖")
	_to_p3(duel, g)
	g.on_special_triple(duel)
	_check(bool(duel.peaceful_win) and duel.game_state == duel.FlowState.WON, "和解成功：状态 WON")
	g.on_special_triple(duel)   # 重复和解回调
	g.on_consumable_used(duel, "heal")
	_check(bool(duel.peaceful_win), "重复和解回调：标志保持 true（幂等，不二次结算）")

	# 场景7：其他 Boss 直接击杀行为不变（用普通 BOSS 房举例）
	var other = _first_non_shadow_boss(duel)
	if other != null:
		var g2 = _start_room(duel, String(other.name))
		duel.enemy_hp_max = 100
		duel.enemy_hp = 30
		duel.combat.apply_enemy_damage(9999, true)
		duel.apply_enemy_hp_floor()
		_check(duel.enemy_hp <= 0, "其他 Boss：直接击杀有效（不受 P0-FINAL 影响）")
		_check(int(g2.hp_floor(duel)) == -1, "其他 Boss：无血锁下限")

	# 场景8（P3 建池做实）：poison_dagger 单武器建池 → build_strips → 真实三列锁定 → 结算和解。
	# 负向三废铁已由 5c 覆盖，不再重复。W-01B（2026-11-26）起 poison_dagger 已迁移：
	# 状态符号 poison 离池、核心符号为毒牙（venom_bite，damage）。此处验证"迁移后仍可用三列同符号和解"的真实链路。
	var pd := ""
	for p in duel.WEAPON_POOL:
		if String(p).ends_with("poison_dagger.tres"):
			pd = String(p)
			break
	_check(pd != "", "poison_dagger 在武器池中存在")
	if pd != "":
		duel.selected_loadout.assign([pd])
		duel.selected_consumables.clear()
		duel.selected_charms.clear()
		duel.selected_skills.clear()
		duel._confirm_loadout()
		g = _start_room(duel, "勇者的阴影")
		# 建池做实：_start_room 内 _build_pool 已填 pool_items，这里显式重建带子。
		duel.reel_system.build_strips()
		var rs = duel.reel_system
		var status_cells := 0
		var venom_cells := 0
		for r in duel.REELS:
			var strip: Array = rs.reel_strips[r] if r < rs.reel_strips.size() else []
			for cell in strip:
				var sym = cell[0] if cell is Array else cell
				if sym == null:
					continue
				var k := String(sym.kind)
				if k == "status":
					status_cells += 1
				if String(sym.resource_path).ends_with("venom_bite.tres"):
					venom_cells += 1
		_check(status_cells == 0, "poison_dagger 建池：status 格已离池（实测 %d）" % status_cells)
		_check(venom_cells >= 3, "poison_dagger 建池：三条 strip 合计毒牙(damage) 格 >=3（实测 %d）" % venom_cells)
		# 打到 P3
		duel.enemy_hp_max = 100
		duel.enemy_hp = 66
		g.on_damaged(duel, 0)
		duel.enemy_hp = 19
		g.on_damaged(duel, 0)
		duel.enemy_hp = 1
		_check(bool(g._phase3), "poison_dagger 单武器：敌人被打到 P3")
		# 真实 spin → 目押锁定：走 begin_spin 正确初始化 cursor/stopped（既有 RNG，不在测试里新增），
		# 再把每列 cursor 对到毒牙格并 forced 锁定，spin_finished 后真实结算触发 on_turn_resolved。
		duel._busy = false
		duel._on_spin_pressed()
		await get_tree().process_frame
		for r in duel.REELS:
			var strip: Array = rs.reel_strips[r]
			var idx := -1
			for i in range(strip.size()):
				var cell = strip[i]
				var sym = cell[0] if cell is Array else cell
				if sym != null and String(sym.resource_path).ends_with("venom_bite.tres"):   # 迁移后 poison_dagger 的核心符号
					idx = i
					break
			_check(idx >= 0, "第 %d 列 strip 含毒牙(damage) 格" % (r + 1))
			if idx >= 0:
				rs.reel_cursor[r] = idx
			rs.lock_reel(r, false, "forced")
		# 等 spin_finished → 真实 evaluate（含演出等待）→ on_turn_resolved 全部跑完。
		# 以 game_state 离开 PLAYING 为完成信号，上限 180 帧（3s）兜底，避免固定帧数临界。
		for _i in range(180):
			await get_tree().process_frame
			if duel.peaceful_win or duel.game_state != duel.FlowState.PLAYING:
				break
		_check(bool(duel.peaceful_win), "poison_dagger P3：建池三列毒牙 真实 spin+结算后和解（无死局）")

	duel.queue_free()
	await get_tree().process_frame

func _to_p3(duel: DuelController, g) -> void:
	duel.enemy_hp_max = 100
	duel.enemy_hp = 66
	g.on_damaged(duel, 0)
	duel.enemy_hp = 19
	g.on_damaged(duel, 0)
	duel.enemy_hp = 1   # hp_floor 会锁 1

func _first_non_shadow_boss(duel: DuelController):
	for r in duel.ALL_ROOMS:
		if String(r.kind) == "boss" and String(r.name) != "勇者的阴影":
			return r
	return null

func near_one(v) -> bool:
	return absf(float(v) - 1.0) < 0.001
