class_name ReelClock
extends RefCounted

# ============================================================================
# 转轮手感优化 · Step 1（2026-11-12）
# 连续时间与落点计算 —— 纯计算模块：不读 RNG、不写 grid、不参与结算。
#
# 依据：docs/转轮手感优化_连续时间与落点吸附_执行方案_2026-11-11.md
#   §3 推荐时序 / §4.1 连续时间计算模块 / §8 Step 1
#
# 每列保存：
#   position        连续位置（单位 = 格子，方向与带子索引一致，单调递增后取模）
#   elapsed         本次旋转已滚动时间
#   cells_per_second 巡航速度（格/秒）
#   ramp_seconds    启动加速段时长（二次速度曲线）
#   decel_cells     停轮减速格数
#   state           IDLE / SPINNING / STOPPING / STOPPED / FROZEN / LOCKED / EMPTY
#
# 关键约束（Step 1 出口）：
#   1. 位置由「绝对时间」推导（二次速度曲线 + 三次位置积分），不是逐帧累加位移，
#      因此 30/60/120fps 在同一时刻得到同一位置。
#   2. 预测落点 = round(请求停轮瞬间的位置 + decel_cells)，只依赖请求时的位置与
#      配置，不依赖之后的帧率；减速吸附终点就是该格中心。
#   3. 不调用任何随机函数——自动/手动停轮共用同一落点算法（Step 2 接入）。
# ============================================================================

enum State { IDLE, SPINNING, STOPPING, STOPPED, FROZEN, LOCKED, EMPTY }

# 方案 §5 的试验区间：主滚动 8–10 格/秒；落地减速 0.12–0.16 秒。
const DEFAULT_CELLS_PER_SECOND := 9.0
const DEFAULT_RAMP_SECONDS := 0.18
const DEFAULT_DECEL_CELLS := 1.0
const DEFAULT_START_FACTOR := 0.45     # 起转初速 = 巡航速度 × 该系数
const MIN_STOP_SECONDS := 0.12
const MAX_STOP_SECONDS := 0.16

var _sizes: Array[int] = []
var _position: Array[float] = []
var _elapsed: Array[float] = []
var _start_position: Array[float] = []
var _state: Array[int] = []

# 每列配置
var _cells_per_second: Array[float] = []
var _ramp_seconds: Array[float] = []
var _decel_cells: Array[float] = []
var _start_factor: Array[float] = []

# 停轮状态（STOPPING / STOPPED 使用）
var _stop_elapsed: Array[float] = []
var _stop_seconds: Array[float] = []
var _stop_from: Array[float] = []
var _stop_delta: Array[float] = []
var _stop_landing_position: Array[float] = []   # 未取模的落点位置
var _stop_landing_index: Array[int] = []


# 按每列带子长度建立/重建状态。strip_sizes 为空或元素 ≤0 → 该列 EMPTY。
# 默认参数取自方案 §5 试验区间的中位值；Step 2/3 再从 ReadabilitySystem 接入。
func configure(strip_sizes: Array, cells_per_second: float = DEFAULT_CELLS_PER_SECOND,
		ramp_seconds: float = DEFAULT_RAMP_SECONDS, decel_cells: float = DEFAULT_DECEL_CELLS,
		start_factor: float = DEFAULT_START_FACTOR) -> void:
	_sizes = []
	_position = []
	_elapsed = []
	_start_position = []
	_state = []
	_cells_per_second = []
	_ramp_seconds = []
	_decel_cells = []
	_start_factor = []
	_stop_elapsed = []
	_stop_seconds = []
	_stop_from = []
	_stop_delta = []
	_stop_landing_position = []
	_stop_landing_index = []
	for i in strip_sizes.size():
		var n: int = int(strip_sizes[i])
		_sizes.append(n)
		_position.append(0.0)
		_elapsed.append(0.0)
		_start_position.append(0.0)
		_state.append(State.IDLE if n > 0 else State.EMPTY)
		_cells_per_second.append(maxf(0.0, cells_per_second))
		_ramp_seconds.append(maxf(0.0, ramp_seconds))
		_decel_cells.append(maxf(0.0, decel_cells))
		_start_factor.append(clampf(start_factor, 0.0, 1.0))
		_stop_elapsed.append(0.0)
		_stop_seconds.append(0.0)
		_stop_from.append(0.0)
		_stop_delta.append(0.0)
		_stop_landing_position.append(0.0)
		_stop_landing_index.append(-1)


func reel_count() -> int:
	return _sizes.size()


func strip_size(r: int) -> int:
	return _sizes[r] if _valid(r) else 0


