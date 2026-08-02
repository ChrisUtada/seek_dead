extends BossGimmick

# 幕一 BOSS·锈蚀傀儡「熔铸护甲」：
# 每 2 回合叠 1 层减伤（20%/层，最多 3 层=60%，地板×0.4），玩家打出 special 三连清空全部层数。
# 设计意图：教玩家主动追求 special 三连。

const MAX_STACKS := 3
const REDUCTION_PER_STACK := 0.20       # 每层减伤 20%（三层=60%，地板×0.4；三连清层回到×1.0 = 2.5倍跳）

var _stacks := 0
var _turns := 0

func on_room_start(ctrl) -> void:
	_stacks = 0
	_turns = 0
	ctrl.boss_dmg_mult = 1.0
	ctrl.hud._log("🛡 熔铸护甲展开：每 2 回合叠加一层减伤（上限 %d 层）" % MAX_STACKS)

func on_turn_begin(ctrl) -> void:
	_turns += 1
	if _turns % 2 == 0 and _stacks < MAX_STACKS:
		_stacks += 1
		ctrl.hud._log("🛡 熔铸护甲 +1 层（%d/%d，玩家伤害 ×%s）" % [_stacks, MAX_STACKS, _fmt(1.0 - REDUCTION_PER_STACK * _stacks)])
	ctrl.boss_dmg_mult = max(0.4, 1.0 - REDUCTION_PER_STACK * _stacks)

func on_special_triple(ctrl) -> void:
	if _stacks > 0:
		ctrl.hud._log("💥 special 三连击碎熔铸护甲！减伤层数清空")
		_stacks = 0
		ctrl.boss_dmg_mult = 1.0

func _fmt(m: float) -> String:
	return "%.2f" % m
