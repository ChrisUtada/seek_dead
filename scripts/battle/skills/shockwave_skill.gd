class_name ShockwaveSkill
extends SkillBase

@export var aoe_range: float = 120.0
@export var damage_mult: float = 1.5
@export var knockback_force: float = 300.0

func _init():
	skill_name = "震波"
	skill_description = "对周围敌人造成范围伤害并击退"
	energy_cost = 10.0
	cooldown = 8.0

var _shape_cache: CircleShape2D

func _activate_skill(user: Node2D):
	play_visual(user)
	var space = user.get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	if not _shape_cache:
		_shape_cache = CircleShape2D.new()
	_shape_cache.radius = aoe_range
	query.shape = _shape_cache
	query.transform = user.global_transform
	query.collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_ENEMY)
	query.exclude = [user]
	var results = space.intersect_shape(query)
	for result in results:
		var target = result.collider as Damageable
		if not target:
			continue
		target.take_damage(target.state.max_hp * 0.15 if "state" in target else 30.0, -1)
		var dir = (target.global_position - user.global_position).normalized()
		target.knockback(dir * knockback_force)
