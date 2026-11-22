# RunSetup — 对局构建与 ante 难度曲线（P2 架构还债，2026-08-24 自 duel_controller 迁入）
# 运行时经 duel_controller preload 实例化（不注册全局 class_name——headless 测试环境不刷新类缓存）
extends RefCounted
# ============================================================================
# P2 架构还债（2026-08-24）：对局构建与 ante 难度曲线从 duel_controller 迁入。
# 职责：按 BalanceConfig 的 run_* 配置从全量房间池抽一局房序列（T25）、房间语义排序、
#       常规 BOSS 加权抽取（4 候选选 1）、ante 曲线纯函数（幕间台阶 × 幕内爬升）。
# 纯编排无自身状态；经 _ctrl 读 ALL_ROOMS / BALANCE / ROOMS。controller 留单行转发器，
# HUD / gimmick / 测试的既有调用面（_build_run/_ante_scale/_sort_rooms/_pick_boss）不变。
# ============================================================================

var _ctrl  # DuelController


func _init(ctrl) -> void:
	_ctrl = ctrl


# T25 房数重排（2026-08-09）：每幕按 run_act_layout 抽房（5 普通 + 2 精英 + 1 常规 BOSS 战 = 8 房），
# run_acts 幕共 24 房；常规 BOSS 按角色权重加权抽 1；真·最终独立于候选池，追加为整局最后一间。
func build_run() -> Array[RoomData]:
	var by_act := {}   # act -> {kind: [RoomData,...]}
	var final_boss: RoomData = null
	for r in _ctrl.ALL_ROOMS:
		if r.final_boss:
			if final_boss == null:
				final_boss = r
			continue
		var a = int(r.act)
		if not by_act.has(a):
			by_act[a] = {"normal": [], "elite": [], "boss": []}
		by_act[a][r.kind].append(r)
	var run: Array[RoomData] = []
	# 新版 M-02a：特殊房的受控 RNG——独立 RandomNumberGenerator，不消耗全局 RNG；
	# 用每局固定一次的 shop_run_seed 播种，保证同种子同输入下类型/内容可复现。
	var special_rng := RandomNumberGenerator.new()
	special_rng.seed = maxi(1, int(_ctrl.shop_run_seed) ^ 0x5A17)
	var used_events: Array = []   # §5：同一事件一局内不重复
	# M4-01：demo.act_only 时只跑 ACT1（ALL_ROOMS 已在 controller 侧收窄，这里再显式兜底）
	var acts := int(_ctrl.BALANCE.run_acts)
	if _ctrl.demo_active() and _ctrl.demo_config.act_only:
		acts = 1
	for a in range(1, acts + 1):
		if not by_act.has(a):
			continue
		var pools := {}   # kind -> 打乱后的候选（pop 逐个取用）
		for k in ["normal", "elite", "boss"]:
			var arr: Array = by_act[a][k].duplicate()
			arr.shuffle()
			pools[k] = arr
		for kind in _ctrl.BALANCE.run_act_layout:
			# M-02a（§10.1）：camp 是 Boss 前非战斗营地，不从怪物池抽取、不生成敌人。
			# 用内存哨兵 RoomData（不落 resources/rooms/，避免污染 ALL_ROOMS 的房数断言与 BOSS 抽取池）。
			if kind == "camp":
				run.append(_make_camp_room(a))
				continue
			# 新版 M-02a §2：第 3 房是宝箱或事件（非战斗），生成时冻结类型，内容由步骤 3 填充。
			if kind == "special":
				var sp: RoomData = _make_special_room(a, special_rng, used_events)
				run.append(sp)
				var sp_eid: String = String(sp.gimmick_params.get("id", ""))
				if sp_eid != "" and not used_events.has(sp_eid):
					used_events.append(sp_eid)
				continue
			if not pools.has(kind) or pools[kind].is_empty():
				continue
			var pick: RoomData = pick_boss(pools["boss"]) if kind == "boss" else pools[kind].pop_back()
			run.append(pick)
	if _ctrl.BALANCE.run_include_final_boss and final_boss != null:
		if not (_ctrl.demo_active() and _ctrl.demo_config.act_only):
			run.append(final_boss)
	return run


