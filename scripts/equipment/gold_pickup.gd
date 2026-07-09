class_name GoldPickup
extends PickupBase

var gold_value: int = 15


func setup(value: int = 15):
	gold_value = value
	_init_pickup()


func _build_visual():
	super._build_visual()
	_add_orb(Color(1, 0.85, 0.3, 0.9), Vector2(14, 14), Vector2(-7, -7))
	_add_label("$", Vector2(14, 14), Vector2(-7, -8), 14)


# 金币无需校验 players 组，只要 GameManager 存在即可入账。
func _player_valid(_target: Node2D) -> bool:
	return has_node("/root/GameManager")


func _apply_effect(_target: Node2D) -> bool:
	GameManager.run_gold += gold_value
	Debug.log("[金币拾取] +%d (当前局内:%d)" % [gold_value, GameManager.run_gold])
	return true
