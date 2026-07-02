class_name PlayerController
extends Damageable

const _WeaponComp = preload("res://scripts/components/weapon_component.gd")
const _MoverComp = preload("res://scripts/components/movement_component.gd")

signal player_damaged(amount: float, current_hp: float, max_hp: float)

enum PlayerState { IDLE, WALK, ATTACK, DODGE, SPRINT, HURT, DEAD }

@onready var state: StateComponent = $StateComponent
@onready var weapon: WeaponComponent = $WeaponComponent
@onready var mover: MovementComponent = $MovementComponent
@onready var dodge: DodgeComponent = $DodgeComponent
@onready var sprint: SprintComponent = $SprintComponent
@onready var ammo: AmmoSystem = $AmmoSystem
@onready var skill_manager: SkillManager = $SkillManager
@onready var _sprite: Node = $Sprite2D

@export var config: PlayerConfig

var walk_speed: float = 200.0
var _base_walk_speed: float = 200.0
var _flash_timer: float = 0.0
var _state: PlayerState = PlayerState.IDLE
var _hurt_timer: float = 0.0

var equipment_manager: EquipmentManager
var equipment_inventory: EquipmentInventory
var escape_skill: EscapeSkill

var _debug_k_held: bool = false


func _ready():
	GameManager.register_player(self)
	EntityRegistry.register_player(self)
	add_to_group("players")
	if config:
		walk_speed = config.walk_speed
		_base_walk_speed = config.walk_speed
		state.max_hp = config.max_hp
		state.hp = config.max_hp
		state.max_energy = config.max_energy
		state.energy = config.max_energy
		state.max_stamina = config.max_stamina
		state.stamina = config.max_stamina
		mover.speed = config.walk_speed
	_generate_placeholder_texture()
	state.died.connect(_on_died)
	state.meltdown_triggered.connect(_on_meltdown)
	state.meltdown_ended.connect(_on_meltdown_end)
	weapon.weapon_changed.connect(_on_weapon_changed)
	dodge.dodge_finished.connect(_on_dodge_finished)
	sprint.sprint_finished.connect(_on_sprint_finished)
	_init_equipment()
	_init_escape_skill()


# ===================== State Machine =====================

func _change_state(new_state: PlayerState):
	if _state == new_state or _state == PlayerState.DEAD:
		return
	_exit_state(_state)
	_state = new_state
	_enter_state(_state)


func _enter_state(s: PlayerState):
	match s:
		PlayerState.ATTACK:
			weapon.attack()
		PlayerState.DODGE:
			if dodge.can_dodge():
				var dir = _get_input_direction()
				dodge.try_dodge(dir if dir != Vector2.ZERO else Vector2.DOWN)
		PlayerState.SPRINT:
			sprint.try_start_sprint()
		PlayerState.HURT:
			_hurt_timer = 0.25
		PlayerState.DEAD:
			set_physics_process(false)
			mover.direction = Vector2.ZERO
			GameManager.game_over()


func _exit_state(s: PlayerState):
	match s:
		PlayerState.SPRINT:
			if sprint.is_sprinting:
				sprint.stop_sprint()


func _on_dodge_finished():
	if _state == PlayerState.DODGE:
		_change_state(PlayerState.IDLE if _get_input_direction() == Vector2.ZERO else PlayerState.WALK)
	EventManager.dodge_performed.emit()


func _on_sprint_finished():
	if _state == PlayerState.SPRINT:
		_change_state(PlayerState.IDLE if _get_input_direction() == Vector2.ZERO else PlayerState.WALK)


# ===================== Input =====================

func _cancel_escape_channel():
	if escape_skill and escape_skill.get("_is_channeling"):
		escape_skill._cancel_channel()


func _unhandled_input(event: InputEvent):
	if event.is_action_type() and event.is_pressed():
		_cancel_escape_channel()
	match _state:
		PlayerState.DEAD, PlayerState.HURT, PlayerState.DODGE:
			return
		PlayerState.ATTACK:
			if event.is_action_pressed("dodge") and dodge.can_dodge():
				_change_state(PlayerState.DODGE)
			return
		PlayerState.SPRINT:
			if event.is_action_pressed("dodge") and dodge.can_dodge():
				_change_state(PlayerState.DODGE)
				return
			if event.is_action_pressed("attack") and weapon.can_attack():
				_change_state(PlayerState.ATTACK)
				return

	if event.is_action_pressed("attack") and weapon.can_attack():
		_change_state(PlayerState.ATTACK)
		return
	if event.is_action_pressed("dodge") and dodge.can_dodge():
		_change_state(PlayerState.DODGE)
		return
	if event.is_action_pressed("sprint"):
		if _state != PlayerState.SPRINT:
			_change_state(PlayerState.SPRINT)
		return
	if event.is_action_released("sprint") and _state == PlayerState.SPRINT:
		_change_state(PlayerState.IDLE if _get_input_direction() == Vector2.ZERO else PlayerState.WALK)
		return
	if event.is_action_pressed("reload"):
		ammo.start_reload()
		return
	if event.is_action_pressed("escape_skill") and escape_skill:
		escape_skill.use(self)
		return
	for i in range(2):
		if event.is_action_pressed("skill_%d" % (i + 1)):
			skill_manager.use_skill(i, self)
			return


