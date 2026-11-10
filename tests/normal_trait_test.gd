extends Node

# ============================================================================
# 扫雷棋盘 Step 4 · 普通怪早期特性样板（2026-11-11）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/normal_trait_test.tscn
#
# 覆盖（Step 4 出口）：
# ① 3–4 只 ACT1 普通怪各挂且只挂 1 个早期特性（normal_trait_gimmick）；
# ② 特性在「入场 / 首次转轮前 / 首次受击」就能看到，早于玩家第一次动作；
# ③ 不加锁血 / 强制复活 / 阶段变化：hp_floor = -1，高爆发仍可直接击杀；
# ④ 每只怪 mechanic_summary 非空（快速击杀也能从确认层 / 右栏读到身份）；
# ⑤ 仅改本房临时状态，不依赖玩家 Build 动态调值。
# ============================================================================

const EXPECTED := {
	"窃语咒师": "jam_open",
	"冰锋群蝠": "frost_open",
	"毒壳壁垒": "shell",
	"辉光游侠": "first_hit_ward",
}

var _checks := 0
var _fails := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var duel: DuelController = await _boot()
	if duel == null:
		print("RESULT FAIL (boot)")
		get_tree().quit(2)
		return

	for monster in EXPECTED:
		var trait_id := String(EXPECTED[monster])
		var r := _room_by_name(duel, monster)
		_check(r != null, "找到 ACT1 普通怪 %s" % monster)
		if r == null:
			continue
		_check(String(r.kind) == "normal" and int(r.act) == 1, "%s 是 ACT1 普通怪" % monster)
		_check(String(r.gimmick_params.get("trait", "")) == trait_id, "%s 只配置 trait=%s" % [monster, trait_id])
		_check(r.gimmick_params.size() <= 2, "%s 没有叠加多机制" % monster)
		_check(String(r.mechanic_summary) != "", "%s 有可见机制摘要" % monster)
		_start_room(duel, r)
		var g = duel.current_gimmick
		_check(g != null, "%s 实例化特性" % monster)
		if g == null:
			continue
		_check(g.get_script().resource_path.get_file() == "normal_trait_gimmick.gd",
			"%s 使用普通特性样板脚本" % monster)
		_check(int(g.hp_floor(duel)) == -1, "%s 无锁血下限" % monster)
		_check(not bool(g.recovery_window(duel)), "%s 不是精英式恢复窗口" % monster)
		match trait_id:
			"shell":
				_check(int(duel.enemy_armor) == 20 and int(duel.enemy_armor_max) == 20,
					"毒壳壁垒入场即有 20 护甲")
				for i in 3:
					g.on_turn_begin(duel)
				_check(int(duel.enemy_armor) == 20, "硬壳不随回合叠加")
			"frost_open":
				_check(int(duel.player_frost) == 1, "冰锋群蝠首回合冻结 1 列（转轮前可见）")
				duel.turn_flow.begin_player_turn()
				_check(int(duel.player_frost) == 0, "冻结次回合自消，不形成永久封锁")
			"jam_open":
				_check(int(duel.pending_jam_reel) == 0, "窃语咒师首次转轮前注废第 1 列")
				duel.pending_jam_reel = -1
				duel.turn_flow.begin_player_turn()
				_check(int(duel.pending_jam_reel) == -1, "注废只触发一次，不逐回合叠加")
			"first_hit_ward":
				_check(int(duel.enemy_armor) == 0, "辉光游侠开局无护甲")
				g.on_damaged(duel, 7)
				_check(int(duel.enemy_armor) == 10, "首次受击后获得 10 护甲")
				g.on_damaged(duel, 7)
				_check(int(duel.enemy_armor) == 10, "护体只触发一次")
				# 快速击杀：无锁血 / 无强制复活，护甲也挡不住高爆发。
				duel.enemy_hp = 5
				duel.combat.apply_enemy_damage(999.0, false)
				duel.apply_enemy_hp_floor()
				_check(int(duel.enemy_hp) <= 0, "高爆发可直接击杀（无锁血 / 复活）")

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	var scene: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.board_config.enabled = false
	duel._confirm_loadout()
	await get_tree().process_frame
	return duel


func _start_room(duel: DuelController, r: RoomData) -> void:
	duel.ROOMS.clear()
	duel.ROOMS.append(r)
	duel.start_room_data(r, 0, 0, false)


func _room_by_name(duel: DuelController, room_name: String) -> RoomData:
	for r in duel.ALL_ROOMS:
		if String(r.name) == room_name:
			return r
	return null


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)
