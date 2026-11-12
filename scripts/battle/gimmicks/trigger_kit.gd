extends RefCounted

# ============================================================================
# Step 1（2026-11-12）· 共用触发模块 TriggerKit
# 规格：docs/全怪物个性机制设计与制作计划_2026-11-12.md §10 Step 1
#
# 用一份数据声明「什么时候、对玩家做什么」，怪物无需再各写一套计时：
#   gimmick_params = {
#       "triggers": [
#           {"on": "enter",       "debuff": "weak",      "turns": 1},
#           {"on": "first_spin",  "debuff": "blind",     "turns": 2},
#           {"on": "first_hit",   "debuff": "vulnerable","turns": 2},
#           {"on": "every", "n": 3, "debuff": "corrode", "turns": 99},
#           {"on": "armor_break", "debuff": "strip"},
#           {"on": "phase", "hp": 0.4, "debuff": "vulnerable", "turns": 2},
#       ]
#   }
#
# 触发时机：
#   enter        进入房间，一次性
#   first_spin   玩家首次开始转轮前，一次性
#   first_hit    首次受到玩家伤害，一次性
#   every        每 n 个玩家回合（按 turn_count，每回合最多一次）
#   armor_break  玩家首次破甲（护甲清零），一次性
#   phase        HP 比例首次低于 hp（0–1），每个条目一次
#
# 效果字段：
#   debuff / turns / stacks / order   → ctrl.apply_debuff(...)
#   charge                            → 充能增减（整数）
#
# 纪律：纯确定性；不掷随机、不读全局 RNG；不直接改玩家字段（一律走 apply_debuff）。
# ============================================================================

const SUPPORTED := ["enter", "first_spin", "first_hit", "every", "armor_break", "phase"]

var _entries: Array = []
var _once: Dictionary = {}             # 条目下标 -> true（一次性触发已用）
var _last_every_turn: Dictionary = {}  # 条目下标 -> 上次触发回合


func _init(params: Dictionary = {}) -> void:
	var raw = params.get("triggers", []) if params != null else []
	if typeof(raw) != TYPE_ARRAY:
		return
	for i in raw.size():
		var e = raw[i]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var on := String(e.get("on", ""))
		if on == "" or not SUPPORTED.has(on):
			push_warning("TriggerKit：未知触发「%s」（条目 %d 已跳过）" % [on, i])
			continue
		_entries.append((e as Dictionary).duplicate(true))


func entry_count() -> int:
	return _entries.size()


# 触发某一时机；返回本次真正执行的效果条数（供测试与调试）。
func fire(when: String, ctrl) -> int:
	var fired := 0
	for i in _entries.size():
		var e: Dictionary = _entries[i]
		if String(e.get("on", "")) != when:
			continue
		if when != "every" and _once.has(i):
			continue
		if when == "every":
			var n: int = maxi(1, int(e.get("n", 1)))
			if int(ctrl.turn_count) % n != 0:
				continue
			if int(_last_every_turn.get(i, -999)) == int(ctrl.turn_count):
				continue
		if when == "phase":
			if int(ctrl.enemy_hp_max) <= 0:
				continue
			var pct: float = float(e.get("hp", 0.5))
			if float(ctrl.enemy_hp) / float(ctrl.enemy_hp_max) > pct:
				continue
		_apply(e, ctrl)
		if when == "every":
			_last_every_turn[i] = int(ctrl.turn_count)
		else:
			_once[i] = true
		fired += 1
	return fired


func _apply(e: Dictionary, ctrl) -> void:
	if e.has("charge"):
		ctrl.charge_points = maxi(0, int(ctrl.charge_points) + int(e.get("charge", 0)))
	var id := String(e.get("debuff", ""))
	if id == "":
		return
	var extra: Dictionary = {}
	if e.has("order"):
		extra["order"] = String(e.get("order"))
	ctrl.apply_debuff(id, int(e.get("turns", -1)), int(e.get("stacks", 1)), extra)
