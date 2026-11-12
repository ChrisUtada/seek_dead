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
# 2026-11-12 Step 2：停轮吸附时长沿用 Step 1 的区间常量；用 preload 而非全局类名，
# 避免 --script / 未打开编辑器的环境读不到 global_script_class_cache。
const _REEL_CLOCK = preload("res://scripts/battle/reel_clock.gd")

const _SPIN_BASE_WAIT := 1.0 / 9.0     # 巡航每跳间隔（秒）——9 格/秒（Step 3）
const _SPIN_MIN_WAIT := 1.0 / 12.0     # 最快每跳间隔——12 格/秒封顶（Step 3）
const STARTUP_CPS := 5.0               # 起转初速：给首轮观察留出时间，不改变巡航/封顶
const STARTUP_RAMP_SECONDS := 0.32     # 二次速度曲线从初速升至巡航，再进入原有逐拍加速
const _STRIP_MIN_CELLS := 30           # 转轮带最小格数（整份平铺补足，不改变符号占比）
const _GOLD_CELLS := 2                 # 金币符号常驻格数（经济引擎，与装备频率解耦）
const ABSORB_DECEL_CELLS := 1.0        # 吸附减速格数（Step 3 再按手感调）
# 2026-11-12 Step 3：逐列基础停顿（方案 §5）——自动/夺轮停列的基础间隔与递增。
const AUTO_STOP_BASE_WAIT := 0.25      # 第 1 列自动停下的基础停顿（方案 0.22–0.28）
const AUTO_STOP_STEP_WAIT := 0.07      # 后续每列递增（方案 0.06–0.08）
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
var _startup_ticks := 0                # 启动段拍数；巡航后的加速从启动段结束时重新计拍
var _startup_tween: Tween = null       # 逐帧更新启动速度；逻辑拍仍由同一 Timer 推进
var _pending_stops: Dictionary = {}    # P1 输入缓冲：reel -> true（最多等到下一逻辑拍锁定）
# 2026-11-12 Step 2：停轮先记录、再吸附、最后落子。
# reel -> {idx, reason, progress, tween}；吸附中拒绝重复停轮，网格与结算只在完成时更新。
var _absorb: Dictionary = {}
# 2026-11-12 Step 3：逐列自动停轮节奏与本次旋转的模型耗时（秒）。
var _auto_stop_index := 0
var _auto_stop_left := AUTO_STOP_BASE_WAIT
var _spin_model_seconds := 0.0
var _spin_end_model := 0.0
var _last_spin_seconds := 0.0

var spinning: bool:
	get:
		return _spinning


# 当前旋转节拍（秒/格）：供转轮滚动视觉按同一速度推进（UI 只读）。
func current_spin_wait() -> float:
	if _timer == null:
		return _base_wait()
	return _timer.wait_time


# P1 预设接管速度；未接入时回落到原常量，保证旧探针/单元测试口径不变。
func _base_wait() -> float:
	if _ctrl.readability != null:
		return float(_ctrl.readability.base_wait)
	return _SPIN_BASE_WAIT


func _min_wait() -> float:
	if _ctrl.readability != null:
		return float(_ctrl.readability.min_wait)
	return _SPIN_MIN_WAIT


func _accel() -> float:
	if _ctrl.readability != null:
		return float(_ctrl.readability.accel)
	return 0.0020


func _startup_wait(base: float, progress: float) -> float:
	var start_factor: float = clampf(STARTUP_CPS * base, 0.0, 1.0)
	var u: float = clampf(progress, 0.0, 1.0)
	var factor: float = start_factor + (1.0 - start_factor) * u * u
	return base / maxf(factor, 0.001)


func _spin_wait_at(elapsed: float, spin_ticks: int, startup_ticks: int) -> float:
	var base: float = _ctrl.growth.spin_wait_base(_base_wait())
	if elapsed < STARTUP_RAMP_SECONDS:
		return _startup_wait(base, elapsed / STARTUP_RAMP_SECONDS)
	var accel_ticks: int = maxi(0, spin_ticks - startup_ticks)
	return maxf(_min_wait(), base - accel_ticks * _accel())


func _set_startup_progress(progress: float) -> void:
	if not _spinning or _timer == null:
		return
	var base: float = _ctrl.growth.spin_wait_base(_base_wait())
	_timer.wait_time = _startup_wait(base, progress)