func state(r: int) -> int:
	return _state[r] if _valid(r) else State.EMPTY


func state_name(r: int) -> String:
	return State.keys()[state(r)]


func is_spinning(r: int) -> bool:
	return state(r) == State.SPINNING


func is_stopping(r: int) -> bool:
	return state(r) == State.STOPPING


func is_stopped(r: int) -> bool:
	return state(r) == State.STOPPED


func position(r: int) -> float:
	return _position[r] if _valid(r) else 0.0


func elapsed(r: int) -> float:
	return _elapsed[r] if _valid(r) else 0.0


# 开始一列旋转：位置可从任意连续位置起转（Step 2 由逻辑游标带入）。
func start_reel(r: int, from_position: float = 0.0) -> void:
	if not _valid(r) or _sizes[r] <= 0:
		return
	if _state[r] in [State.FROZEN, State.LOCKED, State.EMPTY]:
		return
	_start_position[r] = from_position
	_position[r] = _wrap(from_position, _sizes[r])
	_elapsed[r] = 0.0
	_stop_elapsed[r] = 0.0
	_stop_seconds[r] = 0.0
	_stop_landing_index[r] = -1
	_state[r] = State.SPINNING


# 所有可旋转列同时起转。
func start(from_position: float = 0.0) -> void:
	for r in _sizes.size():
		start_reel(r, from_position)


func mark_frozen(r: int) -> void:
	if _valid(r):
		_state[r] = State.FROZEN
		_stop_landing_index[r] = -1


func mark_locked(r: int) -> void:
	if _valid(r):
		_state[r] = State.LOCKED
		_stop_landing_index[r] = -1


# 恢复到未旋转状态（房间重开 / 换装重建带子）。
func reset() -> void:
	for r in _sizes.size():
		_state[r] = State.IDLE if _sizes[r] > 0 else State.EMPTY
		_position[r] = 0.0
		_elapsed[r] = 0.0
		_stop_elapsed[r] = 0.0
		_stop_seconds[r] = 0.0
		_stop_landing_index[r] = -1


# 二次速度曲线：0→ramp 从 start_factor 平滑升到 1.0，之后保持巡航速度。
func speed_factor_at(r: int, t: float) -> float:
	if not _valid(r):
		return 0.0
	var ramp: float = _ramp_seconds[r]
	if ramp <= 0.0 or t >= ramp:
		return 1.0
	var u: float = clampf(t / ramp, 0.0, 1.0)
	return _start_factor[r] + (1.0 - _start_factor[r]) * u * u


# 位置对时间的闭式积分（三次曲线），保证同一时刻的位置与帧率无关。
func position_at(r: int, t: float) -> float:
	if not _valid(r):
		return 0.0
	var v: float = _cells_per_second[r]
	var ramp: float = _ramp_seconds[r]
	var f: float = _start_factor[r]
	if ramp <= 0.0:
		return _start_position[r] + v * t
	if t <= ramp:
		return _start_position[r] + v * (f * t + (1.0 - f) * t * t * t / (3.0 * ramp * ramp))
	var ramp_distance: float = v * (f * ramp + (1.0 - f) * ramp / 3.0)
	return _start_position[r] + ramp_distance + v * (t - ramp)


# 当前瞬时速度（格/秒）。停止中按减速进度线性衰减到 0。
func current_speed(r: int) -> float:
	if not _valid(r):
		return 0.0
	match _state[r]:
		State.SPINNING:
			return _cells_per_second[r] * speed_factor_at(r, _elapsed[r])
		State.STOPPING:
			var secs: float = _stop_seconds[r]
			var t: float = clampf(_stop_elapsed[r] / secs, 0.0, 1.0) if secs > 0.0 else 1.0
			return _cells_per_second[r] * speed_factor_at(r, _elapsed[r]) * (1.0 - t)
		_:
			return 0.0


# 推进所有旋转中的列。返回本次调用「完成吸附」的列索引（每列只会返回一次）。
# STOPPING 列按二次缓出从请求位置吸附到预测落点；落点只由 request_stop 时记录。
func advance(delta: float) -> Array:
	var landed: Array = []
	if delta <= 0.0:
		return landed
	for r in _sizes.size():
		match _state[r]:
			State.SPINNING:
				_elapsed[r] += delta
				_position[r] = _wrap(position_at(r, _elapsed[r]), _sizes[r])
			State.STOPPING:
				_stop_elapsed[r] += delta
				var secs: float = _stop_seconds[r]
				var t: float = clampf(_stop_elapsed[r] / secs, 0.0, 1.0) if secs > 0.0 else 1.0
				var eased: float = 1.0 - (1.0 - t) * (1.0 - t)
				_position[r] = _wrap(_stop_from[r] + _stop_delta[r] * eased, _sizes[r])
				if t >= 1.0:
					_position[r] = _wrap(_stop_landing_position[r], _sizes[r])
					_state[r] = State.STOPPED
					landed.append(r)
	return landed


