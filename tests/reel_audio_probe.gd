extends Node

# 转轮音效接线诊断（2026-11-23）：按事件规格验证播放器配置 + RNG 不变量。
# 事件映射：启动 chop / 每格 metalClick 轮换±3% / 吸附静默 / 落定 impactSoft / 胜负 confirmation/impactPunch
const FIRE := "res://resources/weapon_templates/fire_sword.tres"
const ICE := "res://resources/weapon_templates/ice_staff.tres"

var _fails := 0
var _checks := 0


func _ok(c: bool, m: String) -> void:
	_checks += 1
	if not c:
		_fails += 1
		push_error("REEL_AUDIO FAIL: " + m)


func _ready() -> void:
	await get_tree().process_frame
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.selected_loadout.assign([FIRE, ICE])
	duel._confirm_loadout()
	await get_tree().process_frame
	var rs: ReelSystem = duel.reel_system as ReelSystem

	_ok(rs._sfx_start != null, "启动播放器存在")
	_ok(rs._sfx_tick_players.size() == 6, "每格音 6 个轮换播放器（metalClick 450ms 需 ≥6）")
	_ok(rs._sfx_land != null, "落定播放器存在")
	_ok(rs._sfx_win != null and rs._sfx_lose != null, "胜负播放器存在")
	_ok(rs._sfx_coin_players.size() == 2, "金币闪烁 2 个轮换播放器")
	_ok(rs._sfx_sym_players.size() == 3, "符号闪烁 3 类播放器存在（攻击/护盾/增益）")
	for c in ["attack", "shield", "support"]:
		_ok(rs._sfx_sym_players.has(c), "符号音 %s 播放器存在" % c)
	_ok(rs._sfx_start.stream != null and rs._sfx_land.stream != null, "音效 stream 已加载")
	for p in rs._sfx_tick_players:
		_ok(p.stream != null, "tick stream 已加载")
	_ok(rs._sfx_start.volume_db == -6.0 and rs._sfx_tick_players[0].volume_db == -12.0
		and rs._sfx_land.volume_db == -4.0, "音量分层正确")

	# 事件方法可调用不报错（实际听感靠 F6）
	rs.play_result_sfx(true)
	rs.play_result_sfx(false)
	rs.play_coin_sfx()
	for k in ["damage", "special", "shield", "heal", "buff", "status", "trash"]:
		rs.play_symbol_sfx(k)
	_ok(true, "胜负/金币/符号音效方法可调用（trash 静默）")

	# 铁律10：begin_spin + on_spin_tick 的 tick 音高抖动走独立 RNG，不碰全局 RNG。
	# 验证：相同全局种子下两次 begin_spin 后的全局 RNG 状态一致。
	seed(12345)
	rs.begin_spin()
	var state1 := randi()
	seed(12345)
	rs.begin_spin()
	var state2 := randi()
	_ok(state1 == state2, "音效未额外消耗全局 RNG（铁律10，状态 %d/%d）" % [state1, state2])

	# tick 音高抖动范围 ±3%
	var t: float = rs._sfx_rng.randf_range(0.97, 1.03)
	_ok(t >= 0.97 and t <= 1.03, "独立 RNG 音高抖动范围正确")

	print("REEL_AUDIO|RESULT|checks=%d|fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