func _finish_startup() -> void:
	_startup_tween = null
	if _spinning:
		_timer.wait_time = _spin_wait_at(STARTUP_RAMP_SECONDS, _spin_ticks, _startup_ticks)


func _clear_startup_tween() -> void:
	if _startup_tween != null and _startup_tween.is_valid():
		_startup_tween.kill()
	_startup_tween = null


func _start_startup_tween() -> void:
	_clear_startup_tween()
	_startup_tween = _ctrl.create_tween()
	_startup_tween.tween_method(_set_startup_progress, 0.0, 1.0, STARTUP_RAMP_SECONDS)
	_startup_tween.finished.connect(_finish_startup)


func has_pending_stop(r: int) -> bool:
	return bool(_pending_stops.get(r, false))


# Step 2：该列是否正处于「停轮吸附」中（已记录落点，尚未写格子/结算）。
func is_absorbing(r: int) -> bool:
	return _absorb.has(r)


# 吸附进度 0..1（供 ReelSpinView 只读驱动减速动画）；非吸附返回 -1。
func absorb_progress(r: int) -> float:
	if not _absorb.has(r):
		return -1.0
	return float(_absorb[r].get("progress", 0.0))


# 吸附目标格（请求停轮时记录的落点）。
func absorb_target(r: int) -> int:
	return int(_absorb[r].get("idx", -1)) if _absorb.has(r) else -1


# 一列是否仍占用输入：已停或吸附中都算 busy，避免重复停轮/重复结算。
func is_busy(r: int) -> bool:
	return r >= 0 and r < reel_stopped.size() and (bool(reel_stopped[r]) or is_absorbing(r))


# 上一次完整旋转的模型耗时（节拍累计 + 吸附，秒）。供探针/报告记录，不参与结算。
func last_spin_seconds() -> float:
	return _last_spin_seconds


# 本次旋转已累计的模型时间（秒，不含尚未发生的吸附）。
func spin_model_seconds() -> float:
	return _spin_model_seconds


# 自动停轮节奏（Step 3）：第 n 列的目标间隔 = 基础 + 递增 × n。
func auto_stop_interval(index: int) -> float:
	return AUTO_STOP_BASE_WAIT + AUTO_STOP_STEP_WAIT * maxi(0, index)


func _reset_auto_stop() -> void:
	_auto_stop_index = 0
	_auto_stop_left = AUTO_STOP_BASE_WAIT


func _init(ctrl) -> void:
	_ctrl = ctrl
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.timeout.connect(on_spin_tick)
	_ctrl.add_child(_timer)


# 开始一次旋转：构建转轮带、随机起点、启动节拍器。结果在 spin_finished 后结算。
# 冻结列已在回合一开始（_begin_player_turn）声明——此处仅让冻结列不转、其余正常转。
func begin_spin() -> void:
	_clear_absorbs()
	reel_cursor = []
	reel_stopped = []
	_pending_stops.clear()
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
	_startup_ticks = 0
	_reset_auto_stop()
	_spin_model_seconds = 0.0
	_spin_end_model = 0.0
	_last_spin_seconds = 0.0
	_timer.wait_time = _spin_wait_at(0.0, 0, 0)
	_timer.start()
	_start_startup_tween()
	if _ctrl.readability != null:
		_ctrl.readability.begin_spin()
	_ctrl.hud._refresh_p1_previews()
	if _ctrl._telemetry != null:
		_ctrl._telemetry.spin_start()   # M1-06：旋转耗时
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
			var cnt: int = cells_for(agg[k]["w"], agg[k]["sym"].kind, int(agg[k]["rank"]), int(agg[k]["sources"]))
			cnt = _apply_trim(String(k), cnt)   # G7-B B1：主动减带（保底 1 格）
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


# 单条 (符号|有效元素) 聚合项的格子数（M1-02：build_strips 与奖励灌注预览共用，
# 避免「卡片说 +N 格、实际带子不变」的口径漂移）。
static func cells_for(w: float, kind: String, rank: int, sources: int) -> int:
	var cnt := 2
	if w >= 4.0:
		cnt = 4
	elif w >= 2.0:
		cnt = 3
	if kind != "damage" and rank >= RARITY_RANK["rare"] and sources < 2:
		cnt = mini(cnt, _RARE_CAP_CELLS)
	return cnt


