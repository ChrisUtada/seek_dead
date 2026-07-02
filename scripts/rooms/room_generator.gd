@tool
extends Node

const DOOR_SCENE := preload("res://scenes/rooms/door_marker.tscn")
const ROOMS_DIR := "res://scenes/rooms/"
const CONFIG_DIR := "res://resources/rooms/"
const ENV_LAYER := 4
const WALL_THICKNESS := 16
const DOOR_WIDTH := 32

enum RoomSize { SMALL, MEDIUM, LARGE, BOSS }

class RoomDef:
	var id: String
	var name: String
	var size: RoomSize
	var nav_rect: Rect2
	var doors: Array
	var obstacles: Array
	var spawn_count: int

class DoorDef:
	var edge: int
	var pos: float

class ObstacleDef:
	var type: String
	var pos: Vector2


func _ready():
	if Engine.is_editor_hint():
		return
	generate_all()
	print("=== Room generation complete ===")
	get_tree().quit()


func generate_all():
	print("=== Starting room generation ===")

	_generate_template()

	for r in _define_rooms():
		_generate_room(r)

	print("=== Done ===")


func _own_recursive(node: Node, owner: Node):
	if node != owner:
		node.owner = owner
	if node != owner and node.scene_file_path != "":
		return
	for child in node.get_children():
		_own_recursive(child, owner)


func _define_rooms() -> Array:
	var rooms: Array[RoomDef] = []

	rooms.append(_mk("room_small_test", "测试小房间", RoomSize.SMALL, Rect2(16, 16, 256, 256), [dd(0, 144)], [ob("pillar", 80, 80), ob("pillar", 200, 180)], 4))

	rooms.append(_mk("room_medium_test", "测试中房间", RoomSize.MEDIUM, Rect2(16, 16, 448, 320), [dd(0, 240), dd(2, 240)], [ob("pillar", 120, 100), ob("crate", 300, 200), ob("bookshelf", 380, 80)], 6))

	rooms.append(_mk("room_large_test", "测试大房间", RoomSize.LARGE, Rect2(16, 16, 640, 432), [dd(0, 336), dd(1, 216), dd(3, 216)], [ob("pillar", 120, 80), ob("pillar", 500, 300), ob("crate", 300, 200), ob("counter", 80, 300)], 8))

	return rooms


func _mk(id: String, name: String, size: RoomSize, nav: Rect2, doors: Array, obstacles: Array, spawn_count: int) -> RoomDef:
	var r := RoomDef.new()
	r.id = id; r.name = name; r.size = size; r.nav_rect = nav; r.doors = doors; r.obstacles = obstacles; r.spawn_count = spawn_count
	return r


func dd(edge: int, pos: float) -> DoorDef:
	var d := DoorDef.new(); d.edge = edge; d.pos = pos; return d


func ob(type: String, x: float, y: float) -> ObstacleDef:
	var o := ObstacleDef.new(); o.type = type; o.pos = Vector2(x, y); return o


func _generate_template():
	var root := Node2D.new()
	root.name = "RoomTemplate"
	root.add_child(_make_nav(Rect2(16, 16, 256, 256)))
	root.add_child(_make_floor(Rect2(16, 16, 256, 256), []))
	var w := Node2D.new(); w.name = "Walls"; root.add_child(w)
	var o := Node2D.new(); o.name = "Obstacles"; root.add_child(o)
	root.add_child(_make_markers(Rect2(16, 16, 256, 256), 4, false))
	root.add_child(_make_doors([], Rect2(0, 0, 288, 288)))

	_own_recursive(root, root)
	var scene := PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, ROOMS_DIR + "room_template.tscn")
	print("  saved: room_template.tscn")


func _make_nav(nav_rect: Rect2) -> NavigationRegion2D:
	var nav := NavigationRegion2D.new()
	nav.name = "NavigationRegion2D"
	var poly := NavigationPolygon.new()
	var verts := PackedVector2Array([
		Vector2(nav_rect.position.x, nav_rect.position.y),
		Vector2(nav_rect.position.x + nav_rect.size.x, nav_rect.position.y),
		Vector2(nav_rect.position.x + nav_rect.size.x, nav_rect.position.y + nav_rect.size.y),
		Vector2(nav_rect.position.x, nav_rect.position.y + nav_rect.size.y)
	])
	poly.vertices = verts
	poly.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	nav.navigation_polygon = poly
	return nav


