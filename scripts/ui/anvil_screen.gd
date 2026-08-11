extends Control
class_name AnvilScreen

# anvil_screen — 铁砧纯 gacha 覆盖层（§6 纯 gacha 定案：抽装备注入 owned_* 拥有池）
# 静态骨架由 anvil_screen.tscn 提供；本脚本负责显隐 / 填数据 / 摇按钮 / 旋转三连仪式动画。

var controller
var hud: BattleHud
const ANVIL_CELL = preload("res://scenes/ui/anvil_cell.tscn")

var _spinning := false
var _stop_all := false
const _SPIN_AUTO_STOP := 4.0   # 手动按停超时兜底（防软锁：不点也会停）

@onready var bg = $Bg
@onready var title_label = $Margin/Content/TitleLabel
@onready var points_label = $Margin/Content/PointsLabel
@onready var sub_label = $Margin/Content/SubLabel
@onready var info_label = $Margin/Content/InfoLabel
@onready var reel_box = $Margin/Content/ReelBox
@onready var roll_btn = $Margin/Content/Bot/RollBtn
@onready var back_btn = $Margin/Content/Bot/BackBtn

func configure(ctrl, h: BattleHud) -> void:
	controller = ctrl
	hud = h
	bg.color = Palette.BG_ANVIL
	title_label.text = "🔨 铁砧 · 抽装备"
	sub_label.text = "消耗铁砧点数摇一次，三格必出同一件装备（仪式感三连）"
	# 摇/返回按钮为静态节点（anvil_screen.tscn），这里只填动态文案 + 接线
	roll_btn.text = "🔨 摇动 (%d点)" % controller.BALANCE.anvil_roll_cost
	roll_btn.connect("pressed", _on_roll_pressed)
	back_btn.connect("pressed", hud.anvil_back_requested.emit)

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
	if info["not_yet"] > 0 and pity >= controller.BALANCE.anvil_pity_max:
		pity_txt = "（保底触发：下次必出未拥有）"
	info_label.text = "图鉴 %.0f%%  已拥有 %d / 全池 %d\n未拥有 %d 件 · 连续重复 %d/%d %s" % [
		info["pct"] * 100, info["owned"], info["total"], info["not_yet"], pity, controller.BALANCE.anvil_pity_max, pity_txt]
	for c in reel_box.get_children():
		reel_box.remove_child(c)
		c.queue_free()
	if controller._anvil_system.last_anvil_drops.is_empty():
		# 未摇过：单格显示问号，制造悬念
		reel_box.add_child(_make_placeholder())
	else:
		for d in controller._anvil_system.last_anvil_drops:
			reel_box.add_child(_make_cell(d))
func _on_roll_pressed() -> void:
	if _spinning:
		# 转动中：按钮变为「停止」，一键停止转轮
		_stop_all = true
		return
	if controller.meta["anvil_points"] < controller.BALANCE.anvil_roll_cost:
		sub_label.text = "铁砧点数不足，先去局内赚点数吧"
		return
	_spinning = true
	_stop_all = false
	roll_btn.text = "⏹ 停止"
	sub_label.text = "转动中…"
	controller._on_anvil_roll_pressed()  # 扣点 + 结算 + 写入 last_anvil_drops（单格结果）
	_play_spin(controller._anvil_system.last_anvil_drops)


func _input(event: InputEvent) -> void:
	# 空格/回车：一键停止转轮（按停便捷键）
	if _spinning and event.is_action_pressed("ui_accept"):
		_stop_all = true
		get_viewport().set_input_as_handled()


func _play_spin(final_drops: Array) -> void:
	# 清空旧格，建立单格转动（手动按停：点格子 / 停止按钮 / 空格）
	for c in reel_box.get_children():
		reel_box.remove_child(c)
		c.queue_free()
	var names = controller._anvil_system.collection_info()["names"]
	var final_d: Dictionary = final_drops[0] if final_drops.size() > 0 else {"kind": "blank"}
	var cell: AnvilCell = ANVIL_CELL.instantiate()
	reel_box.add_child(cell)
	sub_label.text = "点击格子 / 停止按钮（空格停止）"
	await _spin_cell(cell, names, final_d)
	_spinning = false
	roll_btn.text = "🔨 摇动 (%d点)" % controller.BALANCE.anvil_roll_cost
	sub_label.text = "消耗铁砧点数摇一次，单格揭晓装备（物品与稀有度随机）"
	refresh()  # 旋转收尾：用正式单元格重渲染（名称/稀有度/新获取标记）并刷新点数


func _spin_cell(cell: AnvilCell, names: Array, final_d: Dictionary) -> void:
	# 让格子可点：自身接收鼠标，子节点全部 IGNORE（点击穿透到 cell 本体）
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for n in cell.find_children("*", "Control", true, false):
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stopped := false
	var on_click := func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			stopped = true
	cell.gui_input.connect(on_click)
	var t := 0.0
	var step := 0.06
	while not stopped and t < _SPIN_AUTO_STOP:
		# 旋转中屏幕可能被关闭/重建（返回整备、run 重置等），标签已释放则直接退出协程，避免写已释放对象
		if not is_instance_valid(cell):
			return
		if _stop_all:
			stopped = true
		cell.configure(names[randi() % names.size()])
		t += step
		await get_tree().create_timer(step).timeout
	if not is_instance_valid(cell):
		return
	cell.gui_input.disconnect(on_click)
	cell.mouse_default_cursor_shape = Control.CURSOR_ARROW
	# 落定到本次真实结果
	if final_d.get("kind", "") == "blank":
		cell.configure("?")
	else:
		cell.configure(final_d.get("name", "?"))
func _make_placeholder() -> Control:
	var cell: AnvilCell = ANVIL_CELL.instantiate()
	cell.configure("?")
	return cell

func _make_cell(d: Dictionary) -> Control:
	var cell: AnvilCell = ANVIL_CELL.instantiate()
	if d.get("kind", "") == "blank":
		cell.configure("空白格")
	else:
		var tag = "✨ 新获取" if d.get("is_new", false) else "↺ 重复"
		cell.configure(d.get("name", "?"), "%s · %s" % [d.get("rarity", "?"), tag])
		var p: String = d.get("path", "")
		if p != "":
			cell.tooltip_text = ItemTooltip.for_resource(load(p))   # 物品悬停信息窗（ItemTooltip 生成器）
	return cell

func hide_screen() -> void:
	visible = false
