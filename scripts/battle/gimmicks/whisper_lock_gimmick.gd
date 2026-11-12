extends BossGimmick

const ICON := "🌀"   # 呓语锁轮/迷宫低语者（battle_hud 经 get_script_constant_map 读取）

# 幕二 BOSS：呓语锁轮（教学·单阶段）→ 迷宫低语者（双阶段·T10 阶段化示例）。
# 呓语锁轮：每 lock_every 回合锁 1 列（pending_lock_reel，目押提前按停应对），该回合攻击 ×attack_mult。
# 双阶段（迷宫低语者，gimmick_params 传 phase2_* 启用）：
#   P1 呓语不绝：上述锁轮节奏（默认每 3 回合 ×1.5）
#   P2 疯狂呓语（on_damaged 检测 HP < phase2_hp_ratio 一次性触发）：
#       锁轮加速（phase2_lock_every）+ 攻击强化（phase2_attack_mult）+ 每回合 phase2_chaos_chance 概率乱权（pending_chaos，不占意图槽位）
# 缺省 = 单阶段（phase2_hp_ratio=0 永不触发）——呓语教徒（教学位）.tres 零改动。
# 参数经 RoomData.gimmick_params（T24），缺省值见各字段注释。

var _lock_every := 3            # P1 锁轮周期（回合）
var _attack_mult := 1.5         # P1 锁轮回合攻击倍率
var _first_lock_turn := 0       # Step 5（D6）：P1 首次锁轮提前到第 N 回合（0 = 按 lock_every）
var _phase2_hp_ratio := 0.0     # P2 触发阈值（0 = 单阶段）
var _phase2_lock_every := 2     # P2 锁轮周期
var _phase2_attack_mult := 1.8  # P2 攻击倍率
var _chaos_chance := 0.25       # P2 每回合乱权概率
# —— Step 4 精英参数化（默认全关，BOSS/旧精英行为不变）——
var _same_col := false          # 深渊咏者：每次都锁同一列
var _lock_column := -1          # 指定列（-1 = 首次随机后固定）
var _jam_on_lock := false       # 深渊咒师（D4）：锁列同时向该列注 1 废铁
var _triple_counter := false    # 深渊咏者：用锁定符号三连后，下回合攻击降低
var _counter_atk_mult := 0.7
var _lock_col := -1
var _counter_next := false
var _turns := 0
var _phase2 := false            # 是否已进入 P2（一次性）
# Step 5：锁轮后的下一回合是真实间隙——不追加锁轮/乱权，供玩家净化与输出。
var _recovery_next := false
var _recovering := false

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.ROOMS[ctrl.room_index].gimmick_params if (ctrl.room_index >= 0 and ctrl.room_index < ctrl.ROOMS.size()) else {}
	_lock_every = int(p.get("lock_every", 3))
	_attack_mult = float(p.get("attack_mult", 1.5))
	_first_lock_turn = int(p.get("first_lock_turn", 0))
	_phase2_hp_ratio = float(p.get("phase2_hp_ratio", 0.0))
	_phase2_lock_every = int(p.get("phase2_lock_every", 2))
	_phase2_attack_mult = float(p.get("phase2_attack_mult", 1.8))
	_chaos_chance = float(p.get("phase2_chaos_chance", 0.25))
	_same_col = bool(p.get("same_col", false))
	_lock_column = int(p.get("lock_column", -1))
	_jam_on_lock = bool(p.get("jam_on_lock", false))
	_triple_counter = bool(p.get("triple_counter", false))
	_counter_atk_mult = float(p.get("counter_atk_mult", 0.7))
	_lock_col = -1
	_counter_next = false
	_turns = 0
	_phase2 = false
	_recovery_next = false
	_recovering = false
	var phase_txt := ""
	if _phase2_hp_ratio > 0.0:
		phase_txt = "；HP<%d%% 进入疯狂呓语（乱权+锁轮加速）" % int(_phase2_hp_ratio * 100)
	ctrl.hud._log("🌀 呓语锁轮：每 %d 回合锁 1 列，本回合敌方攻击 ×%s%s" % [_lock_every, _attack_mult, phase_txt])

