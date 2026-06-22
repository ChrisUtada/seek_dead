extends Node2D

const ENEMY_SCENE = preload("res://scenes/enemies/skeleton.tscn")
const ENEMY_CONFIG = preload("res://resources/enemies/skeleton.tres")

var _enemies: Array = []
var _fps_samples: Array = []
var _test_phase: String = "spawn"
var _spawn_count: int = 0
var _phase_timer: float = 0.0
var _report: Dictionary = {}

func _ready():
	print("\n" + "=".repeat(70))
	print("  性能测试开始")
	print("=".repeat(70))
	_spawn_wave(5)

func _spawn_wave(count: int):
	_spawn_count = count
	_enemies.clear()
	for i in range(count):
		var e = ENEMY_SCENE.instantiate()
		var x = randf_range(200, 1400)
		var y = randf_range(200, 1000)
		e.position = Vector2(x, y)
		add_child(e)
		e.apply_config(ENEMY_CONFIG)
		_enemies.append(e)

func _process(delta):
	_phase_timer += delta
	_fps_samples.append(Performance.get_monitor(Performance.TIME_FPS))

	if _test_phase == "spawn" and _phase_timer >= 5.0:
		_report["combat_5enemy_avg_fps"] = _avg_fps()
		_fps_samples.clear()
		_phase_timer = 0.0
		_spawn_wave(10)

	elif _test_phase == "spawn" and _spawn_count == 10 and _phase_timer >= 5.0:
		_report["combat_10enemy_avg_fps"] = _avg_fps()
		_fps_samples.clear()
		_phase_timer = 0.0
		_finish()

func _avg_fps() -> float:
	if _fps_samples.is_empty():
		return 0.0
	var sum = 0.0
	for s in _fps_samples:
		sum += s
	return sum / _fps_samples.size()

func _finish():
	print("\n" + "=".repeat(70))
	print("  性能测试报告")
	print("=".repeat(70))
	for key in _report:
		print("  %s: %.1f FPS" % [key, _report[key]])
	print("=".repeat(70))
	print("")
	_report["timestamp"] = Time.get_datetime_string_from_system()
	var file = FileAccess.open("user://perf_report.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_report, "\t"))
		file.close()
		print("性能报告已保存: user://perf_report.json")
	queue_free()
