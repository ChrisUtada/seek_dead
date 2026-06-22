class_name PlayerController
extends CharacterBody2D

const _WeaponComp = preload("res://scripts/components/weapon_component.gd")
const _MoverComp = preload("res://scripts/components/movement_component.gd")

signal player_damaged(amount: float, current_hp: float, max_hp: float)

@onready var state: StateComponent = $StateComponent
@onready var weapon: WeaponComponent = $WeaponComponent
@onready var mover: MovementComponent = $MovementComponent
@onready var _sprite: Sprite2D = $Sprite2D

var walk_speed: float = 200.0
var sprint_speed: float = 350.0
var _flash_timer: float = 0.0

func _ready():
	GameManager.register_player(self)
	EntityRegistry.register_player(self)
	add_to_group("players")
	_generate_placeholder_texture()
	mover.speed = walk_speed
	state.max_hp = 200.0
	state.hp = 200.0
	state.died.connect(_on_died)

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
	weapon.init_weapons(weapon_list)

func take_damage(amount: float, damage_type: int) -> Dictionary:
	var result = state.take_damage(amount, damage_type)
	_flash_timer = 0.1
	player_damaged.emit(result.final_damage, state.hp, state.max_hp)
	print("玩家受伤: %.0f (剩余HP: %.0f/%.0f)" % [result.final_damage, state.hp, state.max_hp])
	if result.is_critical:
		print("  ! 暴击! (%.1fx)" % result.breakdown.get("crit_damage", 1.5))
	return result

func _on_died():
	print("玩家死亡!")
	get_tree().reload_current_scene()

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("attack"):
		weapon.attack()

func _physics_process(delta: float):
	if _flash_timer > 0:
		_flash_timer -= delta
		_sprite.modulate = Color(1, 1 - _flash_timer * 10, 1 - _flash_timer * 10)
		if _flash_timer <= 0:
			_sprite.modulate = Color(1, 1, 1)

	mover.direction = _get_input_direction()
	mover.speed = sprint_speed if Input.is_action_pressed("dodge") else walk_speed
	weapon.tick_cooldown(delta)

	var mouse_pos = get_global_mouse_position()
	if global_position.distance_squared_to(mouse_pos) > 1.0:
		look_at(mouse_pos)

	for i in range(5):
		if Input.is_key_pressed(KEY_1 + i):
			weapon.switch_weapon(i)

func _get_input_direction() -> Vector2:
	var dir = Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		dir.x -= 1
	if Input.is_action_pressed("move_right"):
		dir.x += 1
	if Input.is_action_pressed("move_forward"):
		dir.y -= 1
	if Input.is_action_pressed("move_backward"):
		dir.y += 1
	return dir.normalized()
