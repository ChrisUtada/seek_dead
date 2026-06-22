class_name PlayerController
extends CharacterBody2D

signal weapon_changed(weapon: WeaponBase)
signal attack_performed(weapon: WeaponBase, hit_count: int)

@export var walk_speed: float = 200.0
@export var sprint_speed: float = 350.0

var weapons: Array[WeaponBase] = []
var weapon_index: int = 0
var current_weapon: WeaponBase:
	get:
		return weapons[weapon_index] if weapons.size() > 0 else null
var attack_cooldown: float = 0.0

@onready var _state: StateComponent = $StateComponent
@onready var _sprite: Sprite2D = $Sprite2D

func _ready():
	GameManager.register_player(self)
	add_to_group("players")
	_generate_placeholder_texture()

func _generate_placeholder_texture():
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for x in range(32):
		for y in range(32):
			var dx = x - 16
			var dy = y - 16
			var dist = sqrt(dx * dx + dy * dy)
			if dist < 12:
				image.set_pixel(x, y, Color(0.3, 0.6, 1.0))
			if dist < 8 and dx > 6 and abs(dy) < 4:
				image.set_pixel(x, y, Color(1, 1, 1))
			if dist < 6 and dx > 2 and abs(dy) < 2:
				image.set_pixel(x, y, Color(0, 0, 0))
	_sprite.texture = ImageTexture.create_from_image(image)
	_sprite.centered = true

func init_weapons(weapon_list: Array[WeaponBase]):
	weapons = weapon_list
	weapon_index = 0
	if weapons.size() > 0:
		weapon_changed.emit(weapons[0])

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("attack"):
		_attack()

func _physics_process(delta: float):
	var speed = sprint_speed if Input.is_action_pressed("dodge") else walk_speed

	var move_dir = Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		move_dir.x -= 1
	if Input.is_action_pressed("move_right"):
		move_dir.x += 1
	if Input.is_action_pressed("move_forward"):
		move_dir.y -= 1
	if Input.is_action_pressed("move_backward"):
		move_dir.y += 1

	velocity = move_dir.normalized() * speed
	move_and_slide()

	var mouse_pos = get_global_mouse_position()
	if global_position.distance_squared_to(mouse_pos) > 1.0:
		look_at(mouse_pos)

	attack_cooldown = max(0, attack_cooldown - delta)

	for i in range(5):
		if Input.is_key_pressed(KEY_1 + i) and i < weapons.size():
			_switch_weapon(i)

func _switch_weapon(index: int):
	if index != weapon_index:
		weapon_index = index
		weapon_changed.emit(current_weapon)

func _attack():
	if not current_weapon or attack_cooldown > 0:
		return
	attack_cooldown = 1.0 / current_weapon.attack_speed

	match current_weapon.weapon_type:
		WeaponBase.WeaponType.MELEE:
			_melee_attack()
		WeaponBase.WeaponType.RANGED:
			_ranged_attack()

func _melee_attack():
	var space = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = current_weapon.range
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = 2
	query.exclude = [self]

	var results = space.intersect_shape(query)
	var hit_count = 0

	for result in results:
		var body = result.collider
		if body.has_method("take_damage"):
			var damage_result = body.take_damage(current_weapon.damage, current_weapon.damage_type)
			hit_count += 1

			if current_weapon.status_effect_type >= 0 and body.has_method("apply_status"):
				body.apply_status(current_weapon.status_effect_type, current_weapon.status_effect_damage, current_weapon.status_effect_duration)

			if damage_result.hit_result == DamageSystem.HitResult.CRITICAL:
				print("! 暴击! %.0f 伤害 (%.1fx)" % [damage_result.final_damage, damage_result.breakdown.get("crit_damage", 1.5)])
			elif damage_result.is_weakness:
				print("! 弱点! %.0f 伤害 (属性克制%.1fx)" % [damage_result.final_damage, damage_result.breakdown.get("type_advantage", 1.0)])

	if hit_count == 0:
		print("近战挥空 (范围: %.0f)" % current_weapon.range)
	else:
		print("近战命中 %d 个敌人" % hit_count)

	attack_performed.emit(current_weapon, hit_count)

func _ranged_attack():
	var bullet = load("res://scenes/battle/projectile.tscn").instantiate()
	bullet.global_position = global_position
	bullet.direction = Vector2.RIGHT.rotated(global_rotation)
	bullet.damage = current_weapon.damage
	bullet.damage_type = current_weapon.damage_type
	bullet.shooter = self
	bullet.status_effect_type = current_weapon.status_effect_type
	bullet.status_effect_damage = current_weapon.status_effect_damage
	bullet.status_effect_duration = current_weapon.status_effect_duration
	get_parent().add_child(bullet)

	var color = DamageSystem.get_color(current_weapon.damage_type)
	var bimg = Image.create(10, 10, false, Image.FORMAT_RGBA8)
	bimg.fill(Color(0, 0, 0, 0))
	for x in range(10):
		for y in range(10):
			var dx = x - 5
			var dy = y - 5
			if dx * dx + dy * dy < 25:
				bimg.set_pixel(x, y, color)
	bullet.get_node("Sprite2D").texture = ImageTexture.create_from_image(bimg)
	bullet.get_node("Sprite2D").centered = true

	print("远程射击: %s (伤害: %.0f)" % [current_weapon.weapon_name, current_weapon.damage])
	attack_performed.emit(current_weapon, 1)
