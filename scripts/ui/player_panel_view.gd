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
		"ice":    return "❄"
		"poison": return "☠"
		"light":  return "✨"
		"dark":   return "🌑"
		_:        return ""   # 无属性：仅保留武器本体符号（⚔），避免 ⚔️ 变体在像素字体里成豆腐块


var _card_style: StyleBoxFlat = null

# C2：左栏大图标卡片统一规格（左栏内宽 80 → 两列各 39px；高度 38 与 24 主图 + 9px 名对齐）
const CARD_MIN := Vector2(38, 38)
const CARD_NAME_W := 36.0


# 单张大图标卡片：PanelContainer（1px 细框）+ [24/16 图标 或 emoji] + 单行短名。
# 文案一律 clip，不撑宽；完整信息由调用方放进 tooltip。
func _make_gear_card(art: Texture2D, art_size: Vector2, emoji: String, short_name: String, tip: String) -> PanelContainer:
	if _card_style == null:
		_card_style = StyleBoxFlat.new()
		_card_style.bg_color = Palette.CARD_BG
		_card_style.border_color = Palette.CARD_NORM_BORDER
		_card_style.set_border_width_all(Palette.BORDER_WIDTH)
		_card_style.set_content_margin_all(1)
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.tooltip_text = tip
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _card_style)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vb)
	if art != null:
		var tr := TextureRect.new()
		tr.texture = art
		tr.custom_minimum_size = art_size
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(tr)
	else:
		var el := Label.new()
		el.text = emoji if emoji != "" else "—"
		el.custom_minimum_size = Vector2(art_size.x, art_size.y)
		el.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		el.add_theme_font_size_override("font_size", TypeScale.REEL)
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		el.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		el.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(el)
	var nl := Label.new()
	nl.text = short_name
	nl.custom_minimum_size = Vector2(CARD_NAME_W, 0)
	nl.add_theme_font_size_override("font_size", TypeScale.TINY)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nl)
	return card


# 装备图标刷新（C2）：双武器 → 两列大卡片；技能 / 护符 → 并排大卡片。
# 武器取 24×24 art，无 art 才回落 16 icon_tex / emoji；完整名、元素、R 熟练、铭印进 tooltip。
# 技能/护符只占一张主卡，其余条目与技艺全部并入 tooltip（避免把卡片挤成多行小字）。
func refresh_gear_icons() -> void:
	if weapons_row == null or charms_row == null or skills_row == null:
		return
	for row in [weapons_row, charms_row, skills_row]:
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()
	var st = controller().state
	var mastery = controller().mastery
	var idx := 0
	for path in st.selected_loadout:
		var wd = load(path)
		if wd == null:
			continue
		var name_txt: String = String(wd.weapon_name) if "weapon_name" in wd else path.get_file().get_basename()
		var elem: String = String(wd.element) if "element" in wd else ""
		var tip := name_txt
		if elem != "" and elem != "none":
			tip += " · " + ElementCounter.label(elem)
		var prog: String = mastery.progress_text(path)
		if prog != "":
			tip += "\n" + prog
			var imp: String = mastery.imprint_text(path)
			if imp != "":
				tip += "\n" + imp
		var art: Texture2D = wd.get("art") if wd != null else null
		var icon_tex: Texture2D = wd.get("icon_tex") if wd != null else null
		var card: Control
		if art != null:
			card = _make_gear_card(art, Vector2(24, 24), "", name_txt, tip)
		elif icon_tex != null:
			card = _make_gear_card(icon_tex, Vector2(16, 16), "", name_txt, tip)
		else:
			card = _make_gear_card(null, Vector2(16, 16), "🗡️" + element_icon(elem), name_txt, tip)
		card.name = "WCard_%d_%s" % [idx, path.get_file().get_basename()]
		weapons_row.add_child(card)
		idx += 1

	# 技能：主技能一张卡，其余技能并入 tooltip；技艺（M2-03）只进 tooltip
	var skill_paths: Array = st.selected_skills
	var perk_lines: Array[String] = []
	for pid in controller().growth.perk_ids:
		perk_lines.append("%s · %s" % [controller().growth.perk_name(pid), controller().growth.perk_desc(pid)])
	if skill_paths.is_empty():
		var empty_tip := "未装备技能"
		if not perk_lines.is_empty():
			empty_tip += "\n技艺: " + " / ".join(perk_lines)
		skills_row.add_child(_make_gear_card(null, Vector2(16, 16), "✦", "无技能", empty_tip))
	else:
		var sd = load(skill_paths[0])
		var s_name: String = String(sd.get("buff_name")) if sd != null and sd.get("buff_name") != null else skill_paths[0].get_file().get_basename()
		var s_desc: String = String(sd.get("description")) if sd != null and sd.get("description") != null else ""
		var s_tip := s_name + (" · " + s_desc if s_desc != "" else "")
		if skill_paths.size() > 1:
			var others: Array[String] = []
			for sp in skill_paths.slice(1):
				var od = load(sp)
				others.append(String(od.get("buff_name")) if od != null and od.get("buff_name") != null else sp.get_file().get_basename())
			s_tip += "\n其他技能: " + "、".join(others)
		if not perk_lines.is_empty():
			s_tip += "\n技艺: " + " / ".join(perk_lines)
		var s_icon_tex: Texture2D = sd.get("icon_tex") if sd != null else null
		var s_emoji: String = String(sd.get("icon")) if sd != null and sd.get("icon") != null else "✦"
		var s_label: String = s_name if skill_paths.size() == 1 else "%s+%d" % [s_name, skill_paths.size() - 1]
		var scard := _make_gear_card(s_icon_tex, Vector2(16, 16), s_emoji, s_label, s_tip)
		scard.name = "SCard"
		skills_row.add_child(scard)

	# 护符：主护符一张卡，其余护符并入 tooltip
	var charm_paths: Array = st.selected_charms
	if charm_paths.is_empty():
		charms_row.add_child(_make_gear_card(null, Vector2(16, 16), "🛡", "无护符", "未装备护符"))
	else:
		var cd = load(charm_paths[0])
		var c_name: String = String(cd.get("item_name")) if cd != null and cd.get("item_name") != null else charm_paths[0].get_file().get_basename()
		var c_desc: String = String(cd.get("description")) if cd != null and cd.get("description") != null else ""
		var c_tip := c_name + (" · " + c_desc if c_desc != "" else "")
		if charm_paths.size() > 1:
			var c_others: Array[String] = []
			for cp in charm_paths.slice(1):
				var od2 = load(cp)
				c_others.append(String(od2.get("item_name")) if od2 != null and od2.get("item_name") != null else cp.get_file().get_basename())
			c_tip += "\n其他护符: " + "、".join(c_others)
		var c_icon_tex: Texture2D = cd.get("icon_tex") if cd != null else null
		var c_emoji: String = String(cd.get("icon")) if cd != null and cd.get("icon") != null else "🛡"
		var c_label: String = c_name if charm_paths.size() == 1 else "%s+%d" % [c_name, charm_paths.size() - 1]
		var ccard := _make_gear_card(c_icon_tex, Vector2(16, 16), c_emoji, c_label, c_tip)
		ccard.name = "CCard"
		charms_row.add_child(ccard)


