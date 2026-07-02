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
	var has_elite: bool

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
	print("Generation complete.")
	get_tree().quit()


func generate_all():
	print("=== Starting room generation ===")
	for r in _define_all_rooms():
		_generate_room(r)
	print("=== Done ===")


func _define_all_rooms() -> Array:
	var rooms: Array[RoomDef] = []

	var sn := Rect2(16, 16, 384, 224)
	var mn := Rect2(16, 16, 480, 352)
	var ln := Rect2(16, 16, 640, 432)
	var bn := Rect2(16, 16, 640, 448)

	rooms.append(_mk("room_01", "石质大厅", RoomSize.SMALL, sn, [dd(0, 192)], [ob("pillar", 120, 80), ob("pillar", 260, 140)], 5))
	rooms.append(_mk("room_02", "水牢", RoomSize.SMALL, Rect2(16, 16, 288, 256), [dd(2, 144)], [ob("crate", 80, 120), ob("crate", 180, 160)], 4))
	rooms.append(_mk("room_03", "武器库", RoomSize.SMALL, Rect2(16, 16, 352, 224), [dd(0, 120), dd(2, 120)], [ob("counter", 160, 64), ob("counter", 160, 160), ob("bookshelf", 280, 80)], 4))
	rooms.append(_mk("room_04", "囚室", RoomSize.SMALL, Rect2(16, 16, 320, 256), [dd(1, 128), dd(2, 160)], [ob("pillar", 80, 80), ob("pillar", 240, 80), ob("pillar", 160, 160)], 5))
	rooms.append(_mk("room_05", "食堂", RoomSize.SMALL, Rect2(16, 16, 352, 288), [dd(2, 176)], [ob("counter", 100, 80), ob("crate", 240, 180)], 5))
	rooms.append(_mk("room_06", "兵营", RoomSize.MEDIUM, mn, [dd(2, 120), dd(3, 240)], [ob("pillar", 80, 80), ob("pillar", 120, 220), ob("crate", 280, 120), ob("crate", 320, 260)], 6))
	rooms.append(_mk("room_07", "图书馆", RoomSize.MEDIUM, mn, [dd(1, 240), dd(3, 160)], [ob("bookshelf", 160, 80), ob("bookshelf", 160, 140), ob("bookshelf", 320, 200)], 6))
	rooms.append(_mk("room_08", "实验室", RoomSize.MEDIUM, mn, [dd(0, 160), dd(1, 240), dd(2, 160)], [ob("counter", 120, 100), ob("counter", 260, 200), ob("pillar", 200, 160)], 6))
	rooms.append(_mk("room_09", "锻造间", RoomSize.MEDIUM, mn, [dd(1, 200), dd(3, 240)], [ob("crate", 80, 120), ob("crate", 140, 80), ob("crate", 280, 200), ob("counter", 320, 100)], 6))
	rooms.append(_mk("room_10", "祭坛", RoomSize.MEDIUM, mn, [dd(0, 120), dd(2, 120)], [ob("pillar", 120, 100), ob("pillar", 240, 100), ob("pillar", 120, 240), ob("pillar", 240, 240)], 6))
	rooms.append(_mk("room_11", "仓库", RoomSize.MEDIUM, mn, [dd(1, 160), dd(3, 200)], [ob("crate", 80, 80), ob("crate", 140, 100), ob("crate", 80, 200), ob("crate", 140, 220), ob("crate", 300, 120), ob("crate", 300, 200)], 6))
	rooms.append(_mk("room_12", "宴会厅", RoomSize.MEDIUM, mn, [dd(0, 80), dd(1, 240), dd(3, 80)], [ob("counter", 160, 80), ob("counter", 240, 200), ob("bookshelf", 80, 180), ob("bookshelf", 360, 180)], 6))
	rooms.append(_mk("room_13", "演武场", RoomSize.MEDIUM, mn, [dd(0, 160), dd(2, 160)], [], 8))
	rooms.append(_mk("room_14", "花园", RoomSize.LARGE, ln, [dd(0, 80), dd(1, 320), dd(2, 80)], [ob("pillar", 100, 80), ob("pillar", 200, 80), ob("pillar", 400, 160), ob("pillar", 500, 200), ob("pillar", 200, 300), ob("pillar", 400, 360)], 8))
	rooms.append(_mk("room_15", "军械库", RoomSize.LARGE, ln, [dd(1, 160), dd(3, 320), dd(2, 240)], [ob("crate", 120, 100), ob("crate", 180, 80), ob("crate", 120, 200), ob("crate", 400, 150), ob("counter", 320, 100), ob("counter", 320, 280)], 8))
	rooms.append(_mk("room_16", "大殿", RoomSize.LARGE, ln, [dd(1, 320), dd(3, 320)], [ob("bookshelf", 160, 80), ob("bookshelf", 160, 160), ob("bookshelf", 160, 240), ob("bookshelf", 480, 80), ob("pillar", 320, 160), ob("pillar", 320, 280)], 8))
	rooms.append(_mk("room_17", "地下河", RoomSize.LARGE, ln, [dd(0, 160), dd(1, 480), dd(2, 160)], [ob("pillar", 80, 120), ob("pillar", 160, 200), ob("crate", 400, 100), ob("crate", 500, 300)], 8))
	rooms.append(_mk("room_18", "宝库", RoomSize.LARGE, ln, [dd(0, 80), dd(1, 160), dd(2, 80), dd(3, 240)], [ob("crate", 160, 80), ob("crate", 240, 80), ob("crate", 360, 160), ob("crate", 440, 240), ob("counter", 80, 200), ob("counter", 500, 300)], 8))
	rooms.append(_mk("room_19", "迷宫", RoomSize.LARGE, Rect2(16, 16, 480, 416), [dd(1, 128), dd(1, 384)], [ob("bookshelf", 120, 80), ob("bookshelf", 120, 200), ob("bookshelf", 240, 160), ob("bookshelf", 240, 320), ob("bookshelf", 360, 80), ob("bookshelf", 360, 240)], 6))
	rooms.append(_mk("room_20", "角斗场", RoomSize.LARGE, ln, [dd(0, 240), dd(2, 240)], [ob("pillar", 80, 80), ob("pillar", 560, 80), ob("pillar", 80, 360), ob("pillar", 560, 360)], 10))
	rooms.append(_mk("room_21", "教堂", RoomSize.LARGE, ln, [dd(0, 160), dd(2, 160), dd(3, 80)], [ob("pillar", 160, 80), ob("pillar", 320, 80), ob("pillar", 480, 80), ob("bookshelf", 80, 200), ob("bookshelf", 560, 200)], 8))
	rooms.append(_mk("room_22", "巨龙巢穴", RoomSize.BOSS, bn, [dd(0, 320)], [ob("pillar", 80, 80), ob("pillar", 560, 80), ob("pillar", 80, 380), ob("pillar", 560, 380)], 10))
	rooms.append(_mk("room_23", "巫妖塔顶", RoomSize.BOSS, Rect2(16, 16, 512, 384), [dd(2, 256)], [ob("pillar", 160, 80), ob("pillar", 320, 80), ob("pillar", 240, 200)], 8))
	rooms.append(_mk("room_24", "深渊裂隙", RoomSize.BOSS, bn, [dd(1, 320), dd(3, 320)], [ob("pillar", 120, 100), ob("pillar", 200, 200), ob("pillar", 320, 150), ob("pillar", 440, 300), ob("pillar", 520, 200), ob("pillar", 400, 80)], 10))
	rooms.append(_mk("room_25", "最终之间", RoomSize.BOSS, bn, [dd(0, 320)], [ob("pillar", 160, 160), ob("pillar", 320, 160), ob("pillar", 480, 160), ob("crate", 160, 300), ob("crate", 480, 300)], 12))

	return rooms


