extends BossGimmick

# 幕一 BOSS·锈蚀傀儡「熔铸护甲」：
# 护甲为扁平池（先破甲后掉血，见 DuelController._apply_enemy_damage）；
# 每 2 回合叠 1 层护甲（每层 +ARMOR_PER_STACK，上限 MAX_STACKS 层），叠加在 RoomData.armor 之上。
# 玩家打出 special 三连清空全部护甲（由 DuelController._on_counter("special") 统一处理）。
# 设计意图：教玩家主动追求 special 三连 / 用穿透符号破甲（RPG 式破甲机制）。

const MAX_STACKS := 3
const ARMOR_PER_STACK := 8        # 每层护甲点数（三层 = +24，叠加在 RoomData.armor 之上）

var _stacks := 0
var _turns := 0

func on_room_start(ctrl) -> void:
	_stacks = 0
	_turns = 0
	ctrl.hud._log("🛡 熔铸护甲展开：每 2 回合叠加一层护甲（上限 %d 层）" % MAX_STACKS)

func on_turn_begin(ctrl) -> void:
	_turns += 1
	if _turns % 2 == 0 and _stacks < MAX_STACKS:
		_stacks += 1
		ctrl.enemy_armor_max += ARMOR_PER_STACK
		ctrl.enemy_armor += ARMOR_PER_STACK
		ctrl.hud._log("🛡 熔铸护甲 +%d（%d/%d 层，护甲 %d/%d）" % [ARMOR_PER_STACK, _stacks, MAX_STACKS, int(ctrl.enemy_armor), int(ctrl.enemy_armor_max)])
	# 护甲清空由 DuelController._on_counter("special") 统一处理（special 三连），此处不再重复
