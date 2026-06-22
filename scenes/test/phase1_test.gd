extends Node

## 阶段一测试脚本
## 验证 Autoload 单例、Signals 事件系统、JSON 资源管理

var passed := 0
var failed := 0

func _ready():
	print("")
	print("=".repeat(50))
	print("  阶段一：基础框架验证")
	print("=".repeat(50))
	print("")

	test_autoload_singleton()
	test_game_manager()
	test_event_manager_signals()
	test_resource_manager_json()

	print("")
	print("=".repeat(50))
	print("  测试结果: %d 通过, %d 失败" % [passed, failed])
	print("=".repeat(50))
	print("")

	if failed == 0:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")

func test_autoload_singleton():
	print("[Test] Autoload 单例验证")

	var gm1 = GameManager
	var gm2 = GameManager
	assert(gm1 == gm2, "GameManager 单例失败")
	_assert_true(gm1 != null, "GameManager 不为空")
	_assert_true(gm2 != null, "GameManager 不为空")

	var em1 = EventManager
	var em2 = EventManager
	assert(em1 == em2, "EventManager 单例失败")
	_assert_true(em1 != null, "EventManager 不为空")

	var rm1 = ResourceManager
	var rm2 = ResourceManager
	assert(rm1 == rm2, "ResourceManager 单例失败")
	_assert_true(rm1 != null, "ResourceManager 不为空")

	_pass("Autoload 单例验证")

func test_game_manager():
	print("[Test] GameManager 功能验证")

	_assert_true(GameManager.current_level == 1, "初始关卡为1")
	_assert_true(GameManager.is_paused == false, "初始状态未暂停")

	GameManager.pause_game()
	_assert_true(GameManager.is_paused == true, "暂停后状态为true")

	GameManager.resume_game()
	_assert_true(GameManager.is_paused == false, "恢复后状态为false")

	GameManager.change_level(5)
	_assert_true(GameManager.current_level == 5, "切换关卡到5")

	GameManager.reset()
	_assert_true(GameManager.current_level == 1, "重置后关卡为1")

	_pass("GameManager 功能验证")

var _signal_received := false
var _signal_amount := 0.0

func test_event_manager_signals():
	print("[Test] EventManager Signals 验证")

	_signal_received = false
	_signal_amount = 0.0

	var callable = Callable(self, "_on_damage_dealt")
	EventManager.damage_dealt.connect(callable)
	EventManager.damage_dealt.emit(null, null, 150.0, 0)

	_assert_true(_signal_received == true, "信号已接收")
	_assert_true(_signal_amount == 150.0, "信号参数正确")

	EventManager.damage_dealt.disconnect(callable)

	_pass("EventManager Signals 验证")

func _on_damage_dealt(attacker: Node2D, defender: Node2D, amount: float, damage_type: int):
	_signal_received = true
	_signal_amount = amount

func test_resource_manager_json():
	print("[Test] ResourceManager JSON 验证")

	# 测试保存和读取
	var test_data = {
		"weapons": [
			{"name": "1HSword", "damage": 50, "type": "slash"},
			{"name": "G36", "damage": 30, "type": "puncture"}
		],
		"enemies": {
			"slime": {"hp": 100, "speed": 2.0},
			"bat": {"hp": 50, "speed": 4.0}
		}
	}

	var save_path = "user://test_config.json"
	var save_result = ResourceManager.save_json(save_path, test_data)
	_assert_true(save_result == true, "JSON保存成功")

	var loaded = ResourceManager.load_json(save_path)
	_assert_true(loaded != null, "JSON加载成功")
	_assert_true(loaded["weapons"][0]["name"] == "1HSword", "数据读取正确")
	_assert_true(loaded["enemies"]["slime"]["hp"] == 100, "嵌套数据读取正确")

	# 测试缓存机制
	var cached = ResourceManager.load_json(save_path)
	_assert_true(cached == loaded, "缓存机制正常")

	ResourceManager.clear_cache()
	_assert_true(ResourceManager.config_cache.size() == 0, "缓存清空成功")

	# 测试加载项目内配置文件
	var project_config = ResourceManager.load_json("res://resources/test_config.json")
	_assert_true(project_config != null, "项目内配置加载成功")
	_assert_true(project_config.has("weapons"), "配置包含weapons字段")
	_assert_true(project_config["weapons"].size() == 2, "武器数量正确")
	_assert_true(project_config["damage_types"]["fire"] == 3, "伤害类型映射正确")

	_pass("ResourceManager JSON 验证")

func _assert_true(condition: bool, message: String):
	if not condition:
		print("  [FAIL] %s" % message)
		failed += 1

func _pass(test_name: String):
	passed += 1
	print("  [PASS] %s" % test_name)
	print("")
