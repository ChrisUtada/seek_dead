extends Node

# ============================================================================
# T3-3 C 轮第 1 步：组合面板组件结构测试（不需要完整战斗）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t3c_combo_panel_test.tscn
# ============================================================================

const PANEL_SCENE := "res://scenes/ui/combo_panel.tscn"

var _fails := 0
var _checks := 0
var _panel: ComboPanel
var _closed := 0


func _on_closed() -> void:
	_closed += 1


func _ready() -> void:
	await get_tree().process_frame
	_panel = (load(PANEL_SCENE) as PackedScene).instantiate() as ComboPanel
	add_child(_panel)
	await get_tree().process_frame
	await _run()
	print("T3CPANEL|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _row(id: String, group: String, name: String, matched: bool, unlocked: bool, contribution: String = "") -> Dictionary:
	return {
		"id": id, "name": name, "group": group, "priority": 10,
		"unlocked": unlocked, "matched_now": matched,
		"condition_text": "条件-%s" % id, "contribution_text": contribution,
	}


func _all_rows() -> Array[Dictionary]:
	return [
		_row("G01", "base", "同源刻", false, true),
		_row("W01", "main", "烈焰共鸣", false, true),
		_row("W07", "main", "强化燃刃", true, true, "🔥 强化燃刃：燃烧 +1 层"),
		_row("T02", "aux", "守护祷言", false, false),
		_row("SIG_W01_FIRESWORD", "signature", "火剑签名", false, false),
		_row("X01", "universal", "通用X", false, true),
	]


func _run() -> void:
	var rows: Array[Dictionary] = _all_rows()
	var before: Array[Dictionary] = []
	for r in rows:
		before.append((r as Dictionary).duplicate(true))

	_panel.open(rows)
	var texts: Array[String] = _panel.rendered_texts
	# 区段标题 5 个且顺序固定
	var titles: Array[String] = []
	for t in texts:
		if t == "基础组合" or t == "主组合" or t == "辅助组合" or t == "签名" or t == "通用":
			titles.append(t)
	_check(titles == ["基础组合", "主组合", "辅助组合", "签名", "通用"],
		"区段标题 5 个且顺序正确（实测 %s）" % str(titles))
	# 行总数 6（标题 5 + 行 6 = 11 条文本）
	_check(texts.size() == 11, "渲染文本 11 条（5 标题 + 6 行，实测 %d）" % texts.size())
	var w07_text := ""
	var t02_text := ""
	for t in texts:
		if t.contains("强化燃刃"):
			w07_text = t
		if t.contains("守护祷言"):
			t02_text = t
	_check(w07_text.contains("已触发") and w07_text.contains("🔥 强化燃刃：燃烧 +1 层"),
		"matched 行含「已触发」与贡献文本（%s）" % w07_text)
	_check(t02_text.contains("未解锁"), "unlocked=false 行含「未解锁」（%s）" % t02_text)

	_panel.close()
	_check(not _panel.visible, "close() 后 visible == false")

	# B2 空分组：只给 main 行
	_panel.open([rows[1]])
	var t2: Array[String] = _panel.rendered_texts
	_check(t2.size() == 2 and t2[0] == "主组合", "只给 main 行时仅显示主组合标题（实测 %s）" % str(t2))
	_panel.close()

	# B3 只读：rows 逐字段一致 + randf 序列不变
	var copied: Array[Dictionary] = []
	for r in rows:
		copied.append((r as Dictionary).duplicate(true))
	_panel.open(copied)
	var after: Array[Dictionary] = _panel.last_rendered_rows
	var same := before.size() == after.size()
	for i in range(mini(before.size(), after.size())):
		if before[i] != after[i]:
			same = false
	_check(same, "B3 传入 rows 内容完全一致（只读快照）")
	seed(1234)
	var seq0: Array[float] = []
	for _i in 4:
		seq0.append(randf())
	seed(1234)
	var _ignored_rows: Array[Dictionary] = _all_rows()
	_panel.open(_ignored_rows)
	var seq1: Array[float] = []
	for _i in 4:
		seq1.append(randf())
	_check(seq0 == seq1, "B3 open() 不消耗 RNG（randf 序列不变）")
	_panel.close()

	# A4-1 同帧连续 open 两次：旧行立即清理，只渲染第二批（A1 remove_child+free）
	_panel.open([rows[1]])
	_panel.open([rows[2]])
	var t3: Array[String] = _panel.rendered_texts
	_check(t3.size() == 2 and t3[0] == "主组合" and t3[1].contains("强化燃刃"),
		"同帧 open 两次只渲染第二批（实测 %s）" % str(t3))
	_panel.close()

	# A4-2 未知 group：落到通用区渲染，行尾标「（未分组）」，不静默丢弃（A2）
	var unknown := _row("Z99", "weird", "未知组", false, true)
	_panel.open([unknown])
	var t4: Array[String] = _panel.rendered_texts
	_check(t4.size() == 2 and t4[0] == "通用", "未知 group 落到通用区（实测 %s）" % str(t4))
	_check(t4.size() == 2 and t4[1].ends_with("（未分组）"),
		"未知 group 行尾标「（未分组）」（实测 %s）" % str(t4))
	_panel.close()

	# A4-3 点 ✕：发出 closed 信号并关闭面板（A3）
	var close_btn := _panel.find_child("CloseBtn", true, false) as Button
	_check(close_btn != null, "✕ 关闭按钮存在")
	_panel.closed.connect(_on_closed)
	_panel.open([rows[1]])
	if close_btn != null:
		close_btn.pressed.emit()
	_check(_closed == 1 and not _panel.visible, "点 ✕ 后发出 closed 且 visible == false（closed=%d）" % _closed)
	_panel.close()
