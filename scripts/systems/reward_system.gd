class_name RewardSystem
extends RefCounted

# T22：平衡常量收敛于 BalanceConfig（balance_config.tres）
const BALANCE = preload("res://resources/config/balance_config.tres")

# M4 房奖励 / 精英战前补给 / BOSS 战利品 / 局末元进度三选一——从 duel_controller.gd 抽出。
#
# 由 controller 在 _ready 处实例化并注入：RewardSystem.new(ctrl)。
# 约定（与 docs/[已完成]duel_controller拆分方案B.md 步骤4一致，延续步骤1–3 的写法）：
# - reward_choices / reward_is_boss 仍由 controller 持有（HUD 直读直写），本子系统只填充不持有；
#   本局加成层 run_symbol_bonus / run_power_bonus / run_shield_next 随本子系统走（方案B §4 状态归属表）。
# - @export 常量（META_ANVIL_BONUS / META_CHOICE_COUNT / REWARD_POOL / ELITE_REWARD_POOL 等）留
#   controller（RefCounted 无法在 Inspector 编辑），本子系统动态读 _ctrl.xxx。
# - 跨系统联动（奖励后推进房间 / 元进度生效后开新局 _full_reset / UI 刷新）留在 controller 编排层；
#   本子系统不互调其他子系统。
# - ctrl 标类型 DuelController（已加 class_name），成员访问获得编译期检查。

var _ctrl: DuelController          # DuelController 实例（类型标注，编译期检查）
var run_symbol_bonus: Dictionary = {}   # resource_path -> 额外权重（本局符号灌注，房奖励）
var run_power_bonus: int = 0            # 本局符号基础伤害加成（房奖励：攻击研磨）
var run_shield_next: int = 0            # 进入下一房时获得的护盾（房奖励：守望结界 / 精英备战）

func _init(ctrl: DuelController) -> void:
	_ctrl = ctrl


# ---------------------------------------------------------------------------
# 局内清零（_full_reset 调用）
# ---------------------------------------------------------------------------

func reset_run() -> void:
	run_symbol_bonus = {}
	run_power_bonus = 0
	run_shield_next = 0


# ---------------------------------------------------------------------------
# 局末元进度三选一（膨胀双轨：武器 base 线性 × 护符乘数增值，持久跨局）
# ---------------------------------------------------------------------------

func roll_meta_choices() -> Array:
	# T6：武器/护符/命中率等 per-item 旋钮入口已退役（§6 铁砧纯 gacha 定案）。
	# 元进度三选一只保留「铁砧点数」兜底候选，避免给出无生效通道的假选项。
	var meta_pool := [{
		"kind": "anvil", "path": "",
		"icon": "🔨", "label": "铁砧点数 +%d" % BALANCE.meta_anvil_bonus,
		"desc": "永久铁砧点数，用于铁砧抽取装备（盘外成长）",
	}]
	return meta_pool.slice(0, BALANCE.meta_choice_count)   # 三选一：候选不足时全出


func on_meta_choice_chosen(opt: Dictionary) -> void:
	match opt["kind"]:
		"anvil":
			_ctrl.meta["anvil_points"] += BALANCE.meta_anvil_bonus
			_ctrl.hud._log("元进度：铁砧点数 +%d（共 %d）" % [BALANCE.meta_anvil_bonus, _ctrl.meta["anvil_points"]])
	_ctrl._meta_store.save_meta()   # 元进度持久落盘；开新局（_full_reset）由 controller 编排层负责


# ---------------------------------------------------------------------------
# 房奖励三选一（Roguelike 构筑）
# ---------------------------------------------------------------------------

func roll_rewards() -> Array:
	# REWARD_POOL 现为 RewardData 资源数组；元素只读不修改，用浅拷贝即可（避免深拷贝复制资源）。
	var copy = _ctrl.REWARD_POOL.duplicate()
	var out := []
	for i in 3:
		if copy.is_empty():
			break
		var idx = randi() % copy.size()
		out.append(copy[idx])
		copy.remove_at(idx)
	return out


# T6 精英房「战前补给」三选一：精英池恰为 3 项（金币囤 / 铁砧点 / 结界备战），
# 直接全量返回供玩家三选一，保证每次精英都能看到全部 prep 选项。
func roll_elite_rewards() -> Array:
	return _ctrl.ELITE_REWARD_POOL.duplicate()


# BOSS 战利品：从主题池+混合券抽 3 张候选卡（dict 结构，供 HUD 直接渲染）。
# 候选构成：① 主题新武器（未持有，进池）② Boss 信物（占护符槽，若未占满）
func roll_boss_rewards(room) -> Array:
	var cands := []
	# ① 主题新武器：房间指定池（空则按 element 从全部武器取）中，玩家尚未持有的
	var src: Array = room.boss_reward_weapons if (room.boss_reward_weapons.size() > 0) else _ctrl.WEAPON_POOL
	for p in src:
		if not _ctrl.selected_loadout.has(p):
			var wd: WeaponData = load(p)
			var elem = wd.element if wd != null else "none"
			cands.append({
				"kind": "boss_weapon", "path": p,
				"icon": ElementCounter.label(elem),
				"label": (wd.weapon_name if wd != null else p.get_file().get_basename()),
				"desc": "新武器 · 进转轮带",
			})
	# ③ Boss 信物：占护符槽 1/3（CHARM_CAP），护符槽满则不出
	if room.boss_relic_path != "" and _ctrl._loadout_system.sel_arr("passive").size() < _ctrl._loadout_system.cat_max("passive"):
		var rd: ItemData = load(room.boss_relic_path)
		cands.append({
			"kind": "boss_relic", "path": room.boss_relic_path,
			"icon": (rd.icon if rd != null else "🏆"),
			"label": (rd.item_name if rd != null else "Boss 信物"),
			"desc": "信物 · 占护符槽",
			"tip": (rd.description if rd != null else "专属信物 · 占护符槽"),
		})
	cands.shuffle()
	var out := []
	for i in min(3, cands.size()):
		out.append(cands[i])
	return out


