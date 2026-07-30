extends Node

const SAVE_PATH: String = "user://save_data.json"
const LOBBY_PATH: String = "user://lobby_data.json"

# 大厅存档防抖：所有 lobby 写入先落内存缓存，最多每 _LOBBY_FLUSH_INTERVAL 秒批量落盘一次，
# 避免高频调用（拾取/收集/附魔）造成的频繁 IO 与读改写竞争（审查建议 C）。
const LOBBY_FLUSH_INTERVAL: float = 0.5

var _lobby_cache: Dictionary = {}
var _lobby_loaded: bool = false
var _lobby_dirty: bool = false
var _lobby_flush_timer: float = 0.0


func _process(delta: float) -> void:
	if _lobby_dirty:
		_lobby_flush_timer -= delta
		if _lobby_flush_timer <= 0.0:
			_flush_lobby()

func save_game(data: Dictionary) -> bool:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_error("SaveSystem: 无法打开存档文件")
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true

func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return {}
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		push_error("SaveSystem: 存档解析失败 - " + json.get_error_message())
		return {}
	return json.data

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func delete_save():
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)

## 写入大厅存档。先更新内存缓存并标记脏，实际落盘由防抖定时器批量执行；
## 关键节点（运行结束/退出/附魔后）应改调 flush_lobby_data() 立即落盘。
func save_lobby_data(data: Dictionary) -> bool:
	_lobby_cache = data
	_lobby_loaded = true
	_mark_lobby_dirty()
	return true

## 读取大厅存档。优先返回内存缓存；缓存未初始化时从磁盘加载并缓存。
func load_lobby_data() -> Dictionary:
	if not _lobby_loaded:
		_lobby_cache = _read_json(LOBBY_PATH)
		_lobby_loaded = true
	return _lobby_cache

## 清空大厅存档（文件 + 内存缓存）。
func reset_lobby_data():
	DirAccess.remove_absolute(LOBBY_PATH)
	_lobby_cache = {}
	_lobby_loaded = false
	_lobby_dirty = false


## 关键节点立即把大厅缓存落盘（绕过防抖）。用于运行结束、退出、附魔等不可丢失的存档点。
func flush_lobby_data():
	_flush_lobby()


func _mark_lobby_dirty():
	_lobby_dirty = true
	_lobby_flush_timer = LOBBY_FLUSH_INTERVAL


func _flush_lobby():
	if not _lobby_loaded or not _lobby_dirty:
		return
	if _write_json(LOBBY_PATH, _lobby_cache):
		_lobby_dirty = false
		_lobby_flush_timer = 0.0
	else:
		# 写入失败则保留脏标记，下一帧 _process 重试
		Debug.warn("SaveSystem: 大厅存档落盘失败，下一帧重试")


## 退出时尽力把待落盘的大厅数据写入磁盘，避免丢失。
func _exit_tree():
	_flush_lobby()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK:
		push_error("SaveSystem: 存档解析失败 - " + json.get_error_message())
		return {}
	return json.data


func _write_json(path: String, data: Dictionary) -> bool:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("SaveSystem: 无法打开存档文件: " + path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true