func _mk(id: String, name: String, size: RoomSize, nav: Rect2, doors: Array, obstacles: Array, spawn_count: int) -> RoomDef:
	var r := RoomDef.new()
	r.id = id; r.name = name; r.size = size; r.nav_rect = nav; r.doors = doors; r.obstacles = obstacles; r.spawn_count = spawn_count; r.has_elite = size != RoomSize.SMALL
	return r


func dd(edge: int, pos: float) -> DoorDef:
	var d := DoorDef.new(); d.edge = edge; d.pos = pos; return d

func ob(type: String, x: float, y: float) -> ObstacleDef:
	var o := ObstacleDef.new(); o.type = type; o.pos = Vector2(x, y); return o


func _generate_room(r: RoomDef):
	var outer := Rect2(r.nav_rect.position.x - WALL_THICKNESS, r.nav_rect.position.y - WALL_THICKNESS, r.nav_rect.size.x + WALL_THICKNESS * 2, r.nav_rect.size.y + WALL_THICKNESS * 2)
	var root := Node2D.new()
	root.name = r.id
	root.set_editable_instance(true)

	var nav_node := NavigationRegion2D.new()
	nav_node.name = "NavigationRegion2D"
	var nav_poly := NavigationPolygon.new()
	var verts := PackedVector2Array([Vector2(r.nav_rect.position.x, r.nav_rect.position.y), Vector2(r.nav_rect.position.x + r.nav_rect.size.x, r.nav_rect.position.y), Vector2(r.nav_rect.position.x + r.nav_rect.size.x, r.nav_rect.position.y + r.nav_rect.size.y), Vector2(r.nav_rect.position.x, r.nav_rect.position.y + r.nav_rect.size.y)])
	nav_poly.vertices = verts
	nav_poly.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	nav_node.navigation_polygon = nav_poly
	root.add_child(nav_node)
	nav_node.owner = root

	var floor_node := Node2D.new()
	floor_node.name = "Floor"
	root.add_child(floor_node)
	floor_node.owner = root

	var floor_rect := ColorRect.new()
	floor_rect.name = "ColorRect"
	floor_rect.color = Color("#2a2a2a")
	floor_rect.size = r.nav_rect.size
	floor_rect.position = r.nav_rect.position
	floor_node.add_child(floor_rect)
	floor_rect.owner = root

	for i in r.doors.size():
		var dd_obj := r.doors[i] as DoorDef
		var glow := ColorRect.new()
		glow.name = "DoorGlow" + str(i + 1)
		glow.color = Color(0, 1, 0.267, 0.3)
		glow.size = Vector2(32, 16)
		glow.position = _door_glow_pos(dd_obj, outer)
		floor_node.add_child(glow)
		glow.owner = root

	var walls_node := Node2D.new()
	walls_node.name = "Walls"
	root.add_child(walls_node)
	walls_node.owner = root

	for ws in _wall_segments(r, outer):
		var body := StaticBody2D.new()
		body.name = ws.name
		body.collision_layer = ENV_LAYER
		walls_node.add_child(body)
		body.owner = root
		var shape := RectangleShape2D.new()
		shape.size = ws.size
		var col := CollisionShape2D.new()
		col.name = "CollisionShape2D"
		col.shape = shape
		col.position = ws.shape_offset
		body.add_child(col)
		col.owner = root

	var obs_node := Node2D.new()
	obs_node.name = "Obstacles"
	root.add_child(obs_node)
	obs_node.owner = root

	for i in r.obstacles.size():
		var ob_obj := r.obstacles[i] as ObstacleDef
		var body := StaticBody2D.new()
		body.name = ob_obj.type.capitalize() + "_" + str(i + 1)
		body.collision_layer = ENV_LAYER
		body.position = ob_obj.pos
		obs_node.add_child(body)
		body.owner = root
		var osize := _obs_size(ob_obj.type)
		var shape := RectangleShape2D.new()
		shape.size = osize
		var col := CollisionShape2D.new()
		col.name = "CollisionShape2D"
		col.shape = shape
		body.add_child(col)
		col.owner = root
		var nav_obs := NavigationObstacle2D.new()
		nav_obs.name = "NavigationObstacle2D"
		nav_obs.avoidance_enabled = true
		nav_obs.radius = 12.0
		body.add_child(nav_obs)
		nav_obs.owner = root

	var markers_node := Node2D.new()
	markers_node.name = "Markers"
	root.add_child(markers_node)
	markers_node.owner = root

	var cx := r.nav_rect.position.x + r.nav_rect.size.x / 2
	var cy := r.nav_rect.position.y + r.nav_rect.size.y / 2

	var spawn := Marker2D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = Vector2(cx, cy + r.nav_rect.size.y * 0.25)
	markers_node.add_child(spawn)
	spawn.owner = root

	var sp_positions := _spawn_positions(r)
	for i in sp_positions.size():
		var sp := Marker2D.new()
		sp.name = "SpawnMarker" + str(i + 1)
		sp.position = sp_positions[i]
		sp.add_to_group("spawn")
		markers_node.add_child(sp)
		sp.owner = root

	if r.size == RoomSize.BOSS:
		var boss_sp := Marker2D.new()
		boss_sp.name = "SpawnMarker_Boss"
		boss_sp.position = spawn.position + Vector2(0, -80)
		markers_node.add_child(boss_sp)
		boss_sp.owner = root

	var interactables := _interactables(r)
	for key in interactables:
		var im := Marker2D.new()
		im.name = key
		im.position = interactables[key]
		im.add_to_group("interactable")
		markers_node.add_child(im)
		im.owner = root

	var doors_node := Node2D.new()
	doors_node.name = "Doors"
	root.add_child(doors_node)
	doors_node.owner = root

	for i in r.doors.size():
		var dd_obj := r.doors[i] as DoorDef
		var door := DOOR_SCENE.instantiate()
		door.name = "DoorMarker" + str(i + 1)
		door.position = _door_pos(dd_obj, outer)
		door.direction = dd_obj.edge
		if i == 0:
			door.is_entrance = true
		doors_node.add_child(door)
		door.owner = root

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
		cfg.has_elite = r.has_elite
	elif r.size == RoomSize.BOSS:
		cfg.boss_pool = []
	cfg.reward_count = 3 if r.size == RoomSize.BOSS else 1
	cfg.reward_quality_bonus = 0.3 if r.size == RoomSize.BOSS else 0.0

	var cfg_path := CONFIG_DIR + r.id + ".tres"
	ResourceSaver.save(cfg, cfg_path)
	print("  saved: ", cfg_path)


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


