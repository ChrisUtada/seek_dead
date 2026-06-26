class_name RangedWeaponNode
extends WeaponNode

const _RangedWeapon = preload("res://scripts/battle/ranged_weapon.gd")
const _DefaultBulletScene = preload("res://scenes/battle/projectile.tscn")
const _BULLET_SIZE := 10

func attack():
	if not can_attack():
		return
	_start_attack()

	var ranged_stats = stats as RangedWeapon
	if not ranged_stats:
		_end_active()
		return

	var ammo_node = shooter.get_node_or_null("AmmoSystem")
	if ranged_stats.max_ammo > 0 and ammo_node and not ammo_node.consume_ammo():
		_end_active()
		return

	flash_range()
	AudioManager.play_sfx(AudioManager.SfxType.PLAYER_SHOT)

	var parent = shooter.get_parent()
	var pool = GameManager.get_bullet_pool()
	var scene = ranged_stats.bullet_scene if ranged_stats.bullet_scene else _DefaultBulletScene
	var bullet
	if scene == _DefaultBulletScene and pool:
		bullet = pool.acquire(parent)
		bullet.set_pool(pool)
	else:
		bullet = scene.instantiate()
		parent.add_child(bullet)
	bullet.global_position = shooter.global_position
	bullet.direction = aim_direction
	bullet.data = ranged_stats.bullet_data
	bullet.damage = stats.damage
	bullet.damage_type = stats.damage_type
	bullet.shooter = shooter
	bullet.status_effect_type = stats.status_effect_type
	bullet.status_effect_damage = stats.status_effect_damage
	bullet.status_effect_duration = stats.status_effect_duration

	var sprite = bullet.get_node_or_null("Sprite2D")
	if sprite:
		var color = DamageSystem.get_color(stats.damage_type)
		sprite.texture = DamageSystem.get_circle_texture(_BULLET_SIZE, color)
		sprite.centered = true

	if not bullet.hit.is_connected(_on_bullet_hit):
		bullet.hit.connect(_on_bullet_hit)
	attack_finished.emit(self, 1)
	_end_active()


func _on_bullet_hit(hit_pos: Vector2, hit_dir: Vector2, hit_damage_type: int, body: Node2D):
	hit_landed.emit(hit_pos, hit_dir, hit_damage_type, body)
