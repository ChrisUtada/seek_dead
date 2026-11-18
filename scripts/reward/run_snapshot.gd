class_name RunSnapshot
extends RefCounted

# 战后三选一重构 P0：奖励生成前的只读状态快照。
#
# 由 RunStateAnalyzer.capture(ctrl) 一次性构建；RewardEvaluator / DraftComposer
# 只读本快照，不直接扫描 Weapon/Symbol/Skill 等系统（契约 §3.6）。
#
# 字段只纳入项目真实存在、可可靠计算的数据；无法可靠计算的（如 estimated_threat）
# 留空/给默认值，不强造预测系统（v2.0 §6.1）。

var survival: Dictionary = {}     # current_hp, max_hp, hp_ratio, shield
var offense: Dictionary = {}      # 待 P1 填充（当前输出概要）
var economy: Dictionary = {}      # gold, consumable_slots, shop_distance
var progression: Dictionary = {}  # room_index, act, room_kind, boss_distance

var build_state: BuildState = null


func _init() -> void:
	build_state = BuildState.new()


# 便捷读取（避免调用方到处写 dictionary.get）。
func hp_ratio() -> float:
	return float(survival.get("hp_ratio", 1.0))


func gold() -> int:
	return int(economy.get("gold", 0))


func room_index() -> int:
	return int(progression.get("room_index", -1))


func room_kind() -> String:
	return String(progression.get("room_kind", ""))


# ===== BuildState：构筑状态 =====
class BuildState:
	extends RefCounted

	# 标签 → 强度（如 "element.fire" -> 2.0, "build.fire" -> 1.0）
	var tags: Dictionary = {}

	# 各来源对标签的贡献（P0 先建结构，P1/P3 填充）
	# weapon_contributions[tag] = 强度；symbol/skill/reward 同理
	var weapon_contributions: Dictionary = {}
	var symbol_contributions: Dictionary = {}
	var skill_contributions: Dictionary = {}
	var reward_contributions: Dictionary = {}

	# 构筑分数（如 "fire" -> 7），由各来源贡献汇总
	var build_scores: Dictionary = {}

	func tag_strength(tag: String) -> float:
		return float(tags.get(tag, 0.0))

	func build_score(key: String) -> int:
		return int(build_scores.get(key, 0))

	func has_tag(tag: String) -> bool:
		return tags.has(tag) and float(tags[tag]) > 0.0
