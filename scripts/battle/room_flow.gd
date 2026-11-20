# RoomFlow — 房间推进 / 间歇态 / 元进度与铁砧编排（P2 架构还债，2026-08-24 自 duel_controller 迁入）
# 运行时经 duel_controller preload 实例化（不注册全局 class_name——headless 测试环境不刷新类缓存）。
# 职责：M1 战后成长三槽编排（历练/熟练结算 → 三槽选择 → 铁砧点/金币/drops → 间歇）、
#       间歇态抽屉、战败回整备、铁砧摇奖入口。controller 留单行转发器，HUD 信号连接面不变。
# 状态归属不变：in_interroom / game_state / meta 等仍由 controller 持有，经 _ctrl 读写。

var _ctrl  # DuelController


func _init(ctrl) -> void:
	_ctrl = ctrl


# 清房推进编排（成长三选一）：
# 普通 / 精英胜利 → 结算历练/熟练并生成成长三选一；选一项、付费重抽或免费跳过。
# 任意结算后清空本次未选成长，不进入下一战；BOSS 未选成长采用同一清空规则。
var post_battle_active := false

# L3 §6.6：本场战果快照（胜利结算后生成，供三选一界面同屏展示；零额外点击）
var last_battle_summary: Dictionary = {}
var _summary_before: Dictionary = {}
var _post_offer: Array = []       # 本次胜利可用的成长候选（0 或 1 项，展示前冻结）
var _phase := ""                  # "" | "loot" | "growth"
var _loot_view: Dictionary = {}


# B 方案：精英战必掉「精简剪」，保证每幕至少一次瘦身机会。
const TRIM_ITEM_PATH := "res://resources/consumables/trim_scissors.tres"   # L3 P1 弃用：精英奖励改为克制元素武器，常量保留兼容


# L3 P1：精英战专属奖励——必给一把「克制本房 element」的武器（Build 组件身份）。
# 例：冰精英给火武器（克冰+毒），而非同元素冰武器（打冰敌人×0.85劣势）。
# 替换原「精简剪」消耗品；武器槽满时由 controller 弹替换弹层（复用 BOSS 武器替换流程）。
func _grant_elite_trim() -> void:
	if _ctrl.current_room == null or String(_ctrl.current_room.kind) != "elite":
		return
	var act: int = int(_ctrl.current_room.act)
	var path: String = _ctrl._reward_system.roll_elite_element_weapon(act)
	if path == "":
		_ctrl.hud._log("精英战利品：无可掉落的主题武器（池空），跳过")
		return
	_ctrl.grant_elite_weapon(path)


func begin_post_battle() -> void:
	if post_battle_active:
		return
	post_battle_active = true
	# G7-5：首局引导——战后提示"选择会真实改造机器"（一次性，不弹窗）
	if _ctrl.onboarding != null:
		_ctrl.onboarding.hint("draft")
	# L3 §6.6：先结算再开三选一——本场战果在三选一打开时已全部确定，供界面同屏展示。
	# 原本 _award_victory 在 finish_room（选完之后）才发，改到这里提前发，确保战果栏数字准确。
	_snapshot_before()
	_settle_victory()
	_award_victory(false)   # 铁砧/金币/掉落提前结算（原在 finish_room）
	_finish_battle_summary(false)
	# ⚠️ G6-1 曾尝试移除精英自动掉克制武器，但安全门实证未通过（ACT2 422→378 < 396 门槛），
	# 已回退。方案 §7「去堆叠」需配合替代强度来源，不能在无补偿时直接删。
	_grant_elite_trim()
	# 成长候选先冻结：战利品阶段的 post_battle_has_growth() 仍要能回答「本房有没有真实成长」。
	_post_offer = _growth_candidates()
	_start_loot_phase()


# 新一局 / 回整备：清掉未完成的战后结算状态（避免跨局残留 active=true 卡住下一局）。
func reset_flow() -> void:
	post_battle_active = false
	_post_offer = []
	_phase = ""
	_loot_view = {}


func _start_loot_phase() -> void:
	_phase = "loot"
	_loot_view = _ctrl._reward_system.build_loot_offer(_current_source(), _current_act(), {"growth_only": true})
	if not bool(_loot_view.get("ok", false)):
		_ctrl._reward_system.settle_loot_skip()
		_ctrl._post_battle.clear_pending_choices()
		_finish_post_battle(Callable())
		return
	_ctrl.hud.show_loot_offer(_loot_view)


