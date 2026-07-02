@tool
extends Node

const DOOR_SCENE := preload("res://scenes/rooms/door_marker.tscn")
const ROOMS_DIR := "res://scenes/rooms/"
const CONFIG_DIR := "res://resources/rooms/"

const LAYER_ENV := 4

const WALL_THICKNESS := 16
const DOOR_WIDTH := 32

enum RoomSize { SMALL, MEDIUM, LARGE, BOSS }

class RoomDef:
	var id: String
	var name: String
	var size: RoomSize
	var nav_rect: Rect2
	var doors: Array[DoorDef]
	var obstacles: Array[ObstacleDef]
	var spawn_count: int
	var has_elite: bool

class DoorDef:
	var edge: int  # 0=top, 1=right, 2=bottom, 3=left
	var pos: float  # position along the edge

class ObstacleDef:
	var type: String  # pillar, crate, bookshelf, counter
	var pos: Vector2


func _ready():
	if Engine.is_editor_hint():
		return
	generate_all()
	print("Generation complete. You can close this scene.")
	get_tree().quit()


func generate_all():
	print("=== Starting room generation ===")

	var rooms := _define_all_rooms()

	for r in rooms:
		_generate_room(r)

	print("=== All rooms generated ===")


func _define_all_rooms() -> Array[RoomDef]:
	var rooms: Array[RoomDef] = []

	var small_nav = Rect2(16, 16, 384, 224)
	var med_nav = Rect2(16, 16, 480, 352)
	var large_nav = Rect2(16, 16, 640, 432)
	var boss_nav = Rect2(16, 16, 640, 448)

	rooms.append(_make("room_01", "石质大厅", RoomSize.SMALL, Rect2(16, 16, 384, 224), [d(0, 192)], [o("pillar", 120, 80), o("pillar", 260, 140)], 5, false, []))
	rooms.append(_make("room_02", "水牢", RoomSize.SMALL, Rect2(16, 16, 288, 256), [d(2, 144)], [o("crate", 80, 120), o("crate", 180, 160)], 4, false, []))
	rooms.append(_make("room_03", "武器库", RoomSize.SMALL, Rect2(16, 16, 352, 224), [d(0, 120), d(2, 120)], [o("counter", 160, 64), o("counter", 160, 160), o("bookshelf", 280, 80)], 4, false, []))
	rooms.append(_make("room_04", "囚室", RoomSize.SMALL, Rect2(16, 16, 320, 256), [d(1, 128), d(2, 160)], [o("pillar", 80, 80), o("pillar", 240, 80), o("pillar", 160, 160)], 5, false, []))
	rooms.append(_make("room_05", "食堂", RoomSize.SMALL, Rect2(16, 16, 352, 288), [d(2, 176)], [o("counter", 100, 80), o("crate", 240, 180)], 5, false, []))

	rooms.append(_make("room_06", "兵营", RoomSize.MEDIUM, med_nav, [d(2, 120), d(3, 240)], [o("pillar", 80, 80), o("pillar", 120, 220), o("crate", 280, 120), o("crate", 320, 260)], 6, true, []))
	rooms.append(_make("room_07", "图书馆", RoomSize.MEDIUM, med_nav, [d(1, 240), d(3, 160)], [o("bookshelf", 160, 80), o("bookshelf", 160, 140), o("bookshelf", 320, 200)], 6, false, []))
	rooms.append(_make("room_08", "实验室", RoomSize.MEDIUM, med_nav, [d(0, 160), d(1, 240), d(2, 160)], [o("counter", 120, 100), o("counter", 260, 200), o("pillar", 200, 160)], 6, true, []))
	rooms.append(_make("room_09", "锻造间", RoomSize.MEDIUM, med_nav, [d(1, 200), d(3, 240)], [o("crate", 80, 120), o("crate", 140, 80), o("crate", 280, 200), o("counter", 320, 100)], 6, false, []))
	rooms.append(_make("room_10", "祭坛", RoomSize.MEDIUM, med_nav, [d(0, 120), d(2, 120)], [o("pillar", 120, 100), o("pillar", 240, 100), o("pillar", 120, 240), o("pillar", 240, 240)], 6, true, []))
	rooms.append(_make("room_11", "仓库", RoomSize.MEDIUM, med_nav, [d(1, 160), d(3, 200)], [o("crate", 80, 80), o("crate", 140, 100), o("crate", 80, 200), o("crate", 140, 220), o("crate", 300, 120), o("crate", 300, 200)], 6, false, []))
	rooms.append(_make("room_12", "宴会厅", RoomSize.MEDIUM, med_nav, [d(0, 80), d(1, 240), d(3, 80)], [o("counter", 160, 80), o("counter", 240, 200), o("bookshelf", 80, 180), o("bookshelf", 360, 180)], 6, true, []))
	rooms.append(_make("room_13", "演武场", RoomSize.MEDIUM, med_nav, [d(0, 160), d(2, 160)], [], 8, true, []))

	rooms.append(_make("room_14", "花园", RoomSize.LARGE, large_nav, [d(0, 80), d(1, 320), d(2, 80)], [o("pillar", 100, 80), o("pillar", 200, 80), o("pillar", 400, 160), o("pillar", 500, 200), o("pillar", 200, 300), o("pillar", 400, 360)], 8, false, []))
	rooms.append(_make("room_15", "军械库", RoomSize.LARGE, large_nav, [d(1, 160), d(3, 320), d(2, 240)], [o("crate", 120, 100), o("crate", 180, 80), o("crate", 120, 200), o("crate", 400, 150), o("counter", 320, 100), o("counter", 320, 280)], 8, true, []))
	rooms.append(_make("room_16", "大殿", RoomSize.LARGE, large_nav, [d(1, 320), d(3, 320)], [o("bookshelf", 160, 80), o("bookshelf", 160, 160), o("bookshelf", 160, 240), o("bookshelf", 480, 80), o("pillar", 320, 160), o("pillar", 320, 280)], 8, true, []))
	rooms.append(_make("room_17", "地下河", RoomSize.LARGE, large_nav, [d(0, 160), d(1, 480), d(2, 160)], [o("pillar", 80, 120), o("pillar", 160, 200), o("crate", 400, 100), o("crate", 500, 300)], 8, false, []))
	rooms.append(_make("room_18", "宝库", RoomSize.LARGE, large_nav, [d(0, 80), d(1, 160), d(2, 80), d(3, 240)], [o("crate", 160, 80), o("crate", 240, 80), o("crate", 360, 160), o("crate", 440, 240), o("counter", 80, 200), o("counter", 500, 300)], 8, true, []))
	rooms.append(_make("room_19", "迷宫", RoomSize.LARGE, Rect2(16, 16, 480, 416), [d(1, 128), d(1, 384)], [o("bookshelf", 120, 80), o("bookshelf", 120, 200), o("bookshelf", 240, 160), o("bookshelf", 240, 320), o("bookshelf", 360, 80), o("bookshelf", 360, 240)], 6, false, []))
	rooms.append(_make("room_20", "角斗场", RoomSize.LARGE, large_nav, [d(0, 240), d(2, 240)], [o("pillar", 80, 80), o("pillar", 560, 80), o("pillar", 80, 360), o("pillar", 560, 360)], 10, true, []))
	rooms.append(_make("room_21", "教堂", RoomSize.LARGE, large_nav, [d(0, 160), d(2, 160), d(3, 80)], [o("pillar", 160, 80), o("pillar", 320, 80), o("pillar", 480, 80), o("bookshelf", 80, 200), o("bookshelf", 560, 200)], 8, true, []))

	rooms.append(_make("room_22", "巨龙巢穴", RoomSize.BOSS, boss_nav, [d(0, 320)], [o("pillar", 80, 80), o("pillar", 560, 80), o("pillar", 80, 380), o("pillar", 560, 380)], 10, false, [true]))
	rooms.append(_make("room_23", "巫妖塔顶", RoomSize.BOSS, Rect2(16, 16, 512, 384), [d(2, 256)], [o("pillar", 160, 80), o("pillar", 320, 80), o("pillar", 240, 200)], 8, false, [true]))
	rooms.append(_make("room_24", "深渊裂隙", RoomSize.BOSS, boss_nav, [d(1, 320), d(3, 320)], [o("pillar", 120, 100), o("pillar", 200, 200), o("pillar", 320, 150), o("pillar", 440, 300), o("pillar", 520, 200), o("pillar", 400, 80)], 10, false, [true]))
	rooms.append(_make("room_25", "最终之间", RoomSize.BOSS, boss_nav, [d(0, 320)], [o("pillar", 160, 160), o("pillar", 320, 160), o("pillar", 480, 160), o("crate", 160, 300), o("crate", 480, 300)], 12, false, [true]))

	return rooms


