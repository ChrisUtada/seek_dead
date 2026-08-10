extends BossGimmick

const ICON := "🐚"   # 下一房预告横幅的机制图标（battle_hud 经 get_script_constant_map 读取）

# 幕一 BOSS·茧居石雕「开合节律」（cocoon_cycle · v2，2026-08-10 定稿）：
# 周期重置甲 = 动态窗口——闭合×3（厚甲 shell_armor + 回血 + jam 注废骚扰）→ 开合×1（甲 0 + 强制重击）。
# 与铁瓮（rust_armor 永久甲，破甲一次投资永久生效）差异化：本 BOSS 甲每回合闭合补满，
# 闭合期破甲只管当回合（下回合回满）——唯一输出窗口 = 开合回合（甲 0），正解 = 节奏管理（攒爆发进窗口）/ 穿透全程直击。
# 意图随相：闭合期走 RoomData.intents（attack 45 / jam 35 / heavy 20，jam 可净化）；开合期 gimmick 强制 heavy（威慑窗口，玩家提前一回合可见）。
# T24 参数化：cycle_period/shell_armor/open_armor/heal_per_turn/open_heavy_mult 读 gimmick_params。
# 单侧性纪律：只操作本 BOSS 的 enemy_armor/enemy_hp/enemy_intent（敌人侧），无跨侧共享。

var _cycle_period := 4
var _shell_armor := 45
var _open_armor := 0
var _heal_per_turn := 6
var _open_heavy_mult := 2.0
var _turns := 0

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.ROOMS[ctrl.room_index].gimmick_params if (ctrl.room_index >= 0 and ctrl.room_index < ctrl.ROOMS.size()) else {}
	_cycle_period = maxi(2, int(p.get("cycle_period", 4)))
	_shell_armor = int(p.get("shell_armor", 45))
	_open_armor = int(p.get("open_armor", 0))
	_heal_per_turn = int(p.get("heal_per_turn", 6))
	_open_heavy_mult = float(p.get("open_heavy_mult", 2.0))
	_turns = 0
	# 进房即闭合：厚甲补满
	ctrl.enemy_armor_max = _shell_armor
	ctrl.enemy_armor = _shell_armor
	ctrl.hud._log("🐚 茧壳闭合：厚甲 %d 展开，每 %d 回合探头一次（开合期护甲归零）" % [_shell_armor, _cycle_period])

func on_turn_begin(ctrl) -> void:
	_turns += 1
	var is_open: bool = (_turns % _cycle_period) == 0
	if is_open:
		# 开合：甲归零 + 不回血 + 强制重击（威慑窗口）——意图覆盖可读，玩家提前一回合可见
		ctrl.enemy_armor_max = _open_armor
		ctrl.enemy_armor = _open_armor
		var hv: int = int(round(ctrl.enemy_atk * _open_heavy_mult))
		ctrl.enemy_intent = {"data": null, "type": "heavy", "value": hv}
		ctrl.hud._log("🐚 茧壳裂开！护甲归零，探头重击 %d（脆弱窗口！）" % hv)
		ctrl.hud._refresh_meta()
		return
	# 闭合：甲每回合补满（周期重置甲——闭合期破甲只管当回合）+ 休养回血
	ctrl.enemy_armor_max = _shell_armor
	ctrl.enemy_armor = _shell_armor
	if _heal_per_turn > 0 and ctrl.enemy_hp > 0 and ctrl.enemy_hp < ctrl.enemy_hp_max:
		ctrl.enemy_hp = mini(ctrl.enemy_hp + _heal_per_turn, ctrl.enemy_hp_max)
		ctrl.hud._log("🐚 茧壳内休养 +%d（HP %d/%d）" % [_heal_per_turn, int(ctrl.enemy_hp), int(ctrl.enemy_hp_max)])
