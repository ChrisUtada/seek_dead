extends BossGimmick

const ICON := "🛡❄"   # 下一房预告横幅的机制图标（battle_hud 经 get_script_constant_map 读取）

# 幕一 BOSS·冰封铁瓮「熔铸护甲」：
# 护甲为扁平池（先破甲后掉血，见 DuelController._apply_enemy_damage）；
# 每 interval 回合叠 1 层护甲（每层 +per_stack，上限 max_stacks 层），叠加在 RoomData.armor 之上。
# 玩家打出 special 三连清空全部护甲（由 DuelController._on_counter("special") 统一处理）。
# 设计意图：教玩家主动追求 special 三连 / 用穿透符号破甲（RPG 式破甲机制）。
# T24 参数化：interval/per_stack/max_stacks/two_cols_chance/first_pressure_turn 读 RoomData.gimmick_params（空则回落默认值，行为不变）——
# Act2/3 复用脚本时在 .tres 调参即可，不再硬编码。

var _interval := 2
var _per_stack := 8
var _max_stacks := 3
var _two_cols_chance := 0.3   # 2026-08-13 用户拍板：冻结随机 1~2 列，2 列概率（1 列更常见）
# Step 4（D1）：精英冻结在护甲被打破时立即解除；BOSS 冻结固定到次回合（默认 false）。
var _freeze_clears_on_break := false
# Step 4（锈铁傀儡）：叠甲/冻结同回合附加腐蚀（护盾收益 -25%，破甲或清净解除）。
var _apply_corrode := false
# Step 3（2026-11-11）：首轮爆发的回合数。默认 = interval（保持旧节奏：第 2/3 回合首次爆发）。
# 样板房可前移到第 2 回合，使 2 回合内的高爆发击杀至少看到一次「蓄势→爆发」；
# 之后仍按 interval 重复，不改变层数、护甲量或任何动态数值。
var _first_pressure_turn := 2

var _stacks := 0
var _turns := 0
var _last_pressure_turn := -1

func on_room_start(ctrl) -> void:
	_stacks = 0
	_turns = 0
	_last_pressure_turn = -1
	var room: RoomData = ctrl.current_room
	var p: Dictionary = room.gimmick_params if room != null else {}
	_interval = int(p.get("interval", 2))
	_per_stack = int(p.get("per_stack", 8))
	_max_stacks = int(p.get("max_stacks", 3))
	_two_cols_chance = float(p.get("two_cols_chance", 0.3))
	_first_pressure_turn = int(p.get("first_pressure_turn", _interval))
	_freeze_clears_on_break = bool(p.get("freeze_clears_on_break", false))
	_apply_corrode = bool(p.get("apply_corrode", false))
	ctrl.hud._log("🛡 熔铸护甲展开：每 %d 回合叠加一层护甲（上限 %d 层）" % [_interval, _max_stacks])
	ctrl.hud._log("🛡 熔铸节律：首轮蓄势 %d 回合 → 爆发（叠甲+冻结）→ 次回合恢复（熔铸间隙），之后每 %d 回合重复" % [_first_pressure_turn - 1, _interval])

func on_turn_begin(ctrl) -> void:
	_turns += 1
	if _turns >= _first_pressure_turn and (_turns - _first_pressure_turn) % _interval == 0 and _stacks < _max_stacks:
		_last_pressure_turn = _turns
		_stacks += 1
		ctrl.enemy_armor_max += _per_stack
		ctrl.enemy_armor += _per_stack
		ctrl.hud._log("⚠ 熔铸爆发：叠甲与冻结；随后一回合进入熔铸间隙（恢复）")
		ctrl.hud._log("🛡 熔铸护甲 +%d（%d/%d 层，护甲 %d/%d）" % [_per_stack, _stacks, _max_stacks, int(ctrl.enemy_armor), int(ctrl.enemy_armor_max)])
		# T30 寒霜侵蚀：与叠甲同频（固定节奏，第 3/6/9 回合；叠甲封顶后 frost 同步停止）
		# 2026-08-09 单侧性纪律：玩家侧冻结上限读 frozen StatusDef.max_cols（frost 已回归纯敌人侧）
		# 2026-08-13 用户拍板：随机冻结 1~2 列（1 列更常见，two_cols_chance），次回合自动解除（frozen decay=1）——
		# 无清净药剂不会死锁；清净药剂 = 当回合立即解除（保住输出），非必修
		var fc_max: int = int(ctrl.status_system.status_def("frozen").max_cols) if ctrl.status_system.status_def("frozen") != null else 2
		var cols := 1
		if fc_max >= 2 and randf() < _two_cols_chance:
			cols = 2
		ctrl.player_frost = cols
		ctrl.hud._log("❄ 寒霜侵蚀：冻结 %d 列（次回合自消，清净药剂可当回合解除）" % cols)
		if _apply_corrode:
			ctrl.apply_debuff("corrode")
			ctrl.hud._log("🧪 锈蚀：护盾收益 -25%（破甲或清净解除）")
	elif recovery_window(ctrl):
		ctrl.hud._log("⚔ 熔铸间隙：本回合不再叠甲/冻结，抓住破甲与输出窗口")
	# 护甲清空由 DuelController._on_counter("special") 统一处理（special 三连），此处不再重复

func recovery_window(_ctrl) -> bool:
	return _last_pressure_turn >= 0 and _turns == _last_pressure_turn + 1


func recovery_title(_ctrl) -> String:
	return "熔铸间隙"


func recovery_detail(_ctrl) -> String:
	return "本回合不新增叠甲/冻结；可争取三连、破甲或集中输出。"


# Step 4（D1）：精英的冻结随破甲立即解除（BOSS 保持到次回合），让「破甲」这条应对同时清掉两种压力。
func on_armor_break(ctrl) -> void:
	if not _freeze_clears_on_break:
		return
	if int(ctrl.player_frost) <= 0:
		return
	ctrl.player_frost = 0
	ctrl.frozen_cols.clear()
	for r in DuelController.REELS:
		ctrl.hud._refresh_cell(r, 0)
	ctrl.hud._log("🛡→❄ 护甲破碎：冻结随甲解除（本回合可正常转动）")


# Step 5：蓄势（下一次叠甲/冻结前的准备回合）→ 爆发（叠甲+冻结当回合）→ 恢复（熔铸间隙）。
# 叠满 max_stacks 后不再加压，返回空串（HUD 不再声明节奏窗口）。
func rhythm_window(_ctrl) -> String:
	if recovery_window(_ctrl):
		return "恢复"
	if _last_pressure_turn >= 0 and _turns == _last_pressure_turn:
		return "爆发"
	if _stacks < _max_stacks:
		return "蓄势"
	return ""
