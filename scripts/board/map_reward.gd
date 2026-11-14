extends RefCounted

# ============================================================================
# MapReward — 新地图的奖励结算语义与合法性校验（Step 5A）
# 规格：docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md
#       §6 Step 5A 任务 1–4 与出口、§3.2 路线收益
#
# 边界：
# - 只描述「一个节点被结算时会发生什么」，不直接改玩家状态（发放由上层执行）；
# - `chest` 与 `shop` 语义必须不同：宝箱免费授予，商店一律付费，绝不为兼容旧测试统一成宝箱；
# - 数值复用旧地图已冻结口径（宝箱折算 15 金、藏库空/已有折算 15 金、休整 25%、神龛 35%/12/15），
#   避免同一系统出现第二套数值；
# - 不引入新装备目录，所有 path 都必须指向现有 resources/ 资源。
# ============================================================================

# 与 duel_controller 的旧地图结算保持一致（_board_treasure / _board_armory / _board_rest / _board_shrine）。
const CHEST_GOLD := 15
const ARMORY_EMPTY_GOLD := 15
const REST_HEAL_PCT := 0.25
const SHRINE_HEAL_PCT := 0.35
const SHRINE_MAXHP_BONUS := 12
const SHRINE_WARD := 15

const TYPE_BATTLE := "battle"
const TYPE_ELITE := "elite"
const TYPE_BOSS := "boss"
const TYPE_CHEST := "chest"
const TYPE_ARMORY := "armory"
const TYPE_SHOP := "shop"
const TYPE_REST := "rest"
const TYPE_EVENT := "event"
const TYPE_PATH := "path"
const TYPE_START := "start"

const CONTENT_TYPES := [
	TYPE_BATTLE, TYPE_ELITE, TYPE_BOSS, TYPE_CHEST,
	TYPE_ARMORY, TYPE_SHOP, TYPE_REST, TYPE_EVENT,
]
const EXPLORE_TYPES := [TYPE_CHEST, TYPE_ARMORY, TYPE_SHOP, TYPE_REST, TYPE_EVENT]
const BATTLE_TYPES := [TYPE_BATTLE, TYPE_ELITE, TYPE_BOSS]

const SOURCE_OF := {
	TYPE_BATTLE: "room",
	TYPE_ELITE: "room",
	TYPE_BOSS: "room",
	TYPE_CHEST: "chest",
	TYPE_ARMORY: "armory",
	TYPE_SHOP: "shop",
	TYPE_REST: "rest",
	TYPE_EVENT: "event",
}

const MODE_GOLD := "gold"
const MODE_ITEM := "item"
const MODE_ACTIVE := "active"
const MODE_CHOOSE_ONE := "choose_one"
const MODE_PURCHASE := "purchase"
const MODE_HEAL := "heal"
const MODE_SHRINE := "shrine"
const MODE_BATTLE := "battle"
const MODE_NONE := "none"


# 结算计划：纯函数，只读节点字段，不改变任何状态。
static func plan(node: Dictionary) -> Dictionary:
	var type := String(node.get("type", ""))
	match type:
		TYPE_CHEST:
			var kind := String(node.get("treasure_kind", ""))
			var path := String(node.get("item_path", ""))
			if kind == "gold" or path == "":
				return {
					"mode": MODE_GOLD, "free": true,
					"amount": int(node.get("gold_amount", CHEST_GOLD)),
					"reason": "宝箱折算金币",
				}
			if kind == "active":
				return {"mode": MODE_ACTIVE, "free": true, "category": kind, "path": path}
			return {"mode": MODE_ITEM, "free": true, "category": kind, "path": path}
		TYPE_ARMORY:
			var options: Array = node.get("armory_paths", [])
			return {
				"mode": MODE_CHOOSE_ONE, "free": true, "category": "weapon",
				"options": options.duplicate(),
				"fallback_gold": ARMORY_EMPTY_GOLD,
			}
		TYPE_SHOP:
			return {
				"mode": MODE_PURCHASE, "free": false, "category": "shop",
				"stock": (node.get("shop_stock", []) as Array).duplicate(),
				"pricing": "shop",
			}
		TYPE_REST:
			return {
				"mode": MODE_HEAL, "free": true,
				"pct": float(node.get("rest_heal_pct", REST_HEAL_PCT)),
			}
		TYPE_EVENT:
			return {
				"mode": MODE_SHRINE, "free": true,
				"kind": String(node.get("shrine_kind", "")),
				"value": int(node.get("shrine_value", 0)),
			}
		TYPE_BATTLE, TYPE_ELITE, TYPE_BOSS:
			return {"mode": MODE_BATTLE, "free": false, "room": node.get("room")}
	return {"mode": MODE_NONE, "free": true}


