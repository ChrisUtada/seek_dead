# RoomFlow — 房间推进 / 间歇态 / 元进度与铁砧编排（P2 架构还债，2026-08-24 自 duel_controller 迁入）
# 运行时经 duel_controller preload 实例化（不注册全局 class_name——headless 测试环境不刷新类缓存）。
# 职责：M1 战后成长三槽编排（历练/熟练结算 → 三槽选择 → 铁砧点/金币/drops → 间歇）、
#       间歇态抽屉、战败回整备、铁砧摇奖入口。controller 留单行转发器，HUD 信号连接面不变。
# 状态归属不变：in_interroom / game_state / meta 等仍由 controller 持有，经 _ctrl 读写。

var _ctrl  # DuelController


func _init(ctrl) -> void:
	_ctrl = ctrl


# 清房推进编排（M1 战后成长）：
# 普通 / 精英胜利 → begin_post_battle（先结算历练/熟练，再生成三槽屏）
# → 玩家选一项 → finish_room / finish_post_battle（应用 → 铁砧/金币/掉落 → 间歇或元进度）。
# BOSS 胜利不走三槽屏：保留专属战利品；未处理的成长留在队列，进入下一战斗房的成长位。
var post_battle_active := false
var _post_offer: Array = []


func begin_post_battle() -> void:
	if post_battle_active:
		return
	post_battle_active = true
	_settle_victory()
	_post_offer = _ctrl._post_battle.build(_current_kind())
	_ctrl.hud.show_post_battle(_post_offer, _growth_summary_text())


func finish_room(apply_fn: Callable, is_boss: bool) -> void:
	if post_battle_active:
		_finish_post_battle(apply_fn)
		return
	_ctrl.hud.hide_reward_screen()
	_settle_victory()
	if apply_fn.is_valid():
		apply_fn.call()
	_award_victory(is_boss)
	_after_victory()


func _finish_post_battle(apply_fn: Callable) -> void:
	post_battle_active = false
	_post_offer = []
	_ctrl.hud.hide_reward_screen()
	if apply_fn.is_valid():
		apply_fn.call()
	_award_victory(false)
	_after_victory()


# 房间胜利的成长节奏：历练 → 熟练（触发项进入 PostBattleSystem 的成长队列）。
func _settle_victory() -> void:
	if _ctrl._telemetry != null:
		_ctrl._telemetry.on_room_clear()   # M1-06：清房耗时
	var kind := _current_kind()
	_ctrl.growth.grant_room_xp(kind)   # M2-01：房间胜利发放历练经验（升级即时入账）
	_ctrl.mastery.settle_room(kind)    # M2-02：样板武器按本房有效结算累计熟练


# 与选择无关的清房收益：铁砧点 / 金币 / T8 掉落。
func _award_victory(is_boss: bool) -> void:
	_ctrl._anvil_system.award_meta(is_boss)    # M5：房间通关发放铁砧点数
	_ctrl._meta_store.award_gold(is_boss)    # S6+S8：清房金币 + 利息
	_ctrl._reward_system.apply_room_drops()   # T8：普通房 12% 掉消耗品 / 精英房保底护符（BOSS 走自身战利品）
	if is_boss and _ctrl._career != null:
		_ctrl._career.on_boss_cleared()        # G6-01：BOSS 通关 → 一次性生涯成就（只记录，不发属性）
	if is_boss and _ctrl._codex != null:
		_ctrl._codex.record_run(_ctrl.mastery)   # G6-04：记录本局武器最高熟练与铭印组合


func _after_victory() -> void:
	if _ctrl._is_run_final(_ctrl.room_index):
		log_telemetry()                               # M1-06：整局结束打印遥测
		_ctrl._reward_system.show_meta_choice()        # 通关整局（最终 BOSS）→元进度结算（持久生效）→回整备
	elif _ctrl.node_mode:
		# M2：棋盘模式胜利后回棋盘待机；下一房预告由可见棋盘替代，不进入线性间歇态。
		_ctrl.board.return_to_board()
	else:
		enter_interroom()   # opt-in 商店：进入房间歇态（🛒 可选，▶ 下一房继续）
	_ctrl.hud._refresh_meta()   # 幂等兜底：各子系统方法已自包含刷新，防编排层遗漏


