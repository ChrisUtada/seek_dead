class_name BehaviorTree
extends RefCounted

enum NodeStatus { SUCCESS, FAILURE, RUNNING }

class Blackboard:
	var data: Dictionary = {}

	func get_var(key: String, default: Variant = null) -> Variant:
		return data.get(key, default)

	func set_var(key: String, value: Variant):
		data[key] = value

	func has_var(key: String) -> bool:
		return key in data

	func erase(key: String):
		data.erase(key)

class BehaviorNode:
	var name: String = ""
	var status: NodeStatus = NodeStatus.FAILURE
	var blackboard: Blackboard

	func _init(node_name: String = ""):
		name = node_name

	func tick(entity: Node, delta: float) -> NodeStatus:
		return status

class SelectorNode extends BehaviorNode:
	var _items = []

	func add(node: BehaviorNode):
		_items.append(node)

	func tick(entity: Node, delta: float) -> NodeStatus:
		for i in range(_items.size()):
			var result = _items[i].tick(entity, delta)
			if result != NodeStatus.FAILURE:
				status = result
				return status
		status = NodeStatus.FAILURE
		return status

class SequenceNode extends BehaviorNode:
	var _items = []

	func add(node: BehaviorNode):
		_items.append(node)

	func tick(entity: Node, delta: float) -> NodeStatus:
		for i in range(_items.size()):
			var result = _items[i].tick(entity, delta)
			if result != NodeStatus.SUCCESS:
				status = result
				return status
		status = NodeStatus.SUCCESS
		return status

class ConditionNode extends BehaviorNode:
	var condition: Callable

	func tick(entity: Node, delta: float) -> NodeStatus:
		if condition.is_valid() and condition.call(entity):
			status = NodeStatus.SUCCESS
		else:
			status = NodeStatus.FAILURE
		return status

class ActionNode extends BehaviorNode:
	var action: Callable

	func tick(entity: Node, delta: float) -> NodeStatus:
		if action.is_valid():
			status = action.call(entity, delta)
		else:
			status = NodeStatus.FAILURE
		return status

class InvertNode extends BehaviorNode:
	var child: BehaviorNode

	func tick(entity: Node, delta: float) -> NodeStatus:
		var result = child.tick(entity, delta)
		match result:
			NodeStatus.SUCCESS:
				status = NodeStatus.FAILURE
			NodeStatus.FAILURE:
				status = NodeStatus.SUCCESS
			NodeStatus.RUNNING:
				status = NodeStatus.RUNNING
		return status

class CooldownNode extends BehaviorNode:
	var child: BehaviorNode
	var cooldown_time: float = 1.0
	var _timer: float = 0.0

	func tick(entity: Node, delta: float) -> NodeStatus:
		if _timer > 0:
			_timer -= delta
			status = NodeStatus.FAILURE
			return status
		var result = child.tick(entity, delta)
		if result == NodeStatus.SUCCESS:
			_timer = cooldown_time
		status = result
		return status
