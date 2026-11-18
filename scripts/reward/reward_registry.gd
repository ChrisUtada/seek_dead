class_name RewardRegistry
extends RefCounted

# 战后三选一重构 P0 · 核心①：奖励注册、查询、标签索引与数据校验。
#
# 数据源：resources/rewards/defs/ 下的 RewardDefinition .tres。
# 用 ResourceScan.scan_resources（内部 ResourceLoader.list_directory，导出安全，项目铁律 9）。
# 加新卡 = 放一个 .tres，不改本文件、不碰全局注册表。
#
# 本模块是无状态 static 工具：不持有 ctrl、不修改任何玩家数据。

const DEFS_FOLDER := "res://resources/rewards/defs/"


# 加载全部定义（含非法项，交给 validate_all 报告）。
static func load_all() -> Array[RewardDefinition]:
	var resources := ResourceScan.scan_resources(DEFS_FOLDER, "RewardDefinition")
	var out: Array[RewardDefinition] = []
	for r in resources:
		if r is RewardDefinition:
			out.append(r)
	return out


# 仅返回校验通过的定义。
static func load_valid() -> Array[RewardDefinition]:
	var out: Array[RewardDefinition] = []
	for def in load_all():
		if def.validate().is_empty():
			out.append(def)
	return out


# 返回 {def_id -> [error,...]}，空字典 = 全部合法。供 P0 测试与开发日志。
static func validate_all() -> Dictionary:
	var problems: Dictionary = {}
	for def in load_all():
		var errors := def.validate()
		if not errors.is_empty():
			problems[def.id] = errors
	return problems


static func by_id(id: String) -> RewardDefinition:
	for def in load_all():
		if def.id == id:
			return def
	return null


# 按标签取候选（标签索引的轻量实现：P0 直接遍历，卡池变大后再建索引）。
static func with_tag(tag: String) -> Array[RewardDefinition]:
	var out: Array[RewardDefinition] = []
	for def in load_valid():
		if def.has_tag(tag):
			out.append(def)
	return out


static func count() -> int:
	return load_all().size()
