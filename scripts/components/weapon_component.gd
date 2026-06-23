class_name WeaponComponent
extends Node2D

signal weapon_changed(weapon: WeaponBase)
signal attack_performed(weapon: WeaponBase, hit_count: int)

var weapons: Array[WeaponBase] = []
var weapon_index: int = 0
var attack_cooldown: float = 0.0

var aim_direction: Vector2 = Vector2.RIGHT
var _visual: Node2D = null

var _bullet_pools: Dictionary = {}
var _particles_pool: Array[ColorRect] = []
const POOL_BULLET_SIZE: int = 20
const POOL_PARTICLE_SIZE: int = 60

func set_aim_direction(dir: Vector2):
	if dir.length_squared() > 0.001:
		aim_direction = dir
		rotation = dir.angle()

var current_weapon: WeaponBase:
	get: return weapons[weapon_index] if weapons.size() > 0 else null

func _ready():
	_visual = load("res://scripts/ui/weapon_visual.gd").new()
	add_child(_visual)
	_visual.visible = false

func init_weapons(weapon_list: Array[WeaponBase]):
	weapons = weapon_list
	weapon_index = 0
	if weapons.size() > 0:
		_update_visual(weapons[0])
		weapon_changed.emit(weapons[0])

func _update_visual(w: WeaponBase):
	if not _visual:
		return
	_visual.visible = true
	_color = DamageSystem.get_color(w.damage_type)
	_visual.set_weapon(_color, w.range, w.weapon_type == WeaponBase.WeaponType.MELEE)

func switch_weapon(index: int):
	if index != weapon_index and index < weapons.size():
		weapon_index = index
		_update_visual(current_weapon)
		weapon_changed.emit(current_weapon)

func can_attack() -> bool:
	return current_weapon != null and attack_cooldown <= 0

func attack():
	if not can_attack():
		return
	var speed_mod = _get_attack_speed_modifier()
	attack_cooldown = 1.0 / (current_weapon.attack_speed * speed_mod)

	match current_weapon.weapon_type:
		WeaponBase.WeaponType.MELEE:
			_melee_attack()
		WeaponBase.WeaponType.RANGED:
			_ranged_attack()

func tick_cooldown(delta: float):
	attack_cooldown = max(0, attack_cooldown - delta)

func _melee_attack():
	var parent: CharacterBody2D = get_parent()
	var state = parent.state if parent.has_node("StateComponent") else null
	var in_meltdown = state and state.in_meltdown()
	var atk_range = current_weapon.range * (1.5 if in_meltdown else 1.0)

	_visual.flash_range()
	_visual.swing()
	AudioManager.play_sfx(AudioManager.SfxType.PLAYER_MELEE)
	var space = parent.get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = atk_range
	query.shape = shape
	query.transform = parent.global_transform
	query.collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_ENEMY)
	query.exclude = [parent]

	var results = space.intersect_shape(query)
	var hit_count = 0
	var dmg_mod = _get_damage_modifier()
	var final_dmg = current_weapon.damage * dmg_mod

	for result in results:
		var body = result.collider
		if body.has_method("take_damage"):
			var damage_result = body.take_damage(final_dmg, current_weapon.damage_type)
			hit_count += 1
			if in_meltdown:
				damage_result.is_critical = true
				damage_result.hit_result = DamageSystem.HitResult.CRITICAL
				if state:
					var recoil = max(final_dmg * 0.1, 5.0)
					state.take_damage(recoil, -1)

			if current_weapon.status_effect_type >= 0 and body.has_method("apply_status"):
				body.apply_status(current_weapon.status_effect_type, current_weapon.status_effect_damage, current_weapon.status_effect_duration)

			if damage_result.hit_result == DamageSystem.HitResult.CRITICAL:
				print("! 暴击! %.0f 伤害 (%.1fx)" % [damage_result.final_damage, damage_result.breakdown.get("crit_damage", 1.5)])
			elif damage_result.is_weakness:
				print("! 弱点! %.0f 伤害 (属性克制%.1fx)" % [damage_result.final_damage, damage_result.breakdown.get("type_advantage", 1.0)])

	if hit_count == 0:
		print("近战挥空 (范围: %.0f)" % atk_range)
	else:
		print("近战命中 %d 个敌人" % hit_count)
		GameManager.hit_stop(0.04)
		_spawn_impact_circle(results[0].collider.global_position, _color)
		for result in results:
			var pos = result.collider.global_position
			_spawn_hit_particles(pos, aim_direction, _color)
			if result.collider.has_method("knockback"):
				result.collider.knockback(aim_direction * 200.0)
		_shake_parent_camera(Vector2(2.0, 1.0), 0.1)

	if not in_meltdown:
		_add_heat_after_attack()
	attack_performed.emit(current_weapon, hit_count)

