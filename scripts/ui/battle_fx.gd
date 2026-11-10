class_name BattleFx
extends Node
## 战斗特效层：把 pixelfx 导出的 SpriteFrames 叠到角色立绘上。
##
## 设计约束：
## 1) 定位一律在运行时读立绘的 global_rect 反推，不写死屏幕坐标。
## 2) 偏移/缩放/翻转的**唯一真源**是 scenes/fx/ice_bat_attack.tscn（那里能所见即所得地拖）；
##    改完把数值同步到下面这组常量即可。
## 3) 🔴 本层不取全局随机数：战斗演出不得平移种子局的随机流。
## 4) 只做表现，不读写任何战斗数值。

const FRAMES := {
	"breath": preload("res://assets/fx/frost-breath/frost-breath.tres"),
	"burst": preload("res://assets/fx/snowflake-burst/snowflake-burst.tres"),
	"spikes": preload("res://assets/fx/ice-spikes/ice-spikes.tres"),
}

## 相对「立绘中心」的偏移。取自 ice_bat_attack.tscn：
##   BreathFx (280,219) − EnemySprite (378,188) = (-98, +31)
##   BurstFx  (130,213) − PlayerSprite (132,212) = (-2, +1)
##   SpikesFx (121,212) − PlayerSprite (132,212) = (-11, 0)
const BREATH_OFFSET := Vector2(-98.0, 31.0)
const BURST_OFFSET := Vector2(-2.0, 1.0)
const SPIKES_OFFSET := Vector2(-11.0, 0.0)
const SPIKES_SCALE := 0.55

## frost-breath 原图气流是「左 → 右」（亮核在 x≈20，雾向右扩散）。
## 敌人站在玩家右侧，必须水平翻转才朝玩家喷 —— 与场景里的 flip_h 保持一致。
const BREATH_FLIP := true
## ice-spikes 原图就是「左 → 右」推进（= 玩家身前 → 身后），**不要翻转**。
const SPIKES_FLIP := false

## 帧速缩放：1.0 = 按导出的 30fps 播放。像素特效 30fps 偏快，整体压到 0.8。
const FX_SPEED := 0.8

## 时序（秒，相对敌人攻击判定时刻）。整体 2s，给演出留足阅读时间。
const T_RISE_END := 0.30        ## 抬身
const T_BREATH_START := 0.55    ## 俯冲途中开始喷气
const T_DIVE_END := 0.75        ## 俯冲到位
const T_HIT := 0.95             ## 命中：爆发 + 玩家受击
const T_SPIKES := 1.05          ## 地面冰锥
const T_RETURN_START := 1.30    ## 退回
const T_BREATH_STOP := 1.55
const T_RETURN_END := 1.95
const T_TOTAL := 1.95           ## 调用方需要等待的完整时长
const T_CLEANUP := T_TOTAL + 0.25

## 俯冲位移（相对立绘初始位置）
const DIVE_RISE := Vector2(0.0, -8.0)
const DIVE_LUNGE := Vector2(-70.0, 22.0)

var hud = null

var _token := 0
var _live: Array[AnimatedSprite2D] = []
var _follow: Array = []      ## [{node, target, offset}]：随角色移动的特效（冰风要跟着俯冲）
var _enemy_home := Vector2.ZERO
var _enemy_moved := false


func setup(p_hud) -> void:
	hud = p_hud


func _process(_delta: float) -> void:
	for f in _follow:
		if is_instance_valid(f["node"]) and is_instance_valid(f["target"]):
			f["node"].position = _sprite_center(f["target"]) + f["offset"]


# ---------------------------------------------------------------------------
# 对外：敌人属性攻击演出
# ---------------------------------------------------------------------------

## 播放该元素对应的敌人攻击演出，返回调用方应等待的秒数（0 = 本次无演出）。
func play_enemy_attack(elem: String) -> float:
	match elem:
		"ice":
			return _play_ice_attack()
		_:
			return 0.0


