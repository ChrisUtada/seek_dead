extends BossGimmick

const ICON := "⚫"   # 下一房预告横幅的机制图标（battle_hud 经 get_script_constant_map 读取）
const IntentData = preload("res://scripts/battle/intent_data.gd")
const P2_INTENTS := [
	preload("res://resources/intents/attack.tres"),
	preload("res://resources/intents/heavy.tres"),
	preload("res://resources/intents/jam.tres"),
]

# 幕二 BOSS·无名虚空「情感剥离」（emotional_vacuum，2026-08-10 定稿）：
# P1 情感剥离（deprived_level=1）：玩家护符被动全部失效（乘区/每回合盾/回血/抗扰/破甲/元素/状态/开局盾）——
#   只剩武器/技能/消耗品/目押基本功（聚合层 agg_* 与消费点读取开关，零结算改动）。
# P2 全面麻木（HP<50% 一次性，deprived_level=2）：技能也失效——下一回合重建转轮条带（技能符号出池）+
#   已挂增益清空（player_buffs.clear()）+ 护甲重设 p2_armor + 攻击 ×p2_atk_mult + 意图 attack 40/heavy 30/jam 30。
# 与茧居石雕（Act1 隐秘·节奏）错位：本 BOSS 验收「装备独立性」——高 base 武器 + 光武克制 + 消耗品管理的裸输出。
# T24 参数化：phase2_hp_ratio/deprive_charms/deprive_skills/p2_atk_mult/p2_armor 读 gimmick_params。
# 单侧性纪律：只操作本 BOSS 的 enemy_hp/enemy_armor/enemy_intent/boss_atk_mult + 玩家侧剥夺开关（惩罚语义），无跨侧共享。

var _phase2_hp_ratio := 0.5
var _deprive_charms := true
var _deprive_skills := true
var _p2_atk_mult := 0.85
var _p2_armor := 32
var _phase2 := false
var _rebuild_pending := false
var _p2_room_data: RoomData

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.ROOMS[ctrl.room_index].gimmick_params if (ctrl.room_index >= 0 and ctrl.room_index < ctrl.ROOMS.size()) else {}
	_phase2_hp_ratio = float(p.get("phase2_hp_ratio", 0.5))
	_deprive_charms = bool(p.get("deprive_charms", true))
	_deprive_skills = bool(p.get("deprive_skills", true))
	_p2_atk_mult = float(p.get("p2_atk_mult", 0.85))
	_p2_armor = int(p.get("p2_armor", 32))
	_phase2 = false
	_rebuild_pending = false
	_p2_room_data = RoomData.new()
	_p2_room_data.kind = "boss"
	_p2_room_data.intents.assign(P2_INTENTS)
	# P1 情感剥离：护符被动全部失效（deprived_level=1，聚合层读取）+ 开局盾扣回
	if _deprive_charms:
		ctrl.deprived_level = 1
		if ctrl.charm_room_shield > 0 and ctrl.player_shield > 0:
			ctrl.player_shield = maxi(0, ctrl.player_shield - ctrl.charm_room_shield)
			ctrl.hud._log("⚫ 情感剥离：守望护符的开局护盾被抽离")
		ctrl.hud._log("⚫ 无名虚空：情感剥离——护符效果全部失效，只剩武器/技能/消耗品（HP<%d%% 全面麻木：技能也失效）" % int(_phase2_hp_ratio * 100))
		ctrl.hud._popup("⚫ 情感剥离：护符失效！", Palette.POP_STATUS, ctrl.hud._enemy_sprite_anchor())
	else:
		ctrl.deprived_level = 0
		ctrl.hud._log("⚫ 无名虚空：情感涌动（剥夺关闭，参数演习模式）")

func on_turn_begin(ctrl) -> void:
	# P2 技能出池延迟到下一回合重建条带（build_strips 仅进房/精华时构建）——照元素精华序列
	if _rebuild_pending:
		_rebuild_pending = false
		ctrl._build_pool(ctrl.selected_loadout)
		ctrl.reel_system.build_strips()
		ctrl.reel_system.reset_grid()
		ctrl.hud._log("⚫ 转轮重建：技能符号已出池——只剩武器与消耗品")
		ctrl.hud._refresh_meta()
	ctrl.boss_atk_mult = _p2_atk_mult if _phase2 else 1.0
	if _phase2:
		ctrl.enemy_intent = ctrl.status_system.roll_intent(_p2_room_data)

func on_damaged(ctrl, _dmg: int) -> void:
	if _phase2 or _phase2_hp_ratio <= 0.0:
		return
	if ctrl.enemy_hp <= int(float(ctrl.enemy_hp_max) * _phase2_hp_ratio):
		_phase2 = true
		if _deprive_skills:
			ctrl.deprived_level = 2
			ctrl.player_buffs.clear()          # 全面麻木：已挂增益当场剥离
			_rebuild_pending = true            # 技能符号下一回合出池
		ctrl.enemy_armor_max = _p2_armor
		ctrl.enemy_armor = _p2_armor
		ctrl.boss_atk_mult = _p2_atk_mult
		ctrl.hud._log("⚫ 全面麻木：技能失效——护甲 %d，攻击 ×%s，意图转入麻木剖面（技能符号下一回合出池）" % [_p2_armor, _p2_atk_mult])
		ctrl.hud._popup("⚫ 全面麻木！", Palette.POP_STATUS, ctrl.hud._enemy_sprite_anchor())
		ctrl.hud._refresh_meta()
