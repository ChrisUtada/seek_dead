class_name Shadow
extends Node2D

@export var shadow_scale: Vector2 = Vector2(1.2, 0.4)
@export var shadow_offset: Vector2 = Vector2(0, 20)
@export var shadow_opacity: float = 0.3
@export var texture_size: int = 32

func _ready():
	var img = Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var half = texture_size / 2.0
	for x in range(texture_size):
		for y in range(texture_size):
			var dx = (x - half) / half
			var dy = (y - half) / half
			var dist_sq = dx * dx + dy * dy
			if dist_sq < 1.0:
				var alpha = (1.0 - dist_sq) * shadow_opacity
				img.set_pixel(x, y, Color(0, 0, 0, alpha))
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.centered = true
	sprite.scale = shadow_scale
	sprite.position = shadow_offset
	add_child(sprite)