# M-02a（§10.1）：Boss 前营地哨兵房。纯内存构造，不进 resources/rooms/、不生成敌人。
# 所有战斗字段留空，start_room_data 依 kind=="camp" 前置分流到线性营地流程（非战斗节点）。
func _make_camp_room(act: int) -> RoomData:
	var r := RoomData.new()
	r.name = "营地"
	r.kind = "camp"
	r.act = act
	r.hp = 0
	r.atk = 0
	r.armor = 0
	r.element = "none"
	r.archetype = null
	r.intents = []
	r.gimmick_script = null
	r.mechanic_summary = "休整或整理，然后面对本幕 Boss"
	return r


# 新版 M-02a §2/§3：第 3 房宝箱或事件哨兵（非战斗）。纯内存构造，不落 resources/rooms/。
# 生成时冻结类型与具体内容到 gimmick_params（只读快照，展示/结算/日志共用），进入时才向玩家揭示。
func _make_special_room(act: int, rng: RandomNumberGenerator, used_events: Array = []) -> RoomData:
	var r := RoomData.new()
	var is_chest: bool = rng.randi_range(0, 1) == 0
	r.name = "宝箱" if is_chest else "事件"
	r.kind = "chest" if is_chest else "event"
	r.act = act
	r.hp = 0
	r.atk = 0
	r.armor = 0
	r.element = "none"
	r.archetype = null
	r.intents = []
	r.gimmick_script = null
	r.mechanic_summary = "特殊房（进入时揭示内容）"
	if is_chest:
		r.gimmick_params = _freeze_chest(act, rng)
	else:
		r.gimmick_params = _freeze_event(act, rng, used_events)
	return r