# ---------------------------------------------------------------------------
# 冰系：抬身 → 俯冲（冰风自嘴部喷出，跟着俯冲走）→ 命中爆发 → 地面冰锥 → 退回
# ---------------------------------------------------------------------------

func _play_ice_attack() -> float:
	_clear()
	_token += 1
	var token := _token
	var enemy_at := _sprite_center(hud.enemy_sprite)
	var player_at := _sprite_center(hud.player_sprite)

	_dive(token)
	var breath := _spawn(FRAMES["breath"], enemy_at + BREATH_OFFSET, 1.0, BREATH_FLIP)
	breath.visible = false
	_follow.append({"node": breath, "target": hud.enemy_sprite, "offset": BREATH_OFFSET})

	_delay(T_BREATH_START, token, func() -> void:
		breath.visible = true
		breath.play(&"default"))
	_delay(T_BREATH_STOP, token, func() -> void:
		if is_instance_valid(breath):
			breath.stop())
	_delay(T_HIT, token, func() -> void:
		# 命中瞬间才闪红/屏震——否则攻击一开始就抖，和喷气对不上
		if hud.animator != null:
			hud.animator.play_enemy_attack())
	_delay(T_HIT, token, func() -> void:
		_spawn(FRAMES["burst"], _sprite_center(hud.player_sprite) + BURST_OFFSET).play(&"default"))
	_delay(T_SPIKES, token, func() -> void:
		_spawn(FRAMES["spikes"], _sprite_center(hud.player_sprite) + SPIKES_OFFSET,
			SPIKES_SCALE, SPIKES_FLIP).play(&"default"))
	_delay(T_CLEANUP, token, func() -> void: _clear())
	return T_TOTAL


## 敌人俯冲：抬身 → 前扑 → 停顿 → 回位。只动 position，结束复位。
func _dive(token: int) -> void:
	if hud.enemy_sprite == null:
		return
	var sp: Control = hud.enemy_sprite
	_enemy_home = sp.position
	_enemy_moved = true
	var home := _enemy_home
	var tw := sp.create_tween()
	tw.tween_property(sp, "position", home + DIVE_RISE, T_RISE_END) \
		.set_trans(Tween.TRANS_SINE)
	tw.tween_property(sp, "position", home + DIVE_LUNGE, T_DIVE_END - T_RISE_END) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(T_RETURN_START - T_DIVE_END)
	tw.tween_property(sp, "position", home, T_RETURN_END - T_RETURN_START) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(sp):
			sp.position = home)


# ---------------------------------------------------------------------------
# 内部工具
# ---------------------------------------------------------------------------

## 立绘中心在 HUD 局部坐标系里的位置（HUD 边距/缩放变化时自动跟随）
func _sprite_center(c: Control) -> Vector2:
	if c == null or hud == null:
		return Vector2.ZERO
	var g: Vector2 = c.get_global_rect().get_center()
	return hud.get_global_transform().affine_inverse() * g


func _spawn(frames: SpriteFrames, at: Vector2, scl: float = 1.0,
		flip: bool = false) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.centered = true
	s.scale = Vector2(scl, scl)
	s.flip_h = flip
	s.speed_scale = FX_SPEED
	s.position = at
	s.z_index = 20
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hud.add_child(s)
	_live.append(s)
	return s


func _clear() -> void:
	for n in _live:
		if is_instance_valid(n):
			n.queue_free()
	_live.clear()
	_follow.clear()
	# 中断时把被俯冲拉走的敌人复位，避免残留在半空
	if _enemy_moved and hud != null and is_instance_valid(hud.enemy_sprite):
		hud.enemy_sprite.position = _enemy_home
	_enemy_moved = false


## 延时执行；token 变了说明有更新的一次演出，旧的协程直接作废
func _delay(seconds: float, token: int, cb: Callable) -> void:
	await get_tree().create_timer(seconds).timeout
	if token != _token or not is_inside_tree():
		return
	cb.call()
