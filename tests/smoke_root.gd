extends Node

# ============================================================================
# P1-A 冒烟基建 · L2 全流程驱动 + L3 BOSS 相位探针（场景入口，正常游戏启动路径）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/smoke_root.tscn
# （必须以「运行场景」而非 --script 启动：--script 模式不注册 SaveSystem autoload，
#   meta_store.gd 编译即失败；本场景方式下 autoload 完整、controller 依赖链可编译。）
#
# L2 固定种子三局：
#   Run A「生存局」（完全原生数值）——朴素策略的自然天花板基线；终局分支合法即可。
#   Run B「通关局」（神装 HP + 伤害 ×40）——必须打穿 24+1 房至元进度三选一（流程正确性）。
#   Run C「公平通关局」（仅神装 HP，伤害原生）——证明真实战斗链路能清空全部房型与常规 BOSS；
#       真·最终 P3 血锁走和解通道（探针策略：末房低血线时主动用腰带消耗品触发非暴力和解）。
# L3 十三个 gimmick 定向探针——压血跨相位阈值调 on_damaged，断言 _phase* 置位/保持 + 全钩子无崩溃。
#
# 断言三类：① 状态不变式（仅在 PLAYING 回合严格判定；WON/LOST 过渡回合允许击杀溢出负血）
# ② gimmick 相位单调翻转 ③ 经济收支非负与清房入账。汇总行前缀 SMOKE|。
# ============================================================================

const DEADLINE_MS := 300000
const TURN_BUDGET_NORMAL := 400
const TURN_BUDGET_ASSIST := 150
const GOD_HP := 1000000

var _fails := 0
var _checks := 0
var _t0 := 0
var _report: Array[String] = []


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	_run()


