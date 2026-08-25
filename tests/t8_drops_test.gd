extends Node

# ============================================================================
# T8 掉落渠道 · headless 回归（场景入口，工程约束同 smoke_root）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t8_drops_test.tscn
#
# 覆盖（docs/装备收集规划_200.md §12.1）：
# ① 共享获取权重分布：按候选构成解析期望对照频数；epic 占比 <5%；排除 BOSS 信物；
# ② 普通房掉落概率 ≈ 0.12，授予必为 active 消耗品；腰带满折金币（奇数试预填满覆盖兜底分支）；
# ③ 精英房保底 1 护符：同一局内前 3 次免费开槽入槽（CHARM_CAP=3），此后转金币；永不掉信物；
# ④ BOSS 房不经掉落渠道。
# ============================================================================

const NORMAL_TRIALS := 300
const ELITE_TRIALS := 60
const PICK_TRIALS := 4000

var _fails := 0
var _checks := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var duel: DuelController = await _boot()
	if duel == null:
		print("RESULT FAIL (boot)")
		get_tree().quit(2)
		return

	_part_a_weighted_distribution(duel)
	await _part_b_normal_drop_rate(duel)
	_part_c_elite_guarantee(duel)
	_part_d_boss_isolated(duel)
	_part_e_reward_belt_guard(duel)

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	return duel


func _room_of_kind(duel: DuelController, kind: String) -> RoomData:
	for r in duel.ALL_ROOMS:
		if r.kind == kind and not r.final_boss and r.boss_relic_path == "":
			return r
	return duel.ALL_ROOMS[0]


func _passive_candidates(duel: DuelController) -> Array[String]:
	var relics: Array = duel._reward_system.relic_paths()
	var cand: Array[String] = []
	for p in duel.ITEM_POOL:
		if p in relics:
			continue
		var res: Resource = load(p)
		if res != null and res.get("category") == "passive":
			cand.append(p)
	return cand


func _setup_room(duel: DuelController, r: RoomData) -> void:
	duel._reset_run_state()
	var rooms: Array[RoomData] = [r]
	duel.ROOMS = rooms
	duel._build_pool(duel.selected_loadout)
	duel._start_room(0)


# ① 共享获取权重分布：观察频数 vs 候选构成解析期望（±max(25, 10%)）；epic 占比 <5%
func _part_a_weighted_distribution(duel: DuelController) -> void:
	seed(8001)
	var cand := _passive_candidates(duel)
	_check(cand.size() >= 20, "精英护符候选 ≥20（排除信物后 %d）" % cand.size())
	var tally := {"common": 0, "uncommon": 0, "rare": 0, "epic": 0}
	var expect := {"common": 0.0, "uncommon": 0.0, "rare": 0.0, "epic": 0.0}
	var total_w := 0.0
	for p in cand:
		var res: Resource = load(p)
		var r: String = String(res.get("rarity"))
		expect[r] += float(DuelController.BALANCE.acquisition_weight.get(r, 100))
		total_w += float(DuelController.BALANCE.acquisition_weight.get(r, 100))
	for k in expect.keys():
		expect[k] = expect[k] / total_w * float(PICK_TRIALS)
	for i in PICK_TRIALS:
		var path: String = duel._reward_system.acq_weighted_pick(cand)
		var res: Resource = load(path)
		tally[String(res.get("rarity"))] += 1
	for k in tally.keys():
		var tol: float = maxf(25.0, float(expect[k]) * 0.10)
		_check(absf(float(tally[k]) - expect[k]) <= tol,
			"%s 频数符合期望（obs %d / exp %.0f）" % [k, tally[k], expect[k]])
	var epic_share: float = float(tally["epic"]) / float(PICK_TRIALS)
	_check(epic_share < 0.05, "epic 占比 <5%%（实测 %.1f%%）" % [epic_share * 100.0])


