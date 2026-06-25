class_name CollisionSystem
extends RefCounted

const LAYER_PLAYER := 1
const LAYER_ENEMY := 2
const LAYER_ENVIRONMENT := 3
const LAYER_PICKUP := 4
const LAYER_HAZARD := 5
const LAYER_HURTBOX := 6
const LAYER_HITBOX := 7

static func bit(layer: int) -> int:
	return 1 << (layer - 1)

static func mask(layers: Array[int]) -> int:
	var m := 0
	for l in layers:
		m |= bit(l)
	return m
