class_name BattleAnimator
extends Node
# P4 战斗动画骨架：tween 驱动玩家/敌人立绘的攻击 / 受击 / 暴击 / 核爆演出。
# 只读结算结果演出，绝不修改 BattleMath / duel_controller 的结算逻辑（解耦原则）。
# 浮空伤害数字由 BattleHud._popup 负责，本脚本专注立绘 sprite 动效。
# 玩家使用 48×48 正面持盾骑士静态立绘（knight_v1/hero_48.png），不做帧动画。
# 2026-11-09：原 viking_ash/idle_01~04 四帧呼吸改为单帧静态；旧帧素材保留未删，可随时切回。

# 静态立绘（单帧）。_on_idle_tick() 对 size=1 取模安全，仅重复赋同一张图、视觉静止。
const PLAYER_IDLE_FRAMES := [
	preload("res://assets/characters/knight_v1/hero_48.png"),
]
const PLAYER_IDLE_FRAME_TIME := 0.18

# ── 方案 A：借 pixelfx-godot 的 act 时序，只借时间、不借像素 ──────────────────
# 数据源：./pfx sheets melee/sword-slash --spriteframes 产出的 meta.pixelfx.act
#   windup 0.55 / hit t 0.06 / freeze 0.14 / recovery 0.11 / duration 0.75 / shake 0.18 amp 2
# 官方整套约 1.35s，对回合制偏拖；按 ACT_TIME_SCALE 等比压到 ~0.34s，
# 保留「前摇 → 命中顿帧 → 恢复」的结构比例，玩家仍是 48×48 静态立绘、不旋转、不切帧。
# pixelfx 的小人由 rig.gd 骨架实时求解，不是可替换的帧动画，故这里只取时序数据。
const ACT_TIME_SCALE := 0.42
const ACT_WINDUP := 0.55 * ACT_TIME_SCALE
const ACT_FREEZE := 0.14 * ACT_TIME_SCALE
const ACT_RECOVER := 0.11 * ACT_TIME_SCALE
const SLASH_SPEED_SCALE := 2.4   # 24 帧 @30fps = 0.8s，压到 ~0.33s 与演出等长
const SLASH_FRAMES := preload("res://assets/fx/sword_slash.res")   # 自包含 SpriteFrames，动画名 "default"
# 落点三件套（F6 目视后改这里即可）：单帧 136×104，pivot 来自 meta.pixelfx.pivot。
# 默认让弧光落在剑举朝右的上半身方向；曾试 (20,56)/0.55，弧光压在腰腹且与剑不连贯。
const SLASH_FX_PIVOT := Vector2(44, 92)
const SLASH_FX_SCALE := Vector2(0.45, 0.45)
const SLASH_FX_POS := Vector2(30, 42)

var hud = null
var player_sprite: Control = null
var enemy_sprite: Control = null
var _slash_fx: AnimatedSprite2D = null
var _shake_base := Transform2D()   # 屏震基准变换，供 _apply_shake 读取
var _idle_timer: Timer = null          # 站立呼吸节拍器
var _idle_index := 0                   # 站立当前帧
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

	# 斩击特效层：挂为玩家立绘的子节点（天然在角色前面），先 add_child 再 configure。
	# 零插件依赖 —— 直接播导出的 SpriteFrames，不需要把 addons/pixelfx 拷进 res://addons/、也不用启用插件。
	_slash_fx = AnimatedSprite2D.new()
	_slash_fx.name = "SlashFx"
	player_sprite.add_child(_slash_fx)
	_slash_fx.sprite_frames = SLASH_FRAMES
	_slash_fx.animation = "default"
	_slash_fx.centered = false
	_slash_fx.offset = -SLASH_FX_PIVOT        # 让 feet 落在 SLASH_FX_POS
	_slash_fx.scale = SLASH_FX_SCALE          # 136×104 → ~61×47，适配 48×48 骑士 / 480×270
	_slash_fx.position = SLASH_FX_POS
	_slash_fx.speed_scale = SLASH_SPEED_SCALE
	_slash_fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_slash_fx.visible = false
	_slash_fx.animation_finished.connect(_on_slash_finished)


func _on_slash_finished() -> void:
	if _slash_fx != null:
		_slash_fx.visible = false


func _play_slash_fx() -> void:
	if _slash_fx == null:
		return
	_slash_fx.visible = true
	_slash_fx.frame = 0
	_slash_fx.speed_scale = SLASH_SPEED_SCALE
	_slash_fx.play("default")


func _on_idle_tick() -> void:
	if player_sprite == null:
		return
	_idle_index = (_idle_index + 1) % PLAYER_IDLE_FRAMES.size()
	player_sprite.texture = PLAYER_IDLE_FRAMES[_idle_index]


func _sprite(which: String) -> Control:
	return player_sprite if which == "player" else enemy_sprite


# 攻击者蓄力 → 命中定格 → 恢复；目标闪白对齐命中点。
# 时长来自 pixelfx-godot 的 act 时序（见文件头常量），只借时间不借像素；玩家不旋转、不切帧。
# 特效层固定在玩家侧：玩家攻击时读作剑尖弧光，敌人攻击时读作落在该处的受击弧光。
func play_attack(attacker: String, target: String) -> void:
	var atk = _sprite(attacker)
	var tgt = _sprite(target)
	if atk == null or tgt == null:
		return
	_center_pivot(atk)
	var home_scale = atk.scale

	# 特效 ~0.33s 与下面演出 ~0.34s 等长：起手帧对齐前摇、弧光峰值对齐命中。
	_play_slash_fx()

	# 前摇：官方 WIND→CUT，略收身再前冲；只用 scale，不动 VBoxContainer 布局。
	var tw = create_tween()
	tw.tween_property(atk, "scale", Vector2(home_scale.x * 0.94, home_scale.y * 1.10), ACT_WINDUP * 0.65)
	tw.tween_property(atk, "scale", Vector2(home_scale.x * 1.16, home_scale.y * 0.96), ACT_WINDUP * 0.35)
	tw.tween_interval(ACT_FREEZE)   # hit-stop：命中瞬间定格
	tw.tween_property(atk, "scale", home_scale, ACT_RECOVER)

	if attacker == "enemy":
		var twr = create_tween()
		twr.tween_property(atk, "rotation", -0.10, ACT_WINDUP)
		twr.tween_property(atk, "rotation", 0.0, ACT_FREEZE + ACT_RECOVER)

	# 目标受击暖白闪延迟到命中点才起，不再从攻击一开始就亮。
	var base = tgt.modulate
	var tw2 = create_tween()
	tw2.tween_interval(ACT_WINDUP)
	tw2.tween_property(tgt, "modulate", Color(1.75, 1.70, 1.55), 0.07)
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