func _make(id: String, name: String, size: RoomSize, nav_rect: Rect2, doors: Array, obstacles: Array, spawn_count: int, has_elite: bool, boss_flags: Array = []) -> RoomDef:
	var r := RoomDef.new()
	r.id = id
	r.name = name
	r.size = size
	r.nav_rect = nav_rect
	r.doors = doors
	r.obstacles = obstacles
	r.spawn_count = spawn_count
	r.has_elite = has_elite or (size == RoomSize.BOSS)
	return r


func d(edge: int, pos: float) -> DoorDef:
	var dd := DoorDef.new()
	dd.edge = edge
	dd.pos = pos
	return dd


func o(type: String, x: float, y: float) -> ObstacleDef:
	var od := ObstacleDef.new()
	od.type = type
	od.pos = Vector2(x, y)
	return od


func _generate_room(r: RoomDef):
	var outer := _outer_rect(r.nav_rect)
	var path := ROOMS_DIR + r.id + ".tscn"
	print("Generating ", path)

	var scene_text := _build_scene_text(r, outer)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(scene_text)
	file.close()

	var res_path := CONFIG_DIR + r.id + ".tres"
	var config_text := _build_config_text(r)
	var cfg_file := FileAccess.open(res_path, FileAccess.WRITE)
	cfg_file.store_string(config_text)
	cfg_file.close()

	print("  -> ", path)
	print("  -> ", res_path)