# ===================== Physics =====================

func _physics_process(delta: float):
	if escape_skill:
		escape_skill.tick(delta)
	match _state:
		PlayerState.IDLE, PlayerState.WALK, PlayerState.SPRINT:
			_process_movement(delta)
			if _state != PlayerState.SPRINT:
				var moving = _get_input_direction() != Vector2.ZERO
				if moving and _state == PlayerState.IDLE:
					_change_state(PlayerState.WALK)
				elif not moving and _state == PlayerState.WALK:
					_change_state(PlayerState.IDLE)
		PlayerState.ATTACK:
			_process_movement(delta)
			if _attack_finished():
				_change_state(PlayerState.IDLE if _get_input_direction() == Vector2.ZERO else PlayerState.WALK)
		PlayerState.HURT:
			_hurt_timer -= delta
			if _hurt_timer <= 0:
				_change_state(PlayerState.IDLE if _get_input_direction() == Vector2.ZERO else PlayerState.WALK)
		PlayerState.DODGE, PlayerState.DEAD:
			pass


func _attack_finished() -> bool:
		var node = weapon.get_active_weapon_node()
		return node == null or not node.is_attacking


func _process_movement(delta: float):
	if _flash_timer > 0 and _sprite and _sprite is CanvasItem:
		var spr = _sprite as CanvasItem
		_flash_timer -= delta
		spr.modulate = Color(1, 1 - _flash_timer * 10, 1 - _flash_timer * 10)
		if _flash_timer <= 0:
			spr.modulate = Color(1, 1, 1)

	mover.direction = _get_input_direction()
	mover.speed = walk_speed

	var aim_dir = (get_global_mouse_position() - global_position).normalized()
	weapon.set_aim_direction(aim_dir)
	if _sprite and "flip_h" in _sprite:
		_sprite.flip_h = aim_dir.x < 0

	# Q/E 切换主副手
	if Input.is_action_just_pressed("weapon_slot_1"):
		weapon.switch_active_hand(0)  # 主手
	if Input.is_action_just_pressed("weapon_slot_2"):
		weapon.switch_active_hand(1)  # 副手

	if Input.is_key_pressed(KEY_K):
		if not _debug_k_held:
			_debug_k_held = true
			_debug_spawn_equipment()
	else:
		_debug_k_held = false


# ===================== Lifecycle =====================

func _on_weapon_changed(w: WeaponNode, _hand: int = 0):
	if w.weapon_data and w.weapon_data.weapon_type == WeaponData.WeaponType.RANGED and w.weapon_data.max_ammo > 0:
		ammo.switch_to_weapon(w.weapon_data.weapon_name, w.weapon_data.max_ammo)


func _on_meltdown():
	AudioManager.play_sfx(AudioManager.SfxType.PLAYER_MELTDOWN)
	walk_speed = _base_walk_speed * 0.7
	if _sprite and _sprite is CanvasItem:
		(_sprite as CanvasItem).modulate = Color(1, 0.7, 0.2)


func _on_meltdown_end():
	walk_speed = _base_walk_speed
	if _sprite and _sprite is CanvasItem:
		(_sprite as CanvasItem).modulate = Color(1, 1, 1)


func _init_equipment():
	equipment_manager = EquipmentManager.new()
	equipment_manager.name = "EquipmentManager"
	add_child(equipment_manager)
	equipment_inventory = EquipmentInventory.new()
	equipment_inventory.name = "EquipmentInventory"
	add_child(equipment_inventory)
	# 延迟装备初始武器，确保 WeaponComponent._ready() 已完成扫描
	call_deferred("_equip_starting_weapon")


func _equip_starting_weapon():
	# 主手：铁剑（近战）
	var starting_weapon = EquipmentBase.new()
	starting_weapon.equipment_name = "铁剑"
	starting_weapon.slot = EquipmentEnums.EquipmentSlot.WEAPON_MAIN
	starting_weapon.rarity = EquipmentEnums.Rarity.COMMON
	starting_weapon.weapon_data = preload("res://resources/weapon_templates/iron_sword.tres").duplicate(true)
	equipment_manager.equip(starting_weapon)

	# 副手：手枪（远程）
	var offhand_weapon = EquipmentBase.new()
	offhand_weapon.equipment_name = "手枪"
	offhand_weapon.slot = EquipmentEnums.EquipmentSlot.WEAPON_OFFHAND
	offhand_weapon.rarity = EquipmentEnums.Rarity.COMMON
	offhand_weapon.weapon_data = preload("res://resources/weapon_templates/pistol.tres").duplicate(true)
	equipment_manager.equip(offhand_weapon)