func _make_floor(nav_rect: Rect2, doors: Array) -> Node2D:
	var floor := Node2D.new()
	floor.name = "Floor"

	var rect := ColorRect.new()
	rect.name = "ColorRect"
	rect.color = Color("#2a2a2a")
	rect.size = nav_rect.size
	rect.position = nav_rect.position
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor.add_child(rect)

	var outer := Rect2(nav_rect.position.x - WALL_THICKNESS, nav_rect.position.y - WALL_THICKNESS, nav_rect.size.x + WALL_THICKNESS * 2, nav_rect.size.y + WALL_THICKNESS * 2)
	for i in doors.size():
		var dd_obj := doors[i] as DoorDef
		var glow := ColorRect.new()
		glow.name = "DoorGlow" + str(i + 1)
		glow.color = Color(0, 1, 0.267, 0.3)
		glow.size = Vector2(32, 16)
		glow.position = _door_glow_pos(dd_obj, outer)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		floor.add_child(glow)

	return floor


func _make_walls(r: RoomDef, outer: Rect2) -> Node2D:
	var walls := Node2D.new()
	walls.name = "Walls"

	for ws in _wall_segments(r, outer):
		var body := StaticBody2D.new()
		body.name = ws.name
		body.collision_layer = ENV_LAYER
		body.position = ws.pos
		walls.add_child(body)

		var shape := RectangleShape2D.new()
		shape.size = ws.size
		var col := CollisionShape2D.new()
		col.name = "CollisionShape2D"
		col.shape = shape
		col.position = ws.shape_offset
		body.add_child(col)

	return walls


func _make_obstacles(r: RoomDef) -> Node2D:
	var obs := Node2D.new()
	obs.name = "Obstacles"

	for i in r.obstacles.size():
		var ob_obj := r.obstacles[i] as ObstacleDef
		var body := StaticBody2D.new()
		body.name = ob_obj.type.capitalize() + "_" + str(i + 1)
		body.collision_layer = ENV_LAYER
		body.position = ob_obj.pos
		obs.add_child(body)

		var osize := _obs_size(ob_obj.type)
		var shape := RectangleShape2D.new()
		shape.size = osize
		var col := CollisionShape2D.new()
		col.name = "CollisionShape2D"
		col.shape = shape
		col.position = Vector2(osize.x / 2, osize.y / 2)
		body.add_child(col)

		var nav_obs := NavigationObstacle2D.new()
		nav_obs.name = "NavigationObstacle2D"
		nav_obs.avoidance_enabled = true
		nav_obs.radius = min(osize.x, osize.y) / 2
		body.add_child(nav_obs)

		var vis := Polygon2D.new()
		vis.name = "Visual"
		vis.polygon = PackedVector2Array([
			Vector2(-osize.x / 2, -osize.y / 2),
			Vector2(osize.x / 2, -osize.y / 2),
			Vector2(osize.x / 2, osize.y / 2),
			Vector2(-osize.x / 2, osize.y / 2)
		])
		vis.color = _obs_color(ob_obj.type)
		body.add_child(vis)

	return obs


func _make_markers(nav_rect: Rect2, spawn_count: int, is_boss: bool) -> Node2D:
	var markers := Node2D.new()
	markers.name = "Markers"

	var cx := nav_rect.position.x + nav_rect.size.x / 2
	var cy := nav_rect.position.y + nav_rect.size.y / 2

	var spawn := Marker2D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = Vector2(cx, cy + nav_rect.size.y * 0.25)
	markers.add_child(spawn)

	var sp_positions := _spawn_positions(nav_rect, spawn_count)
	for i in sp_positions.size():
		var sp := Marker2D.new()
		sp.name = "SpawnMarker" + str(i + 1)
		sp.position = sp_positions[i]
		sp.add_to_group("spawn", true)
		markers.add_child(sp)

	if is_boss:
		var boss_sp := Marker2D.new()
		boss_sp.name = "SpawnMarker_Boss"
		boss_sp.position = spawn.position + Vector2(0, -80)
		markers.add_child(boss_sp)

	return markers


func _make_doors(doors: Array, outer: Rect2) -> Node2D:
	var doors_node := Node2D.new()
	doors_node.name = "Doors"

	for i in doors.size():
		var dd_obj := doors[i] as DoorDef
		var door := DOOR_SCENE.instantiate()
		door.name = "DoorMarker" + str(i + 1)
		door.position = _door_pos(dd_obj, outer)
		door.direction = dd_obj.edge
		if i == 0:
			door.is_entrance = true
		doors_node.add_child(door)

	return doors_node


