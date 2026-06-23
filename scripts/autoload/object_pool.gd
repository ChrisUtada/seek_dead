class_name ObjectPool
extends RefCounted

var _scene: PackedScene
var _available: Array[Node] = []

func _init(scene: PackedScene, initial_size: int = 10):
	_scene = scene
	for i in range(initial_size):
		var obj = _create()
		obj.visible = false
		obj.set_process(false)
		obj.set_physics_process(false)
		if obj is Area2D:
			obj.monitoring = false
		_available.append(obj)

func _create() -> Node:
	return _scene.instantiate()

func acquire(target_parent: Node) -> Node:
	var obj: Node
	if _available.size() > 0:
		obj = _available.pop_back()
	else:
		obj = _create()
	target_parent.add_child(obj)
	obj.visible = true
	obj.set_process(true)
	obj.set_physics_process(true)
	if obj is Area2D:
		obj.monitoring = true
	return obj

func release(obj: Node):
	if obj is Area2D:
		obj.set_deferred("monitoring", false)
	obj.get_parent().remove_child(obj)
	obj.visible = false
	obj.set_process(false)
	obj.set_physics_process(false)
	_available.append(obj)