func _init_escape_skill():
	escape_skill = preload("res://resources/skills/escape_skill.tres").duplicate(true)


func _debug_spawn_equipment():
	var helm = EquipmentBase.new()
	helm.equipment_name = "调试头盔"
	helm.slot = EquipmentEnums.EquipmentSlot.HELMET
	helm.rarity = EquipmentEnums.Rarity.RARE
	var aff = AffixDatabase.get_affix("活力")
	if not aff:
		aff = Affix.new()
		aff.affix_name = "活力(fallback)"
		var mod = StatModifier.new()
		mod.target_stat = EquipmentEnums.StatTarget.MAX_HP
		mod.modifier_type = EquipmentEnums.ModifierType.ADD
		mod.value = 50.0
		aff.stat_modifiers.append(mod)
	var trigger = TriggerEffect.new()
	trigger.trigger_event = EquipmentEnums.TriggerEvent.ON_HIT
	trigger.effect_action = EquipmentEnums.EffectAction.HEAL
	trigger.chance = 0.25
	trigger.param_value = 10.0
	aff.trigger_effects.append(trigger)
	var burn = AffixDatabase.get_affix("灼烧")
	if burn:
		helm.affixes.append(burn)
	helm.affixes.append(aff)
	if equipment_inventory.add_item(helm):
		print("[装备调试] 调试头盔: " + aff.affix_name + " + 灼烧(命中25%爆炸100火伤)")
	else:
		print("[装备调试] 背包已满")
	equipment_manager.equip(helm)
	print("[装备调试] HP加成前: %d / %d" % [state.hp, state.max_hp])
	state.hp = state.max_hp
	print("[装备调试] HP加成后: %d / %d" % [state.hp, state.max_hp])


func _generate_placeholder_texture():
	if not _sprite or _sprite is AnimatedSprite2D:
		return
	var body = config.body_color if config else Color(0.3, 0.6, 1.0)
	var eye = config.eye_color if config else Color(1, 1, 1)
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for x in range(32):
		for y in range(32):
			var dx = x - 16
			var dy = y - 16
			var dist = sqrt(dx * dx + dy * dy)
			if dist < 12:
				image.set_pixel(x, y, body)
			if dist < 8 and dx > 6 and abs(dy) < 4:
				image.set_pixel(x, y, eye)
			if dist < 6 and dx > 2 and abs(dy) < 2:
				image.set_pixel(x, y, Color(0, 0, 0))
	var spr = _sprite as Sprite2D
	spr.texture = ImageTexture.create_from_image(image)
	spr.centered = true


func take_damage(amount: float, damage_type: int) -> Dictionary:
	if is_invincible:
		return {"final_damage": 0.0, "is_critical": false, "is_weakness": false, "hit_result": -1, "breakdown": {}}
	var executor = equipment_manager.get_node_or_null("EffectExecutor") as EffectExecutor
	if executor and executor.has_shield():
		amount = executor.absorb_damage(amount)
		if amount <= 0:
			return {"final_damage": 0.0, "is_critical": false, "is_weakness": false, "hit_result": -1, "breakdown": {}}
	var result = state.take_damage(amount, damage_type)
	if _state != PlayerState.DEAD:
		_change_state(PlayerState.HURT)
	_flash_timer = 0.1
	EventManager.damage_dealt.emit(null, self, result.final_damage, damage_type)
	player_damaged.emit(result.final_damage, state.hp, state.max_hp)
	_shake_camera(Vector2(2.0, 1.5) if result.is_critical else Vector2(1.0, 0.8), 0.15)
	return result


func _shake_camera(intensity: Vector2, duration: float):
	var cam = $Camera2D
	if not cam:
		return
	var original = cam.position
	var tween = create_tween()
	tween.tween_method(_apply_shake.bind(cam, original, intensity), 0.0, 1.0, duration).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func(): cam.position = original)


func _apply_shake(_t: float, cam: Camera2D, original: Vector2, intensity: Vector2):
	cam.position = original + Vector2(randf_range(-intensity.x, intensity.x), randf_range(-intensity.y, intensity.y))


func knockback(kb_velocity: Vector2):
	mover.push(kb_velocity, 0.12)


func _on_died():
	_change_state(PlayerState.DEAD)
	AudioManager.play_sfx(AudioManager.SfxType.PLAYER_HURT)


func _get_input_direction() -> Vector2:
	var dir = Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		dir.x -= 1
	if Input.is_action_pressed("move_right"):
		dir.x += 1
	if Input.is_action_pressed("move_forward"):
		dir.y -= 1
	if Input.is_action_pressed("move_backward"):
		dir.y += 1
	return dir.normalized()
