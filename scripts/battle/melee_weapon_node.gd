class_name MeleeWeaponNode
extends WeaponNode

@onready var _hitbox: Hitbox = $Hitbox

var _hit_count: int = 0


func _ready():
	_hitbox.set_deferred("monitoring", false)
	_hitbox.set_deferred("monitorable", false)
	_hitbox.lifespan = 0
	_hitbox.hit_landed.connect(_on_hitbox_landed)


func attack():
	if not can_attack():
		return
	_start_attack()
	flash_range()
	swing()
	AudioManager.play_sfx(AudioManager.SfxType.PLAYER_MELEE)

	var cs = _hitbox.get_child(0) as CollisionShape2D
	if cs and cs.shape:
		var circle = cs.shape as CircleShape2D
		circle.radius = stats.attack_range
	_hitbox.damage = stats.damage
	_hitbox.damage_type = stats.damage_type
	_hitbox.shooter = shooter
	_hitbox.knockback_force = 120.0
	_hitbox.status_effect_type = stats.status_effect_type
	_hitbox.status_effect_damage = stats.status_effect_damage
	_hitbox.status_effect_duration = stats.status_effect_duration
	_hitbox.reset()
	_hitbox.global_position = shooter.global_position
	_hitbox.monitoring = true
	_hitbox.monitorable = true


func _end_active():
	_hitbox.monitoring = false
	_hitbox.monitorable = false
	super()


func _on_hitbox_landed(target: Node2D):
	_hit_count += 1
	hit_landed.emit(target.global_position, aim_direction, stats.damage_type, target)