# 节拍器回调：推进仍在旋转的转轮并逐步加速。没有自动停止——只有玩家按停才会锁定。
func on_spin_tick() -> void:
	if not _spinning:
		return
	_spin_ticks += 1
	# 模型耗时：本拍间隔 = 上一拍设置的 wait_time（冻结/吸附时也计入真实等待）。
	if _spin_model_seconds < STARTUP_RAMP_SECONDS:
		_startup_ticks += 1
	_spin_model_seconds += current_spin_wait()
	var any_active := false
	for r in DuelController.REELS:
		if reel_stopped[r]:
			continue
		any_active = true
		if is_absorbing(r):
			continue   # 停轮吸附中：结果已记录，不再推进/改写该列
		var strip_len = reel_strips[r].size() if reel_strips.size() > r and not reel_strips[r].is_empty() else 1
		reel_cursor[r] = (reel_cursor[r] + 1) % strip_len
		write_reel_cell(r)
	if not any_active:
		finish_spin()
		return
	# P1 输入缓冲：上一拍按停时视觉中心还在「下一格」，本拍已到达——现在提交停轮吸附。
	for r in _pending_stops.keys():
		if reel_stopped[r] or is_absorbing(r):
			_pending_stops.erase(r)
			continue
		_pending_stops.erase(r)
		var strip_len2: int = reel_strips[r].size() if reel_strips.size() > r and not reel_strips[r].is_empty() else 1
		_begin_absorb(r, int(reel_cursor[r]) % strip_len2, "player")
	if not _spinning:
		return   # 缓冲落子可能刚好停完最后一列，finish_spin 已接管
	_ctrl.hud._refresh_p1_previews()
	# 敌人夺轮（auto_stop）：Step 3 改为按「逐列基础停顿」节奏停列——
	# 第 1 列 0.25s，之后每列 +0.07s；仍走与手动相同的 stop_next_reel/吸附入口。
	if _ctrl.pending_auto_stop:
		_auto_stop_left -= current_spin_wait()
		if _auto_stop_left <= 0.0:
			stop_next_reel(false, "forced")
			_auto_stop_index += 1
			_auto_stop_left = auto_stop_interval(_auto_stop_index)
	_timer.wait_time = _spin_wait_at(_spin_model_seconds, _spin_ticks, _startup_ticks)


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


# M2-01 洞察：某列当前带子位置的下一格符号（只读，供 HUD 旋转中预览）。无带子返回 null。
func next_symbol(r: int) -> SymbolData:
	var arr := next_symbols(r, 1)
	return arr[0] if not arr.is_empty() else null


# P1 预览：从 base_index 之后取 count 个符号（不含 base_index 本身）。
# base_index < 0 时用逻辑游标；旋转中 HUD 传视觉中心索引，保证「看到的下一格」就是真的下一格。
func next_symbols(r: int, count: int, base_index: int = -1) -> Array:
	var strip = reel_strips[r] if reel_strips.size() > r else null
	if strip == null or strip.is_empty() or count <= 0:
		return []
	var n: int = strip.size()
	var base: int = base_index if base_index >= 0 else int(reel_cursor[r])
	var out: Array = []
	for i in range(1, count + 1):
		out.append(strip[(base + i) % n][0])
	return out


