class_name SpriteLiveliness
extends Node
## 给单帧 Sprite2D 注入"生命力"：呼吸缩放 / 行走浮动 / 出生弹出 /
## 受击挤压弹跳 / 阴影联动。
## 用法：挂到 Sprite2D 下（parent 必须是 Sprite2D），
## owner 需是 CharacterBody2D（或任何有 get_real_velocity() 的节点）。

@export var shadow_path: NodePath = ""        # 可选：关联 Shadow 节点
@export var breath_strength := 0.06           # 待机呼吸幅度
@export var bob_strength_px := 2.5            # 行走上下浮动像素
@export var bob_speed := 14.0                 # 浮动频率

var _sprite: CanvasItem
var _shadow: Node2D
var _t := 0.0
var _base_scale := Vector2.ONE


func _ready():
	_sprite = get_parent()
	if not (_sprite is CanvasItem):
		push_warning("SpriteLiveliness: parent 不是 CanvasItem，跳过")
		return
	_base_scale = _sprite.scale

	if not shadow_path.is_empty():
		_shadow = get_node_or_null(shadow_path)
	else:
		# 自动向上找同层 Shadow 节点
		var owner_node = get_owner()
		if owner_node:
			for c in owner_node.get_children():
				if c is Node2D and c.has_method("_ready"):  # Shadow 脚本标记
					_shadow = c
					break

	# 出生弹出：从 0 弹回原大小（弹性缓出）
	_sprite.scale = Vector2.ZERO
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_sprite, "scale", _base_scale, 0.35)


func _process(delta: float) -> void:
	if not _sprite:
		return

	_t += delta
	var body := get_owner()
	var vel := Vector2.ZERO
	if body and body.has_method("get_real_velocity"):
		vel = body.get_real_velocity()
	elif body and body is CharacterBody2D:
		vel = body.velocity if "velocity" in body else Vector2.ZERO

	var moving := vel.length() > 10.0

	# ---- 呼吸：纵向轻微缩放（仅待机时明显） ----
	var breath_factor := 1.0
	if not moving:
		breath_factor = 1.0 + sin(_t * 3.5) * breath_strength

	# ---- 行走浮动：上下位移 ----
	var bob := 0.0
	if moving:
		bob = sin(_t * bob_speed) * bob_strength_px

	# 应用：缩放 + 浮位偏移
	_sprite.scale.y = _base_scale.y * breath_factor
	_sprite.position.y = -bob  # 负值=向上浮

	# ---- 阴影联动：随浮动缩小+变淡，增加离地体积感 ----
	if _shadow:
		_shadow.scale.x = _base_scale.x * (1.0 - abs(bob) * 0.03)
		_shadow.modulate.a = clamp(1.0 - abs(bob) * 0.05, 0.15, 1.0)


## 外部调用：受击时触发挤压弹跳（先放大再缩小回弹）
func play_hit_bounce(intensity: float = 1.25, duration_squash: float = 0.08):
	if not _sprite:
		return
	var tw := create_tween()
	tw.tween_property(_sprite, "scale", _base_scale * intensity, duration_squash)
	tw.set_trans(Tween.TRANS_ELASTIC)
	tw.tween_property(_sprite, "scale", _base_scale, 0.25)


## 外部调用：攻击前冲（朝 direction 横向拉伸、纵向压扁）
func play_attack_stretch(direction: Vector2, intensity: float = 1.18):
	if not _sprite:
		return
	var stretch := Vector2.ONE
	stretch.x = intensity if abs(direction.x) >= abs(direction.y) else 1.0 / intensity
	stretch.y = 1.0 / intensity if abs(direction.x) >= abs(direction.y) else intensity

	# 根据 aim_dir 翻转镜像
	if direction.x < 0:
		stretch.x *= -1

	var tw := create_tween()
	tw.tween_property(_sprite, "scale", _base_scale * stretch, 0.05)
	tw.set_ease(Tween.EASE_IN)
	tw.tween_property(_sprite, "scale", _base_scale, 0.12)
