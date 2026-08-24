class_name ReelSystem
extends RefCounted

# reel_system — 转轮系统（2026-08-09 从 duel_controller 拆分）
#
# 职责：转轮带构建（权重聚合 → 预算分配）、旋转推进（节拍器+加速）、按停锁定、格子落子。
# 状态共享：grid / grid_elem / frozen_cols / pending_jam_reel / pending_lock_reel / pending_chaos
#   仍由 DuelController 持有（敌人意图、结算等多处读写），本系统经 _ctrl 访问；
#   转轮专属状态（带子/游标/锁定）内聚在本类。
# 结果信号：spin_finished —— controller 等待它进入结算。
#
# 落点规则（方案 A）：3 根转轮 = base 的洗牌副本，玩家按停时机决定落点，
# 而非后台加权随机；频率 = 带子上该符号的格子数。
# MISS（2026-08-09 恢复）：装备命中率 <1.0 → 带子聚合 MISS 格（占比随 hit_rate 浮动）；
# MISS 与废铁同语义（kind=trash，不匹配/不结算），视觉显示「MISS」文字，玩家可滚过规避。

signal spin_finished

const MISS_SYMBOL = preload("res://resources/symbols/miss.tres")

const _SPIN_BASE_WAIT := 0.15          # 起始每跳间隔（秒）——调慢以便看清落点、凑三连 special
const _SPIN_MIN_WAIT := 0.06           # 最快每跳间隔（封顶也调慢，整体更易控）
const _STRIP_MIN_CELLS := 30           # 转轮带最小格数（整份平铺补足，不改变符号占比）
const _GOLD_CELLS := 2                 # 金币符号常驻格数（经济引擎，与装备频率解耦）
# 2026-08-09 传统 slots 频率（拍板）：格子数 = 权重档位（保底 2 = 目押下限），
# rare/epic 符号封顶 2 格（≤ 普通——大奖罕见，推翻旧「稀有度不影响次数」决策）。
const RARITY_RANK := {"common": 0, "uncommon": 1, "rare": 2, "epic": 3}
const _RARE_CAP_CELLS := 2             # rare/epic 符号格数上限（不得超过普通符号）

var _ctrl                                # DuelController
var _timer: Timer

var reel_strips: Array = []            # [reel] -> Array[ [SymbolData, element] ]
var reel_cursor: Array[int] = []       # [reel] -> 当前带子索引（旋转时递增，取模长度）
var reel_stopped: Array[bool] = []     # [reel] -> 该列是否已停
var _locked_prev_sym: Array = []       # [reel] -> 锁轮保留的上一轮符号
var _locked_prev_elem: Array[String] = []   # [reel] -> 锁轮保留的上一轮有效元素
var _spinning := false                 # 旋转进行中（供输入分支判断）
var _spin_ticks := 0                   # 已跳次数（用于加速上限）

var spinning: bool:
	get:
		return _spinning


func _init(ctrl) -> void:
	_ctrl = ctrl
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.timeout.connect(on_spin_tick)
	_ctrl.add_child(_timer)