# 任意战利品结算后，本次未选成长全部放弃，不再保留到下一战。
func after_loot_settled() -> void:
	if not post_battle_active or _phase != "loot":
		return
	_ctrl._post_battle.clear_pending_choices()
	_finish_post_battle(Callable())


# 重抽：支付递增金币，普通战利品与 queued 成长都重新生成，品质层不变。
func on_loot_reroll() -> void:
	if not post_battle_active or _phase != "loot":
		return
	_ctrl._post_battle.reroll_choices()
	var v: Dictionary = _ctrl._reward_system.reroll_loot_offer()
	if bool(v.get("ok", false)):
		_loot_view = v
		_ctrl.hud.refresh_loot_offer(v)


# 免费跳过：不发放本次战利品，未选成长同时放弃。
func skip_loot() -> void:
	if not post_battle_active or _phase != "loot":
		return
	_ctrl._reward_system.settle_loot_skip()
	_ctrl._post_battle.clear_pending_choices()
	_finish_post_battle(Callable())


# 整体跳过：战利品与未选成长都放弃。
func skip_post_battle() -> void:
	if not post_battle_active:
		return
	if _phase == "loot":
		_ctrl._reward_system.settle_loot_skip()
	_ctrl._post_battle.clear_pending_choices()
	_finish_post_battle(Callable())


# 旧成长阶段兼容入口：未选成长不再保留。
func defer_growth() -> void:
	if not post_battle_active:
		return
	_ctrl._post_battle.clear_pending_choices()
	_finish_post_battle(Callable())


func _enter_growth_phase() -> void:
	_phase = "growth"
	_post_offer = _growth_candidates()
	var cand: Dictionary = _post_offer[0] if not _post_offer.is_empty() else {}
	if cand.is_empty():
		_finish_post_battle(Callable())
		return
	_ctrl.hud.show_loot_growth(cand, _growth_summary_text())


func _growth_candidates() -> Array:
	var g: Dictionary = _ctrl._post_battle.build_growth(_current_kind())
	return [] if g.is_empty() else [g]


func _current_source() -> String:
	var k := _current_kind()
	return k if k in ["normal", "elite"] else "normal"


func _current_act() -> int:
	if _ctrl.room_index >= 0 and _ctrl.room_index < _ctrl.ROOMS.size():
		return maxi(1, int(_ctrl.ROOMS[_ctrl.room_index].act))
	return 1


func finish_room(apply_fn: Callable, is_boss: bool) -> void:
	if post_battle_active:
		_finish_post_battle(apply_fn)
		return
	_ctrl.hud.hide_reward_screen()
	_settle_victory()
	_ctrl._post_battle.clear_pending_choices()
	if apply_fn.is_valid():
		apply_fn.call()
	# L3 §6.6：_award_victory 已提前（普通战在 begin_post_battle / BOSS 在 prepare_boss_summary），此处不再重复。
	_after_victory()


func _finish_post_battle(apply_fn: Callable) -> void:
	if not post_battle_active:
		return
	post_battle_active = false
	_ctrl._post_battle.clear_pending_choices()
	_phase = ""
	_post_offer = []
	_loot_view = {}
	_ctrl.hud.hide_reward_screen()
	if apply_fn.is_valid():
		apply_fn.call()
	# L3 §6.6：_award_victory(false) 已提前到 begin_post_battle，此处不再重复结算。
	_after_victory()


# 房间胜利的成长节奏：房间计数 → 技艺结算 → 熟练（等级已移除）。
func _settle_victory() -> void:
	if _ctrl._telemetry != null:
		_ctrl._telemetry.on_room_clear()   # M1-06：清房耗时
	if _ctrl._journal != null:
		_ctrl._journal.note_battle_end("win")   # G5 工具：战斗胜利（战败由局末收口）
	var kind := _current_kind()
	# P0.3：技艺保底计数归 RewardSystem（V1.1 §23 单一权威来源）
	# 普通/精英战后走 Draft 三选一 → 计入；BOSS 走专属战利品 → 不计入
	_ctrl._reward_system.note_skill_pity_room(kind != "boss")
	_ctrl.growth.apply_victory_perks(kind)   # G7-A S1：回春 / 积蓄（无对应技艺时为空操作）
	_ctrl.mastery.settle_room(kind)    # M2-02：样板武器按本房有效结算累计熟练


