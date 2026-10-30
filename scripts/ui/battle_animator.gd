class_name BattleAnimator
extends Node
# P4 战斗动画骨架：tween 驱动玩家/敌人立绘的攻击 / 受击 / 暴击 / 核爆演出。
# 只读结算结果演出，绝不修改 BattleMath / duel_controller 的结算逻辑（解耦原则）。
# 浮空伤害数字由 BattleHud._popup 负责，本脚本专注立绘 sprite 动效。
# 2026-10-30（M3-02）：玩家立绘换 48×48 维京战士（assets/characters/viking/），
# idle 4 帧循环 + attack 5 帧序列；旧 knight 素材保留不回退、不删除。
# 注意：这偏离 M0-02「灰白流亡者」的样板范围——viking 是当前唯一完整的 48×48 角色帧组，
# 样板范围待用户确认后回写文档。

# 站立循环帧（4 帧，0.18s/帧）。
const PLAYER_IDLE_FRAMES := [
	preload("res://assets/characters/viking/idle_01.png"),
	preload("res://assets/characters/viking/idle_02.png"),
	preload("res://assets/characters/viking/idle_03.png"),
	preload("res://assets/characters/viking/idle_04.png"),
]
const PLAYER_IDLE_FRAME_TIME := 0.18
# 玩家攻击帧序列（attack_01-05：蓄力→挥击→命中→收势）。
# 帧长 0.06s × 5 ≈ 0.30s，必须 ≤ combat_system 在 play_attack 之后的 0.35s 等待窗口，
# 否则动画会被敌人回合打断（若改帧长/帧数，须同步核对那一处等待值）。
const PLAYER_ATTACK_FRAMES := [
	preload("res://assets/characters/viking/attack_01.png"),
	preload("res://assets/characters/viking/attack_02.png"),
	preload("res://assets/characters/viking/attack_03.png"),
	preload("res://assets/characters/viking/attack_04.png"),
	preload("res://assets/characters/viking/attack_05.png"),
]
const PLAYER_ATTACK_FRAME_TIME := 0.06
const PLAYER_IMPACT_FRAME := 3        # 索引 3 = attack_04（命中斩击帧）→ 触发轻微屏震
const PLAYER_IMPACT_SHAKE := 4.0

var hud = null
var player_sprite: Control = null
var enemy_sprite: Control = null
var _shake_base := Transform2D()   # 屏震基准变换，供 _apply_shake 读取
var _player_anim_tween: Tween = null   # 玩家帧序列 tween（重入先 kill，避免半帧残留）
var _idle_timer: Timer = null          # 站立循环节拍器（攻击演出期间暂停换帧）
var _idle_index := 0                   # 站立当前帧
var _attacking := false                # 攻击帧序列进行中（站立循环不抢帧）
var _rng := RandomNumberGenerator.new()   # 动画专用随机源（见 _shake 的 use_local_rng 说明）

func setup(p_hud) -> void:
	hud = p_hud
	player_sprite = hud.get_node("Margin/Content/MainRow/CenterStage/StageRow/PlayerCenter/PlayerSprite")
	enemy_sprite = hud.get_node("Margin/Content/MainRow/CenterStage/StageRow/EnemyCenter/EnemySprite")
	_idle_timer = Timer.new()
	_idle_timer.one_shot = false
	_idle_timer.wait_time = PLAYER_IDLE_FRAME_TIME
	_idle_timer.timeout.connect(_on_idle_tick)
	hud.add_child(_idle_timer)
	_idle_timer.start()


# 站立循环：仅在空闲时换帧（攻击序列与命中闪回由各自 tween 管理）。
func _on_idle_tick() -> void:
	if _attacking or player_sprite == null:
		return
	_idle_index = (_idle_index + 1) % PLAYER_IDLE_FRAMES.size()
	player_sprite.texture = PLAYER_IDLE_FRAMES[_idle_index]


func _sprite(which: String) -> Control:
	return player_sprite if which == "player" else enemy_sprite


# P0：攻击者前冲（scale 脉冲 + 轻微旋转）+ 目标受击红闪
func play_attack(attacker: String, target: String) -> void:
	var atk = _sprite(attacker)
	var tgt = _sprite(target)
	if atk == null or tgt == null:
		return
	# 仅玩家攻击播骑士帧序列（敌人攻击走 play_enemy_attack → 此处 attacker=="enemy"，跳过）
	if attacker == "player":
		_play_player_attack_frames()
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
	# M3-02：受击反馈改暖白闪（红色敌人用红闪会糊成一片）；亮而不偏色 = 明暗反相观感。
	tw2.tween_property(tgt, "modulate", Color(1.75, 1.70, 1.55), 0.07)
	tw2.tween_property(tgt, "modulate", base, 0.24)


# 玩家攻击帧序列：逐帧换 player_sprite.texture（非阻塞；播完回站立帧）。
# 与 play_attack 的 scale/rotation tween 并行，互不冲突（操作的是不同属性）。
func _play_player_attack_frames() -> void:
	if player_sprite == null:
		return
	if _player_anim_tween != null and _player_anim_tween.is_valid():
		_player_anim_tween.kill()   # 连击/重转重入：先掐掉上一轮，避免停在半帧
	_attacking = true
	_player_anim_tween = create_tween()
	for i in PLAYER_ATTACK_FRAMES.size():
		var idx: int = i
		_player_anim_tween.tween_callback(func() -> void:
			player_sprite.texture = PLAYER_ATTACK_FRAMES[idx]
			if idx == PLAYER_IMPACT_FRAME:
				_shake(PLAYER_IMPACT_SHAKE, true))   # 命中帧打击感；true=用动画专用随机源，不扰动种子局
		_player_anim_tween.tween_interval(PLAYER_ATTACK_FRAME_TIME)
	_player_anim_tween.tween_callback(func() -> void:
		_attacking = false
		player_sprite.texture = PLAYER_IDLE_FRAMES[_idle_index])


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
# 2026-09-22：新增 use_local_rng——新增的玩家攻击命中帧屏震必须走动画专用随机源。
# 理由：全局 randf_range 是种子局的唯一随机流（商店货架 / 房奖励 / 敌人意图全走它）。
# 动画若借全局流取随机数，等于整体平移种子流，会让同种子的局跑出不同结局
# （实测：多加这一次屏震后，tests/smoke_root.gd 的 Run C 种子局走向改变，撞出该测试
#  里一个潜伏的死循环——详见该文件 _spam_consumables_for_peace 的守卫注释）。
# 既有调用点（敌人攻击 / 暴击 / 核爆）保持走全局流不变，以免平移已验收的基线。
func _shake(intensity: float, use_local_rng: bool = false) -> void:
	var vp = get_viewport()
	_shake_base = vp.canvas_transform
	var tw = create_tween()
	for i in 6:
		var o1 = _rand_off(intensity, use_local_rng)
		var o2 = _rand_off(intensity, use_local_rng)
		tw.tween_method(_apply_shake, o1, o2, 0.03)
	tw.tween_method(_apply_shake, Vector2.ZERO, Vector2.ZERO, 0.03)


func _rand_off(intensity: float, use_local_rng: bool) -> Vector2:
	if use_local_rng:
		return Vector2(_rng.randf_range(-intensity, intensity), _rng.randf_range(-intensity, intensity))
	return Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))


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
	l.add_theme_font_size_override("font_size", 16)   # 像素字体缓存尺寸（16px 清晰）
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
