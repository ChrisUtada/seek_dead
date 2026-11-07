extends Control

# ============================================================================
# G3-01 棋盘静态样稿（2026-11-07）
# 运行（必须窗口模式，headless 无帧缓冲）：
#   Godot_v4.7-stable_win64_console.exe --path <项目> res://tools/g3_mockup.tscn
# 产物：docs/baseline/2026-11-07_g3/board_mockup_{1x,2x,3x}.png
#
# 只画图，不加载对局、不写存档、不碰资源。
# 目的：在改真实 BoardScreen 之前，先确认 480×270 原生布局与视觉语言：
#   - 地图占约 62%（y 26..192），底部详情/构筑/掷骰条 y 194..270
#   - 25 节点 13 列：共享骨架 1 行、岔路 A 上下 2 行、四条尾路 4 行
#   - 道路按 BOARD_EDGES 走直角折线；已走 / 合法 / 未探索三种亮度
#   - 节点头像用几何像素图标，状态框独立绘制（当前 / 合法 / 已消耗）
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-07_g3"

const BG := Color("#160d13")
const MAP_BG := Color("#1a1016")
const TILE := Color("#1e1319")
const ROAD_DIM := Color("#3a2b31")
const ROAD_DONE := Color("#5f4d45")
const GOLD := Color("#d5a33d")
const WARM := Color("#e2d7bd")
const MUTED := Color("#a99d89")
const DIM := Color("#6e5f57")
const ENEMY := Color("#e35b50")
const PANEL := Color("#1d1219")
const GREEN := Color("#a4bc4d")
const BLUE := Color("#62a1c2")

# 新布局坐标：13 列 × 36px；5 行（四尾路 + 中间共享骨架）y = 24 / 58 / 92 / 126 / 160。
const POS := {
	"n0": Vector2(6, 96), "n1": Vector2(42, 96), "n2": Vector2(78, 96),
	"n3": Vector2(114, 96), "n4": Vector2(150, 96), "n5": Vector2(186, 96),
	"n6": Vector2(222, 96),
	"n7": Vector2(258, 60), "n8": Vector2(294, 60), "n9": Vector2(330, 60),
	"n10": Vector2(258, 132), "n11": Vector2(294, 132), "n12": Vector2(330, 132),
	"n13": Vector2(366, 24), "n21": Vector2(402, 24), "n14": Vector2(438, 24),
	"n15": Vector2(366, 60), "n22": Vector2(402, 60), "n16": Vector2(438, 60),
	"n17": Vector2(366, 132), "n23": Vector2(402, 132), "n18": Vector2(438, 132),
	"n19": Vector2(366, 168), "n24": Vector2(402, 168), "n20": Vector2(438, 168),
}

const TYPES := {
	"n0": "start", "n1": "normal", "n2": "weapon", "n3": "normal", "n4": "elite",
	"n5": "charm", "n6": "normal", "n7": "normal", "n8": "elite", "n9": "shop",
	"n10": "normal", "n11": "elite", "n12": "rest", "n13": "normal", "n21": "rest",
	"n14": "boss", "n15": "normal", "n22": "rest", "n16": "boss", "n17": "normal",
	"n23": "rest", "n18": "boss", "n19": "normal", "n24": "rest", "n20": "boss",
}

const EDGES := {
	"n0": ["n1"], "n1": ["n2"], "n2": ["n3"], "n3": ["n4"], "n4": ["n5"],
	"n5": ["n6"], "n6": ["n7", "n10"], "n7": ["n8"], "n8": ["n9"],
	"n9": ["n13", "n15"], "n10": ["n11"], "n11": ["n12"], "n12": ["n17", "n19"],
	"n13": ["n21"], "n21": ["n14"], "n15": ["n22"], "n22": ["n16"],
	"n17": ["n23"], "n23": ["n18"], "n19": ["n24"], "n24": ["n20"],
}

const NODE_W := 34.0
const NODE_H := 28.0

# 样稿状态：走共享骨架 + 上路 + 第一条尾路，停在营地，BOSS 为唯一合法落点。
const CONSUMED := ["n0", "n1", "n2", "n3", "n4", "n5", "n6", "n7", "n8", "n9", "n13"]
const CURRENT := "n21"
const LEGAL := ["n14"]
const BOSS_NAMES := {"n14": "溺王", "n16": "焚王", "n18": "蚀王", "n20": "霜王"}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_window().size = Vector2i(480, 270)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p1 := "%s/board_mockup_1x.png" % OUT_DIR
	print("G3_SHOT|%s|%s" % [p1, img.save_png(p1)])
	# 像素放大用最近邻，避免抗锯齿糊边
	for s in [2, 3]:
		var big := img.duplicate() as Image
		big.resize(480 * s, 270 * s, Image.INTERPOLATE_NEAREST)
		var path := "%s/board_mockup_%dx.png" % [OUT_DIR, s]
		print("G3_SHOT|%s|%s" % [path, big.save_png(path)])
	get_tree().quit()