# 与选择无关的清房收益：铁砧点 / 金币 / T8 掉落。
func _award_victory(is_boss: bool) -> void:
	_ctrl._anvil_system.award_meta(is_boss)    # M5：房间通关发放铁砧点数
	_ctrl._meta_store.award_gold(is_boss)    # S6+S8：清房金币 + 利息
	_ctrl._reward_system.apply_room_drops()   # T8：普通房 12% 掉消耗品 / 精英房保底护符（BOSS 走自身战利品）
	# G6-2：Boss 遗物胜利时保证入账（不再混入三选一候选）；grant 内部按 run_relics 去重，重复调用安全。
	if is_boss:
		_ctrl._reward_system.grant_boss_relic(_ctrl.current_room)
	if is_boss and _ctrl._career != null:
		_ctrl._career.on_boss_cleared()        # G6-01：BOSS 通关 → 一次性生涯成就（只记录，不发属性）
	if is_boss and _ctrl._codex != null:
		_ctrl._codex.record_run(_ctrl.mastery)   # G6-04：记录本局武器最高熟练与铭印组合


# ===== L3 §6.6 战果快照（before/after 差值，不改任何结算逻辑）=====
# BOSS 战入口：三选一打开前调用——提前结算收益并生成战果快照（普通战在 begin_post_battle 内）。
func prepare_boss_summary() -> void:
	_snapshot_before()
	_settle_victory()
	_award_victory(true)
	_finish_battle_summary(true)


func _snapshot_before() -> void:
	_summary_before = {
		"gold": int(_ctrl.gold),
		"anvil": int(_ctrl.meta.get("anvil_points", 0)),
		"charms": _ctrl.selected_charms.duplicate(),
		"consumables": [],
	}
	for slot in _ctrl.consumable_slots:
		_summary_before["consumables"].append(String(slot.get("path", "")))


func _finish_battle_summary(is_boss: bool) -> void:
	var d_gold: int = int(_ctrl.gold) - int(_summary_before.get("gold", 0))
	var d_anvil: int = int(_ctrl.meta.get("anvil_points", 0)) - int(_summary_before.get("anvil", 0))
	# 掉落：护符/消耗品的集合差（本场新入账的）
	var drops: Array[String] = []
	var before_charms: Array = _summary_before.get("charms", [])
	for p in _ctrl.selected_charms:
		if not before_charms.has(p):
			drops.append("护符")
	var before_cons: Array = _summary_before.get("consumables", [])
	var now_cons: Array[String] = []
	for slot in _ctrl.consumable_slots:
		now_cons.append(String(slot.get("path", "")))
	for p in now_cons:
		if not before_cons.has(p):
			drops.append("消耗品")
	var drop_txt: String = "、".join(drops) if not drops.is_empty() else "无"
	last_battle_summary = {
		"gold": d_gold,
		"anvil": d_anvil,
		"mastery": "本场武器熟练已结算",   # 熟练按本房有效结算，无单一增量字段
		"drops": drop_txt,
		"is_boss": is_boss,
		"text": "金币 +%d · 熟练已计 · 铁砧 +%d · 掉落 %s" % [
			d_gold, d_anvil, drop_txt],
	}


func _after_victory() -> void:
	if _ctrl._is_run_final(_ctrl.room_index):
		log_telemetry()                               # M1-06：整局结束打印遥测
		_ctrl._reward_system.show_meta_choice()        # 通关整局（最终 BOSS）→元进度结算（持久生效）→回整备
	elif _ctrl.node_mode:
		# M2：棋盘模式胜利后回棋盘待机；下一房预告由可见棋盘替代，不进入线性间歇态。
		# G7-A S4：幕 BOSS 通关 → 开下一幕棋盘（状态全部保留）；生成失败按通关收口，不软锁。
		if _ctrl.board.current_is_boss() and _ctrl.board.act < _ctrl.run_act_count():
			if not _ctrl.advance_act():
				log_telemetry()
				_ctrl._reward_system.show_meta_choice()
		else:
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
# Step 7：先结算战利品（取第一项可正常授予的物品；全是替换 / 转化时按跳过），再处理成长位。
# want_growth_id 非空时，只接受该 id 的成长卡（探针按铭印类型分组用）；不匹配则保留到下次。
func auto_pick_post_battle(prefer: Array = ["growth", "supply", "build"], want_growth_id: String = "") -> bool:
	if not post_battle_active:
		return false
	if _phase == "loot":
		_auto_settle_loot(prefer, want_growth_id)
		if not post_battle_active:
			return true
	if _phase != "growth":
		return false
	var chosen := _growth_candidate(want_growth_id)
	if chosen.is_empty() or not prefer.has("growth"):
		defer_growth()
		return true
	_ctrl._on_post_battle_growth_chosen(chosen)
	return true