# 开始一次旋转：构建转轮带、随机起点、启动节拍器。结果在 spin_finished 后结算。
# 冻结列已在回合一开始（_begin_player_turn）声明——此处仅让冻结列不转、其余正常转。
func begin_spin() -> void:
	reel_cursor = []
	reel_stopped = []
	_locked_prev_sym = []
	_locked_prev_elem = []
	for r in DuelController.REELS:
		if r in _ctrl.frozen_cols:
			# 冻结列：本轮不转、不可按停（锁定 spin 前的符号；结算时该格失效，见 _evaluate）
			reel_cursor.append(0)
			reel_stopped.append(true)
			_locked_prev_sym.append(_ctrl.grid[r][0] if _ctrl.grid.size() > r and _ctrl.grid[r].size() > 0 else DuelController.TRASH_SYMBOL)
			_locked_prev_elem.append(_ctrl.grid_elem[r][0] if _ctrl.grid_elem.size() > r and _ctrl.grid_elem[r].size() > 0 else "none")
			_ctrl.hud.set_reel_enabled(r, false)
			continue
		if r == _ctrl.pending_lock_reel:
			# 2026-08-14 锁轮语义修正（用户拍板）：锁定列本轮不转——转轮开始前即固定显示
			# 上一轮符号（金框标记），玩家直接看到"被锁"，不再有"转了但被替换"的割裂；
			# 锁住的符号【照常参与结算】（与冻结的"失效格"语义区分——锁 = 保留，冻 = 作废）
			reel_cursor.append(0)
			reel_stopped.append(true)
			_locked_prev_sym.append(_ctrl.grid[r][0] if _ctrl.grid.size() > r and _ctrl.grid[r].size() > 0 else DuelController.TRASH_SYMBOL)
			_locked_prev_elem.append(_ctrl.grid_elem[r][0] if _ctrl.grid_elem.size() > r and _ctrl.grid_elem[r].size() > 0 else "none")
			_ctrl.hud.set_reel_enabled(r, false)
			_ctrl.hud._refresh_cell(r, 0)   # spin 前刷新：金框 + 固定符号立即可见
			_ctrl.hud._log("🔒 第 %d 列被锁轮：本轮固定不转（符号照常结算）" % (r + 1))
			continue
		var strip_len = reel_strips[r].size() if reel_strips.size() > r and not reel_strips[r].is_empty() else 1
		reel_cursor.append(randi() % strip_len)
		reel_stopped.append(false)
		# 锁轮列：保留旋转前该列的符号与有效元素
		_locked_prev_sym.append(_ctrl.grid[r][0] if _ctrl.grid.size() > r and _ctrl.grid[r].size() > 0 else DuelController.TRASH_SYMBOL)
		_locked_prev_elem.append(_ctrl.grid_elem[r][0] if _ctrl.grid_elem.size() > r and _ctrl.grid_elem[r].size() > 0 else "none")
		# 旋转期间允许点击该列以停止
		_ctrl.hud.set_reel_enabled(r, true)
	_spinning = true
	_spin_ticks = 0
	_timer.wait_time = _SPIN_BASE_WAIT
	_timer.start()
	_ctrl.hud._log("转轮旋转中——按【空格】逐列停止，或点击某一列单独停下（不停就一直转）")