func _outer_rect(nav: Rect2) -> Rect2:
	return Rect2(
		nav.position.x - WALL_THICKNESS,
		nav.position.y - WALL_THICKNESS,
		nav.size.x + WALL_THICKNESS * 2,
		nav.size.y + WALL_THICKNESS * 2
	)


func _build_scene_text(r: RoomDef, outer: Rect2) -> String:
	var lines: Array[String] = []
	lines.append("[gd_scene format=4]")
	lines.append("")

	var door_ref := "[ext_resource type=\"PackedScene\" path=\"res://scenes/rooms/door_marker.tscn\" id=\"1_1adhe\"]"
	lines.append(door_ref)
	lines.append("")

	var nav_poly_id := "NavigationPolygon_yxrvq"
	lines.append("[sub_resource type=\"NavigationPolygon\" id=\"" + nav_poly_id + "\"]")

	var nav := r.nav_rect
	var verts := PackedVector2Array([
		Vector2(nav.position.x, nav.position.y),
		Vector2(nav.position.x + nav.size.x, nav.position.y),
		Vector2(nav.position.x + nav.size.x, nav.position.y + nav.size.y),
		Vector2(nav.position.x, nav.position.y + nav.size.y),
	])
	var vert_str := ""
	for v in verts:
		vert_str += str(v.x) + ", " + str(v.y) + ", "
	vert_str = vert_str.trim_suffix(", ")
	lines.append("vertices = PackedVector2Array(" + vert_str + ")")
	lines.append("polygons = Array[PackedInt32Array]([PackedInt32Array(0, 1, 2, 3)])")
	lines.append("")

	lines.append("[node name=\"" + r.id + "\" type=\"Node2D\"]")
	lines.append("")

	lines.append("[node name=\"NavigationRegion2D\" type=\"NavigationRegion2D\" parent=\".\"]")
	lines.append("navigation_polygon = SubResource(\"" + nav_poly_id + "\")")
	lines.append("")

	lines.append("[node name=\"Floor\" type=\"Node2D\" parent=\".\"]")
	lines.append("")

	var floor_color := "\"#2a2a2a\""
	lines.append("[node name=\"ColorRect\" type=\"ColorRect\" parent=\"Floor\"]")
	lines.append("color = Color(" + floor_color + ")")
	lines.append("size = Vector2(" + str(nav.size.x) + ", " + str(nav.size.y) + ")")
	lines.append("position = Vector2(" + str(nav.position.x) + ", " + str(nav.position.y) + ")")
	lines.append("")

	for i in r.doors.size():
		var dd := r.doors[i] as DoorDef
		var glow_pos := _door_glow_pos(dd, outer)
		lines.append("[node name=\"DoorGlow" + str(i + 1) + "\" type=\"ColorRect\" parent=\"Floor\"]")
		lines.append("color = Color(0, 1, 0.267, 0.3)")
		lines.append("size = Vector2(32, 16)")
		lines.append("position = Vector2(" + str(glow_pos.x) + ", " + str(glow_pos.y) + ")")
	lines.append("")

	lines.append("[node name=\"Walls\" type=\"Node2D\" parent=\".\"]")
	lines.append("")

	var wall_segments := _calc_wall_segments(r, outer)
	for i in wall_segments.size():
		var ws := wall_segments[i]
		lines.append("[node name=\"" + ws.name + "\" type=\"StaticBody2D\" parent=\"Walls\"]")
		lines.append("collision_layer = " + str(LAYER_ENV))
		lines.append("")
		var shape_id := "RectangleShape2D_" + ws.name
		lines.append("[sub_resource type=\"RectangleShape2D\" id=\"" + shape_id + "\"]")
		lines.append("size = Vector2(" + str(ws.size.x) + ", " + str(ws.size.y) + ")")
		lines.append("")
		lines.append("[node name=\"CollisionShape2D\" type=\"CollisionShape2D\" parent=\"Walls/" + ws.name + "\"]")
		lines.append("shape = SubResource(\"" + shape_id + "\")")
		lines.append("position = Vector2(" + str(ws.pos.x) + ", " + str(ws.pos.y) + ")")
		lines.append("")

	lines.append("[node name=\"Obstacles\" type=\"Node2D\" parent=\".\"]")
	lines.append("")

	for i in r.obstacles.size():
		var ob := r.obstacles[i] as ObstacleDef
		var obs_name := ob.type.capitalize() + "_" + str(i + 1)
		var obs_size := _obstacle_size(ob.type)
		lines.append("[node name=\"" + obs_name + "\" type=\"StaticBody2D\" parent=\"Obstacles\"]")
		lines.append("collision_layer = " + str(LAYER_ENV))
		lines.append("position = Vector2(" + str(ob.pos.x) + ", " + str(ob.pos.y) + ")")
		lines.append("")
		var obs_shape_id := "RectangleShape2D_" + obs_name
		lines.append("[sub_resource type=\"RectangleShape2D\" id=\"" + obs_shape_id + "\"]")
		lines.append("size = Vector2(" + str(obs_size.x) + ", " + str(obs_size.y) + ")")
		lines.append("")
		lines.append("[node name=\"CollisionShape2D\" type=\"CollisionShape2D\" parent=\"Obstacles/" + obs_name + "\"]")
		lines.append("shape = SubResource(\"" + obs_shape_id + "\")")
		lines.append("")
		lines.append("[node name=\"NavigationObstacle2D\" type=\"NavigationObstacle2D\" parent=\"Obstacles/" + obs_name + "\"]")
		lines.append("avoidance_enabled = true")
		lines.append("radius = 12.0")
		lines.append("")

	lines.append("[node name=\"Markers\" type=\"Node2D\" parent=\".\"]")
	lines.append("")

	var spawn_positions := _calc_spawn_positions(r, outer)
	lines.append("[node name=\"PlayerSpawn\" type=\"Marker2D\" parent=\"Markers\"]")
	lines.append("position = Vector2(" + str(spawn_positions.player.x) + ", " + str(spawn_positions.player.y) + ")")
	lines.append("")

	for i in spawn_positions.spawns.size():
		var sp := spawn_positions.spawns[i]
		lines.append("[node name=\"SpawnMarker" + str(i + 1) + "\" type=\"Marker2D\" parent=\"Markers\"]")
		lines.append("position = Vector2(" + str(sp.x) + ", " + str(sp.y) + ")")
		lines.append("groups = [\"spawn\"]")
		lines.append("")

	if r.size == RoomSize.BOSS:
		lines.append("[node name=\"SpawnMarker_Boss\" type=\"Marker2D\" parent=\"Markers\"]")
		lines.append("position = Vector2(" + str(spawn_positions.player.x) + ", " + str(spawn_positions.player.y - 80) + ")")
		lines.append("")

	var interactables := _calc_interactables(r, outer)
	for key in interactables:
		var ip := interactables[key]
		lines.append("[node name=\"" + key + "\" type=\"Marker2D\" parent=\"Markers\"]")
		lines.append("position = Vector2(" + str(ip.x) + ", " + str(ip.y) + ")")
		lines.append("groups = [\"interactable\"]")
		lines.append("")

	lines.append("[node name=\"Doors\" type=\"Node2D\" parent=\".\"]")
	lines.append("")

	for i in r.doors.size():
		var dd := r.doors[i] as DoorDef
		var door_pos := _door_pos(dd, outer)
		var dir_name := ["RIGHT", "DOWN", "LEFT", "UP"][dd.edge]
		lines.append("[node name=\"DoorMarker" + str(i + 1) + "\" parent=\"Doors\" instance=ExtResource(\"1_1adhe\")]")
		lines.append("position = Vector2(" + str(door_pos.x) + ", " + str(door_pos.y) + ")")
		if i == 0:
			lines.append("direction = " + str(dd.edge))
			lines.append("is_entrance = true")
		else:
			lines.append("direction = " + str(dd.edge))

	return "\n".join(lines)


