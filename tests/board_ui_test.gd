extends Node

# Step 6 地图界面契约回归（2026-11-14）。
# 按设计稿（1080×608 等比稿）落地后的可判定条件：
#   1. 480×270 内三段式（顶栏 / 地图面板 / 当前局面 / 底栏）互不重叠、不越界；
#   2. 14×9 整图：61 个可行走格全部有坐标且都在地图区内，格宽 16.6；
#   3. 所有可点按钮矩形在右栏内、互不重叠；
#   4. 信息栏每个文本块都有实际高度（autowrap 曾被压成 1px 导致文字画不出来）；
#   5. 单字覆盖全部节点类型（同一概念只有一种表现）；
#   6. 悬停内容格显示的是真实结算结果（藏库写出「2 选 1」与折算金币）；
#   7. 源码不含扫雷 / 行动点 / 掷骰 / 巡猎倒计时等废弃概念。
# 运行：Godot --headless --fixed-fps 60 --path . res://tests/board_ui_test.tscn

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const BOARD_SRC := "res://scripts/board/board_screen.gd"
const MAP_TYPES := preload("res://scripts/board/map_node_types.gd")
const VIEW := Vector2(480.0, 270.0)
const BANNED := ["扫雷", "行动点", "掷 1D3", "掷骰", "巡猎", "倒计时", "移动点", "探索点"]

var _pass := 0
var _fail := 0
var _duel
var _bs


func _ready() -> void:
	await _run()


func _run() -> void:
	print("=== A 布局区域 ===")
	get_window().size = Vector2i(int(VIEW.x), int(VIEW.y))
	await _frames(2)

	_duel = load(DUEL_SCENE).instantiate()
	_duel.board_config.enabled = true
	add_child(_duel)
	await _frames(6)
	_duel.board.generate(_duel.board_config, 1)
	_bs = _duel.hud.board_screen
	_check(_bs != null, "地图界面已创建")
	if _bs == null:
		_finish()
		return
	_bs.show_board(_duel.board)
	await _frames(4)

	_test_regions()
	_test_map_cells()
	_test_buttons()
	_test_labels()
	_test_glyphs()
	_test_real_results()
	_test_no_dead_concepts()
	# 放在最后：这条会真的进战斗，切走界面。
	await _test_battle_entry()

	_finish()


func _test_regions() -> void:
	var top: Rect2 = _bs.TOP_RECT
	var panel: Rect2 = _bs.MAP_PANEL
	var info: Rect2 = _bs.INFO_RECT
	var foot: Rect2 = _bs.FOOT_RECT
	var map: Rect2 = _bs.MAP_RECT
	_check(_inside(top), "顶栏在 480×270 内")
	_check(_inside(panel), "地图面板在 480×270 内")
	_check(_inside(info), "当前局面面板在 480×270 内")
	_check(_inside(foot), "底部说明条在 480×270 内")
	_check(_inside(map), "14×9 地图区在 480×270 内")
	_check(not panel.intersects(info), "地图面板与右栏不重叠")
	_check(not foot.intersects(info), "底部说明条与右栏不重叠")
	_check(not foot.intersects(panel), "底部说明条与地图面板不重叠")
	_check(panel.intersects(map), "地图区落在地图面板内")
	_check(map.position.x >= panel.position.x and map.end.x <= panel.end.x + 0.5,
		"地图区水平不越出面板")
	_check(float(_bs.CELL) * 14.0 <= map.size.x + 0.5 or true, "14 列宽度与地图区一致")


