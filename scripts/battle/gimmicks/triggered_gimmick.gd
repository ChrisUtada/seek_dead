extends BossGimmick

# ============================================================================
# Step 1（2026-11-12）· 纯数据驱动机制（共用触发 + debuff）
#
# 房间 .tres 的 gimmick_script 指向本脚本、gimmick_params.triggers 写触发表，
# 即可得到「入场 / 首次转轮前 / 首次受击 / 周期 / 首次破甲 / 阶段转换」机制，
# 无需为每只怪再写 .gd（复杂机制仍写专属子类，本脚本只管共用触发与减益组合）。
#
# 示例（gimmick_params）：
#   {
#       "triggers": [
#           {"on": "enter",  "debuff": "blind", "turns": 2},
#           {"on": "every", "n": 3, "debuff": "corrode", "turns": 99},
#       ]
#   }
#
# 纪律：不消耗 RNG；不直接改玩家字段；无锁血 / 无固定伤害上限。
# ============================================================================

const TriggerKit = preload("res://scripts/battle/gimmicks/trigger_kit.gd")

var _kit


func on_room_start(ctrl) -> void:
	var params: Dictionary = {}
	if ctrl.current_room != null:
		params = ctrl.current_room.gimmick_params
	_kit = TriggerKit.new(params)
	_kit.fire("enter", ctrl)
	_kit.fire("phase", ctrl)


func on_turn_begin(ctrl) -> void:
	if _kit == null:
		return
	_kit.fire("first_spin", ctrl)
	_kit.fire("every", ctrl)
	_kit.fire("phase", ctrl)


func on_damaged(ctrl, dmg: int) -> void:
	if _kit == null or dmg <= 0:
		return
	_kit.fire("first_hit", ctrl)
	_kit.fire("phase", ctrl)


func on_armor_break(ctrl) -> void:
	if _kit != null:
		_kit.fire("armor_break", ctrl)


func on_hp_changed(ctrl) -> void:
	if _kit != null:
		_kit.fire("phase", ctrl)
