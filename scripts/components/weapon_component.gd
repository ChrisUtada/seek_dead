class_name WeaponComponent
extends Node2D

signal weapon_changed(weapon: WeaponNode, hand: int)
signal attack_performed(weapon: WeaponNode, hit_count: int)
signal active_hand_changed(hand: int)

# 主副手武器
var weapon_main: EquipmentBase = null
var weapon_offhand: EquipmentBase = null

# 当前激活的手 (0 = 主手, 1 = 副手)
var active_hand: int = 0

# WeaponNode 引用
var _weapon_node: WeaponNode = null

var aim_direction: Vector2 = Vector2.RIGHT

var _particles_pool: Array[ColorRect] = []


func set_aim_direction(dir: Vector2):
	if dir.length_squared() > 0.001:
		aim_direction = dir
		if _weapon_node:
			_weapon_node.aim_direction = dir
		rotation = dir.angle()


func _ready():
	# 获取 WeaponNode 子节点
	for child in get_children():
		if child is WeaponNode:
			_weapon_node = child
			_weapon_node.shooter = get_parent() as CharacterBody2D
			_weapon_node.aim_direction = aim_direction
			_weapon_node.visible = false
			_weapon_node.hit_landed.connect(_on_weapon_hit)
			_weapon_node.attack_finished.connect(_on_attack_finished)
			break


# ════════════════════════════════════════
#  装备接口（由 EquipmentManager 调用）
# ════════════════════════════════════════

func equip_weapon(equip: EquipmentBase, slot: int):
	if equip.weapon_data == null:
		return

	# 存储到对应槽位
	if slot == EquipmentEnums.EquipmentSlot.WEAPON_MAIN:
		weapon_main = equip
	elif slot == EquipmentEnums.EquipmentSlot.WEAPON_OFFHAND:
		weapon_offhand = equip
	else:
		return

	# 如果装备的是当前激活的手，立即更新视觉
	if _is_slot_active(slot):
		_update_weapon_node(equip)
		weapon_changed.emit(_weapon_node, active_hand)


func unequip_weapon(slot: int):
	# 清空对应槽位
	if slot == EquipmentEnums.EquipmentSlot.WEAPON_MAIN:
		weapon_main = null
	elif slot == EquipmentEnums.EquipmentSlot.WEAPON_OFFHAND:
		weapon_offhand = null

	# 如果卸下的是当前激活的手，清空视觉
	if _is_slot_active(slot):
		if _weapon_node:
			_weapon_node.unequip()


## 切换激活的手 (0 = 主手, 1 = 副手)
func switch_active_hand(hand: int):
	if hand == active_hand:
		return
	if hand < 0 or hand > 1:
		return

	active_hand = hand

	# 更新武器视觉
	var equip = _get_active_equipment()
	if equip:
		_update_weapon_node(equip)
	else:
		if _weapon_node:
			_weapon_node.unequip()

	active_hand_changed.emit(hand)


## 获取当前激活的 EquipmentBase
func _get_active_equipment() -> EquipmentBase:
	if active_hand == 0:
		return weapon_main
	else:
		return weapon_offhand


## 公开接口：获取当前激活的 WeaponNode（供 HUD 等外部系统使用）
func get_active_weapon_node() -> WeaponNode:
	if _weapon_node and _get_active_equipment() != null:
		return _weapon_node
	return null


## 检查槽位是否是当前激活的
func _is_slot_active(slot: int) -> bool:
	if slot == EquipmentEnums.EquipmentSlot.WEAPON_MAIN:
		return active_hand == 0
	elif slot == EquipmentEnums.EquipmentSlot.WEAPON_OFFHAND:
		return active_hand == 1
	return false


## 更新 WeaponNode 的装备
func _update_weapon_node(equip: EquipmentBase):
	if _weapon_node:
		_weapon_node.equip(equip)
		_weapon_node.aim_direction = aim_direction


# ════════════════════════════════════════
#  攻击
# ════════════════════════════════════════

func can_attack() -> bool:
	return _weapon_node != null and _weapon_node.can_attack() and _get_active_equipment() != null


func attack():
	if not can_attack():
		return
	var node = _weapon_node
	node.attack_speed_modifier = _get_attack_speed_modifier(node)
	node.attack()


func _get_attack_speed_modifier(node: WeaponNode) -> float:
	var state = _get_state()
	if state and state.in_meltdown():
		var is_ranged = node.weapon_data and node.weapon_data.weapon_type == WeaponData.WeaponType.RANGED
		return 2.0 if is_ranged else 1.5
	return 1.0


# ════════════════════════════════════════
#  命中反馈
# ════════════════════════════════════════

func _on_weapon_hit(hit_pos: Vector2, hit_dir: Vector2, damage_type: int, body: Node2D):
	call_deferred("_on_weapon_hit_deferred", hit_pos, hit_dir, damage_type, body)


func _on_weapon_hit_deferred(hit_pos: Vector2, hit_dir: Vector2, damage_type: int, body: Node2D):
	var color = DamageSystem.get_color(damage_type)
	_spawn_hit_particles(hit_pos, hit_dir, color)
	_spawn_impact_circle(hit_pos, color)
	GameManager.hit_stop(0.03)
	if is_instance_valid(body):
		var target = body as Damageable
		if target:
			target.knockback(hit_dir * 150.0)
	_shake_parent_camera(Vector2(1.5, 0.8), 0.08)


func _on_attack_finished(node: WeaponNode, hit_count: int):
	var state = _get_state()
	var in_meltdown = state and state.in_meltdown()
	var is_ranged = node.weapon_data and node.weapon_data.weapon_type == WeaponData.WeaponType.RANGED
	var is_melee = node.weapon_data and node.weapon_data.weapon_type == WeaponData.WeaponType.MELEE
	if in_meltdown and is_ranged:
		if state:
			state.take_damage(5.0, -1)
	if not in_meltdown:
		_add_heat_after_attack(node)
	if hit_count > 0 and is_melee:
		GameManager.hit_stop(0.04)
		_shake_parent_camera(Vector2(2.0, 1.0), 0.1)
	attack_performed.emit(node, hit_count)


func _get_state():
	return get_parent().get("state") as StateComponent


func _add_heat_after_attack(node: WeaponNode):
	var state = _get_state()
	if not state:
		return
	var heat = node.weapon_data.heat_per_attack if node.weapon_data and node.weapon_data.heat_per_attack >= 0 else -1.0
	if heat < 0:
		var is_melee = node.weapon_data and node.weapon_data.weapon_type == WeaponData.WeaponType.MELEE
		heat = 5.0 if is_melee else 8.0
	state.add_heat(heat)


# ════════════════════════════════════════
#  粒子特效
# ════════════════════════════════════════

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
