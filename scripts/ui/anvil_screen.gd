extends Control
class_name AnvilScreen

# anvil_screen — 铁砧纯 gacha 覆盖层（§6 纯 gacha 定案：抽装备注入 owned_* 拥有池）
# 静态骨架由 anvil_screen.tscn 提供；本脚本负责显隐 / 填数据 / 摇按钮 / mini-reel 结果显示。

var controller
var hud: BattleHud
const UI_BUTTON = preload("res://scenes/ui/ui_button.tscn")

@onready var bg = $Bg
@onready var title_label = $Margin/Content/TitleLabel
@onready var points_label = $Margin/Content/PointsLabel
@onready var sub_label = $Margin/Content/SubLabel
@onready var info_label = $Margin/Content/InfoLabel
@onready var reel_box = $Margin/Content/ReelBox
@onready var bot = $Margin/Content/Bot

func configure(ctrl, h: BattleHud) -> void:
	controller = ctrl
	hud = h
	bg.color = Palette.BG_ANVIL
	title_label.text = "🔨 铁砧 · 抽装备"
	title_label.add_theme_font_size_override("font_size", TypeScale.BODY)
	sub_label.text = "消耗铁砧点数摇 3 格，抽到的装备进入拥有池（盘外永久保留）"
	sub_label.add_theme_font_size_override("font_size", TypeScale.CAPTION)
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(sp)
	var roll_btn = UI_BUTTON.instantiate()
	roll_btn.text = "🔨 摇动 (%d点)" % controller.ANVIL_ROLL_COST
	roll_btn.custom_minimum_size = Vector2(170, 48)
	roll_btn.add_theme_font_size_override("font_size", TypeScale.MEDIUM)
	roll_btn.connect("pressed", controller._on_anvil_roll_pressed)
	bot.add_child(roll_btn)
	var back_btn = UI_BUTTON.instantiate()
	back_btn.text = "返回整备"
	back_btn.custom_minimum_size = Vector2(120, 40)
	back_btn.add_theme_font_size_override("font_size", TypeScale.MEDIUM)
	back_btn.connect("pressed", controller._on_anvil_back_pressed)
	bot.add_child(back_btn)

func show_screen() -> void:
	refresh()
	visible = true

func refresh() -> void:
	var meta = controller.state.meta
	points_label.text = "铁砧点数: %d" % meta["anvil_points"]
	var pool = controller._anvil_pool()
	var owned = 0
	for p in pool:
		if controller._anvil_is_owned(p):
			owned += 1
	var not_yet = pool.size() - owned
	var pity = meta["anvil_pity"]
	var pity_txt = ""
	if not_yet > 0 and pity >= controller.ANVIL_PITY_MAX:
		pity_txt = "（保底触发：下次必出未拥有）"
	info_label.text = "图鉴 %.0f%%  已拥有 %d / 全池 %d\n未拥有 %d 件 · 连续重复 %d/%d %s" % [
		controller._anvil_collection_pct() * 100, owned, pool.size(), not_yet, pity, controller.ANVIL_PITY_MAX, pity_txt]
	for c in reel_box.get_children():
		reel_box.remove_child(c)
		c.queue_free()
	for d in controller.last_anvil_drops:
		reel_box.add_child(_make_cell(d))

func _make_cell(d: Dictionary) -> Control:
	var cc = CenterContainer.new()
	cc.custom_minimum_size = Vector2(160, 90)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(156, 86)
	var style = StyleBoxFlat.new()
	style.bg_color = Palette.CARD_BG
	style.border_color = Palette.PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	panel.add_child(vb)
	if d.get("kind", "") == "blank":
		vb.add_child(hud._label("空白格", TypeScale.META))
	else:
		vb.add_child(hud._label(d.get("name", "?"), TypeScale.META))
		var tag = "✨ 新获取" if d.get("is_new", false) else "↺ 重复"
		vb.add_child(hud._label("%s · %s" % [d.get("rarity", "?"), tag], TypeScale.CAPTION))
	cc.add_child(panel)
	return cc

func hide_screen() -> void:
	visible = false
