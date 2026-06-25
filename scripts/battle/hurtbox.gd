class_name Hurtbox
extends Area2D

func _ready():
	collision_layer = CollisionSystem.bit(CollisionSystem.LAYER_HURTBOX)
	collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_HITBOX)
	area_entered.connect(_on_hitbox_entered)

func _on_hitbox_entered(hitbox: Area2D):
	var hb = hitbox as Hitbox
	if not hb or hb.process_mode == PROCESS_MODE_DISABLED:
		return
	hb.apply_to(self)
