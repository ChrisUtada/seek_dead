extends Control
class_name LoadoutScreen

# loadout_screen — 整备（选择携带物品）覆盖层（P3b-2 抽独立场景）
# 静态骨架由 loadout_screen.tscn 提供；本脚本负责四分类列构建 / 显隐 / 填数据 / 发信号。
# 卡片构造复用 HUD 的 _make_item_card；信号走 controller 的整备方法。

var controller
var hud: BattleHud
const UI_BUTTON = preload("res://scenes/ui/ui_button.tscn")
const ItemData = preload("res://scripts/items/item_data.gd")
const SkillData = preload("res://scripts/items/skill_data.gd")

@onready var bg = $Bg
@onready var title_label = $Margin/Content/TitleLabel
@onready var rule_label = $Margin/Content/RuleLabel
@onready var cat_box = $Margin/Content/CatBox
@onready var bot = $Margin/Content/Bot

var loadout_cards := []                   # 卡片元数据列表 {path, btn, selected, kind}
var loadout_columns: Dictionary = {}      # category -> 列头 Label
var loadout_slot_strips: Dictionary = {}  # category -> 槽位条 HBoxContainer
var loadout_count_label
var loadout_confirm_btn
var loadout_anvil_label

func configure(ctrl, h: BattleHud) -> void:
	controller = ctrl
	hud = h
	bg.color = Palette.BG_LOADOUT
	title_label.text = "⚙ 整备 · 选择携带物品"
	title_label.add_theme_font_size_override("font_size", TypeScale.LEAD)
	title_label.add_theme_color_override("font_color", Palette.TITLE)
	rule_label.text = "四类独立槽位 · 武器/技能=进转轮(稀释自然刹车·无硬顶) · 消耗品/护符=不进池(硬限) · 买即开槽扩槽"
	rule_label.add_theme_font_size_override("font_size", 10)
	rule_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# 底部：计数 + 铁砧点数 + 铁砧按钮 + 确认（始终可见）
	loadout_count_label = hud._label("武器 0/%d · 技能 0/%d · 消耗品 0/%d · 护符 0/%d" % [controller.state.loadout_max, controller.state.skill_max, controller._cat_max("active"), controller.state.charm_max], TypeScale.META)
	loadout_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	bot.add_child(loadout_count_label)
	var bot_spacer = Control.new()
	bot_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(bot_spacer)
	loadout_anvil_label = hud._label("铁砧点数: 0", TypeScale.TINY)
	bot.add_child(loadout_anvil_label)
	var anvil_btn = UI_BUTTON.instantiate()
	anvil_btn.text = "🔨 铁砧"
	anvil_btn.custom_minimum_size = Vector2(90, 36)
	anvil_btn.add_theme_font_size_override("font_size", TypeScale.TINY)
	anvil_btn.connect("pressed", hud._show_anvil_screen)
	bot.add_child(anvil_btn)
	loadout_confirm_btn = UI_BUTTON.instantiate()
	loadout_confirm_btn.text = "确认开战 ▶"
	loadout_confirm_btn.custom_minimum_size = Vector2(120, 40)
	loadout_confirm_btn.add_theme_font_size_override("font_size", TypeScale.MEDIUM)
	loadout_confirm_btn.connect("pressed", controller._confirm_loadout)
	bot.add_child(loadout_confirm_btn)
	# 四分类并列卡片区
	loadout_cards = []
	loadout_columns = {}
	loadout_slot_strips = {}
	_add_loadout_column(cat_box, "武器", controller.state.WEAPON_POOL, "weapon", 1)
	_add_loadout_column(cat_box, "技能", controller.state.SKILL_POOL, "skill", 1)
	_add_loadout_column(cat_box, "消耗品", hud._item_pool_of("active"), "active", 1)
	_add_loadout_column(cat_box, "护符", hud._item_pool_of("passive"), "passive", 1)

func _add_loadout_column(parent: Control, title: String, pool: Array, category: String, _columns: int) -> void:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(250, 0)   # 四列并排：250*4 + 间隔 < 1280 设计宽
	var style = StyleBoxFlat.new()
	style.bg_color = Palette.CARD_BG
	style.border_color = Palette.PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)

	var title_label = hud._label("%s 0/%d" % [title, controller._cat_max(category)], 12)
	loadout_columns[category] = title_label
	v.add_child(title_label)

	# 槽位条：按该类天花板画满格子，直观呈现「还能扩几格」
	var strip = HBoxContainer.new()
	strip.add_theme_constant_override("separation", 2)
	loadout_slot_strips[category] = strip
	v.add_child(strip)
	_refresh_slot_strip(category)

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	v.add_child(scroll)

	# 单列纵向列表（固定最小宽度 170 设计 px，确保文字不会竖排）
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(0, 0)
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for path in pool:
		var data: Resource = load(path)
		var kind := "weapon"
		if data is ItemData:
			kind = data.category
		elif data is SkillData:
			kind = "skill"
		var card = hud._make_item_card(data, path, kind)
		list.add_child(card["btn"])
		loadout_cards.append(card)

