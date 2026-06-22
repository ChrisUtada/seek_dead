extends "res://scripts/battle/enemy_base.gd"

const _BossAIComp = preload("res://scripts/components/boss_ai_component.gd")
const _MoverComp = preload("res://scripts/components/movement_component.gd")

@onready var ai: BossAIComponent = $BossAIComponent

var _boss_config: BossConfig
var _is_charging: bool = false
var _charge_velocity: Vector2 = Vector2.ZERO
var _charge_duration: float = 0.0

func _ready():
	_enemy_ready()
	_apply_boss_config()
	ai.perform_melee_slam.connect(_on_melee_slam)
	ai.perform_charge.connect(_on_charge)
	ai.perform_ranged_burst.connect(_on_ranged_burst)
	mover.speed = 40.0

func _apply_boss_config():
	state.max_hp = 600.0
	state.hp = 600.0
	state.innate_type = DamageSystem.DamageType.FIRE
	state.defenses = {
		"puncture_defense": 0.15,
		"slash_defense": 0.15,
		"smash_defense": 0.05,
		"fire_defense": 0.3,
	}

func apply_config(config: EnemyConfig):
	state.max_hp = randf_range(config.hp_min, config.hp_max)
	state.hp = state.max_hp
	state.innate_type = config.innate_type
	state.defenses = config.defenses.duplicate()
	mover.speed = config.speed
	if config is BossConfig:
		_boss_config = config as BossConfig
	_generate_boss_texture()

func _generate_boss_texture():
	var img = Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(48):
		for y in range(48):
			var dx = x - 24
			var dy = y - 24
			var d = sqrt(dx * dx + dy * dy)
			if d < 20: img.set_pixel(x, y, Color(0.7, 0.15, 0.15))
			if d < 8: img.set_pixel(x, y, Color(1, 0.8, 0.0))
			if abs(dx) < 3 and abs(dy) < 14 and abs(dy) > 10:
				img.set_pixel(x, y, Color(0.9, 0.5, 0.0))
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.centered = true
	scale = Vector2(1.5, 1.5)

func _get_phase_value(arr: Array, phase: int) -> Variant:
	if arr.is_empty():
		return null
	return arr[min(phase - 1, arr.size() - 1)]

func take_damage(amount: float, damage_type: int):
	var result = super(amount, damage_type)
	var hit_str = DamageSystem.hit_result_to_string(result.hit_result)
	var prefix = "[%s]" % hit_str if hit_str else ""
	print("Boss受伤: %s %.0f (HP: %.0f/%.0f, %.0f%%)" % [prefix, result.final_damage, state.hp, state.max_hp, get_hp_ratio() * 100])
	var old_phase = ai.phase
	ai.check_phase(get_hp_ratio())
	if ai.phase != old_phase:
		_on_phase_changed()
	return result

func _on_phase_changed():
	print("BOSS进入阶段 %d!" % ai.phase)
	var colors = [Color(1, 1, 1), Color(1, 0.7, 0.2), Color(1, 0.2, 0.1)]
	_sprite.modulate = colors[min(ai.phase, 3) - 1] if ai.phase > 1 else Color(1, 1, 1)

func get_slam_damage() -> float:
	return _get_phase_value(_boss_config.slam_damages if _boss_config else [], ai.phase) as float

func get_slam_range() -> float:
	return _get_phase_value(_boss_config.slam_ranges if _boss_config else [], ai.phase) as float

func get_charge_speed() -> float:
	return _get_phase_value(_boss_config.charge_speeds if _boss_config else [], ai.phase) as float

func get_charge_duration() -> float:
	return _get_phase_value(_boss_config.charge_durations if _boss_config else [], ai.phase) as float

func get_burst_count() -> int:
	return _get_phase_value(_boss_config.burst_counts if _boss_config else [], ai.phase) as int

func get_burst_damage() -> float:
	return _get_phase_value(_boss_config.burst_damages if _boss_config else [], ai.phase) as float

func get_attack_cooldown() -> float:
	return _get_phase_value(_boss_config.attack_cooldowns if _boss_config else [], ai.phase) as float

func get_bullet_speed() -> float:
	return _boss_config.bullet_speed if _boss_config else 400.0

func _on_melee_slam(_target: Node2D):
	var space = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = get_slam_range()
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_PLAYER)
	query.exclude = [self]
	for result in space.intersect_shape(query):
		var body = result.collider
		if body.has_method("take_damage"):
			body.take_damage(get_slam_damage(), state.innate_type)
	print("Boss 猛击! 阶段 %d" % ai.phase)

func _on_charge(_target: Node2D):
	if not _target:
		return
	_is_charging = true
	var dir = global_position.direction_to(_target.global_position)
	_charge_velocity = dir * get_charge_speed()
	_charge_duration = get_charge_duration()
	print("Boss 冲锋!")

func _on_ranged_burst(_target: Node2D):
	if not _target:
		return
	var bullet_scene = load("res://scenes/battle/projectile.tscn")
	var count = get_burst_count()
	var base_dir = global_position.direction_to(_target.global_position)
	for i in range(count):
		var bullet = bullet_scene.instantiate()
		var spread = (i - (count - 1) / 2.0) * 0.15
		bullet.direction = base_dir.rotated(spread)
		bullet.global_position = global_position + bullet.direction * 30
		bullet.damage = get_burst_damage()
		bullet.damage_type = state.innate_type
		bullet.shooter = self
		bullet.speed = get_bullet_speed()
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
			if dx * dx + dy * dy < 25: img.set_pixel(x, y, Color(1, 0.5, 0))
			if dx * dx + dy * dy < 9: img.set_pixel(x, y, Color(1, 1, 0))
	bullet.get_node("Sprite2D").texture = ImageTexture.create_from_image(img)
	bullet.get_node("Sprite2D").centered = true

func _on_died():
	print("BOSS死亡!")
	super()

func _physics_process(delta):
	_enemy_physics(delta)

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

	ai.check_phase(get_hp_ratio())
