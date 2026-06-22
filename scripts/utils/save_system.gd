extends Node

const SAVE_PATH: String = "user://save_data.json"

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
