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
	# 2026-11-12 Step 2：行动失效（裂石像破甲窗口）——消耗一次，跳过本次意图但照常结算 DoT。
	if int(_ctrl.enemy_stunned) > 0:
		_ctrl.enemy_stunned -= 1
		_ctrl.hud._log("🪨 崩解：本回合无法行动（破甲输出窗口）")
		_ctrl.enemy_intent = {}
		_ctrl.enemy_extra_attacks.clear()
		_ctrl.enemy_attack_poison = 0
		_ctrl.enemy_attack_pierce_pct = 0.0
		_ctrl.enemy_self_damage_after = 0
		_ctrl.combat.tick_status()
		_ctrl.invalidate_state()
		return
	var it: Dictionary = _ctrl.enemy_intent
	_ctrl.last_enemy_intent = it.duplicate(true)   # Step 3：供「重复上一意图」读取（复制，防后续改字典）
	match it.get("type", "attack"):
		"attack", "heavy": _do_attack(it)
		"jam":             _do_jam()
		"lock":            _do_lock()
		"chaos":           _do_chaos()
		"auto_stop":       _do_auto_stop()
		"none":            _ctrl.hud._log("敌人意图落空（已被净化）")
	_resolve_extra_attacks()
	_resolve_self_damage_after()
	_ctrl.enemy_intent = {}
	_ctrl.combat.tick_status()
	_ctrl.invalidate_state()   # 敌人攻击扣血/意图清空/DoT 结算


func _do_attack(it: Dictionary) -> void:
	var raw: int = int(it.get("value", _ctrl.enemy_atk))
	# 圣辉游侠：少量伤害直接穿透护盾（先扣，再走统一闸口结算剩余）
	var pct: float = float(_ctrl.enemy_attack_pierce_pct)
	_ctrl.enemy_attack_pierce_pct = 0.0
	if pct > 0.0:
		var pierce: int = int(round(float(raw) * pct))
		if pierce > 0:
			_ctrl.player_hp = maxi(0, int(_ctrl.player_hp) - pierce)
			_ctrl.hud._popup("🗡穿透 -%d" % pierce, Palette.POP_DAMAGE, _ctrl.hud._player_sprite_anchor())
			_ctrl.hud._log("🗡 穿透护盾：%d 点直接命中（本次攻击 %d 的 %d%%）" % [pierce, raw, int(round(pct * 100.0))])
	_ctrl.combat.enemy_deal_damage(raw)
	# 毒针群蝠：主攻击附带毒层
	if int(_ctrl.enemy_attack_poison) > 0:
		var stacks: int = int(_ctrl.enemy_attack_poison)
		_ctrl.enemy_attack_poison = 0
		_ctrl.player_status["poison"] = int(_ctrl.player_status.get("poison", 0)) + stacks
		_ctrl.hud._log("🧪 毒针：玩家中毒 +%d 层（共 %d）" % [stacks, int(_ctrl.player_status["poison"])])


# Step 3：一次行动的多段攻击（炎锋群蝠 / 毒针群蝠），逐段走统一伤害闸口。
func _resolve_extra_attacks() -> void:
	var list: Array = _ctrl.enemy_extra_attacks
	_ctrl.enemy_extra_attacks = []
	for item in list:
		var d: Dictionary = item
		var value: int = int(d.get("value", 0))
		if value <= 0:
			continue
		_ctrl.combat.enemy_deal_damage(value)
		var poison: int = int(d.get("poison", 0))
		if poison > 0:
			_ctrl.player_status["poison"] = int(_ctrl.player_status.get("poison", 0)) + poison
			_ctrl.hud._log("🧪 追加一击附带毒 +%d 层（共 %d）" % [poison, int(_ctrl.player_status["poison"])])


# Step 3：行动后自损（湮灭使徒）——走敌人 HP 直扣，不吃护甲，可被任何上限/下限钩子收口。
func _resolve_self_damage_after() -> void:
	var dmg: int = int(_ctrl.enemy_self_damage_after)
	_ctrl.enemy_self_damage_after = 0
	if dmg <= 0:
		return
	_ctrl.enemy_hp = maxi(0, int(_ctrl.enemy_hp) - dmg)
	_ctrl.hud._log("💥 反噬自身：%s -%d HP（剩余 %d）" % [_ctrl.enemy_name, dmg, int(_ctrl.enemy_hp)])


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


# 夺轮（2026-08-14 v2）：下一轮转轮自动停止——每跳自动停一列（落点随机，玩家无法目押停轮时机，
# 见 ReelSystem.on_spin_tick）+ 顺带注废 1 列（转轮完全失控），净化药剂可抵消
func _do_auto_stop() -> void:
	_ctrl.pending_auto_stop = true
	_ctrl.pending_jam_reel = randi() % DuelController.REELS
	_ctrl.hud._log("敌人夺轮 → 下一轮转轮自动停止并注入废铁（第 %d 列被占据）" % (_ctrl.pending_jam_reel + 1))
