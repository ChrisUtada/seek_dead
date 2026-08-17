class_name StatusSystem
extends RefCounted

# status_system — 意图与状态定义工具（2026-08-09 从 duel_controller 拆分）
#
# 职责：敌人意图的加权抽取（_roll_intent：房间表 → 行为族表 → 默认表，抗扰折扣）、
# 意图/状态定义表与查询（IntentData / StatusDef）、状态汇总文案、增益效果名。
# 纯工具层：不持有运行时状态，全部经 _ctrl 读取（enemy_atk / _interf_resist_rf）。

# T20 意图资源化：意图定义（IntentData）+ 默认三档表（按房型 kind；课程化落地在数据层）
const INTENT_DEFS := {
	"attack": preload("res://resources/intents/attack.tres"),
	"heavy": preload("res://resources/intents/heavy.tres"),
	"jam": preload("res://resources/intents/jam.tres"),
	"lock": preload("res://resources/intents/lock.tres"),
	"chaos": preload("res://resources/intents/chaos.tres"),
	"auto_stop": preload("res://resources/intents/auto_stop.tres"),
}
# 默认表权重（id → 权重；房间 RoomData.intents 非空时用房间表（IntentData.weight）覆盖）
# 2026-08-14 新增 auto_stop「夺轮」：从 jam/chaos 各挪部分权重，干扰类总量占比基本不变
const DEFAULT_INTENT_WEIGHTS := {
	"normal": {"attack": 60, "heavy": 20, "jam": 8, "lock": 5, "chaos": 4, "auto_stop": 5},
	"elite":  {"attack": 40, "heavy": 20, "jam": 12, "lock": 15, "chaos": 8, "auto_stop": 10},
	"boss":   {"attack": 60, "heavy": 40},
}

# T23：状态定义资源化（StatusDef：base/element/name/icon/decay/desc），显示名替代原 STATUS_NAMES 硬编码
# 2026-08-09 单侧性纪律：frost=敌人侧（减攻）/ frozen=玩家侧（冻结转轮）拆分，状态定义不得跨侧共享
const STATUS_DEFS := {
	"burn": preload("res://resources/statuses/burn.tres"),
	"frost": preload("res://resources/statuses/frost.tres"),
	"poison": preload("res://resources/statuses/poison.tres"),
	"frozen": preload("res://resources/statuses/frozen.tres"),
}

var _ctrl  # DuelController


func _init(ctrl) -> void:
	_ctrl = ctrl


func intent_def(id: String) -> IntentData:
	return INTENT_DEFS.get(id, null)


# T20：加权抽取意图（优先级：房间 RoomData.intents（IntentData.weight）→ 行为族 EnemyArchetype.intent_weights → kind 默认表；
# 抗扰（_interf_resist_rf）对可净化（干扰类）意图权重打折）
func roll_intent(room: RoomData) -> Dictionary:
	var wtable := {}
	if room != null and room.intents.size() > 0:
		for it in room.intents:
			if it != null:
				wtable[it.id] = it.weight
	elif room != null and room.archetype != null and room.archetype.intent_weights.size() > 0:
		wtable = room.archetype.intent_weights.duplicate()
	else:
		wtable = DEFAULT_INTENT_WEIGHTS.get(room.kind if room != null else "normal", DEFAULT_INTENT_WEIGHTS["normal"]).duplicate()
	var total := 0.0
	var interf_rf: float = 1.0 if _ctrl.deprived_level >= 1 else _ctrl._interf_resist_rf   # 无名虚空：抗扰护符剥离
	for k in wtable:
		var w: float = wtable[k]
		var sd: IntentData = intent_def(k)
		if sd != null and sd.purifiable:
			w *= interf_rf   # 抗扰：干扰类意图权重打折
		wtable[k] = w
		total += w
	var r := randf() * total
	var tid := "attack"
	for k in wtable:
		r -= wtable[k]
		if r <= 0.0:
			tid = k
			break
	var sd2: IntentData = intent_def(tid)
	var value := 0
	match tid:
		"heavy":  value = int(_ctrl.enemy_atk * sd2.value_mult) if sd2 != null else _ctrl.enemy_atk * 2
		"attack": value = _ctrl.enemy_atk
	return {"data": sd2, "type": tid, "value": value}


func intent_name(t: String) -> String:
	# T20：优先读 IntentData.display_name；未定义时回落默认名（新意图类型兜底）
	var sd: IntentData = intent_def(t)
	if sd != null and sd.display_name != "":
		return sd.display_name
	match t:
		"jam":   return "注废"
		"lock":  return "锁轮"
		"chaos": return "乱权"
		"heavy": return "重击"
		"attack": return "攻击"
		_:      return t


func status_def(st: String) -> StatusDef:
	return STATUS_DEFS.get(st, null)


func status_base(type_str: String) -> float:
	var sd: StatusDef = status_def(type_str)
	return sd.base if sd != null else 0.0


# 状态类型对应的属性元素（用于 DoT 单向克制）
func status_element(st: String) -> String:
	var sd: StatusDef = status_def(st)
	return sd.element if sd != null else "none"


func status_summary(stacks: Dictionary) -> String:
	var parts: Array = []
	for st in stacks.keys():
		var sd: StatusDef = status_def(st)
		parts.append("%s+%d" % [sd.name if sd != null else st, stacks[st]])
	return "/".join(parts)


func buff_effect_name(effect: String) -> String:
	return BattleMath.buff_effect_name(effect)
