class_name HealthPickup
extends PickupBase

var heal_amount: int = 15


func setup(amount: int = 15):
	heal_amount = amount
	_init_pickup()


func _build_visual():
	super._build_visual()
	_add_orb(Color(1, 0.2, 0.2, 0.9), Vector2(14, 14), Vector2(-7, -7))
	_add_border(Color(1, 1, 1, 0.3), Vector2(18, 18), Vector2(-9, -9))
	_add_label("+", Vector2(14, 14), Vector2(-7, -8), 14)


func _apply_effect(target: Node2D) -> bool:
	var state := target.get_node_or_null("StateComponent") as StateComponent
	if not state:
		return false
	var old := state.hp
	state.hp = min(state.hp + heal_amount, state.max_hp)
	var healed := state.hp - old
	Debug.log("[血球拾取] +%d HP" % healed)
	return true
