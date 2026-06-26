class_name WaveConfig
extends Resource

enum Trigger { ON_START, ENEMIES_LEFT, TIMER, BOSS_PHASE }

@export var trigger: Trigger = Trigger.ON_START
@export var trigger_value: float = 0.0
@export var spawn_marker_groups: Array[String] = ["spawn"]
@export var enemy_count: int = 4
@export var delay: float = 0.0
@export var announce: String = ""
