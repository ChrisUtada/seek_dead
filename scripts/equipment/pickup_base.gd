class_name PickupBase
extends Area2D

## 所有掉落拾取物的基类。
## 统一收口：碰撞层/掩码设置、信号连接、已收集状态守卫、收集动画，
## 子类只需实现数据字段 + 外观(_build_visual) + 业务逻辑钩子(_player_valid / _apply_effect)。
##
## 子类约定的调用方式：
##   func setup(...):
##       # 保存自己的数据
##       _init_pickup()   # 由基类完成碰撞设置、信号连接、延迟构建外观

var _collected: bool = false


# ---- 生命周期 ----------------------------------------------------------------

## 子类 setup() 末尾调用：完成碰撞与信号初始化，并延迟构建外观。
func _init_pickup() -> void:
	collision_layer = 0
	collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_PLAYER)
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	call_deferred("_build_visual")


func _on_body_entered(body: Node2D) -> void:
	_on_player_touched(body)


func _on_area_entered(area: Area2D) -> void:
	var owner := area.owner if area.owner else area
	_on_player_touched(owner)


## 统一的接触入口：守卫重复收集 -> 校验目标 -> 应用效果 -> 播放动画。
func _on_player_touched(target: Node2D) -> void:
	if _collected:
		return
	if not _player_valid(target):
		return
	if _apply_effect(target):
		_collected = true
		_play_collect_animation()


# ---- 子类钩子 ----------------------------------------------------------------

## 校验触碰到的节点是否是有效目标。默认要求目标在 "players" 组。
## 子类可重写（例如金币只需 GameManager 存在）。
func _player_valid(_target: Node2D) -> bool:
	return _target.is_in_group("players")


## 应用拾取效果。成功消耗返回 true（播放消失动画），失败返回 false（保留拾取物供重试）。
## 子类必须重写。
func _apply_effect(_target: Node2D) -> bool:
	return false


# ---- 外观 --------------------------------------------------------------------

## 构建掉落物外观。基类只创建碰撞体，子类调用 super._build_visual() 后追加 orb/label。
func _build_visual() -> void:
	_add_collision_shape(10.0)


func _add_collision_shape(radius: float) -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	return shape


func _add_orb(color: Color, size: Vector2, offset: Vector2) -> ColorRect:
	var orb := ColorRect.new()
	orb.size = size
	orb.color = color
	orb.position = offset
	add_child(orb)
	return orb


func _add_border(color: Color, size: Vector2, offset: Vector2) -> ColorRect:
	var border := ColorRect.new()
	border.size = size
	border.color = color
	border.position = offset
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)
	return border


func _add_label(text: String, size: Vector2, offset: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = offset
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


# ---- 动画 --------------------------------------------------------------------

func _play_collect_animation() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.1)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.15)
	tween.tween_callback(queue_free)