# 腰带 4 格刷新（C2-3）：方格内「居中图标 + 剩余次数」；名称与详情进 tooltip。
# 空位 / 禁用 / 律法锁（⚖）三种状态仍可辨；格内永远只有短内容，避免撑破 34px 方格。
func refresh_consumable_panel() -> void:
	if consumable_cells.is_empty():
		return
	var can_use = (controller().state.game_state == DuelController.FlowState.PLAYING) and (not controller().state.in_loadout)
	for i in range(consumable_cells.size()):
		var cell = consumable_cells[i]
		if i < controller().state.consumable_slots.size():
			var slot = controller().state.consumable_slots[i]
			var cd: Resource = load(slot["path"])
			var charges: int = int(slot["charges"])
			if cd != null:
				# 有 icon_tex 用 16px 图标 + ×N；无图回落 emoji + ×N（两者总宽都 ≤ 32px 内容区）
				cell.icon = cd.get("icon_tex")
				if cell.icon == null:
					cell.text = "%s×%d" % [cd.icon, charges]
				else:
					cell.text = "×%d" % charges
				cell.tooltip_text = "%s · %s\n剩 %d 次" % [cd.item_name, ItemTooltip.for_resource(cd), charges]
			else:
				cell.icon = null
				cell.text = "?"
				cell.tooltip_text = "资源缺失"
			var locked: bool = controller().state.locked_consumable_slot == i   # 天平审判官：律法封印该格
			cell.disabled = not can_use or charges <= 0 or locked
			if locked:
				# 律法锁：图标保留、次数换成天秤符（完整剩余次数在 tooltip）
				cell.text = "⚖%d" % charges
		else:
			cell.icon = null
			cell.text = "—"
			cell.tooltip_text = "消耗品空位"
			cell.disabled = true   # 空位不响应点击


# 4 格子点击：发 consumable_used(uid) 让 controller 走统一扣减+结算路径。
func on_consumable_cell_pressed(cell_index: int) -> void:
	if cell_index < 0 or cell_index >= controller().state.consumable_slots.size():
		return
	var uid = controller().state.consumable_slots[cell_index]["uid"]
	_hud.consumable_used.emit(uid)