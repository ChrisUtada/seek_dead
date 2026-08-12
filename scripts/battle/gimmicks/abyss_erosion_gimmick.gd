extends BossGimmick

const ICON := "🕳"   # 下一房预告横幅的机制图标（battle_hud 经 get_script_constant_map 读取）
const P2_INTENTS := [
	preload("res://resources/intents/attack.tres"),
	preload("res://resources/intents/heavy.tres"),
	preload("res://resources/intents/jam.tres"),
]
const P3_INTENTS := [
	preload("res://resources/intents/attack.tres"),
	preload("res://resources/intents/heavy.tres"),
]

# 幕三 BOSS·深渊监视者「深渊侵蚀」三阶段（2026-08-10 定稿，草案原型 §9 PTSD）：
# P1 噩梦侵袭（HP 100%→66%）：每回合向转轮注入废铁（量 = 池大小 × (base_ratio + 残血比例×low_hp_bonus)，
#   上限 max_trash）——稀释「进池类无天花板」，带越多武器侵蚀越狠（稀释刹车）。
# P2 闪回暴走（HP<66% 一次性）：每次停轮后有 phase2_flashback_chance 概率强制免费重转（停轮作废、
#   玩家二次按停——duel_controller 经 consume_flashback 消费标志挂接）+ 注废 ×phase2_trash_mult +
#   护甲 35→40 + 意图 attack 40/heavy 30/jam 30（jam 可净化）。
# P3 深渊吞噬（HP<33% 一次性）：注废再 ×phase3_trash_mult（与 P2 叠乘）+ 攻击 ×phase3_atk_mult +
#   护甲 40→45 + 意图 attack 50/heavy 50——终局高攻厚甲。
# 与 Act2 双阶段 BOSS（换轴）错位：三阶段同轴加深，验收「池稀释对抗」（洗盘/少带/穿透）。
# T24 参数化：全部数值读 gimmick_params（现状硬编码 const 迁入）；参数缺省 = 单阶段行为不变（教学回归）。
# 单侧性纪律：只操作本 BOSS 的 boss_trash/enemy_armor/enemy_intent/boss_atk_mult（敌人侧），无跨侧共享。

var _base_ratio := 0.10
var _low_hp_bonus := 0.30
var _max_trash := 24
var _phase2_hp_ratio := 0.66
var _phase2_trash_mult := 1.5
var _phase2_flashback_chance := 0.5
var _phase2_armor := 40
var _phase3_hp_ratio := 0.33
var _phase3_trash_mult := 2.0
var _phase3_atk_mult := 1.3
var _phase3_armor := 45
var _phase2 := false
var _phase3 := false
var _flashback_pending := false
var _p2_room_data: RoomData
var _p3_room_data: RoomData

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.ROOMS[ctrl.room_index].gimmick_params if (ctrl.room_index >= 0 and ctrl.room_index < ctrl.ROOMS.size()) else {}
	_base_ratio = float(p.get("base_ratio", 0.10))
	_low_hp_bonus = float(p.get("low_hp_bonus", 0.30))
	_max_trash = int(p.get("max_trash", 24))
	_phase2_hp_ratio = float(p.get("phase2_hp_ratio", 0.66))
	_phase2_trash_mult = float(p.get("phase2_trash_mult", 1.5))
	_phase2_flashback_chance = float(p.get("phase2_flashback_chance", 0.5))
	_phase2_armor = int(p.get("phase2_armor", 40))
	_phase3_hp_ratio = float(p.get("phase3_hp_ratio", 0.33))
	_phase3_trash_mult = float(p.get("phase3_trash_mult", 2.0))
	_phase3_atk_mult = float(p.get("phase3_atk_mult", 1.3))
	_phase3_armor = int(p.get("phase3_armor", 45))
	_phase2 = false
	_phase3 = false
	_flashback_pending = false
	_p2_room_data = RoomData.new()
	_p2_room_data.kind = "boss"
	_p2_room_data.intents = P2_INTENTS
	_p3_room_data = RoomData.new()
	_p3_room_data.kind = "boss"
	_p3_room_data.intents = P3_INTENTS
	ctrl.boss_trash = 0
	var phase_txt := ""
	if _phase2_hp_ratio > 0.0:
		phase_txt = "；HP<%d%% 闪回暴走（停轮强制重转），HP<%d%% 深渊吞噬（废铁翻倍+高攻）" % [int(_phase2_hp_ratio * 100), int(_phase3_hp_ratio * 100)]
	ctrl.hud._log("🕳 深渊侵蚀：每回合向转轮注入废铁，池越大/血越低注入越多%s" % phase_txt)

