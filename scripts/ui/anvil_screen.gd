extends Control
class_name AnvilScreen

# anvil_screen — 铁砧锻造（元进度永久强化）覆盖层（P3b-2 抽独立场景）
# 静态骨架由 anvil_screen.tscn 提供；本脚本负责显隐 / 填数据（武器转轮升级 + 抗干扰）。
# 卡片构造复用 HUD 的 _label，按钮用 UI_BUTTON 组件；信号直接连 controller 铁砧方法。

var controller
var hud: BattleHud
const UI_BUTTON = preload("res://scenes/ui/ui_button.tscn")

@onready var bg = $Bg
@onready var title_label = $Margin/Content/TitleLabel
@onready var points_label = $Margin/Content/PointsLabel
@onready var sub_label = $Margin/Content/SubLabel
@onready var anvil_grid = $Margin/Content/Scroll/AnvilGrid
@onready var bot = $Margin/Content/Bot

func configure(ctrl, h: BattleHud) -> void:
	controller = ctrl
	hud = h
	bg.color = Palette.BG_ANVIL
	title_label.text = "🔨 铁砧锻造 · 元进度"
	title_label.add_theme_font_size_override("font_size", TypeScale.BODY)
	sub_label.text = "消耗点数永久强化转轮 / 抗干扰（跨局保留）"
	sub_label.add_theme_font_size_override("font_size", TypeScale.CAPTION)
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(sp)
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
	points_label.text = "铁砧点数: %d" % controller.state.meta["anvil_points"]
	for c in anvil_grid.get_children():
		anvil_grid.remove_child(c)
		c.queue_free()
	# 武器转轮升级
	for path in controller.state.WEAPON_POOL:
		var wd: Resource = load(path)
		var wname = wd.weapon_name if (wd != null) else path.get_file().get_basename()
		var lvl = controller.state.meta["weapon_upgrades"].get(path, 0)
		var cost = (lvl + 1) * 10
		var btn = UI_BUTTON.instantiate()
		btn.custom_minimum_size = Vector2(96, 56)
		btn.text = ""
		var cc = CenterContainer.new()
		cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.add_child(cc)
		var vb = VBoxContainer.new()
		vb.add_theme_constant_override("separation", 1)
		cc.add_child(vb)
		vb.add_child(hud._label(wname, TypeScale.META))
		vb.add_child(hud._label("转轮 Lv%d" % lvl, TypeScale.CAPTION))
		vb.add_child(hud._label("升级 %d 点" % cost, TypeScale.CAPTION))
		btn.connect("pressed", controller._on_anvil_weapon_pressed.bind(path))
		anvil_grid.add_child(btn)
	# 抗干扰
	var rl = controller.state.meta["interference_resist"]
	var rcost = (rl + 1) * 15
	var rbtn = UI_BUTTON.instantiate()
	rbtn.custom_minimum_size = Vector2(96, 56)
	rbtn.text = ""
	var rcc = CenterContainer.new()
	rcc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rcc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rbtn.add_child(rcc)
	var rvb = VBoxContainer.new()
	rvb.add_theme_constant_override("separation", 1)
	rcc.add_child(rvb)
	rvb.add_child(hud._label("锤炼意志", TypeScale.META))
	rvb.add_child(hud._label("抗干扰 Lv%d/5" % rl, TypeScale.CAPTION))
	if rl >= 5:
		rvb.add_child(hud._label("已满级", TypeScale.CAPTION))
	else:
		rvb.add_child(hud._label("升级 %d 点" % rcost, TypeScale.CAPTION))
	rbtn.connect("pressed", controller._on_anvil_resist_pressed)
	anvil_grid.add_child(rbtn)

func hide_screen() -> void:
	visible = false
