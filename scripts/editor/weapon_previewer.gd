@tool
extends Node2D

## 编辑器武器预览工具
##
## 使用方法：
##   1. 在玩家场景中添加一个 Node2D 子节点
##   2. 将此脚本挂载到该节点上
##   3. 在 Inspector 中将 weapon_template 设为任意武器 .tres 模板
##   4. 调整 grip_point / visual_scale / visual_offset 实时预览
##   5. 调好后点 "✅ 写入模板" 将数值同步回 .tres
##   6. 运行游戏前删除或隐藏此节点（运行时自动不工作）

@export var weapon_template: WeaponData:
	set(v):
		weapon_template = v
		_spawn_weapon_preview()

@export var grip_point: Vector2 = Vector2.ZERO:
	set(v):
		grip_point = v
		_spawn_weapon_preview()

@export var visual_scale: Vector2 = Vector2.ONE:
	set(v):
		visual_scale = v
		_spawn_weapon_preview()

@export var visual_offset: Vector2 = Vector2.ZERO:
	set(v):
		visual_offset = v
		_spawn_weapon_preview()

@export var debug_show_grip: bool = false:
	set(v):
		debug_show_grip = v
		queue_redraw()

@export var commit_to_template: bool = false:
	set(v):
		_commit_to_template()

var _weapon_visual: WeaponVisualBase = null


func _process(_delta):
	# 仅在编辑器中工作，运行时自动隐藏
	if not Engine.is_editor_hint():
		if visible:
			visible = false
		return
	visible = true


func _draw():
	if debug_show_grip:
		draw_circle(Vector2.ZERO, 4, Color.RED)
		draw_line(Vector2(-10, 0), Vector2(10, 0), Color.RED, 2.0)
		draw_line(Vector2(0, -10), Vector2(0, 10), Color.RED, 2.0)


func _spawn_weapon_preview():
	if not Engine.is_editor_hint():
		return

	# 清理旧视觉
	if _weapon_visual and is_instance_valid(_weapon_visual):
		_weapon_visual.queue_free()
		_weapon_visual = null

	if not weapon_template or not weapon_template.weapon_scene:
		queue_redraw()
		return

	# 实例化武器场景
	var instance = weapon_template.weapon_scene.instantiate()
	if not instance is WeaponVisualBase:
		instance.queue_free()
		return

	add_child(instance)
	_weapon_visual = instance as WeaponVisualBase

	# 用本地覆盖值创建临时 WeaponData 副本
	var temp_data = weapon_template.duplicate() as WeaponData
	temp_data.grip_point = grip_point
	temp_data.visual_scale = visual_scale
	temp_data.visual_offset = visual_offset

	# 调用 setup() 应用定位（GripPoint 锚点对齐 + 缩放 + 偏移）
	_weapon_visual.setup(temp_data)
	_weapon_visual.set_aim_direction(Vector2.RIGHT)

	queue_redraw()


func _commit_to_template():
	if not weapon_template:
		push_warning("WeaponPreviewer: 未选择武器模板")
		return

	weapon_template.grip_point = grip_point
	weapon_template.visual_scale = visual_scale
	weapon_template.visual_offset = visual_offset

	# 保存资源到磁盘
	var path = weapon_template.resource_path
	if path != "":
		ResourceSaver.save(weapon_template, path)
		print("[WeaponPreviewer] 已写入: ", path)
	else:
		print("[WeaponPreviewer] 模板无磁盘路径，仅内存更新")