func _generate_room(r: RoomDef):
	var outer := Rect2(r.nav_rect.position.x - WALL_THICKNESS, r.nav_rect.position.y - WALL_THICKNESS, r.nav_rect.size.x + WALL_THICKNESS * 2, r.nav_rect.size.y + WALL_THICKNESS * 2)

	var root := Node2D.new()
	root.name = r.id
	root.add_child(_make_nav(r.nav_rect))
	root.add_child(_make_floor(r.nav_rect, r.doors))
	root.add_child(_make_walls(r, outer))
	root.add_child(_make_obstacles(r))
	root.add_child(_make_markers(r.nav_rect, r.spawn_count, r.size == RoomSize.BOSS))
	root.add_child(_make_doors(r.doors, outer))

	_own_recursive(root, root)
	var scene := PackedScene.new()
	scene.pack(root)
	var path := ROOMS_DIR + r.id + ".tscn"
	ResourceSaver.save(scene, path)
	print("  saved: ", path)

	var cfg := RoomConfig.new()
	cfg.scene = scene
	cfg.room_name = r.name
	cfg.room_size = r.size as int
	match r.size:
		RoomSize.SMALL: cfg.min_enemies = 3; cfg.max_enemies = 6
		RoomSize.MEDIUM: cfg.min_enemies = 5; cfg.max_enemies = 8
		RoomSize.LARGE: cfg.min_enemies = 6; cfg.max_enemies = 10
		RoomSize.BOSS: cfg.min_enemies = 0; cfg.max_enemies = 0; cfg.boss_count = 1
	if r.size != RoomSize.BOSS:
		cfg.enemy_pool = [load("res://scenes/enemies/goblin.tscn"), load("res://scenes/enemies/skeleton.tscn")]
	elif r.size == RoomSize.BOSS:
		cfg.boss_pool = []
	cfg.reward_count = 3 if r.size == RoomSize.BOSS else 1
	cfg.reward_quality_bonus = 0.3 if r.size == RoomSize.BOSS else 0.0
	cfg.waves = []

	var cfg_path := CONFIG_DIR + r.id + ".tres"
	ResourceSaver.save(cfg, cfg_path)
	print("  saved: ", cfg_path)


