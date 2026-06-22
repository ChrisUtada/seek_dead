extends CharacterBody2D

@onready var state: StateComponent = $StateComponent
var _flash_timer: float = 0.0

func _ready():
	var hp_val = randi_range(50, 150)
	state.max_hp = hp_val
	state.hp = hp_val
	state.innate_type = randi_range(0, DamageSystem.DamageType.size() - 1)
	state.defenses = {
		"puncture_defense": randf_range(0.0, 0.3),
		"slash_defense": randf_range(0.0, 0.3),
		"smash_defense": randf_range(0.0, 0.3),
		"fire_defense": randf_range(0.0, 0.3),
	}
	state.died.connect(_on_died)

func take_damage(amount: float, damage_type: int):
	var result = state.take_damage(amount, damage_type)
	var hit_str = DamageSystem.hit_result_to_string(result.hit_result)
	var prefix = "[%s]" % hit_str if hit_str else ""
	print("敌人受伤: %s %.0f (剩余HP: %.0f/%.0f)" % [prefix, result.final_damage, state.hp, state.max_hp])
	modulate = Color(1, 0.5, 0.5)
	_flash_timer = 0.1
	return result

func _on_died():
	print("敌人死亡!")
	queue_free()

func _physics_process(delta):
	if _flash_timer > 0:
		_flash_timer -= delta
		if _flash_timer <= 0:
			modulate = Color(1, 1, 1)

	var target = _find_nearest_player()
	if target and global_position.distance_to(target.global_position) > 30:
		var dir = global_position.direction_to(target.global_position)
		velocity = dir * 50.0
		move_and_slide()

func _find_nearest_player():
	var players = get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return null
	return players[0]
