extends Control
class_name AnvilScreen

# anvil_screen — 铁砧纯 gacha 覆盖层（§6 纯 gacha 定案：抽装备注入 owned_* 拥有池）
# 静态骨架由 anvil_screen.tscn 提供；本脚本负责显隐 / 填数据 / 摇按钮 / 旋转三连仪式动画。

var controller
var hud: BattleHud
const UI_BUTTON = preload("res://scenes/ui/ui_button.tscn")

var _spinning := false

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
	sub_label.text = "消耗铁砧点数摇一次，三格必出同一件装备（仪式感三连）"
	sub_label.add_theme_font_size_override("font_size", TypeScale.CAPTION)
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(sp)
	var roll_btn = UI_BUTTON.instantiate()
	roll_btn.text = "🔨 摇动 (%d点)" % controller.ANVIL_ROLL_COST
	roll_btn.custom_minimum_size = Vector2(170, 48)
	roll_btn.add_theme_font_size_override("font_size", TypeScale.MEDIUM)
	roll_btn.connect("pressed", _on_roll_pressed)
	bot.add_child(roll_btn)
	var back_btn = UI_BUTTON.instantiate()
	back_btn.text = "返回整备"
	back_btn.custom_minimum_size = Vector2(120, 40)
	back_btn.add_theme_font_size_override("font_size", TypeScale.MEDIUM)
	back_btn.connect("pressed", hud.anvil_back_requested.emit)
	bot.add_child(back_btn)

func show_screen() -> void:
	refresh()
	visible = true

func refresh() -> void:
	# 旋转动画进行中：格子由 _play_spin 接管，此处不重绘，避免清掉转动中的标签
	if _spinning:
		return
	var meta = controller.state.meta
	var info = controller._anvil_system.collection_info()
	points_label.text = "铁砧点数: %d" % meta["anvil_points"]
	var pity = meta["anvil_pity"]
	var pity_txt = ""
	if info["not_yet"] > 0 and pity >= controller.ANVIL_PITY_MAX:
		pity_txt = "（保底触发：下次必出未拥有）"
	info_label.text = "图鉴 %.0f%%  已拥有 %d / 全池 %d\n未拥有 %d 件 · 连续重复 %d/%d %s" % [
		info["pct"] * 100, info["owned"], info["total"], info["not_yet"], pity, controller.ANVIL_PITY_MAX, pity_txt]
	for c in reel_box.get_children():
		reel_box.remove_child(c)
		c.queue_free()
	if controller._anvil_system.last_anvil_drops.is_empty():
		# 未摇过：三格显示问号，制造悬念
		for i in 3:
			reel_box.add_child(_make_placeholder())
	else:
		for d in controller._anvil_system.last_anvil_drops:
			reel_box.add_child(_make_cell(d))

func _on_roll_pressed() -> void:
	if _spinning:
		return
	if controller.meta["anvil_points"] < controller.ANVIL_ROLL_COST:
		sub_label.text = "铁砧点数不足，先去局内赚点数吧"
		return
	_spinning = true
	sub_label.text = "转动中…"
	controller._on_anvil_roll_pressed()  # 扣点 + 结算 + 写入 last_anvil_drops（三连相同）
	_play_spin(controller._anvil_system.last_anvil_drops)

func _play_spin(final_drops: Array) -> void:
	# 清空旧格，建立三张转动标签
	for c in reel_box.get_children():
		reel_box.remove_child(c)
		c.queue_free()
	var names = controller._anvil_system.collection_info()["names"]
	var labels := []
	var stops = [0.45, 0.62, 0.80]  # 三格错峰停下，强化仪式感
	for i in 3:
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
		var lb = hud._label("?", TypeScale.META)
		panel.add_child(lb)
		cc.add_child(panel)
		reel_box.add_child(cc)
		labels.append(lb)
		_spin_cell(lb, names, stops[i], final_drops[i] if i < final_drops.size() else {"kind": "blank"})
	await get_tree().create_timer(stops[2] + 0.08).timeout
	_spinning = false
	sub_label.text = "消耗铁砧点数摇一次，三格必出同一件装备（仪式感三连）"
	refresh()  # 旋转收尾：用正式单元格重渲染（名称/稀有度/新获取标记）并刷新点数

func _spin_cell(lb: Label, names: Array, stop_at: float, final_d: Dictionary) -> void:
	var t := 0.0
	var step := 0.06
	while t < stop_at:
		# 旋转中屏幕可能被关闭/重建（返回整备、run 重置等），标签已释放则直接退出协程，避免写已释放对象
		if not is_instance_valid(lb):
			return
		lb.text = names[randi() % names.size()]
		t += step
		await get_tree().create_timer(step).timeout
	# 落定到本次真实结果（三连相同）
	if not is_instance_valid(lb):
		return
	if final_d.get("kind", "") == "blank":
		lb.text = "?"
	else:
		lb.text = final_d.get("name", "?")

func _make_placeholder() -> Control:
	var cc = CenterContainer.new()
	cc.custom_minimum_size = Vector2(160, 90)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(156, 86)
	var style = StyleBoxFlat.new()
	style.bg_color = Palette.CARD_BG
	style.border_color = Palette.PANEL_BORDER
	style.set_border_width_all(Palette.BORDER_WIDTH)
	style.set_corner_radius_all(Palette.PANEL_RADIUS)
	panel.add_theme_stylebox_override("panel", style)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	panel.add_child(vb)
	vb.add_child(hud._label("?", TypeScale.META))
	cc.add_child(panel)
	return cc

func _make_cell(d: Dictionary) -> Control:
	var cc = CenterContainer.new()
	cc.custom_minimum_size = Vector2(160, 90)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(156, 86)
	var style = StyleBoxFlat.new()
	style.bg_color = Palette.CARD_BG
	style.border_color = Palette.PANEL_BORDER
	style.set_border_width_all(Palette.BORDER_WIDTH)
	style.set_corner_radius_all(Palette.PANEL_RADIUS)
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

