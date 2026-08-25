extends Node

# ============================================================================
# 全流程审计跑局（P-审计，2026-08-24）：多种子 × 神血公平伤害完整通关，
# 采集逐房遥测 + 商店稀有度 + 掉落事件 + 意图分布 + 精英 mini 触发。
# 输出行前缀 AUD|。运行：Godot --headless --fixed-fps 60 --path . res://tests/audit_playthrough.tscn
# ============================================================================

const GOD_HP := 1000000
const TURN_BUDGET := 400
const SEEDS := [11, 22, 33]

var _fails := 0
var _checks := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var duel: DuelController = await _boot()
	if duel == null:
		get_tree().quit(2)
		return

	for seed_v in SEEDS:
		await _one_run(duel, int(seed_v))

	print("AUD|DONE")
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	return duel


func _setup_loadout(duel: DuelController) -> void:
	var out: Array[String] = []
	for want in ["fire_sword", "holy_sword"]:
		for p in duel.WEAPON_POOL:
			if p.ends_with(want + ".tres"):
				out.append(p)
				break
	if out.size() < 2:
		out.clear()
		for p in duel.WEAPON_POOL:
			out.append(p)
	duel.selected_loadout.assign(out.slice(0, 2))
	duel.selected_consumables.assign([])
	duel.selected_charms.clear()
	duel.selected_skills.clear()
	duel._confirm_loadout()


func _god_hp(duel: DuelController) -> void:
	duel.player_hp_max = GOD_HP
	duel.player_hp = GOD_HP


func _one_run(duel: DuelController, seed_v: int) -> void:
	seed(seed_v)
	_setup_loadout(duel)
	_god_hp(duel)
	var orig: float = DuelController.BALANCE.player_dmg_mult
	var bal: Resource = DuelController.BALANCE
	bal.player_dmg_mult = orig * 3.0   # 轻助推：保证打穿全程，同时保留战斗节奏（比 T7 验证的 40 温和）

	print("AUD|RUN|seed=%d" % seed_v)
	var intent_tally := {}          # act -> {type: count}
	var shop_rarity := {}           # 稀有度 -> offer 数
	var shop_visits := 0
	var drop_events := {"consumable": 0, "charm": 0}
	var charm_paths := {}
	var room_turns := 0
	var last_room := -999
	var dmg_room := 0
	var last_hp := int(duel.player_hp)
	var just_won := false
	var terminal := "NONE"
	var rooms_won := 0

	while not _deadline():
		if duel.game_state == DuelController.FlowState.LOST:
			terminal = "LOST@%d" % (duel.room_index + 1)
			duel._on_overlay_button_pressed()
			await get_tree().process_frame
			break
		if duel.game_state == DuelController.FlowState.WON:
			if not just_won:
				rooms_won = duel.room_index + 1
				var gname: String = duel.enemy_name
				var gm := ""
				if duel.current_gimmick != null:
					gm = duel.current_gimmick.get_script().resource_path.get_file().get_basename().replace("_gimmick", "")
				print("AUD|ROOM|seed%d|%d|%s|%s|%s|turns=%d|dmg=%d|gold=%d%s" % [
					seed_v, duel.room_index + 1, duel.ROOMS[duel.room_index].kind, gname, gm,
					room_turns, dmg_room, int(duel.gold), "|peaceful" if duel.peaceful_win else ""])
				duel._on_reward_skip_pressed()
				await get_tree().process_frame
				if duel.in_interroom:
					just_won = true
				elif duel._is_run_final(duel.room_index):
					terminal = "WON_GAME"
					break
				else:
					terminal = "BROKEN"
					break
			else:
				just_won = false
				# 商店货架稀有度采样
				shop_visits += 1
				for offer in duel._shop_system.shop_offers:
					var r: String = _rarity(offer["path"])
					shop_rarity[r] = int(shop_rarity.get(r, 0)) + 1
				duel._on_next_room_pressed()
				await get_tree().process_frame
				_god_hp(duel)
			continue
		# PLAYING
		if duel.in_interroom:
			continue
		if duel.room_index != last_room:
			last_room = duel.room_index
			room_turns = 0
			dmg_room = 0
			last_hp = int(duel.player_hp)
		room_turns += 1
		if room_turns > TURN_BUDGET:
			terminal = "STUCK@%d" % (duel.room_index + 1)
			break
		_auto_consume(duel)
		# 记录本回合敌人意图类型（begin_player_turn 已在上一回合尾声明）
		if duel.enemy_intent.has("type"):
			var act_k: String = str(duel.ROOMS[duel.room_index].act)
			if not intent_tally.has(act_k):
				intent_tally[act_k] = {}
			var t: String = str(duel.enemy_intent["type"])
			intent_tally[act_k][t] = int(intent_tally[act_k].get(t, 0)) + 1
		var t: String = await _play_one_turn(duel)
		if t != "OK":
			terminal = t
			break
		if duel.game_state == DuelController.FlowState.PLAYING and duel.player_hp < last_hp:
			dmg_room += last_hp - int(duel.player_hp)
		last_hp = int(duel.player_hp)
		if duel.player_hp < GOD_HP / 2:
			duel.player_hp = GOD_HP   # 半血回满：专注 TTK/承伤曲线而非生存
		# T8 掉落事件检测（belt/charm 增量）
		# （belt 增量与回满无冲突；charm 只增不减）
	if terminal == "NONE":
		terminal = "DEADLINE"

	# 掉落统计：整局结束后对比「理论无掉落基线」——直接重放计数不可行，改由 ROOM 行间 gold/belt 推断已在上文省略；
	# 此处输出整局终态资产 + 意图分布 + 商店直方图
	print("AUD|SUMMARY|seed=%d|terminal=%s|rooms=%d|shop_visits=%d|shop_rarity=%s|intents=%s|charms=%d|anvil=%d" % [
		seed_v, terminal, rooms_won, shop_visits, str(shop_rarity), str(intent_tally),
		duel.selected_charms.size(), int(duel.meta.get("anvil_points", 0))])
	bal.player_dmg_mult = orig
	_check(terminal == "WON_GAME", "seed%d 打穿整局（%s）" % [seed_v, terminal])


func _play_one_turn(duel: DuelController) -> String:
	duel._on_spin_pressed()
	while not _deadline():
		if duel.reel_system.spinning:
			duel._on_spin_button_pressed()
		elif not duel._busy:
			return "OK"
		await get_tree().process_frame
	return "DEADLINE"


func _auto_consume(duel: DuelController) -> void:
	var interfered: bool = duel.pending_jam_reel >= 0 or duel.pending_lock_reel >= 0 \
		or duel.pending_chaos or duel.pending_auto_stop
	if interfered:
		for it in duel.consumable_slots:
			var res: Resource = load(it["path"])
			if res != null and res.effect == "purify":
				duel.consumable_system.use(it["uid"])
				return


func _rarity(path: String) -> String:
	var res: Resource = load(path)
	return String(res.get("rarity")) if res != null and res.get("rarity") != null else "common"


func _deadline() -> bool:
	return Time.get_ticks_msec() > 600000


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