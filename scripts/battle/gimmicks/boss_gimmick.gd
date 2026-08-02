class_name BossGimmick
extends Resource

# S10 T2：BOSS 专属机制基类。
# 每个 BOSS 一个子类，覆写下列钩子；duel_controller 在 BOSS 房 _start_room 时
# 实例化对应脚本（RoomData.gimmick_script）并赋值 current_gimmick，
# 非 BOSS 房 current_gimmick = null，所有钩子调用处均已显式判空跳过。
# 钩子参数 ctrl = DuelController 实例（动态访问其字段/方法，故参数不标类型以保持动态访问）。

# 进入 BOSS 房时调用一次（清状态、打开场日志）
func on_room_start(ctrl) -> void:
	pass

# 每个玩家回合开始时调用（推栈/锁轮/注废铁等逐回合效果）
func on_turn_begin(ctrl) -> void:
	pass

# 敌人受到玩家伤害后调用（dmg = 本次结算造成的总伤害）
func on_damaged(ctrl, dmg: int) -> void:
	pass

# 玩家打出 special 三连时调用（rust_armor 等据此清层数）
func on_special_triple(ctrl) -> void:
	pass
