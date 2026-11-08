extends RefCounted

# G6-03 局末路线总结：把本局「路线 / 成长 / 新收藏 / 下一局建议」压成 4 行短文本。
#
# 边界：
# - 只读本局状态与 meta 拥有池，不写存档、不改数值/奖励/掉落/RNG。
# - 收藏基线在每局 _reset_run_state 时快照，只存在内存。
# - 任一行返回空串表示该项没有可展示内容；展示顺序固定。

const SHAPE_LABEL := {"standard": "标准", "long_tail": "长尾", "long_share": "延展"}
const TEMPLATE_LABEL := {"standard": "常规", "mirror": "镜像", "elite_first": "精英前置",
	"elite_upper": "上路精英前置", "elite_lower": "下路精英前置"}
const MAX_NAMES := 3

var _ctrl
var _owned_weapons: Array[String] = []
var _owned_charms: Array[String] = []
var _owned_consumables: Array[String] = []


func _init(ctrl) -> void:
	_ctrl = ctrl


# 每局开始记录拥有池基线；局末用它算出「本局新收藏」。
func snapshot() -> void:
	_owned_weapons = _paths("owned_weapons")
	_owned_charms = _paths("owned_charms")
	_owned_consumables = _paths("owned_consumables")


func lines() -> Array[String]:
	var out: Array[String] = []
	for s in [route_line(), growth_line(), collection_line(), next_line()]:
		if String(s) != "":
			out.append(String(s))
	return out


# 本局路线：棋盘模式给骨架/模板/尾路主题/各节点计数；线性模式给房型计数与终局 BOSS。
func route_line() -> String:
	if _ctrl.node_mode and _ctrl.board != null and _ctrl.board.generated:
		var b = _ctrl.board
		var bits: Array[String] = []
		var shape := String(SHAPE_LABEL.get(String(b.shape_id), String(b.shape_id)))
		var tpl := String(TEMPLATE_LABEL.get(String(b.template_id), String(b.template_id)))
		if shape != "":
			bits.append(shape)
		if tpl != "":
			bits.append(tpl)
		var theme := _boss_element()
		if theme != "":
			bits.append(theme + "尾路")
		var counts := _board_count_text(b)
		if counts != "":
			bits.append(counts)
		return "路线：棋盘 · " + " · ".join(bits)

	var normal := 0
	var elite := 0
	var boss := 0
	for r in _ctrl.ROOMS:
		if r == null:
			continue
		var kind := String(r.kind)
		if kind == "normal":
			normal += 1
		elif kind == "elite":
			elite += 1
		elif kind == "boss":
			boss += 1
	var parts: Array[String] = []
	if normal > 0:
		parts.append("战斗%d" % normal)
	if elite > 0:
		parts.append("精英%d" % elite)
	if boss > 0:
		parts.append("BOSS%d" % boss)
	var txt := "路线：线性"
	if not parts.is_empty():
		txt += " · " + " ".join(parts)
	var bn := _boss_name()
	if bn != "":
		txt += " · 终局 " + bn
	return txt


# 本局成长：等级/技艺数 + 熟练（只列本局有结算的武器）+ 铭印方向。
func growth_line() -> String:
	var bits: Array[String] = []
	if _ctrl.growth != null:
		bits.append("Lv.%d" % int(_ctrl.growth.level))
		if not _ctrl.growth.perk_ids.is_empty():
			bits.append("技艺%d" % _ctrl.growth.perk_ids.size())
	var ms := _mastery_text()
	if ms != "":
		bits.append(ms)
	if _ctrl.mastery != null:
		var im := String(_ctrl.mastery.summary_line())
		if im != "" and im != "铭印：无":
			bits.append(im)
	if bits.is_empty():
		return ""
	return "成长：" + " · ".join(bits)


# 本局新收藏：与开局快照做差，最多列 3 件名称。
func collection_line() -> String:
	var new_paths: Array[String] = []
	for p in _paths("owned_weapons"):
		if not _owned_weapons.has(p):
			new_paths.append(p)
	for p in _paths("owned_charms"):
		if not _owned_charms.has(p):
			new_paths.append(p)
	for p in _paths("owned_consumables"):
		if not _owned_consumables.has(p):
			new_paths.append(p)
	if new_paths.is_empty():
		return "新收藏：无"
	var names: Array[String] = []
	for i in range(mini(MAX_NAMES, new_paths.size())):
		names.append(_display_name(new_paths[i]))
	var txt := "新收藏：" + "、".join(names)
	if new_paths.size() > MAX_NAMES:
		txt += " 等%d件" % new_paths.size()
	return txt


# 下一局建议：沿用生涯的下一目标；有定向解锁机会时一并提示。
func next_line() -> String:
	var bits: Array[String] = []
	if _ctrl._career != null:
		var goal := String(_ctrl._career.next_goal_hint())
		if goal != "":
			bits.append(goal)
		var charges := int(_ctrl._career.unlock_charges())
		if charges > 0:
			bits.append("还有 %d 次定向解锁" % charges)
	if bits.is_empty():
		bits.append("换一条尾路，试试不同元素组合")
	return "下一局建议：" + "；".join(bits)


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _paths(key: String) -> Array[String]:
	var out: Array[String] = []
	var arr: Array = _ctrl.meta.get(key, [])
	for p in arr:
		out.append(String(p))
	return out


func _board_count_text(b) -> String:
	var normal := 0
	var elite := 0
	var shop := 0
	var rest := 0
	var special := 0
	for id in b.consumed:
		var n: Dictionary = b.by_id.get(String(id), {})
		var t := String(n.get("type", ""))
		if t == "normal":
			normal += 1
		elif t == "elite":
			elite += 1
		elif t == "shop":
			shop += 1
		elif t == "rest":
			rest += 1
		elif t in ["weapon", "charm", "treasure", "shrine", "armory"]:
			special += 1
	var parts: Array[String] = []
	if normal > 0:
		parts.append("战斗%d" % normal)
	if elite > 0:
		parts.append("精英%d" % elite)
	if shop > 0:
		parts.append("商店%d" % shop)
	if rest > 0:
		parts.append("休整%d" % rest)
	if special > 0:
		parts.append("特殊%d" % special)
	return " ".join(parts)


func _mastery_text() -> String:
	if _ctrl.mastery == null:
		return ""
	var arr: Array = []
	for p in _ctrl.mastery.mastery:
		var pts := int(_ctrl.mastery.mastery[p])
		if pts > 0:
			arr.append({"path": String(p), "pts": pts})
	if arr.is_empty():
		return ""
	arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["pts"]) > int(b["pts"]))
	var names: Array[String] = []
	for i in range(mini(MAX_NAMES, arr.size())):
		var p := String(arr[i]["path"])
		names.append("%s R%d" % [_ctrl.mastery.display_name(p), _ctrl.mastery.r_level(p)])
	var txt := "熟练 " + "、".join(names)
	if arr.size() > MAX_NAMES:
		txt += "等%d把" % arr.size()
	return txt


func _boss_room() -> RoomData:
	var r: RoomData = _ctrl.current_room
	if r != null and String(r.kind) == "boss":
		return r
	return null


func _boss_name() -> String:
	var r := _boss_room()
	return String(r.name) if r != null else ""


func _boss_element() -> String:
	var r := _boss_room()
	if r == null:
		return ""
	var e := ElementCounter.label(String(r.element))
	if e == "" or e == "无":
		return ""
	return e


func _display_name(path: String) -> String:
	var res = load(path)
	if res is WeaponData:
		return String(res.weapon_name)
	if res is ItemData:
		return String(res.item_name)
	return path.get_file().get_basename()
