extends BossGimmick

const ICON := "💥🕯"

# ============================================================================
# ACT3 精英·湮灭领主（Step 4，计划 §7 替换原深渊注废复用）
# 触发：每 4 回合
# 效果：重击 + 行动后自损 8% max HP
# 持续/结束：次回合减攻并停止干扰（恢复窗）
# 应对：防御重击，自损后爆发
# 参数：interval / heavy_mult / self_pct / weak_mult
# ============================================================================

var _interval := 4
var _heavy_mult := 2.0
var _self_pct := 0.08
var _weak_mult := 0.7
var _turns := 0
var _last_pressure_turn := -1
var _weak_next := false

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.current_room.gimmick_params if ctrl.current_room != null else {}
	_interval = maxi(1, int(p.get("interval", 4)))
	_heavy_mult = float(p.get("heavy_mult", 2.0))
	_self_pct = float(p.get("self_pct", 0.08))
	_weak_mult = float(p.get("weak_mult", 0.7))
	_turns = 0
	_last_pressure_turn = -1
	_weak_next = false
	ctrl.hud._log("💥 湮灭领主：每 %d 回合重击并自损 %d%% HP；随后一回合减攻（恢复窗）" % [
		_interval, int(round(_self_pct * 100.0))])

func on_turn_begin(ctrl) -> void:
	_turns += 1
	if _weak_next:
		_weak_next = false
		ctrl.boss_atk_mult = _weak_mult
		ctrl.hud._log("🕯 余烬未熄：本回合攻击 ×%s（恢复窗，集中输出）" % _weak_mult)
		return
	if _turns % _interval != 0:
		return
	_last_pressure_turn = _turns
	var sd: IntentData = ctrl.status_system.intent_def("heavy")
	var v: int = int(round(float(ctrl.enemy_atk) * _heavy_mult))
	ctrl.enemy_intent = {"data": sd, "type": "heavy", "value": v}
	ctrl.enemy_self_damage_after = maxi(1, int(round(float(ctrl.enemy_hp_max) * _self_pct)))
	_weak_next = true
	ctrl.hud._log("⚠ 湮灭重击：%d（行动后自损 %d）" % [v, int(ctrl.enemy_self_damage_after)])

func recovery_window(_ctrl) -> bool:
	return _last_pressure_turn >= 0 and _turns == _last_pressure_turn + 1

func rhythm_window(_ctrl) -> String:
	if recovery_window(_ctrl):
		return "恢复"
	if _last_pressure_turn >= 0 and _turns == _last_pressure_turn:
		return "爆发"
	return "蓄势"
