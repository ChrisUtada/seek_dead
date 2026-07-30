class_name RoomConfig
extends Resource

enum RoomSize { SMALL, MEDIUM, LARGE, BOSS }

@export var scene: PackedScene
@export var room_name: String = ""
@export var room_size: RoomSize = RoomSize.SMALL

@export_group("Enemies")
@export var min_enemies: int = 3
@export var max_enemies: int = 6
@export var enemy_pool: Array[PackedScene] = []

@export_group("Elite")
@export var has_elite: bool = false
@export var elite_pool: Array[PackedScene] = []

@export_group("Boss")
@export var boss_count: int = 0
@export var boss_pool: Array[PackedScene] = []

@export_group("Waves")
@export var waves: Array[WaveConfig] = []

@export_group("Rewards")
@export var reward_count: int = 1
@export var reward_quality_bonus: float = 0.0
