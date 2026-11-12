extends BossGimmick

const ICON := "👁🔒"

# ============================================================================
# ACT3 精英·终焉守望（Step 4，计划 §7 替换原深渊注废复用）
# 触发：周期交替（每 2 回合一次干扰，目盲 ↔ 锁轮）
# 效果：目盲隐藏预览 / 锁轮固定一列；HP 低于阈值后，干扰回合追加重击
# 持续/结束：每次干扰后一回合恢复（不追加新干扰）
# 应对：看当前格、净化、恢复窗口输出
# 参数：interval / hp_ratio / heavy_mult
# ============================================================================

var _interval := 2
var _hp_ratio := 0.5
var _heavy_mult := 2.0
var _turns := 0
var _last_pressure_turn := -1
var _next_blind := true

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.current_room.gimmick_params if ctrl.current_room != null else {}
	_interval = maxi(1, int(p.get("interval", 2)))
	_hp_ratio = float(p.get("hp_ratio", 0.5))
	_heavy_mult = float(p.get("heavy_mult", 2.0))
	_turns = 0
	_last_pressure_turn = -1
	_next_blind = true
	ctrl.hud._log("👁 终焉守望：每 %d 回合交替目盲/锁轮；HP<%d%% 后干扰回合追加重击（每次干扰后一回合恢复）" % [
		_interval, int(_hp_ratio * 100.0)])

func on_turn_begin(ctrl) -> void:
	_turns += 1
	if _turns % _interval != 0:
		if recovery_window(ctrl):
			ctrl.hud._log("👁 守望间隙：本回合不追加干扰（输出窗口）")
		return
	_last_pressure_turn = _turns
	if _next_blind:
		ctrl.apply_debuff("blind", 1)
		ctrl.hud._log("🌫 终焉目盲：本回合隐藏后续预览（看当前格/净化）")
	else:
		var col: int = randi() % DuelController.REELS
		ctrl.pending_lock_reel = col
		ctrl.hud._log("🔒 终焉锁轮：第 %d 列固定不变" % (col + 1))
	_next_blind = not _next_blind
	if float(ctrl.enemy_hp) / float(maxi(1, int(ctrl.enemy_hp_max))) <= _hp_ratio:
		var sd: IntentData = ctrl.status_system.intent_def("heavy")
		var v: int = int(round(float(ctrl.enemy_atk) * _heavy_mult))
		ctrl.enemy_intent = {"data": sd, "type": "heavy", "value": v}
		ctrl.hud._log("⚠ 低血守望：本回合追加重击（%d）" % v)

func recovery_window(_ctrl) -> bool:
	return _last_pressure_turn >= 0 and _turns == _last_pressure_turn + 1

func rhythm_window(_ctrl) -> String:
	if recovery_window(_ctrl):
		return "恢复"
	if _last_pressure_turn >= 0 and _turns == _last_pressure_turn:
		return "爆发"
	return "蓄势"