func _build_config_text(r: RoomDef) -> String:
	var lines: Array[String] = []
	lines.append("[gd_resource type=\"Resource\" script_class=\"RoomConfig\" format=3]")
	lines.append("")
	lines.append("[ext_resource type=\"Script\" path=\"res://scripts/rooms/room_config.gd\" id=\"1\"]")
	lines.append("[ext_resource type=\"PackedScene\" path=\"res://scenes/rooms/" + r.id + ".tscn\" id=\"2\"]")
	lines.append("[ext_resource type=\"PackedScene\" path=\"res://scenes/enemies/goblin.tscn\" id=\"3\"]")
	lines.append("[ext_resource type=\"PackedScene\" path=\"res://scenes/enemies/skeleton.tscn\" id=\"4\"]")
	lines.append("")
	lines.append("[resource]")
	lines.append("script = ExtResource(\"1\")")
	lines.append("scene = ExtResource(\"2\")")
	lines.append("room_name = \"" + r.name + "\"")
	lines.append("room_size = " + str(r.size))

	var min_enemy := 3
	var max_enemy := 6
	match r.size:
		RoomSize.MEDIUM:
			min_enemy = 5; max_enemy = 8
		RoomSize.LARGE:
			min_enemy = 6; max_enemy = 10
		RoomSize.BOSS:
			min_enemy = 0; max_enemy = 0

	lines.append("min_enemies = " + str(min_enemy))
	lines.append("max_enemies = " + str(max_enemy))

	if r.size == RoomSize.BOSS:
		lines.append("boss_count = 1")
		lines.append("")
		var pool := "enemy_pool = Array[PackedScene]([])"

		lines.append(pool)
		lines.append("has_elite = false")
	else:
		lines.append("enemy_pool = Array[PackedScene]([ExtResource(\"3\"), ExtResource(\"4\")])")
		lines.append("has_elite = " + ("true" if r.has_elite else "false"))

	if r.size == RoomSize.BOSS:
		lines.append("boss_pool = Array[PackedScene]([])")

	lines.append("")
	return "\n".join(lines)


