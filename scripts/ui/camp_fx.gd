extends Node2D
## 整备页营地动效
## - 炉火：炭底上的光团粒子 + 火星粒子 + 暖光呼吸
## - 烛火：原画烛焰保留，粒子只做绕着火焰飘的小光团
## - 吊瓶：完全静止（原画不动），只做随机单帧高光闪动
## - 桌上瓶罐：内部带呼吸感的亮光明灭（像装了萤火虫）
## 随机一律走本节点私有 RNG 实例，绝不碰全局 randf（会污染种子局）。

const FIRE_TEX: Texture2D = preload("res://assets/fx/fx_soft.png")
const EMBER_TEX: Texture2D = preload("res://assets/fx/fx_ember.png")
const GLINT_TEX: Texture2D = preload("res://assets/fx/fx_glint.png")
const DUST_TEX: Texture2D = preload("res://assets/fx/fx_dust.png")
const MOTE_TEX: Texture2D = preload("res://assets/fx/fx_mote.png")
const FIRE_SFX: AudioStream = preload("res://assets/audio/fire_loop.ogg")
const FIRE_SFX_DB := -3.0                    # 炉火底噪音量（源文件 mean -32dB，压太多会听不见）

const FIRE_ORIGIN := Vector2(119, 238)      # 炉膛炭床中心
const FIRE_HALF := Vector2(14, 3)           # 发射区半宽/半高
const ANVIL_POS := Vector2(228, 178)        # 铁砧砧面

## 吊挂三只瓶（原画，不重绘）：玻璃高光位置
const HANG_GLINTS: Array[Vector2] = [
	Vector2(275, 61),
	Vector2(288, 60),
	Vector2(298, 65),
]
const GLINT_PERIOD := Vector2(5.0, 7.5)     # 随机闪动间隔（秒）
const GLINT_HOLD := 0.34                    # 一次闪动的总时长（两段：亮 → 半亮）
const GLINT_DEBUG_ALWAYS := false           # 调试：强制高光常亮

## 桌面上三只瓶罐：内部呼吸光（萤火虫感）
const POT_GLOWS: Array[Vector2] = [
	Vector2(251, 84),
	Vector2(284, 84),
	Vector2(297, 86),
]

## 五个站位的「地贴光斑」位置（与 loadout_scene.tscn 的 Area2D 坐标一致）
const STATION_SPOTS: Array[Vector2] = [
	Vector2(120, 252),   # 熔炉 · 武器
	Vector2(196, 130),   # 书斋 · 技能
	Vector2(318, 138),   # 药台 · 消耗品
	Vector2(386, 186),   # 供台 · 护符
	Vector2(232, 258),   # 铁砧 · 强化
]

const CANDLES: Array[Vector2] = [
	Vector2(190, 70),   # 书桌蜡烛
	Vector2(374, 112),  # 石堆：左
	Vector2(387, 117),
	Vector2(405, 110),
	Vector2(419, 123),  # 石堆：最右
]

var _time := 0.0
var _fire: CPUParticles2D = null
var _glow: Sprite2D = null
var _glints: Array[Sprite2D] = []
var _glint_t: Array[float] = []
var _glint_wait: Array[float] = []
var _pot_glows: Array[Sprite2D] = []
var _pot_phase: Array[float] = []
var _sparks: CPUParticles2D = null
var _fire_sfx: AudioStreamPlayer = null
var _spark_wait := 3.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0x5EED11
	_build_fire()
	_build_embers()
	_build_candles()
	_build_glow()
	_build_station_spots()
	_build_hang_glints()
	_build_pot_glows()
	_build_sparks()
	_build_dust()
	_build_motes()
	_build_audio()


func _additive(node: CanvasItem) -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	node.material = m


func _build_fire() -> void:
	var p := CPUParticles2D.new()
	p.texture = FIRE_TEX
	p.position = FIRE_ORIGIN
	p.amount = 34
	p.lifetime = 0.72
	p.preprocess = 0.6
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = FIRE_HALF
	p.direction = Vector2(0, -1)
	p.spread = 9.0
	p.gravity = Vector2(0, -34)
	p.initial_velocity_min = 16.0
	p.initial_velocity_max = 34.0
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	p.color = Color(1, 0.92, 0.72, 0.95)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.94, 0.74, 0.50))
	g.add_point(0.30, Color(1.0, 0.82, 0.46, 0.46))
	g.add_point(0.62, Color(0.98, 0.55, 0.18, 0.34))
	g.set_color(g.get_point_count() - 1, Color(0.55, 0.16, 0.05, 0.0))
	p.color_ramp = g
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.80))
	sc.add_point(Vector2(0.45, 1.10))
	sc.add_point(Vector2(1, 0.45))
	p.scale_amount_curve = sc
	_additive(p)
	add_child(p)
	_fire = p


