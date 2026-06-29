class_name WeaponVisualBase
extends Node2D

## 武器视觉基类
## 所有武器场景的根节点脚本
## 提供统一的接口供 WeaponNode 调用

signal animation_finished()

# 武器数据引用（由 WeaponNode 注入）
var weapon_data: WeaponData
var aim_direction: Vector2 = Vector2.RIGHT
var is_attacking: bool = false

# 视觉状态
var _flash_timer: float = 0.0
var _swing_progress: float = 0.0
var _is_swinging: bool = false


func _ready():
	# 默认隐藏，由 WeaponNode 控制显示
	visible = false


func _process(delta):
	_update_flash(delta)
	_update_swing(delta)


# ════════════════════════════════════════
#  公共接口（由 WeaponNode 调用）
# ════════════════════════════════════════

## 装备时调用，初始化视觉
func setup(data: WeaponData):
	weapon_data = data
	visible = true


## 卸下时调用
func teardown():
	visible = false
	weapon_data = null


## 播放攻击动画
func play_attack():
	is_attacking = true
	_attack_animation()


## 更新朝向
func set_aim_direction(dir: Vector2):
	aim_direction = dir
	# 默认行为：水平翻转
	if dir.x < 0:
		scale.x = -abs(scale.x)
	else:
		scale.x = abs(scale.x)


## 范围闪烁（近战）
func flash_range():
	_flash_timer = 0.15
	queue_redraw()


## 挥砍动画（近战）
func swing():
	_is_swinging = true
	_swing_progress = 0.0


# ════════════════════════════════════════
#  子类可重写的方法
# ════════════════════════════════════════

## 攻击动画（子类重写实现不同武器的攻击效果）
func _attack_animation():
	# 默认：简单的挥砍
	swing()
	# 0.3秒后结束
	await get_tree().create_timer(0.3).timeout
	is_attacking = false
	animation_finished.emit()


## 闲置状态更新
func _update_idle(_delta: float):
	pass


# ════════════════════════════════════════
#  内部实现
# ════════════════════════════════════════

func _update_flash(delta: float):
	if _flash_timer > 0:
		_flash_timer -= delta
		if _flash_timer <= 0:
			queue_redraw()


func _update_swing(delta: float):
	if _is_swinging:
		_swing_progress += delta * 8.0
		queue_redraw()
		if _swing_progress >= 1.0:
			_is_swinging = false
			_swing_progress = 0.0
			queue_redraw()


# 绘制攻击范围（调试用）
func _draw():
	if not weapon_data:
		return

	# 闪烁效果
	if _flash_timer > 0:
		var alpha = _flash_timer / 0.15
		var color = Color(1, 1, 1, alpha * 0.3)
		draw_arc(Vector2.ZERO, weapon_data.attack_range, 0, TAU, 32, color, 2.0, true)

	# 挥砍拖尾
	if _is_swinging:
		var angle = _swing_progress * PI * 0.8 - PI * 0.4
		var color = Color(1, 1, 1, 0.5)
		draw_arc(Vector2.ZERO, weapon_data.attack_range * 0.5, -PI * 0.4, angle, 16, color, 4.0, true)