func _calc_wall_segments(r: RoomDef, outer: Rect2) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []

	var top_gaps: Array[float] = []
	var bot_gaps: Array[float] = []
	var left_gaps: Array[float] = []
	var right_gaps: Array[float] = []

	for dd in r.doors:
		var d := dd as DoorDef
		var half := DOOR_WIDTH / 2.0
		match d.edge:
			0: top_gaps.append(d.pos)
			1: right_gaps.append(d.pos)
			2: bot_gaps.append(d.pos)
			3: left_gaps.append(d.pos)

	top_gaps.sort()
	bot_gaps.sort()
	left_gaps.sort()
	right_gaps.sort()

	var ox := outer.position.x
	var oy := outer.position.y
	var ow := outer.size.x
	var oh := outer.size.y

	var half_door := DOOR_WIDTH / 2.0

	if top_gaps.is_empty():
		segments.append({"name": "TopWall", "pos": Vector2(ox + ow / 2, oy), "size": Vector2(ow, WALL_THICKNESS)})
	else:
		var prev := ox
		for i in top_gaps.size():
			var g := top_gaps[i]
			var left_end := g - half_door
			var right_start := g + half_door
			if left_end > prev + 1:
				var seg_w := left_end - prev
				segments.append({"name": "TopWall_L" + str(i + 1) if i == 0 else "TopWall_" + str(i + 1), "pos": Vector2(prev + seg_w / 2, oy), "size": Vector2(seg_w, WALL_THICKNESS)})
			prev = right_start
		if outer.position.x + ow > prev + 1:
			var seg_w := (outer.position.x + ow) - prev
			segments.append({"name": "TopWall_R", "pos": Vector2(prev + seg_w / 2, oy), "size": Vector2(seg_w, WALL_THICKNESS)})

	if bot_gaps.is_empty():
		segments.append({"name": "BottomWall", "pos": Vector2(ox + ow / 2, oy + oh), "size": Vector2(ow, WALL_THICKNESS)})
	else:
		var prev := ox
		for i in bot_gaps.size():
			var g := bot_gaps[i]
			var left_end := g - half_door
			var right_start := g + half_door
			if left_end > prev + 1:
				var seg_w := left_end - prev
				segments.append({"name": "BottomWall_L" + str(i + 1) if i == 0 else "BottomWall_" + str(i + 1), "pos": Vector2(prev + seg_w / 2, oy + oh), "size": Vector2(seg_w, WALL_THICKNESS)})
			prev = right_start
		if ox + ow > prev + 1:
			var seg_w := (ox + ow) - prev
			segments.append({"name": "BottomWall_R", "pos": Vector2(prev + seg_w / 2, oy + oh), "size": Vector2(seg_w, WALL_THICKNESS)})

	if left_gaps.is_empty():
		segments.append({"name": "LeftWall", "pos": Vector2(ox, oy + oh / 2), "size": Vector2(WALL_THICKNESS, oh)})
	else:
		var prev := oy
		for i in left_gaps.size():
			var g := left_gaps[i]
			var top_end := g - half_door
			var bot_start := g + half_door
			if top_end > prev + 1:
				var seg_h := top_end - prev
				segments.append({"name": "LeftWall_T" + str(i + 1) if i == 0 else "LeftWall_" + str(i + 1), "pos": Vector2(ox, prev + seg_h / 2), "size": Vector2(WALL_THICKNESS, seg_h)})
			prev = bot_start
		if oy + oh > prev + 1:
			var seg_h := (oy + oh) - prev
			segments.append({"name": "LeftWall_B", "pos": Vector2(ox, prev + seg_h / 2), "size": Vector2(WALL_THICKNESS, seg_h)})

	if right_gaps.is_empty():
		segments.append({"name": "RightWall", "pos": Vector2(ox + ow, oy + oh / 2), "size": Vector2(WALL_THICKNESS, oh)})
	else:
		var prev := oy
		for i in right_gaps.size():
			var g := right_gaps[i]
			var top_end := g - half_door
			var bot_start := g + half_door
			if top_end > prev + 1:
				var seg_h := top_end - prev
				segments.append({"name": "RightWall_T" + str(i + 1) if i == 0 else "RightWall_" + str(i + 1), "pos": Vector2(ox + ow, prev + seg_h / 2), "size": Vector2(WALL_THICKNESS, seg_h)})
			prev = bot_start
		if oy + oh > prev + 1:
			var seg_h := (oy + oh) - prev
			segments.append({"name": "RightWall_B", "pos": Vector2(ox + ow, prev + seg_h / 2), "size": Vector2(WALL_THICKNESS, seg_h)})

	return segments