func _ranged_attack():
	var parent: CharacterBody2D = get_parent()
	var state = parent.state if parent.has_node("StateComponent") else null
	var in_meltdown = state and state.in_meltdown()

	if not in_meltdown:
		if current_weapon.max_ammo > 0:
			var ammo_node = parent.get_node_or_null("AmmoSystem")
			if ammo_node and not ammo_node.consume_ammo():
				return
	else:
		if state:
			state.take_damage(5.0, -1)

	_visual.flash_range()
	AudioManager.play_sfx(AudioManager.SfxType.PLAYER_SHOT)
	var bullet_scene = current_weapon.bullet_scene
	if bullet_scene == null:
		bullet_scene = load("res://scenes/battle/projectile.tscn")
	var bullet = _get_bullet(bullet_scene)
	bullet.global_position = parent.global_position
	bullet._age = 0
	bullet.direction = aim_direction
	bullet.speed = current_weapon.bullet_speed
	bullet.damage = current_weapon.damage * _get_damage_modifier()
	bullet.damage_type = current_weapon.damage_type
	bullet.shooter = parent
	bullet.status_effect_type = current_weapon.status_effect_type
	bullet.status_effect_damage = current_weapon.status_effect_damage
	bullet.status_effect_duration = current_weapon.status_effect_duration
	var sprite = bullet.get_node_or_null("Sprite2D")
	if sprite:
		var color = DamageSystem.get_color(current_weapon.damage_type)
		var bsize = 18 if in_meltdown else 10
		var bimg = Image.create(bsize, bsize, false, Image.FORMAT_RGBA8)
		bimg.fill(Color(0, 0, 0, 0))
		var radius = bsize >> 1
		for x in range(bsize):
			for y in range(bsize):
				var dx = x - radius
				var dy = y - radius
				if dx * dx + dy * dy < radius * radius:
					bimg.set_pixel(x, y, color)
		sprite.texture = ImageTexture.create_from_image(bimg)
		sprite.centered = true

	if not bullet.hit.is_connected(_on_bullet_hit):
		bullet.hit.connect(_on_bullet_hit)
	var label = "远程射击" + (" [超载]" if in_meltdown else "")
	print("%s: %s (伤害: %.0f)" % [label, current_weapon.weapon_name, current_weapon.damage * _get_damage_modifier()])
	if not in_meltdown:
		_add_heat_after_attack()
	attack_performed.emit(current_weapon, 1)

func _on_bullet_hit(hit_pos: Vector2, hit_dir: Vector2, damage_type: int, body: Node2D):
	call_deferred("_on_bullet_hit_deferred", hit_pos, hit_dir, damage_type, body)

func _on_bullet_hit_deferred(hit_pos: Vector2, hit_dir: Vector2, damage_type: int, body: Node2D):
	var color = DamageSystem.get_color(damage_type)
	_spawn_hit_particles(hit_pos, hit_dir, color)
	_spawn_impact_circle(hit_pos, color)
	GameManager.hit_stop(0.03)
	if is_instance_valid(body) and body.has_method("knockback"):
		body.knockback(hit_dir * 150.0)
	_shake_parent_camera(Vector2(1.5, 0.8), 0.08)

func _spawn_hit_particles(pos: Vector2, dir: Vector2, particle_color: Color = Color(1, 1, 1)):
	var count = randi_range(6, 10)
	var parent = get_parent().get_parent()
	for i in range(count):
		var dot = _get_particle()
		dot.size = Vector2(randf_range(4.0, 8.0), randf_range(4.0, 8.0))
		var spread = dir.rotated(randf_range(-1.4, 1.4))
		var dist = randf_range(12.0, 40.0)
		dot.color = Color(particle_color.r, particle_color.g, particle_color.b, 0.9)
		dot.global_position = pos
		dot.modulate = Color(1, 1, 1, 1)
		dot.visible = true
		parent.add_child(dot)
		var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_LINEAR)
		tween.tween_property(dot, "global_position", pos + spread * dist, 0.25)
		tween.parallel().tween_property(dot, "modulate", Color(1, 1, 1, 0), 0.25)
		tween.tween_callback(_release_particle.bind(dot))

func _spawn_impact_circle(pos: Vector2, color: Color):
	var parent = get_parent().get_parent()
	var ring = _get_particle()
	ring.size = Vector2(4, 4)
	ring.color = Color(color.r, color.g, color.b, 0.6)
	ring.modulate = Color(1, 1, 1, 1)
	ring.visible = true
	ring.global_position = pos - Vector2(2, 2)
	parent.add_child(ring)
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUINT)
	tween.tween_property(ring, "size", Vector2(60, 60), 0.15)
	tween.parallel().tween_property(ring, "modulate", Color(1, 1, 1, 0), 0.15)
	tween.tween_callback(_release_particle.bind(ring))

func _shake_parent_camera(intensity: Vector2, duration: float):
	var parent = get_parent()
	if not parent.has_method("_shake_camera"):
		return
	parent._shake_camera(intensity, duration)

var _color: Color = Color(1, 1, 1)

func _get_attack_speed_modifier() -> float:
	var parent = get_parent()
	if not parent.has_node("StateComponent"):
		return 1.0
	var state = parent.state
	if state.in_meltdown():
		return 2.0 if current_weapon.weapon_type == WeaponBase.WeaponType.RANGED else 1.5
	return 1.0

func _get_damage_modifier() -> float:
	var parent = get_parent()
	if not parent.has_node("StateComponent"):
		return 1.0
	var state = parent.state
	if state.in_meltdown() and current_weapon.weapon_type == WeaponBase.WeaponType.RANGED:
		return 1.5
	return 1.0

func _get_bullet(scene: PackedScene) -> Node:
	var target = get_parent().get_parent()
	var path = scene.resource_path
	if not _bullet_pools.has(path):
		_bullet_pools[path] = ObjectPool.new(scene, POOL_BULLET_SIZE)
	var pool = _bullet_pools[path]
	var bullet = pool.acquire(target)
	bullet.set_pool(pool)
	return bullet

func _get_particle() -> ColorRect:
	if _particles_pool.size() > 0:
		return _particles_pool.pop_back()
	return ColorRect.new()

func _release_particle(p: ColorRect):
	if not is_instance_valid(p):
		return
	if p.get_parent():
		p.get_parent().remove_child(p)
	p.visible = false
	_particles_pool.append(p)

func _add_heat_after_attack():
	var parent = get_parent()
	if not parent.has_node("StateComponent"):
		return
	var heat = current_weapon.heat_per_attack
	if heat < 0:
		heat = 5.0 if current_weapon.weapon_type == WeaponBase.WeaponType.MELEE else 8.0
	parent.state.add_heat(heat)
