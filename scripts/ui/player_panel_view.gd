# PlayerPanelView — 左栏玩家面板视图逻辑（P2 架构还债，2026-08-24 自 battle_hud 迁入）
# 模式：照覆盖层 configure 注入——包装 battle_hud.tscn 静态 PlayerPanel 节点引用，
# 拥有装备图标行重建 / 腰带 4 格刷新 / 元素图标映射。节点仍由 tscn 提供（无场景手术），
# 本类只承载「这些节点怎么随状态刷新」的逻辑；battle_hud 留单行转发器。
# 数据一律读 controller.state 快照；使用请求发回 hud 的 consumable_used 信号（controller 统一结算）。

var _hud            # BattleHud
var weapons_row: Control
var charms_row: Control
var skills_row: Control
var consumable_cells: Array


func configure(hud, weapons_row_n: Control, charms_row_n: Control, skills_row_n: Control, cells: Array) -> void:
	_hud = hud
	weapons_row = weapons_row_n
	charms_row = charms_row_n
	skills_row = skills_row_n
	consumable_cells = cells


func controller():
	return _hud.controller


# 元素 emoji 映射（武器图标用；与 ElementCounter.label 文案轴解耦的视觉轴）
func element_icon(elem: String) -> String:
	match elem:
		"fire":   return "🔥"
		"ice":    return "❄️"
		"poison": return "☠️"
		"light":  return "✨"
		"dark":   return "🌑"
		_:        return "⚔️"


# 装备图标刷新：武器取「⚔️+元素」、护符取 icon、技能取 icon；
# 每次清空旧的 WIcon_/CIcon_/SIcon_ 子节点后重建（数量极小，无性能问题）。
func refresh_gear_icons() -> void:
	if weapons_row == null or charms_row == null or skills_row == null:
		return
	for child in weapons_row.get_children().duplicate():
		if child.name.begins_with("WIcon_"):
			weapons_row.remove_child(child)
			child.queue_free()
	for child in charms_row.get_children().duplicate():
		if child.name.begins_with("CIcon_"):
			charms_row.remove_child(child)
			child.queue_free()
	for child in skills_row.get_children().duplicate():
		if child.name.begins_with("SIcon_"):
			skills_row.remove_child(child)
			child.queue_free()
	var st = controller().state
	for path in st.selected_loadout:
		var wd = load(path)
		if wd == null:
			continue
		var icon := "⚔️"
		if wd != null and "element" in wd:
			icon = "⚔️" + element_icon(String(wd.element))
		var tip: String = wd.weapon_name if "weapon_name" in wd else path.get_file().get_basename()
		var lbl = Label.new()
		lbl.name = "WIcon_" + path.get_file().get_basename()
		lbl.text = icon
		lbl.add_theme_font_size_override("font_size", TypeScale.REEL)
		lbl.tooltip_text = tip
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		weapons_row.add_child(lbl)
	for path in st.selected_charms:
		var cd = load(path)
		if cd == null:
			continue
		var icon_str: String = cd.get("icon") if cd.get("icon") != null else ""
		var icon: String = icon_str if icon_str != "" else "🛡"
		var name_str: String = cd.get("item_name") if cd.get("item_name") != null else path.get_file().get_basename()
		var desc_str: String = cd.get("description") if cd.get("description") != null else ""
		var lbl = Label.new()
		lbl.name = "CIcon_" + path.get_file().get_basename()
		lbl.text = icon
		lbl.add_theme_font_size_override("font_size", TypeScale.REEL)
		lbl.tooltip_text = name_str + (" · " + desc_str if desc_str != "" else "")
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		charms_row.add_child(lbl)
	for path in st.selected_skills:
		var sd = load(path)
		if sd == null:
			continue
		var icon_str: String = sd.get("icon") if sd.get("icon") != null else ""
		var icon: String = icon_str if icon_str != "" else "✦"
		var name_str: String = sd.get("buff_name") if sd.get("buff_name") != null else path.get_file().get_basename()
		var desc_str: String = sd.get("description") if sd.get("description") != null else ""
		var lbl = Label.new()
		lbl.name = "SIcon_" + path.get_file().get_basename()
		lbl.text = icon
		lbl.add_theme_font_size_override("font_size", TypeScale.REEL)
		lbl.tooltip_text = name_str + (" · " + desc_str if desc_str != "" else "")
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		skills_row.add_child(lbl)


# 腰带 4 格刷新：按 consumable_slots 顺序填，缺位留空占位；
# 按 game_state/in_loadout/律法锁槽决定禁用。
func refresh_consumable_panel() -> void:
	if consumable_cells.is_empty():
		return
	var can_use = (controller().state.game_state == DuelController.FlowState.PLAYING) and (not controller().state.in_loadout)
	for i in range(consumable_cells.size()):
		var cell = consumable_cells[i]
		if i < controller().state.consumable_slots.size():
			var slot = controller().state.consumable_slots[i]
			var cd: Resource = load(slot["path"])
			if cd != null:
				cell.text = "%s %s" % [cd.icon, cd.item_name]
				cell.tooltip_text = ItemTooltip.for_resource(cd) + "\n剩 %d 次" % slot["charges"]   # 统一生成器 + 腰带余量
			else:
				cell.text = "?"
				cell.tooltip_text = "资源缺失"
			var locked: bool = controller().state.locked_consumable_slot == i   # 天平审判官：律法封印该格
			cell.disabled = not can_use or slot["charges"] <= 0 or locked
			if locked and not cell.text.begins_with("⚖ "):
				cell.text = "⚖ " + cell.text
		else:
			cell.text = "—"
			cell.tooltip_text = "消耗品空位"
			cell.disabled = true   # 空位不响应点击


# 4 格子点击：发 consumable_used(uid) 让 controller 走统一扣减+结算路径。
func on_consumable_cell_pressed(cell_index: int) -> void:
	if cell_index < 0 or cell_index >= controller().state.consumable_slots.size():
		return
	var uid = controller().state.consumable_slots[cell_index]["uid"]
	_hud.consumable_used.emit(uid)