func _door_pos(dd: DoorDef, outer: Rect2) -> Vector2:
	var half := DOOR_WIDTH / 2.0
	match dd.edge:
		0: return Vector2(dd.pos, outer.position.y)
		1: return Vector2(outer.position.x + outer.size.x, dd.pos)
		2: return Vector2(dd.pos, outer.position.y + outer.size.y)
		3: return Vector2(outer.position.x, dd.pos)
	_: return Vector2.ZERO


func _door_glow_pos(dd: DoorDef, outer: Rect2) -> Vector2:
	var half := DOOR_WIDTH / 2.0
	var in_off := WALL_THICKNESS + 4
	match dd.edge:
		0: return Vector2(dd.pos - half, outer.position.y + in_off)
		1: return Vector2(outer.position.x + outer.size.x - in_off - 32, dd.pos - 8)
		2: return Vector2(dd.pos - half, outer.position.y + outer.size.y - in_off - 16)
		3: return Vector2(outer.position.x + in_off, dd.pos - 8)
	_: return Vector2.ZERO


func _obstacle_size(type: String) -> Vector2:
	match type:
		"pillar": return Vector2(24, 24)
		"crate": return Vector2(32, 32)
		"bookshelf": return Vector2(16, 64)
		"counter": return Vector2(64, 16)
		_: return Vector2(24, 24)


