extends Node2D
## 冰蝠攻击玩家的演出预览（编辑器可调）。
##
## 定位规则：BreathFx / BurstFx / SpikesFx 三个 AnimatedSprite2D 直接在 2D 视图里拖动，
## 这里只负责时序，不参与任何坐标计算——避免把喷口位置写死在代码里。
## 冰风朝左（喷口在贴图右缘）；冰锥已 flip_h，从玩家身前向左后推进。

@export_group("时序（秒）")
## 开场留白，让玩家先看清敌人再起手
@export var idle_lead: float = 0.35
## 冰风持续时间（frost-breath 自身可循环）
@export var breath_duration: float = 1.0
## 命中爆发相对开场的延迟
@export var burst_delay: float = 0.73
## 地面冰锥相对开场的延迟
@export var spikes_delay: float = 0.87
## 整段演出的总时长
@export var total_duration: float = 2.0

@export_group("调试")
## 进入场景自动播一次
@export var auto_play: bool = true
## 敌人待机时是否轻微上下浮动（纯预览观感，不影响时序）
@export var enemy_bob: bool = false
@export var enemy_bob_amplitude: float = 4.0
@export var enemy_bob_speed: float = 2.2

@onready var enemy: Sprite2D = $EnemySprite
@onready var breath_fx: AnimatedSprite2D = $BreathFx
@onready var burst_fx: AnimatedSprite2D = $BurstFx
@onready var spikes_fx: AnimatedSprite2D = $SpikesFx

var _enemy_base_y: float = 0.0
var _bob_time: float = 0.0
## 每次 play 递增，用来作废上一轮还在等待中的协程
var _token: int = 0


func _ready() -> void:
	_enemy_base_y = enemy.position.y
	for fx: AnimatedSprite2D in [breath_fx, burst_fx, spikes_fx]:
		fx.stop()
		fx.frame = 0
	if auto_play:
		play()


func _process(delta: float) -> void:
	if enemy_bob:
		_bob_time += delta * enemy_bob_speed
		enemy.position.y = _enemy_base_y + sin(_bob_time) * enemy_bob_amplitude


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_R:
			play()


## 重播整段演出。可被外部（战斗控制器）调用。
func play() -> void:
	_token += 1
	var my_token := _token
	for fx: AnimatedSprite2D in [breath_fx, burst_fx, spikes_fx]:
		fx.stop()
		fx.frame = 0

	_schedule(idle_lead, my_token, func() -> void: breath_fx.play())
	_schedule(idle_lead + breath_duration, my_token, func() -> void: breath_fx.stop())
	_schedule(burst_delay, my_token, func() -> void: burst_fx.play())
	_schedule(spikes_delay, my_token, func() -> void: spikes_fx.play())


func _schedule(delay: float, my_token: int, cb: Callable) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if my_token != _token:
		return
	cb.call()
