extends BossGimmick

const ICON := "💔"   # 下一房预告横幅的机制图标（battle_hud 经 get_script_constant_map 读取）
const P2_INTENTS := [
	preload("res://resources/intents/attack.tres"),
	preload("res://resources/intents/heavy.tres"),
]
const P3_INTENTS := [
	preload("res://resources/intents/attack.tres"),
	preload("res://resources/intents/heavy.tres"),
	preload("res://resources/intents/jam.tres"),
]

# 幕三 BOSS·碎裂魔王「人格裂变」（split_ego，2026-08-10 定稿，草案原型 §10 DID）：
# P1 愤怒人格（HP 100%→66%）：火属性（弱冰），攻击 ×anger_atk_mult + 意图 attack 40/heavy 60（重击偏置）。
# P2 恐惧人格（HP<66% 一次性）：切冰属性（弱火）+ 每回合叠甲 fear_armor_step（上限 fear_armor_cap）+
#   攻击 ×fear_atk_mult + 意图 attack 60/heavy 40——顽固防御（破甲只管当回合，下回合又叠）。
# P3 悲伤人格（HP<33% 一次性）：切毒属性（弱光）+ 每回合挂毒 grief_dot_per_turn 层（毒伤 = 层数 × grief_dot_base，
#   走 enemy_deal_damage 闸口护盾可挡、层数不衰减、清净药剂可清零——acid_bomb 玩家侧 DoT 支点先例）+
#   意图 attack 50/heavy 30/jam 20（jam 可净化）。
# 与躁怒元素使（双元素切换）错位：三元素三阶段人格切换（元素应变终极形态）+ 每人格专属机制（高攻/叠盾/挂毒）。
# T24 参数化：phase2_hp_ratio/phase3_hp_ratio/anger_atk_mult/fear_atk_mult/fear_armor_step/fear_armor_cap/grief_dot_per_turn/grief_dot_base。
# 单侧性纪律：只操作本 BOSS 的 enemy_hp/enemy_element/enemy_armor/enemy_intent/boss_atk_mult + 玩家侧毒层（惩罚语义，acid 先例）。

var _phase2_hp_ratio := 0.66
var _phase3_hp_ratio := 0.33
var _anger_atk_mult := 1.15
var _fear_atk_mult := 0.9
var _fear_armor_step := 6
var _fear_armor_cap := 45
var _grief_dot_per_turn := 2
var _grief_dot_base := 1
var _phase2 := false
var _phase3 := false
var _p2_room_data: RoomData
var _p3_room_data: RoomData

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.ROOMS[ctrl.room_index].gimmick_params if (ctrl.room_index >= 0 and ctrl.room_index < ctrl.ROOMS.size()) else {}
	_phase2_hp_ratio = float(p.get("phase2_hp_ratio", 0.66))
	_phase3_hp_ratio = float(p.get("phase3_hp_ratio", 0.33))
	_anger_atk_mult = float(p.get("anger_atk_mult", 1.15))
	_fear_atk_mult = float(p.get("fear_atk_mult", 0.9))
	_fear_armor_step = int(p.get("fear_armor_step", 6))
	_fear_armor_cap = int(p.get("fear_armor_cap", 45))
	_grief_dot_per_turn = int(p.get("grief_dot_per_turn", 2))
	_grief_dot_base = int(p.get("grief_dot_base", 1))
	_phase2 = false
	_phase3 = false
	_p2_room_data = RoomData.new()
	_p2_room_data.kind = "boss"
	_p2_room_data.intents = P2_INTENTS
	_p3_room_data = RoomData.new()
	_p3_room_data.kind = "boss"
	_p3_room_data.intents = P3_INTENTS
	ctrl.boss_atk_mult = _anger_atk_mult
	ctrl.hud._log("💔 碎裂魔王：愤怒人格——攻击 ×%s（HP<%d%% 恐惧人格：切冰叠甲；HP<%d%% 悲伤人格：切毒挂毒）" % [_anger_atk_mult, int(_phase2_hp_ratio * 100), int(_phase3_hp_ratio * 100)])
	ctrl.hud._popup("💔 愤怒人格：烈焰暴怒！", Palette.POP_STATUS, ctrl.hud._enemy_sprite_anchor())