func on_turn_begin(ctrl) -> void:
	# 闪回掷取：P2 起每回合一次（消费后即 false，重转不重复触发）
	_flashback_pending = _phase2 and not _phase3 and _phase2_flashback_chance > 0.0 and randf() < _phase2_flashback_chance
	var hp_ratio: float = float(ctrl.enemy_hp) / float(ctrl.enemy_hp_max)
	var ratio: float = _base_ratio + (1.0 - hp_ratio) * _low_hp_bonus
	if _phase2:
		ratio *= _phase2_trash_mult
	if _phase3:
		ratio *= _phase3_trash_mult
	var add: int = int(round(ctrl.pool.size() * ratio))
	ctrl.boss_trash = mini(_max_trash, ctrl.boss_trash + add)
	if add > 0:
		ctrl.hud._log("🕳 深渊侵蚀 +%d 废铁（池 %d，HP %d%%）" % [add, ctrl.pool.size(), int(hp_ratio * 100)])
	# 阶段倍率/意图
	ctrl.boss_atk_mult = _phase3_atk_mult if _phase3 else 1.0
	if _phase3:
		ctrl.enemy_intent = ctrl.status_system.roll_intent(_p3_room_data)
	elif _phase2:
		ctrl.enemy_intent = ctrl.status_system.roll_intent(_p2_room_data)

func on_damaged(ctrl, _dmg: int) -> void:
	if not _phase2 and _phase2_hp_ratio > 0.0 and ctrl.enemy_hp <= int(float(ctrl.enemy_hp_max) * _phase2_hp_ratio):
		_phase2 = true
		ctrl.enemy_armor_max = _phase2_armor
		ctrl.enemy_armor = _phase2_armor
		ctrl.boss_atk_mult = 1.0
		ctrl.enemy_intent = ctrl.status_system.roll_intent(_p2_room_data)
		ctrl.hud._log("🕳 闪回暴走：噩梦闪回——停轮将被强制重转，注废加速，护甲 %d" % _phase2_armor)
		ctrl.hud._popup("🕳 闪回暴走！", Palette.POP_STATUS, ctrl.hud._enemy_sprite_anchor())
		ctrl.hud._refresh_meta()
		return
	if _phase2 and not _phase3 and _phase3_hp_ratio > 0.0 and ctrl.enemy_hp <= int(float(ctrl.enemy_hp_max) * _phase3_hp_ratio):
		_phase3 = true
		ctrl.enemy_armor_max = _phase3_armor
		ctrl.enemy_armor = _phase3_armor
		ctrl.boss_atk_mult = _phase3_atk_mult
		ctrl.enemy_intent = ctrl.status_system.roll_intent(_p3_room_data)
		ctrl.hud._log("🕳 深渊吞噬：废铁注入翻倍，攻击 ×%s，护甲 %d——终局降临" % [_phase3_atk_mult, _phase3_armor])
		ctrl.hud._popup("🕳 深渊吞噬！", Palette.POP_STATUS, ctrl.hud._enemy_sprite_anchor())
		ctrl.hud._refresh_meta()

# duel_controller 停轮后、结算前调用：返回 true 则本次停轮作废强制重转（消费标志，每回合至多一次）
func consume_flashback() -> bool:
	if not _flashback_pending:
		return false
	_flashback_pending = false
	return true