func _current_kind() -> String:
	if _ctrl.room_index < 0 or _ctrl.room_index >= _ctrl.ROOMS.size():
		return "normal"
	return String(_ctrl.ROOMS[_ctrl.room_index].kind)


# 当前三槽候选（测试 / 探针只读）。
func post_offer() -> Array:
	return _post_offer


# 成长位是否为真实成长触发（技艺 / 铭印）；fallback 对策不算。
func post_battle_growth_candidate() -> Dictionary:
	for c in _post_offer:
		if String(c.get("slot", "")) == "growth" and String(c.get("kind", "")) in ["perk", "imprint"]:
			return c
	return {}


func post_battle_has_growth() -> bool:
	return not post_battle_growth_candidate().is_empty()


# 测试 / bot 用：按槽位偏好自动选择一项并确认（与玩家点卡走同一套应用路径）。
# want_growth_id 非空时，只接受该 id 的成长卡（探针按铭印类型分组用）。
func auto_pick_post_battle(prefer: Array = ["growth", "supply", "build"], want_growth_id: String = "") -> bool:
	if not post_battle_active:
		return false
	var chosen: Dictionary = {}
	for slot in prefer:
		for cand in _post_offer:
			if String(cand.get("slot", "")) != String(slot):
				continue
			if String(slot) == "growth" and want_growth_id != "":
				if String(cand.get("kind", "")) not in ["perk", "imprint"]:
					continue
				if String(cand.get("growth_id", "")) != want_growth_id:
					continue
			chosen = cand
			break
		if not chosen.is_empty():
			break
	if chosen.is_empty():
		return false
	if String(chosen.get("kind", "")) == "reward":
		_ctrl._on_reward_chosen(String(chosen["reward"].id), int(chosen["index"]))
	else:
		_ctrl._on_post_battle_growth_chosen(chosen)
	return true


# P0-2：成长摘要（结算页头 + 确认后日志），让「本局成长方向」可复述。
func _growth_summary_text() -> String:
	var bits: Array[String] = [_ctrl.growth.progress_text()]
	if not _ctrl.growth.perk_ids.is_empty():
		bits.append(_ctrl.growth.summary_line())
	if _ctrl.mastery.imprint_total() > 0:
		bits.append(_ctrl.mastery.summary_line())
	return "本局成长：" + " ｜ ".join(bits)


# M1-06：局末遥测输出（真人评测指标；只打印/记日志，不改变结算）
func log_telemetry() -> void:
	if _ctrl._telemetry == null:
		return
	var txt: String = _ctrl._telemetry.summary_text()
	print("TELEMETRY|" + txt)
	_ctrl.hud._log("📊 本局遥测：" + txt)


func enter_interroom(roll_shop: bool = true) -> void:
	if _ctrl.node_mode:
		_ctrl.board.return_to_board()   # M2：棋盘模式没有线性间歇态
		return
	_ctrl.in_interroom = true
	_ctrl._shop_system.reroll_used = 0   # 2026-08-09：刷新次数随房间歇期清零（价格重新从 reroll_base 起）
	_ctrl.hud._hide_overlay()    # 防御性：确保胜利弹层已关闭，避免其遮挡/重触发
	_ctrl.hud.set_interroom_enabled(true)
	if roll_shop:
		# 每房间歇期货架生成一次——反复开关商店不刷新（防「买完再开刷货架」）
		_ctrl._roll_shop()
	_ctrl.invalidate_state()


# 🛒 按钮在抽屉展开/收起间切换。
func on_shop_requested() -> void:
	if not _ctrl.in_interroom:
		return
	if _ctrl.hud.shop_screen_is_open():
		_ctrl.hud.hide_shop_screen()
		_ctrl.hud.set_shop_button_text("🛒 商店")
	else:
		_ctrl.hud._show_shop_screen()
		_ctrl.hud.set_shop_button_text("🛒 收起")


