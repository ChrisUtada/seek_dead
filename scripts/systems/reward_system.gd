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
	_ctrl.invalidate_state()


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
# 胜利奖励方案（2026-08-13，见 docs/胜利奖励方案.md）：
# - 候选池 9 类（5 数值 + gold 经济 + consumable/weapon 构筑 + maxhp_heal 双效），三档稀有度加权（common 50 / uncommon 30 / rare 20，幕三 rare 升至 30）
# - 组合保证：3 张里至少 1 张恢复/防御向（def）+ 至少 1 张输出/构筑向（atk）
# - 按幕分层：幕一教学期不出 weapon（构筑武器）
const REWARD_TAG := {
	"heal": "def", "maxhp": "def", "shield": "def",
	"power": "atk", "symbol": "atk", "gold": "atk", "consumable": "atk", "weapon": "atk",
}

func roll_rewards() -> Array:
	var act: int = _ctrl.ROOMS[_ctrl.room_index].act if (_ctrl.room_index >= 0 and _ctrl.room_index < _ctrl.ROOMS.size()) else 1
	var pool: Array = _ctrl.REWARD_POOL.duplicate()
	# 幕一教学期不出构筑武器；武器槽满（2 把，A 方案 2026-08-13）时武器卡不入候选池——尊重「固定 2 把」规则
	if act < 2 or _ctrl.selected_loadout.size() >= _ctrl._loadout_system.cat_cap("weapon"):
		pool = pool.filter(func(rw): return rw.id != "weapon")
	var def_pool: Array = pool.filter(func(rw): return REWARD_TAG.get(rw.id, "") == "def")
	var atk_pool: Array = pool.filter(func(rw): return REWARD_TAG.get(rw.id, "") == "atk")
	var out := []
	var first: RewardData = _weighted_pick(def_pool, act)
	if first != null:
		out.append(first)
	var second: RewardData = _weighted_pick(atk_pool, act)
	if second != null:
		out.append(second)
	var rest: Array = pool.duplicate()
	rest.erase(first)
	rest.erase(second)
	var third: RewardData = _weighted_pick(rest, act)
	if third != null:
		out.append(third)
	return out


# 稀有度权重档（胜利奖励方案：common 50 / uncommon 30 / rare 20；幕三 rare 升至 30、common 降至 40）
func _rarity_weight(r: String, act: int) -> float:
	match r:
		"rare":
			return 0.3 if act >= 3 else 0.2
		"uncommon":
			return 0.3
	return 0.4 if act >= 3 else 0.5


func _weighted_pick(pool: Array, act: int) -> RewardData:
	if pool.is_empty():
		return null
	var total := 0.0
	for rw in pool:
		total += _rarity_weight(rw.rarity, act)
	var roll := randf() * total
	for rw in pool:
		roll -= _rarity_weight(rw.rarity, act)
		if roll <= 0.0:
			return rw
	return pool[pool.size() - 1]


# T6 精英房「战前补给」：2 固定（金币囤/铁砧点）+ 1 动态高品质位（rare 构筑/大数值——胜利奖励方案 2026-08-13）
func roll_elite_rewards() -> Array:
	var out := []
	for rw in _ctrl.ELITE_REWARD_POOL:
		if rw.id == "elite_gold" or rw.id == "elite_anvil":
			out.append(rw)
	var act: int = _ctrl.ROOMS[_ctrl.room_index].act if (_ctrl.room_index >= 0 and _ctrl.room_index < _ctrl.ROOMS.size()) else 1
	var high_pool: Array = []
	for rw in _ctrl.REWARD_POOL:
		if rw.id in ["weapon", "consumable", "maxhp_heal"] and (rw.id != "weapon" or _ctrl.selected_loadout.size() < _ctrl._loadout_system.cat_cap("weapon")):
			high_pool.append(rw)
	var bonus: RewardData = _weighted_pick(high_pool, act)
	if bonus != null:
		out.append(bonus)
	return out


