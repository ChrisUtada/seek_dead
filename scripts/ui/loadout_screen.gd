extends Control
class_name LoadoutScreen

# loadout_screen — 整备（选择携带物品）覆盖层（P3：5 小人 hub + 可收起副屏）
# 静态结构由 loadout_screen.tscn 完整提供（5 个小人站 + 右侧抽屉副屏 + 底部栏）；
# 本脚本只负责：小人点击/高亮 / 副屏滑入滑出 / 填类目卡片数据 / 发信号。
# 卡片构造复用 HUD 的 _make_item_card；信号走 controller 的整备方法。

var controller
var hud: BattleHud
const UI_BUTTON = preload("res://scenes/ui/ui_button.tscn")

const CHAR_CATS := ["weapon", "skill", "active", "passive"]
const TITLES := {"weapon": "武器", "skill": "技能", "active": "消耗品", "passive": "护符"}
const SUB_W := 260   # 副屏抽屉宽度（480 设计宽下占 ~54%）

@onready var bg = $Bg
@onready var title_label = $Margin/Content/TitleLabel
@onready var rule_label = $Margin/Content/RuleLabel
@onready var char_buttons := {
	"weapon": $Margin/Content/CharRow/CharWeapon,
	"skill": $Margin/Content/CharRow/CharSkill,
	"active": $Margin/Content/CharRow/CharActive,
	"passive": $Margin/Content/CharRow/CharPassive,
}
@onready var anvil_btn = $Margin/Content/CharRow/CharAnvil
@onready var count_label = $Margin/Content/Bot/CountLabel
@onready var anvil_label = $Margin/Content/Bot/AnvilLabel
@onready var confirm_btn = $Margin/Content/Bot/ConfirmBtn
@onready var sub_handle = $SubHandle
@onready var sub_screen = $SubScreen
@onready var sub_panel = $SubScreen/Panel
@onready var sub_head = $SubScreen/Panel/VBox/Head
@onready var sub_strip = $SubScreen/Panel/VBox/Strip
@onready var sub_list = $SubScreen/Panel/VBox/Scroll/List

var selected_char := "weapon"   # 当前选中的类目
var loadout_cards := []         # 副屏内卡片元数据 {path, btn, selected, kind}
var sub_open := false
var _tween: Tween


func configure(ctrl, h: BattleHud) -> void:
	controller = ctrl
	hud = h
	bg.color = Palette.BG_LOADOUT
	title_label.text = "⚙ 整备 · 选择携带物品"
	title_label.add_theme_font_size_override("font_size", TypeScale.LEAD)
	title_label.add_theme_color_override("font_color", Palette.TITLE)
	rule_label.text = "点击小人查看/装备该类目 · 再点把手收起 · 铁砧小人进入锻造"
	rule_label.add_theme_font_size_override("font_size", TypeScale.CAPTION)
	rule_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# 5 个小人站
	for cat in CHAR_CATS:
		var b: Button = char_buttons[cat]
		b.pressed.connect(_on_char_pressed.bind(cat))
		_style_char_btn(b, false)
	anvil_btn.pressed.connect(_on_anvil_pressed)
	_style_char_btn(anvil_btn, true)
	# 副屏（抽屉）
	sub_panel.add_theme_stylebox_override("panel", _panel_style())
	sub_head.add_theme_font_size_override("font_size", TypeScale.META)
	sub_handle.add_theme_font_size_override("font_size", TypeScale.OVERLAY)
	sub_handle.text = "❯"
	sub_handle.pressed.connect(_toggle_sub)
	_style_handle()
	# 底部栏
	count_label.add_theme_font_size_override("font_size", TypeScale.META)
	anvil_label.add_theme_font_size_override("font_size", TypeScale.TINY)
	confirm_btn.text = "确认开战 ▶"
	confirm_btn.add_theme_font_size_override("font_size", TypeScale.MEDIUM)
	confirm_btn.pressed.connect(controller._confirm_loadout)
	_refresh_char_highlight()
	_set_sub_open(false, true)   # 初始收起


# ---- 小人站 ----

func _style_char_btn(btn: Button, is_anvil: bool) -> void:
	var bgc := Palette.CARD_NORM_BG
	var bdc := Palette.CARD_NORM_BORDER
	if is_anvil:
		bgc = Palette.BG_ANVIL
		bdc = Palette.ACCENT_GOLD.darkened(0.25)
	var sb = StyleBoxFlat.new()
	sb.bg_color = bgc
	sb.border_color = bdc
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(Palette.PANEL_RADIUS)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	var sb_h = sb.duplicate()
	sb_h.bg_color = bgc.lightened(0.08)
	var sb_p = sb.duplicate()
	sb_p.bg_color = bgc.darkened(0.10)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.add_theme_stylebox_override("pressed", sb_p)