func on_turn_begin(ctrl) -> void:
	# 人格倍率/意图
	if _phase3:
		ctrl.boss_atk_mult = 1.0
		ctrl.enemy_intent = ctrl.status_system.roll_intent(_p3_room_data)
		# 悲伤人格：先结算旧毒（毒伤 + 护盾闸口），再挂新层（acid_bomb 玩家侧 DoT 支点先例）
		var stacks: int = int(ctrl.player_status.get("poison", 0))
		if stacks > 0:
			var dot_dmg: int = stacks * _grief_dot_base
			ctrl.combat.enemy_deal_damage(dot_dmg)
			ctrl.hud._log("☣ 悲伤侵蚀：%d 层毒伤 -%d（护盾可挡）" % [stacks, dot_dmg])
		var add: int = maxi(0, _grief_dot_per_turn - int(ctrl.charm_dot_reduce))   # 蚀毒壁垒护符：挂毒量 -N/回合
		ctrl.player_status["poison"] = int(ctrl.player_status.get("poison", 0)) + add
		ctrl.hud._log("☣ 悲伤人格：玩家中毒 +%d 层（%d 层）" % [add, int(ctrl.player_status.get("poison", 0))])
		return
	if _phase2:
		ctrl.boss_atk_mult = _fear_atk_mult
		ctrl.enemy_intent = ctrl.status_system.roll_intent(_p2_room_data)
		# 恐惧人格：每回合叠甲（上限 fear_armor_cap）
		if ctrl.enemy_armor < _fear_armor_cap:
			ctrl.enemy_armor = mini(_fear_armor_cap, ctrl.enemy_armor + _fear_armor_step)
			ctrl.hud._log("❄️ 恐惧人格：寒冰壁垒 +%d（护甲 %d/%d）" % [_fear_armor_step, ctrl.enemy_armor, _fear_armor_cap])
			ctrl.hud._refresh_meta()
		return
	ctrl.boss_atk_mult = _anger_atk_mult

func on_damaged(ctrl, _dmg: int) -> void:
	if not _phase2 and _phase2_hp_ratio > 0.0 and ctrl.enemy_hp <= int(float(ctrl.enemy_hp_max) * _phase2_hp_ratio):
		_phase2 = true
		ctrl.enemy_element = "ice"
		ctrl.hud._update_enemy_element()
		ctrl.boss_atk_mult = _fear_atk_mult
		ctrl.enemy_intent = ctrl.status_system.roll_intent(_p2_room_data)
		ctrl.hud._log("❄️ 恐惧人格：寒冰壁垒层层加固——属性→冰（弱火），攻击 ×%s，每回合叠甲 +%d（上限 %d）" % [_fear_atk_mult, _fear_armor_step, _fear_armor_cap])
		ctrl.hud._popup("❄️ 恐惧人格！", Palette.POP_STATUS, ctrl.hud._enemy_sprite_anchor())
		ctrl.hud._refresh_meta()
		return
	if _phase2 and not _phase3 and _phase3_hp_ratio > 0.0 and ctrl.enemy_hp <= int(float(ctrl.enemy_hp_max) * _phase3_hp_ratio):
		_phase3 = true
		ctrl.enemy_element = "poison"
		ctrl.hud._update_enemy_element()
		ctrl.boss_atk_mult = 1.0
		ctrl.enemy_intent = ctrl.status_system.roll_intent(_p3_room_data)
		ctrl.hud._log("☣ 悲伤人格：毒泪弥漫——属性→毒（弱光），每回合挂毒 %d 层（清净药剂可解）" % _grief_dot_per_turn)
		ctrl.hud._popup("☣ 悲伤人格！", Palette.POP_STATUS, ctrl.hud._enemy_sprite_anchor())
		ctrl.hud._refresh_meta()