func on_turn_begin(ctrl) -> void:
	_turns += 1
	_recovering = _recovery_next
	_recovery_next = false
	# P2 乱权呓语：每回合概率直置 pending_chaos（不占意图槽位，意图预告仍显示 attack/jam/lock）
	# Step 5：锁轮间隙不追加乱权，保证「锁轮后不追加其他新干扰」。
	if _phase2 and not _recovering and _chaos_chance > 0.0 and randf() < _chaos_chance:
		ctrl.pending_chaos = true
		ctrl.hud._log("🌀 疯狂呓语：乱权降临（整带注废）")
	# 呓语锁轮：P2 周期更短、攻击更凶；锁轮后的下一回合留间隙。
	var every: int = _phase2_lock_every if _phase2 else _lock_every
	var mult: float = _phase2_attack_mult if _phase2 else _attack_mult
	if not _recovering and _lock_due(every):
		var col: int = randi() % ctrl.REELS
		if _same_col:
			if _lock_col < 0:
				_lock_col = clampi(_lock_column, 0, ctrl.REELS - 1) if _lock_column >= 0 else col
			col = _lock_col
		ctrl.pending_lock_reel = col
		ctrl.boss_atk_mult = mult
		_recovery_next = true
		ctrl.hud._log("🌀 呓语锁轮：第 %d 列被锁定，本回合敌方攻击 ×%s" % [col + 1, mult])
		if _jam_on_lock:
			_jam_column_strip(ctrl, col)
	if _recovering:
		ctrl.hud._log("🌀 锁轮间隙：本回合不追加锁轮/乱权（净化与输出窗口）")
	# 深渊咏者：上一次三连反制的弱化在本回合落地
	if _counter_next:
		_counter_next = false
		ctrl.boss_atk_mult = minf(float(ctrl.boss_atk_mult), _counter_atk_mult)
		ctrl.hud._log("🌀 咏者失声：三连反制生效，本回合敌方攻击 ×%s" % _counter_atk_mult)


# Step 5（D6）：P1 可把首次锁轮提前（呓语教徒第 2 回合），之后仍按周期；P2 不受影响。
func _lock_due(every: int) -> bool:
	if not _phase2 and _first_lock_turn > 0:
		if _turns == _first_lock_turn:
			return true
		return _turns > _first_lock_turn and (_turns - _first_lock_turn) % every == 0
	return _turns % every == 0


# 深渊咏者：玩家用「被锁列的中心符号」完成三连 → 下一回合攻击降低（一次性）。
func on_special_triple(ctrl) -> void:
	if not _triple_counter or _counter_next:
		return
	var col: int = int(ctrl.pending_lock_reel)
	if col < 0 or col >= DuelController.REELS:
		return
	if ctrl.grid.size() <= col or ctrl.grid[col].size() == 0:
		return
	var locked = ctrl.grid[col][0]
	if locked == null:
		return
	var same := 0
	for r in DuelController.REELS:
		if ctrl.grid.size() > r and ctrl.grid[r].size() > 0 and ctrl.grid[r][0] == locked:
			same += 1
	if same < 3:
		return
	_counter_next = true
	ctrl.hud._log("🌀 三连反制：锁定符号成线，下一回合咏者攻击降低")


# 把 1 格废铁注入该列转轮带（内容改变，但保留本轮锁定的符号；next spin 起生效）。
func _jam_column_strip(ctrl, col: int) -> void:
	var strips: Array = ctrl.reel_system.reel_strips
	if strips.size() <= col or strips[col].is_empty():
		return
	var idx: int = randi() % strips[col].size()
	strips[col].insert(idx, [DuelController.TRASH_SYMBOL, "none"])
	ctrl.hud._log("🗑 咒师注废：第 %d 列转轮带 +1 废铁（该列后续更脏）" % (col + 1))

func on_damaged(ctrl, _dmg: int) -> void:
	# P2 一次性触发：HP 跌破阈值进入疯狂呓语（不重复触发）
	if _phase2 or _phase2_hp_ratio <= 0.0:
		return
	if ctrl.enemy_hp <= int(float(ctrl.enemy_hp_max) * _phase2_hp_ratio):
		_phase2 = true
		ctrl.hud._log("🌀 疯狂呓语！乱权降临，锁轮加速（每 %d 回合），攻击 ×%s" % [_phase2_lock_every, _phase2_attack_mult])
		ctrl.hud._popup("🌀 疯狂呓语！", Palette.POP_STATUS, ctrl.hud._enemy_sprite_anchor())


func recovery_window(_ctrl) -> bool:
	return _recovering


func rhythm_window(_ctrl) -> String:
	return "恢复" if _recovering else ""


func recovery_title(_ctrl) -> String:
	return "锁轮间隙"


func recovery_detail(_ctrl) -> String:
	return "本回合不追加锁轮或乱权；可净化、治疗或利用锁符间隙输出。"