# 锁定某列：默认取视觉中心（P1），并在需要时进入最多一拍的输入缓冲。
# use_visual=false 用于敌人自动停等非玩家目押路径；reason 只影响遥测与 HUD 反馈。
func lock_reel(r: int, use_visual: bool = true, reason: String = "player") -> void:
	if r < 0 or r >= DuelController.REELS or reel_stopped[r] or is_absorbing(r):
		return
	# 2026-11-12 Step 1：缠绕——本回合只能按指定方向逐列停止。
	# 只约束玩家手动按停；自动停轮（reason="forced"）不受限，避免与夺轮/冻结叠加时软锁。
	if reason == "player" and _ctrl.debuffs != null and _ctrl.debuffs.entangle_active():
		var need: int = _ctrl.debuffs.entangle_next(self)
		if need >= 0 and r != need:
			var dir_txt: String = "从左往右" if _ctrl.debuffs.entangle_order() == "ltr" else "从右往左"
			_ctrl.hud._show_action_feedback("缠绕：先停第 %d 列" % (need + 1))
			_ctrl.hud._log("🪢 缠绕：本回合需%s逐列停止（下一列：第 %d 列）" % [dir_txt, need + 1])
			return
	# 注废/锁轮列的结果是机制决定的，不进入视觉解析或输入缓冲。
	if r == _ctrl.pending_jam_reel or r == _ctrl.pending_lock_reel:
		_lock_at(r, 0, reason)
		return
	var strip = reel_strips[r] if reel_strips.size() > r else null
	var idx := 0
	if strip != null and not strip.is_empty():
		var n: int = strip.size()
		var cur: int = int(reel_cursor[r]) % n
		idx = cur
		if reason == "player" and use_visual and _ctrl.readability != null:
			var vi: int = _ctrl.hud.visual_center_index(r)
			if vi >= 0:
				vi %= n
				if vi == cur:
					idx = vi
				elif vi == (cur + 1) % n and (_ctrl.readability.buffer_enabled or _ctrl.readability.steady_hand_ready()):
					# 视觉中心已经到下一格、逻辑尚未推进：等到下一拍（最多一拍）。
					# G7-A S1「稳手」：即使预设未开缓冲，每回合也允许这样一次。
					if not has_pending_stop(r):
						_pending_stops[r] = true
						_ctrl.readability.on_buffer_queued()
						if not _ctrl.readability.buffer_enabled:
							_ctrl.readability.consume_steady_hand()
						_ctrl.hud._log("⏳ 第 %d 列进入输入缓冲：下一拍锁定视觉中心符号" % (r + 1))
					return
				elif _ctrl.readability.visual_stop and (vi == (cur + 1) % n or vi == (cur - 1 + n) % n):
					# 视觉对齐但不开缓冲：立即锁定玩家看到的那一格（最多前后一格，不跨多格）。
					idx = vi
	_begin_absorb(r, idx, reason)


# Step 2：停轮请求先记录，不立即写格子；0.12–0.16s 减速吸附结束才落子并进入结算。
# 吸附是本列「请求之后唯一允许的动作」：期间拒绝重复停轮，位置不再由节拍器推进。
func _begin_absorb(r: int, idx: int, reason: String) -> void:
	if r < 0 or r >= DuelController.REELS or reel_stopped[r] or is_absorbing(r):
		return
	var strip = reel_strips[r] if reel_strips.size() > r else null
	if strip == null or strip.is_empty():
		_lock_at(r, 0, reason)   # 无带子：保持旧行为（直接落废铁）
		return
	idx = int(idx) % strip.size()
	_pending_stops.erase(r)
	var secs: float = _absorb_seconds()
	_spin_end_model = maxf(_spin_end_model, _spin_model_seconds + secs)
	var tween: Tween = _ctrl.create_tween()
	_absorb[r] = {"idx": idx, "reason": reason, "progress": 0.0, "tween": tween}
	_ctrl.hud.set_reel_enabled(r, false)   # 吸附中拒绝点击/空格重复停列
	tween.tween_method(_set_absorb_progress.bind(r), 0.0, 1.0, secs)
	tween.finished.connect(_complete_absorb.bind(r))


# 吸附时长：按当前节拍折算速度与减速格数，收敛到 Step 1 的 0.12–0.16s 区间。
func _absorb_seconds() -> float:
	var speed: float = 1.0 / maxf(current_spin_wait(), 0.001)
	return clampf(2.0 * ABSORB_DECEL_CELLS / maxf(speed, 0.001),
		_REEL_CLOCK.MIN_STOP_SECONDS, _REEL_CLOCK.MAX_STOP_SECONDS)


func _set_absorb_progress(p: float, r: int) -> void:
	if _absorb.has(r):
		_absorb[r]["progress"] = clampf(p, 0.0, 1.0)


# 吸附完成：此时才写入格子符号、收尾并检查是否所有列都停完。
func _complete_absorb(r: int) -> void:
	if not _absorb.has(r):
		return
	var rec: Dictionary = _absorb[r]
	_absorb.erase(r)
	_lock_at(r, int(rec.get("idx", 0)), String(rec.get("reason", "player")))


# 中断吸附（新回合/房间重置）：只清理状态，不落子。
func _clear_absorbs() -> void:
	for r in _absorb.keys():
		var tw = _absorb[r].get("tween")
		if tw != null and is_instance_valid(tw):
			tw.kill()
	_absorb.clear()


