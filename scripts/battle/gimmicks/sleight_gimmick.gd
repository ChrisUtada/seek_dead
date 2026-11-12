extends BossGimmick

const ICON := "🎴⚡"

# ============================================================================
# ACT3 精英·终末庄家（Step 4，计划 §7 写作「终焉诡匠」，沿用资源显示名）
# 触发：每 3 回合注废 + 玩家连续同符号
# 效果：注废 1 列，并施加反噬（连续同符号受小额代价）
# 持续/结束：换符号即结束；干扰后一回合不追加注废
# 应对：换目标、净化、窗口爆发
# 参数：interval / backlash_turns / jam_column
# ============================================================================

var _interval := 3
var _backlash_turns := 2
var _jam_column := -1
var _turns := 0
var _last_pressure_turn := -1

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.current_room.gimmick_params if ctrl.current_room != null else {}
	_interval = maxi(1, int(p.get("interval", 3)))
	_backlash_turns = maxi(1, int(p.get("backlash_turns", 2)))
	_jam_column = int(p.get("jam_column", -1))
	_turns = 0
	_last_pressure_turn = -1
	ctrl.hud._log("🎴 庄家换牌：每 %d 回合注废 1 列并施加反噬（连续同符号受代价；换符号即结束）" % _interval)

func on_turn_begin(ctrl) -> void:
	_turns += 1
	if _turns % _interval != 0:
		if recovery_window(ctrl):
			ctrl.hud._log("🎴 洗牌间隙：本回合不再注废/反噬（输出窗口）")
		return
	_last_pressure_turn = _turns
	var col: int = _jam_column
	if col < 0:
		col = randi() % DuelController.REELS
	ctrl.pending_jam_reel = clampi(col, 0, DuelController.REELS - 1)
	ctrl.apply_debuff("backlash", _backlash_turns)
	ctrl.hud._log("🎴 庄家发牌：第 %d 列被注废；反噬生效 %d 回合" % [ctrl.pending_jam_reel + 1, _backlash_turns])

func recovery_window(_ctrl) -> bool:
	return _last_pressure_turn >= 0 and _turns == _last_pressure_turn + 1

func rhythm_window(_ctrl) -> String:
	if recovery_window(_ctrl):
		return "恢复"
	if _last_pressure_turn >= 0 and _turns == _last_pressure_turn:
		return "爆发"
	return "蓄势"
