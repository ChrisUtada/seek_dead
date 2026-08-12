extends BossGimmick

const ICON := "⚖"   # 下一房预告横幅的机制图标（battle_hud 经 get_script_constant_map 读取）
const IntentData = preload("res://scripts/battle/intent_data.gd")
const RoomData = preload("res://scripts/battle/room_data.gd")
const P2_INTENTS := [
	preload("res://resources/intents/attack.tres"),
	preload("res://resources/intents/heavy.tres"),
	preload("res://resources/intents/jam.tres"),
]

# 幕二 BOSS·天平审判官「律法强迫」（compulsion_rule，2026-08-10 定稿）：
# P1 规则宣告：每 rule_every 回合宣告 1 条律法（纯律=三格同元素 / 清规=三格全异 / 杀律=三格全攻击，
#   基于停轮后三列顶格 grid/grid_elem）——达成 → 本回合敌方攻击 ×rule_reward_atk_mult（安全窗口）；
#   未达成 → 重击 ×rule_punish_mult。宣告回合之间走意图表（P1: RoomData.intents）。
# P2 严刑惩戒（HP<50% 一次性）：护甲重设 p2_armor + 攻击 ×p2_atk_mult + 意图 attack 40/heavy 30/jam 30
#   （自由回合掷取）+ 惩罚升级：未达成律法 → 重击 + 锁 1 个消耗品槽（p2_lock_consumable，1 回合）。
# 与低语者（干扰应变）/元素使（元素应变）错位：本 BOSS 验收「目押规则应变」——按律法停轮，
# 达成=攻减半的安全回合，未达成=自选重击；MISS/废铁格天然助成清规/杀律。
# T24 参数化：rule_pool/rule_every/rule_reward_atk_mult/rule_punish_mult/phase2_hp_ratio/p2_atk_mult/p2_armor/p2_lock_consumable。
# 单侧性纪律：只操作本 BOSS 的 enemy_hp/enemy_armor/enemy_intent/boss_atk_mult + 玩家侧锁槽字段（惩罚语义），无跨侧共享。

const RULE_NAMES := {"same_element": "纯律", "all_distinct": "清规", "all_damage": "杀律"}

var _rule_pool: Array = ["same_element", "all_distinct", "all_damage"]
var _rule_every := 2
var _rule_reward_atk_mult := 0.5
var _rule_punish_mult := 2.0
var _phase2_hp_ratio := 0.5
var _p2_atk_mult := 0.9
var _p2_armor := 35
var _p2_lock_consumable := true
var _phase2 := false
var _turns := 0
var _pending_rule := ""
var _p2_room_data: RoomData

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.ROOMS[ctrl.room_index].gimmick_params if (ctrl.room_index >= 0 and ctrl.room_index < ctrl.ROOMS.size()) else {}
	var pool: Array = p.get("rule_pool", ["same_element", "all_distinct", "all_damage"])
	_rule_pool = []
	for r in pool:
		if RULE_NAMES.has(str(r)):
			_rule_pool.append(str(r))
	_rule_every = maxi(1, int(p.get("rule_every", 2)))
	_rule_reward_atk_mult = float(p.get("rule_reward_atk_mult", 0.5))
	_rule_punish_mult = float(p.get("rule_punish_mult", 2.0))
	_phase2_hp_ratio = float(p.get("phase2_hp_ratio", 0.5))
	_p2_atk_mult = float(p.get("p2_atk_mult", 0.9))
	_p2_armor = int(p.get("p2_armor", 35))
	_p2_lock_consumable = bool(p.get("p2_lock_consumable", true))
	_phase2 = false
	_turns = 0
	_pending_rule = ""
	_p2_room_data = RoomData.new()
	_p2_room_data.kind = "boss"
	_p2_room_data.intents = P2_INTENTS
	ctrl.hud._log("⚖ 天平审判官：律法宣告——每 %d 回合 1 条律法（达成 → 敌方攻击 ×%s；违逆 → 重击 ×%s）；HP<%d%% 严刑惩戒（护甲 %d + 惩罚升级锁槽）" % [_rule_every, _rule_reward_atk_mult, _rule_punish_mult, int(_phase2_hp_ratio * 100), _p2_armor])