# 方案 B（2026-08-07）：跨装备聚合 (符号|有效元素) 权重，共享符号累加（同元素堆三连）；
# 2026-08-09 传统 slots 频率（拍板）：每符号格子数 = 权重档位（2-4 格，保底 2 目押下限），
# rare/epic 符号封顶 2 格（≤ 普通符号——大奖罕见）；MISS 按 miss_w/wsum 比例折算格数（保底 1）。
# 稀释表达 = 符号种类增多 → 条带变长（每符号格数稳定，频率可预期可目押），替代旧 16 格总预算。
# 结算/连锁/special 三连等下游逻辑不变（仍按 REELS x ROWS 落子统计）。
func build_strips() -> void:
	reel_strips = []
	if _ctrl.pool_items.is_empty():
		for r in DuelController.REELS:
			reel_strips.append([[DuelController.TRASH_SYMBOL, "none"]])
		return
	# —— 方案 B：跨装备聚合 (符号 | 有效元素) 权重 ——
	# 同一 (符号, 有效元素) 被多件装备携带时权重累加（同元素武器堆三连；异元素互不稀释符号总价值）。
	# 有效元素已在 _build_pool 用 _eff_element 解析（普通符号继承武器元素，special 优先 reel_element）。
	var agg := {}   # key("path|elem") -> {sym, elem, w, rank, sources}
	var miss_w := 0.0   # MISS 聚合权重：Σ 装备符号总权重 × (1 - hit_rate)
	for it in _ctrl.pool_items:
		var syms: Array = it["syms"]
		if syms.is_empty():
			continue
		var it_rank: int = RARITY_RANK.get(String(it.get("rarity", "common")), 0)   # 2026-08-09：携带装备稀有度（最高者决定封顶）
		var it_total_w := 0.0
		for s in syms:
			var w = max(0.0, s[1] + _ctrl.combat.agg_symbol_weight_mod(s[0]) + _ctrl._synergy_system.weight_mod(s[0]))
			if w <= 0.0:
				continue
			it_total_w += w
			var key: String = s[0].resource_path + "|" + s[2]
			if not agg.has(key):
				agg[key] = {"sym": s[0], "elem": s[2], "w": 0.0, "rank": 0, "sources": 0}
			agg[key]["w"] += w
			agg[key]["rank"] = maxi(int(agg[key]["rank"]), it_rank)
			agg[key]["sources"] += 1   # 共享源数（2026-08-14：≥2 件装备共用 → 构筑投资突破稀有度封顶，见 _RARE_CAP 判定）
		# 2026-08-09 恢复 MISS：命中率 1.0 = 无 miss（当前武器/技能均 <1.0，形成带子 MISS 段）
		var hit: float = clamp(it.get("hit", 1.0), 0.0, 1.0)
		if hit < 1.0:
			miss_w += it_total_w * (1.0 - hit)
	var wsum: float = 0.0
	for k in agg:
		wsum += agg[k]["w"]
	var base := []
	var total_cells := 0
	if wsum > 0.0:
		# 2026-08-09 传统 slots 频率：格子数 = 权重档位（保底 2 = 目押下限；≥2 → 3 格；≥4 → 4 格），
		# rare/epic（rank ≥ 2）封顶 2 格——稀有符号不得超过普通符号（大奖罕见）。
		# 2026-08-14 按 kind 分流：damage 攻击符号【不受】稀有度封顶（主输出按权重档位 2/3/4 格——
		# 修「反向稀有度惩罚」：同权重 5 的 uncommon 弩矢 4 格 vs rare 暗斩 2 格，带高稀有武器反而更刮）；
		# status/buff 等功能符号维持 rare/epic 封顶 2 格（大奖罕见语义本就指向机制符号）。
		# 2026-08-14 例外：共享符号 ≥2 源（sources ≥ 2）突破封顶走正常档位——修复「双同属性武器陷阱构装」
		# （低攻第二把被 max 攻 + 封顶双重吃掉，收益≈0，蒙特卡洛实测 +1%）。单件仍封顶。
		for k in agg:
			var cnt: int = 2
			var w: float = agg[k]["w"]
			if w >= 4.0:
				cnt = 4
			elif w >= 2.0:
				cnt = 3
			if agg[k]["sym"].kind != "damage" and int(agg[k]["rank"]) >= RARITY_RANK["rare"] and int(agg[k]["sources"]) < 2:
				cnt = mini(cnt, _RARE_CAP_CELLS)
			for _c in cnt:
				base.append([agg[k]["sym"], agg[k]["elem"]])
			total_cells += cnt
	# 2026-08-09 恢复 MISS：按 miss_w/wsum 比例折算格数（保底 1）——命中率越低带子越脏；
	# 废铁仍由敌人意图注入（chaos/abyss_erosion，见下）。金币常驻（经济引擎，与装备频率解耦）
	if miss_w > 0.0:
		var miss_cells: int = maxi(1, roundi(float(total_cells) * miss_w / maxf(0.001, wsum)))
		for _c in miss_cells:
			base.append([MISS_SYMBOL, "none"])
	for _c in _GOLD_CELLS:
		base.append([DuelController.GOLD_SYMBOL, "none"])
	# 敌人乱权：向整带注入额外废铁（等比重削弱所有装备，忠实还原「削弱优势」意图）
	if _ctrl.pending_chaos:
		var extra: int = roundi(float(base.size()) * 0.20)
		for _c in extra:
			base.append([DuelController.TRASH_SYMBOL, "none"])
	# S10 T2：深渊侵蚀注入额外废铁
	for _i in _ctrl.boss_trash:
		base.append([DuelController.TRASH_SYMBOL, "none"])
	# 最小带长保护：整份平铺到 _STRIP_MIN_CELLS 以上——只拉长周期，各符号占比完全不变
	if base.size() < _STRIP_MIN_CELLS:
		var unit = base.duplicate(true)
		while base.size() < _STRIP_MIN_CELLS:
			base.append_array(unit.duplicate(true))
	# 3 根转轮 = base 的洗牌副本（落点由玩家停止时机决定）
	for r in DuelController.REELS:
		var copy = base.duplicate(true)
		for i in range(copy.size() - 1, 0, -1):
			var j = randi() % (i + 1)
			var tmp = copy[i]
			copy[i] = copy[j]
			copy[j] = tmp
		reel_strips.append(copy)


# 节拍器回调：推进仍在旋转的转轮并逐步加速。没有自动停止——只有玩家按停才会锁定。
func on_spin_tick() -> void:
	if not _spinning:
		return
	_spin_ticks += 1
	var any_moving := false
	for r in DuelController.REELS:
		if not reel_stopped[r]:
			var strip_len = reel_strips[r].size() if reel_strips.size() > r and not reel_strips[r].is_empty() else 1
			reel_cursor[r] = (reel_cursor[r] + 1) % strip_len
			write_reel_cell(r)
			any_moving = true
	if not any_moving:
		finish_spin()
		return
	# 敌人夺轮（auto_stop）：每跳自动停一列（落点随机，玩家无法目押停轮时机；与手动按停共存）
	if _ctrl.pending_auto_stop:
		stop_next_reel()
	var w = max(_SPIN_MIN_WAIT, _SPIN_BASE_WAIT - _spin_ticks * 0.0010)
	_timer.wait_time = w


