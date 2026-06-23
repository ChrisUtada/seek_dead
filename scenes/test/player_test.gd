extends Node2D

func _ready():
	print("")
	print("*".repeat(70))
	print("  Seek Dead - 战斗系统验证")
	print("  WASD移动 | 鼠标瞄准 | 左键攻击")
	print("  1铁剑 | 2火剑 | 3毒匕 | 4手枪 | 5冰枪")
	print("  Shift闪避(-15热) | Ctrl冲刺 | R装弹 | Q治疗 | E护盾 | F冲刺")
	print("  F5存档 | F9读档 | Esc暂停 | F2重开")
	print("  超载(100%热): 远程攻速x2自伤5/不耗弹, 近战范围x1.5必暴/-30%移速")
	print("  骑士: Idle/Run/Death 动画")
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
		print("敌人%d: %s HP=%.0f 属性=%s" % [i + 1, cfg.display_name, enemy.state.max_hp, innate_names[enemy.state.innate_type]])

func _spawn_boss():
	var cfg = load("res://resources/enemies/fire_boss.tres") as BossConfig
	var scene = load(cfg.scene_path)
	var boss = scene.instantiate()
	boss.position = Vector2(800, 200)
	add_child(boss)
	boss.apply_config(cfg)
	print("Boss: HP=%.0f 属性=火焰" % boss.state.max_hp)

func _input(event):
	if event.is_action_pressed("save_game"):
		_save_game()
	if event.is_action_pressed("load_game"):
		_load_game()

func _save_game():
	var player = $Player
	if not player:
		return
	var data = {
		"hp": player.state.hp,
		"max_hp": player.state.max_hp,
		"energy": player.state.energy,
		"stamina": player.state.stamina,
		"heat": player.state.heat,
		"position_x": player.position.x,
		"position_y": player.position.y,
		"weapon_index": player.weapon.current_index,
		"timestamp": Time.get_datetime_string_from_system(),
	}
	if SaveSystem.save_game(data):
		print("存档成功")
	else:
		push_error("存档失败")

func _load_game():
	var data = SaveSystem.load_game()
	if data.is_empty():
		print("没有存档")
		return
	var player = $Player
	if not player:
		return
	player.state.hp = data.get("hp", player.state.max_hp)
	player.state.energy = data.get("energy", player.state.max_energy)
	player.state.stamina = data.get("stamina", player.state.max_stamina)
	player.state.heat = data.get("heat", 0.0)
	player.position = Vector2(data.get("position_x", 400.0), data.get("position_y", 300.0))
	var wi = data.get("weapon_index", 0)
	if wi < player.weapon.get_weapon_count():
		player.weapon.switch_weapon(wi)
	print("读档成功")

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
