class_name RangedWeaponNode
extends WeaponNode

const _RangedWeapon = preload("res://scripts/battle/ranged_weapon.gd")

func attack():
	if not shooter or not stats:
		return
	var ranged_stats = stats as RangedWeapon
	if not ranged_stats:
		return

	cooldown = get_cooldown_time()

	var ammo_node = shooter.get_node_or_null("AmmoSystem")
	if ranged_stats.max_ammo > 0 and ammo_node and not ammo_node.consume_ammo():
		return

	flash_range()
	AudioManager.play_sfx(AudioManager.SfxType.PLAYER_SHOT)

	var parent = shooter.get_parent()
	var scene = ranged_stats.bullet_scene if ranged_stats.bullet_scene else load("res://scenes/battle/projectile.tscn")
	var bullet = scene.instantiate()
	bullet.global_position = shooter.global_position
	bullet.direction = aim_direction
	bullet.data = ranged_stats.bullet_data
	bullet.damage = stats.damage
	bullet.damage_type = stats.damage_type
	bullet.shooter = shooter
	bullet.status_effect_type = stats.status_effect_type
	bullet.status_effect_damage = stats.status_effect_damage
	bullet.status_effect_duration = stats.status_effect_duration
	bullet._age = 0
	parent.add_child(bullet)

	var sprite = bullet.get_node_or_null("Sprite2D")
	if sprite:
		var bsize = 10
		var color = DamageSystem.get_color(stats.damage_type)
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

	bullet.hit.connect(_on_bullet_hit)
	attack_finished.emit(self, 1)

func _on_bullet_hit(hit_pos: Vector2, hit_dir: Vector2, hit_damage_type: int, body: Node2D):
	hit_landed.emit(hit_pos, hit_dir, hit_damage_type, body)