func _wall_segments(r: RoomDef, outer: Rect2) -> Array[Dictionary]:
	var segs: Array[Dictionary] = []
	var gaps := {0: [], 1: [], 2: [], 3: []}
	for d_obj in r.doors:
		var dd_obj := d_obj as DoorDef
		gaps[dd_obj.edge].append(dd_obj.pos)
	for e in gaps: gaps[e].sort()

	var ox := outer.position.x
	var oy := outer.position.y
	var ow := outer.size.x
	var oh := outer.size.y
	var half := DOOR_WIDTH / 2.0

	var top_gaps: Array = gaps[0]
	var btm_gaps: Array = gaps[2]
	var lft_gaps: Array = gaps[3]
	var rgt_gaps: Array = gaps[1]

	if top_gaps.is_empty():
		segs.append({"name": "TopWall", "pos": Vector2(ox, oy), "size": Vector2(ow, WALL_THICKNESS), "shape_offset": Vector2(ow / 2, WALL_THICKNESS / 2)})
	else:
		var prev: float = ox
		for g in top_gaps:
			if g - half > prev + 1:
				var w: float = g - half - prev
				segs.append({"name": "TopWall_L", "pos": Vector2(prev, oy), "size": Vector2(w, WALL_THICKNESS), "shape_offset": Vector2(w / 2, WALL_THICKNESS / 2)})
			prev = g + half
		if ox + ow > prev + 1:
			var w: float = ox + ow - prev
			segs.append({"name": "TopWall_R", "pos": Vector2(prev, oy), "size": Vector2(w, WALL_THICKNESS), "shape_offset": Vector2(w / 2, WALL_THICKNESS / 2)})

	if btm_gaps.is_empty():
		segs.append({"name": "BottomWall", "pos": Vector2(ox, oy + oh - WALL_THICKNESS), "size": Vector2(ow, WALL_THICKNESS), "shape_offset": Vector2(ow / 2, WALL_THICKNESS / 2)})
	else:
		var prev: float = ox
		for g in btm_gaps:
			if g - half > prev + 1:
				var w: float = g - half - prev
				segs.append({"name": "BottomWall_L", "pos": Vector2(prev, oy + oh - WALL_THICKNESS), "size": Vector2(w, WALL_THICKNESS), "shape_offset": Vector2(w / 2, WALL_THICKNESS / 2)})
			prev = g + half
		if ox + ow > prev + 1:
			var w: float = ox + ow - prev
			segs.append({"name": "BottomWall_R", "pos": Vector2(prev, oy + oh - WALL_THICKNESS), "size": Vector2(w, WALL_THICKNESS), "shape_offset": Vector2(w / 2, WALL_THICKNESS / 2)})

	if lft_gaps.is_empty():
		segs.append({"name": "LeftWall", "pos": Vector2(ox, oy), "size": Vector2(WALL_THICKNESS, oh), "shape_offset": Vector2(WALL_THICKNESS / 2, oh / 2)})
	else:
		var prev: float = oy
		for g in lft_gaps:
			if g - half > prev + 1:
				var h: float = g - half - prev
				segs.append({"name": "LeftWall_T", "pos": Vector2(ox, prev), "size": Vector2(WALL_THICKNESS, h), "shape_offset": Vector2(WALL_THICKNESS / 2, h / 2)})
			prev = g + half
		if oy + oh > prev + 1:
			var h: float = oy + oh - prev
			segs.append({"name": "LeftWall_B", "pos": Vector2(ox, prev), "size": Vector2(WALL_THICKNESS, h), "shape_offset": Vector2(WALL_THICKNESS / 2, h / 2)})

	if rgt_gaps.is_empty():
		segs.append({"name": "RightWall", "pos": Vector2(ox + ow - WALL_THICKNESS, oy), "size": Vector2(WALL_THICKNESS, oh), "shape_offset": Vector2(WALL_THICKNESS / 2, oh / 2)})
	else:
		var prev: float = oy
		for g in rgt_gaps:
			if g - half > prev + 1:
				var h: float = g - half - prev
				segs.append({"name": "RightWall_T", "pos": Vector2(ox + ow - WALL_THICKNESS, prev), "size": Vector2(WALL_THICKNESS, h), "shape_offset": Vector2(WALL_THICKNESS / 2, h / 2)})
			prev = g + half
		if oy + oh > prev + 1:
			var h: float = oy + oh - prev
			segs.append({"name": "RightWall_B", "pos": Vector2(ox + ow - WALL_THICKNESS, prev), "size": Vector2(WALL_THICKNESS, h), "shape_offset": Vector2(WALL_THICKNESS / 2, h / 2)})

	return segs


func _obs_size(type: String) -> Vector2:
	match type:
		"pillar": return Vector2(24, 24)
		"crate": return Vector2(32, 32)
		"bookshelf": return Vector2(16, 64)
		"counter": return Vector2(64, 16)
	return Vector2(24, 24)


func _obs_color(type: String) -> Color:
	match type:
		"pillar": return Color("#8B7355")
		"crate": return Color("#CD853F")
		"bookshelf": return Color("#6B3A2A")
		"counter": return Color("#A0522D")
	return Color("#888888")


func _spawn_positions(nav_rect: Rect2, count: int) -> Array[Vector2]:
	var margin: float = 48.0
	var cols: int = 2
	var result: Array[Vector2] = []
	var idx: int = 0
	var rows: float = ceil(float(count) / cols)

	for row in range(int(rows)):
		for col in range(cols):
			if idx >= count: break
			var x: float = margin + (nav_rect.size.x - margin * 2.0) * (float(col) + 0.5) / float(cols)
			var y: float = margin + (nav_rect.size.y - margin * 2.0) * (float(row) + 0.5) / rows
			result.append(Vector2(x, y))
			idx += 1
	return result


func _door_pos(dd: DoorDef, outer: Rect2) -> Vector2:
	match dd.edge:
		0: return Vector2(dd.pos, outer.position.y)
		1: return Vector2(outer.position.x + outer.size.x, dd.pos)
		2: return Vector2(dd.pos, outer.position.y + outer.size.y)
		3: return Vector2(outer.position.x, dd.pos)
	return Vector2.ZERO


func _door_glow_pos(dd: DoorDef, outer: Rect2) -> Vector2:
	var half := DOOR_WIDTH / 2.0
	var off := WALL_THICKNESS + 4
	match dd.edge:
		0: return Vector2(dd.pos - half, outer.position.y + off)
		1: return Vector2(outer.position.x + outer.size.x - off - 32, dd.pos - 8)
		2: return Vector2(dd.pos - half, outer.position.y + outer.size.y - off - 16)
		3: return Vector2(outer.position.x + off, dd.pos - 8)
	return Vector2.ZERO
