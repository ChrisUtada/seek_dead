class_name ArcherPlayer
extends "res://scripts/battle/player_controller.gd"

## 弓箭手玩家角色 —— 使用单帧 Sprite2D（非 AnimatedSprite2D），
## 依赖 SpriteLiveliness 组件提供呼吸 / 浮动 / 弹跳等程序化生命力。

var _liveliness: SpriteLiveliness


func _ready():
	super()
	add_to_group("player")

	# 获取 SpriteLiveliness（挂载在 Sprite2D 子节点下）
	_liveliness = $Sprite2D.get_node_or_null("SpriteLiveliness")
	if not _liveliness:
		push_warning("Archer: SpriteLiveliness 未找到，跳过程序化动画")


func _on_died():
	super()
	if _liveliness:
		_liveliness.play_hit_bounce(1.4)


func _physics_process(delta: float):
	super(delta)
	# 瞄准方向翻转精灵（与 player_controller._process_movement 的 flip_h 一致）
	var aim_dir := (get_global_mouse_position() - global_position).normalized()
	if $Sprite2D.has_method("set"):
		$Sprite2D.flip_h = aim_dir.x > 0


func take_damage(amount: float, damage_type: int) -> Dictionary:
	var result := super(amount, damage_type)
	# 受击挤压弹跳
	if _liveliness:
		_liveliness.play_hit_bounce(1.25)
	return result