# 把当前带子位置的符号写入展示格（旋转中每跳调用，复用既有 _refresh_cell）。
func write_reel_cell(r: int) -> void:
	var strip = reel_strips[r] if reel_strips.size() > r else null
	if strip == null or strip.is_empty():
		_ctrl.grid[r][0] = DuelController.TRASH_SYMBOL
		_ctrl.grid_elem[r][0] = "none"
	else:
		var idx = reel_cursor[r] % strip.size()
		_ctrl.grid[r][0] = strip[idx][0]
		_ctrl.grid_elem[r][0] = strip[idx][1]
	_ctrl.hud._refresh_cell(r, 0)


# 锁定某列：pos<0 表示锁定在当前带子位置（按停时机）。注废/锁轮列覆盖结果。
func lock_reel(r: int) -> void:
	if r < 0 or r >= DuelController.REELS or reel_stopped[r]:
		return
	if r == _ctrl.pending_jam_reel:
		_ctrl.grid[r][0] = DuelController.TRASH_SYMBOL
		_ctrl.grid_elem[r][0] = "none"
		_ctrl.pending_jam_reel = -1
		_ctrl.hud._log("⚠ 干扰列作废：第 %d 列被废铁占据（红框列，按停即废）" % (r + 1))   # 2026-08-14 UX：替换即时提示
	elif r == _ctrl.pending_lock_reel:
		_ctrl.grid[r][0] = _locked_prev_sym[r]
		_ctrl.grid_elem[r][0] = _locked_prev_elem[r]
		_ctrl.pending_lock_reel = -1
		_ctrl.hud._log("🔒 锁轮列：第 %d 列保留旋转前符号（金框列）" % (r + 1))
	else:
		var strip = reel_strips[r]
		var idx = reel_cursor[r] % strip.size()
		_ctrl.grid[r][0] = strip[idx][0]
		_ctrl.grid_elem[r][0] = strip[idx][1]
	reel_stopped[r] = true
	_ctrl.hud._refresh_cell(r, 0)
	_ctrl.hud.set_reel_enabled(r, false)
	var all := true
	for rr in DuelController.REELS:
		if not reel_stopped[rr]:
			all = false
			break
	if all:
		finish_spin()


# 停止下一列（空格）：依次锁定尚未停下的列，时机由玩家掌握。
func stop_next_reel() -> void:
	for r in DuelController.REELS:
		if not reel_stopped[r]:
			lock_reel(r)
			return


# 全部转轮停下：停止节拍器、复位交互态、发信号让结算继续。
func finish_spin() -> void:
	if not _spinning:
		return
	_spinning = false
	_timer.stop()
	for r in DuelController.REELS:
		_ctrl.hud.set_reel_enabled(r, false)
	_ctrl.pending_jam_reel = -1
	_ctrl.pending_lock_reel = -1
	_ctrl.pending_chaos = false
	_ctrl.pending_auto_stop = false
	spin_finished.emit()


# 房间开局 / 精华注入后重建落子：清空角标，逐格从新带子随机落子（先于旋转的初始画面）。
func reset_grid() -> void:
	_ctrl.hud._clear_badges()
	_ctrl.grid_elem = []
	for reel in DuelController.REELS:
		_ctrl.grid_elem.append([])
		for row in DuelController.ROWS:
			_ctrl.grid_elem[reel].append("none")
			_ctrl.grid[reel][row] = DuelController.TRASH_SYMBOL
			if reel_strips.size() > reel and not reel_strips[reel].is_empty():
				var idx = randi() % reel_strips[reel].size()
				_ctrl.grid[reel][row] = reel_strips[reel][idx][0]
				_ctrl.grid_elem[reel][row] = reel_strips[reel][idx][1]
			_ctrl.hud._refresh_cell(reel, row)
	_ctrl.invalidate_state()   # grid_elem 重新实例化


# ----------------------------------------------------------------------------
# P2 架构还债（2026-08-24）：符号池构建自 duel_controller._build_pool 迁入——
# 池/带子/落子同域（pool_items 在此被 build_strips 消费）。controller 留单行转发器。
# ----------------------------------------------------------------------------