func on_turn_begin(ctrl) -> void:
	_turns += 1
	ctrl.boss_atk_mult = _p2_atk_mult if _phase2 else 1.0
	var rule_turn: bool = _rule_pool.size() > 0 and (_turns % _rule_every == 0)
	if rule_turn:
		_pending_rule = _rule_pool[randi() % _rule_pool.size()]
		ctrl.enemy_intent = _rule_intent(_pending_rule)
		ctrl.hud._log("⚖ 律法宣告：「%s」——本回合按律法停轮，违逆将遭重击惩戒" % RULE_NAMES[_pending_rule])
	elif _phase2:
		_pending_rule = ""
		ctrl.enemy_intent = ctrl.status_system.roll_intent(_p2_room_data)
	else:
		_pending_rule = ""

func on_turn_resolved(ctrl) -> void:
	if _pending_rule == "":
		return
	var rule := _pending_rule
	_pending_rule = ""
	if _rule_met(ctrl, rule):
		ctrl.boss_atk_mult *= _rule_reward_atk_mult
		ctrl.hud._log("⚖ 律法遵从：敌方攻击 ×%s（安全窗口）" % _rule_reward_atk_mult)
		return
	ctrl.boss_atk_mult *= _rule_punish_mult
	var hv: int = int(round(ctrl.enemy_atk * ctrl.boss_atk_mult))
	ctrl.enemy_intent = {"data": null, "type": "heavy", "value": hv}
	ctrl.hud._log("⚖ 律法违逆：重击惩戒 %d！" % hv)
	if _phase2 and _p2_lock_consumable and not ctrl.consumable_slots.is_empty():
		ctrl.locked_consumable_slot = randi() % ctrl.consumable_slots.size()
		ctrl.hud._log("⚖ 严刑封印：腰带第 %d 格被律法锁定（本回合不可用）" % (ctrl.locked_consumable_slot + 1))
		ctrl.hud._refresh_consumable_panel()

func on_damaged(ctrl, dmg: int) -> void:
	if _phase2 or _phase2_hp_ratio <= 0.0:
		return
	if ctrl.enemy_hp <= int(float(ctrl.enemy_hp_max) * _phase2_hp_ratio):
		_phase2 = true
		ctrl.enemy_armor_max = _p2_armor
		ctrl.enemy_armor = _p2_armor
		ctrl.boss_atk_mult = _p2_atk_mult
		ctrl.hud._log("⚖ 严刑惩戒：律法升级——护甲 %d，攻击 ×%s，违逆者将被封印" % [_p2_armor, _p2_atk_mult])
		ctrl.hud._popup("⚖ 严刑惩戒！", Palette.POP_STATUS, ctrl.hud._enemy_sprite_anchor())
		ctrl.hud._refresh_meta()

func _rule_intent(rule: String) -> Dictionary:
	var rd: IntentData = IntentData.new()
	rd.id = "rule"
	rd.display_name = "律法·%s" % RULE_NAMES.get(rule, rule)
	rd.icon = "⚖"
	rd.weight = 1.0
	rd.purifiable = false
	rd.value_mult = 0.0
	return {"data": rd, "type": "rule", "value": 0}

# 判定基于停轮后三列顶格（grid[reel][0] 符号 / grid_elem[reel][0] 有效元素）
func _rule_met(ctrl, rule: String) -> bool:
	var g: Array = ctrl.grid
	var ge: Array = ctrl.grid_elem
	if g.size() < 3 or ge.size() < 3:
		return false
	var s0 = g[0][0]
	var s1 = g[1][0]
	var s2 = g[2][0]
	if s0 == null or s1 == null or s2 == null:
		return false
	match rule:
		"same_element":
			var e0: String = ge[0][0]
			return e0 == ge[1][0] and e0 == ge[2][0]
		"all_distinct":
			return s0.resource_path != s1.resource_path and s0.resource_path != s2.resource_path and s1.resource_path != s2.resource_path
		"all_damage":
			return s0.kind == "damage" and s1.kind == "damage" and s2.kind == "damage"
	return false