func _refresh_char_highlight() -> void:
	for cat in CHAR_CATS:
		var b: Button = char_buttons[cat]
		var sel: bool = (cat == selected_char)
		var sb = StyleBoxFlat.new()
		sb.bg_color = Palette.CARD_SEL_BG if sel else Palette.CARD_NORM_BG
		sb.border_color = Palette.CARD_SEL_BORDER if sel else Palette.CARD_NORM_BORDER
		sb.set_border_width_all(2 if sel else 1)
		sb.set_corner_radius_all(Palette.PANEL_RADIUS)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)


func _on_char_pressed(cat: String) -> void:
	selected_char = cat
	_open_sub(cat)


func _on_anvil_pressed() -> void:
	_set_sub_open(false, true)
	hud._show_anvil_screen()


# ---- 副屏抽屉 ----

func _panel_style() -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL_BG
	sb.border_color = Palette.PANEL_BORDER
	sb.set_border_width_all(Palette.BORDER_WIDTH)
	sb.set_corner_radius_all(Palette.PANEL_RADIUS)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _style_handle() -> void:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL_BG
	sb.border_color = Palette.PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(Palette.PANEL_RADIUS)
	sub_handle.add_theme_stylebox_override("normal", sb)
	sub_handle.add_theme_stylebox_override("hover", sb)
	sub_handle.add_theme_stylebox_override("pressed", sb)


func _toggle_sub() -> void:
	if sub_open:
		_set_sub_open(false)
	else:
		_open_sub(selected_char)


func _open_sub(cat: String) -> void:
	selected_char = cat
	_refresh_char_highlight()
	_fill_sub(cat)
	_set_sub_open(true)


func _close_sub() -> void:
	_set_sub_open(false)


func _set_sub_open(open: bool, instant := false) -> void:
	sub_open = open
	if _tween and _tween.is_valid():
		_tween.kill()
	var target := -float(SUB_W) if open else 0.0
	sub_handle.text = "❮" if open else "❯"
	sub_screen.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if instant:
		sub_screen.offset_left = target
	else:
		_tween = create_tween()
		_tween.tween_property(sub_screen, "offset_left", target, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ---- 数据填充 ----

func _fill_sub(cat: String) -> void:
	sub_head.text = _cat_count_text(cat, TITLES[cat])
	for c in sub_list.get_children():
		sub_list.remove_child(c)
		c.queue_free()
	loadout_cards = []
	for path in controller._owned_arr(cat):
		var data: Resource = load(path)
		var card = hud._make_item_card(data, path, cat)
		sub_list.add_child(card["btn"])
		loadout_cards.append(card)
	_sync_card_selection()
	_update_loadout_cards_visual()
	_refresh_slot_strip()


func _refresh_slot_strip() -> void:
	var category := selected_char
	for c in sub_strip.get_children():
		sub_strip.remove_child(c)
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
		sub_strip.add_child(g)
	if uncapped:
		var plus = hud._label("＋", 12)
		plus.add_theme_color_override("font_color", Palette.PANEL_BORDER)
		sub_strip.add_child(plus)


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
	count_label.text = "%s · %s · %s · %s" % [
		_cat_count_text("weapon", "武器"), _cat_count_text("skill", "技能"),
		_cat_count_text("active", "消耗品"), _cat_count_text("passive", "护符")]
	if sub_open:
		sub_head.text = _cat_count_text(selected_char, TITLES[selected_char])
		_refresh_slot_strip()
	var ok = controller.state.selected_loadout.size() >= controller.state.LOADOUT_MIN
	confirm_btn.disabled = not ok
	confirm_btn.text = ("确认开战 ▶" if ok else "至少选 %d 把武器 ▶" % controller.state.LOADOUT_MIN)


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
	if anvil_label != null:
		anvil_label.text = "点数:%d" % controller.state.meta["anvil_points"]


# 铁砧授予等 owned 变化后，整备页开着时立即重建副屏（隐藏时由 show_screen 自动重建）
func refresh_data() -> void:
	_fill_sub(selected_char)
	_update_loadout_count()
	_update_loadout_anvil()


func show_screen() -> void:
	controller.in_loadout = true
	_update_loadout_anvil()
	_fill_sub(selected_char)     # 预填当前类目，展开时立即有内容
	_update_loadout_count()
	_refresh_char_highlight()
	visible = true


func hide_screen() -> void:
	controller.in_loadout = false
	visible = false
