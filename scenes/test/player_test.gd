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
	_spawn_enemies_from_configs()
	_spawn_boss()
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

func _spawn_enemies_from_configs():
	var config_paths = [
		"res://resources/enemies/skeleton.tres",
		"res://resources/enemies/goblin.tres",
	]
	var positions = [Vector2(600, 150), Vector2(800, 150), Vector2(600, 400), Vector2(800, 400)]
	var innate_names = ["穿刺", "斩击", "打击", "火焰", "雷电", "冰霜", "毒素", "风系"]

	for i in range(4):
		var cfg = load(config_paths[i % config_paths.size()]) as EnemyConfig
		var scene = load(cfg.scene_path)
		var enemy = scene.instantiate()
		enemy.position = positions[i]
		add_child(enemy)
		enemy.apply_config(cfg)
		_generate_enemy_texture(enemy, cfg.color)
		print("敌人%d: %s HP=%.0f 属性=%s" % [i + 1, cfg.display_name, enemy.state.max_hp, innate_names[enemy.state.innate_type]])

func _generate_enemy_texture(enemy: Node2D, color: Color):
	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var darker = Color(color.r * 0.6, color.g * 0.6, color.b * 0.6)
	for x in range(32):
		for y in range(32):
			var dx = x - 16
			var dy = y - 16
			if abs(dx) < 12 and abs(dy) < 12:
				img.set_pixel(x, y, color)
			if abs(dx) < 4 and abs(dy) < 4:
				img.set_pixel(x, y, darker)
	var sprite = enemy.get_node("Sprite2D")
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.centered = true

func _spawn_boss():
	var boss = load("res://scenes/battle/boss_enemy.tscn").instantiate()
	boss.position = Vector2(800, 200)
	add_child(boss)
	print("Boss: HP=%.0f 属性=火焰" % boss.state.max_hp)

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