func _draw() -> void:
	var font := get_theme_default_font()
	# 背景与地图底
	draw_rect(Rect2(0, 0, 480, 270), BG)
	draw_rect(Rect2(0, 0, 480, 22), Color("#120b11"))
	draw_line(Vector2(0, 22), Vector2(480, 22), Color("#3a2b31"), 1)
	draw_rect(Rect2(0, 24, 480, 174), MAP_BG)
	# 低对比石砖网格，只作质感，不进入交互层
	for x in range(0, 481, 16):
		draw_line(Vector2(x, 24), Vector2(x, 198), TILE, 1)
	for y in range(24, 199, 16):
		draw_line(Vector2(0, y), Vector2(480, y), TILE, 1)

	# 道路：已走 / 普通 / 合法三种亮度
	for from_id in EDGES:
		for to_id in EDGES[from_id]:
			var a := _center(String(from_id))
			var b := _center(String(to_id))
			var col := ROAD_DIM
			if String(from_id) in CONSUMED and String(to_id) in CONSUMED:
				col = ROAD_DONE
			if String(to_id) in LEGAL:
				col = GOLD
			_road(a, b, col)

	# 岔路 / 尾路标注：放在空白区，不压节点
	_text(font, Vector2(206, 84), "岔路 A", 8, DIM)
	_text(font, Vector2(250, 44), "尾路 → 四座 BOSS", 8, DIM)

	# 节点
	for id in POS:
		_node(String(id), String(TYPES[id]), POS[id], font)

	# 棋子（当前节点右上）
	var cur := POS[CURRENT] + Vector2(NODE_W - 8, 4)
	draw_circle(cur, 6.0, Color("#1d1219"))
	draw_circle(cur, 5.0, GOLD)
	draw_circle(cur, 2.5, WARM)

	# 顶栏
	_text(font, Vector2(8, 15), "ACT I · 墓道", 10, GOLD)
	_text(font, Vector2(232, 15), "HP 62/80 · 金 41 · 骰 2 · 已走 12/13", 9, MUTED)

	# 底部：节点详情 / 构筑摘要 / 掷骰
	_panel(Rect2(6, 200, 302, 44))
	_panel(Rect2(312, 200, 162, 44))
	_text(font, Vector2(12, 212), "休整营地", 10, WARM)
	_text(font, Vector2(12, 224), "恢复 25% 最大 HP；可花金币购买 1 件", 8, MUTED)
	_text(font, Vector2(12, 235), "（武器 / 护符 / 消耗品，离开不扣费）", 8, MUTED)
	_text(font, Vector2(318, 212), "构筑", 9, GOLD)
	_text(font, Vector2(318, 224), "火焰剑 R3 · 冰刃 R2", 8, WARM)
	_text(font, Vector2(318, 235), "护符 3/4 · 金币 41", 8, MUTED)

	# 掷骰按钮 + 说明
	draw_rect(Rect2(6, 246, 126, 22), PANEL)
	draw_rect(Rect2(6, 246, 126, 22), GOLD, false, 2.0)
	_text(font, Vector2(28, 261), "🎲 前进", 10, WARM)
	_text(font, Vector2(140, 260), "剩 1 步 · 继续前进（BOSS 前营地，离开后可开战）", 9, MUTED)

	# 图例（地图左下空白，低对比）
	_text(font, Vector2(6, 44), "金框=可达 · 暗色=已走 · 红=敌人", 7, DIM)


func _center(id: String) -> Vector2:
	return POS[id] + Vector2(NODE_W * 0.5, NODE_H * 0.5)


# 直角折线：先横到中点、再竖、再横；方头线，无抗锯齿观感。
func _road(a: Vector2, b: Vector2, col: Color) -> void:
	if absf(a.y - b.y) < 0.5:
		draw_rect(Rect2(a.x, a.y - 1.5, b.x - a.x, 3), col)
		return
	var mid := (a.x + b.x) * 0.5
	draw_rect(Rect2(a.x, a.y - 1.5, mid - a.x, 3), col)
	var y0 := minf(a.y, b.y)
	draw_rect(Rect2(mid - 1.5, y0, 3, absf(b.y - a.y)), col)
	draw_rect(Rect2(mid, b.y - 1.5, b.x - mid, 3), col)