# 当前最接近窗口中心的格（连续位置四舍五入，与 ReelSpinView.center_index 同口径）。
# 冻结/锁轮/空带返回 -1（这些列没有可观测的旋转中心）。
func center_index(r: int) -> int:
	if not _valid(r) or _sizes[r] <= 0:
		return -1
	if _state[r] in [State.FROZEN, State.LOCKED, State.EMPTY]:
		return -1
	return index_for_position(_position[r], _sizes[r])


# 预览：从视觉中心之后取 count 格（不含中心本身），与 ReelSystem.next_symbols 同口径。
func preview_indexes(r: int, count: int) -> Array:
	var out: Array = []
	var n: int = strip_size(r)
	var base: int = center_index(r)
	if n <= 0 or base < 0:
		return out
	for i in range(1, count + 1):
		out.append((base + i) % n)
	return out


# 预测落点：请求瞬间的连续位置 + 减速格数，四舍五入到格中心。
# 停止中/已停止返回已记录的落点；冻结/锁轮/空带返回 -1。
func predicted_landing(r: int) -> int:
	if not _valid(r) or _sizes[r] <= 0:
		return -1
	if _state[r] in [State.FROZEN, State.LOCKED, State.EMPTY]:
		return -1
	if _state[r] in [State.STOPPING, State.STOPPED]:
		return _stop_landing_index[r]
	return landing_index_at(_position[r], _decel_cells[r], _sizes[r])


# 提交停轮请求：记录请求位置与预测落点，进入 STOPPING。
# 重复提交同一列返回空字典（Step 2 据此去重，不会重复结算）。
func request_stop(r: int) -> Dictionary:
	if not _valid(r) or _state[r] != State.SPINNING or _sizes[r] <= 0:
		return {}
	var n: int = _sizes[r]
	var from: float = _position[r]
	var landing_position: float = roundf(from + _decel_cells[r])
	var speed: float = current_speed(r)
	var secs: float = MIN_STOP_SECONDS if speed <= 0.0 else clampf(2.0 * _decel_cells[r] / speed,
		MIN_STOP_SECONDS, MAX_STOP_SECONDS)
	_stop_from[r] = from
	_stop_delta[r] = landing_position - from
	_stop_landing_position[r] = landing_position
	_stop_landing_index[r] = index_for_position(landing_position, n)
	_stop_elapsed[r] = 0.0
	_stop_seconds[r] = secs
	_state[r] = State.STOPPING
	return {
		"reel": r,
		"from_position": from,
		"landing_position": landing_position,
		"landing_index": _stop_landing_index[r],
		"decel_cells": _decel_cells[r],
		"stop_seconds": secs,
	}


# 吸附所需时间（秒）；未请求停轮时返回 0。
func stop_seconds(r: int) -> float:
	return _stop_seconds[r] if _valid(r) else 0.0


func snapshot(r: int) -> Dictionary:
	if not _valid(r):
		return {}
	return {
		"reel": r, "state": state_name(r), "position": _position[r],
		"elapsed": _elapsed[r], "center": center_index(r),
		"landing": predicted_landing(r),
		"speed": current_speed(r),
		"cells_per_second": _cells_per_second[r],
		"ramp_seconds": _ramp_seconds[r],
		"decel_cells": _decel_cells[r],
		"stop_seconds": _stop_seconds[r],
		"strip_size": _sizes[r],
	}


# —— 纯静态计算（可单独定向测试）——

# 连续位置 → 格索引。0.5 向上取整，与 ReelSpinView 的 `_frac >= 0.5` 分界一致。
static func index_for_position(pos: float, strip_size: int) -> int:
	if strip_size <= 0:
		return -1
	return floori(_wrap(pos, strip_size) + 0.5) % strip_size


static func landing_index_at(pos: float, decel_cells: float, strip_size: int) -> int:
	if strip_size <= 0:
		return -1
	return index_for_position(roundf(pos + maxf(0.0, decel_cells)), strip_size)


static func _wrap(pos: float, strip_size: int) -> float:
	if strip_size <= 0:
		return pos
	return fposmod(pos, float(strip_size))


func _valid(r: int) -> bool:
	return r >= 0 and r < _sizes.size()
