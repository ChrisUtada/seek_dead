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

func _activate_skill(user: Node2D):
	var space = user.get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = aoe_range
	query.shape = shape
	query.transform = user.global_transform
	query.collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_ENEMY)
	query.exclude = [user]
	var results = space.intersect_shape(query)
	for result in results:
		var body = result.collider
		if body.has_method("take_damage"):
			var dmg = body.state.max_hp * 0.15 if body.has_node("StateComponent") else 30.0
			body.take_damage(dmg, -1)
		if body.has_method("knockback"):
			var dir = (body.global_position - user.global_position).normalized()
			body.knockback(dir * knockback_force)