func _node(id: String, type: String, pos: Vector2, font: Font) -> void:
	var consumed := id in CONSUMED
	var is_cur := id == CURRENT
	var is_legal := id in LEGAL
	var box := Rect2(pos.x, pos.y, NODE_W, NODE_H)
	var c := pos + Vector2(NODE_W * 0.5, NODE_H * 0.5)
	# 状态框：独立绘制，不烘焙进图标
	draw_rect(box, Color("#120b11") if consumed else PANEL)
	if is_cur:
		draw_rect(box, WARM, false, 2.0)
		draw_rect(Rect2(pos.x, pos.y + NODE_H - 3, NODE_W, 3), GOLD)
	elif is_legal:
		draw_rect(box, GOLD, false, 2.0)
		draw_circle(c + Vector2(13, -10), 2.0, GOLD)
	elif type == "boss":
		draw_rect(box, GOLD, false, 1.0)
	else:
		draw_rect(box, Color("#3a2b31"), false, 1.0)

	var ink := WARM
	if consumed:
		ink = Color("#6e5f57")
	elif type in ["normal", "elite", "boss"]:
		ink = ENEMY
	if type == "boss":
		ink = GOLD

	_icon(type, c + Vector2(0, -4), ink, consumed)
	_text_centered(font, pos + Vector2(NODE_W * 0.5, NODE_H - 1), _tag(id, type), 7,
		Color("#6e5f57") if consumed else WARM)


func _tag(id: String, type: String) -> String:
	if type == "boss":
		return String(BOSS_NAMES.get(id, "王"))
	return {"start": "起", "normal": "战", "elite": "精", "weapon": "武",
		"charm": "符", "shop": "店", "rest": "营"}.get(type, "•")


func _icon(type: String, c: Vector2, ink: Color, consumed: bool) -> void:
	var a := 0.55 if consumed else 1.0
	var col := Color(ink.r, ink.g, ink.b, a)
	match type:
		"start":
			for i in 3:
				draw_rect(Rect2(c.x - 6 + i, c.y + 4 - i * 3, 12 - i * 2, 2), col)
		"normal":
			# 立剑：剑身 + 护手 + 剑柄
			draw_rect(Rect2(c.x - 1, c.y - 7, 2, 10), col)
			draw_rect(Rect2(c.x - 5, c.y + 2, 10, 2), col)
			draw_rect(Rect2(c.x - 1, c.y + 4, 2, 4), col)
		"elite":
			draw_rect(Rect2(c.x - 1, c.y - 7, 2, 10), col)
			draw_rect(Rect2(c.x - 5, c.y + 2, 10, 2), col)
			draw_rect(Rect2(c.x - 1, c.y + 4, 2, 4), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -2), c + Vector2(-5, -5), c + Vector2(-5, 1)]), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(8, -2), c + Vector2(5, -5), c + Vector2(5, 1)]), col)
		"boss":
			# 王冠
			draw_rect(Rect2(c.x - 7, c.y + 1, 14, 3), col)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-7, 1), c + Vector2(-7, -6), c + Vector2(-3, -1),
				c + Vector2(0, -7), c + Vector2(3, -1), c + Vector2(7, -6), c + Vector2(7, 1)]), col)
		"weapon":
			draw_line(c + Vector2(-5, 6), c + Vector2(5, -6), col, 2.0)
			draw_line(c + Vector2(-2, -4), c + Vector2(3, 1), col, 1.0)
		"charm":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -7), c + Vector2(6, 0), c + Vector2(0, 7), c + Vector2(-6, 0)]), col)
			draw_circle(c, 2.0, Color("#120b11"))
		"shop":
			draw_rect(Rect2(c.x - 7, c.y - 6, 14, 2), col)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-7, -4), c + Vector2(7, -4), c + Vector2(6, -1), c + Vector2(-6, -1)]), col)
			draw_rect(Rect2(c.x - 5, c.y + 1, 10, 6), col, false, 1.0)
		"rest":
			# 帐篷
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -7), c + Vector2(8, 7), c + Vector2(-8, 7)]), col)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, 0), c + Vector2(3, 7), c + Vector2(-3, 7)]), Color("#120b11"))


func _panel(r: Rect2) -> void:
	draw_rect(r, PANEL)
	draw_rect(r, Color("#3a2b31"), false, 1.0)


func _text(font: Font, pos: Vector2, text: String, size: int, col: Color) -> void:
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _text_centered(font: Font, center: Vector2, text: String, size: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(center.x - w * 0.5, center.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