# ② 普通房掉落概率 + 授予类型 + 腰带满折算金币。
# 检测语义：偶数试（腰带清空）→ 掉落以 belt.size()>0 判定并校验 category；
# 奇数试（预填满 active）→ 掉落必折金币，以 gold delta 判定（不检腰带——预填物会污染计数）。
func _part_b_normal_drop_rate(duel: DuelController) -> void:
	seed(8002)
	var room := _room_of_kind(duel, "normal")
	var granted := 0
	var gold_converted := 0
	var cat_violations := 0
	var odd_trials := 0
	for i in NORMAL_TRIALS:
		_setup_room(duel, room)
		duel.consumable_slots.clear()
		var filler_path := ""
		if i % 2 == 1:
			odd_trials += 1
			for p in duel.ITEM_POOL:
				var pres: Resource = load(p)
				if pres != null and pres.get("category") == "active":
					filler_path = p
					break
			if filler_path != "":
				var filler: Resource = load(filler_path)
				while duel.consumable_slots.size() < duel.CONSUMABLE_CAP:
					duel._consumable_uid += 1
					duel.consumable_slots.append({"path": filler_path, "item_id": filler.item_id, "charges": 9, "uid": "c%d" % duel._consumable_uid})
		var g0 := int(duel.gold)
		duel._reward_system.apply_room_drops()
		if i % 2 == 0:
			if duel.consumable_slots.size() > 0:
				granted += 1
				for it in duel.consumable_slots:
					var res: Resource = load(it["path"])
					if res.get("category") != "active":
						cat_violations += 1
			elif int(duel.gold) > g0:
				gold_converted += 1   # 理论不走：空腰带必入袋；防御性计数
		else:
			if int(duel.gold) > g0:
				gold_converted += 1
			elif duel.consumable_slots.size() > duel.CONSUMABLE_CAP:
				cat_violations += 1   # 满腰带还硬塞 = 越界违规
	var rate: float = float(granted + gold_converted) / float(NORMAL_TRIALS)
	_check(cat_violations == 0, "普通房授予必为消耗品且不越界（违规 %d）" % cat_violations)
	_check(rate > 0.06 and rate < 0.18, "普通房掉落率 ≈12%%（实测 %.1f%%）" % [rate * 100.0])
	_check(gold_converted > 0, "腰带满折算金币路径被覆盖（%d 次）" % gold_converted)
# ③ 精英保底护符：同一局内连续清精英——首 3 次免费开槽入槽（CHARM_CAP=3），此后全部转金币；永不掉信物
func _part_c_elite_guarantee(duel: DuelController) -> void:
	seed(8003)
	var room := _room_of_kind(duel, "elite")
	var relics: Array = duel._reward_system.relic_paths()
	_setup_room(duel, room)   # 仅首试做整局重置：charm_max 随局保持，才能真实走到天花板分支
	var charm_grants := 0
	var gold_fallbacks := 0
	var relic_violations := 0
	for i in ELITE_TRIALS:
		if i > 0:
			duel._start_room(0)
		var c0: int = duel.selected_charms.size()
		var g0 := int(duel.gold)
		duel._reward_system.apply_room_drops()
		if duel.selected_charms.size() > c0:
			charm_grants += 1
			var p: String = duel.selected_charms[duel.selected_charms.size() - 1]
			if p in relics:
				relic_violations += 1
		elif int(duel.gold) > g0:
			gold_fallbacks += 1
		else:
			_fail("精英保底落空（第%d次：无护符也无金币）" % (i + 1))
	_check(relic_violations == 0, "精英掉落零信物（违规 %d）" % relic_violations)
	_check(charm_grants == 3, "开槽阶段恰发 3 枚护符（CHARM_CAP=3，实测 %d）" % charm_grants)
	_check(gold_fallbacks == ELITE_TRIALS - 3, "天花板后全部折算金币（%d/%d）" % [gold_fallbacks, ELITE_TRIALS - 3])


# ④ BOSS 房隔离：apply_room_drops 对 boss 房零副作用
func _part_d_boss_isolated(duel: DuelController) -> void:
	seed(8004)
	var room := _room_of_kind(duel, "boss")
	_setup_room(duel, room)
	var g0 := int(duel.gold)
	var b0 := duel.consumable_slots.size()
	var c0 := duel.selected_charms.size()
	duel._reward_system.apply_room_drops()
	_check(int(duel.gold) == g0 and duel.consumable_slots.size() == b0 and duel.selected_charms.size() == c0,
		"BOSS 房不掉落（走自身战利品）")


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

# ⑤ P-审计 P2：奖励卡消耗品腰带守卫——未满入腰带；满则折算金币（卖价），绝不溢出
func _part_e_reward_belt_guard(duel: DuelController) -> void:
	seed(8005)
	var room := _room_of_kind(duel, "normal")
	_setup_room(duel, room)
	duel.consumable_slots.clear()
	duel._reward_system._pick_item_reward("active")
	_check(duel.consumable_slots.size() == 1, "未满时奖励卡消耗品入腰带（%d）" % duel.consumable_slots.size())
	while duel.consumable_slots.size() < duel.CONSUMABLE_CAP:
		duel._consumable_uid += 1
		duel.consumable_slots.append({"path": duel.ITEM_POOL[0], "item_id": "filler", "charges": 9, "uid": "c%d" % duel._consumable_uid})
	var g0 := int(duel.gold)
	duel._reward_system._pick_item_reward("active")
	_check(duel.consumable_slots.size() == duel.CONSUMABLE_CAP, "满腰带不溢出（%d/%d）" % [duel.consumable_slots.size(), duel.CONSUMABLE_CAP])
	_check(int(duel.gold) > g0, "满腰带折算金币 +%d" % (int(duel.gold) - g0))
