class_name WeaponComponent
extends Node2D

const _WeaponBase = preload("res://scripts/battle/weapon_base.gd")
const _WeaponNode = preload("res://scripts/battle/weapon_node.gd")
const _MeleeWeaponNode = preload("res://scripts/battle/melee_weapon_node.gd")
const _RangedWeaponNode = preload("res://scripts/battle/ranged_weapon_node.gd")

signal weapon_changed(weapon: WeaponNode)
signal attack_performed(weapon: WeaponNode, hit_count: int)

var weapons: Array[WeaponNode] = []
var weapon_index: int = 0
var current_weapon: WeaponNode:
	get: return weapons[weapon_index] if weapons.size() > 0 else null

var aim_direction: Vector2 = Vector2.RIGHT
var _color: Color = Color(1, 1, 1)

var _particles_pool: Array[ColorRect] = []

func set_aim_direction(dir: Vector2):
	if dir.length_squared() > 0.001:
		aim_direction = dir
		for w in weapons:
			w.aim_direction = dir
		rotation = dir.angle()

func init_weapons(weapon_list: Array[WeaponBase]):
	for w in weapon_list:
		var scene = w.visual_scene
		if not scene:
			continue
		var node = scene.instantiate() as WeaponNode
		if not node:
			continue
		node.stats = w
		node.shooter = get_parent() as CharacterBody2D
		node.aim_direction = aim_direction
		node.weapon_color = DamageSystem.get_color(w.damage_type)
		node.hit_landed.connect(_on_weapon_hit)
		node.attack_finished.connect(_on_attack_finished)
		node.visible = false
		add_child(node)
		weapons.append(node)
	weapon_index = 0
	if weapons.size() > 0:
		weapons[0].on_equip()
		weapon_changed.emit(weapons[0])

func switch_weapon(index: int):
	if index == weapon_index or index >= weapons.size():
		return
	if current_weapon:
		current_weapon.on_unequip()
	weapon_index = index
	current_weapon.on_equip()
	_color = DamageSystem.get_color(current_weapon.stats.damage_type)
	weapon_changed.emit(current_weapon)

func can_attack() -> bool:
	return current_weapon != null and current_weapon.can_attack()

func attack():
	if not can_attack():
		return
	var node = current_weapon
	var speed_mod = _get_attack_speed_modifier(node)
	node.cooldown = 1.0 / (node.stats.attack_speed * speed_mod)
	node.attack()

func get_weapon_count() -> int:
	return weapons.size()

func _on_weapon_hit(hit_pos: Vector2, hit_dir: Vector2, damage_type: int, body: Node2D):
	call_deferred("_on_weapon_hit_deferred", hit_pos, hit_dir, damage_type, body)

func _on_weapon_hit_deferred(hit_pos: Vector2, hit_dir: Vector2, damage_type: int, body: Node2D):
	var color = DamageSystem.get_color(damage_type)
	_spawn_hit_particles(hit_pos, hit_dir, color)
	_spawn_impact_circle(hit_pos, color)
	GameManager.hit_stop(0.03)
	if is_instance_valid(body) and body.has_method("knockback"):
		body.knockback(hit_dir * 150.0)
	_shake_parent_camera(Vector2(1.5, 0.8), 0.08)

func _on_attack_finished(node: WeaponNode, hit_count: int):
	var state = _get_state()
	var in_meltdown = state and state.in_meltdown()
	if in_meltdown and node is RangedWeaponNode:
		if state:
			state.take_damage(5.0, -1)
	if not in_meltdown:
		_add_heat_after_attack(node)
	if hit_count > 0 and node is MeleeWeaponNode:
		GameManager.hit_stop(0.04)
		_shake_parent_camera(Vector2(2.0, 1.0), 0.1)
	attack_performed.emit(node, hit_count)

func _get_state():
	var parent = get_parent()
	return parent.state if parent.has_node("StateComponent") else null

func _get_attack_speed_modifier(node: WeaponNode) -> float:
	var state = _get_state()
	if state and state.in_meltdown():
		return 2.0 if node is RangedWeaponNode else 1.5
	return 1.0

func _add_heat_after_attack(node: WeaponNode):
	var state = _get_state()
	if not state:
		return
	var heat = node.stats.heat_per_attack if node.stats and node.stats.heat_per_attack >= 0 else -1.0
	if heat < 0:
		heat = 5.0 if node is MeleeWeaponNode else 8.0
	state.add_heat(heat)

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
