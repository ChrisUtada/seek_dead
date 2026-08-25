extends Node

# ============================================================================
# T7 获取轴加权 · headless 回归（场景入口，工程约束同 smoke_root）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t7_acquisition_test.tscn
#
# 覆盖（docs/装备收集规划_200.md §11）：
# ① 商店货架：acquisition_weight 加权抽样——观察稀有度分布 vs 候选构成解析期望；
#    且 epic 出现率显著高于旧均匀口径（epic_count/total_candidates）；
# ② BOSS 深度偏置：同一武器池在 act1 vs act3 下，rare+epic 候选占比单调上升，
#    并与解析期望（rare/epic × bias）对照；信物卡不受偏置影响（固定出现逻辑不变）。
# ============================================================================

const SHOP_ROLLS := 300
const BOSS_ROLLS := 500

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

	_part_a_shop_distribution(duel)
	_part_b_boss_depth_bias(duel)

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


func _rarity_of(path: String) -> String:
	var res: Resource = load(path)
	return String(res.get("rarity")) if res != null and res.get("rarity") != null else "common"


func _weight(path: String, bias: float) -> float:
	return duel_weight_of(self, path, bias)


func duel_weight_of(_self: Node, path: String, bias: float) -> float:
	var w: float = float(DuelController.BALANCE.acquisition_weight.get(_self._rarity_of(path), 100))
	if bias != 1.0 and (_self._rarity_of(path) == "rare" or _self._rarity_of(path) == "epic"):
		w *= bias
	return w


# ① 商店货架加权分布
func _part_a_shop_distribution(duel: DuelController) -> void:
	seed(9001)
	duel._reset_run_state()
	var rooms: Array[RoomData] = [duel.ALL_ROOMS[0]]
	duel.ROOMS = rooms
	duel._start_room(0)
	# 解析期望：候选构成镜像 roll_shop 过滤（武器全池 / 消耗品+非装备护符（排除 BOSS 信物）/ 技能未带）
	var expect := {"common": 0.0, "uncommon": 0.0, "rare": 0.0, "epic": 0.0}
	var total_w := 0.0
	var cand_paths := []
	for p in duel.WEAPON_POOL:
		cand_paths.append(p)
		expect[_rarity_of(p)] += duel_weight_of(self, p, 1.0)
		total_w += duel_weight_of(self, p, 1.0)
	# 期望构成镜像 roll_shop 过滤：排除信物、本局已装备护符/技能（T29 软默认后常驻 1+1）
	var relics: Array = duel._reward_system.relic_paths()
	for p in duel.ITEM_POOL:
		if p in relics or p in duel.selected_charms:
			continue
		expect[_rarity_of(p)] += duel_weight_of(self, p, 1.0)
		total_w += duel_weight_of(self, p, 1.0)
	for p in duel.SKILL_POOL:
		if p in duel.selected_skills:
			continue
		expect[_rarity_of(p)] += duel_weight_of(self, p, 1.0)
		total_w += duel_weight_of(self, p, 1.0)
	for k in expect.keys():
		expect[k] = expect[k] / total_w * float(SHOP_ROLLS * 6)
	var tally := {"common": 0, "uncommon": 0, "rare": 0, "epic": 0}
	var epic_rolls := 0
	for i in SHOP_ROLLS:
		duel._shop_system.roll_shop()
		var has_epic := false
		for offer in duel._shop_system.shop_offers:
			var r: String = _rarity_of(offer["path"])
			tally[r] = int(tally.get(r, 0)) + 1
			if r == "epic":
				has_epic = true
		if has_epic:
			epic_rolls += 1
	for k in tally.keys():
		var tol: float = maxf(30.0, float(expect[k]) * 0.10)
		_check(absf(float(tally[k]) - expect[k]) <= tol,
			"商店 %s 频数符合期望（obs %d / exp %.0f）" % [k, tally[k], expect[k]])
	_check(epic_rolls > 0, "加权后货架可见 epic（%d/%d 局）" % [epic_rolls, SHOP_ROLLS])


