extends PanelContainer
class_name ComboPanel

# T3-3 C 轮第 1 步（2026-11-25）：组合面板组件（只读）。
# 只消费 ComboCatalog.build_rows() 的输出；不改传入 rows。
# 铁律：不调用任何结算/面板以外的系统，不读写 enemy_hp / enemy_status / charge / RNG。
# C 轮第 2 步：加滚动与关闭入口（closed 信号），仍不改任何战斗状态。

signal closed   # 点击「✕」后发出（已调用 close()）

const SECTION_ORDER: Array = ["base", "main", "aux", "signature", "universal"]
const SECTION_TITLES := {
	"base": "基础组合",
	"main": "主组合",
	"aux": "辅助组合",
	"signature": "签名",
	"universal": "通用",
}

# 只读快照：供测试核对，不依赖场景树遍历。open() 里以 duplicate(true) 写入。
var last_rendered_rows: Array[Dictionary] = []
var last_rendered_sources: Array[Dictionary] = []
var last_rendered_preview: Array[Dictionary] = []
# 测试可读的行文本（按渲染顺序，含区段标题与每一行文本），便于结构断言。
var rendered_texts: Array[String] = []
# 「本轮来源」区段的行文本（不含标题/分隔），供行数断言。
var rendered_source_texts: Array[String] = []
# 「第三格预览」区段的行文本（不含标题/分隔），供行数断言。
var rendered_preview_texts: Array[String] = []
# 最近一次 open() 是否用了战斗内抽屉布局（测试与排查可读；open_preview 不改它）。
var last_battle_layout := false


func _ready() -> void:
	visible = false
	var close_btn := find_child("CloseBtn", true, false) as Button
	if close_btn != null:
		close_btn.pressed.connect(_on_close_pressed)
	_clear()


func open(rows: Array[Dictionary], sources: Array[Dictionary] = [], preview: Array[Dictionary] = [],
		battle_layout := false) -> void:
	last_battle_layout = battle_layout
	# 战斗内用左侧抽屉：三列转轮与敌方 HP/意图都保持可见；间歇期仍全屏（信息量大，且棋盘已不在看）。
	# 注意用 set_anchors_preset + 显式 offsets：set_anchors_and_offsets_preset 默认按最小尺寸
	# 落位，会把抽屉压成一条窄缝。
	offset_top = 0
	offset_bottom = 0
	if battle_layout:
		set_anchors_preset(Control.PRESET_LEFT_WIDE)
		offset_left = 0
		offset_top = 0
		offset_right = 150
		offset_bottom = 0
	else:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		offset_left = 0
		offset_top = 0
		offset_right = 0
		offset_bottom = 0
	_open_impl(rows, sources, preview)


# 单独刷新「第三格预览」区段：沿用当前 rows/sources 快照重绘（只读，不触发任何战斗逻辑）。
func open_preview(preview_rows: Array[Dictionary]) -> void:
	_open_impl(last_rendered_rows, last_rendered_sources, preview_rows)


func _open_impl(rows: Array[Dictionary], sources: Array[Dictionary], preview: Array[Dictionary]) -> void:
	_clear()
	# A4：不修改传入数组；保存深拷贝快照供只读核对。
	last_rendered_rows = []
	for r in rows:
		last_rendered_rows.append((r as Dictionary).duplicate(true))
	last_rendered_sources = []
	for s in sources:
		last_rendered_sources.append((s as Dictionary).duplicate(true))
	last_rendered_preview = []
	for p in preview:
		last_rendered_preview.append((p as Dictionary).duplicate(true))

	var root: VBoxContainer = _vbox()
	if root == null:
		return
	# C1/C2：来源区在组合区段之前，仅 sources 非空时显示；与组合区用一条「—」分隔。
	_render_sources(root)
	# C1：第三格预览独立区段，位于来源区之后、组合区之前；仅 preview 非空时显示。
	_render_preview(root)
	for group in SECTION_ORDER:
		var g := String(group)
		var group_rows: Array[Dictionary] = []
		var group_ungrouped: Array[bool] = []
		for r in last_rendered_rows:
			var raw_group := String(r.get("group", ""))
			# A2：未知分组不丢弃——落到 universal 区渲染，并在行尾标注「（未分组）」。
			var ungrouped := not SECTION_ORDER.has(raw_group)
			var bucket := "universal" if ungrouped else raw_group
			if bucket == g:
				group_rows.append(r)
				group_ungrouped.append(ungrouped)
		if group_rows.is_empty():
			continue   # 空分组不显示标题
		var title := Label.new()
		title.text = String(SECTION_TITLES.get(g, g))
		root.add_child(title)
		rendered_texts.append(title.text)
		for i in group_rows.size():
			var line := Label.new()
			line.text = _row_text(group_rows[i])
			if group_ungrouped[i]:
				line.text += "（未分组）"
			root.add_child(line)
			rendered_texts.append(line.text)
	visible = true


