extends CanvasLayer

@onready var _container: Control = $Container
@onready var _panels_container: Control = $Container/PanelsContainer
@onready var _forge_panel: Control = $Container/PanelsContainer/ForgePanel
@onready var _collection_panel: Control = $Container/PanelsContainer/CollectionPanel
@onready var _coll_progress: Label = $Container/PanelsContainer/CollectionPanel/ProgressLabel
@onready var _coll_bar_fill: ColorRect = $Container/PanelsContainer/CollectionPanel/BarFill
@onready var _coll_bonus: Label = $Container/PanelsContainer/CollectionPanel/BonusLabel
@onready var _coll_list: Label = $Container/PanelsContainer/CollectionPanel/ListLabel

const RESOURCE_NAMES: Dictionary = {
	"gold": ["金币", Color(1, 0.85, 0.3)],
	"iron": ["铁碎片", Color(0.6, 0.6, 0.7)],
	"magic_essence": ["魔法精华", Color(0.4, 0.5, 1)],
	"legendary_core": ["传奇核心", Color(1, 0.4, 0.2)],
}

const _LABEL_STYLES: Dictionary = {
	"Container/Title": { "size": 20, "color": Color(0.8, 0.8, 0.8), "outline": Color(0, 0, 0), "outline_size": 2 },
	"Container/Subtitle": { "size": 9, "color": Color(0.4, 0.4, 0.4) },
	"Container/ResTitle": { "size": 12, "color": Color(0.7, 0.7, 0.7) },
	"Container/ResGold": { "size": 10 },
	"Container/ResIron": { "size": 10 },
	"Container/ResMagic": { "size": 10 },
	"Container/ResLegendary": { "size": 10 },
	"Container/DoorArea/DoorLabel": { "size": 10, "color": Color(0.8, 0.7, 0.5), "outline": Color(0, 0, 0), "outline_size": 1 },
	"Container/ForgeArea/RoleLabel": { "size": 9, "color": Color(0.8, 0.8, 0.6), "outline": Color(0, 0, 0), "outline_size": 1 },
	"Container/CollectionArea/RoleLabel": { "size": 9, "color": Color(0.8, 0.8, 0.6), "outline": Color(0, 0, 0), "outline_size": 1 },
	"Container/ExitArea/ExitLabel": { "size": 11, "color": Color(0.8, 0.8, 0.8) },
	"Container/PanelsContainer/ForgePanel/PanelTitle": { "size": 14, "color": Color(0.6, 0.8, 1) },
	"Container/PanelsContainer/ForgePanel/HintLabel": { "size": 11, "color": Color(0.5, 0.5, 0.5) },
	"Container/PanelsContainer/ForgePanel/CloseBtn/CloseLabel": { "size": 12 },
	"Container/PanelsContainer/CollectionPanel/PanelTitle": { "size": 14, "color": Color(0.4, 1, 0.4) },
	"Container/PanelsContainer/CollectionPanel/ProgressLabel": { "size": 12 },
	"Container/PanelsContainer/CollectionPanel/BonusLabel": { "size": 10 },
	"Container/PanelsContainer/CollectionPanel/ListLabel": { "size": 9 },
	"Container/PanelsContainer/CollectionPanel/CloseBtn/CloseLabel": { "size": 12 },
}

const PANEL_NONE = -1
const PANEL_FORGE = 0
const PANEL_COLLECTION = 1
var _active_panel: int = PANEL_NONE


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_style_labels()
	_refresh_resources()
	_make_interactive($Container/DoorArea, _on_start_run)
	_make_interactive($Container/ForgeArea, _on_open_forge)
	_make_interactive($Container/CollectionArea, _on_open_collection)
	_make_interactive($Container/ExitArea, _on_back_to_menu)
	_make_interactive($Container/PanelsContainer/Overlay, _close_all_panels)
	_make_interactive($Container/PanelsContainer/ForgePanel/CloseBtn, _close_all_panels)
	_make_interactive($Container/PanelsContainer/CollectionPanel/CloseBtn, _close_all_panels)
	_container.modulate = Color(1, 1, 1, 0)
	var t = create_tween()
	t.tween_property(_container, "modulate", Color(1, 1, 1, 1), 0.3)


func _style_labels():
	for path in _LABEL_STYLES:
		var node = get_node_or_null(path)
		if not node or not node is Label:
			continue
		var lbl = node as Label
		var opts = _LABEL_STYLES[path]
		if opts.has("size"):
			lbl.add_theme_font_size_override("font_size", opts.size)
		if opts.has("color"):
			lbl.add_theme_color_override("font_color", opts.color)
		if opts.has("outline"):
			lbl.add_theme_color_override("font_outline_color", opts.outline)
		if opts.has("outline_size"):
			lbl.add_theme_constant_override("outline_size", opts.outline_size)


func _make_interactive(control: Control, callback: Callable):
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	control.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			callback.call()
	)


func _refresh_resources():
	var data = SaveSystem.load_lobby_data()
	var _res_nodes = {
		"gold": $Container/ResGold,
		"iron": $Container/ResIron,
		"magic_essence": $Container/ResMagic,
		"legendary_core": $Container/ResLegendary,
	}
	for key in _res_nodes:
		var label = _res_nodes[key] as Label
		var meta = RESOURCE_NAMES[key]
		var val = data.get(key, 0)
		label.text = "%s: %s" % [meta[0], _fmt_num(val)]
		label.add_theme_color_override("font_color", meta[1] if val > 0 else Color(0.4, 0.4, 0.4))


func _fmt_num(v: int) -> String:
	if v >= 100000:
		return "%dk" % (v / 1000)
	return str(v)


func _open_panel(idx: int):
	_close_all_panels()
	_active_panel = idx
	_panels_container.show()
	_forge_panel.visible = idx == PANEL_FORGE
	_collection_panel.visible = idx == PANEL_COLLECTION
	if idx == PANEL_COLLECTION:
		_refresh_collection()


func _refresh_collection():
	var total = Collection.get_total_count()
	var count = Collection.get_collection_count()
	var pct = Collection.get_completion_percent()
	_coll_progress.text = "收集进度: %d / %d  (%.0f%%)" % [count, total, pct * 100.0]
	_coll_bar_fill.size.x = 400.0 * pct

	var bonuses = Collection.get_global_bonuses()
	var txt = "全局奖励:"
	if bonuses.size() == 0:
		txt += "\n  收集 5 件解锁 HP+20"
	else:
		var m = {"max_hp": "HP上限", "move_speed": "移速", "attack_damage": "伤害", "crit_rate": "暴击率"}
		for k in bonuses:
			txt += "\n  " + m.get(k, k) + " +" + str(bonuses[k])
	_coll_bonus.text = txt

	var collected = Collection.get_collected()
	var list_txt = "已收集:"
	for k in collected:
		list_txt += " " + k
	if collected.size() == 0:
		list_txt += " 无"
	_coll_list.text = list_txt


func _on_start_run():
	SaveSystem.delete_save()
	SceneManager.fade_to_scene("res://scenes/game/game.tscn")


func _on_open_forge():
	_open_panel(PANEL_FORGE)


func _on_open_collection():
	_open_panel(PANEL_COLLECTION)


func _close_all_panels():
	_active_panel = PANEL_NONE
	if _panels_container:
		_panels_container.hide()


func _on_back_to_menu():
	SceneManager.fade_to_scene("res://scenes/ui/main_menu.tscn")
