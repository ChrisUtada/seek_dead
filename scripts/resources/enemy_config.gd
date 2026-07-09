class_name EnemyConfig
extends Resource

enum EnemyTier { NORMAL, ELITE_STAT, ELITE_MECHANIC, BOSS }

@export var tier: EnemyTier = EnemyTier.NORMAL
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
@export var stat_multiplier: float = 1.5
@export var color: Color = Color(0.9, 0.2, 0.2)
@export var scene_path: String = ""
@export var bullet_data: BulletData
@export var behavior_types: Array[AIComponent.BehaviorType]
@export var behavior_durations: Array[float]
@export var attack_range: float = 50.0
@export var attack_cooldown: float = 1.5
@export var loot_table: LootTable
@export var drop_heal: int = 0
@export var drop_heal_chance: float = 0.0
@export var drop_equip_chance: float = 0.0
@export var drop_equip_quality_bonus: float = 0.0
@export var drop_gold: int = 0