# 真正落子并收尾（不经过视觉解析；吸附完成才走这里）。
func _lock_at(r: int, idx: int, reason: String) -> void:
	if r < 0 or r >= DuelController.REELS or reel_stopped[r]:
		return
	_pending_stops.erase(r)
	var sym = DuelController.TRASH_SYMBOL
	if r == _ctrl.pending_jam_reel:
		_ctrl.grid[r][0] = DuelController.TRASH_SYMBOL
		_ctrl.grid_elem[r][0] = "none"
		_ctrl.pending_jam_reel = -1
		sym = DuelController.TRASH_SYMBOL
		reason = "jam"
		_ctrl.hud._log("⚠ 干扰列作废：第 %d 列被废铁占据（红框列，按停即废）" % (r + 1))   # 2026-08-14 UX：替换即时提示
	elif r == _ctrl.pending_lock_reel:
		_ctrl.grid[r][0] = _locked_prev_sym[r]
		_ctrl.grid_elem[r][0] = _locked_prev_elem[r]
		_ctrl.pending_lock_reel = -1
		sym = _locked_prev_sym[r]
		reason = "lock"
		_ctrl.hud._log("🔒 锁轮列：第 %d 列保留旋转前符号（金框列）" % (r + 1))
	else:
		var strip = reel_strips[r]
		if strip != null and not strip.is_empty():
			idx = int(idx) % strip.size()
			_ctrl.grid[r][0] = strip[idx][0]
			_ctrl.grid_elem[r][0] = strip[idx][1]
			sym = strip[idx][0]
		else:
			_ctrl.grid[r][0] = DuelController.TRASH_SYMBOL
			_ctrl.grid_elem[r][0] = "none"
	reel_stopped[r] = true
	_ctrl.hud._refresh_cell(r, 0)
	_ctrl.hud.set_reel_enabled(r, false)
	if _ctrl.readability != null:
		_ctrl.readability.on_stop(r, sym, reason)
	_ctrl.hud._refresh_p1_previews()
	var all := true
	for rr in DuelController.REELS:
		if not reel_stopped[rr]:
			all = false
			break
	if all:
		finish_spin()


# 停止下一列（空格）：依次锁定尚未停下的列，时机由玩家掌握。
# 输入缓冲中的列不会重复入队；敌人 auto_stop 传 use_visual=false / reason="forced"。
func stop_next_reel(use_visual: bool = true, reason: String = "player") -> void:
	# 2026-11-12 Step 3：缠绕时「下一列」必须按指定方向——否则空格键会反复点被拒绝的列导致软锁。
	# 自动停轮（forced）不受此约束，仍按普通顺序。
	if reason == "player" and _ctrl.debuffs != null and _ctrl.debuffs.entangle_active():
		var need: int = _ctrl.debuffs.entangle_next(self)
		if need >= 0 and not reel_stopped[need] and not is_absorbing(need) and not has_pending_stop(need):
			lock_reel(need, use_visual, reason)
			return
	for r in DuelController.REELS:
		if not reel_stopped[r] and not is_absorbing(r) and not has_pending_stop(r):
			lock_reel(r, use_visual, reason)
			return


# 全部转轮停下：停止节拍器、复位交互态、发信号让结算继续。
func finish_spin() -> void:
	if not _spinning:
		return
	_last_spin_seconds = maxf(_spin_model_seconds, _spin_end_model)
	_spinning = false
	_clear_startup_tween()
	_clear_absorbs()   # 防御性清理：所有列都已停，不应再有吸附中的记录
	_timer.stop()
	_pending_stops.clear()
	if _ctrl._telemetry != null:
		_ctrl._telemetry.spin_end()
	for r in DuelController.REELS:
		_ctrl.hud.set_reel_enabled(r, false)
	_ctrl.pending_jam_reel = -1
	_ctrl.pending_lock_reel = -1
	_ctrl.pending_chaos = false
	_ctrl.pending_auto_stop = false
	if _ctrl.readability != null:
		_ctrl.readability.finish_spin()
	_ctrl.hud._refresh_p1_previews()
	spin_finished.emit()


