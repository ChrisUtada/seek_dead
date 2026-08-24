# TurnFlow — 转轮回合流（P2 架构还债，2026-08-24 自 duel_controller 迁入）
# 运行时经 duel_controller preload 实例化（不注册全局 class_name——headless 测试环境不刷新类缓存）。
# 职责：SPIN 主流程协程（旋转→按停→结算→敌人行动→下回合预告，含闪回暴走重转）、
#       回合开始结算（持续效果衰减/意图声明/冻结声明）、免费重转、非暴力和解。
# 时序演出用 _ctrl.get_tree() 计时器；战斗数值全部在 CombatSystem（evaluate/take_turn）。
# 状态归属不变：_busy / game_state / pending_* / charge_points 等仍由 controller 持有。

var _ctrl  # DuelController


func _init(ctrl) -> void:
	_ctrl = ctrl


# 回合开始：持续效果衰减（frozen 先衰减再挂新层）→ 敌人声明意图 → gimmick 回合钩子 → 冻结列声明。
func begin_player_turn() -> void:
	if _ctrl.game_state != _ctrl.FlowState.PLAYING:
		return
	_ctrl.turn_count += 1
	# 深渊凝视（信物）：每回合开始元素充能 +N（不触发爆发，爆发仍由克制命中驱动）
	if _ctrl.charm_charge_start > 0 and _ctrl.deprived_level < 1:
		_ctrl.charge_points += _ctrl.charm_charge_start
	_ctrl.locked_consumable_slot = -1   # 天平审判官：律法锁槽仅锁 1 回合，新回合开始即解锁
	_ctrl.hud._refresh_consumable_panel()
	_ctrl.hud._log("▶ 回合 %d 开始" % _ctrl.turn_count)
	if _ctrl.player_frost > 0:
		var sd: StatusDef = _ctrl._status_def("frozen")   # 单侧性纪律：玩家侧冻结 = frozen（frost 回归纯敌人侧）
		_ctrl.player_frost = max(0, _ctrl.player_frost - (sd.decay if sd != null else 1))
		_ctrl.frozen_cols.clear()
	_ctrl.enemy_intent = _ctrl._roll_intent(_ctrl.ROOMS[_ctrl.room_index] if _ctrl.room_index >= 0 and _ctrl.room_index < _ctrl.ROOMS.size() else null)
	# 每玩家回合重置 BOSS 倍率，再由 gimmick 钩子按本回合状态设定
	_ctrl.boss_atk_mult = 1.0
	if _ctrl.current_gimmick != null:
		_ctrl.current_gimmick.on_turn_begin(_ctrl)
	# T30 寒霜侵蚀：回合一开始敌人即冻结（frost 挂上后立即声明冻结列，spin 前玩家可见蓝框提示）
	_ctrl.frozen_cols = _ctrl.combat.pick_frozen_cols()
	# UX：干扰/锁轮列标记（敌人上回合已声明 pending_*，spin 前刷新格子显示红/黄框）
	if not _ctrl.frozen_cols.is_empty() or _ctrl.pending_jam_reel >= 0 or _ctrl.pending_lock_reel >= 0:
		if not _ctrl.frozen_cols.is_empty():
			var cols_txt := PackedStringArray()
			for c in _ctrl.frozen_cols:
				cols_txt.append(str(c + 1))
			_ctrl.hud._log("❄ 寒霜侵蚀：第 %s 列被冰封，本轮无法转动（清净药剂可解）" % "/".join(cols_txt))
		# 冻结列不参与 tick/按停刷新——此处手动刷新格子，spin 前即显示边框
		for r in _ctrl.REELS:
			_ctrl.hud._refresh_cell(r, 0)
	_ctrl.invalidate_state()