# 按 id 在普通/精英奖励池中查找 RewardData（数值资源化：value 字段，文案同文件防漂移）
func _find_reward(id: String) -> RewardData:
	for rw in _ctrl.REWARD_POOL:
		if rw is RewardData and rw.id == id:
			return rw
	for rw in _ctrl.ELITE_REWARD_POOL:
		if rw is RewardData and rw.id == id:
			return rw
	return null


func apply_reward(id: String) -> void:
	var rd = _find_reward(id)
	if rd == null:
		_ctrl.hud._log("奖励资源缺失：%s" % id)
		return
	match id:
		"heal":
			var h = int(_ctrl.player_hp_max * float(rd.value) / 100.0)
			_ctrl.player_hp = min(_ctrl.player_hp_max, _ctrl.player_hp + h)
			_ctrl.hud._log("奖励：治疗 +%d HP" % h)
		"maxhp":
			_ctrl.player_hp_max += rd.value
			_ctrl.player_hp = _ctrl.player_hp_max
			_ctrl.hud._log("奖励：最大 HP +%d 并回满" % rd.value)
		# "purify" 净化上限奖励已删除（净化完全走消耗品）
		"symbol":
			var cand := []
			for p in _ctrl.pool:
				if p[0] != _ctrl.TRASH_SYMBOL:
					cand.append(p[0])
			if cand.is_empty():
				cand = [_ctrl.TRASH_SYMBOL]
			var sym: SymbolData = cand[randi() % cand.size()]
			run_symbol_bonus[sym.resource_path] = run_symbol_bonus.get(sym.resource_path, 0) + rd.value
			_ctrl.hud._log("奖励：%s 符号权重 +%d" % [sym.name, rd.value])
		"shield":
			run_shield_next += rd.value
			_ctrl.hud._log("奖励：下一房 +%d 护盾" % rd.value)
		"power":
			run_power_bonus += rd.value
			_ctrl.hud._log("奖励：本局符号伤害 +%d（当前 +%d）" % [rd.value, run_power_bonus])
		# T6 精英房「战前补给」三类选项
		"elite_gold":
			_ctrl.gold += rd.value
			_ctrl.hud._log("精英战利：金币 +%d（共 %d）" % [rd.value, _ctrl.gold])
		"elite_anvil":
			_ctrl.meta["anvil_points"] += rd.value
			_ctrl.hud._log("精英战利：铁砧点数 +%d（共 %d）" % [rd.value, _ctrl.meta["anvil_points"]])
		"elite_ward":
			run_shield_next += rd.value
			_ctrl.hud._log("精英战利：下一房 +%d 护盾" % rd.value)


# BOSS 战利品结算（主题池+混合券三选一）：新武器(进池) / 武器强化券(meta升级,不进池) / Boss信物(占护符槽1/3)
func apply_boss_reward(cand: Dictionary) -> void:
	match cand.get("kind", ""):
		"boss_weapon":
			var p = cand.get("path", "")
			if p != "" and not _ctrl.selected_loadout.has(p):
				_ctrl._loadout_system.grow_slot("weapon")                 # 免费武器自动开槽（武器 UNCAPPED，无天花板限制）
				_ctrl.selected_loadout.append(p)          # 武器无上限（UNCAPPED），免费获得即自动开槽
				_ctrl._build_pool(_ctrl.selected_loadout)  # 重建符号池（新武器注入转轮带）
				_ctrl.hud._log("BOSS 战利品：获得武器 %s（已加入转轮带）" % cand.get("label", p))
		"boss_relic":
			var p = cand.get("path", "")
			if p != "" and not _ctrl.selected_charms.has(p):
				if _ctrl._loadout_system.sel_arr("passive").size() >= _ctrl._loadout_system.cat_max("passive"):
					_ctrl.hud._log("BOSS 战利品：护符槽已满，信物无法拾取")
					return
				_ctrl.selected_charms.append(p)            # 占护符槽 1/3（CHARM_CAP）
				_ctrl._apply_charms()                     # 重算护符被动（伤害乘区等随持有变化）
				_ctrl.hud._log("BOSS 战利品：获得专属信物 %s（占护符槽）" % cand.get("label", p))


# 打开奖励屏的语义入口：填充 reward_choices / reward_is_boss（HUD 从 state 快照读取）。
# 2026-08-09 由 controller._open_reward_screen 迁入（二次拆分 3/4）
func open_reward_screen(is_boss: bool) -> void:
	_ctrl.reward_is_boss = is_boss
	if is_boss:
		_ctrl.reward_choices = roll_boss_rewards(_ctrl.ROOMS[_ctrl.room_index])
	elif _ctrl.ROOMS[_ctrl.room_index].kind == "elite":
		_ctrl.reward_choices = roll_elite_rewards()
	else:
		_ctrl.reward_choices = roll_rewards()


# 局末元进度三选一弹屏（2026-08-09 由 controller._show_meta_choice 迁入）
func show_meta_choice() -> void:
	_ctrl.hud._show_meta_choice()