# 房间开局 / 精华注入后重建落子：清空角标，逐格从新带子随机落子（先于旋转的初始画面）。
func reset_grid() -> void:
	_clear_absorbs()   # 新房间/精华注入：丢弃未完成的吸附记录
	_ctrl.hud._clear_badges()
	_ctrl.hud._clear_stop_feedback()   # 新房间/精华注入：上一回合的停轮结果不再适用
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
# 2026-11-08（G8）：按物品段拆分；各段纯函数（make_pool_item / weapon_syms / skill_pool_item /
# essence_pool_item / flatten_pool）不读写 _ctrl，装配顺序与拆分前逐段一致。
func build_pool(loadout: Array) -> void:
	_ctrl._synergy_system.refresh()   # 装备集合变化：重估共鸣激活集（每房/换装时一次）
	_reset_pool_state()
	_apply_weapon_strength(loadout)
	if _ctrl.deprived_level < 2:
		_apply_skill_strength()   # 无名虚空（deprived_level≥2）：技能符号也不进强度聚合
	_collect_weapon_items(loadout)
	if _ctrl.deprived_level < 2:
		_collect_skill_items()   # 技能段（deprived_level≥2 剥离不入池）
	_collect_essence_items()
	# 扁平池（图例/状态查询等 legacy 消费者）+ 金币常驻
	var flat: Array = flatten_pool(_ctrl.pool_items, DuelController.GOLD_SYMBOL, _ctrl.BALANCE.gold_pool_weight)
	_ctrl.pool.clear()
	_ctrl.pool.append_array(flat)
	_ctrl.hud._update_enemy_element()
	_ctrl.invalidate_state()


func _reset_pool_state() -> void:
	_ctrl.pool.clear()
	_ctrl.pool_items.clear()
	_ctrl.loadout_names.clear()
	_ctrl._weapon_power_map = {}
	_ctrl._item_crit_map = {}
	_ctrl._item_crit_chance_map = {}
	_ctrl._item_pierce_map = {}
	_ctrl._item_pierce_at = {}
	_ctrl._item_status_bonus = {}


# 强度轴映射：符号 resource_path -> 该物品有效攻击力(base_power)；共享符号取最高者（最强来源）。
func _apply_weapon_strength(loadout: Array) -> void:
	for path in loadout:
		var wd: WeaponData = load(path)
		if wd == null or wd.symbols == null:
			_ctrl.hud._log("⚠ 武器加载失败（符号未入池）: %s" % path)
			continue
		var style_power: int = _ctrl._forge_styles.power_bonus(path) if _ctrl._forge_styles != null else 0
		var style_pierce: int = _ctrl._forge_styles.pierce_at(path) if _ctrl._forge_styles != null else 3
		var style_status: int = _ctrl._forge_styles.status_bonus(path) if _ctrl._forge_styles != null else 0
		var eff: float = wd.base_power + _ctrl.mastery.forge_bonus(path) + style_power   # M2-02 锋铸 + G6-05 铸式
		for sw in wd.symbols:
			if sw == null or sw.symbol == null:
				continue
			var sp = sw.symbol.resource_path
			_ctrl._weapon_power_map[sp] = max(_ctrl._weapon_power_map.get(sp, 0.0), eff)
			var crit_add: float = _ctrl.mastery.crit_bonus(path) if _ctrl.mastery != null else 0.0
			_ctrl._item_crit_map[sp] = max(_ctrl._item_crit_map.get(sp, 1.0), wd.crit_mult + crit_add)   # G7-A S2 暴虐
			_ctrl._item_crit_chance_map[sp] = max(_ctrl._item_crit_chance_map.get(sp, 0.0), wd.crit_chance)
			if wd.triple_pierce:
				_ctrl._item_pierce_map[sp] = true
				_ctrl._item_pierce_at[sp] = mini(int(_ctrl._item_pierce_at.get(sp, 3)), style_pierce)
			if style_status > 0:
				_ctrl._item_status_bonus[sp] = maxi(int(_ctrl._item_status_bonus.get(sp, 0)), style_status)


func _apply_skill_strength() -> void:
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


# G7-B B1：符号精简——按本局精简状态扣格（每符号保底 1 格）。无精简系统时原样返回。
func _apply_trim(key: String, cells: int) -> int:
	if _ctrl._trim == null:
		return cells
	var cut: int = int(_ctrl._trim.trimmed.get(key, 0))
	return maxi(1, cells - cut) if cut > 0 else cells


