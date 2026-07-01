extends EnemyBase

const _BulletScene = preload("res://scenes/battle/projectile.tscn")
const _DefaultBulletData = preload("res://resources/bullets/default_bullet.tres")
const _GoblinTexture = preload("res://assets/chars/kl/Run-Sheet.png")

@export var config: EnemyConfig

enum BossPhase { PHASE_1, PHASE_2, PHASE_3 }

var _boss_config: BossConfig = null
var _phase: BossPhase = BossPhase.PHASE_1
var _can_take_damage: bool = false
var _is_defeated: bool = false
var _target: Node2D = null
var _nav: NavigationAgent2D
var _room_bounds: Rect2

@onready var _charge_hitbox: Hitbox = $ChargeHitbox

# --- Phase 1 ---
var _limbs: Array[BossLimb] = []
var _destroyed_limb_count: int = 0
var _limb_fire_timer: float = 0.0

# --- Phase 2 ---
var _phase2_start_hp: float = 0.0
var _phase2_burst_timer: float = 5.0

# --- Phase 3 ---
var _is_charging: bool = false
var _charge_velocity: Vector2 = Vector2.ZERO
var _charge_duration: float = 0.0
var _stun_timer: float = 0.0
var _is_stunned: bool = false

# --- 共享移动辅助 ---
var _strafe_dir := Vector2.RIGHT
var _strafe_timer := 0.0


func _ready():
	_enemy_ready()
	if config:
		apply_config(config)
	_generate_boss_texture()
	for child in get_children():
		if child is BossLimb:
			_limbs.append(child)
			child.limb_destroyed.connect(_on_limb_destroyed)
	_nav = $NavigationAgent2D
	_charge_hitbox.monitoring = false
	_charge_hitbox.monitorable = false
	_charge_hitbox.lifespan = 0
	_charge_hitbox.hit_landed.connect(_on_charge_hit)
	_compute_room_bounds()
	_change_phase(BossPhase.PHASE_1)


# ===================== FSM =====================

func _change_phase(new_phase: BossPhase):
	_exit_phase(_phase)
	_phase = new_phase
	_enter_phase(_phase)


func _enter_phase(p: BossPhase):
	match p:
		BossPhase.PHASE_1: _enter_phase1()
		BossPhase.PHASE_2: _enter_phase2()
		BossPhase.PHASE_3: _enter_phase3()


func _exit_phase(p: BossPhase):
	match p:
		BossPhase.PHASE_1: _exit_phase1()
		BossPhase.PHASE_2: _exit_phase2()
		BossPhase.PHASE_3: _exit_phase3()


func _process_phase(delta):
	match _phase:
		BossPhase.PHASE_1: _process_phase1(delta)
		BossPhase.PHASE_2: _process_phase2(delta)
		BossPhase.PHASE_3: _process_phase3(delta)


# ===================== Phase 1 =====================

func _enter_phase1():
	_can_take_damage = false
	_limb_fire_timer = _get_attack_cooldown(0, 1.2)


func _exit_phase1():
	pass


func _process_phase1(delta):
	if not _target or not is_instance_valid(_target):
		mover.direction = Vector2.ZERO
		return

	var dir = global_position.direction_to(_target.global_position)
	var dist = global_position.distance_squared_to(_target.global_position)

	if dist > 350 * 350:
		_movement_chase(_target.global_position, dir)
	elif dist > 120 * 120:
		_movement_strafe(delta, dir)
	else:
		_movement_retreat(dir)

	_limb_fire_timer -= delta
	if _limb_fire_timer <= 0 and _has_line_of_sight_to(_target, 500.0):
		_limb_fire_timer = _get_attack_cooldown(0, 1.2)
		for limb in _limbs:
			if limb and not limb.is_destroyed:
				_fire_limb_bullet(limb, _target.global_position)


func _on_limb_destroyed(_limb: BossLimb):
	_destroyed_limb_count += 1
	if _destroyed_limb_count >= _limbs.size() and _phase == BossPhase.PHASE_1:
		_change_phase(BossPhase.PHASE_2)


# ===================== Phase 2 =====================

func _enter_phase2():
	_can_take_damage = true
	_phase2_start_hp = state.hp
	_phase2_burst_timer = _get_attack_cooldown(1, 5.0)
	_sprite.modulate = Color(1, 0.8, 0.3)


func _exit_phase2():
	pass