# bot 策略：优先处理 queued 成长，再取普通战利品；保留无替换与跳过兜底。
func _auto_settle_loot(prefer: Array = [], want_growth_id: String = "") -> void:
	var opts: Array = _ctrl._reward_system.loot_offer_view().get("options", [])
	if prefer.has("growth"):
		for i in range(opts.size()):
			var o: Dictionary = opts[i]
			# 新 Draft 路径：技艺卡的 id 以 "perk_" 开头；旧路径：queued_growth
			var is_perk := String(o.get("id", "")).begins_with("perk_")
			var is_queued := String(o.get("kind", "")) == "queued_growth"
			if not is_perk and not is_queued:
				continue
			if want_growth_id != "" and String(o.get("id", o.get("growth_entry", {}).get("growth_id", ""))) != want_growth_id:
				continue
			_ctrl._on_loot_offer_chosen(i)
			return
	var pick := -1
	for i in range(opts.size()):
		var o: Dictionary = opts[i]
		if bool(o.get("needs_replace", false)):
			continue
		if String(o.get("kind", "")) == "item" and String(o.get("grant", "")) in ["item", "mastery"]:
			pick = i
			break
	if pick < 0:
		for i in range(opts.size()):
			if not bool((opts[i] as Dictionary).get("needs_replace", false)):
				pick = i
				break
	var res: Dictionary = {}
	if pick >= 0:
		res = _ctrl._reward_system.settle_loot_offer(pick)
	if not bool(res.get("ok", false)):
		res = _ctrl._reward_system.settle_loot_skip()
	after_loot_settled()


func _growth_candidate(want_growth_id: String = "") -> Dictionary:
	for cand in _post_offer:
		if String(cand.get("slot", "")) != "growth":
			continue
		if String(cand.get("kind", "")) not in ["perk", "imprint"]:
			continue
		if want_growth_id != "" and String(cand.get("growth_id", "")) != want_growth_id:
			continue
		return cand
	return {}


# 当前阶段（测试 / 探针只读）："" | "loot" | "growth"。
func post_battle_phase() -> String:
	return _phase


func loot_view() -> Dictionary:
	return _loot_view.duplicate(true)


# P0-2：成长摘要（结算页头 + 确认后日志），让「本局成长方向」可复述。
func _growth_summary_text() -> String:
	var bits: Array[String] = []
	if not _ctrl.growth.perk_ids.is_empty():
		bits.append(_ctrl.growth.summary_line())
	if _ctrl.mastery.imprint_total() > 0:
		bits.append(_ctrl.mastery.summary_line())
	return "本局成长：" + " ｜ ".join(bits)


# M1-06：局末遥测输出（真人评测指标；只打印/记日志，不改变结算）
func log_telemetry() -> void:
	if _ctrl._journal != null:
		_ctrl._journal.finish()   # G5 工具：局末写 JSON + 预填记录表（只读，不改结算）
	if _ctrl._telemetry == null:
		return
	# P4：记录局末结果（构筑标签 vs 通关/死亡，仅作相关性观察）
	var win: bool = _ctrl.game_state == DuelController.FlowState.WON
	var tags: Array = []
	var affinity = _ctrl.get("element_affinity")
	if affinity is Dictionary:
		for k in affinity:
			if int(affinity[k]) > 0:
				tags.append("build." + String(k))
	_ctrl._telemetry.on_run_outcome(win, int(_ctrl.room_index), tags)
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


# 扫雷棋盘 Step 3：主动撤回整备（BoardScreen 二次确认后调用）。
# 不发 BOSS / 通关奖励，记录 result=retreat；图鉴、收藏、解锁与局外点数由 return_to_loadout 落盘保留。
func retreat_run() -> void:
	if _ctrl._journal != null:
		_ctrl._journal.finish("retreat")
	if _ctrl._codex != null:
		_ctrl._codex.record_run(_ctrl.mastery)   # 保留本局武器最高熟练（同战败口径）
	return_to_loadout()


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