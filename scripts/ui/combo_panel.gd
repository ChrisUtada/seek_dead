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
# 测试可读的行文本（按渲染顺序，含区段标题与每一行文本），便于结构断言。
var rendered_texts: Array[String] = []


func _ready() -> void:
	visible = false
	var close_btn := find_child("CloseBtn", true, false) as Button
	if close_btn != null:
		close_btn.pressed.connect(_on_close_pressed)
	_clear()


func open(rows: Array[Dictionary]) -> void:
	_clear()
	# A4：不修改传入数组；保存深拷贝快照供只读核对。
	last_rendered_rows = []
	for r in rows:
		last_rendered_rows.append((r as Dictionary).duplicate(true))

	var root: VBoxContainer = _vbox()
	if root == null:
		return
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
	var root: VBoxContainer = _vbox()
	if root == null:
		return
	# A1：remove_child + free() 立即清理（queue_free 会拖到帧末，同帧连续 open 时旧行残留）。
	for c in root.get_children():
		root.remove_child(c)
		c.free()
