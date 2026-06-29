class_name WeaponNode
extends Node2D

signal hit_landed(hit_pos: Vector2, hit_dir: Vector2, damage_type: int, body: Node2D)
signal attack_finished(weapon_node: WeaponNode, hit_count: int)

enum WeaponState { IDLE, ACTIVE, COOLDOWN }

const _DefaultBulletScene = preload("res://scenes/battle/projectile.tscn")
const _BULLET_SIZE := 10

var equipment: EquipmentBase
var weapon_data: WeaponData

var shooter: Node2D = null
var aim_direction: Vector2 = Vector2.RIGHT
var weapon_color: Color = Color.WHITE
var is_attacking: bool = false
var attack_speed_modifier: float = 1.0

var _ws: WeaponState = WeaponState.IDLE
var _active_timer: float = 0.0
var _cooldown_timer: float = 0.0

# -- 武器视觉场景 --
var _weapon_visual: WeaponVisualBase = null

# -- 近战运行时 --
var _hitbox: Node = null
var _hit_count: int = 0


func _ready():
	visible = false


func _process(delta):
	match _ws:
		WeaponState.ACTIVE:
			_active_timer -= delta
			if _active_timer <= 0:
				_end_active()
		WeaponState.COOLDOWN:
			_cooldown_timer -= delta
			if _cooldown_timer <= 0:
				_ws = WeaponState.IDLE


# ════════════════════════════════════════
#  装备注入
# ════════════════════════════════════════

func equip(equip: EquipmentBase):
	equipment = equip
	weapon_data = equip.weapon_data.duplicate() as WeaponData
	_apply_archetype_modifiers()
	weapon_color = DamageSystem.get_color(weapon_data.damage_type)
	_spawn_weapon_visual()
	_init_hitbox()
	# 重置状态机，避免继承前一把武器的状态
	_ws = WeaponState.IDLE
	is_attacking = false
	_active_timer = 0.0
	_cooldown_timer = 0.0
	visible = true


func unequip():
	visible = false
	_clear_weapon_visual()
	_clear_hitbox()
	# 重置状态机
	_ws = WeaponState.IDLE
	is_attacking = false
	_active_timer = 0.0
	_cooldown_timer = 0.0
	equipment = null
	weapon_data = null


func _spawn_weapon_visual():
	_clear_weapon_visual()
	if weapon_data.weapon_scene:
		var visual_instance = weapon_data.weapon_scene.instantiate()
		if visual_instance is WeaponVisualBase:
			_weapon_visual = visual_instance
			add_child(_weapon_visual)
			_weapon_visual.setup(weapon_data)
			_weapon_visual.set_aim_direction(aim_direction)
		else:
			push_warning("Weapon scene root must have WeaponVisualBase script")
			visual_instance.queue_free()


func _clear_weapon_visual():
	if _weapon_visual and is_instance_valid(_weapon_visual):
		_weapon_visual.teardown()
		_weapon_visual.queue_free()
	_weapon_visual = null


func _apply_archetype_modifiers():
	if weapon_data == null:
		return
	var mods = WeaponData.get_implicit_modifiers(weapon_data.archetype)
	for m in mods:
		match m.target_stat:
			EquipmentEnums.StatTarget.ATTACK_SPEED:
				weapon_data.attack_speed *= (1.0 + m.value)
			EquipmentEnums.StatTarget.ATTACK_DAMAGE:
				weapon_data.damage *= (1.0 + m.value)


# ════════════════════════════════════════
#  动态 Hitbox
# ════════════════════════════════════════

func _init_hitbox():
	_clear_hitbox()
	if weapon_data.weapon_type == WeaponData.WeaponType.MELEE:
		_hitbox = Area2D.new()
		_hitbox.name = "Hitbox"
		_hitbox.set_script(load("res://scripts/battle/hitbox.gd"))
		_hitbox.collision_layer = 0
		_hitbox.collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_ENEMY)
		var cs = CollisionShape2D.new()
		cs.position = weapon_data.hitbox_offset
		match weapon_data.hitbox_shape:
			WeaponData.HitboxShape.RECTANGLE:
				var rect = RectangleShape2D.new()
				rect.size = weapon_data.hitbox_size if weapon_data.hitbox_size != Vector2.ZERO else Vector2(weapon_data.attack_range, weapon_data.attack_range)
				cs.shape = rect
			_:  # CIRCLE
				var circle = CircleShape2D.new()
				circle.radius = weapon_data.hitbox_size.x if weapon_data.hitbox_size != Vector2.ZERO else weapon_data.attack_range
				cs.shape = circle
		_hitbox.add_child(cs)
		add_child(_hitbox)
		_hitbox.set_deferred("monitoring", false)
		_hitbox.set_deferred("monitorable", false)
		_hitbox.lifespan = 0
		_hitbox.hit_landed.connect(_on_melee_hit)


