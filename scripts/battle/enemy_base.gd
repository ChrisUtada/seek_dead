extends CharacterBody2D

signal died()

@onready var state: StateComponent = $StateComponent
@onready var effects: StatusEffectComponent = $StatusEffectComponent
@onready var mover: MovementComponent = $MovementComponent
@onready var _sprite: Sprite2D = $Sprite2D

var _flash_timer: float = 0.0

func _enemy_ready():
	effects.tick_damage.connect(_on_tick_damage)
	effects.effect_applied.connect(_on_effect_applied)
	effects.effect_expired.connect(_on_effect_expired)
	state.died.connect(_on_died)
	EntityRegistry.register_enemy(self)
	add_to_group("enemies")
	_add_hp_bar()

func _add_hp_bar():
	var bar = load("res://scripts/ui/enemy_hp_bar.gd").new()
	add_child(bar)

func _generate_texture(color: Color, size: int = 32):
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var darker = Color(color.r * 0.6, color.g * 0.6, color.b * 0.6)
	var half = size / 2
	for x in range(size):
		for y in range(size):
			var dx = x - half
			var dy = y - half
			if abs(dx) < half * 0.75 and abs(dy) < half * 0.75:
				img.set_pixel(x, y, color)
			if abs(dx) < half * 0.25 and abs(dy) < half * 0.25:
				img.set_pixel(x, y, darker)
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.centered = true

func take_damage(amount: float, damage_type: int):
	var result = state.take_damage(amount, damage_type)
	_flash_timer = 0.1
	EventManager.damage_dealt.emit(null, self, result.final_damage, damage_type)
	return result

func apply_status(effect_type: int, damage: float, duration: float):
	effects.apply(effect_type, damage, duration)

func _on_tick_damage(dmg: float, dmg_type: int):
	take_damage(dmg, dmg_type)

func _on_effect_applied(_et: int, _name: String):
	_tint_from_effects()

func _on_effect_expired(_et: int, _name: String):
	_tint_from_effects()

func _tint_from_effects():
	if _flash_timer <= 0:
		_sprite.modulate = effects.get_last_color() if effects.has_any() else Color(1, 1, 1)

func _on_died():
	EntityRegistry.unregister_enemy(self)
	queue_free()

func _enemy_physics(delta):
	if _flash_timer > 0:
		_flash_timer -= delta
		if _flash_timer <= 0:
			_tint_from_effects()

func get_hp_ratio() -> float:
	return state.hp / state.max_hp if state.max_hp > 0 else 0.0
