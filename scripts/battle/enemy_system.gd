class_name EnemySystem
extends RefCounted

# enemy_system — 敌人回合系统（2026-08-09 从 duel_controller 拆分）
#
# 职责：执行敌人意图（take_turn：按意图类型分发效果）、清理意图、DoT 状态结算。
# 意图的「抽取/定义」在 StatusSystem（roll_intent），此处只负责「执行」。
# 新增意图类型（如给玩家挂 buff） = 在 take_turn 加一个分支 + 对应效果函数，controller 零改动。
#
# 状态共享：enemy_intent / pending_jam_reel / pending_lock_reel / pending_chaos / enemy_atk
# 仍由 DuelController 持有，本系统经 _ctrl 读写；伤害与 DoT 结算复用 CombatSystem。

var _ctrl  # DuelController


func _init(ctrl) -> void:
	_ctrl = ctrl


# 敌人回合主入口（玩家结算后调用）：执行预告的意图 → 清理 → 状态 DoT 结算。
func take_turn() -> void:
	var it: Dictionary = _ctrl.enemy_intent
	match it.get("type", "attack"):
		"attack", "heavy": _do_attack(it)
		"jam":             _do_jam()
		"lock":            _do_lock()
		"chaos":           _do_chaos()
		"none":            _ctrl.hud._log("敌人意图落空（已被净化）")
	_ctrl.enemy_intent = {}
	_ctrl.combat.tick_status()
	_ctrl.invalidate_state()   # 敌人攻击扣血/意图清空/DoT 结算


func _do_attack(it: Dictionary) -> void:
	_ctrl.combat.enemy_deal_damage(it.get("value", _ctrl.enemy_atk))


# 注废：下一轮随机一列被废铁占据（锁定时落实，见 ReelSystem.lock_reel）
func _do_jam() -> void:
	_ctrl.pending_jam_reel = randi() % DuelController.REELS
	_ctrl.hud._log("敌人注废 → 下一轮第 %d 列被废铁占据" % (_ctrl.pending_jam_reel + 1))


# 锁轮：下一轮随机一列固定不变（保留旋转前符号）
func _do_lock() -> void:
	_ctrl.pending_lock_reel = randi() % DuelController.REELS
	_ctrl.hud._log("敌人锁轮 → 下一轮第 %d 列固定不变" % (_ctrl.pending_lock_reel + 1))


# 乱权：下一轮权重被打乱（向整带注入废铁等比重削弱，见 ReelSystem.build_strips）
func _do_chaos() -> void:
	_ctrl.pending_chaos = true
	_ctrl.hud._log("敌人乱权 → 下一轮权重被打乱（优势符号被削弱）")