func _calc_spawn_positions(r: RoomDef, outer: Rect2) -> Dictionary:
	var nav := r.nav_rect
	var cx := nav.position.x + nav.size.x / 2
	var cy := nav.position.y + nav.size.y / 2

	var player_pos := Vector2(cx, cy + nav.size.y * 0.25)

	var spawns: Array[Vector2] = []
	var margin := 48.0
	var cols := 2
	if r.size >= RoomSize.MEDIUM:
		cols = 3

	var idx := 0
	for row in range(ceil(float(r.spawn_count) / cols)):
		for col in range(cols):
			if idx >= r.spawn_count:
				break
			var x := margin + (nav.size.x - margin * 2) * (col + 0.5) / cols
			var y := margin + (nav.size.y - margin * 2) * (row + 0.5) / ceil(float(r.spawn_count) / cols)
			spawns.append(Vector2(x, y))
			idx += 1

	return {"player": player_pos, "spawns": spawns}


func _calc_interactables(r: RoomDef, outer: Rect2) -> Dictionary:
	var result := {}
	var nav := r.nav_rect
	if r.size != RoomSize.SMALL:
		result["Interactable_Chest"] = Vector2(nav.position.x + nav.size.x * 0.2, nav.position.y + nav.size.y * 0.85)
	if r.size >= RoomSize.LARGE:
		result["Interactable_Shop"] = Vector2(nav.position.x + nav.size.x * 0.8, nav.position.y + nav.size.y * 0.85)
	if r.size != RoomSize.SMALL:
		result["Trap_Spikes"] = Vector2(nav.position.x + nav.size.x * 0.5, nav.position.y + nav.size.y * 0.5)
	return result
