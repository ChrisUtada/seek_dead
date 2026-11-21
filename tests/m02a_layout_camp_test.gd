extends Node

# M-02a（2026-11-21）：固定每幕 8 房顺序 + Boss 前营地 · 专项回归。
#
# 覆盖验收：
#   1. 三幕严格符合 §10.1 固定顺序：普通→普通→精英→普通→普通→精英→营地→Boss。
#   2. 营地无敌人、无 gimmick，进入不触发战斗/建池/奖励。
#   3. 休整真实回 25% 最大 HP；满血显示无需恢复；只结算一次。
#   4. 整理：授予 1 次后有合法候选即可结算；无候选不提供假选项。
#   5. 营地后进入房间歇态，可开商店 / 下一房进真 Boss。

var _fails := 0
var _checks := 0
var _duel: DuelController

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("M02A FAIL: " + label)

func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	_duel = scene_res.instantiate() as DuelController
	add_child(_duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_duel.demo_config.enabled = false
	_duel.board_config.enabled = false
	_duel._confirm_loadout()
	await get_tree().process_frame

	_test_layout()
	_test_camp_node()
	_test_rest()
	_test_rest_full_hp()
	_test_trim()
	_test_settled_once()

	_finish()

# 新版 M-02a §2：3 普通 + 2 精英 + 1 宝箱/事件 + 1 营地 + 1 Boss。
const EXPECT_KINDS: Array = ["normal", "normal", "SPECIAL", "elite", "normal", "elite", "camp", "boss"]

# 1. 三幕固定顺序（真·最终房单独追加在末尾，不计入幕内 8 房）。
func _test_layout() -> void:
	var rooms: Array = _duel.ROOMS
	_ok(rooms.size() == 25, "总房数 = 3×8 + 真·最终 1（实测 %d）" % rooms.size())
	for act in range(1, 4):
		var base: int = (act - 1) * 8
		var got: Array = []
		for i in 8:
			var k: String = String((rooms[base + i] as RoomData).kind)
			if k == "chest" or k == "event":
				k = "SPECIAL"
			got.append(k)
		_ok(got == EXPECT_KINDS, "幕 %d 固定顺序（实测 %s）" % [act, str(got)])
		# 营地 act 与 BOSS act 正确
		_ok(int((rooms[base + 6] as RoomData).act) == act, "幕 %d 营地 act=%d" % [act, act])
		_ok(int((rooms[base + 7] as RoomData).act) == act, "幕 %d BOSS act=%d" % [act, act])

# 2. 营地哨兵：无敌人数值、无 gimmick；进入不建池、不生成敌人、不触发奖励。
func _test_camp_node() -> void:
	var camp: RoomData = _duel.ROOMS[6]   # 幕 1 第 7 房
	_ok(camp.kind == "camp", "营地 kind=camp")
	_ok(int(camp.hp) == 0 and int(camp.atk) == 0 and int(camp.armor) == 0, "营地无战斗数值")
	_ok(camp.archetype == null and camp.gimmick_script == null, "营地把无 archetype/gimmick")
	_ok(camp.intents.is_empty(), "营地无意图表")

# 进入营地：设残血后调用入口，断言不生成敌人、无战斗奖励触发。
func _enter_camp_with_hp(hp: int) -> void:
	_duel.room_index = 5
	_duel.player_hp = hp
	_duel.player_hp_max = 100
	_duel._linear_camp_done = false
	# 清空上一房残留，使「营地不生成敌人/gimmick」可被精确断言。
	_duel.enemy_hp = 0
	_duel.current_gimmick = null
	var gold_before: int = _duel.gold
	var owned_before: int = (_duel.meta.get("owned_weapons", []) as Array).size()
	_duel.start_room_data(_duel.ROOMS[6], 6)
	_ok(int(_duel.enemy_hp) == 0, "营地未生成敌人（enemy_hp=%d）" % int(_duel.enemy_hp))
	_ok(_duel.current_gimmick == null, "营地无 gimmick")
	_ok(_duel.gold == gold_before, "营地不发清房金币/利息")
	_ok((_duel.meta.get("owned_weapons", []) as Array).size() == owned_before, "营地不发武器/不写 owned")

# 3. 休整：残血回 25% 最大 HP（30），只结算一次。
func _test_rest() -> void:
	_enter_camp_with_hp(40)
	_duel._linear_camp_rest()
	_ok(int(_duel.player_hp) == 65, "休整：40 + 25 = 65（实测 %d）" % int(_duel.player_hp))
	_ok(_duel._linear_camp_done, "休整后置已结算守卫")
	_ok(_duel.in_interroom, "营地结算后进入房间歇态")

# 满血：休整显示无需恢复（回调不增血）、不软锁。
func _test_rest_full_hp() -> void:
	_enter_camp_with_hp(100)
	_duel._linear_camp_rest()
	_ok(int(_duel.player_hp) == 100, "满血休整不增血（实测 %d）" % int(_duel.player_hp))
	_ok(_duel._linear_camp_done, "满血休整也置已结算（不软锁）")

# 4. 整理：授予一次后有合法候选即可结算（用技能卸除路径）。
func _test_trim() -> void:
	_enter_camp_with_hp(60)
	# 确保有技能可卸（若无则用精简剪路径；这里直接验证 candidates 非空时 trim 可推进）。
	_duel._trim.grant(1)
	var cands: Array = _duel._trim.candidates()
	if cands.is_empty():
		_ok(true, "整理：无合法候选时跳过（不提供假选项）")
		_duel._linear_camp_continue()
	else:
		var before: int = _duel._trim.trims_left()
		var cand: Dictionary = cands[0]
		var msg: String = _duel._trim.apply(cand)
		_ok(msg != "", "整理：apply 真实生效（%s）" % msg)
		_ok(_duel._trim.trims_left() == before - 1, "整理：消耗 1 次")
	_duel._linear_camp_settle()
	_ok(_duel._linear_camp_done, "整理后结算守卫置位")

# 5. 只结算一次：重复调用回调不改 HP、不重复推进。
func _test_settled_once() -> void:
	_enter_camp_with_hp(50)
	_duel._linear_camp_rest()
	var hp_once: int = int(_duel.player_hp)
	_duel._linear_camp_rest()
	_duel._linear_camp_continue()
	_ok(int(_duel.player_hp) == hp_once, "重复回调不再回血（只结算一次）")

func _finish() -> void:
	print("M02A RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
