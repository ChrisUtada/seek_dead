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
# 按幕渐进（P0-A，2026-08-24）：意图首次入池幕号——Act1 纯 attack/heavy 教学；Act2 干扰入门（jam/lock/chaos）；
# Act3 夺轮入池（auto_stop）。作用于「行为族表」与「kind 默认表」两层；房间显式表（RoomData.intents）
# 不受限（BOSS/特殊怪逃生口）。新意图默认 unlock=1（恒可出），需要教学保护才在此登记。
const INTENT_UNLOCK_ACT := {
	"jam": 2,
	"lock": 2,
	"chaos": 2,
	"auto_stop": 3,
}
# 按幕分档默认表（act → kind）：只分档 normal/elite；boss 不分档（专属表/gimmick 主导，走 DEFAULT_INTENT_WEIGHTS）。
# Act3 行与旧全局表一致；被锁意图的权重按比例折入 attack/heavy（干扰总量随幕解锁逐步恢复）。
const ACT_INTENT_WEIGHTS := {
	1: {
		"normal": {"attack": 75, "heavy": 25},
		"elite":  {"attack": 70, "heavy": 30},
	},
	2: {
		"normal": {"attack": 65, "heavy": 20, "jam": 8, "lock": 5, "chaos": 4},
		"elite":  {"attack": 50, "heavy": 20, "jam": 12, "lock": 15, "chaos": 8},
	},
	3: {
		"normal": {"attack": 60, "heavy": 20, "jam": 8, "lock": 5, "chaos": 4, "auto_stop": 5},
		"elite":  {"attack": 40, "heavy": 20, "jam": 12, "lock": 15, "chaos": 8, "auto_stop": 10},
	},
}
# 兜底默认表（boss 恒用；normal/elite 已由 ACT_INTENT_WEIGHTS 全幕覆盖）
const DEFAULT_INTENT_WEIGHTS := {
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


# T20：加权抽取意图（优先级：房间 RoomData.intents（IntentData.weight，显式覆盖不受按幕限制）
# → 行为族 EnemyArchetype.intent_weights（按幕过滤）→ kind 默认表（按幕分档 ACT_INTENT_WEIGHTS）；
# 抗扰（_interf_resist_rf）对可净化（干扰类）意图权重打折）
func roll_intent(room: RoomData) -> Dictionary:
	var wtable := {}
	if room != null and room.intents.size() > 0:
		for it in room.intents:
			if it != null:
				wtable[it.id] = it.weight   # 房间显式表：BOSS/特殊怪逃生口，不做幕过滤
	else:
		var kind: String = room.kind if room != null else "normal"
		var act: int = int(room.act) if room != null else 1
		if room != null and room.archetype != null and room.archetype.intent_weights.size() > 0:
			wtable = room.archetype.intent_weights.duplicate()
			_gate_by_act(wtable, act)   # 行为族剖面同样按幕过滤（Act1 干扰系怪也不出干扰意图）
			if wtable.is_empty():
				wtable = _default_wtable(kind, act)   # 全被锁空（如纯干扰剖面遇 Act1）→ 回落默认表
		else:
			wtable = _default_wtable(kind, act)
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


# P0-A 按幕分档默认表：boss 不分档；未知 act 收拢进 1~3；未知 kind 回落 normal。
func _default_wtable(kind: String, act: int) -> Dictionary:
	if kind == "boss":
		return (DEFAULT_INTENT_WEIGHTS["boss"] as Dictionary).duplicate()
	var by_act: Dictionary = ACT_INTENT_WEIGHTS[clampi(act, 1, 3)]
	return (by_act[kind if by_act.has(kind) else "normal"] as Dictionary).duplicate()


# P0-A 按幕过滤未解锁意图（就地修改；attack/heavy 未登记恒可出）。行为族表与默认表共用此闸；
# 房间显式表不经过此处。过滤后为空由调用方回落默认表。
func _gate_by_act(wtable: Dictionary, act: int) -> void:
	for k in wtable.keys():
		if act < int(INTENT_UNLOCK_ACT.get(k, 1)):
			wtable.erase(k)


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
