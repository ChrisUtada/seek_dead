class_name BossConfig
extends EnemyConfig

@export var phase_hp_ratios: Array[float] = [0.6, 0.3]

@export var slam_damages: Array[float] = [25.0, 35.0, 50.0]
@export var slam_ranges: Array[float] = [70.0, 80.0, 90.0]

@export var charge_speeds: Array[float] = [350.0, 400.0, 500.0]
@export var charge_durations: Array[float] = [0.4, 0.5, 0.6]

@export var burst_counts: Array[int] = [2, 3, 4]
@export var burst_damages: Array[float] = [15.0, 20.0, 25.0]

@export var attack_cooldowns: Array[float] = [1.2, 0.9, 0.6]
@export var bullet_speed: float = 400.0

@export var stun_duration: float = 3.0