# 刷新某类槽位条：天花板 = 格子总数，当前上限 = 已解锁边界，已选数 = 已装备边界
func _refresh_slot_strip(category: String) -> void:
	if not loadout_slot_strips.has(category):
		return
	var strip: HBoxContainer = loadout_slot_strips[category]
	for c in strip.get_children():
		strip.remove_child(c)
		c.queue_free()
	var used = controller._sel_arr(category).size()
	var unlocked = controller._cat_max(category)
	var ceiling = controller._cat_cap(category)
	var uncapped = (ceiling == controller.state.UNCAPPED)
	var cells = unlocked if uncapped else ceiling
	for i in cells:
		var glyph := "·"
		var tint := Palette.PANEL_BORDER
		if i < used:
			glyph = "◆"
			tint = Palette.CARD_SEL_BORDER
		elif i < unlocked:
			glyph = "◇"
			tint = Palette.MUTED
		var g = hud._label(glyph, 12)
		g.add_theme_color_override("font_color", tint)
		strip.add_child(g)
	if uncapped:
		var plus = hud._label("＋", 12)
		plus.add_theme_color_override("font_color", Palette.PANEL_BORDER)
		strip.add_child(plus)

func _update_loadout_cards_visual() -> void:
	var wfull = controller.state.selected_loadout.size() >= controller._cat_max("weapon")
	var cfull = controller._sel_arr("active").size() >= controller._cat_max("active")
	var hfull = controller.state.selected_charms.size() >= controller._cat_max("passive")
	var bfull = controller.state.selected_skills.size() >= controller._cat_max("skill")
	for card in loadout_cards:
		var sb = StyleBoxFlat.new()
		if card["selected"]:
			sb.bg_color = Palette.CARD_SEL_BG
			sb.border_color = Palette.CARD_SEL_BORDER
			sb.set_border_width_all(2)
			card["btn"].disabled = false
		else:
			sb.bg_color = Palette.CARD_NORM_BG
			sb.border_color = Palette.CARD_NORM_BORDER
			sb.set_border_width_all(1)
			var cf = (card["kind"] == "weapon" and wfull) or (card["kind"] == "active" and cfull) or (card["kind"] == "passive" and hfull) or (card["kind"] == "skill" and bfull)
			card["btn"].disabled = cf
		card["btn"].add_theme_stylebox_override("normal", sb)
		card["btn"].add_theme_stylebox_override("hover", sb)
		card["btn"].add_theme_stylebox_override("pressed", sb)
		card["btn"].add_theme_stylebox_override("disabled", sb)

func _cat_count_text(cat: String, label: String) -> String:
	var grow = "＋" if controller._cat_cap(cat) == controller.state.UNCAPPED else ""
	return "%s %d/%d%s" % [label, controller._sel_arr(cat).size(), controller._cat_max(cat), grow]

func _update_loadout_count() -> void:
	loadout_count_label.text = "%s · %s · %s · %s" % [
		_cat_count_text("weapon", "武器"), _cat_count_text("skill", "技能"),
		_cat_count_text("active", "消耗品"), _cat_count_text("passive", "护符")]
	var titles = {"weapon": "武器", "skill": "技能", "active": "消耗品", "passive": "护符"}
	for cat in titles:
		if loadout_columns.has(cat):
			loadout_columns[cat].text = _cat_count_text(cat, titles[cat])
		_refresh_slot_strip(cat)
	var ok = controller.state.selected_loadout.size() >= controller.state.LOADOUT_MIN
	loadout_confirm_btn.disabled = not ok
	loadout_confirm_btn.text = ("确认开战 ▶" if ok else "至少选 %d 把武器 ▶" % controller.state.LOADOUT_MIN)

func show_screen() -> void:
	controller.in_loadout = true
	_sync_card_selection()      # 从数组重建卡片 selected 标志（防止 Boss 奖励等外部路径直接改数组导致不同步）
	_update_loadout_cards_visual()
	_update_loadout_count()
	_update_loadout_anvil()
	visible = true

# 每次打开整备屏时，从 controller 的四个选中数组重建所有卡片的 selected 标志。
func _sync_card_selection() -> void:
	var weapons = controller.state.selected_loadout
	var consumables = controller.state.selected_consumables
	var charms = controller.state.selected_charms
	var skills = controller.state.selected_skills
	for card in loadout_cards:
		match card["kind"]:
			"weapon":
				card["selected"] = weapons.has(card["path"])
			"active":
				card["selected"] = consumables.has(card["path"])
			"passive":
				card["selected"] = charms.has(card["path"])
			"skill":
				card["selected"] = skills.has(card["path"])

func _update_loadout_anvil() -> void:
	if loadout_anvil_label != null:
		loadout_anvil_label.text = "铁砧点数: %d" % controller.state.meta["anvil_points"]

func hide() -> void:
	controller.in_loadout = false
	visible = false