func _clear_hitbox():
	if _hitbox and is_instance_valid(_hitbox):
		_hitbox.queue_free()
	_hitbox = null


# ════════════════════════════════════════
#  攻击分发
# ════════════════════════════════════════

func attack():
	if not can_attack():
		return
	if shooter == null:
		shooter = get_parent() as Node2D
	_start_attack()
	if weapon_data.weapon_type == WeaponData.WeaponType.MELEE:
		_attack_melee()
	else:
		_attack_ranged()
	_end_active()


# ════════════════════════════════════════
#  近战攻击
# ════════════════════════════════════════

func _attack_melee():
	AudioManager.play_sfx(AudioManager.SfxType.PLAYER_MELEE)

	# 触发武器视觉攻击动画
	if _weapon_visual:
		_weapon_visual.flash_range()
		_weapon_visual.swing()

	_hitbox.damage = weapon_data.damage
	_hitbox.damage_type = weapon_data.damage_type
	_hitbox.shooter = shooter
	_hitbox.knockback_force = weapon_data.knockback_force
	_hitbox.status_effect_type = weapon_data.status_effect_type
	_hitbox.status_effect_damage = weapon_data.status_effect_damage
	_hitbox.status_effect_duration = weapon_data.status_effect_duration
	_hitbox.reset()
	_hitbox.global_position = shooter.global_position
	_hitbox.monitoring = true
	_hitbox.monitorable = true


func _on_melee_hit(target: Node2D):
	_hit_count += 1
	hit_landed.emit(target.global_position, aim_direction, weapon_data.damage_type, target)


# ════════════════════════════════════════
#  远程攻击
# ════════════════════════════════════════

func _attack_ranged():
	AudioManager.play_sfx(AudioManager.SfxType.PLAYER_SHOT)

	var ammo_node = shooter.get_node_or_null("AmmoSystem")
	if weapon_data.max_ammo > 0 and ammo_node and not ammo_node.consume_ammo():
		return

	# 触发武器视觉攻击动画
	if _weapon_visual:
		_weapon_visual.flash_range()

	var parent = shooter.get_parent()
	var pool = GameManager.get_bullet_pool()
	var scene = weapon_data.bullet_scene if weapon_data.bullet_scene else _DefaultBulletScene
	var bullet
	if scene == _DefaultBulletScene and pool:
		bullet = pool.acquire(parent)
		bullet.set_pool(pool)
	else:
		bullet = scene.instantiate()
		parent.add_child(bullet)

	bullet.global_position = shooter.global_position
	bullet.direction = aim_direction
	bullet.data = weapon_data.bullet_data if weapon_data.bullet_data else _make_default_bullet_data()
	bullet.damage = weapon_data.damage
	bullet.damage_type = weapon_data.damage_type
	bullet.shooter = shooter
	bullet.status_effect_type = weapon_data.status_effect_type
	bullet.status_effect_damage = weapon_data.status_effect_damage
	bullet.status_effect_duration = weapon_data.status_effect_duration

	var sprite = bullet.get_node_or_null("Sprite2D")
	if sprite:
		var color = DamageSystem.get_color(weapon_data.damage_type)
		sprite.texture = DamageSystem.get_circle_texture(_BULLET_SIZE, color)
		sprite.centered = true

	if not bullet.hit.is_connected(_on_ranged_hit):
		bullet.hit.connect(_on_ranged_hit)


func _on_ranged_hit(hit_pos: Vector2, hit_dir: Vector2, hit_damage_type: int, body: Node2D):
	hit_landed.emit(hit_pos, hit_dir, hit_damage_type, body)


func _make_default_bullet_data() -> BulletData:
	var bd = BulletData.new()
	bd.speed = weapon_data.bullet_speed if weapon_data else 600.0
	bd.lifetime = 2.0
	return bd


# ════════════════════════════════════════
#  状态机
# ════════════════════════════════════════

func can_attack() -> bool:
	return _ws == WeaponState.IDLE and weapon_data != null


func get_cooldown_time() -> float:
	return 1.0 / (weapon_data.attack_speed * attack_speed_modifier) if weapon_data else 1.0


func _start_attack():
	_ws = WeaponState.ACTIVE
	is_attacking = true
	_active_timer = 0.15
	_cooldown_timer = get_cooldown_time()
	_hit_count = 0


func _end_active():
	_ws = WeaponState.COOLDOWN
	is_attacking = false
	if _hitbox:
		_hitbox.monitoring = false
		_hitbox.monitorable = false
	attack_finished.emit(self, _hit_count)


# ════════════════════════════════════════
#  朝向更新
# ════════════════════════════════════════

func set_aim_direction(dir: Vector2):
	aim_direction = dir
	if _weapon_visual:
		_weapon_visual.set_aim_direction(dir)
