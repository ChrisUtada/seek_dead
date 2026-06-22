extends Node

## 资源管理器
## 负责加载和缓存 JSON 配置文件

var config_cache: Dictionary = {}

func _ready():
	print("[ResourceManager] Initialized")

func load_json(path: String) -> Variant:
	if path in config_cache:
		return config_cache[path]

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[ResourceManager] 无法加载配置文件: %s" % path)
		return null

	var text = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(text)

	if error != OK:
		push_error("[ResourceManager] JSON解析错误: %s at line %d" % [json.get_error_message(), json.get_error_line()])
		return null

	config_cache[path] = json.data
	print("[ResourceManager] 加载配置成功: %s" % path)
	return json.data

func save_json(path: String, data: Variant) -> bool:
	var dir_path = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)

	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("[ResourceManager] 无法写入文件: %s" % path)
		return false

	var json_string = JSON.stringify(data, "\t")
	file.store_string(json_string)
	file.close()
	print("[ResourceManager] 保存配置成功: %s" % path)
	return true

func clear_cache():
	config_cache.clear()
	print("[ResourceManager] 缓存已清空")
