class_name RoomConfig
extends Resource

@export var scene: PackedScene
@export var room_name: String = ""
@export var min_enemies: int = 3
@export var max_enemies: int = 6
@export var enemy_pool: Array[PackedScene] = []