func _process_phase2(delta):
	if not _target or not is_instance_valid(_target):
		mover.direction = Vector2.ZERO
		return

	var dir = global_position.direction_to(_target.global_position)
	var dist = global_position.distance_squared_to(_target.global_position)

	if dist < 200 * 200:
		mover.direction = -dir
	else:
		_strafe_timer -= delta
		if _strafe_timer <= 0:
			_strafe_timer = randf_range(1.0, 2.5)
			_strafe_dir = dir.orthogonal() if randf() < 0.5 else -dir.orthogonal()
		mover.direction = _strafe_dir

	_phase2_burst_timer -= delta
	if _phase2_burst_timer <= 0:
		_phase2_burst_timer = _get_attack_cooldown(1, 5.0)
		_fire_radial_burst()


# ===================== Phase 3 =====================

func _enter_phase3():
	_can_take_damage = false
	_sprite.modulate = Color(1, 0.2, 0.1)
	_start_charge()


func _exit_phase3():
	_is_charging = false
	_is_stunned = false
	_charge_hitbox.set_deferred("monitoring", false)
	_charge_hitbox.set_deferred("monitorable", false)


func _process_phase3(delta):
	if _is_charging:
		_charge_duration -= delta
		velocity = _charge_velocity
		move_and_slide()
		if _charge_duration <= 0:
			_end_charge_stun()
		return

	if _is_stunned:
		_stun_timer -= delta
		mover.direction = Vector2.ZERO
		if _stun_timer <= 0:
			_start_charge()
		return

	mover.direction = Vector2.ZERO


func _start_charge():
	if not _target or not is_instance_valid(_target):
		_target = _find_player()
		if not _target:
			return
	_is_charging = true
	_is_stunned = false
	_can_take_damage = false
	var dir = global_position.direction_to(_target.global_position)
	_charge_velocity = dir * _get_charge_speed(2, 500.0)
	_charge_duration = _get_charge_duration(2, 0.8)
	_charge_hitbox.damage = _get_burst_damage(2, 25.0)
	_charge_hitbox.damage_type = state.innate_type
	_charge_hitbox.shooter = self
	_charge_hitbox.reset()
	_charge_hitbox.set_deferred("monitoring", true)
	_charge_hitbox.set_deferred("monitorable", true)


func _end_charge_stun():
	_is_charging = false
	_charge_duration = 0.0
	_charge_hitbox.set_deferred("monitoring", false)
	_charge_hitbox.set_deferred("monitorable", false)
	_is_stunned = true
	_can_take_damage = true
	_stun_timer = _boss_config.stun_duration if _boss_config else 5.0


func _on_charge_hit(_hit_target: Node2D):
	_end_charge_stun()
	mover.push(-_charge_velocity.normalized() * 200.0, 0.3)


# ===================== Movement =====================

func _movement_chase(target_pos: Vector2, dir: Vector2) -> void:
	if _nav:
		_nav.target_position = target_pos
		if not _nav.is_navigation_finished():
			var next = _nav.get_next_path_position()
			mover.direction = global_position.direction_to(next)
		else:
			mover.direction = dir
	else:
		mover.direction = dir


func _movement_strafe(delta: float, dir: Vector2) -> void:
	_strafe_timer -= delta
	if _strafe_timer <= 0:
		_strafe_timer = randf_range(0.8, 2.0)
		_strafe_dir = dir.orthogonal() if randf() < 0.5 else -dir.orthogonal()
	mover.direction = _strafe_dir


func _movement_retreat(dir: Vector2) -> void:
	mover.direction = -dir


# ===================== 公共 =====================

func _physics_process(delta):
	if _is_defeated:
		mover.direction = Vector2.ZERO
		return

	_enemy_physics(delta)
	effects.update(delta)
	_target = _find_player()
	_process_phase(delta)
	_update_facing()
	_clamp_to_room()


func apply_config(cfg: EnemyConfig):
	state.max_hp = randf_range(cfg.hp_min, cfg.hp_max)
	state.hp = state.max_hp
	state.innate_type = cfg.innate_type
	state.defenses = cfg.defenses.duplicate()
	mover.speed = cfg.speed
	_apply_tier_multipliers(cfg)
	if cfg is BossConfig:
		_boss_config = cfg as BossConfig


# ===================== Config Accessors =====================

func _get_phase_value(arr: Array, idx: int, default = null):
	if arr.is_empty():
		return default
	return arr[min(idx, arr.size() - 1)]

func _get_attack_cooldown(idx: int, default: float) -> float:
	return _get_phase_value(_boss_config.attack_cooldowns if _boss_config else [], idx, default) as float

func _get_burst_damage(idx: int, default: float) -> float:
	return _get_phase_value(_boss_config.burst_damages if _boss_config else [], idx, default) as float

func _get_burst_count(idx: int, default: int) -> int:
	return _get_phase_value(_boss_config.burst_counts if _boss_config else [], idx, default) as int

