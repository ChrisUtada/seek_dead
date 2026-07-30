class_name PlayerConfig
extends Resource

@export var display_name: String = "玩家"
@export var max_hp: float = 200.0
@export var max_energy: float = 100.0
@export var max_stamina: float = 100.0
@export var walk_speed: float = 200.0
@export var body_color: Color = Color(0.3, 0.6, 1.0)
@export var eye_color: Color = Color(1, 1, 1)

# 初始武器（由 .tres 配置，null 则使用兜底默认）
@export var starting_weapon_main: WeaponData
@export var starting_weapon_offhand: WeaponData
