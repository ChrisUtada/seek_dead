extends Node

## 主测试入口
## 运行所有阶段的测试

func _ready():
	print("")
	print("*".repeat(50))
	print("  Seek Dead - Godot 迁移可行性验证")
	print("  阶段一：基础框架验证")
	print("*".repeat(50))
	print("")

	# 加载并运行阶段一测试
	var phase1_test = load("res://scenes/test/phase1_test.tscn").instantiate()
	add_child(phase1_test)

	# 等待测试完成后退出
	await get_tree().create_timer(2.0).timeout
	print("")
	print("验证完成。关闭窗口以结束测试。")