func _get_charge_speed(idx: int, default: float) -> float:
	return _get_phase_value(_boss_config.charge_speeds if _boss_config else [], idx, default) as float

func _get_charge_duration(idx: int, default: float) -> float:
	return _get_phase_value(_boss_config.charge_durations if _boss_config else [], idx, default) as float


func take_damage(amount: float, damage_type: int) -> Dictionary:
	if not _can_take_damage:
		return {"final_damage": 0.0}
	var result = super(amount, damage_type)
	if _phase == BossPhase.PHASE_2 and state.hp <= _phase2_start_hp * 0.5:
		_change_phase(BossPhase.PHASE_3)
	return result


func _on_died():
	_is_defeated = true
	_exit_phase(_phase)
	call_deferred("_drop_weapon")
	super()


func _drop_weapon():
	var wd = preload("res://resources/weapon_templates/fire_sword.tres").duplicate(true) as WeaponData
	var equip = EquipmentBase.new()
	equip.equipment_name = wd.weapon_name
	equip.slot = EquipmentEnums.EquipmentSlot.WEAPON_MAIN
	equip.rarity = EquipmentEnums.Rarity.RARE
	equip.weapon_data = wd
	var node = WeaponNode.new()
	node.name = "BossDrop"
	add_child(node)
	node.equip(equip)
	node.global_position = global_position + Vector2(0, -20)


func _generate_boss_texture():
	_sprite.texture = _GoblinTexture
	_sprite.hframes = 6
	_sprite.centered = true
	scale = Vector2(1.8, 1.8)


func _find_player() -> Node2D:
	return EntityRegistry.get_nearest_player(global_position)


func _has_line_of_sight_to(target: Node2D, max_distance: float) -> bool:
	var offset = target.global_position - global_position
	if offset.length() > max_distance:
		return false
	var ray = $LOSRay
	ray.global_position = global_position
	ray.target_position = offset
	ray.force_raycast_update()
	return not ray.is_colliding()


func _compute_room_bounds():
	var nav = get_parent().get_node_or_null("NavigationRegion2D")
	if nav and nav.navigation_polygon:
		var verts = nav.navigation_polygon.vertices
		if verts.size() >= 2:
			var minp = verts[0]
			var maxp = verts[0]
			for v in verts:
				minp = minp.min(v)
				maxp = maxp.max(v)
			_room_bounds = Rect2(minp, maxp - minp)
		else:
			_room_bounds = Rect2(Vector2(-1000, -1000), Vector2(2000, 2000))
	else:
		_room_bounds = Rect2(Vector2(-1000, -1000), Vector2(2000, 2000))


func _clamp_to_room():
	if _room_bounds.size.x <= 0 or _room_bounds.size.y <= 0:
		return
	global_position = global_position.clamp(_room_bounds.position, _room_bounds.position + _room_bounds.size)


func _update_facing():
	if _target and is_instance_valid(_target):
		_sprite.flip_h = _target.global_position.x < global_position.x


# ===================== 子弹 =====================

func _fire_limb_bullet(limb: BossLimb, target_pos: Vector2):
	var dir = limb.global_position.direction_to(target_pos)
	var bullet = _BulletScene.instantiate()
	bullet.direction = dir
	bullet.global_position = limb.global_position
	bullet.damage = _get_burst_damage(0, 12.0)
	bullet.damage_type = limb.element_type
	bullet.shooter = self
	bullet.data = config.bullet_data if config and config.bullet_data else _DefaultBulletData
	get_parent().add_child(bullet)
	_setup_bullet_visual(bullet, limb.limb_color)


func _fire_radial_burst():
	var count = _get_burst_count(1, 12)
	for i in range(count):
		var angle = (i * TAU) / count
		var dir = Vector2(cos(angle), sin(angle))
		var bullet = _BulletScene.instantiate()
		bullet.direction = dir
		bullet.global_position = global_position + dir * 20
		bullet.damage = _get_burst_damage(1, 10.0)
		bullet.damage_type = state.innate_type
		bullet.shooter = self
		bullet.data = config.bullet_data if config and config.bullet_data else _DefaultBulletData
		get_parent().add_child(bullet)
		_setup_bullet_visual(bullet, Color(1, 0.5, 0))


func _setup_bullet_visual(bullet, bullet_color: Color):
	var lighter = Color(
		min(bullet_color.r * 1.5, 1.0),
		min(bullet_color.g * 1.5, 1.0),
		min(bullet_color.b * 1.5, 1.0)
	)
	var spr = bullet.get_node_or_null("Sprite2D")
	if spr:
		spr.texture = DamageSystem.get_circle_texture(10, bullet_color, lighter)
		spr.centered = true
