extends Node2D

func _ready():
	print("")
	print("*".repeat(70))
	print("  Seek Dead - 伤害系统验证")
	print("  WASD移动 | 鼠标瞄准 | 左键攻击")
	print("  1铁剑(斩击) | 2火剑(火焰) | 3毒匕(毒素) | 4手枪(穿刺) | 5冰枪(冰霜)")
	print("  近战范围伤害 | 远程子弹 | 属性克制 | 暴击 | 敌人自动追踪玩家")
	print("*".repeat(70))
	print("")

	_create_background()
	_create_obstacle()
	_spawn_enemies()
	_init_player_weapons()

func _create_obstacle():
	var block = StaticBody2D.new()
	block.name = "Obstacle"
	block.collision_layer = 1 << 2
	add_child(block)
	var shape = CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(80, 80)
	block.add_child(shape)
	var sprite = Sprite2D.new()
	var img = Image.create(80, 80, false, Image.FORMAT_RGBA8)
	for x in range(80):
		for y in range(80):
			img.set_pixel(x, y, Color(0.5, 0.25, 0.05))
	sprite.texture = ImageTexture.create_from_image(img)
	block.add_child(sprite)
	block.position = Vector2(800, 600)

func _create_background():
	for x in range(-200, 1800, 50):
		var line = Line2D.new()
		line.points = [Vector2(x, -200), Vector2(x, 1400)]
		line.default_color = Color(0.2, 0.2, 0.2, 0.3)
		line.width = 1
		add_child(line)
	for y in range(-200, 1400, 50):
		var line = Line2D.new()
		line.points = [Vector2(-200, y), Vector2(1800, y)]
		line.default_color = Color(0.2, 0.2, 0.2, 0.3)
		line.width = 1
		add_child(line)

func _spawn_enemies():
	for i in range(4):
		var enemy = load("res://scenes/battle/test_enemy.tscn").instantiate()
		enemy.position = Vector2(600 + (i % 2) * 200, 150 + (i / 2) * 250)
		add_child(enemy)

		var eimg = Image.create(32, 32, false, Image.FORMAT_RGBA8)
		eimg.fill(Color(0, 0, 0, 0))
		for x in range(32):
			for y in range(32):
				var dx = x - 16
				var dy = y - 16
				if abs(dx) < 12 and abs(dy) < 12:
					eimg.set_pixel(x, y, Color(0.9, 0.2, 0.2))
				if abs(dx) < 4 and abs(dy) < 4:
					eimg.set_pixel(x, y, Color(0, 0, 0))
		enemy.get_node("Sprite2D").texture = ImageTexture.create_from_image(eimg)
		enemy.get_node("Sprite2D").centered = true

		var innate_names = ["穿刺", "斩击", "打击", "火焰", "雷电", "冰霜", "毒素", "风系"]
		print("敌人%d: HP=%.0f 属性=%s" % [i + 1, enemy.state.max_hp, innate_names[enemy.state.innate_type]])

func _init_player_weapons():
	var player = $Player
	if not player:
		return

	var weapon_files = [
		"res://resources/weapons/iron_sword.tres",
		"res://resources/weapons/fire_sword.tres",
		"res://resources/weapons/poison_dagger.tres",
		"res://resources/weapons/pistol.tres",
		"res://resources/weapons/ice_gun.tres",
	]

	var weapons: Array[WeaponBase] = []
	for path in weapon_files:
		var w = load(path) as WeaponBase
		if w:
			weapons.append(w)
		else:
			push_error("武器加载失败: " + path)

	player.init_weapons(weapons)
