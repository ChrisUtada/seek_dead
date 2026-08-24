# RoomFlow — 房间推进 / 间歇态 / 元进度与铁砧编排（P2 架构还债，2026-08-24 自 duel_controller 迁入）
# 运行时经 duel_controller preload 实例化（不注册全局 class_name——headless 测试环境不刷新类缓存）。
# 职责：清房结算链（奖励应用 → 铁砧点/金币入账 → 元进度三选一或房间歇态）、间歇态抽屉、
#       战败回整备、铁砧摇奖入口。controller 留单行转发器，HUD 信号连接面不变。
# 状态归属不变：in_interroom / game_state / meta 等仍由 controller 持有，经 _ctrl 读写。

var _ctrl  # DuelController


func _init(ctrl) -> void:
	_ctrl = ctrl


# 清房推进编排：hide → 应用奖励（可选）→ 铁砧点/金币入账 → T8 掉落（普通消耗品概率/精英保底护符）→ 元进度或间歇态 → 刷元进度栏。
func finish_room(apply_fn: Callable, is_boss: bool) -> void:
	_ctrl.hud.hide_reward_screen()
	if apply_fn.is_valid():
		apply_fn.call()
	_ctrl._anvil_system.award_meta(is_boss)    # M5：房间通关发放铁砧点数
	_ctrl._meta_store.award_gold(is_boss)    # S6+S8：清房金币 + 利息
	_ctrl._reward_system.apply_room_drops()   # T8：普通房 12% 掉消耗品 / 精英房保底护符（BOSS 走自身战利品）
	if _ctrl._is_run_final(_ctrl.room_index):
		_ctrl._reward_system.show_meta_choice()        # 通关整局（最终 BOSS）→元进度三选一（持久生效）
	else:
		enter_interroom()        # opt-in 商店：进入房间歇态（🛒 可选，▶ 下一房继续）
	_ctrl.hud._refresh_meta()   # 幂等兜底：各子系统方法已自包含刷新（apply_reward/award_gold 等），此处防编排层遗漏
func enter_interroom(roll_shop: bool = true) -> void:
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
	_ctrl._start_room(_ctrl.room_index + 1)


func on_shop_leave_pressed() -> void:
	_ctrl.hud.hide_shop_screen()
	_ctrl.hud.set_shop_button_text("🛒 商店")
	enter_interroom(false)   # 离开商店回房间歇态：不重滚货架（每房一次，防刷商店）


# 元进度三选一确认：应用 + 落盘（子系统内）→ 开新一局。
func on_meta_choice_chosen(opt: Dictionary) -> void:
	_ctrl.hud.hide_meta_screen()
	_ctrl._reward_system.on_meta_choice_chosen(opt)   # 元进度应用 + 落盘（_save_meta 在子系统内）
	_ctrl.hud._refresh_meta()
	_ctrl._full_reset()   # 元进度生效后开新一局（金币/槽位随局清零，但 meta 持久）


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