class_name EnemyConfig
extends Resource

@export var display_name: String = "敌人"
@export var hp_min: float = 50.0
@export var hp_max: float = 150.0
@export var speed: float = 50.0
@export var damage: float = 15.0
@export var innate_type: int = 0
@export var defenses: Dictionary = {
	"puncture_defense": 0.0,
	"slash_defense": 0.0,
	"smash_defense": 0.0,
	"fire_defense": 0.0,
}
@export var color: Color = Color(0.9, 0.2, 0.2)
@export var scene_path: String = "res://scenes/battle/test_enemy.tscn"
