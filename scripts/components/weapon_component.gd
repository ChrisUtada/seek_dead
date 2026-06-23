class_name WeaponComponent
extends Node2D

signal weapon_changed(weapon: WeaponBase)
signal attack_performed(weapon: WeaponBase, hit_count: int)

var weapons: Array[WeaponBase] = []
var weapon_index: int = 0
var attack_cooldown: float = 0.0

var aim_direction: Vector2 = Vector2.RIGHT
var _visual: Node2D = null

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
	_visual.set_weapon(DamageSystem.get_color(w.damage_type), w.range, w.weapon_type == WeaponBase.WeaponType.MELEE)

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
	var bullet = load("res://scenes/battle/projectile.tscn").instantiate()
	bullet.global_position = parent.global_position
	bullet.direction = aim_direction
	bullet.damage = current_weapon.damage * _get_damage_modifier()
	bullet.damage_type = current_weapon.damage_type
	bullet.shooter = parent
	bullet.status_effect_type = current_weapon.status_effect_type
	bullet.status_effect_damage = current_weapon.status_effect_damage
	bullet.status_effect_duration = current_weapon.status_effect_duration
	parent.get_parent().add_child(bullet)

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
	bullet.get_node("Sprite2D").texture = ImageTexture.create_from_image(bimg)
	bullet.get_node("Sprite2D").centered = true

	var label = "远程射击" + (" [超载]" if in_meltdown else "")
	print("%s: %s (伤害: %.0f)" % [label, current_weapon.weapon_name, current_weapon.damage * _get_damage_modifier()])
	if not in_meltdown:
		_add_heat_after_attack()
	attack_performed.emit(current_weapon, 1)

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

func _add_heat_after_attack():
	var parent = get_parent()
	if not parent.has_node("StateComponent"):
		return
	var heat = current_weapon.heat_per_attack
	if heat < 0:
		heat = 5.0 if current_weapon.weapon_type == WeaponBase.WeaponType.MELEE else 8.0
	parent.state.add_heat(heat)
