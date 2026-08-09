extends BossGimmick

const ICON := "🐚"   # 下一房预告横幅的机制图标（battle_hud 经 get_script_constant_map 读取）

# 幕一 BOSS·茧居石雕「封闭壁垒」（shield_heal）：
# 叠厚盾 + 自我治疗 + 注废（jam 意图，走意图表）三线拖时间——破甲流高压验收关。
# 回合结构：on_turn_begin 先回血再叠盾（每 shield_interval 回合 +shield_amount，叠加量上限 shield_max，不含基础甲）。
# 护甲为扁平池（先破甲后掉血）：破甲武器三连清空 / 穿透直击 / 破甲符 是打开直击窗口的手段（与 rust_armor 同模式）。
# T24 参数化：shield_interval/shield_amount/shield_max/heal_per_turn 读 RoomData.gimmick_params（空则回落默认值）。
# 设计意图：净输出必须压过「回血 6/回合 + 等效盾 5/回合 ≈ 11/回合」，磨血流被拖死，逼爆发/穿透。

var _shield_interval := 3
var _shield_amount := 15
var _shield_max := 45
var _heal_per_turn := 6
var _turns := 0
var _stacked := 0   # gimmick 已叠加的盾量（不含基础甲）

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.ROOMS[ctrl.room_index].gimmick_params if (ctrl.room_index >= 0 and ctrl.room_index < ctrl.ROOMS.size()) else {}
	_shield_interval = int(p.get("shield_interval", 3))
	_shield_amount = int(p.get("shield_amount", 15))
	_shield_max = int(p.get("shield_max", 45))
	_heal_per_turn = int(p.get("heal_per_turn", 6))
	_turns = 0
	_stacked = 0
	ctrl.hud._log("🐚 封闭壁垒展开：每 %d 回合叠 %d 盾（叠加上限 %d），每回合自我治疗 %d" % [_shield_interval, _shield_amount, _shield_max, _heal_per_turn])

func on_turn_begin(ctrl) -> void:
	_turns += 1
	# 自我治疗（存活才回）
	if _heal_per_turn > 0 and ctrl.enemy_hp > 0 and ctrl.enemy_hp < ctrl.enemy_hp_max:
		ctrl.enemy_hp = mini(ctrl.enemy_hp + _heal_per_turn, ctrl.enemy_hp_max)
		ctrl.hud._log("🐚 自我治疗 +%d（HP %d/%d）" % [_heal_per_turn, int(ctrl.enemy_hp), int(ctrl.enemy_hp_max)])
	# 封闭壁垒：每 interval 回合叠盾（叠加量上限 shield_max；破甲后补满增量）
	if _turns % _shield_interval == 0 and _stacked < _shield_max:
		var add: int = mini(_shield_amount, _shield_max - _stacked)
		ctrl.enemy_armor_max += add
		ctrl.enemy_armor += add
		_stacked += add
		ctrl.hud._log("🐚 封闭壁垒 +%d 盾（叠加 %d/%d，护甲 %d/%d）" % [add, _stacked, _shield_max, int(ctrl.enemy_armor), int(ctrl.enemy_armor_max)])
