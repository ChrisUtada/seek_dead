extends Node

## 全局事件管理器
## 使用 Godot Signals 机制，提供解耦的事件通信

signal damage_dealt(attacker: Node2D, defender: Node2D, amount: float, damage_type: int)
signal player_died(player: Node2D)
signal enemy_died(enemy: Node2D)
signal skill_used(skill_data: Dictionary)
signal scene_changed(scene_name: String)
signal item_picked_up(item_data: Dictionary)
signal hp_changed(target: Node2D, current_hp: float, max_hp: float)
signal energy_changed(target: Node2D, current_energy: float, max_energy: float)
signal stamina_changed(target: Node2D, current_stamina: float, max_stamina: float)

func _ready():
	print("[EventManager] Initialized")