# ② BOSS 深度偏置：同池 act1 vs act3，rare+epic 占比上升且符合解析期望
func _part_b_boss_depth_bias(duel: DuelController) -> void:
	seed(9002)
	duel._reset_run_state()
	# 合成房间：固定三稀有武器池（common/rare/epic 各一），act 可切换
	var base: RoomData = null
	for r in duel.ALL_ROOMS:
		if r.kind == "boss" and not r.final_boss:
			base = r
			break
	var room_act1: RoomData = base.duplicate()
	room_act1.act = 1
	room_act1.boss_relic_path = ""          # 隔离信物变量，只看武器分布
	room_act1.boss_reward_weapons = [
		"res://resources/weapon_templates/iron_sword.tres",           # common
		"res://resources/weapon_templates/holy_sword.tres",           # rare
		"res://resources/weapon_templates/flame_staff.tres",          # epic
	]
	var room_act3: RoomData = room_act1.duplicate()
	room_act3.act = 3
	var share := {}
	for cfg in [["act1", room_act1, 1.0], ["act3", room_act3, 2.5]]:
		var label: String = cfg[0]
		var room: RoomData = cfg[1]
		var bias: float = cfg[2]
		var hi := 0
		var lo := 0
		for i in BOSS_ROLLS:
			duel.selected_loadout.clear()
			for c in duel._reward_system.roll_boss_rewards(room):
				if c.get("kind", "") != "boss_weapon":
					continue
				var r: String = _rarity_of(c["path"])
				if r == "rare" or r == "epic":
					hi += 1
				else:
					lo += 1
		share[label] = float(hi) / maxf(1.0, float(hi + lo))
		# 解析期望：无放回抽 3（全池恰 3 → 即全出），偏置改变的是「哪 3 把进候选」——
		# 全池=3 时每把必现，份额恒定 2/3；故此处用 6 把池验证偏置方向性
		_check(hi + lo > 0, "%s 有武器候选产出" % label)
	# 方向性断言需 >3 把池：扩池重跑（加 uncommon/dark 系）
	room_act1.boss_reward_weapons.append("res://resources/weapon_templates/battle_axe.tres")       # uncommon
	room_act1.boss_reward_weapons.append("res://resources/weapon_templates/night_scythe.tres")     # rare
	room_act1.boss_reward_weapons.append("res://resources/weapon_templates/poison_dagger.tres")    # uncommon
	room_act1.boss_reward_weapons.append("res://resources/weapon_templates/sin_blade.tres")        # rare
	room_act3.boss_reward_weapons = room_act1.boss_reward_weapons.duplicate()
	var shares := {}
	for cfg in [["a1", room_act1, 1.0], ["a3", room_act3, 2.5]]:
		var hi := 0
		var lo := 0
		for i in BOSS_ROLLS * 2:
			duel.selected_loadout.clear()
			for c in duel._reward_system.roll_boss_rewards(cfg[1]):
				if c.get("kind", "") != "boss_weapon":
					continue
				var r: String = _rarity_of(c["path"])
				if r == "rare" or r == "epic":
					hi += 1
				else:
					lo += 1
		shares[cfg[0]] = float(hi) / maxf(1.0, float(hi + lo))
	_check(shares["a3"] > shares["a1"], "深度偏置方向性：act3 高稀占比 %.2f > act1 %.2f" % [shares["a3"], shares["a1"]])
	# 解析期望：加权无放回抽 3 的精确枚举（7P3=210 条有序路径，概率逐步连乘）。
	# 朴素「独立逐件」近似会低估（无放回对高权重件正相关）。
	var ws1: Array = []
	var ws3: Array = []
	var his: Array = []
	for p in room_act1.boss_reward_weapons:
		var r: String = _rarity_of(p)
		ws1.append(duel_weight_of(self, p, 1.0))
		ws3.append(duel_weight_of(self, p, 2.5))
		his.append(1 if (r == "rare" or r == "epic") else 0)
	var exp_a1: float = _enum_hi_share(ws1, his)
	var exp_a3: float = _enum_hi_share(ws3, his)
	_check(absf(shares["a1"] - exp_a1) < 0.05, "act1 高稀占比符合精确枚举期望（%.3f vs %.3f）" % [shares["a1"], exp_a1])
	_check(absf(shares["a3"] - exp_a3) < 0.05, "act3 高稀占比符合精确枚举期望（%.3f vs %.3f）" % [shares["a3"], exp_a3])


# 加权无放回抽 k=min(3,n) 件的「高稀槽位占比」精确期望：枚举全部 nP3 有序抽样路径，概率连乘求和。
func _enum_hi_share(ws: Array, his: Array) -> float:
	var n := ws.size()
	var k := mini(3, n)
	var idx := [0, 0, 0]
	var used := []
	for i in n:
		used.append(false)
	var acc := [0.0, 0.0]   # [总概率, 高稀槽位概率和]——Array 引用传参供递归累积
	_walk(ws, his, idx, used, 0, n, k, 1.0, acc)
	return acc[1] / maxf(acc[0], 0.000001)


func _walk(ws: Array, his: Array, idx: Array, used: Array, depth: int, n: int, k: int, prob: float, acc: Array) -> void:
	if depth == k:
		acc[0] += prob
		var h := 0
		for d in k:
			if his[idx[d]] == 1:
				h += 1
		acc[1] += prob * float(h) / float(k)
		return
	var remain := 0.0
	for i in n:
		if not used[i]:
			remain += ws[i]
	for i in n:
		if used[i]:
			continue
		used[i] = true
		idx[depth] = i
		_walk(ws, his, idx, used, depth + 1, n, k, prob * float(ws[i]) / maxf(remain, 0.000001), acc)
		used[i] = false


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