func _obs_size(type: String) -> Vector2:
	match type:
		"pillar": return Vector2(24, 24)
		"crate": return Vector2(32, 32)
		"bookshelf": return Vector2(16, 64)
		"counter": return Vector2(64, 16)
	return Vector2(24, 24)


func _wall_segments(r: RoomDef, outer: Rect2) -> Array[Dictionary]:
	var segs: Array[Dictionary] = []
	var gaps := {0: [], 1: [], 2: [], 3: []}
	for d_obj in r.doors:
		var dd_obj := d_obj as DoorDef
		gaps[dd_obj.edge].append(dd_obj.pos)
	for e in gaps: gaps[e].sort()

	var ox := outer.position.x; var oy := outer.position.y
	var ow := outer.size.x; var oh := outer.size.y
	var half := DOOR_WIDTH / 2.0

	func add_seg(name: String, px: float, py: float, sx: float, sy: float):
		segs.append({"name": name, "pos": Vector2(px, py), "size": Vector2(sx, sy), "shape_offset": Vector2(sx / 2, sy / 2)})

	if gaps[0].is_empty():
		add_seg("TopWall", ox, oy, ow, WALL_THICKNESS)
	else:
		var prev := ox
		for g in gaps[0]:
			if g - half > prev + 1: add_seg("TopWall_L", prev, oy, g - half - prev, WALL_THICKNESS)
			prev = g + half
		if ox + ow > prev + 1: add_seg("TopWall_R", prev, oy, ox + ow - prev, WALL_THICKNESS)

	if gaps[2].is_empty():
		add_seg("BottomWall", ox, oy + oh, ow, WALL_THICKNESS)
	else:
		var prev := ox
		for g in gaps[2]:
			if g - half > prev + 1: add_seg("BottomWall_L", prev, oy + oh, g - half - prev, WALL_THICKNESS)
			prev = g + half
		if ox + ow > prev + 1: add_seg("BottomWall_R", prev, oy + oh, ox + ow - prev, WALL_THICKNESS)

	if gaps[3].is_empty():
		add_seg("LeftWall", ox, oy, WALL_THICKNESS, oh)
	else:
		var prev := oy
		for g in gaps[3]:
			if g - half > prev + 1: add_seg("LeftWall_T", ox, prev, WALL_THICKNESS, g - half - prev)
			prev = g + half
		if oy + oh > prev + 1: add_seg("LeftWall_B", ox, prev, WALL_THICKNESS, oy + oh - prev)

	if gaps[1].is_empty():
		add_seg("RightWall", ox + ow, oy, WALL_THICKNESS, oh)
	else:
		var prev := oy
		for g in gaps[1]:
			if g - half > prev + 1: add_seg("RightWall_T", ox + ow, prev, WALL_THICKNESS, g - half - prev)
			prev = g + half
		if oy + oh > prev + 1: add_seg("RightWall_B", ox + ow, prev, WALL_THICKNESS, oy + oh - prev)

	return segs


