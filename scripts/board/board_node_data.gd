extends RefCounted

# ============================================================================
# BoardNodeData — 棋盘节点静态数据的构造与展示映射（M2 灰盒，不注册 class_name）
#
# 节点在运行时以 Dictionary 保存（便于测试与状态快照）：
#   id / type / depth / act / next:Array[String]
#   room:RoomData（战斗节点）/ ria:int（幕内难度位置）/ battle_index:int（ROOMS 下标）
#   item_path:String（武器 / 护符格）/ title / desc / icon / final:bool
# 消耗状态由 BoardSystem.consumed 保存，不写入节点本身。
# ============================================================================

const TYPE_LABEL := {
	"start": "起点",
	"normal": "普通",
	"elite": "精英",
	"boss": "BOSS",
	"weapon": "武器",
	"charm": "护符",
	"shop": "商店",
	"rest": "休整",
	"treasure": "宝箱",
	"shrine": "神龛",
	"armory": "武器藏库",
}

const TYPE_ICON := {
	"start": "🚩",
	"normal": "⚔",
	"elite": "★",
	"boss": "👑",
	"weapon": "🗡",
	"charm": "📿",
	"shop": "🛒",
	"rest": "🔥",
	"treasure": "🎁",
	"shrine": "⛩",
	"armory": "🏛",
}

const TYPE_HINT := {
	"start": "本幕起点，无结算",
	"normal": "普通战斗 · 胜利后进入战后成长",
	"elite": "精英战斗 · 战后成长 + 精英掉落",
	"boss": "BOSS 战 · 专属战利品",
	"weapon": "提前可见的具体武器 · 落地直接获得",
	"charm": "提前可见的具体护符 · 落地入槽或折算",
	"shop": "现有商店 · 离开后节点消耗",
	"rest": "恢复 25% 最大 HP · 满血显示无需休整",
	"treasure": "宝箱 · 落地开启 · 类别开局公开，具体物品开启时揭晓",
	"shrine": "神龛 · 落地生效 · 效果开局公开",
	"armory": "武器藏库 · 落地二选一 · 两把武器开局公开",
}


static func make(id: String, type: String, depth: int) -> Dictionary:
	return {
		"id": id,
		"type": type,
		"depth": depth,
		"act": 1,
		"next": [],
		"room": null,
		"ria": -1,
		"battle_index": -1,
		"item_path": "",
		"title": "",
		"desc": "",
		"icon": String(TYPE_ICON.get(type, "•")),
		"final": false,
	}


static func is_battle(type: String) -> bool:
	return type in ["normal", "elite", "boss"]


static func label(type: String) -> String:
	return String(TYPE_LABEL.get(type, type))


static func icon(type: String) -> String:
	return String(TYPE_ICON.get(type, "•"))


static func hint(type: String) -> String:
	return String(TYPE_HINT.get(type, ""))


# 节点按钮上的极短标签（48×34 像素、单行）：图标 + 单字/双字。
static func short_label(type: String) -> String:
	match type:
		"normal": return "⚔ 普"
		"elite": return "★ 精"
		"boss": return "👑 王"
		"weapon": return "🗡 武"
		"charm": return "📿 符"
		"shop": return "🛒 店"
		"rest": return "🔥 休"
		"treasure": return "🎁 宝"
		"shrine": return "⛩ 龛"
		"armory": return "🏛 库"
		"start": return "🚩 起"
	return String(TYPE_ICON.get(type, "•"))


static func display_title(node: Dictionary) -> String:
	var t := String(node.get("type", ""))
	if node.get("title", "") != "":
		return "%s %s" % [icon(t), String(node["title"])]
	return "%s %s" % [icon(t), label(t)]


static func display_desc(node: Dictionary) -> String:
	if node.get("desc", "") != "":
		return String(node["desc"])
	return hint(String(node.get("type", "")))