func _build_embers() -> void:
	var p := CPUParticles2D.new()
	p.texture = EMBER_TEX
	p.position = FIRE_ORIGIN + Vector2(0, -4)
	p.amount = 10
	p.lifetime = 1.7
	p.preprocess = 1.2
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(15, 2)
	p.direction = Vector2(0, -1)
	p.spread = 18.0
	p.gravity = Vector2(0, -14)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 20.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var g2 := Gradient.new()
	g2.set_color(0, Color(1, 0.95, 0.75, 0.0))
	g2.add_point(0.2, Color(1, 0.88, 0.55, 1.0))
	g2.add_point(0.7, Color(1, 0.55, 0.18, 0.8))
	g2.set_color(g2.get_point_count() - 1, Color(0.5, 0.15, 0.05, 0.0))
	p.color_ramp = g2
	_additive(p)
	add_child(p)


func _build_candles() -> void:
	# 保留背景里原有的烛焰，粒子只做「绕着烛焰飘的小光团」
	for pos in CANDLES:
		var p := CPUParticles2D.new()
		p.texture = FIRE_TEX
		p.position = pos + Vector2(0, -1)
		p.amount = 6
		p.lifetime = 1.45
		p.preprocess = 0.5
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 3.0
		p.direction = Vector2(0, -1)
		p.spread = 180.0
		p.gravity = Vector2(0, -6)
		p.initial_velocity_min = 4.0
		p.initial_velocity_max = 9.0
		p.scale_amount_min = 0.18
		p.scale_amount_max = 0.30
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.95, 0.78, 0.0))
		g.add_point(0.25, Color(1.0, 0.90, 0.62, 0.62))
		g.add_point(0.7, Color(1.0, 0.74, 0.36, 0.38))
		g.set_color(g.get_point_count() - 1, Color(0.85, 0.40, 0.12, 0.0))
		p.color_ramp = g
		_additive(p)
		add_child(p)


func _build_station_spots() -> void:
	# 站位地贴：地上一点微亮的暖光斑，提示"这里可以点"，不抢画面
	for pos in STATION_SPOTS:
		var sp := Sprite2D.new()
		sp.texture = FIRE_TEX
		sp.position = pos
		sp.scale = Vector2(4.0, 1.25)
		sp.modulate = Color(1.0, 0.80, 0.50, 0.30)
		_additive(sp)
		add_child(sp)


func _build_hang_glints() -> void:
	# 吊挂瓶完全不动（用的是背景原画），只在玻璃高光处随机闪一帧
	for pos in HANG_GLINTS:
		var gl := Sprite2D.new()
		gl.texture = GLINT_TEX
		gl.position = pos
		gl.visible = GLINT_DEBUG_ALWAYS
		gl.modulate = Color(1, 1, 1, 0.75)
		_additive(gl)
		add_child(gl)
		_glints.append(gl)
		_glint_t.append(0.0)
		_glint_wait.append(_rng.randf_range(0.8, GLINT_PERIOD.y))


func _build_pot_glows() -> void:
	# 桌上瓶罐里的"萤火虫"：柔光缓慢明灭，藏在罐子里
	for i in POT_GLOWS.size():
		var sp := Sprite2D.new()
		sp.texture = FIRE_TEX
		sp.position = POT_GLOWS[i]
		sp.scale = Vector2(1.05, 0.85)
		sp.modulate = Color(1.0, 0.74, 0.40, 0.0)
		_additive(sp)
		add_child(sp)
		_pot_glows.append(sp)
		_pot_phase.append(_rng.randf_range(0.0, TAU))


func _build_glow() -> void:
	# 火塘暖光呼吸：叠一层加色柔光，只影响炉子周围
	_glow = Sprite2D.new()
	_glow.texture = FIRE_TEX
	_glow.position = FIRE_ORIGIN + Vector2(2, -14)
	_glow.scale = Vector2(7.0, 5.2)
	_glow.modulate = Color(1.0, 0.62, 0.30, 0.12)
	_additive(_glow)
	add_child(_glow)


func _build_sparks() -> void:
	_sparks = CPUParticles2D.new()
	_sparks.texture = EMBER_TEX
	_sparks.position = ANVIL_POS
	_sparks.amount = 9
	_sparks.lifetime = 0.5
	_sparks.one_shot = true
	_sparks.explosiveness = 0.95
	_sparks.emitting = false
	_sparks.direction = Vector2(0, -1)
	_sparks.spread = 62.0
	_sparks.gravity = Vector2(0, 190)
	_sparks.initial_velocity_min = 26.0
	_sparks.initial_velocity_max = 58.0
	_sparks.scale_amount_min = 0.5
	_sparks.scale_amount_max = 0.9
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.97, 0.80, 1.0))
	g.add_point(0.45, Color(1.0, 0.72, 0.28, 0.9))
	g.set_color(g.get_point_count() - 1, Color(0.7, 0.22, 0.06, 0.0))
	_sparks.color_ramp = g
	_additive(_sparks)
	add_child(_sparks)


