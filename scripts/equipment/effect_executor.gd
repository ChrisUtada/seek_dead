class_name EffectExecutor
extends Node

var _shield_amount: float = 0.0
var _shield_node: Node2D = null

const SHIELD_LIFETIME: float = 5.0


func execute(effect: TriggerEffect, context: Dictionary = {}) -> bool:
	match effect.effect_action:
		EquipmentEnums.EffectAction.HEAL:
			return _execute_heal(effect, context)
		EquipmentEnums.EffectAction.SHIELD:
			return _execute_shield(effect, context)
		EquipmentEnums.EffectAction.KNOCKBACK:
			return _execute_knockback(effect, context)
		EquipmentEnums.EffectAction.EXPLODE:
			return _execute_explode(effect, context)
		EquipmentEnums.EffectAction.CHAIN_LIGHTNING:
			return _execute_chain_lightning(effect, context)
		EquipmentEnums.EffectAction.SPAWN_PROJECTILE:
			return _execute_spawn_projectile(effect, context)
		_:
			print("[EffectExecutor] 未实现效果: ", effect.effect_action)
			return false


func _get_player() -> Node2D:
	var mgr = get_parent()
	if not mgr:
		return null
	return mgr.get_parent() as Node2D


func _get_state() -> StateComponent:
	var p = _get_player()
	if not p:
		return null
	return p.get_node_or_null("StateComponent") as StateComponent


func _get_nearest_enemies(pos: Vector2, radius: float, max_count: int) -> Array:
	var player = _get_player()
	if not player:
		return []
	var space = player.get_world_2d().direct_space_state
	if not space:
		return []
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = radius
	query.shape = shape
	query.position = pos
	query.collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_ENEMY)
	query.collide_with_areas = true
	var results = space.intersect_shape(query)
	var enemies: Array = []
	for r in results:
		if enemies.size() >= max_count:
			break
		var obj = r.collider
		if not obj:
			continue
		var owner = obj.owner if obj.owner else obj
		if owner is Damageable and owner not in enemies:
			enemies.append(owner)
	return enemies


func _execute_heal(effect: TriggerEffect, context: Dictionary) -> bool:
	var state = _get_state()
	if not state:
		return false
	var amount = effect.param_value
	if amount <= 0:
		amount = state.max_hp * 0.1
	var old = state.hp
	state.hp += amount
	print("[效果执行] 治疗 +%.1f (%.0f→%.0f)" % [amount, old, state.hp])
	return true


func _execute_shield(effect: TriggerEffect, context: Dictionary) -> bool:
	var state = _get_state()
	if not state:
		return false
	var amount = effect.param_value
	if amount <= 0:
		amount = state.max_hp * 0.2
	_shield_amount = amount
	print("[效果执行] 护盾 +%.1f (持续%.1fs)" % [amount, SHIELD_LIFETIME])
	return true


func has_shield() -> bool:
	return _shield_amount > 0


func absorb_damage(amount: float) -> float:
	if _shield_amount <= 0:
		return amount
	var absorbed = min(_shield_amount, amount)
	_shield_amount -= absorbed
	print("[护盾] 吸收 %.1f 伤害 (剩余 %.1f)" % [absorbed, _shield_amount])
	return amount - absorbed


func _execute_knockback(effect: TriggerEffect, context: Dictionary) -> bool:
	var player = _get_player()
	if not player:
		return false
	var radius = effect.param_value
	if radius <= 0:
		radius = 150.0
	var enemies = _get_nearest_enemies(player.global_position, radius, 20)
	var force = effect.param_value
	for e in enemies:
		var dir = (e.global_position - player.global_position).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		e.knockback(dir * force)
	print("[效果执行] 击退 %d 个敌人 (半径%.0f, 力度%.0f)" % [enemies.size(), radius, force])
	return true


func _execute_explode(effect: TriggerEffect, context: Dictionary) -> bool:
	var player = _get_player()
	if not player:
		return false
	var radius = effect.param_value
	if radius <= 0:
		radius = 100.0
	var damage = context.get("damage", 10.0)
	var enemies = _get_nearest_enemies(player.global_position, radius, 30)
	for e in enemies:
		e.take_damage(damage, DamageSystem.DamageType.FIRE)
	print("[效果执行] 爆炸: %.1f 范围伤害 %d 个敌人 (半径%.0f)" % [damage, enemies.size(), radius])
	return true


func _execute_chain_lightning(effect: TriggerEffect, context: Dictionary) -> bool:
	var player = _get_player()
	if not player:
		return false
	var chain_count = int(effect.param_value)
	if chain_count <= 0:
		chain_count = 3
	var damage = context.get("damage", 15.0)
	var enemies = _get_nearest_enemies(player.global_position, 250.0, 10)
	var hit_count = 0
	var chain_pos = player.global_position
	for i in range(min(chain_count, enemies.size())):
		var e = enemies[i]
		e.take_damage(damage * 0.5, DamageSystem.DamageType.LIGHTNING)
		chain_pos = e.global_position
		hit_count += 1
	print("[效果执行] 连锁闪电: 命中 %d 个敌人" % [hit_count])
	return true


func _execute_spawn_projectile(effect: TriggerEffect, context: Dictionary) -> bool:
	print("[效果执行] SPAWN_PROJECTILE: 待实现 (param=% .1f)" % [effect.param_value])
	return false
