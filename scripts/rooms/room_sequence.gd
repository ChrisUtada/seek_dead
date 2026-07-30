class_name RoomSequence
extends RefCounted

const TOTAL_ROOMS := 10
const FIXED_ROOMS := 3
const VARIABLE_ROOMS := TOTAL_ROOMS - FIXED_ROOMS

enum RoomSize { SMALL, MEDIUM, LARGE, BOSS }

static func generate() -> Array[int]:
	var sizes: Array[int] = []

	var medium_count: int
	var large_count: int

	medium_count = 3 + randi() % 2
	large_count = VARIABLE_ROOMS - medium_count

	for _i in medium_count:
		sizes.append(RoomSize.MEDIUM)
	for _i in large_count:
		sizes.append(RoomSize.LARGE)

	sizes.shuffle()

	var boss_pos = 2 + randi() % 3
	sizes.insert(boss_pos, RoomSize.BOSS)

	sizes.insert(0, RoomSize.SMALL)
	sizes.insert(0, RoomSize.SMALL)

	Debug.log("RoomSequence (%d rooms, BOSS in room %d): %s" % [sizes.size(), boss_pos + 3, _size_names(sizes)])
	return sizes


static func _size_names(sizes: Array[int]) -> String:
	var names := PackedStringArray()
	for s in sizes:
		match s:
			RoomSize.SMALL: names.append("SMALL")
			RoomSize.MEDIUM: names.append("MEDIUM")
			RoomSize.LARGE: names.append("LARGE")
			RoomSize.BOSS: names.append("BOSS")
	return " → ".join(names)
