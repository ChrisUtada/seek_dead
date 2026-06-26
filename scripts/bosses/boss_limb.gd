class_name BossLimb
extends Node2D

signal limb_destroyed(limb: BossLimb)

@export var max_hp: float = 120.0
@export var element_type: int = 0
@export var limb_color: Color = Color.WHITE

var hp: float
var is_destroyed: bool = false

@onready var _sprite: Sprite2D = $Sprite2D
@onready var hurtbox: Area2D = $Hurtbox


func _ready():
	hp = max_hp
	_sprite.modulate = limb_color
	hurtbox.collision_layer = CollisionSystem.bit(CollisionSystem.LAYER_HURTBOX)
	hurtbox.collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_HITBOX)
	hurtbox.area_entered.connect(_on_hitbox_entered)


func _on_hitbox_entered(hit_area: Area2D):
	var hb = hit_area as Hitbox
	if not hb or not hb.shooter:
		return
	# 只接受玩家伤害（防止友军误伤）
	if not hb.shooter is PlayerController:
		return
	_take_damage(hb.damage)


func _take_damage(amount: float):
	if is_destroyed:
		return
	hp -= amount
	if hp <= 0:
		is_destroyed = true
		_sprite.modulate = Color(0.3, 0.3, 0.3)
		hurtbox.set_deferred("monitoring", false)
		limb_destroyed.emit(self)
