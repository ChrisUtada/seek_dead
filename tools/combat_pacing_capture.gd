extends Node

const OUT := "res://docs/baseline/2026-11-09_combat_pacing"
var duel: DuelController


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_window().size = Vector2i(960, 540)
	seed(9021)
	duel = load("res://scenes/duel/duel.tscn").instantiate() as DuelController
	duel.demo_config.enabled = true
	add_child(duel)
	await _wait(0.4)
	duel._confirm_loadout()
	await _wait(0.4)
	duel.start_room_data(load("res://resources/rooms/frozen_urn.tres"), 0, 7, true)
	await _wait(0.4)
	for turn in 4:
		await _play_turn()
		await _shot("turn_%d" % (turn + 1))
		if duel.game_state != DuelController.FlowState.PLAYING:
			break
	print("PACING_CAPTURE|DONE target=%s reason=%s" % [duel.readability.target_label(), duel.readability.target_reason])
	get_tree().quit()


func _play_turn() -> void:
	duel._on_spin_pressed()
	var frames := 0
	while frames < 900:
		frames += 1
		if duel.reel_system.spinning:
			duel.reel_system.stop_next_reel()
		elif not duel._busy:
			return
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, name])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
