extends BossGimmick

const ICON := "🛡🔒"

# ============================================================================
# ACT3 精英·圣盾守关（Step 4，计划 §7 替换原深渊注废复用）
# 触发：入场 + 每 4 回合
# 效果：入场护甲；周期补甲 + 锁 1 列
# 持续/结束：次回合恢复（锁列本轮后解除）
# 应对：破甲、净化、间隙输出
# 参数：armor / per_stack / interval / lock_column
# ============================================================================

var _armor := 20
var _per_stack := 10
var _interval := 4
var _lock_column := -1
var _turns := 0
var _last_pressure_turn := -1

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.current_room.gimmick_params if ctrl.current_room != null else {}
	_armor = int(p.get("armor", 20))
	_per_stack = int(p.get("per_stack", 10))
	_interval = maxi(1, int(p.get("interval", 4)))
	_lock_column = int(p.get("lock_column", -1))
	_turns = 0
	_last_pressure_turn = -1
	ctrl.enemy_armor_max += _armor
	ctrl.enemy_armor += _armor
	ctrl.hud._log("🛡 圣盾展开：入场 %d 护甲；每 %d 回合补 %d 甲并锁 1 列（次回合恢复）" % [
		_armor, _interval, _per_stack])

func on_turn_begin(ctrl) -> void:
	_turns += 1
	if _turns % _interval != 0:
		if recovery_window(ctrl):
			ctrl.hud._log("🛡 守关间隙：本回合不补甲/不锁列，破甲与输出窗口")
		return
	_last_pressure_turn = _turns
	ctrl.enemy_armor_max += _per_stack
	ctrl.enemy_armor += _per_stack
	var col: int = _lock_column
	if col < 0:
		col = randi() % DuelController.REELS
	ctrl.pending_lock_reel = clampi(col, 0, DuelController.REELS - 1)
	ctrl.hud._log("⚠ 圣盾爆发：补 %d 护甲（现 %d），第 %d 列被锁定" % [
		_per_stack, int(ctrl.enemy_armor), ctrl.pending_lock_reel + 1])

func recovery_window(_ctrl) -> bool:
	return _last_pressure_turn >= 0 and _turns == _last_pressure_turn + 1

func rhythm_window(_ctrl) -> String:
	if recovery_window(_ctrl):
		return "恢复"
	if _last_pressure_turn >= 0 and _turns == _last_pressure_turn:
		return "爆发"
	return "蓄势"
