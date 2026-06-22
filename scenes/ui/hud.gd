extends CanvasLayer

@onready var weapon_label: Label = $WeaponLabel

func _ready():
	var player = get_node("/root/PlayerTest/Player")
	if player and player.has_signal("weapon_changed"):
		player.weapon_changed.connect(_on_weapon_changed)
		if player.current_weapon:
			_on_weapon_changed(player.current_weapon)

func _on_weapon_changed(weapon: WeaponBase):
	var color = DamageSystem.get_color(weapon.damage_type)
	weapon_label.text = "武器: %s | 伤害: %.0f | 类型: %s" % [weapon.weapon_name, weapon.damage, DamageSystem.damage_type_to_string(weapon.damage_type)]
	weapon_label.label_settings.font_color = color