func _build_audio() -> void:
	# 炉火环境声：单独一个播放器，整备页显示时循环、隐藏时停止
	_fire_sfx = AudioStreamPlayer.new()
	_fire_sfx.stream = FIRE_SFX
	_fire_sfx.volume_db = FIRE_SFX_DB
	_fire_sfx.bus = &"Master"
	add_child(_fire_sfx)


func start_ambience() -> void:
	if _fire_sfx != null and not _fire_sfx.playing:
		_fire_sfx.play()


func stop_ambience() -> void:
	# 淡出再停，避免"啪"一声
	if _fire_sfx == null or not _fire_sfx.playing:
		return
	var tw := create_tween()
	tw.tween_property(_fire_sfx, "volume_db", -40.0, 0.45)
	tw.tween_callback(_fire_sfx.stop)
	tw.tween_callback(func() -> void: _fire_sfx.volume_db = FIRE_SFX_DB)


func _build_dust() -> void:
	# 空气里的浮尘：极慢、极淡，靠"看不见但感觉得到"增加氛围
	var p := CPUParticles2D.new()
	p.texture = DUST_TEX
	p.position = Vector2(240, 130)
	p.amount = 32
	p.lifetime = 14.0
	p.preprocess = 8.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(250, 130)
	p.direction = Vector2(1, -0.25)
	p.spread = 30.0
	p.gravity = Vector2(0, -1.5)
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 6.5
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.8
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.94, 0.84, 0.0))
	g.add_point(0.2, Color(1.0, 0.94, 0.84, 0.15))
	g.add_point(0.75, Color(1.0, 0.92, 0.82, 0.10))
	g.set_color(g.get_point_count() - 1, Color(1.0, 0.92, 0.82, 0.0))
	p.color_ramp = g
	_additive(p)
	add_child(p)


func _build_motes() -> void:
	# 柳絮/绒絮：比浮尘大、横着飘，偶尔一两团掠过
	var p := CPUParticles2D.new()
	p.texture = MOTE_TEX
	p.position = Vector2(-20, 120)
	p.amount = 5
	p.lifetime = 26.0
	p.preprocess = 14.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(6, 110)
	p.direction = Vector2(1, 0)
	p.spread = 22.0
	p.gravity = Vector2(0, -0.8)
	p.initial_velocity_min = 7.0
	p.initial_velocity_max = 12.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 0.9
	p.angular_velocity_min = -6.0
	p.angular_velocity_max = 6.0
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.96, 0.90, 0.0))
	g.add_point(0.15, Color(1.0, 0.96, 0.90, 0.24))
	g.add_point(0.8, Color(1.0, 0.95, 0.88, 0.15))
	g.set_color(g.get_point_count() - 1, Color(1.0, 0.95, 0.88, 0.0))
	p.color_ramp = g
	_additive(p)
	add_child(p)


func _process(delta: float) -> void:
	_time += delta
	if _fire == null:
		return

	# 炉火整体呼吸
	_fire.position = FIRE_ORIGIN + Vector2(0.0, sin(_time * 2.4) * 0.7)

	# 暖光呼吸
	if _glow != null:
		var a := 0.115 + 0.035 * sin(_time * 1.9) + 0.012 * sin(_time * 5.7 + 1.3)
		_glow.modulate = Color(1.0, 0.62, 0.30, a)
		_glow.scale = Vector2(7.0 + 0.18 * sin(_time * 1.9), 5.2 + 0.14 * sin(_time * 1.9))

	# 吊挂瓶：随机单帧高光
	for i in _glints.size():
		_glint_wait[i] -= delta
		if _glint_wait[i] <= 0.0:
			_glints[i].visible = true
			_glint_t[i] = GLINT_HOLD
			_glint_wait[i] = _rng.randf_range(GLINT_PERIOD.x, GLINT_PERIOD.y)
		elif _glint_t[i] > 0.0:
			_glint_t[i] -= delta
			if _glint_t[i] <= 0.0:
				_glints[i].visible = false
			else:
				# 两段式渐隐：先亮一档，再落到半亮，最后熄灭（不做亚像素插值）
				var k := _glint_t[i] / GLINT_HOLD
				var a := 0.92 if k > 0.55 else 0.55
				_glints[i].modulate = Color(1, 1, 1, a)

	# 桌上瓶罐：萤火虫般的缓慢明灭（双频叠加，不做同步）
	for i in _pot_glows.size():
		var ph: float = _pot_phase[i]
		var wave := 0.5 + 0.5 * sin(_time * 0.85 + ph)
		var flick := 0.5 + 0.5 * sin(_time * 2.7 + ph * 1.7)
		var v := clampf(0.10 + wave * 0.22 + flick * 0.08, 0.0, 0.42)
		_pot_glows[i].modulate = Color(1.0, 0.74, 0.40, v)
		_pot_glows[i].scale = Vector2(1.05 + 0.10 * wave, 0.85 + 0.08 * wave)

	# 铁砧偶发锤击火花
	_spark_wait -= delta
	if _spark_wait <= 0.0 and _sparks != null:
		_sparks.restart()
		_sparks.emitting = true
		_spark_wait = _rng.randf_range(5.5, 9.5)
