extends "res://scripts/battle/player_controller.gd"

func _ready():
	super()
	var anim: AnimatedSprite2D = $Sprite2D
	if anim:
		anim.play("idle")

func _on_died():
	super()
	var anim: AnimatedSprite2D = $Sprite2D
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("death"):
		anim.play("death")

func _physics_process(delta):
	var anim: AnimatedSprite2D = $Sprite2D
	var prev_dir = mover.direction
	super(delta)
	if not anim or not anim.sprite_frames:
		return
	if not state.is_alive():
		return
	if mover.direction.length() > 0.1:
		if anim.animation != "run":
			anim.offset = Vector2(0, -16)
			anim.play("run")
	elif anim.animation != "idle":
		anim.offset = Vector2(0, 0)
		anim.play("idle")
