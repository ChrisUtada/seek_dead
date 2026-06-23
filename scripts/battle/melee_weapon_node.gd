class_name MeleeWeaponNode
extends WeaponNode

func attack():
	if not shooter or not stats:
		return
	cooldown = get_cooldown_time()
	flash_range()
	swing()
	AudioManager.play_sfx(AudioManager.SfxType.PLAYER_MELEE)

	var space = shooter.get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = stats.attack_range
	query.shape = shape
	query.transform = shooter.global_transform
	query.collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_ENEMY)
	query.exclude = [shooter]

	var results = space.intersect_shape(query)
	var hit_count = 0
	for result in results:
		var body = result.collider
		if body.has_method("take_damage"):
			body.take_damage(stats.damage, stats.damage_type)
			hit_count += 1
			if stats.status_effect_type >= 0 and body.has_method("apply_status"):
				body.apply_status(stats.status_effect_type, stats.status_effect_damage, stats.status_effect_duration)
			hit_landed.emit(body.global_position, aim_direction, stats.damage_type, body)

	attack_finished.emit(self, hit_count)
