class_name WeaponComponent
extends Node2D

signal weapon_changed(weapon: WeaponBase)
signal attack_performed(weapon: WeaponBase, hit_count: int)

var weapons: Array[WeaponBase] = []
var weapon_index: int = 0
var attack_cooldown: float = 0.0

var _visual: Node2D = null

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
	attack_cooldown = 1.0 / current_weapon.attack_speed

	match current_weapon.weapon_type:
		WeaponBase.WeaponType.MELEE:
			_melee_attack()
		WeaponBase.WeaponType.RANGED:
			_ranged_attack()

func tick_cooldown(delta: float):
	attack_cooldown = max(0, attack_cooldown - delta)

func _melee_attack():
	_visual.flash_range()
	_visual.swing()
	var parent: CharacterBody2D = get_parent()
	var space = parent.get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = current_weapon.range
	query.shape = shape
	query.transform = parent.global_transform
	query.collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_ENEMY)
	query.exclude = [parent]

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
	_visual.flash_range()
	var parent: CharacterBody2D = get_parent()
	var bullet = load("res://scenes/battle/projectile.tscn").instantiate()
	bullet.global_position = parent.global_position
	bullet.direction = Vector2.RIGHT.rotated(parent.global_rotation)
	bullet.damage = current_weapon.damage
	bullet.damage_type = current_weapon.damage_type
	bullet.shooter = parent
	bullet.status_effect_type = current_weapon.status_effect_type
	bullet.status_effect_damage = current_weapon.status_effect_damage
	bullet.status_effect_duration = current_weapon.status_effect_duration
	parent.get_parent().add_child(bullet)

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