# 右侧栏 / 日志用的一句话说明，必须写出具体数值或具体结果。
static func describe(p: Dictionary) -> String:
	match String(p.get("mode", "")):
		MODE_GOLD:
			return "%s +%d 金" % [String(p.get("reason", "折算金币")), int(p.get("amount", 0))]
		MODE_ITEM:
			return "获得%s：%s" % [String(p.get("category", "")), String(p.get("path", ""))]
		MODE_ACTIVE:
			return "获得消耗品：%s" % String(p.get("path", ""))
		MODE_CHOOSE_ONE:
			var n: int = (p.get("options", []) as Array).size()
			return "武器藏库：%d 选 1（放弃则 +%d 金）" % [n, int(p.get("fallback_gold", 0))]
		MODE_PURCHASE:
			return "商店：%d 件在售，需付费购买" % (p.get("stock", []) as Array).size()
		MODE_HEAL:
			return "休整：恢复最大 HP 的 %d%%" % int(round(float(p.get("pct", 0.0)) * 100.0))
		MODE_SHRINE:
			var k := String(p.get("kind", ""))
			var v := int(p.get("value", 0))
			if k == "heal":
				return "神龛：恢复 %d HP" % v
			if k == "maxhp":
				return "神龛：最大 HP +%d" % v
			if k == "ward":
				return "神龛：下场战斗 +%d 护盾" % v
			return "神龛：金币 +%d" % CHEST_GOLD
		MODE_BATTLE:
			var room = p.get("room")
			return "战斗：%s" % ("未知房间" if room == null else String(room.name))
	return ""


static func is_free(p: Dictionary) -> bool:
	return bool(p.get("free", true))


# 出口「地图没有空类型、伪装备来源或落空奖励」的可判定形式。
# 返回错误字符串数组，空数组代表合规。
static func validate(board: Dictionary) -> Array:
	var errs: Array = []
	for node in board.get("nodes", []):
		var id := String(node.get("id", "?"))
		var type := String(node.get("type", ""))
		if type == TYPE_PATH or type == TYPE_START:
			continue
		if type == "":
			errs.append("%s 是空类型内容节点" % id)
			continue
		if not CONTENT_TYPES.has(type):
			errs.append("%s 类型 %s 不在注册表" % [id, type])
			continue
		if String(node.get("source", "")) != String(SOURCE_OF.get(type, "")):
			errs.append("%s 的 source=%s 与该类型真实来源 %s 不符（伪来源）"
				% [id, String(node.get("source", "")), String(SOURCE_OF.get(type, ""))])
		match type:
			TYPE_BATTLE, TYPE_ELITE, TYPE_BOSS:
				if node.get("room") == null:
					errs.append("%s 战斗节点没有 RoomData" % id)
			TYPE_CHEST:
				errs.append_array(_validate_chest(id, node))
			TYPE_ARMORY:
				errs.append_array(_validate_armory(id, node))
			TYPE_SHOP:
				errs.append_array(_validate_shop(id, node))
			TYPE_REST:
				if float(node.get("rest_heal_pct", 0.0)) <= 0.0:
					errs.append("%s 休整缺少回血比例（落空奖励）" % id)
				if String(node.get("item_path", "")) != "" or not (node.get("armory_paths", []) as Array).is_empty():
					errs.append("%s 休整不得携带装备（伪来源）" % id)
			TYPE_EVENT:
				errs.append_array(_validate_event(id, node))
	return errs


