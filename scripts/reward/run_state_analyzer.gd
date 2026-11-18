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


# P0：只建立结构，标签来源梳理见契约 §3.2。
# 武器/符号的实际元素从 resource_path load 后读 element 字段（P3 接入）。
static func _build_state(ctrl, bs: RunSnapshot.BuildState) -> void:
	# 火焰来源初始化（P0 不写入实际贡献，结构保留）
	bs.build_scores["fire"] = 0
	# 已学技艺（P0 仅登记，不参与火焰贡献——现有 8 技艺无火标签）
	if ctrl.growth != null:
		for pid in ctrl.growth.perk_ids:
			bs.skill_contributions[String(pid)] = float(bs.skill_contributions.get(String(pid), 0.0))
	# 已选装备路径（P0 仅登记）
	for path in ctrl.selected_loadout:
		bs.weapon_contributions[String(path)] = float(bs.weapon_contributions.get(String(path), 0.0))
