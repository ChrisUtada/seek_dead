# 不注册全局 class_name：headless 测试/新检出环境不会自动刷新类缓存（与 run_setup 等子系统同约定）。
extends Resource

# ============================================================================
# M4-01 ACT1 Demo 配置（docs/ACT1试玩Demo_制作规划.md §4）
# 主工程即 demo 工程：只靠「开关 + 内容白名单」隔离，不新建工程、不写代码分叉。
# 启用条件（任一为真）：
#   1) 本资源 enabled = true            —— 编辑器 / F6 直接试玩；
#   2) 导出 preset 的 custom_features 含 feature_flag（默认 act1_demo）—— 独立 demo 构建。
# 关闭时所有池、房间与三幕流程保持正式版原样（「开关关闭即完整三幕」）。
# 白名单只做「收窄」：已拥有的池外内容不会被删除，只是在 demo 内不可选/不出现在池中。
# ============================================================================

@export var enabled: bool = false
@export var act_only: bool = true
@export var feature_flag: String = "act1_demo"

@export var weapon_pool: Array[String] = []
@export var skill_pool: Array[String] = []
@export var charm_pool: Array[String] = []
@export var consumable_pool: Array[String] = []


func is_active() -> bool:
	if enabled:
		return true
	return feature_flag != "" and OS.has_feature(feature_flag)


func allows_weapon(path: String) -> bool:
	return _set_of(weapon_pool).has(path)


func allows_skill(path: String) -> bool:
	return _set_of(skill_pool).has(path)


func allows_charm(path: String) -> bool:
	return _set_of(charm_pool).has(path)


func allows_consumable(path: String) -> bool:
	return _set_of(consumable_pool).has(path)


func filter_weapons(paths: Array) -> Array:
	return _subset(paths, _set_of(weapon_pool))


func filter_skills(paths: Array) -> Array:
	return _subset(paths, _set_of(skill_pool))


# ITEM_POOL 同时含护符与消耗品，按两者并集过滤。
func filter_items(paths: Array) -> Array:
	return _subset(paths, _set_of(charm_pool + consumable_pool))


func _subset(paths: Array, allowed: Dictionary) -> Array:
	var out := []
	for p in paths:
		if allowed.has(String(p)):
			out.append(p)
	return out


func _set_of(arr: Array) -> Dictionary:
	var s := {}
	for p in arr:
		s[String(p)] = true
	return s
