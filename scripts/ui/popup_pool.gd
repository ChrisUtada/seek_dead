extends Control
# popup_pool.gd — 战斗飘字对象池（2026-11-08 G8 从 battle_hud 拆出）
#
# 满屏忽略鼠标的浮层 + 预建 Label 池：借出 → 上浮淡出 → 归还，避免每次 new/queue_free。
# 纯展示：不读写战斗状态、不消耗 RNG、不改变任何结算时序。
#
# 用法：由 BattleHud 创建并 add_child，调用 popup(text, color, anchor)。

const POOL_SIZE := 16
const RISE_PX := 14.0
const DURATION := 0.8
# 🔴 同锚点堆叠：一回合内金币/护盾/治疗会在同一帧各自弹字，原来全部从同一个 y 起跳、
# 上浮路径完全重合 → 数字叠死读不出来。这里按「该锚点当前活跃飘字条数」逐条上移，
# 让同时出现的数字垂直错开。上限 STACK_MAX 防止堆太高压出屏幕。
const STACK_STEP := 13.0
const STACK_MAX := 4

var _free: Array = []   # 空闲 Label 栈（池空时临时扩容，归还后留在池中）
var _stack_depth: Dictionary = {}   # anchor instance_id -> 当前活跃飘字条数


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in POOL_SIZE:
		_free.append(_make_label())


func _make_label() -> Label:
	var l := Label.new()
	l.visible = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	return l


# 在 anchor 面板顶部中央弹出并上浮淡出。
# 同一锚点已有飘字在场时，本条自动上移 STACK_STEP，避免完全重叠。
func popup(text: String, color: Color, anchor: Control) -> void:
	if anchor == null:
		return
	var key: int = anchor.get_instance_id()
	var depth: int = int(_stack_depth.get(key, 0))
	_stack_depth[key] = depth + 1
	var offset: float = float(mini(depth, STACK_MAX)) * STACK_STEP
	var lbl: Label = _free.pop_back() if not _free.is_empty() else _make_label()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", TypeScale.OVERLAY)
	lbl.add_theme_color_override("font_color", color)
	lbl.modulate = Color(1, 1, 1, 1)
	lbl.visible = true
	var gp := anchor.get_global_rect()
	var pr := get_global_rect()
	var w := lbl.get_minimum_size().x
	lbl.position = Vector2(gp.position.x - pr.position.x + gp.size.x * 0.5 - w * 0.5,
		gp.position.y - pr.position.y + 2 - offset)
	var tw := create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - RISE_PX, DURATION)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, DURATION)
	tw.tween_callback(_return_popup.bind(lbl, key))


func _return_popup(lbl: Label, key: int) -> void:
	lbl.visible = false
	if not _free.has(lbl):
		_free.append(lbl)
	var n: int = int(_stack_depth.get(key, 1)) - 1
	if n <= 0:
		_stack_depth.erase(key)
	else:
		_stack_depth[key] = n
