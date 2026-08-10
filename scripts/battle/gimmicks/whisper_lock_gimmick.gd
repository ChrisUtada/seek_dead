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
var _phase2_hp_ratio := 0.0     # P2 触发阈值（0 = 单阶段）
var _phase2_lock_every := 2     # P2 锁轮周期
var _phase2_attack_mult := 1.8  # P2 攻击倍率
var _chaos_chance := 0.25       # P2 每回合乱权概率
var _turns := 0
var _phase2 := false            # 是否已进入 P2（一次性）

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.ROOMS[ctrl.room_index].gimmick_params if (ctrl.room_index >= 0 and ctrl.room_index < ctrl.ROOMS.size()) else {}
	_lock_every = int(p.get("lock_every", 3))
	_attack_mult = float(p.get("attack_mult", 1.5))
	_phase2_hp_ratio = float(p.get("phase2_hp_ratio", 0.0))
	_phase2_lock_every = int(p.get("phase2_lock_every", 2))
	_phase2_attack_mult = float(p.get("phase2_attack_mult", 1.8))
	_chaos_chance = float(p.get("phase2_chaos_chance", 0.25))
	_turns = 0
	_phase2 = false
	var phase_txt := ""
	if _phase2_hp_ratio > 0.0:
		phase_txt = "；HP<%d%% 进入疯狂呓语（乱权+锁轮加速）" % int(_phase2_hp_ratio * 100)
	ctrl.hud._log("🌀 呓语锁轮：每 %d 回合锁 1 列，本回合敌方攻击 ×%s%s" % [_lock_every, _attack_mult, phase_txt])

func on_turn_begin(ctrl) -> void:
	_turns += 1
	# P2 乱权呓语：每回合概率直置 pending_chaos（不占意图槽位，意图预告仍显示 attack/jam/lock）
	if _phase2 and _chaos_chance > 0.0 and randf() < _chaos_chance:
		ctrl.pending_chaos = true
		ctrl.hud._log("🌀 疯狂呓语：乱权降临（整带注废）")
	# 呓语锁轮：P2 周期更短、攻击更凶
	var every: int = _phase2_lock_every if _phase2 else _lock_every
	var mult: float = _phase2_attack_mult if _phase2 else _attack_mult
	if _turns % every == 0:
		var col = randi() % ctrl.REELS
		ctrl.pending_lock_reel = col
		ctrl.boss_atk_mult = mult
		ctrl.hud._log("🌀 呓语锁轮：第 %d 列被锁定，本回合敌方攻击 ×%s" % [col + 1, mult])

func on_damaged(ctrl, dmg: int) -> void:
	# P2 一次性触发：HP 跌破阈值进入疯狂呓语（不重复触发）
	if _phase2 or _phase2_hp_ratio <= 0.0:
		return
	if ctrl.enemy_hp <= int(float(ctrl.enemy_hp_max) * _phase2_hp_ratio):
		_phase2 = true
		ctrl.hud._log("🌀 疯狂呓语！乱权降临，锁轮加速（每 %d 回合），攻击 ×%s" % [_phase2_lock_every, _phase2_attack_mult])
		ctrl.hud._popup("🌀 疯狂呓语！", Palette.POP_STATUS, ctrl.hud._enemy_sprite_anchor())