func _spawn_positions(r: RoomDef) -> Array[Vector2]:
	var nav := r.nav_rect
	var margin := 48.0
	var cols := 2 if r.size < RoomSize.MEDIUM else 3
	var result: Array[Vector2] = []
	var idx := 0
	var rows := ceil(float(r.spawn_count) / cols)

	for row in range(rows):
		for col in range(cols):
			if idx >= r.spawn_count: break
			var x := margin + (nav.size.x - margin * 2) * (col + 0.5) / cols
			var y := margin + (nav.size.y - margin * 2) * (row + 0.5) / rows
			result.append(Vector2(x, y))
			idx += 1
	return result


func _interactables(r: RoomDef) -> Dictionary:
	var nav := r.nav_rect
	var result := {}
	if r.size != RoomSize.SMALL:
		result["Interactable_Chest"] = Vector2(nav.position.x + nav.size.x * 0.2, nav.position.y + nav.size.y * 0.85)
	if r.size >= RoomSize.LARGE:
		result["Interactable_Shop"] = Vector2(nav.position.x + nav.size.x * 0.8, nav.position.y + nav.size.y * 0.85)
	if r.size != RoomSize.SMALL:
		result["Trap_Spikes"] = Vector2(nav.position.x + nav.size.x * 0.5, nav.position.y + nav.size.y * 0.5)
	return result
