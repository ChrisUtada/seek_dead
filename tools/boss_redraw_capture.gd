extends Node

const OUT_DIR := "res://docs/baseline/2026-11-05_boss_redraw/ingame"
const BOSS_IDS := [
	"acid_ghoul", "brittle_gargoyle", "abyss_watcher", "hero_shadow",
	"manic_elementalist", "maze_whisperer", "nameless_void",
	"scale_inquisitor", "shattered_king", "whispering_cultist",
]

var _duel: DuelController
var _report: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_window().size = Vector2i(960, 540)
	_duel = load("res://scenes/duel/duel.tscn").instantiate() as DuelController
	add_child(_duel)
	await _wait(0.4)
	_duel._confirm_loadout()
	await _wait(0.8)
	var boss_idx := -1
	for i in _duel.ROOMS.size():
		if _duel.ROOMS[i].kind == "boss":
			boss_idx = i
			break
	if boss_idx < 0:
		push_error("No boss room available")
		get_tree().quit(2)
		return
	for boss_id in BOSS_IDS:
		var room: RoomData = load("res://resources/rooms/%s.tres" % boss_id)
		if room == null:
			push_error("Missing room: " + boss_id)
			get_tree().quit(2)
			return
		_duel.player_hp = _duel.player_hp_max
		_duel.ROOMS[boss_idx] = room
		_duel._start_room(boss_idx)
		await _wait(0.75)
		_duel.hud.symbol_tooltip.visible = false
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var err := image.save_png("%s/%s.png" % [OUT_DIR, boss_id])
		var sprite: TextureRect = _duel.hud.enemy_sprite
		_report.append("%s | png=%s | scale=%s | art_scale=%s | shot=%dx%d err=%d" % [
			boss_id, str(sprite.texture.get_size()), str(sprite.scale), str(room.art_scale),
			image.get_width(), image.get_height(), err])
		print(_report.back())
		if boss_id == "hero_shadow":
			_duel.hud.animator.play_attack("player", "enemy")
			await _wait(0.08)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OUT_DIR + "/player_attack_windup.png")
			await _wait(0.13)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OUT_DIR + "/player_attack_impact.png")
			await _wait(0.35)
	var file := FileAccess.open(OUT_DIR + "/capture_data.txt", FileAccess.WRITE)
	file.store_string("\n".join(_report) + "\n")
	print("BOSS_CAPTURE|DONE count=%d" % _report.size())
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
