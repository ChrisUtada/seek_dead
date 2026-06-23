class_name PlayerController
extends CharacterBody2D

const _WeaponComp = preload("res://scripts/components/weapon_component.gd")
const _MoverComp = preload("res://scripts/components/movement_component.gd")

signal player_damaged(amount: float, current_hp: float, max_hp: float)

@onready var state: StateComponent = $StateComponent
@onready var weapon: WeaponComponent = $WeaponComponent
@onready var mover: MovementComponent = $MovementComponent
@onready var dodge: DodgeComponent = $DodgeComponent
@onready var sprint: SprintComponent = $SprintComponent
@onready var ammo: AmmoSystem = $AmmoSystem
@onready var skill_manager: SkillManager = $SkillManager
@onready var _sprite: Node = $Sprite2D

@export var config: PlayerConfig

var walk_speed: float = 200.0
var _base_walk_speed: float = 200.0
var is_invincible: bool = false
var _flash_timer: float = 0.0

func _ready():
	GameManager.register_player(self)
	EntityRegistry.register_player(self)
	add_to_group("players")
	if config:
		walk_speed = config.walk_speed
		_base_walk_speed = config.walk_speed
		state.max_hp = config.max_hp
		state.hp = config.max_hp
		state.max_energy = config.max_energy
		state.energy = config.max_energy
		state.max_stamina = config.max_stamina
		state.stamina = config.max_stamina
		mover.speed = config.walk_speed
	_generate_placeholder_texture()
	state.died.connect(_on_died)
	state.meltdown_triggered.connect(_on_meltdown)
	state.meltdown_ended.connect(_on_meltdown_end)
	weapon.weapon_changed.connect(_on_weapon_changed)
	_init_skills()

func _on_weapon_changed(w: WeaponBase):
	if w.max_ammo > 0:
		ammo.switch_to_weapon(w.resource_path, w.max_ammo)

func _on_meltdown():
	AudioManager.play_sfx(AudioManager.SfxType.PLAYER_MELTDOWN)
	walk_speed = _base_walk_speed * 0.7
	if _sprite and _sprite is CanvasItem:
		(_sprite as CanvasItem).modulate = Color(1, 0.7, 0.2)

func _on_meltdown_end():
	walk_speed = _base_walk_speed
	if _sprite and _sprite is CanvasItem:
		(_sprite as CanvasItem).modulate = Color(1, 1, 1)

func _init_skills():
	skill_manager.add_skill(HealSkill.new())
	skill_manager.add_skill(ShockwaveSkill.new())

func _generate_placeholder_texture():
	if not _sprite or _sprite is AnimatedSprite2D:
		return
	var body = config.body_color if config else Color(0.3, 0.6, 1.0)
	var eye = config.eye_color if config else Color(1, 1, 1)
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for x in range(32):
		for y in range(32):
			var dx = x - 16
			var dy = y - 16
			var dist = sqrt(dx * dx + dy * dy)
			if dist < 12:
				image.set_pixel(x, y, body)
			if dist < 8 and dx > 6 and abs(dy) < 4:
				image.set_pixel(x, y, eye)
			if dist < 6 and dx > 2 and abs(dy) < 2:
				image.set_pixel(x, y, Color(0, 0, 0))
	var spr = _sprite as Sprite2D
	spr.texture = ImageTexture.create_from_image(image)
	spr.centered = true

func init_weapons(weapon_list: Array[WeaponBase]):
	weapon.init_weapons(weapon_list)

func take_damage(amount: float, damage_type: int) -> Dictionary:
	if is_invincible:
		return {"final_damage": 0.0, "is_critical": false, "is_weakness": false, "hit_result": -1, "breakdown": {}}
	var result = state.take_damage(amount, damage_type)
	_flash_timer = 0.1
	EventManager.damage_dealt.emit(null, self, result.final_damage, damage_type)
	player_damaged.emit(result.final_damage, state.hp, state.max_hp)
	_shake_camera(Vector2(2.0, 1.5) if result.is_critical else Vector2(1.0, 0.8), 0.15)
	print("玩家受伤: %.0f (剩余HP: %.0f/%.0f)" % [result.final_damage, state.hp, state.max_hp])
	if result.is_critical:
		print("  ! 暴击! (%.1fx)" % result.breakdown.get("crit_damage", 1.5))
	return result

func _shake_camera(intensity: Vector2, duration: float):
	var cam = $Camera2D
	if not cam:
		return
	var original = cam.position
	var tween = create_tween()
	tween.tween_method(_apply_shake.bind(cam, original, intensity), 0.0, 1.0, duration).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func(): cam.position = original)

func _apply_shake(_t: float, cam: Camera2D, original: Vector2, intensity: Vector2):
	cam.position = original + Vector2(randf_range(-intensity.x, intensity.x), randf_range(-intensity.y, intensity.y))

func knockback(velocity: Vector2):
	mover.push(velocity, 0.12)

func _on_died():
	AudioManager.play_sfx(AudioManager.SfxType.PLAYER_HURT)
	print("玩家死亡!")
	set_physics_process(false)
	mover.direction = Vector2.ZERO
	mover.speed = 0.0

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("attack"):
		weapon.attack()
	if event.is_action_pressed("dodge"):
		var dir = _get_input_direction()
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN
		dodge.try_dodge(dir)
	if event.is_action_pressed("sprint"):
		sprint.try_start_sprint()
	if event.is_action_released("sprint"):
		sprint.stop_sprint()
	if event.is_action_pressed("reload"):
		ammo.start_reload()
	for i in range(2):
		if event.is_action_pressed("skill_%d" % (i + 1)):
			skill_manager.use_skill(i, self)
			break

func _physics_process(delta: float):
	if _flash_timer > 0 and _sprite and _sprite is CanvasItem:
		var spr = _sprite as CanvasItem
		_flash_timer -= delta
		spr.modulate = Color(1, 1 - _flash_timer * 10, 1 - _flash_timer * 10)
		if _flash_timer <= 0:
			spr.modulate = Color(1, 1, 1)

	mover.direction = _get_input_direction()
	mover.speed = walk_speed
	weapon.tick_cooldown(delta)

	var aim_dir = (get_global_mouse_position() - global_position).normalized()
	weapon.set_aim_direction(aim_dir)
	if _sprite and "flip_h" in _sprite:
		_sprite.flip_h = aim_dir.x < 0

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
