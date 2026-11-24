class_name DamageLedger
extends RefCounted

# T4 前置（2026-11-24）：统一伤害表现事件账本。
#
# 铁律（工单 §2）：
# - before/after 由调用方传入，账本不重算任何数值；
# - 账本不碰 enemy_hp / enemy_armor / game_state / RNG；
# - drain() 取走并清空，每个表现阶段各取一次，保证多段伤害按真实结算顺序逐条回放。

var events: Array = []
var turn: int = 0
var hp_before: int = 0


# 一回合开始：清空上一回合残留并记录起始 HP（不重算、不写战斗状态）。
func begin(p_turn: int, p_hp_before: int) -> void:
	events = []
	turn = p_turn
	hp_before = p_hp_before


# 记录一段真实扣血。字段固定七项，调用方负责给出准确 before/after。
func record(kind: String, amount: int, before: int, after: int,
		tag: String = "", element: String = "none", source: String = "") -> void:
	if amount <= 0:
		return
	events.append({
		"kind": kind,
		"amount": amount,
		"before": before,
		"after": after,
		"tag": tag,
		"element": element,
		"source": source,
	})


# 取走并清空：每个表现阶段（攻击回放 / DoT 回放）各取一次。
func drain() -> Array:
	var out: Array = events.duplicate(true)
	events = []
	return out


# 对账用：sum(amount)。
func total() -> int:
	var sum := 0
	for e in events:
		sum += int(e.get("amount", 0))
	return sum
