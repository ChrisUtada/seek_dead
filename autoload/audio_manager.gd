extends Node

enum SfxType {
	PLAYER_SHOT,
	PLAYER_MELEE,
	PLAYER_HURT,
	PLAYER_DODGE,
	PLAYER_HEAL,
	PLAYER_SHOCKWAVE,
	PLAYER_MELTDOWN,
	ENEMY_HURT,
	ENEMY_ATTACK,
	ENEMY_DIE,
	BOSS_SLAM,
	BOSS_CHARGE,
	BOSS_BURST,
	UI_CLICK,
	UI_PAUSE,
	RELOAD,
	AMMO_EMPTY,
}

@export var sfx_paths: Array[String] = []
@export var bgm_path: String = ""

var _players: Array[AudioStreamPlayer] = []
var _bgm_player: AudioStreamPlayer
var _type_count: int = 0

func _ready():
	_type_count = SfxType.size()
	_setup_players()
	_setup_bgm()
	_connect_events()
	print("[AudioManager] Initialized (%d sfx types)" % _type_count)

func _setup_players():
	for i in range(8):
		var p = AudioStreamPlayer.new()
		p.name = "SFXPlayer%d" % i
		add_child(p)
		_players.append(p)

func _setup_bgm():
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BGMPlayer"
	_bgm_player.volume_db = -12
	add_child(_bgm_player)

func _connect_events():
	EventManager.damage_dealt.connect(_on_damage_dealt)
	EventManager.player_died.connect(_on_player_died)
	EventManager.enemy_died.connect(_on_enemy_died)
	EventManager.skill_used.connect(_on_skill_used)
	EventManager.scene_changed.connect(_on_scene_changed)

func play_sfx(type: int):
	if type < 0 or type >= _type_count:
		return
	var path = sfx_paths[type] if type < sfx_paths.size() else ""
	if path == "":
		return
	if not ResourceLoader.exists(path):
		return
	var player = _get_free_player()
	if not player:
		return
	player.stream = load(path)
	player.play()

func _get_free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return null

func set_master_volume(vol: float):
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(clamp(vol, 0.0, 1.0)))

func play_bgm(path: String = ""):
	var p = path if path != "" else bgm_path
	if p == "" or not ResourceLoader.exists(p):
		return
	_bgm_player.stream = load(p)
	_bgm_player.play()

func stop_bgm():
	_bgm_player.stop()

func _on_damage_dealt(_attacker: Node2D, defender: Node2D, _amount: float, _dmg_type: int):
	if not is_instance_valid(defender):
		return
	if defender.is_in_group("players"):
		play_sfx(SfxType.PLAYER_HURT)
	elif defender.is_in_group("enemies"):
		play_sfx(SfxType.ENEMY_HURT)

func _on_player_died(_player: Node2D):
	play_sfx(SfxType.PLAYER_HURT)

func _on_enemy_died(_enemy: Node2D):
	play_sfx(SfxType.ENEMY_DIE)

func _on_skill_used(skill_data: Dictionary):
	var skill_name_str = skill_data.get("skill_name", "")
	match skill_name_str:
		"治疗": play_sfx(SfxType.PLAYER_HEAL)
		"震波": play_sfx(SfxType.PLAYER_SHOCKWAVE)

func _on_scene_changed(_scene_name: String):
	stop_bgm()
