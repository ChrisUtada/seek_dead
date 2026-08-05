class_name BattleAnimator
extends Node
# P4 战斗动画骨架：tween 驱动玩家/敌人立绘的攻击 / 受击 / 暴击 / 核爆演出。
# 只读结算结果演出，绝不修改 BattleMath / duel_controller 的结算逻辑（解耦原则）。
# 浮空伤害数字由 BattleHud._popup 负责，本脚本专注立绘 sprite 动效。

var hud = null
var player_sprite: Control = null
var enemy_sprite: Control = null
var _shake_base := Transform2D()   # 屏震基准变换，供 _apply_shake 读取

func setup(p_hud) -> void:
	hud = p_hud
	player_sprite = hud.get_node("Margin/Content/MainRow/CenterStage/StageRow/PlayerCenter/PlayerSprite")
	enemy_sprite = hud.get_node("Margin/Content/MainRow/CenterStage/StageRow/EnemyCenter/EnemySprite")


func _sprite(which: String) -> Control:
	return player_sprite if which == "player" else enemy_sprite


# P0：攻击者前冲（scale 脉冲 + 轻微旋转）+ 目标受击红闪
func play_attack(attacker: String, target: String) -> void:
	var atk = _sprite(attacker)
	var tgt = _sprite(target)
	if atk == null or tgt == null:
		return
	_center_pivot(atk)
	var dir := 1.0 if attacker == "player" else -1.0
	var home_scale = atk.scale
	var tw = create_tween()
	tw.tween_property(atk, "scale", home_scale * 1.16, 0.09)
	tw.tween_property(atk, "scale", home_scale, 0.15)
	var twr = create_tween()
	twr.tween_property(atk, "rotation", 0.10 * dir, 0.09)
	twr.tween_property(atk, "rotation", 0.0, 0.15)
	var base = tgt.modulate
	var tw2 = create_tween()
	tw2.tween_property(tgt, "modulate", Color(1.6, 0.5, 0.5), 0.07)
	tw2.tween_property(tgt, "modulate", base, 0.24)


# P1：敌人反击（前冲 + 玩家红闪 + 屏震）
func play_enemy_attack() -> void:
	play_attack("enemy", "player")
	_shake(6.0)


# 反制即爆发演出：special = 通用破甲闪光；element = 克制核爆大字 + 膨胀 + 屏震
func play_counter(kind: String) -> void:
	if kind == "element":
		_big_text("💥 克制核爆!")
		if enemy_sprite != null:
			_center_pivot(enemy_sprite)
			var home = enemy_sprite.scale
			var tw = create_tween()
			tw.tween_property(enemy_sprite, "scale", home * 1.3, 0.10)
			tw.tween_property(enemy_sprite, "scale", home, 0.25)
		_shake(10.0)
	else:
		_big_text("⚡ 破甲!")
		_shake(7.0)


# P2：击杀溶解（方法备好，接入点待定：won overlay 时序复杂，留后续挂接）
func play_kill() -> void:
	if enemy_sprite == null:
		return
	var tw = create_tween()
	tw.tween_property(enemy_sprite, "modulate:a", 0.0, 0.5)
	tw.parallel().tween_property(enemy_sprite, "scale", Vector2(0.2, 0.2), 0.5)


func _center_pivot(c: Control) -> void:
	c.pivot_offset = c.size * 0.5


# 屏幕轻微震动：通过 viewport canvas_transform 偏移（不影响任何布局）
func _shake(intensity: float) -> void:
	var vp = get_viewport()
	_shake_base = vp.canvas_transform
	var tw = create_tween()
	for i in 6:
		var o1 = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		var o2 = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		tw.tween_method(_apply_shake, o1, o2, 0.03)
	tw.tween_method(_apply_shake, Vector2.ZERO, Vector2.ZERO, 0.03)


func _apply_shake(off: Vector2) -> void:
	var vp = get_viewport()
	var t = _shake_base
	t.origin += off
	vp.canvas_transform = t


# 居中大字（Label 缩放弹入 + 淡出），用于暴击 / 核爆提示
func _big_text(txt: String) -> void:
	if hud == null:
		return
	var l = Label.new()
	l.text = txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 40)
	l.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2, 1))
	l.modulate = Color(1, 1, 1, 0)
	l.scale = Vector2(0.6, 0.6)
	hud.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var tw = create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.10)
	tw.parallel().tween_property(l, "scale", Vector2(1.15, 1.15), 0.10)
	tw.tween_property(l, "scale", Vector2(1.0, 1.0), 0.10)
	tw.tween_interval(0.45)
	tw.tween_property(l, "modulate:a", 0.0, 0.30)
	tw.tween_callback(l.queue_free)
