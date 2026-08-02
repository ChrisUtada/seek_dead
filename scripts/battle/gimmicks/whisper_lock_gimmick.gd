extends BossGimmick

# 幕二 BOSS·呓语教徒「呓语锁轮」：
# 每 3 回合必锁 1 列（直接置 pending_lock_reel，无视抗扰减免）且当回合敌人攻击 ×1.5。
# 设计意图：逼玩家保留净化次数 / 应对锁轮。

const LOCK_EVERY := 3
const ATTACK_MULT := 1.5

var _turns := 0

func on_room_start(ctrl) -> void:
	_turns = 0
	ctrl.hud._log("🔒 呓语回荡：每 %d 回合必锁 1 列，当回合敌人攻击 ×%s" % [LOCK_EVERY, ATTACK_MULT])

func on_turn_begin(ctrl) -> void:
	_turns += 1
	if _turns % LOCK_EVERY == 0:
		var col = randi() % ctrl.REELS
		ctrl.pending_lock_reel = col
		ctrl.boss_atk_mult = ATTACK_MULT
		ctrl.hud._log("🔒 呓语锁轮！第 %d 列被锁定，本回合敌人攻击 ×%s" % [col + 1, ATTACK_MULT])