# BOSS 战利品：从主题池+混合券抽 3 张候选卡（dict 结构，供 HUD 直接渲染）。
# 候选构成：① 主题新武器（未持有 + 武器槽未满，进池）② Boss 信物（占护符槽，若未占满）。
# T7（2026-08-24）：武器候选改 acq_weighted_sample 加权无放回抽样（替代 shuffle 均匀），
# 并按幕乘 boss_depth_bias 深度偏置（只抬 rare/epic——越深越出好货，§11.2）。
func roll_boss_rewards(room) -> Array:
	var cands := []
	# ① 主题新武器：房间指定池（空则按 element 从全部武器取；真·最终不回退=明确「无战利品」），
	# 玩家尚未持有且武器槽未满才入候选；按获取权重 × 幕深度偏置 加权抽至多 3 把
	var src: Array = room.boss_reward_weapons if (room.boss_reward_weapons.size() > 0) else ([] if room.final_boss else _ctrl.WEAPON_POOL)
	var weapon_slots_free: bool = _ctrl.selected_loadout.size() < _ctrl._loadout_system.cat_cap("weapon")
	var weapon_pool := []
	for p in src:
		if weapon_slots_free and not _ctrl.selected_loadout.has(p):
			weapon_pool.append(p)
	var act: int = int(room.act) if room.act >= 1 and room.act <= _ctrl.BALANCE.boss_depth_bias.size() else 1
	var bias: float = float(_ctrl.BALANCE.boss_depth_bias[act - 1])
	var picked_weapons: Array = acq_weighted_sample(weapon_pool, mini(3, weapon_pool.size()), bias)
	for p in picked_weapons:
		var wd: WeaponData = load(p)
		var elem = wd.element if wd != null else "none"
		cands.append({
			"kind": "boss_weapon", "path": p,
			"icon": ElementCounter.label(elem),
			"label": (wd.weapon_name if wd != null else p.get_file().get_basename()),
			"desc": "新武器 · 进转轮带",
		})
	# ② Boss 信物：占护符槽 1/3（CHARM_CAP），护符槽满则不出
	if room.boss_relic_path != "" and _ctrl._loadout_system.sel_arr("passive").size() < _ctrl._loadout_system.cat_max("passive"):
		var rd: ItemData = load(room.boss_relic_path)
		cands.append({
			"kind": "boss_relic", "path": room.boss_relic_path,
			"icon": (rd.icon if rd != null else "🏆"),
			"label": (rd.item_name if rd != null else "Boss 信物"),
			"desc": "信物 · 占护符槽",
			"tip": (rd.description if rd != null else "专属信物 · 占护符槽"),
		})
	cands.shuffle()   # 展示顺序随机（抽取本身已加权）
	# 空池保底（2026-08-14，docs/BOSS信物_设计方案.md §4）：武器槽满 2 + 护符槽满/无信物
	# → 两来源全被拦截，注入铁砧点兜底卡，战利品永不空屏
	if cands.is_empty():
		cands.append({"kind": "boss_anvil", "path": "", "icon": "🔨",
			"label": "铁砧结晶", "desc": "铁砧点数 +%d（跨局）" % BALANCE.boss_anvil_bonus,
			"tip": "敌库已空（武器/护符槽满），改赏铁砧点数"})
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
			if h > 0:
				_ctrl.hud._popup("❤+%d" % h, Palette.POP_HEAL, _ctrl.hud._player_sprite_anchor())
		"maxhp":
			_ctrl.player_hp_max += rd.value
			_ctrl.player_hp = _ctrl.player_hp_max
			_ctrl.hud._log("奖励：最大 HP +%d 并回满" % rd.value)
			_ctrl.hud._popup("❤上限+%d 回满" % rd.value, Palette.POP_HEAL, _ctrl.hud._player_sprite_anchor())
		# "purify" 净化上限奖励已删除（净化完全走消耗品）
		"symbol":
			# 2026-08-14 方案 A（docs/[已完成]整备结构_技能槽上限与频率规范.md §5）：灌注候选 = 当前未封顶的
			# damage 符号（有效权重 < 4.0，与 reel_system.build_strips 档位制 w≥4→4 格对齐）。
			# 排除：非攻击符号（技能 buff/status/金币——灌注会白加或抬频稀释攻击占比）、
			# 已 4 格封顶的符号（权重再 +3 也是死 roll）。
			var cand := []
			for p in _ctrl.pool:
				var csym: SymbolData = p[0]
				if csym == _ctrl.TRASH_SYMBOL or csym.kind != "damage":
					continue
				var eff_w: float = maxf(0.0, float(p[1]) + _ctrl.combat.agg_symbol_weight_mod(csym) + _ctrl._synergy_system.weight_mod(csym))
				if eff_w < 4.0:
					cand.append(csym)
			# 兜底（极罕见：双单符号武器且主符号均已 4 格封顶）：回退全 damage 符号——
			# 宁可死 roll（权重记录但格数不变）也绝不命中非攻击符号稀释主输出
			if cand.is_empty():
				for p in _ctrl.pool:
					var csym: SymbolData = p[0]
					if csym != _ctrl.TRASH_SYMBOL and csym.kind == "damage" and not cand.has(csym):
						cand.append(csym)
			if cand.is_empty():
				cand = [_ctrl.TRASH_SYMBOL]
			var sym: SymbolData = cand[randi() % cand.size()]
			run_symbol_bonus[sym.resource_path] = run_symbol_bonus.get(sym.resource_path, 0) + rd.value
			_ctrl.hud._log("奖励：%s 符号权重 +%d" % [sym.name, rd.value])
			_ctrl.hud._popup("✨%s 权重+%d" % [sym.label, rd.value], Palette.POP_BUFF, _ctrl.hud._player_sprite_anchor())
		"shield":
			run_shield_next += rd.value
			_ctrl.hud._log("奖励：下一房 +%d 护盾" % rd.value)
			_ctrl.hud._popup("🛡下一房+%d" % rd.value, Palette.POP_SHIELD, _ctrl.hud._player_sprite_anchor())
		"power":
			run_power_bonus += rd.value
			_ctrl.hud._log("奖励：本局符号伤害 +%d（当前 +%d）" % [rd.value, run_power_bonus])
			_ctrl.hud._popup("⚔伤害+%d" % rd.value, Palette.POP_BUFF, _ctrl.hud._player_sprite_anchor())
		# 胜利奖励方案（2026-08-13）新增：经济 / 构筑 / 双效
		"gold":
			_ctrl.gold += rd.value
			_ctrl.hud._log("奖励：金币 +%d（共 %d）" % [rd.value, _ctrl.gold])
			_ctrl.hud._popup("💰+%d" % rd.value, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
		"consumable":
			_pick_item_reward("active")
		"weapon":
			_pick_item_reward("weapon")
		"maxhp_heal":
			_ctrl.player_hp_max += rd.value
			_ctrl.player_hp = mini(_ctrl.player_hp_max, _ctrl.player_hp + int(_ctrl.player_hp_max * 0.2))
			_ctrl.hud._log("奖励：最大 HP +%d 并恢复 20%%" % rd.value)
			_ctrl.hud._popup("❤上限+%d 恢复20%%" % rd.value, Palette.POP_HEAL, _ctrl.hud._player_sprite_anchor())
		# T6 精英房「战前补给」三类选项
		"elite_gold":
			_ctrl.gold += rd.value
			_ctrl.hud._log("精英战利：金币 +%d（共 %d）" % [rd.value, _ctrl.gold])
			_ctrl.hud._popup("💰+%d" % rd.value, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
		"elite_anvil":
			_ctrl.meta["anvil_points"] += rd.value
			_ctrl.hud._log("精英战利：铁砧点数 +%d（共 %d）" % [rd.value, _ctrl.meta["anvil_points"]])
			_ctrl.hud._popup("🔨铁砧点+%d" % rd.value, Palette.ACCENT_GOLD, _ctrl.hud._player_sprite_anchor())
		"elite_ward":
			run_shield_next += rd.value
			_ctrl.hud._log("精英战利：下一房 +%d 护盾" % rd.value)
			_ctrl.hud._popup("🛡下一房+%d" % rd.value, Palette.POP_SHIELD, _ctrl.hud._player_sprite_anchor())
	_ctrl.invalidate_state()   # 玩家 HP/金币/构筑奖励（腰带/转轮带）
	_ctrl.hud._refresh_meta()   # 自包含刷新：任何直接调用本方法的新路径不依赖外部收尾（controller 收尾刷新降级为幂等兜底）


# 构筑奖励：随机未持有武器进转轮带 / 随机未持有消耗品进腰带（胜利奖励方案 2026-08-13）
func _pick_item_reward(kind: String) -> void:
	# A 方案防御保底：武器槽满（上限 2）时不追加（候选层已拦截，此处双保险）
	if kind == "weapon" and _ctrl.selected_loadout.size() >= _ctrl._loadout_system.cat_cap("weapon"):
		return
	var owned: Array = _ctrl.selected_loadout if kind == "weapon" else []
	var src: Array = _ctrl.WEAPON_POOL if kind == "weapon" else _ctrl.ITEM_POOL
	var cand := []
	for p in src:
		var res: Resource = load(p)
		if res == null:
			continue
		if kind != "weapon" and res.get("category") != "active":
			continue
		if not owned.has(p):
			cand.append(p)
	if cand.is_empty():
		for p in src:
			var res: Resource = load(p)
			if res != null and (kind == "weapon" or res.get("category") == "active"):
				cand.append(p)
	if cand.is_empty():
		return
	var path: String = cand[randi() % cand.size()]
	var cd: Resource = load(path)
	if kind == "weapon":
		_ctrl._loadout_system.grow_slot("weapon")                 # 免费武器自动开槽（同 BOSS 战利品）
		_ctrl.selected_loadout.append(path)
		_ctrl._build_pool(_ctrl.selected_loadout)
		_ctrl.hud._log("奖励：获得武器 %s（已加入转轮带）" % cd.weapon_name)
		_ctrl.hud._popup("🎁 获得武器 %s" % cd.weapon_name, Palette.ACCENT_GOLD, _ctrl.hud._player_sprite_anchor())
	else:
		# P-审计 P2：腰带满不硬塞（CONSUMABLE_CAP 之外的格子不可见不可用）——
		# 折算金币（卖价），与 T8 掉落兜底同语义，保底不落空
		if _ctrl.consumable_slots.size() >= _ctrl.CONSUMABLE_CAP:
			var refund: int = _ctrl._sell_price("active", path)
			_ctrl.gold += refund
			_ctrl.hud._log("奖励：%s 但腰带已满 → 折算金币 +%d" % [cd.item_name, refund])
			_ctrl.hud._popup("💰+%d" % refund, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
			return
		_ctrl._consumable_uid += 1
		_ctrl.consumable_slots.append({"path": path, "item_id": cd.item_id, "charges": cd.charges, "uid": "c%d" % _ctrl._consumable_uid})
		_ctrl.hud._log("奖励：获得消耗品 %s（入腰带）" % cd.item_name)
		_ctrl.hud._popup("🎁 获得 %s" % cd.item_name, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
		_ctrl.hud._refresh_consumable_panel()


# BOSS 战利品结算（主题池+混合券三选一）：新武器(进池) / 武器强化券(meta升级,不进池) / Boss信物(占护符槽1/3)
func apply_boss_reward(cand: Dictionary) -> void:
	match cand.get("kind", ""):
		"boss_weapon":
			var p = cand.get("path", "")
			if p != "" and not _ctrl.selected_loadout.has(p):
				_ctrl._loadout_system.grow_slot("weapon")                 # 免费武器自动开槽（武器槽上限 2：grow_slot 封顶兜底，候选层已拦截满槽）
				_ctrl.selected_loadout.append(p)          # 武器槽未满才出候选（A 方案 2026-08-13：上限 2 尊重「固定 2 把」规则）
				_ctrl._build_pool(_ctrl.selected_loadout)  # 重建符号池（新武器注入转轮带）
				_ctrl.hud._log("BOSS 战利品：获得武器 %s（已加入转轮带）" % cand.get("label", p))
				_ctrl.hud._popup("⚔ 获得武器 %s" % cand.get("label", p), Palette.ACCENT_GOLD, _ctrl.hud._player_sprite_anchor())
		"boss_relic":
			var p = cand.get("path", "")
			if p != "" and not _ctrl.selected_charms.has(p):
				if _ctrl._loadout_system.sel_arr("passive").size() >= _ctrl._loadout_system.cat_max("passive"):
					_ctrl.hud._log("BOSS 战利品：护符槽已满，信物无法拾取")
					return
				_ctrl.selected_charms.append(p)            # 占护符槽 1/3（CHARM_CAP）
				# 2026-08-14 拍板（审查 §3.4）：信物跨局持久化——写入 owned_charms（收藏金字塔顶端定位），
				# 后续整备页可随时再选（BOSS 信物不进商店/铁砧/新档种子，仅 BOSS 战利品与后续重选两条路径）
				if not _ctrl.meta["owned_charms"].has(p):
					_ctrl.meta["owned_charms"].append(p)
					_ctrl._meta_store.save_meta()
				_ctrl._apply_charms()                     # 重算护符被动（伤害乘区等随持有变化）
				_ctrl.hud._log("BOSS 战利品：获得专属信物 %s（占护符槽，已入图鉴）" % cand.get("label", p))
				_ctrl.hud._popup("🏆 获得信物 %s" % cand.get("label", p), Palette.ACCENT_GOLD, _ctrl.hud._player_sprite_anchor())
		# 空池兜底（2026-08-14）：武器/护符槽双满时的铁砧点补偿
		"boss_anvil":
			_ctrl.meta["anvil_points"] += BALANCE.boss_anvil_bonus
			_ctrl._meta_store.save_meta()   # 跨局货币立即落盘
			_ctrl.hud._log("BOSS 战利品：铁砧点数 +%d（共 %d）" % [BALANCE.boss_anvil_bonus, _ctrl.meta["anvil_points"]])
			_ctrl.hud._popup("🔨铁砧点+%d" % BALANCE.boss_anvil_bonus, Palette.ACCENT_GOLD, _ctrl.hud._player_sprite_anchor())
	_ctrl.invalidate_state()
	_ctrl.hud._refresh_meta()   # 自包含刷新（同上：新调用路径不依赖外部收尾）


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
	_ctrl.invalidate_state()


# 局末元进度三选一弹屏（2026-08-09 由 controller._show_meta_choice 迁入）
func show_meta_choice() -> void:
	_ctrl.hud._show_meta_choice()


# ---------------------------------------------------------------------------
# T8 掉落渠道（2026-08-24，docs/装备收集规划_200.md §12.1）：
# 普通房 12% 掉 1 消耗品（active 池均匀，不吃稀有竞争）；精英房保底 1 护符
# （acquisition_weight 加权，排除 BOSS 信物）。BOSS 房走自身战利品不经此处。
# 入口：room_flow.finish_room 在铁砧点/金币入账后调用。
# ---------------------------------------------------------------------------
func apply_room_drops() -> void:
	if _ctrl.room_index < 0 or _ctrl.room_index >= _ctrl.ROOMS.size():
		return
	var kind: String = _ctrl.ROOMS[_ctrl.room_index].kind
	if kind == "elite":
		_drop_elite_charm()
	elif kind == "normal" and randf() < BALANCE.drop_consumable_chance_normal:
		var cand := []
		for p in _ctrl.ITEM_POOL:
			var res: Resource = load(p)
			if res != null and res.get("category") == "active":
				cand.append(p)
		if not cand.is_empty():
			_grant_drop_consumable(cand[randi() % cand.size()])


# 精英保底护符：acquisition_weight 加权抽取；护符槽未达天花板时免费开槽（先例：武器奖励自动开槽），
# 已达 CHARM_CAP 天花板则折算金币（卖价），保底永不落空。排除 BOSS 信物（信物仅 BOSS 战利品可获）。
func _drop_elite_charm() -> void:
	var relics := relic_paths()
	var cand := []
	for p in _ctrl.ITEM_POOL:
		if p in relics:
			continue
		var res: Resource = load(p)
		if res != null and res.get("category") == "passive":
			cand.append(p)
	if cand.is_empty():
		return
	var path := acq_weighted_pick(cand)
	if sel_passive_size() >= _ctrl._loadout_system.cat_max("passive"):
		if _ctrl._loadout_system.can_grow_slot("passive"):
			_ctrl._loadout_system.grow_slot("passive")
		else:
			var refund: int = _ctrl._sell_price("passive", path)
			_ctrl.gold += refund
			var nm2: Resource = load(path)
			_ctrl.hud._log("精英掉落：%s 但护符槽已满（3/3）→ 折算金币 +%d" % [(nm2.item_name if nm2 != null else path), refund])
			_ctrl.hud._popup("💰+%d" % refund, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
			return
	_ctrl.selected_charms.append(path)
	_ctrl._apply_charms()
	var cd: Resource = load(path)
	_ctrl.hud._log("精英掉落：获得护符 %s（按获取权重加权，占护符槽）" % (cd.item_name if cd != null else path))
	_ctrl.hud._popup("🎁 获得护符 %s" % (cd.icon if cd != null else "🛡"), Palette.ACCENT_GOLD, _ctrl.hud._player_sprite_anchor())


# 普通房消耗品掉落授予：腰带满（CONSUMABLE_CAP）→ 折算金币（卖价），保底语义不落空。
func _grant_drop_consumable(path: String) -> void:
	if _ctrl.consumable_slots.size() >= _ctrl.CONSUMABLE_CAP:
		var refund: int = _ctrl._sell_price("active", path)
		_ctrl.gold += refund
		var nm: Resource = load(path)
		_ctrl.hud._log("掉落：%s 但腰带已满 → 折算金币 +%d" % [(nm.item_name if nm != null else path), refund])
		_ctrl.hud._popup("💰+%d" % refund, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
		return
	var cd: Resource = load(path)
	_ctrl._consumable_uid += 1
	_ctrl.consumable_slots.append({"path": path, "item_id": cd.item_id, "charges": cd.charges, "uid": "c%d" % _ctrl._consumable_uid})
	_ctrl.hud._log("掉落：获得消耗品 %s（入腰带）" % cd.item_name)
	_ctrl.hud._popup("🎁 获得 %s" % cd.item_name, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
	_ctrl.hud._refresh_consumable_panel()


# 共享获取权重（§11.1）：单件物品权重 = acquisition_weight[rarity]；bias ≠ 1 时乘算 rare/epic
# （§11.2 BOSS 深度偏置——只抬高稀，common/uncommon 不动；商店传 1.0）。
func acq_weight(path: String, bias: float = 1.0) -> float:
	var res: Resource = load(path)
	var r: String = String(res.get("rarity")) if res != null and res.get("rarity") != null else "common"
	var w: float = float(BALANCE.acquisition_weight.get(r, 100))
	if bias != 1.0 and (r == "rare" or r == "epic"):
		w *= bias
	return w


func acq_weighted_pick(paths: Array, bias: float = 1.0) -> String:
	var total := 0.0
	for p in paths:
		total += acq_weight(p, bias)
	var roll := randf() * total
	for p in paths:
		roll -= acq_weight(p, bias)
		if roll <= 0.0:
			return p
	return paths[paths.size() - 1]


# 无放回加权抽样（T7 商店货架 / BOSS 武器候选共用）。items 元素为 String 路径或含 "path" 的 Dictionary。
func acq_weighted_sample(items: Array, n: int, bias: float = 1.0) -> Array:
	var pool := items.duplicate()
	var out := []
	while out.size() < n and not pool.is_empty():
		var paths := []
		for it in pool:
			paths.append(it if it is String else it["path"])
		var chosen: String = acq_weighted_pick(paths, bias)
		for i in range(pool.size()):
			var it = pool[i]
			if (it if it is String else it["path"]) == chosen:
				out.append(it)
				pool.remove_at(i)
				break
	return out


# BOSS 信物路径全集（数据驱动：扫描全部房间的 boss_relic_path）——精英掉落排除集。
func relic_paths() -> Array:
	var out := []
	for r in _ctrl.ALL_ROOMS:
		if r.boss_relic_path != "":
			out.append(r.boss_relic_path)
	return out


func sel_passive_size() -> int:
	return _ctrl._loadout_system.sel_arr("passive").size()