func _collect_weapon_items(loadout: Array) -> void:
	for path in loadout:
		var wd: WeaponData = load(path)
		if wd == null:
			continue
		_ctrl.loadout_names.append(wd.weapon_name)
		if wd.symbols == null or wd.symbols.is_empty():
			continue
		# 权重修正按 symbol path 汇总后交给纯函数（M2-02 调律 + G6-05 铸式权重）
		var weight_bonus := {}
		for sw in wd.symbols:
			if sw == null or sw.symbol == null:
				continue
			var sp: String = sw.symbol.resource_path
			var style_w: float = _ctrl._forge_styles.weight_delta(path, sp) if _ctrl._forge_styles != null else 0.0
			weight_bonus[sp] = _ctrl.mastery.tune_bonus(path, sp) + style_w
		var hit: float = clampf(wd.hit_rate + (_ctrl._forge_styles.hit_delta(path) if _ctrl._forge_styles != null else 0.0), 0.0, 1.0)
		_ctrl.pool_items.append(make_pool_item(wd.weapon_name, hit, weapon_syms(wd, weight_bonus), wd.get("rarity")))


func _collect_skill_items() -> void:
	for path in _ctrl.selected_skills:
		var sd: SkillData = load(path)
		if sd == null or sd.symbol == null:
			continue
		_ctrl.pool_items.append(skill_pool_item(sd))


# 元素精华：使用后本房间内注入对应元素攻击符号
func _collect_essence_items() -> void:
	for e in _ctrl.room_element_mult:
		var ess_sym: SymbolData = DuelController.ESSENCE_SYMBOLS.get(e)
		if ess_sym != null:
			_ctrl.pool_items.append(essence_pool_item(e, ess_sym, DuelController.ESSENCE_POOL_WEIGHT))


# —— 纯函数段（不读写 _ctrl，供建池与定向测试共用）——

# 池条目统一格式：name / hit / syms / rarity。hit 与 rarity 在这里做一次兜底归一。
static func make_pool_item(item_name: String, hit_rate: float, syms: Array, rarity: Variant) -> Dictionary:
	return {"name": item_name, "hit": clampf(hit_rate, 0.0, 1.0), "syms": syms, "rarity": String(rarity if rarity != null else "common")}


# 武器符号段：[符号, 权重, 有效元素]；weight_bonus 按符号 resource_path 给出调律/铸式增量。
static func weapon_syms(wd: WeaponData, weight_bonus: Dictionary) -> Array:
	var syms := []
	for sw in wd.symbols:
		if sw == null or sw.symbol == null:
			continue
		var sp: String = sw.symbol.resource_path
		syms.append([sw.symbol, float(sw.weight) + float(weight_bonus.get(sp, 0.0)), effective_element(sw.symbol, wd.element, wd.reel_element)])
	return syms


# 技能段：元素取符号自身（none 保持 none，不继承武器元素）；名称带图标。
static func skill_pool_item(sd: SkillData) -> Dictionary:
	var elem: String = sd.symbol.element if sd.symbol.element != "none" else "none"
	return make_pool_item("技能" + sd.icon, sd.hit_rate, [[sd.symbol, float(sd.weight), elem]], sd.get("rarity"))


static func essence_pool_item(e: String, sym: SymbolData, weight: float) -> Dictionary:
	return make_pool_item("精华·" + ElementCounter.label(e), 1.0, [[sym, weight, e]], "common")


# 扁平池：[符号, 权重, 元素] 逐条展开，末尾追加金币常驻（不参与强度/元素克制）。
static func flatten_pool(items: Array, gold_sym: SymbolData, gold_weight: float) -> Array:
	var flat: Array = []
	for it in items:
		for s in it["syms"]:
			flat.append([s[0], s[1], s[2]])
	flat.append([gold_sym, gold_weight, "none"])
	return flat


# 符号「有效元素」（武器元素化）：special 优先武器 reel_element；其余自身优先、否则继承武器元素。
func eff_element(sym: SymbolData, wd: WeaponData) -> String:
	return effective_element(sym, wd.element, wd.reel_element)


# 纯计算版本（M1-04 预览共用，避免两处口径漂移）；技能/精华传 weapon_element="none"。
static func effective_element(sym: SymbolData, weapon_element: String, reel_element: String) -> String:
	if sym.kind == "special":
		return reel_element if reel_element != "none" else sym.element
	return sym.element if sym.element != "none" else weapon_element