# SPIN 主流程：旋转→(闪回暴走强制重转)→结算→敌人行动→胜负判定→预告下回合意图。
func on_spin_pressed() -> void:
	if _ctrl.in_loadout or _ctrl.in_interroom or _ctrl.game_state != _ctrl.FlowState.PLAYING or _ctrl._busy:
		return
	_ctrl._busy = true
	# 阶段 0：旋转（实体转轮带滚动，玩家按停止键锁定落点；不立即结算）
	_ctrl.reel_system.begin_spin()
	await _ctrl.reel_system.spin_finished
	await _ctrl.get_tree().create_timer(0.15).timeout
	# 深渊监视者 P2 闪回暴走：停轮后有概率强制重转（第一次停轮作废，玩家二次按停；结算只跑一次）
	if _ctrl.current_gimmick != null and _ctrl.current_gimmick.consume_flashback():
		_ctrl.hud._log("🕳 闪回暴走：噩梦闪回——停轮作废，强制重转！")
		_ctrl.reel_system.begin_spin()
		await _ctrl.reel_system.spin_finished
		await _ctrl.get_tree().create_timer(0.15).timeout
	# 阶段 1+2：结算（先防御/增益/状态，后攻击；含飘字）
	await _ctrl.combat.evaluate()
	if _ctrl.peaceful_win:
		_ctrl._busy = false
		return
	if _ctrl.enemy_hp <= 0:
		_ctrl.hud._log("★ 击败 %s！" % _ctrl.enemy_name)
		_ctrl.game_state = _ctrl.FlowState.WON
		_ctrl.invalidate_state()
		_ctrl.hud._show_reward_screen(_ctrl._is_boss_room(_ctrl.room_index))
		_ctrl.hud._refresh_meta()
		_ctrl._busy = false
		return

	# 阶段 3：敌人行动（先让玩家看清敌人刚掉的血）
	await _ctrl.get_tree().create_timer(0.20).timeout
	_ctrl.enemy_system.take_turn()
	_ctrl.hud._refresh_meta()
	await _ctrl.get_tree().create_timer(0.35).timeout
	if _ctrl.enemy_hp <= 0:
		# 敌人可能在自身回合被状态 DoT 结算致死
		_ctrl.hud._log("★ 击败 %s！（状态结算）" % _ctrl.enemy_name)
		_ctrl.game_state = _ctrl.FlowState.WON
		_ctrl.invalidate_state()
		_ctrl.hud._show_reward_screen(_ctrl._is_boss_room(_ctrl.room_index))
		_ctrl._busy = false
		return
	if _ctrl.player_hp <= 0:
		_ctrl.hud._log("✖ 你被 %s 击倒。" % _ctrl.enemy_name)
		_ctrl.game_state = _ctrl.FlowState.LOST
		_ctrl.invalidate_state()
		_ctrl.hud._show_overlay("✖ 失败\n你倒在了 %s 面前" % _ctrl.enemy_name, "返回整备 ▶")
		_ctrl.hud._refresh_meta()
		_ctrl._busy = false
		return

	await _ctrl.get_tree().create_timer(0.20).timeout
	# 阶段 4：预告下一回合意图
	begin_player_turn()
	_ctrl.hud._refresh_meta()
	_ctrl._busy = false


# 重转卷轴：免费重转一次（不触发敌人回合）。
func free_spin() -> void:
	if _ctrl._busy:
		return
	_ctrl._busy = true
	_ctrl.reel_system.begin_spin()
	await _ctrl.reel_system.spin_finished
	await _ctrl.get_tree().create_timer(0.15).timeout
	await _ctrl.combat.evaluate()
	if _ctrl.enemy_hp <= 0:
		_ctrl.hud._log("★ 重转触发击败 %s！" % _ctrl.enemy_name)
		_ctrl.game_state = _ctrl.FlowState.WON
		_ctrl.invalidate_state()
		_ctrl.hud._show_reward_screen(_ctrl._is_boss_room(_ctrl.room_index))
	_ctrl.hud._refresh_meta()
	_ctrl._busy = false


# 勇者的阴影 P3：非暴力和解通关（gimmick 达成三连/治疗符号/恢复净化消耗品时调用）。
func resolve_peaceful_win() -> void:
	if _ctrl.peaceful_win or _ctrl.game_state != _ctrl.FlowState.PLAYING:
		return
	_ctrl.peaceful_win = true
	_ctrl.game_state = _ctrl.FlowState.WON
	_ctrl.hud._log("🤝 勇者放下武器，与阴影握手言和——非暴力通关！")
	_ctrl.hud._popup("🤝 和解！", Palette.POP_HEAL, _ctrl.hud._player_sprite_anchor())
	_ctrl.hud._show_reward_screen(_ctrl._is_boss_room(_ctrl.room_index))
	_ctrl.hud._refresh_meta()
	_ctrl._busy = false
	_ctrl.invalidate_state()