func _run() -> void:
	await get_tree().process_frame
	var duel: DuelController = await _boot()
	if duel == null:
		print("SMOKE|RESULT FAIL (boot)")
		get_tree().quit(2)
		return

	await _run_a_survival(duel)
	await _run_b_completion(duel)
	await _run_c_fair_completion(duel)
	_probe_all_bosses(duel)

	print("---")
	for line in _report:
		print(line)
	print("SMOKE|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	if get_tree().root.get_node_or_null("SaveSystem") == null:
		_fail("SaveSystem autoload 未注册（应随游戏启动存在）")
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	_check(scene_res != null, "duel.tscn 可加载")
	if scene_res == null:
		return null
	var duel: DuelController = scene_res.instantiate() as DuelController
	_check(duel != null, "duel 根节点为 DuelController")
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(duel.WEAPON_POOL.size() >= 20, "武器池已扫描（%d）" % duel.WEAPON_POOL.size())
	return duel


func _pick_weapons(duel: DuelController) -> Array[String]:
	var out: Array[String] = []
	for want in ["fire_sword", "holy_sword"]:
		for p in duel.WEAPON_POOL:
			if p.ends_with(want + ".tres"):
				out.append(p)
				break
	if out.size() >= 2:
		return out
	var scored: Array = []
	for p in duel.WEAPON_POOL:
		var w: WeaponData = load(p)
		scored.append([w.base_power if w != null else 0.0, p])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	out.clear()
	for s in scored.slice(0, 2):
		out.append(s[1])
	return out


func _setup_loadout(duel: DuelController) -> void:
	duel.selected_loadout.assign(_pick_weapons(duel))
	var consumables: Array[String] = []
	for want in ["heal_potion", "purify_potion"]:
		for p in duel.ITEM_POOL:
			if p.ends_with(want + ".tres"):
				consumables.append(p)
				break
	duel.selected_consumables.assign(consumables.slice(0, 2))
	duel.selected_charms.clear()
	for want in ["guard_charm", "sharp_charm"]:
		for p in duel.ITEM_POOL:
			if p.ends_with(want + ".tres"):
				duel.selected_charms.append(p)
				break
	if duel.selected_charms.is_empty() and not duel.ITEM_POOL.is_empty():
		duel.selected_charms.append(duel.ITEM_POOL[0])
	duel.selected_skills.clear()
	for want in ["recovery", "magic_bolt"]:
		for p in duel.SKILL_POOL:
			if p.ends_with(want + ".tres"):
				duel.selected_skills.append(p)
				break
	if duel.selected_skills.is_empty() and not duel.SKILL_POOL.is_empty():
		duel.selected_skills.append(duel.SKILL_POOL[0])
	duel._confirm_loadout()


func _god_hp(duel: DuelController) -> void:
	# 生存助推：只抬玩家血量上限（不改任何伤害结构；_start_room 不重置上限故跨房有效）
	duel.player_hp_max = GOD_HP
	duel.player_hp = GOD_HP


# ---------------------------------------------------------------- L2 驱动

func _run_a_survival(duel: DuelController) -> void:
	seed(101)
	_setup_loadout(duel)
	var res := await _drive_run(duel, false, false)
	var won: int = int(res["rooms_won"])
	_check(res["terminal"] in ["WON_GAME", "LOST"], "Run A 终局分支合法（%s @ 已胜%d房）" % [res["terminal"], won])
	_check(won >= 6, "Run A 朴素策略基线 ≥6 房（实测 %d——低于此值提示平衡或流程回归）" % won)


func _run_b_completion(duel: DuelController) -> void:
	seed(202)
	_setup_loadout(duel)
	_god_hp(duel)
	var orig: float = DuelController.BALANCE.player_dmg_mult
	var bal: Resource = DuelController.BALANCE   # 经变量中转赋值（const 链直接成员赋值会被解析器拒绝）
	bal.player_dmg_mult = orig * 40.0
	var res := await _drive_run(duel, true, true)
	bal.player_dmg_mult = orig
	_check(res["terminal"] == "WON_GAME",
		"Run B 打穿整局至元进度三选一（terminal=%s @ 已胜%d房）" % [res["terminal"], int(res["rooms_won"])])
	_check(int(res["rooms_total"]) >= 25, "Run B 房序列 24+真·最终（%d）" % int(res["rooms_total"]))


func _run_c_fair_completion(duel: DuelController) -> void:
	seed(303)
	_setup_loadout(duel)
	_god_hp(duel)
	var res := await _drive_run(duel, false, true)
	var won: int = int(res["rooms_won"])
	_check(res["terminal"] == "WON_GAME" or won >= 24,
		"Run C 公平通关（terminal=%s，已胜%d/25 房）" % [res["terminal"], won])


func _drive_run(duel: DuelController, assist: bool, god: bool) -> Dictionary:
	var out := {"terminal": "NONE", "rooms_won": 0, "rooms_total": duel.ROOMS.size()}
	var budget := TURN_BUDGET_ASSIST if assist else TURN_BUDGET_NORMAL
	var room_turns := 0
	var last_room := -999
	var just_won := false
	var gold_anchor := int(duel.gold)
	var anvil_anchor := int(duel.meta.get("anvil_points", 0))
	var phase_track := {}
	while not _deadline_hit():
		if duel.game_state == DuelController.FlowState.LOST:
			_log("ROOM|lost|%d|%s" % [duel.room_index + 1, duel.enemy_name])
			duel._on_overlay_button_pressed()      # 失败弹层 → 返回整备（真实路径）
			await get_tree().process_frame
			out["terminal"] = "LOST"
			break
		if duel.game_state == DuelController.FlowState.WON:
			if not just_won:
				_check(duel.enemy_hp <= 0 or duel.peaceful_win, "WON 时敌人死亡或和解（%s）" % duel.enemy_name)
				out["rooms_won"] = duel.room_index + 1
				_log("ROOM|won|%d|%s|%dturns|gold=%d%s" % [duel.room_index + 1, duel.enemy_name, int(duel.turn_count), int(duel.gold), "|peaceful" if duel.peaceful_win else ""])
				duel._on_reward_skip_pressed()
				await get_tree().process_frame
				if duel.in_interroom:
					just_won = true                # 清房 → 房间歇态（商店可选）
				elif duel._is_run_final(duel.room_index):
					out["terminal"] = "WON_GAME"   # 末房清完 → 元进度三选一已弹出
					break
				else:
					_fail("非末房 WON 后既无间歇态也非终局（房%d）" % (duel.room_index + 1))
					out["terminal"] = "BROKEN"
					break
			else:
				# 房间歇态：经济入账断言 + 进下一房
				var g2 := int(duel.gold)
				var a2 := int(duel.meta.get("anvil_points", 0))
				_check(g2 >= gold_anchor and a2 >= anvil_anchor,
					"清房入账非负（gold %+d, anvil %+d）" % [g2 - gold_anchor, a2 - anvil_anchor])
				gold_anchor = g2
				anvil_anchor = a2
				just_won = false
				duel._on_next_room_pressed()
				await get_tree().process_frame
				room_turns = 0
				last_room = -999
				phase_track.clear()
				if god:
					_god_hp(duel)                  # 神血随局保持（防跨局重置路径漏改）
			continue
		# —— PLAYING：打一个回合 ——
		if duel.in_interroom:
			_fail("PLAYING 与房间歇态互斥被破坏（房%d）" % (duel.room_index + 1))
			out["terminal"] = "BROKEN"
			break
		if duel.room_index != last_room:
			last_room = duel.room_index
			room_turns = 0
			budget = TURN_BUDGET_ASSIST if assist else TURN_BUDGET_NORMAL
			phase_track.clear()
			_track_init(duel, phase_track)
			_log("ROOM|enter|%d/%s|%s|HP%d" % [duel.room_index + 1, duel.ROOMS[duel.room_index].kind, duel.enemy_name, duel.enemy_hp_max])
		room_turns += 1
		if room_turns > budget:
			_fail("回合超预算卡死（房%d %s，assist=%s，已%d回合）" % [duel.room_index + 1, duel.enemy_name, str(assist), room_turns])
			out["terminal"] = "STUCK"
			break
		if god and duel._is_run_final(duel.room_index):
			_spam_consumables_for_peace(duel)      # 真·最终 P3 血锁 → 非暴力和解通道
		else:
			_auto_consume(duel)
		var t: String = await _play_one_turn(duel)
		if t != "OK":
			_fail("回合驱动异常 %s（房%d）" % [t, duel.room_index + 1])
			out["terminal"] = t
			break
		_check_invariants(duel, phase_track)
	if _deadline_hit():
		out["terminal"] = "DEADLINE"
		_fail("整体看门狗超时")
	return out


func _play_one_turn(duel: DuelController) -> String:
	duel._on_spin_pressed()
	var waited := 0
	while not _deadline_hit():
		if duel.reel_system.spinning:
			duel._on_spin_button_pressed()     # 每帧按一次停列（确定性节奏）
		elif not duel._busy:
			if waited > 400:
				print("PROBE|spin resolved after %d extra waits" % waited)
			return "OK"
		waited += 1
		if waited == 240:
			print("PROBE|WAIT spinning=%s busy=%s stopped=%s frozen=%s pend=%d/%d/%s/%s state=%s" % [
				str(duel.reel_system.spinning), str(duel._busy), str(duel.reel_system.reel_stopped),
				str(duel.frozen_cols), duel.pending_jam_reel, duel.pending_lock_reel,
				str(duel.pending_chaos), str(duel.pending_auto_stop), str(duel.game_state)])
		if waited == 480:
			print("PROBE|STALL confirmed — dump reel internals")
		await get_tree().process_frame
	return "DEADLINE"


func _auto_consume(duel: DuelController) -> void:
	# 最小生存策略：低血用治疗、干扰声明时用净化——走真实 consumable_system.use 链路
	if duel.player_hp < duel.player_hp_max * 4 / 10:
		if _use_first_effect(duel, "heal"):
			return
	var interfered: bool = duel.pending_jam_reel >= 0 or duel.pending_lock_reel >= 0 \
		or duel.pending_chaos or duel.pending_auto_stop
	if interfered:
		_use_first_effect(duel, "purify")


func _spam_consumables_for_peace(duel: DuelController) -> void:
	# 真·最终 P3：HP 锁 1 后普通伤害无法击杀，需以恢复/净化类消耗品达成非暴力和解——
	# 只刷「恢复/净化」两类（设计定义的和解触发物）；重转卷轴等会启动异步转轮的物品不在此列。
	if duel.enemy_hp > duel.enemy_hp_max * 3 / 10:
		return
	var snapshot := duel.consumable_slots.duplicate()
	for it in snapshot:
		var res: Resource = load(it["path"])
		if res == null or not (res.effect in ["heal", "purify", "cleanse"]):
			continue
		while duel.consumable_slots.has(it):
			duel.consumable_system.use(it["uid"])


func _use_first_effect(duel: DuelController, effect: String) -> bool:
	for it in duel.consumable_slots:
		var res: Resource = load(it["path"])
		if res != null and res.effect == effect:
			duel.consumable_system.use(it["uid"])
			return true
	return false
func _check_invariants(duel: DuelController, phase_track: Dictionary) -> void:
	# 仅在仍处于战斗的回合做严格界内断言；本回合内已翻 WON/LOST 的过渡回合允许溢出
	if duel.game_state == DuelController.FlowState.PLAYING:
		_check(duel.player_hp <= duel.player_hp_max and duel.player_hp >= 0, "玩家 HP 界内")
		_check(duel.enemy_hp >= 0 and duel.enemy_hp <= duel.enemy_hp_max,
			"敌人血量界内（%d/%d @%s）" % [duel.enemy_hp, duel.enemy_hp_max, duel.enemy_name])
	_check(duel.enemy_armor >= 0, "护甲非负")
	_check(duel.charge_points >= 0 and duel.charge_points <= int(DuelController.BALANCE.charge_max), "充能界内")
	_check(int(duel.gold) >= 0, "金币非负")
	_check(int(duel.meta.get("anvil_points", 0)) >= 0, "铁砧点非负")
	# 相位布尔单调：一旦翻 true 不许回 false（跨回合观察）
	if duel.current_gimmick == null:
		return
	for name in phase_track.keys():
		var now_v = duel.current_gimmick.get(name)
		if now_v == null:
			continue
		if bool(now_v) and not bool(phase_track[name]):
			phase_track[name] = true
			_log("PHASE|%s|%s→true" % [duel.current_gimmick.get_script().get_global_name(), name])
		elif not bool(now_v) and bool(phase_track[name]):
			_fail("相位回退 gimmick.%s true→false" % name)


func _track_init(duel: DuelController, track: Dictionary) -> void:
	track.clear()
	if duel.current_gimmick == null:
		return
	for p in duel.current_gimmick.get_script().get_script_property_list():
		if String(p.name).begins_with("_phase") and p.type == TYPE_BOOL:
			track[p.name] = bool(duel.current_gimmick.get(p.name))


# ---------------------------------------------------------------- L3 探针

func _probe_all_bosses(duel: DuelController) -> void:
	var bosses: Array[RoomData] = []
	for r in duel.ALL_ROOMS:
		if r.kind == "boss":
			bosses.append(r)
	_log("PROBE|count|%d" % bosses.size())
	for r in bosses:
		_probe_boss(duel, r)


func _probe_boss(duel: DuelController, r: RoomData) -> void:
	seed(7000 + int(r.act) * 100 + r.name.hash() % 97)
	duel._reset_run_state()
	var rooms: Array[RoomData] = [r]
	duel.ROOMS = rooms
	duel._build_pool(duel.selected_loadout)
	duel._start_room(0)
	duel.player_hp_max = GOD_HP
	duel.player_hp = GOD_HP
	duel.player_shield = 0
	var g = duel.current_gimmick
	_check(g != null, "%s gimmick 实例化" % r.name)
	if g == null:
		return
	var flipped := {}
	for i in 4:
		duel._begin_player_turn()
		duel.enemy_system.take_turn()
		_check(duel.player_hp >= 0, "%s 第%d轮敌攻后状态一致" % [r.name, i + 1])
		duel.player_hp = GOD_HP    # 探针专注相位机
	# 逐阈值压血：跨 _phase2/_phase3 血线后 on_damaged 应置位对应布尔（周期型无此字段则跳过）
	for stage in [["2", "_phase2_hp_ratio", "_phase2"], ["3", "_phase3_hp_ratio", "_phase3"]]:
		var ratio_v = g.get(stage[1])
		var flag: String = stage[2]
		if ratio_v == null or float(ratio_v) <= 0.0:
			continue
		duel.enemy_hp = maxi(1, int(float(duel.enemy_hp_max) * float(ratio_v)) - 1)
		g.on_damaged(duel, 5)
		var fv = g.get(flag)
		if fv != null:
			_check(bool(fv), "%s 跨越 %s → %s 置位" % [r.name, stage[1], flag])
			flipped[flag] = true
	g.on_special_triple(duel)
	if g.has_method("on_turn_resolved"):
		g.on_turn_resolved(duel)
	for i in 2:
		duel._begin_player_turn()
		duel.enemy_system.take_turn()
		duel.player_hp = GOD_HP
	for name in flipped.keys():
		var still = g.get(name)
		_check(still != null and bool(still), "%s %s 保持置位" % [r.name, name])
	_log("PROBE|ok|%s|phases=%s" % [r.name, ",".join(flipped.keys()) if not flipped.is_empty() else "cycle-only"])


# ---------------------------------------------------------------- 工具

func _log(line: String) -> void:
	_report.append("SMOKE|" + line)


func _deadline_hit() -> bool:
	return Time.get_ticks_msec() - _t0 > DEADLINE_MS


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("PASS  ", label)
	else:
		_fails += 1
		printerr("FAIL  ", label)


func _fail(label: String) -> void:
	_checks += 1
	_fails += 1
	printerr("FAIL  ", label)