# 装备自洽建池：强度轴映射 → 武器/技能/精华各生成符号段 → 扁平池 + 金币常驻。
func build_pool(loadout: Array) -> void:
	_ctrl._synergy_system.refresh()   # 装备集合变化：重估共鸣激活集（每房/换装时一次）
	_ctrl.pool.clear()
	_ctrl.pool_items.clear()
	_ctrl.loadout_names.clear()
	_ctrl._weapon_power_map = {}
	_ctrl._item_crit_map = {}
	# 强度轴映射：符号 resource_path -> 该物品有效攻击力(base_power)；共享符号取最高者（最强来源）。
	for path in loadout:
		var wd: WeaponData = load(path)
		if wd == null or wd.symbols == null:
			_ctrl.hud._log("⚠ 武器加载失败（符号未入池）: %s" % path)
			continue
		var eff: float = wd.base_power
		for sw in wd.symbols:
			if sw == null or sw.symbol == null:
				continue
			var sp = sw.symbol.resource_path
			_ctrl._weapon_power_map[sp] = max(_ctrl._weapon_power_map.get(sp, 0.0), eff)
			_ctrl._item_crit_map[sp] = max(_ctrl._item_crit_map.get(sp, 1.0), wd.crit_mult)
			_ctrl._item_crit_chance_map[sp] = max(_ctrl._item_crit_chance_map.get(sp, 0.0), wd.crit_chance)
			if wd.triple_pierce:
				_ctrl._item_pierce_map[sp] = true
	# 无名虚空（deprived_level≥2）：技能符号也不进强度聚合
	if _ctrl.deprived_level < 2:
		for path in _ctrl.selected_skills:
			var sd: SkillData = load(path)
			if sd == null or sd.symbol == null:
				continue
			var eff2: float = sd.base_power
			var sp2 = sd.symbol.resource_path
			_ctrl._weapon_power_map[sp2] = max(_ctrl._weapon_power_map.get(sp2, 0.0), eff2)
			_ctrl._item_crit_map[sp2] = max(_ctrl._item_crit_map.get(sp2, 1.0), sd.crit_mult)
			_ctrl._item_crit_chance_map[sp2] = max(_ctrl._item_crit_chance_map.get(sp2, 0.0), sd.crit_chance)
			if sd.triple_pierce:
				_ctrl._item_pierce_map[sp2] = true
	for path in loadout:
		var wd: WeaponData = load(path)
		if wd == null:
			continue
		_ctrl.loadout_names.append(wd.weapon_name)
		if wd.symbols == null or wd.symbols.is_empty():
			continue
		var syms := []
		for sw in wd.symbols:
			if sw == null or sw.symbol == null:
				continue
			syms.append([sw.symbol, float(sw.weight), eff_element(sw.symbol, wd)])
		var hit: float = clamp(wd.hit_rate, 0.0, 1.0)
		var wd_rar: Variant = wd.get("rarity")
		_ctrl.pool_items.append({"name": wd.weapon_name, "hit": hit, "syms": syms, "rarity": String(wd_rar if wd_rar != null else "common")})
	# 技能段（deprived_level≥2 剥离不入池）
	if _ctrl.deprived_level < 2:
		for path in _ctrl.selected_skills:
			var sd: SkillData = load(path)
			if sd == null or sd.symbol == null:
				continue
			var ess_elem: String = sd.symbol.element if sd.symbol.element != "none" else "none"
			var hit: float = clamp(sd.hit_rate, 0.0, 1.0)
			var sd_rar: Variant = sd.get("rarity")
			_ctrl.pool_items.append({"name": ("技能" + sd.icon), "hit": hit, "syms": [[sd.symbol, float(sd.weight), ess_elem]], "rarity": String(sd_rar if sd_rar != null else "common")})
	# 元素精华：使用后本房间内注入对应元素攻击符号
	for e in _ctrl.room_element_mult:
		var ess_sym: SymbolData = DuelController.ESSENCE_SYMBOLS.get(e)
		if ess_sym != null:
			_ctrl.pool_items.append({"name": ("精华·" + ElementCounter.label(e)), "hit": 1.0, "syms": [[ess_sym, DuelController.ESSENCE_POOL_WEIGHT, e]], "rarity": "common"})
	# 扁平池（图例/状态查询等 legacy 消费者）+ 金币常驻
	for it in _ctrl.pool_items:
		for s in it["syms"]:
			_ctrl.pool.append([s[0], s[1], s[2]])
	_ctrl.pool.append([DuelController.GOLD_SYMBOL, _ctrl.BALANCE.gold_pool_weight, "none"])
	_ctrl.hud._update_enemy_element()
	_ctrl.invalidate_state()


# 符号「有效元素」（武器元素化）：special 优先武器 reel_element；其余自身优先、否则继承武器元素。
func eff_element(sym: SymbolData, wd: WeaponData) -> String:
	if sym.kind == "special":
		return wd.reel_element if wd.reel_element != "none" else sym.element
	return sym.element if sym.element != "none" else wd.element
