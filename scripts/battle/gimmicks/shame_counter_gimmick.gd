extends BossGimmick

const ICON := "⚖"   # 下一房预告横幅的机制图标（battle_hud 经 get_script_constant_map 读取）
const RoomData = preload("res://scripts/battle/room_data.gd")
const P2_INTENTS := [
	preload("res://resources/intents/attack.tres"),
	preload("res://resources/intents/heavy.tres"),
	preload("res://resources/intents/jam.tres"),
]
const P3_INTENTS := [
	preload("res://resources/intents/attack.tres"),
	preload("res://resources/intents/heavy.tres"),
]

# 幕三 BOSS·耻辱审判官「罪业清算」（shame_counter，2026-08-10 定稿，草案原型 §11 毒性耻感）：
# P1 罪业记录（HP 100%→66%）：玩家每回合受击（player_hp+shield 下降）或空转（enemy_hp 未变）→ 罪业 +1
#   （房内不衰减、跨阶段累计）——敌方攻击 ×（1 + 罪业 × sin_atk_per），操作纪律即生存。
# P2 拷问心防（HP<66% 一次性）：当场清空护盾 + 每回合开局剥盾（护符/增益盾无法保留）——纯血量承伤，
#   攻击 ×phase2_atk_mult + 意图 attack 40/heavy 40/jam 20。
# P3 终极审判（HP<33% 一次性）：玩家血量 ≤ max×low_hp_ratio 时本回合敌方伤害额外 ×low_hp_mult——
#   罪业 × 血线双乘区（残血双重清算），意图 attack 50/heavy 50。
# 与无名虚空（装备剥夺）错位：本 BOSS 验收「失误问责」——罪业来自玩家自己的受击/空转，越拖越痛。
# T24 参数化：sin_atk_per/phase2_*/phase3_*/low_hp_ratio/low_hp_mult 读 gimmick_params。
# 单侧性纪律：只操作本 BOSS 的 enemy_hp/enemy_intent/boss_atk_mult + 玩家侧护盾/血量读取（惩罚语义），无跨侧共享。

var _sin_atk_per := 0.08
var _phase2_hp_ratio := 0.66
var _phase2_atk_mult := 0.9
var _phase3_hp_ratio := 0.33
var _phase3_atk_mult := 1.0
var _low_hp_ratio := 0.5
var _low_hp_mult := 2.0
var _sins := 0
var _phase2 := false
var _phase3 := false
var _last_survival := 0.0     # 受击检测基准：player_hp + player_shield（玩家结算后快照）
var _last_enemy_hp := 0.0     # 空转检测基准：玩家结算前 enemy_hp
var _p2_room_data: RoomData
var _p3_room_data: RoomData

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.ROOMS[ctrl.room_index].gimmick_params if (ctrl.room_index >= 0 and ctrl.room_index < ctrl.ROOMS.size()) else {}
	_sin_atk_per = float(p.get("sin_atk_per", 0.08))
	_phase2_hp_ratio = float(p.get("phase2_hp_ratio", 0.66))
	_phase2_atk_mult = float(p.get("phase2_atk_mult", 0.9))
	_phase3_hp_ratio = float(p.get("phase3_hp_ratio", 0.33))
	_phase3_atk_mult = float(p.get("phase3_atk_mult", 1.0))
	_low_hp_ratio = float(p.get("low_hp_ratio", 0.5))
	_low_hp_mult = float(p.get("low_hp_mult", 2.0))
	_sins = 0
	_phase2 = false
	_phase3 = false
	_last_survival = float(ctrl.player_hp + ctrl.player_shield)
	_last_enemy_hp = float(ctrl.enemy_hp)
	_p2_room_data = RoomData.new()
	_p2_room_data.kind = "boss"
	_p2_room_data.intents = P2_INTENTS
	_p3_room_data = RoomData.new()
	_p3_room_data.kind = "boss"
	_p3_room_data.intents = P3_INTENTS
	ctrl.hud._log("⚖ 耻辱审判官：罪业清算——受击/空转记罪 +1（攻击 ×(1+罪业×%s)）；HP<%d%% 拷问心防（剥盾），HP<%d%% 终极审判（血线 ×%s）" % [_sin_atk_per, int(_phase2_hp_ratio * 100), int(_phase3_hp_ratio * 100), _low_hp_mult])

