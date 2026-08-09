extends BossGimmick

const ICON := "🛡❄"   # 下一房预告横幅的机制图标（battle_hud 经 get_script_constant_map 读取）

# 幕一 BOSS·锈蚀傀儡「熔铸护甲」：
# 护甲为扁平池（先破甲后掉血，见 DuelController._apply_enemy_damage）；
# 每 interval 回合叠 1 层护甲（每层 +per_stack，上限 max_stacks 层），叠加在 RoomData.armor 之上。
# 玩家打出 special 三连清空全部护甲（由 DuelController._on_counter("special") 统一处理）。
# 设计意图：教玩家主动追求 special 三连 / 用穿透符号破甲（RPG 式破甲机制）。
# T24 参数化：interval/per_stack/max_stacks 读 RoomData.gimmick_params（空则回落默认值，行为不变）——
# Act2/3 复用脚本时在 .tres 调参即可，不再硬编码。

var _interval := 2
var _per_stack := 8
var _max_stacks := 3

var _stacks := 0
var _turns := 0

func on_room_start(ctrl) -> void:
	_stacks = 0
	_turns = 0
	var p: Dictionary = ctrl.ROOMS[ctrl.room_index].gimmick_params if (ctrl.room_index >= 0 and ctrl.room_index < ctrl.ROOMS.size()) else {}
	_interval = int(p.get("interval", 2))
	_per_stack = int(p.get("per_stack", 8))
	_max_stacks = int(p.get("max_stacks", 3))
	ctrl.hud._log("🛡 熔铸护甲展开：每 %d 回合叠加一层护甲（上限 %d 层）" % [_interval, _max_stacks])

func on_turn_begin(ctrl) -> void:
	_turns += 1
	if _turns % _interval == 0 and _stacks < _max_stacks:
		_stacks += 1
		ctrl.enemy_armor_max += _per_stack
		ctrl.enemy_armor += _per_stack
		ctrl.hud._log("🛡 熔铸护甲 +%d（%d/%d 层，护甲 %d/%d）" % [_per_stack, _stacks, _max_stacks, int(ctrl.enemy_armor), int(ctrl.enemy_armor_max)])
		# T30 寒霜侵蚀：与叠甲同频挂 frost（固定节奏，第 3/6/9 回合；叠甲封顶后 frost 同步停止）
		# 2026-08-09 单侧性纪律：玩家侧冻结上限读 frozen StatusDef.max_cols（frost 已回归纯敌人侧）
		var fc_max: int = int(ctrl.status_system.status_def("frozen").max_cols) if ctrl.status_system.status_def("frozen") != null else 2
		ctrl.player_frost = min(ctrl.player_frost + 1, fc_max)
		ctrl.hud._log("❄ 寒霜侵蚀：frost +1（%d/%d 层，冻结转轮效果见后续实现）" % [ctrl.player_frost, fc_max])
	# 护甲清空由 DuelController._on_counter("special") 统一处理（special 三连），此处不再重复