static func _validate_chest(id: String, node: Dictionary) -> Array:
	var errs: Array = []
	var kind := String(node.get("treasure_kind", ""))
	var path := String(node.get("item_path", ""))
	if kind == "":
		errs.append("%s 宝箱缺少 treasure_kind（落空奖励）" % id)
		return errs
	if kind == "gold":
		if path != "":
			errs.append("%s 金币宝箱不应带 item_path" % id)
		if int(node.get("gold_amount", 0)) <= 0:
			errs.append("%s 金币宝箱缺少 gold_amount（落空奖励）" % id)
		return errs
	if not (kind == "weapon" or kind == "charm" or kind == "active"):
		errs.append("%s 宝箱类别 %s 非法" % [id, kind])
		return errs
	if path == "":
		errs.append("%s 宝箱缺 item_path（落空奖励）" % id)
	elif not ResourceLoader.exists(path):
		errs.append("%s 宝箱物品不存在：%s（伪装备来源）" % [id, path])
	return errs


static func _validate_armory(id: String, node: Dictionary) -> Array:
	var errs: Array = []
	var paths: Array = node.get("armory_paths", [])
	if paths.size() != 2:
		errs.append("%s 武器藏库应为 2 选 1（实际 %d 项，落空奖励）" % [id, paths.size()])
	if paths.size() >= 2 and String(paths[0]) == String(paths[1]):
		errs.append("%s 武器藏库两把武器重复" % id)
	for p in paths:
		if not ResourceLoader.exists(String(p)):
			errs.append("%s 藏库武器不存在：%s（伪装备来源）" % [id, String(p)])
	if String(node.get("item_path", "")) != "":
		errs.append("%s 藏库不应复用 item_path" % id)
	return errs


static func _validate_shop(id: String, node: Dictionary) -> Array:
	var errs: Array = []
	var stock: Array = node.get("shop_stock", [])
	if stock.is_empty():
		errs.append("%s 商店没有冻结货架（落空奖励）" % id)
	var seen: Dictionary = {}
	for entry in stock:
		var p := String(entry.get("path", "")) if entry is Dictionary else ""
		if p == "":
			errs.append("%s 商店货架存在空条目" % id)
			continue
		if seen.has(p):
			errs.append("%s 商店货架重复：%s" % [id, p])
		seen[p] = true
		if not ResourceLoader.exists(p):
			errs.append("%s 商店在售物品不存在：%s（伪装备来源）" % [id, p])
	# 商店绝不能伪装成宝箱：不得带 chest 的赠予字段。
	if String(node.get("item_path", "")) != "" or not (node.get("armory_paths", []) as Array).is_empty():
		errs.append("%s 商店被伪装成宝箱（携带赠予字段）" % id)
	if bool(plan(node).get("free", true)):
		errs.append("%s 商店结算语义不能是免费" % id)
	return errs


static func _validate_event(id: String, node: Dictionary) -> Array:
	var errs: Array = []
	var kind := String(node.get("shrine_kind", ""))
	if not (kind == "heal" or kind == "maxhp" or kind == "ward"):
		errs.append("%s 事件缺少独立配置 shrine_kind（%s）" % [id, kind])
	if int(node.get("shrine_value", 0)) <= 0:
		errs.append("%s 事件缺少 shrine_value（落空奖励）" % id)
	if String(node.get("item_path", "")) != "" or not (node.get("armory_paths", []) as Array).is_empty():
		errs.append("%s 事件不得生成装备（伪来源）" % id)
	return errs