func close() -> void:
	visible = false


func _on_close_pressed() -> void:
	close()
	closed.emit()


func _vbox() -> VBoxContainer:
	return find_child("VBox", true, false) as VBoxContainer


# 本轮来源：标题 + 每行「标签  数值 单位」+ 一条「—」分隔（轻量，不引入新主题）。
func _render_sources(root: VBoxContainer) -> void:
	if last_rendered_sources.is_empty():
		return
	var title := Label.new()
	title.text = "本轮来源"
	root.add_child(title)
	rendered_texts.append(title.text)
	for s in last_rendered_sources:
		var line := Label.new()
		line.text = ("%s  %d %s" % [
			String(s.get("label", "")),
			int(s.get("value", 0)),
			String(s.get("unit", "")),
		]).strip_edges()
		root.add_child(line)
		rendered_texts.append(line.text)
		rendered_source_texts.append(line.text)
	var sep := Label.new()
	sep.text = "—"
	root.add_child(sep)
	rendered_texts.append(sep.text)


# 第三格预览：每候选一行「符号名：命中组合1、命中组合2」；无命中显示「无组合」。
func _render_preview(root: VBoxContainer) -> void:
	if last_rendered_preview.is_empty():
		return
	var title := Label.new()
	title.text = "第三格预览"
	root.add_child(title)
	rendered_texts.append(title.text)
	for p in last_rendered_preview:
		var names: Array[String] = []
		for m in (p.get("matched", []) as Array):
			if not (m is Dictionary):
				continue
			var nm := String((m as Dictionary).get("name", ""))
			if nm != "" and not names.has(nm):
				names.append(nm)
		var hits := "、".join(names) if not names.is_empty() else "无组合"
		var line := Label.new()
		line.text = "%s：%s" % [String(p.get("candidate_name", "")), hits]
		root.add_child(line)
		rendered_texts.append(line.text)
		rendered_preview_texts.append(line.text)
	var sep := Label.new()
	sep.text = "—"
	root.add_child(sep)
	rendered_texts.append(sep.text)


func _row_text(row: Dictionary) -> String:
	var name_text: String = String(row.get("name", ""))
	var cond: String = String(row.get("condition_text", ""))
	var status: String
	if bool(row.get("matched_now", false)):
		status = "已触发"
	elif bool(row.get("unlocked", false)):
		status = "可用"
	else:
		status = "未解锁"
	var text := "%s｜条件：%s｜%s" % [name_text, cond, status]
	if bool(row.get("matched_now", false)):
		var contrib: String = String(row.get("contribution_text", ""))
		if contrib != "":
			text += "｜%s" % contrib
	return text


func _clear() -> void:
	rendered_texts = []
	rendered_source_texts = []
	rendered_preview_texts = []
	last_rendered_sources = []
	last_rendered_preview = []
	var root: VBoxContainer = _vbox()
	if root == null:
		return
	# A1：remove_child + free() 立即清理（queue_free 会拖到帧末，同帧连续 open 时旧行残留）。
	for c in root.get_children():
		root.remove_child(c)
		c.free()
