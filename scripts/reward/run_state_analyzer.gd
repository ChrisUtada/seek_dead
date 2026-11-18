class_name RunStateAnalyzer
extends RefCounted

# 战后三选一重构 P0 · 核心②：从游戏状态生成只读 RunSnapshot / BuildState。
#
# 由 DraftComposer 在生成 Draft 前调用一次 capture(ctrl)；
# RewardEvaluator 只读快照，不直接扫 Weapon/Symbol/Skill（契约 §3.6）。
#
# P0 范围：只填项目真实存在、可可靠计算的字段（生存/经济/进度）。
# BuildState 的标签聚合先建结构；火焰标签的实际推导放 P3（契约 §7 残留问题 1：
# 现有 8 项技艺无火标签，首期 skill_contributions 火为 0，不为此新增技艺）。

const EPS := 0.0001


static func capture(ctrl) -> RunSnapshot:
	var snap := RunSnapshot.new()
	snap.survival = _capture_survival(ctrl)
	snap.economy = _capture_economy(ctrl)
	snap.progression = _capture_progression(ctrl)
	snap.offense = {}   # P1：当前输出概要
	_build_state(ctrl, snap.build_state)
	return snap


static func _capture_survival(ctrl) -> Dictionary:
	var hp_max := int(ctrl.player_hp_max)
	var hp := int(ctrl.player_hp)
	var ratio := float(hp) / float(maxi(1, hp_max))
	return {
		"current_hp": hp,
		"max_hp": hp_max,
		"hp_ratio": clampf(ratio, 0.0, 1.0),
		"shield": int(ctrl.player_shield),
		"run_shield_next": int(ctrl._reward_system.run_shield_next),
	}


static func _capture_economy(ctrl) -> Dictionary:
	var slots: Array = ctrl.consumable_slots if ctrl.consumable_slots != null else []
	return {
		"gold": int(ctrl.gold),
		"consumable_count": slots.size(),
		"consumable_capacity": int(ctrl.CONSUMABLE_CAP),
	}


static func _capture_progression(ctrl) -> Dictionary:
	var kind := ""
	var act := 1
	var rooms = ctrl.ROOMS
	if rooms != null and ctrl.room_index >= 0 and ctrl.room_index < rooms.size():
		var room = rooms[ctrl.room_index]
		if room != null:
			kind = String(room.kind)
			act = maxi(1, int(room.act))
	return {
		"room_index": int(ctrl.room_index),
		"act": act,
		"room_kind": kind,
		"boss_distance": -1,   # P3：房间类型序列推导
	}


# P3：从玩家真实拥有的武器/符号/技艺/已获奖励推导构筑标签与分数（契约 §3）。
# 贡献表（元素通用，fire/ice/poison/light/dark）：
#   元素武器 +3 / 元素符号 +1 每个 / 元素技艺 +2 / 已获该元素构筑奖励 +2
# 消耗品与临时 Buff 不参与（一次性/易变，不构成永久 Build）。
const ELEMENTS := ["fire", "ice", "poison", "light", "dark"]
const WEAPON_PTS := 3.0
const SYMBOL_PTS := 1.0
const SKILL_PTS := 2.0
const REWARD_PTS := 2.0


static func _build_state(ctrl, bs: RunSnapshot.BuildState) -> void:
	for elem in ELEMENTS:
		bs.build_scores[elem] = 0

	# ① 武器：从 selected_loadout 路径 load，读 element（已含武器自身元素化）
	for path in ctrl.selected_loadout:
		var wd: Resource = load(path) if String(path).begins_with("res://") else null
		if wd == null:
			continue
		var elem := String(wd.get("element"))
		if elem in ELEMENTS:
			bs.weapon_contributions[String(path)] = WEAPON_PTS
			_add_element(bs, elem, WEAPON_PTS)

	# ② 符号：从 pool_items 的 syms 三元组读 element（已含武器继承），每个符号 +1
	#    pool_items 元素格式：[SymbolData, weight, element, source_id, base_power]
	var pool: Array = ctrl.pool_items if ctrl.pool_items != null else []
	var counted_syms := {}
	for it in pool:
		var syms: Array = it.get("syms", []) if it is Dictionary else []
		for s in syms:
			if not (s is Array) or s.size() < 3:
				continue
			var elem := String(s[2])
			var sym = s[0]
			var key: String = String(sym.resource_path) if sym != null else str(syms.find(s))
			if elem in ELEMENTS and not counted_syms.has(String(key)):
				counted_syms[String(key)] = true
				var tag: String = "symbol." + elem
				bs.symbol_contributions[tag] = float(bs.symbol_contributions.get(tag, 0.0)) + SYMBOL_PTS
				_add_element(bs, elem, SYMBOL_PTS)

	# ③ 技艺：现有 8 项无元素标签 → 首期为 0（契约修正 D，不为此新增技艺）
	for pid in ctrl.growth.perk_ids if ctrl.growth != null else []:
		bs.skill_contributions[String(pid)] = 0.0

	# ④ 已获元素构筑奖励：从 controller 的 element_affinity 记录读取（P3 新字段）
	var affinity = ctrl.get("element_affinity")
	if affinity is Dictionary:
		for elem in ELEMENTS:
			var n := int(affinity.get(elem, 0))
			if n > 0:
				var tag: String = "reward." + elem
				bs.reward_contributions[tag] = float(n) * REWARD_PTS
				_add_element(bs, elem, float(n) * REWARD_PTS)

	# 把元素总分写成 tags（element.X + build.X）
	for elem in ELEMENTS:
		var score := int(bs.build_scores.get(elem, 0))
		if score > 0:
			bs.tags["element." + elem] = float(score)
			bs.tags["build." + elem] = float(score)


static func _add_element(bs: RunSnapshot.BuildState, elem: String, pts: float) -> void:
	bs.build_scores[elem] = float(bs.build_scores.get(elem, 0)) + pts
