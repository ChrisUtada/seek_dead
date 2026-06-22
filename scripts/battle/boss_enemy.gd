extends CharacterBody2D

const _SEComp = preload("res://scripts/components/status_effect_component.gd")
const _BossAIComp = preload("res://scripts/components/boss_ai_component.gd")
const _MoverComp = preload("res://scripts/components/movement_component.gd")

@onready var state: StateComponent = $StateComponent
@onready var effects: StatusEffectComponent = $StatusEffectComponent
@onready var ai: BossAIComponent = $BossAIComponent
@onready var mover: MovementComponent = $MovementComponent
@onready var _sprite: Sprite2D = $Sprite2D

var _flash_timer: float = 0.0
var _phase_colors = [Color(1, 1, 1), Color(1, 1, 1), Color(1, 0.7, 0.2), Color(1, 0.2, 0.1)]
var _is_charging: bool = false
var _charge_velocity: Vector2 = Vector2.ZERO
var _charge_duration: float = 0.0

func _ready():
	state.max_hp = 600.0
	state.hp = 600.0
	state.innate_type = DamageSystem.DamageType.FIRE
	state.defenses = {
		"puncture_defense": 0.15,
		"slash_defense": 0.15,
		"smash_defense": 0.05,
		"fire_defense": 0.3,
	}
	state.died.connect(_on_died)
	effects.tick_damage.connect(_on_tick_damage)
	effects.effect_applied.connect(_on_effect_applied)
	effects.effect_expired.connect(_on_effect_expired)
	ai.perform_melee_slam.connect(_on_melee_slam)
	ai.perform_charge.connect(_on_charge)
	ai.perform_ranged_burst.connect(_on_ranged_burst)
	ai.state_changed.connect(_on_ai_state_changed)
	mover.speed = 40.0
	_sprite.modulate = _phase_colors[1]
	_generate_boss_texture()

func _generate_boss_texture():
	var img = Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(48):
		for y in range(48):
			var dx = x - 24
			var dy = y - 24
			var d = sqrt(dx * dx + dy * dy)
			if d < 20:
				img.set_pixel(x, y, Color(0.7, 0.15, 0.15))
			if d < 8:
				img.set_pixel(x, y, Color(1, 0.8, 0.0))
			if abs(dx) < 3 and abs(dy) < 14 and abs(dy) > 10:
				img.set_pixel(x, y, Color(0.9, 0.5, 0.0))
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.centered = true
	scale = Vector2(1.5, 1.5)

func take_damage(amount: float, damage_type: int):
	var result = state.take_damage(amount, damage_type)
	var hit_str = DamageSystem.hit_result_to_string(result.hit_result)
	var prefix = "[%s]" % hit_str if hit_str else ""
	var hp_pct = state.hp / state.max_hp
	print("Boss受伤: %s %.0f (HP: %.0f/%.0f, %.0f%%)" % [prefix, result.final_damage, state.hp, state.max_hp, hp_pct * 100])
	_flash_timer = 0.1
	var old_phase = ai.phase
	ai.check_phase(hp_pct)
	if ai.phase != old_phase:
		_on_phase_changed()
	return result

func _on_phase_changed():
	print("BOSS进入阶段 %d!" % ai.phase)
	_sprite.modulate = _phase_colors[ai.phase] if ai.phase <= 3 else Color(1, 1, 1)

func apply_status(effect_type: int, damage: float, duration: float):
	effects.apply(effect_type, damage, duration)

func _on_tick_damage(dmg: float, dmg_type: int):
	var before = ai.phase
	take_damage(dmg, dmg_type)

func _on_effect_applied(_et: int, name_str: String):
	_update_tint()

func _on_effect_expired(_et: int, name_str: String):
	_update_tint()

func _update_tint():
	if _flash_timer > 0:
		return
	_sprite.modulate = _phase_colors[ai.phase] if ai.phase <= 3 else Color(1, 1, 1)

func _on_ai_state_changed(_new_state: int):
	pass

func _on_melee_slam(_target: Node2D):
	var space = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 70.0
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_PLAYER)
	query.exclude = [self]

	for result in space.intersect_shape(query):
		var body = result.collider
		if body.has_method("take_damage"):
			var mult = [1.0, 1.0, 1.4, 2.0][min(ai.phase, 4) - 1]
			body.take_damage(25.0 * mult, state.innate_type)
	print("Boss 猛击! 阶段 %d" % ai.phase)

func _on_charge(_target: Node2D):
	if not _target:
		return
	_is_charging = true
	var dir = global_position.direction_to(_target.global_position)
	var speed_mult = [1.0, 1.0, 1.3, 1.8][min(ai.phase, 4) - 1]
	_charge_velocity = dir * 350.0 * speed_mult
	_charge_duration = 0.4
	print("Boss 冲锋!")

func _on_ranged_burst(_target: Node2D):
	if not _target:
		return
	var bullet_scene = load("res://scenes/battle/projectile.tscn")
	var mult = [1.0, 1.0, 1.0, 1.5][min(ai.phase, 4) - 1]
	var count = [1, 2, 3, 4][min(ai.phase, 4) - 1]
	var base_dir = global_position.direction_to(_target.global_position)
	for i in range(count):
		var bullet = bullet_scene.instantiate()
		var spread = (i - (count - 1) / 2.0) * 0.15
		bullet.direction = base_dir.rotated(spread)
		bullet.global_position = global_position + bullet.direction * 30
		bullet.damage = 15.0 * mult
		bullet.damage_type = state.innate_type
		bullet.shooter = self
		bullet.speed = 400.0
		get_parent().add_child(bullet)
		_bullet_visual(bullet)
	print("Boss 远程爆发! %d发" % count)

func _bullet_visual(bullet):
	var img = Image.create(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(12):
		for y in range(12):
			var dx = x - 6
			var dy = y - 6
			if dx * dx + dy * dy < 25:
				img.set_pixel(x, y, Color(1, 0.5, 0))
			if dx * dx + dy * dy < 9:
				img.set_pixel(x, y, Color(1, 1, 0))
	bullet.get_node("Sprite2D").texture = ImageTexture.create_from_image(img)
	bullet.get_node("Sprite2D").centered = true

func _on_died():
	print("BOSS死亡!")
	queue_free()

func _physics_process(delta):
	if _flash_timer > 0:
		_flash_timer -= delta
		if _flash_timer <= 0:
			_update_tint()

	if _is_charging:
		_charge_duration -= delta
		velocity = _charge_velocity
		move_and_slide()
		if _charge_duration <= 0:
			_is_charging = false
			velocity = Vector2.ZERO
		return

	effects.update(delta)
	ai.process_ai(delta)

	if effects.has_effect(StatusEffect.EffectType.FREEZE):
		mover.apply_slow(0.3)
	else:
		mover.reset_speed_multiplier()

	match ai.current_state:
		BossAIComponent.BossState.IDLE, BossAIComponent.BossState.MELEE_SLAM, \
		BossAIComponent.BossState.RANGED_BURST:
			mover.direction = Vector2.ZERO
		BossAIComponent.BossState.CHARGE:
			mover.direction = Vector2.ZERO
		_:
			mover.direction = ai.get_move_direction()

	var hp_pct = state.hp / state.max_hp
	ai.check_phase(hp_pct)
