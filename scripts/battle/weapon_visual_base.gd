@tool
class_name WeaponVisualBase
extends Node2D

## 武器视觉基类
## 所有武器场景的根节点脚本
## 提供统一的接口供 WeaponNode 调用
##
## 定位机制：
##   1. 在武器 .tscn 中放置 Marker2D 子节点命名为 "GripPoint"，标记握把位置
##   2. setup() 时将 GripPoint 对齐到自身原点 (0,0)
##   3. 再叠加 WeaponData 的 visual_scale 和 visual_offset
##   这样无论武器贴图多大，原点始终是"手握住的地方"

signal animation_finished()

# 武器数据引用（由 WeaponNode 注入）
var weapon_data: WeaponData
var aim_direction: Vector2 = Vector2.RIGHT
var is_attacking: bool = false

# 视觉状态
var _flash_timer: float = 0.0
var _swing_progress: float = 0.0
var _is_swinging: bool = false
var _base_scale: Vector2 = Vector2.ONE

# 调试：显示握把点位置（编辑器中可开启）
@export var debug_show_grip: bool = false


func _ready():
	if not weapon_data:
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

	# 1. GripPoint 锚点对齐：把握把位置移到原点
	#    优先用场景中的 Marker2D，没有则回退到 WeaponData.grip_point
	var grip_pos = Vector2.ZERO
	var grip_node = get_node_or_null("GripPoint") as Marker2D
	if grip_node:
		grip_pos = grip_node.position
	elif data:
		grip_pos = data.grip_point
	position = -grip_pos

	# 2. 缩放：先应用 visual_scale
	if data:
		var vs = data.visual_scale
		if vs == Vector2.ZERO:
			vs = Vector2.ONE
		_base_scale = vs
		scale = vs

	# 3. 叠加 visual_offset 微调
	if data:
		position += data.visual_offset

	visible = true
	queue_redraw()


## 卸下时调用
func teardown():
	visible = false
	position = Vector2.ZERO
	scale = Vector2.ONE
	_base_scale = Vector2.ONE
	weapon_data = null


## 播放攻击动画
func play_attack():
	is_attacking = true
	_attack_animation()


## 更新朝向（父节点已处理 scale.x 翻转，这里只记录方向）
func set_aim_direction(dir: Vector2):
	aim_direction = dir


## 范围闪烁（近战）
func flash_range():
	_flash_timer = 0.15
	queue_redraw()


## 重置旋转（由 WeaponNode 挥砍结束后调用）
func reset_rotation():
	rotation = 0.0

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


# TODO: 武器外观为调试占位绘制（红色圆点/线框），后续替换为真实武器贴图与挥砍动画。
# 绘制攻击范围（调试用）
func _draw():
	# 调试：显示握把点
	if debug_show_grip:
		draw_circle(Vector2.ZERO, 4, Color.RED)
		draw_line(Vector2(-8, 0), Vector2(8, 0), Color.RED, 1.5)
		draw_line(Vector2(0, -8), Vector2(0, 8), Color.RED, 1.5)

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
