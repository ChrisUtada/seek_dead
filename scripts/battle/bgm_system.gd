class_name BgmSystem
extends RefCounted

# 战斗 BGM（2026-11-23）——单曲循环 + 淡入淡出。
# 素材：OpenGameArt "Battle Theme A"（CC0，免署名，可商用/游戏），
#   完整曲存 res://assets/audio/music/duel_bgm.ogg（1:36）。
#
# 由 duel_controller 在 _ready 创建并注入：BgmSystem.new(self)。
# 约定同其它子系统：不持有 meta，跨系统联动留在 controller。
#
# 混音原则（经典）：BGM 音量低于 SFX（本作 SFX -3~-8dB），BGM 设 -18dB，
#   保证音乐烘托氛围而不盖住攻击/金币/治愈等反馈音。

const BGM_STREAM: AudioStream = preload("res://assets/audio/music/duel_bgm.ogg")
const BGM_TARGET_DB := -18.0
const FADE_IN_SEC := 1.2
const FADE_OUT_SEC := 0.6

var _ctrl: DuelController
var _player: AudioStreamPlayer = null
var _enabled := true        # 用户可关（预留：设置项/静音键）
var _playing := false


func _init(ctrl: DuelController) -> void:
	_ctrl = ctrl


func _ensure_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	_player = AudioStreamPlayer.new()
	_player.stream = BGM_STREAM
	_player.bus = &"Master"
	_player.volume_db = -60.0   # 从静音起步，淡入
	_ctrl.add_child(_player)
	# ogg 循环无缝（无 mp3 编码延迟），stream 本身设 loop
	var ogg := BGM_STREAM as AudioStreamOggVorbis
	if ogg != null:
		ogg.loop = true


func start() -> void:
	if not _enabled or _playing:
		return
	_ensure_player()
	if _player == null:
		return
	_playing = true
	if not _player.playing:
		_player.play()
	_fade_to(BGM_TARGET_DB, FADE_IN_SEC)


func stop(fade: bool = true) -> void:
	if not _playing or _player == null:
		return
	_playing = false
	if fade:
		_fade_to(-60.0, FADE_OUT_SEC)
	else:
		_player.stop()


func set_enabled(on: bool) -> void:
	_enabled = on
	if on:
		start()
	else:
		stop()


func is_playing() -> bool:
	return _playing


func _fade_to(target_db: float, duration: float) -> void:
	if _player == null:
		return
	var tw := _ctrl.create_tween()
	tw.tween_property(_player, "volume_db", target_db, duration)