# §4：宝箱冻结一件合法物品（宝箱品质表，过滤本局已拥有武器/护符，消耗品可重复）。
# 空池走明确金币兜底并记录兜底率。冻结后不再变化，重复进入不会刷新。
func _freeze_chest(act: int, rng: RandomNumberGenerator) -> Dictionary:
	var exclude: Array = []
	exclude.append_array(_ctrl.run_weapon_inventory)
	exclude.append_array(_ctrl.selected_charms)
	var cat: Array = ["weapon", "passive", "active"]
	# T0-2：类别洗牌必须走特殊房专用 RNG，不消耗全局战斗/奖励随机流。
	# 用 Fisher-Yates 替代 Array.shuffle()（后者走全局 randomize() 流，会污染全局序列）。
	for i in range(cat.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = cat[i]
		cat[i] = cat[j]
		cat[j] = tmp
	for c in cat:
		var path: String = _ctrl._reward_system.pick_explore_loot(String(c), act, rng, exclude)
		if path != "":
			return {"special_kind": "chest", "category": String(c), "item_path": path, "fallback_gold": 0}
	# 空池兜底：金币（固定额，记录兜底）
	return {"special_kind": "chest", "category": "gold", "item_path": "",
		"fallback_gold": 15, "fallback": true}


# §5：事件冻结一个二选一（收益/代价/对象明确）。内置小表按 RNG 取，按幕过滤不合法项。
# 同一事件一局内不重复：由调用方在生成时按已用 id 过滤（见 build_run 的 used_events）。
func _freeze_event(act: int, rng: RandomNumberGenerator, used_events: Array = []) -> Dictionary:
	var pool: Array = _event_pool(act)
	var fresh: Array = []
	for ev in pool:
		if not used_events.has(String(ev.get("id", ""))):
			fresh.append(ev)
	pool = fresh
	if pool.is_empty():
		return {"special_kind": "event", "id": "none", "options": [], "empty": true}
	var ev: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	return {"special_kind": "event", "id": String(ev.get("id", "")),
		"options": (ev.get("options", []) as Array).duplicate(true), "empty": false}


# 事件定义（内置纯数据，不新增资源系统）。每个选项含收益/代价/对象，确认前可完整展示。
# 只做 HP/金币之间的交易，不做随机扣血/给物，不做纯数值填充。
func _event_pool(act: int) -> Array:
	var all: Array = [
		{"id": "blood_pact", "min_act": 1, "options": [
			{"label": "献祭生命换金币", "give": "hp", "give_amount": 15, "get": "gold", "get_amount": 30},
			{"label": "拒绝交易", "give": "", "give_amount": 0, "get": "", "get_amount": 0}]},
		{"id": "coin_pact", "min_act": 1, "options": [
			{"label": "付金币换最大生命", "give": "gold", "give_amount": 25, "get": "maxhp", "get_amount": 8},
			{"label": "拒绝交易", "give": "", "give_amount": 0, "get": "", "get_amount": 0}]},
		{"id": "ember_pact", "min_act": 2, "options": [
			{"label": "献祭生命换护盾", "give": "hp", "give_amount": 20, "get": "shield", "get_amount": 18},
			{"label": "拒绝交易", "give": "", "give_amount": 0, "get": "", "get_amount": 0}]},
	]
	var out: Array = []
	for ev in all:
		if act >= int(ev.get("min_act", 1)):
			out.append(ev)
	return out


# 常规 BOSS 抽取（4 候选选 1）：fixed 固定首领默认高权重、rotating 轮替随机、
# hidden 隐秘——「幕内全清后开启」在 BOSS 槽恒满足，故恒可入选。
func pick_boss(candidates: Array) -> RoomData:
	var weights: Dictionary = _ctrl.BALANCE.run_boss_weights
	var total := 0
	for c in candidates:
		total += int(weights.get(c.boss_role, 1))
	var roll: int = randi() % maxi(1, total)
	for c in candidates:
		roll -= int(weights.get(c.boss_role, 1))
		if roll < 0:
			return c
	return candidates[0]


# 房间序列排序：normal/elite 在前、boss 殿后（同档按 resource_path 稳定排序）。
func sort_rooms(rms: Array) -> Array:
	rms.sort_custom(func(a, b):
		var ra = _ctrl.ROOM_KIND_RANK.get(a.kind, 0)
		var rb = _ctrl.ROOM_KIND_RANK.get(b.kind, 0)
		if ra != rb:
			return ra < rb
		return a.resource_path < b.resource_path)
	return rms


# Ante 难度曲线纯函数：RoomData.hp/atk 视为基础值，按「幕间台阶 × 幕内爬升」缩放。
# act = RoomData.act（1/2/3）；幕内战斗序号 = 本房之前（含本房）同幕「实际战斗房」数 - 1。
# T0-6：幕内爬升只数战斗房（normal/elite/boss），宝箱/事件/营地不占强度序号；
#       Boss 作为幕末最后一个战斗房，自然取到本幕战斗序号基准，不因非战斗节点额外提高。
# M2：棋盘入口可显式传 ria_override（棋盘节点分配时已确定位置），线性路径传 -1 走战斗序号扫描。
func ante_scale(r: RoomData, idx: int, ria_override: int = -1) -> Dictionary:
	var rooms: Array[RoomData] = _ctrl.ROOMS
	var a = r.act
	var ria = ria_override   # battle-in-act：同幕内实际战斗序号（0 起）
	if ria < 0:
		ria = 0
		for i in range(idx + 1):
			if rooms[i].act != a:
				continue
			if _is_noncombat_kind(String(rooms[i].kind)):
				continue   # 宝箱/事件/营地不计入强度序号
			ria += 1
		ria -= 1
	return {
		"hp_scale": pow(_ctrl.BALANCE.ante_act_step_hp, a - 1) * pow(_ctrl.BALANCE.ante_room_step_hp, ria),
		"atk_scale": pow(_ctrl.BALANCE.ante_act_step_atk, a - 1) * pow(_ctrl.BALANCE.ante_room_step_atk, ria),
	}


# T0-6：非战斗房型（不占敌人强度序号）。与 ROOM_KIND_RANK 的 1 档一致，但显式列出避免偶合。
static func _is_noncombat_kind(kind: String) -> bool:
	return kind == "chest" or kind == "event" or kind == "camp"