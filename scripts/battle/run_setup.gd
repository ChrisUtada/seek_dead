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
	for a in range(1, int(_ctrl.BALANCE.run_acts) + 1):
		if not by_act.has(a):
			continue
		var pools := {}   # kind -> 打乱后的候选（pop 逐个取用）
		for k in ["normal", "elite", "boss"]:
			var arr: Array = by_act[a][k].duplicate()
			arr.shuffle()
			pools[k] = arr
		for kind in _ctrl.BALANCE.run_act_layout:
			if pools[kind].is_empty():
				continue
			var pick: RoomData = pick_boss(pools["boss"]) if kind == "boss" else pools[kind].pop_back()
			run.append(pick)
	if _ctrl.BALANCE.run_include_final_boss and final_boss != null:
		run.append(final_boss)
	return run


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
# act = RoomData.act（1/2/3）；幕内位置 = 本房之前与本房同幕房数 - 1。
func ante_scale(r: RoomData, idx: int) -> Dictionary:
	var rooms: Array[RoomData] = _ctrl.ROOMS
	var a = r.act
	var ria = 0   # room-in-act：同幕内序号（0 起）
	for i in range(idx + 1):
		if rooms[i].act == a:
			ria += 1
	ria -= 1
	return {
		"hp_scale": pow(_ctrl.BALANCE.ante_act_step_hp, a - 1) * pow(_ctrl.BALANCE.ante_room_step_hp, ria),
		"atk_scale": pow(_ctrl.BALANCE.ante_act_step_atk, a - 1) * pow(_ctrl.BALANCE.ante_room_step_atk, ria),
	}