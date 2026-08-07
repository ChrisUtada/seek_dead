class_name BattleState
extends RefCounted
# 只读状态快照（P1 抽取自 duel_controller.gd）
# 设计：controller.state 每次访问返回一份最新快照；battle_hud 只从中读数据，
# 不再直读 controller 的私有字段（grid/meta/enemy_*/charm_*/player_* 等）。
# 逻辑/动作仍走 controller 的语义方法（_cat_max/_on_*_pressed/_roll_* 等，属 P2 信号范畴）。
# 详见 docs/代码审查与优化建议.md「问题 2 / 阶段 P1」。

var grid: Array = []
var grid_elem: Array = []
var reward_choices: Array = []
var room_index: int = 0
var REELS: int = 3
var meta: Dictionary = {}
var gold: int = 0
var enemy_intent: Dictionary = {}
var enemy_element: String = "none"
var selected_loadout: Array = []
var run_symbol_bonus: Dictionary = {}
var ROWS: int = 1
var ROOMS: Array = []
var LOADOUT_MIN: int = 1
var WEAPON_POOL: Array = []
var UNCAPPED: int = -1
var selected_skills: Array = []
var selected_charms: Array = []
var run_shield_next: int = 0
var run_power_bonus: int = 0
var pool: Array = []
var loadout_names: Array = []
var in_loadout: bool = false
var game_state: String = "playing"          # playing | won | lost | cleared（与 controller.game_state 同步）
var enemy_status: Dictionary = {}
var enemy_armor_max: int = 0
var consumable_slots: Array = []
var CONSUMABLE_CAP: int = 4
# 净化完全走消耗品（净化药剂·charges 用尽即移出腰带），battle_state 不再缓存 purify_* 字段
var charm_room_shield: int = 0
var charm_power_bonus: int = 0
var charm_shield_trickle: int = 0
var charm_heal_trickle: int = 0
var charm_interf_resist: int = 0
var charm_damage_mult: float = 1.0
var turn_count: int = 1
var SKILL_POOL: Array = []
var skill_max: int = 1
var shop_offers: Array = []
var selected_consumables: Array = []
var reward_is_boss: bool = false
var player_shield: int = 0
var player_hp_max: int = 100
var player_hp: int = 100
var loadout_max: int = 2
var ITEM_POOL: Array = []
var enemy_name: String = "敌人"
var enemy_hp_max: int = 120
var enemy_hp: int = 120
var enemy_armor: int = 0
var charm_max: int = 1
