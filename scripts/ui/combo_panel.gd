extends PanelContainer
class_name ComboPanel

# T3-3 C 轮第 1 步（2026-11-25）：组合面板组件（只读）。
# 只消费 ComboCatalog.build_rows() 的输出；不接进战斗流程，不改传入 rows。
# 铁律：不调用任何结算/面板以外的系统，不读写 enemy_hp / enemy_status / charge / RNG。

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
	_clear()


func open(rows: Array[Dictionary]) -> void:
	_clear()
	# A4：不修改传入数组；保存深拷贝快照供只读核对。
	last_rendered_rows = []
	for r in rows:
		last_rendered_rows.append((r as Dictionary).duplicate(true))

	var root: VBoxContainer = get_node_or_null("VBox") as VBoxContainer
	if root == null:
		return
	for group in SECTION_ORDER:
		var g := String(group)
		var group_rows: Array[Dictionary] = []
		for r in last_rendered_rows:
			if String(r.get("group", "")) == g:
				group_rows.append(r)
		if group_rows.is_empty():
			continue   # 空分组不显示标题
		var title := Label.new()
		title.text = String(SECTION_TITLES.get(g, g))
		root.add_child(title)
		rendered_texts.append(title.text)
		for r in group_rows:
			var line := Label.new()
			line.text = _row_text(r)
			root.add_child(line)
			rendered_texts.append(line.text)
	visible = true


func close() -> void:
	visible = false


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
	var root: VBoxContainer = get_node_or_null("VBox") as VBoxContainer
	if root == null:
		return
	for c in root.get_children():
		c.queue_free()
