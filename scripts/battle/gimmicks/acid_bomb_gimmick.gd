extends BossGimmick

const ICON := "☣"   # 下一房预告横幅的机制图标（battle_hud 经 get_script_constant_map 读取）

# 幕一 BOSS·酸蚀恶鬼「酸蚀挂毒」（status_bomb 酸蚀毒性）：
# 低攻平压 + 玩家侧 DoT 叠层磨血 + 层数爆炸（玩家 DoT 状态存 ctrl.player_status，本房清零）。
# 回合结构：on_turn_begin 先结算旧毒（毒伤 + 爆炸判定）再挂新层——爆炸在「层数达标的下一个玩家回合」触发。
# 清净药剂可清零毒层（2026-08-09 职责拆分：净化=敌人意图、清净=玩家自身状态）；蚀毒壁垒护符（charm_dot_reduce）每回合减挂毒量。
# T24 参数化：dot_per_turn/dot_base/bomb_stacks/bomb_dmg 读 RoomData.gimmick_params（空则回落默认值）。
# 设计意图：毒层 = 时间压力（不衰减、越拖越痛），爆炸 = 硬性节奏闸门；速杀（少回合）或清净（主动解）二选一。

var _dot_per_turn := 2
var _dot_base := 1
var _bomb_stacks := 10
var _bomb_dmg := 30

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.ROOMS[ctrl.room_index].gimmick_params if (ctrl.room_index >= 0 and ctrl.room_index < ctrl.ROOMS.size()) else {}
	_dot_per_turn = int(p.get("dot_per_turn", 2))
	_dot_base = int(p.get("dot_base", 1))
	_bomb_stacks = int(p.get("bomb_stacks", 10))
	_bomb_dmg = int(p.get("bomb_dmg", 30))
	ctrl.player_dot_bomb_stacks = _bomb_stacks   # HUD 毒层警示阈值（state 镜像）
	ctrl.hud._log("☣ 酸蚀恶臭：每回合挂毒 %d 层（层数不衰减，≥%d 层爆炸 -%d！清净药剂可解）" % [_dot_per_turn, _bomb_stacks, _bomb_dmg])

func on_turn_begin(ctrl) -> void:
	# 先结算旧毒（毒伤 + 爆炸判定），再挂新层
	var stacks: int = int(ctrl.player_status.get("poison", 0))
	if stacks > 0:
		var dot_dmg: int = stacks * _dot_base
		ctrl.combat.enemy_deal_damage(dot_dmg)   # 唯一闸口：护盾可挡、飘字/受击动画/日志自动
		ctrl.hud._log("☣ 酸蚀侵蚀：%d 层毒伤 -%d（护盾可挡）" % [stacks, dot_dmg])
		if stacks >= _bomb_stacks:
			ctrl.player_status["poison"] = 0
			ctrl.combat.enemy_deal_damage(_bomb_dmg)
			ctrl.hud._log("☣ 毒层爆炸！-%d 伤害，层数清零" % _bomb_dmg)
	var add: int = maxi(0, _dot_per_turn - int(ctrl.charm_dot_reduce))   # 蚀毒壁垒护符：挂毒量 -N/回合
	stacks = int(ctrl.player_status.get("poison", 0)) + add
	ctrl.player_status["poison"] = stacks
	ctrl.hud._log("☣ 酸蚀恶鬼：玩家中毒 +%d 层（%d 层）" % [add, stacks])