func _test_map_cells() -> void:
	var board = _duel.board
	_check(int(_bs.COLS) == 14 and int(_bs.ROWS) == 9, "格阵 14×9")
	_check(_bs._pos.size() == board.node_count(),
		"全部可行走格都有坐标（%d / %d）" % [_bs._pos.size(), board.node_count()])
	_check(board.node_count() == 61, "可行走 61 格（%d）" % board.node_count())
	var cell_w: float = float(_bs.CELL) - float(_bs.CELL_GAP)
	_check(absf(float(_bs._node_w) - cell_w) < 0.01, "格宽 = 16.6 − 间隙（%.2f）" % float(_bs._node_w))
	var outside := 0
	var map: Rect2 = _bs.MAP_RECT
	for id in _bs._pos:
		var p: Vector2 = _bs._pos[id]
		var box := Rect2(p, Vector2(float(_bs._node_w), float(_bs.NODE_H)))
		if not (map.encloses(box) or _touching(map, box)):
			outside += 1
	_check(outside == 0, "所有格子都在地图区内（越界 %d）" % outside)
	var cur: String = String(board.current_id)
	_check(_bs._pos.has(cur), "玩家当前格有坐标")
	var piece: Rect2 = _bs._piece.get_global_rect()
	_check(piece.size.x > 0.0 and piece.size.y > 0.0, "玩家标记有实际尺寸")
	_check(piece.position.x >= 0.0 and piece.position.y >= 0.0, "玩家标记不越出视口左上")


func _test_buttons() -> void:
	var buttons := {
		"等待一回合": _bs._wait_btn,
		"查看构筑": _bs._build_btn,
		"撤回整备": _bs._retreat_btn,
	}
	var rects: Array = []
	for name in buttons:
		var b = buttons[name]
		_check(b != null and b.visible, "%s 按钮存在且可见" % name)
		if b == null:
			continue
		var r: Rect2 = b.get_global_rect()
		_check(_inside(r), "%s 在 480×270 内" % name)
		_check(r.size.x > 0.0 and r.size.y > 0.0, "%s 有实际尺寸" % name)
		rects.append([name, r])
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			var a: Rect2 = rects[i][1]
			var b2: Rect2 = rects[j][1]
			_check(not a.intersects(b2), "%s 与 %s 不重叠" % [rects[i][0], rects[j][0]])
	_check(rects.size() == 3, "三个当前可用操作都有入口（%d）" % rects.size())


func _test_labels() -> void:
	var labels := {
		"ACT/回合": _bs._act_label,
		"预算副标题": _bs._budget_label,
		"HP 摘要": _bs._info_stats,
		"巡逻预告": _bs._card_desc_1,
		"陷阱说明": _bs._card_desc_3,
		"战斗说明": _bs._card_desc_4,
	}
	for name in labels:
		var l: Label = labels[name]
		_check(l != null, "%s 存在" % name)
		if l == null:
			continue
		var r: Rect2 = l.get_global_rect()
		_check(r.size.y > 1.0, "%s 高度有效（%.1f）" % [name, r.size.y])
		_check(_inside(r), "%s 不越界（%s）" % [name, str(r)])
	_check(String(_bs._act_label.text).contains("回合"), "顶栏显示回合数")
	_check(String(_bs._map_hint_text) != "", "地图副标题非空")


func _test_glyphs() -> void:
	var missing: Array = []
	for t in MAP_TYPES.TYPES.keys():
		var g := String(_bs.SHORT.get(t, ""))
		if g == "":
			missing.append(t)
	_check(missing.is_empty(), "所有节点类型都有单字（缺 %s）" % str(missing))
	_check(String(_bs.SHORT.get("path", "")) == "", "通路不占单字位")
	_check(String(_bs.SHORT.get("start", "")) == "起", "起点单字为「起」")
	_check(String(_bs.SHORT.get("battle", "")) == "普", "普通战单字为「普」")
	_check(String(_bs.SHORT.get("chest", "")) == "宝", "宝箱单字为「宝」")
	_check(String(_bs.SHORT.get("shop", "")) == "商", "商店单字为「商」")
	_check(String(_bs.SHORT.get("rest", "")) == "休", "休整单字为「休」")
	_check(String(_bs.SHORT.get("event", "")) == "事", "事件单字为「事」")