func on_turn_begin(ctrl) -> void:
	# 受击罪：敌人行动后检测（player_hp+shield 较上回合结算后下降 = 本回合受击）
	var survival: float = float(ctrl.player_hp + ctrl.player_shield)
	if survival < _last_survival - 0.5:
		_sins += 1
		ctrl.hud._log("⚖ 罪业+1（受击）：当前罪业 %d——敌方攻击 ×%s" % [_sins, 1.0 + _sins * _sin_atk_per])
	_last_survival = survival
	if _phase2:
		# 拷问心防：每回合开局剥盾（纯血量承伤——护符/增益盾无法保留）
		if ctrl.player_shield > 0:
			ctrl.player_shield = 0
			ctrl.hud._log("⚖ 拷问心防：护盾剥离（本回合 %d 盾被剥夺）" % ctrl.player_shield)
			_last_survival = float(ctrl.player_hp)
	# 罪业乘区 × 阶段基础倍率 ×（P3 血线审判）
	var base_mult: float = _phase3_atk_mult if _phase3 else (_phase2_atk_mult if _phase2 else 1.0)
	ctrl.boss_atk_mult = base_mult * (1.0 + _sins * _sin_atk_per)
	if _phase3 and ctrl.player_hp <= int(float(ctrl.player_hp_max) * _low_hp_ratio):
		ctrl.boss_atk_mult *= _low_hp_mult
		ctrl.hud._log("⚖ 终极审判：血线之下——本回合伤害额外 ×%s！" % _low_hp_mult)
	# 意图
	if _phase3:
		ctrl.enemy_intent = ctrl.status_system.roll_intent(_p3_room_data)
	elif _phase2:
		ctrl.enemy_intent = ctrl.status_system.roll_intent(_p2_room_data)
	_last_enemy_hp = float(ctrl.enemy_hp)   # 空转检测基准：玩家结算前快照

func on_turn_resolved(ctrl) -> void:
	# 空转罪：玩家结算后 enemy_hp 未变化 = 本回合无伤害（空转）
	if float(ctrl.enemy_hp) >= _last_enemy_hp - 0.5:
		_sins += 1
		ctrl.hud._log("⚖ 罪业+1（空转）：当前罪业 %d——敌方攻击 ×%s" % [_sins, 1.0 + _sins * _sin_atk_per])
	_last_enemy_hp = float(ctrl.enemy_hp)
	_last_survival = float(ctrl.player_hp + ctrl.player_shield)   # 受击检测基准：玩家结算后快照

func on_damaged(ctrl, dmg: int) -> void:
	if not _phase2 and _phase2_hp_ratio > 0.0 and ctrl.enemy_hp <= int(float(ctrl.enemy_hp_max) * _phase2_hp_ratio):
		_phase2 = true
		ctrl.player_shield = 0
		_last_survival = float(ctrl.player_hp)
		ctrl.boss_atk_mult = _phase2_atk_mult * (1.0 + _sins * _sin_atk_per)
		ctrl.enemy_intent = ctrl.status_system.roll_intent(_p2_room_data)
		ctrl.hud._log("⚖ 拷问心防：护盾剥离——纯血量承伤（攻击 ×%s，每回合剥盾）" % _phase2_atk_mult)
		ctrl.hud._popup("⚖ 拷问心防！", Palette.POP_STATUS, ctrl.hud._enemy_sprite_anchor())
		ctrl.hud._refresh_meta()
		return
	if _phase2 and not _phase3 and _phase3_hp_ratio > 0.0 and ctrl.enemy_hp <= int(float(ctrl.enemy_hp_max) * _phase3_hp_ratio):
		_phase3 = true
		ctrl.boss_atk_mult = _phase3_atk_mult * (1.0 + _sins * _sin_atk_per)
		ctrl.enemy_intent = ctrl.status_system.roll_intent(_p3_room_data)
		ctrl.hud._log("⚖ 终极审判：罪无可赦——攻击 ×%s，玩家血量 <50%% 时伤害再 ×%s" % [_phase3_atk_mult, _low_hp_mult])
		ctrl.hud._popup("⚖ 终极审判！", Palette.POP_STATUS, ctrl.hud._enemy_sprite_anchor())
		ctrl.hud._refresh_meta()