func on_next_room_pressed() -> void:
	# 若抽屉仍展开，进下一房前先收起，避免遮挡新房间
	if _ctrl.hud.shop_screen_is_open():
		_ctrl.hud.hide_shop_screen()
		_ctrl.hud.set_shop_button_text("🛒 商店")
	_ctrl.in_interroom = false
	_ctrl.hud.set_interroom_enabled(false)
	if _ctrl.node_mode:
		_ctrl.board.return_to_board()   # 防御：棋盘模式下一房由棋盘选择，不线性递增
		return
	_ctrl._start_room(_ctrl.room_index + 1)


func on_shop_leave_pressed() -> void:
	_ctrl.hud.hide_shop_screen()
	_ctrl.hud.set_shop_button_text("🛒 商店")
	if _ctrl.node_mode:
		_ctrl.in_interroom = false
		_ctrl.board.return_to_board()   # M2：商店格离开后回棋盘，节点已消耗
		return
	enter_interroom(false)   # 离开商店回房间歇态：不重滚货架（每房一次，防刷商店）


# 元进度确认：应用 + 落盘（子系统内）→ 回整备。
# 2026-10-31（P0）：原实现直接 _full_reset() 开新一局，导致「通关 / 一局结束」没有落点——
# 试玩者看不到结束信号，且整备 / 铁砧 / 图鉴只能靠战败进入，刚攒的铁砧点数无从花掉。
# 改为回整备：换配装、花铁砧点、看图鉴，确认后由 confirm_loadout → full_reset 开新局。
func on_meta_choice_chosen(opt: Dictionary) -> void:
	_ctrl.hud.hide_meta_screen()
	_ctrl._reward_system.on_meta_choice_chosen(opt)   # 元进度应用 + 落盘（_save_meta 在子系统内）
	_ctrl.hud._refresh_meta()
	return_to_loadout()


# 失败弹层按钮：关闭弹层；LOST → 回整备开新局。
func on_overlay_button_pressed() -> void:
	_ctrl.hud._hide_overlay()    # 关闭失败弹层（通关已改走 reward→meta 直链，无 cleared 弹层）
	if _ctrl.game_state == _ctrl.FlowState.LOST:
		return_to_loadout()


# 战败回整备：落盘保进度 → 清上局勾选/腰带/成长 → 解除终态 → 重开整备页。
func return_to_loadout() -> void:
	_ctrl._meta_store.save_meta()
	# 泛型数组属性跨对象只能 clear()/assign()，不能整体赋 []（运行时类型检查会拒绝）
	_ctrl.selected_loadout.clear()
	_ctrl.selected_skills.clear()
	_ctrl.selected_charms.clear()
	_ctrl.selected_consumables.clear()
	_ctrl.consumable_slots.clear()
	_ctrl.game_state = _ctrl.FlowState.PLAYING   # 解除 lost 终态，避免整备/铁砧界面误读终局
	_ctrl.hud.hide_board_screen(false)           # M2：战败 / 通关回整备时收起棋盘
	_ctrl.hud._show_loadout_screen()
	_ctrl.invalidate_state()


# 铁砧纯 gacha 入口：委托 AnvilSystem 完成扣点→摇→结算→写 last_anvil_drops→落盘。
func on_anvil_roll_pressed() -> void:
	var drops = _ctrl._anvil_system.roll_anvil()
	if drops.is_empty():
		return   # 点数不足（已在子系统内日志）
	# 注意：不在此处刷新铁砧屏——由 anvil_screen 旋转动画收尾后自行 refresh
	_ctrl.hud._refresh_meta()
	_ctrl.hud._refresh_loadout_cards()
	_ctrl.hud._update_loadout_anvil()


func on_anvil_back_pressed() -> void:
	_ctrl.hud.hide_anvil_screen()
	_ctrl.hud._show_loadout_screen()   # 铁砧返回后重建整备 2D 场景（loadout 内会 hud.hide()）
	_ctrl.hud._update_loadout_anvil()