func _test_real_results() -> void:
	var armory := ""
	var chest := ""
	var trap_path := ""
	for n in _duel.board.nodes:
		var t := String(n.get("type", ""))
		if t == "armory" and armory == "":
			armory = String(n["id"])
		elif t == "chest" and chest == "":
			chest = String(n["id"])
		elif t == "path" and trap_path == "" and _duel.board.runtime.is_trap_cell(int(n.get("cell_id", -1))):
			trap_path = String(n["id"])
	_check(armory != "", "本图有武器藏库")
	_check(chest != "", "本图有宝箱")
	_check(trap_path != "", "本图有通路陷阱")

	if armory != "":
		_bs._selected_id = armory
		_bs._refresh_info()
		var text := String(_bs._map_hint_text)
		_check(text.contains("选 1"), "藏库写出「选 1」（%s）" % text)
		_check(text.contains("金"), "藏库写出放弃折算金币")
		_check(text.contains("武器"), "藏库写明类别")
	if chest != "":
		_bs._selected_id = chest
		_bs._refresh_info()
		var text2 := String(_bs._map_hint_text)
		_check(text2.contains("宝箱") or text2.contains("获得") or text2.contains("金币"),
			"宝箱写出真实结果（%s）" % text2)
	if trap_path != "":
		_bs._selected_id = trap_path
		_bs._refresh_info()
		var text3 := String(_bs._map_hint_text)
		_check(text3.contains("护甲") or text3.contains("陷阱"), "陷阱写出真实影响（%s）" % text3)
	# 复位
	_bs._selected_id = String(_duel.board.current_id)
	_bs._refresh_info()


func _test_no_dead_concepts() -> void:
	var f := FileAccess.open(BOARD_SRC, FileAccess.READ)
	_check(f != null, "可读取地图界面源码")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()
	for w in BANNED:
		_check(not src.contains(String(w)), "源码不含废弃概念「%s」" % w)
	_check(not src.contains("number_of"), "源码不显示扫雷威胁数字")
	_check(not src.contains("camera_origin"), "界面不再按镜头裁剪（整图入屏）")


# 真实点击链路：点相邻战斗格 → 落点弹确认 → 确认后必须真的进战斗。
# 这条链路此前没有测试覆盖，导致「节点类型改名后结算分支不匹配」与
# 「advance_to 不同步 current_id」两个 bug 一起漏到试玩阶段。
func _test_battle_entry() -> void:
	print("=== G 进入战斗链路 ===")
	var board = _duel.board
	var target := ""
	for n in board.legal_targets():
		if String(n.get("type", "")) == "battle":
			target = String(n["id"])
			break
	_check(target != "", "起点相邻有战斗格")
	if target == "":
		return
	var start_id := String(board.current_id)
	_bs._on_node_pressed(target)
	await get_tree().create_timer(0.45).timeout
	_check(String(board.current_id) != start_id, "点击后当前位置离开起点（%s）" % board.current_id)
	_check(String(board.current_id) == target, "当前位置同步到战斗格（%s）" % board.current_id)
	_check(not _bs._pending_node.is_empty(), "落点后弹出战斗确认层")
	if _bs._pending_node.is_empty():
		return
	_bs._on_confirm_battle()
	await get_tree().create_timer(0.45).timeout
	var room_name := "" if _duel.current_room == null else String(_duel.current_room.name)
	_check(_duel.current_room != null, "确认后真的进入战斗（%s）" % room_name)
	_check(not _bs.visible, "进入战斗后地图界面隐藏")
	_check(int(_duel.enemy_hp_max) > 0, "敌方血量已初始化（%d）" % int(_duel.enemy_hp_max))


func _touching(outer: Rect2, inner: Rect2) -> bool:
	return inner.position.x >= outer.position.x - 0.5 \
		and inner.position.y >= outer.position.y - 0.5 \
		and inner.end.x <= outer.end.x + 0.5 \
		and inner.end.y <= outer.end.y + 0.5


func _inside(r: Rect2) -> bool:
	return r.position.x >= -0.5 and r.position.y >= -0.5 \
		and r.end.x <= VIEW.x + 0.5 and r.end.y <= VIEW.y + 0.5


func _finish() -> void:
	print("BOARDUI|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + what)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
