extends Area2D

var direction: Vector2
var speed: float = 600.0
var damage: float = 20.0
var damage_type: int = 0
var shooter: Node = null
var status_effect_type: int = -1
var status_effect_damage: float = 0.0
var status_effect_duration: float = 3.0

func _ready():
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	position += direction * speed * delta

func _on_body_entered(body):
	if body == shooter:
		return
	if body.has_method("take_damage"):
		var result = body.take_damage(damage, damage_type)
		if status_effect_type >= 0 and body.has_method("apply_status"):
			body.apply_status(status_effect_type, status_effect_damage, status_effect_duration)
		var info = "%.0f" % result.final_damage
		if result.is_critical:
			info = "暴击! " + info
		if result.hit_result == DamageSystem.HitResult.WEAKNESS:
			info = "弱点! " + info
		print("子弹命中: %s" % info)
	queue_free()
