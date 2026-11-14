extends RefCounted

# ============================================================================
# MapNodeTypes — 14×9 新地图节点类型注册表与奖励来源映射
# 规格：docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md §6 Step 0.5 任务 2/3/4、§6 Step 5A
#
# 边界：
# - 与旧 `BoardNodeData` 的 11 种类型并存，旧入口与 g7_run3_test / loot_explore_test / g8_loadout_layout_test 不变；
# - 新地图的内容节点 `type` 必须在本注册表内，禁止空类型或伪造节点；
# - `legacy_type` 只用于 Step 5A 之前映射到既有结算函数，不作为第二套节点口径；
# - 所有探索字段都从现有 LootSourceTable / RewardSystem 取真实路径，同 seed 可复现。
# ============================================================================

# source = 真实奖励来源；settlement = 既有结算函数语义；legacy = 旧类型映射。
const TYPES := {
	"battle": {"label": "普通战斗", "source": "room", "settlement": "battle", "legacy": "normal", "icon": "⚔"},
	"elite":  {"label": "精英战",   "source": "room", "settlement": "battle", "legacy": "elite",  "icon": "★"},
	"boss":   {"label": "BOSS 战",  "source": "room", "settlement": "battle", "legacy": "boss",   "icon": "👑"},
	"chest":  {"label": "宝箱",     "source": "chest", "settlement": "treasure", "legacy": "treasure", "icon": "🎁"},
	"armory": {"label": "武器藏库", "source": "armory", "settlement": "armory", "legacy": "armory", "icon": "🏛"},
	"shop":   {"label": "商店",     "source": "shop", "settlement": "shop", "legacy": "shop", "icon": "🛒"},
	"rest":   {"label": "休整",     "source": "rest", "settlement": "rest", "legacy": "rest", "icon": "🔥"},
	"event":  {"label": "特殊事件", "source": "event", "settlement": "shrine", "legacy": "shrine", "icon": "⛩"},
}

# 非内容节点：通路与起点是地形，不计入注册表（Step 0.5 任务 2 只约束内容节点）。
const PATH := "path"
const START := "start"

# MapGrid 的 content → 注册表类型。treasure 4 个中固定 1 个为 armory，
# 按 cell_id 最小者选取，布局与 seed 都稳定可复现。
static func content_to_type(content: String, cell_id: int, armory_cell: int) -> String:
	match content:
		"start": return START
		"normal": return "battle"
		"elite": return "elite"
		"boss": return "boss"
		"shop": return "shop"
		"rest": return "rest"
		"shrine": return "event"
		"treasure": return "armory" if cell_id == armory_cell else "chest"
	return ""


static func is_registered(type: String) -> bool:
	return TYPES.has(type)


static func is_content(type: String) -> bool:
	return is_registered(type) or type == START


static func is_battle(type: String) -> bool:
	return type in ["battle", "elite", "boss"]


static func source_of(type: String) -> String:
	return String(TYPES.get(type, {}).get("source", ""))


static func legacy_of(type: String) -> String:
	return String(TYPES.get(type, {}).get("legacy", ""))


static func label_of(type: String) -> String:
	return String(TYPES.get(type, {}).get("label", type))


static func icon_of(type: String) -> String:
	return String(TYPES.get(type, {}).get("icon", "·"))


# Step 0.5 任务 3/4：按类型写入真实来源字段，禁止为兼容旧测试伪造来源。
# shop / rest 明确不生成装备路径；event 使用独立配置；chest 与 armory 走 chest 探索来源表。
static func fill_explore_fields(node: Dictionary, ctrl, act: int,
		rng: RandomNumberGenerator, used: Dictionary) -> void:
	var type := String(node["type"])
	node["source"] = source_of(type)
	match type:
		"chest":
			var kinds := ["weapon", "charm", "active"]
			var kind := String(kinds[rng.randi() % kinds.size()])
			var cat: String = String({"weapon": "weapon", "charm": "passive", "active": "active"}[kind])
			var path := String(ctrl._reward_system.pick_explore_loot(cat, act, rng, used.keys()))
			if path == "":
				kind = "gold"
				path = ""
			node["treasure_kind"] = kind
			node["item_path"] = path
			if path != "":
				used[path] = true
		"armory":
			var paths: Array = []
			for i in 2:
				var exclude: Array = paths.duplicate()
				exclude.append_array(ctrl.selected_loadout)
				var p := String(ctrl._reward_system.pick_explore_loot("weapon", act, rng, exclude))
				if p == "":
					break
				paths.append(p)
			node["armory_paths"] = paths
			for p in paths:
				used[String(p)] = true
		"shop", "rest":
			# 不伪装成宝箱：不写 treasure_kind / item_path / armory_paths。
			node["treasure_kind"] = ""
			node["item_path"] = ""
			node["armory_paths"] = []
		"event":
			var kinds := ["heal", "maxhp", "ward"]
			var kind := String(kinds[rng.randi() % kinds.size()])
			node["shrine_kind"] = kind
			node["shrine_value"] = int({"heal": 35, "maxhp": 12, "ward": 15}[kind])
			node["treasure_kind"] = ""
			node["item_path"] = ""
			node["armory_paths"] = []
