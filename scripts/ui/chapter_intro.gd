extends Control
class_name ChapterIntro

# M-02b 第2步：章节头 + Boss 信息公开覆盖屏（2026-11-23）。
# 一屏展示两层信息：章节层（幕名/氛围）与 Boss 层（名称/立绘/元素/弱点/抗性/核心机制）。
# 数据只来自 ChapterInfo.for_run() 返回的字典；mechanic_summary 为唯一机制文案源。
# 点击「继续」或按键（ui_accept）/任意键快速跳过关闭；不发奖、不改构筑、不消耗 RNG。
# 每幕只显示一次（屏内 show_for_run 幂等守卫）；已接入线性跨幕与 ACT1 开局。

signal continue_requested(act: int)

const Palette = preload("res://scripts/ui/palette.gd")

@onready var dimmer: ColorRect = $Dimmer
@onready var chapter_label: Label = $Center/Dialog/Margin/Content/ChapterLabel
@onready var ambience_label: Label = $Center/Dialog/Margin/Content/AmbienceLabel
@onready var flow_label: Label = $Center/Dialog/Margin/Content/FlowLabel
@onready var boss_art: TextureRect = $Center/Dialog/Margin/Content/BossRow/BossArt
@onready var boss_info: VBoxContainer = $Center/Dialog/Margin/Content/BossRow/BossInfo
@onready var continue_btn: Button = $Center/Dialog/Margin/Content/ContinueRow/ContinueBtn

var _data: Dictionary = {}
var _shown_acts: Dictionary = {}   # act -> true，每幕只显示一次
var _current_act: int = 0


func _ready() -> void:
	hide()   # 默认隐藏，由 show_for_run 显式展示
	dimmer.color = Palette.BG_OVERLAY
	if continue_btn != null:
		continue_btn.pressed.connect(_on_continue)


# 用 ChapterInfo.for_run() 的数据配置并显示。已显示过的幕不会重复展示。
# 返回 true 表示本次真正显示，false 表示被幂等守卫视掉。
func show_for_run(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var act: int = int(data.get("act", 0))
	if _shown_acts.has(act):
		return false
	_shown_acts[act] = true
	_current_act = act
	_data = data
	_fill(data)
	show()
	return true


func _fill(data: Dictionary) -> void:
	if chapter_label != null:
		chapter_label.text = "— %s · 章节 —" % String(data.get("chapter_name", ""))
	if ambience_label != null:
		ambience_label.text = String(data.get("ambience", ""))
	if flow_label != null:
		var flow: Array = data.get("flow", [])
		flow_label.text = "本幕流程：" + " → ".join(PackedStringArray(flow)) if flow.size() > 0 else ""
	if boss_art != null:
		var tex = data.get("boss_art")
		boss_art.texture = tex if tex is Texture2D else null   # expand/stretch 由 .tscn 固定
	_boss_info_box(data)


func _boss_info_box(data: Dictionary) -> void:
	if boss_info == null:
		return
	for c in boss_info.get_children():
		boss_info.remove_child(c)   # 立即移除，避免同帧内旧标签仍在（空机制防回归断言）
		c.queue_free()
	var boss_name := String(data.get("boss_name", ""))
	var elem_label := String(data.get("boss_element_label", "none"))
	var weak: Array = data.get("weakness", [])
	var resist: Array = data.get("resistance", [])
	var mech := String(data.get("mechanic_summary", ""))

	_add_line("BOSS  %s" % boss_name, 11, Palette.ACCENT_GOLD)
	_add_line("元素：%s   弱点：%s   抗性：%s" % [
		elem_label,
		", ".join(PackedStringArray(weak)) if weak.size() > 0 else "无",
		", ".join(PackedStringArray(resist)) if resist.size() > 0 else "无",
	], 9, Color(0.9, 0.85, 0.75))
	if mech != "":
		_add_line("核心机制：", 9, Color(0.66, 0.61, 0.54))
		var mech_label := Label.new()
		mech_label.text = mech
		mech_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mech_label.custom_minimum_size = Vector2(240, 0)
		mech_label.add_theme_font_size_override("font_size", 8)
		mech_label.add_theme_color_override("font_color", Color(0.78, 0.74, 0.66))
		boss_info.add_child(mech_label)


func _add_line(text: String, size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	boss_info.add_child(l)


func _on_continue() -> void:
	_close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# 按键快速跳过：ui_accept/空格/回车，以及任意键（快速跳过）。
	if event is InputEventKey and event.pressed:
		if not event.is_echo():
			_close()
	elif event.is_action_pressed("ui_accept"):
		_close()


func _close() -> void:
	if not visible:
		return
	hide()
	continue_requested.emit(_current_act)


# 重置用：清空每幕显示记录与残留文本（跨局重置 / 测试）。
func reset_shown() -> void:
	_shown_acts.clear()
	_current_act = 0
	_data = {}
	if chapter_label != null:
		chapter_label.text = ""
	if ambience_label != null:
		ambience_label.text = ""
	if flow_label != null:
		flow_label.text = ""
	if boss_info != null:
		for c in boss_info.get_children():
			boss_info.remove_child(c)
			c.queue_free()
	if boss_art != null:
		boss_art.texture = null
