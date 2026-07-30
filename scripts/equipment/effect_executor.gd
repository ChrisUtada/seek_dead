class_name EffectExecutor
extends Node

var _shield_amount: float = 0.0
var _shield_node: Node2D = null

const SHIELD_LIFETIME: float = 5.0

const _BulletScene = preload("res://scenes/battle/projectile.tscn")
const _DefaultBulletData = preload("res://resources/bullets/default_bullet.tres")
const _BULLET_SIZE := 10
const _PROJECTILE_SPREAD := deg_to_rad(10.0)


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
		EquipmentEnums.EffectAction.SPAWN_POOL:
			return _execute_spawn_pool(effect, context)
		EquipmentEnums.EffectAction.FIRE_AURA:
			return _execute_fire_aura(effect, context)
		EquipmentEnums.EffectAction.SLOW_ENEMIES:
			return _execute_slow_enemies(effect, context)
		_:
			Debug.error("[EffectExecutor] 未实现效果: " + str(effect.effect_action))
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
	query.transform = Transform2D(0, pos)
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
	Debug.log("[效果执行] 治疗 +%.1f (%.0f→%.0f)" % [amount, old, state.hp])
	return true


func _execute_shield(effect: TriggerEffect, context: Dictionary) -> bool:
	var state = _get_state()
	if not state:
		return false
	var amount = effect.param_value
	if amount <= 0:
		amount = state.max_hp * 0.2
	_shield_amount = amount
	Debug.log("[效果执行] 护盾 +%.1f (持续%.1fs)" % [amount, SHIELD_LIFETIME])
	return true


func has_shield() -> bool:
	return _shield_amount > 0


func absorb_damage(amount: float) -> float:
	if _shield_amount <= 0:
		return amount
	var absorbed = min(_shield_amount, amount)
	_shield_amount -= absorbed
	Debug.log("[护盾] 吸收 %.1f 伤害 (剩余 %.1f)" % [absorbed, _shield_amount])
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
	Debug.log("[效果执行] 击退 %d 个敌人 (半径%.0f, 力度%.0f)" % [enemies.size(), radius, force])
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
	Debug.log("[效果执行] 爆炸: %.1f 范围伤害 %d 个敌人 (半径%.0f)" % [damage, enemies.size(), radius])
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
	Debug.log("[效果执行] 连锁闪电: 命中 %d 个敌人" % [hit_count])
	return true


func _execute_spawn_projectile(effect: TriggerEffect, context: Dictionary) -> bool:
	var player = _get_player()
	if not player:
		return false
	var count = int(effect.param_value)
	if count <= 0:
		count = 1

	# 朝鼠标瞄准方向发射（与 player_controller 一致）
	var aim_dir = (player.get_global_mouse_position() - player.global_position).normalized()
	if aim_dir == Vector2.ZERO:
		aim_dir = Vector2.RIGHT

	var damage = context.get("damage", 12.0)
	var dmg_type = DamageSystem.DamageType.PUNCTURE
	var color = DamageSystem.get_color(dmg_type)

	var pool = GameManager.get_bullet_pool()
	var parent = player.get_parent()

	for i in count:
		# 以瞄准方向为中心做扇形分布
		var angle_offset = (i - float(count - 1) / 2.0) * _PROJECTILE_SPREAD
		var dir = aim_dir.rotated(angle_offset)

		var bullet
		if pool:
			bullet = pool.acquire(parent)
			bullet.set_pool(pool)
		else:
			bullet = _BulletScene.instantiate()
			parent.add_child(bullet)

		bullet.global_position = player.global_position
		bullet.direction = dir
		bullet.data = _DefaultBulletData.duplicate()  # 复制避免共享资源被 pierce 计数改写
		bullet.damage = damage
		bullet.damage_type = dmg_type
		bullet.shooter = player

		var sprite = bullet.get_node_or_null("Sprite2D")
		if sprite:
			sprite.texture = DamageSystem.get_circle_texture(_BULLET_SIZE, color)
			sprite.centered = true

	Debug.log("[效果执行] 发射 %d 枚投射物 (伤害%.1f, 类型=%d)" % [count, damage, dmg_type])
	return true


func _execute_spawn_pool(effect: TriggerEffect, context: Dictionary) -> bool:
	var player = _get_player()
	if not player:
		return false
	var radius = effect.param_value
	if radius <= 0:
		radius = 80.0
	var pool = Area2D.new()
	pool.monitoring = false
	pool.monitorable = false
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	pool.add_child(shape)
	pool.collision_layer = 0
	pool.collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_ENEMY)
	pool.global_position = player.global_position
	var dmg_type = DamageSystem.DamageType.POISON
	var tick_timer = 0.0
	pool.set_script(load("res://scripts/equipment/pool_area.gd"))
	pool.set("damage", context.get("damage", 15.0))
	pool.set("damage_type", dmg_type)
	pool.set("lifetime", 3.0)
	call_deferred("_add_pool_to_scene", pool)
	Debug.log("[效果执行] 毒池: 半径%.0f pos=(%.0f,%.0f)" % [radius, pool.global_position.x, pool.global_position.y])
	return true


func _add_pool_to_scene(pool: Area2D):
	get_tree().current_scene.add_child(pool)
	pool.set_deferred("monitoring", true)
	pool.set_deferred("monitorable", true)


func _execute_fire_aura(effect: TriggerEffect, context: Dictionary) -> bool:
	var player = _get_player()
	if not player:
		return false
	var radius = effect.param_value
	if radius <= 0:
		radius = 100.0
	var aura = Area2D.new()
	aura.monitoring = false
	aura.monitorable = false
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	aura.add_child(shape)
	aura.collision_layer = 0
	aura.collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_ENEMY)
	aura.set_script(load("res://scripts/equipment/aura_area.gd"))
	aura.set("damage", context.get("damage", 10.0))
	aura.set("damage_type", DamageSystem.DamageType.FIRE)
	aura.set("interval", 0.5)
	aura.set("lifetime", 5.0)
	call_deferred("_add_aura_to_player", aura, player)
	Debug.log("[效果执行] 火焰光环: 半径%.0f 持续5s" % [radius])
	return true


func _add_aura_to_player(aura: Area2D, player: Node2D):
	player.add_child(aura)
	aura.global_position = Vector2.ZERO
	aura.set_deferred("monitoring", true)
	aura.set_deferred("monitorable", true)


func _execute_slow_enemies(effect: TriggerEffect, context: Dictionary) -> bool:
	var player = _get_player()
	if not player:
		return false
	var radius = effect.param_value
	if radius <= 0:
		radius = 150.0
	var slow = Area2D.new()
	slow.monitoring = false
	slow.monitorable = false
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	slow.add_child(shape)
	slow.collision_layer = 0
	slow.collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_ENEMY)
	slow.set_script(load("res://scripts/equipment/slow_area.gd"))
	slow.set("speed_mult", 0.5)
	slow.set("lifetime", 3.0)
	call_deferred("_add_slow_to_scene", slow, player.global_position)
	Debug.log("[效果执行] 减速场: 半径%.0f 持续3s" % [radius])
	return true


func _add_slow_to_scene(slow: Area2D, pos: Vector2):
	get_tree().current_scene.add_child(slow)
	slow.global_position = pos
	slow.set_deferred("monitoring", true)
	slow.set_deferred("monitorable", true)
