extends BossGimmick

const ICON := "☣"   # 下一房预告横幅的机制图标（battle_hud 经 get_script_constant_map 读取）

# 毒系挂毒（status_bomb 酸蚀毒性）：
# 低攻平压 + 玩家侧 DoT 叠层磨血 + 层数爆炸（玩家 DoT 状态存 ctrl.player_status，本房清零）。
# 回合结构：on_turn_begin 先结算旧毒（毒伤 + 爆炸判定）再挂新层——爆炸在「层数达标的下一个玩家回合」触发。
# 清净药剂可清零毒层（2026-08-09 职责拆分：净化=敌人意图、清净=玩家自身状态）；蚀毒壁垒护符（charm_dot_reduce）每回合减挂毒量。
# T24 参数化：dot_per_turn/dot_base/bomb_stacks/bomb_dmg 读 RoomData.gimmick_params（空则回落默认值）。
# Step 4 扩展（全部默认关闭，BOSS 酸蚀恶鬼行为不变）：
#   pause_after_bomb_turns  爆炸后停止挂毒 N 回合（BOSS 1；毒疫术士按 D2 用 2）
#   self_damage_every/pct   每 N 回合自损 pct 换额外毒层（邪颂祭司每 4 回合 5%）
#   self_poison_stacks      自损回合额外挂毒层数
#   strip_every             每 N 回合剥一个玩家增益（腐殖巨蠕每 4 回合），触发后下一回合停止挂毒
# 设计意图：毒层 = 时间压力（不衰减、越拖越痛），爆炸 = 硬性节奏闸门；速杀（少回合）或清净（主动解）二选一。

var _dot_per_turn := 2
var _dot_base := 1
var _bomb_stacks := 10
var _bomb_dmg := 30
var _pause_after_bomb_turns := 1
var _self_damage_every := 0
var _self_damage_pct := 0.0
var _self_poison_stacks := 0
var _strip_every := 0
var _turns := 0
var _pause_left := 0
var _window := ""   # Step 5：本回合节奏窗口（恢复 = 毒囊暴露/停毒回合）

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.ROOMS[ctrl.room_index].gimmick_params if (ctrl.room_index >= 0 and ctrl.room_index < ctrl.ROOMS.size()) else {}
	_dot_per_turn = int(p.get("dot_per_turn", 2))
	_dot_base = int(p.get("dot_base", 1))
	_bomb_stacks = int(p.get("bomb_stacks", 10))
	_bomb_dmg = int(p.get("bomb_dmg", 30))
	_pause_after_bomb_turns = int(p.get("pause_after_bomb_turns", 1))
	_self_damage_every = int(p.get("self_damage_every", 0))
	_self_damage_pct = float(p.get("self_damage_pct", 0.0))
	_self_poison_stacks = int(p.get("self_poison_stacks", 0))
	_strip_every = int(p.get("strip_every", 0))
	_turns = 0
	_pause_left = 0
	_window = ""
	ctrl.player_dot_bomb_stacks = _bomb_stacks   # HUD 毒层警示阈值（state 镜像）
	ctrl.hud._log("☣ 酸蚀恶臭：每回合挂毒 %d 层（层数不衰减，≥%d 层爆炸 -%d！清净药剂可解）" % [_dot_per_turn, _bomb_stacks, _bomb_dmg])
	if _strip_every > 0:
		ctrl.hud._log("🪓 寄主收缩：每 %d 回合剥走一个增益，随后一回合停止挂毒" % _strip_every)
	if _self_damage_every > 0:
		ctrl.hud._log("🕯 献祭：每 %d 回合自损 %d%% HP 换取额外毒层（可逼自损）" % [
			_self_damage_every, int(round(_self_damage_pct * 100.0))])

func on_turn_begin(ctrl) -> void:
	_turns += 1
	_window = ""
	# 先结算旧毒（毒伤 + 爆炸判定），再挂新层
	var stacks: int = int(ctrl.player_status.get("poison", 0))
	var bombed := false
	if stacks > 0:
		var dot_dmg: int = stacks * _dot_base
		ctrl.combat.enemy_deal_damage(dot_dmg)   # 唯一闸口：护盾可挡、飘字/受击动画/日志自动
		ctrl.hud._log("☣ 酸蚀侵蚀：%d 层毒伤 -%d（护盾可挡）" % [stacks, dot_dmg])
		if stacks >= _bomb_stacks:
			ctrl.player_status["poison"] = 0
			ctrl.combat.enemy_deal_damage(_bomb_dmg)
			ctrl.hud._log("☣ 毒层爆炸！-%d 伤害，层数清零" % _bomb_dmg)
			bombed = true
	# 剥增益（腐殖巨蠕）：触发后下一回合停止挂毒
	var stripped := false
	if _strip_every > 0 and _turns % _strip_every == 0:
		ctrl.apply_debuff("strip")
		stripped = true
	# 自损换毒（邪颂祭司）
	var bonus := 0
	if _self_damage_every > 0 and _turns % _self_damage_every == 0:
		var loss: int = maxi(1, int(round(float(ctrl.enemy_hp_max) * _self_damage_pct)))
		ctrl.enemy_hp = maxi(1, int(ctrl.enemy_hp) - loss)
		bonus = maxi(0, _self_poison_stacks)
		ctrl.hud._popup("🕯 -%d" % loss, Palette.POP_DAMAGE, ctrl.hud._enemy_sprite_anchor())
		ctrl.hud._log("🕯 献祭：自损 %d HP，额外挂毒 %d 层" % [loss, bonus])
	# 爆炸 / 剥增益后的恢复窗：爆炸当回合不挂毒，随后 N 个回合继续停止挂毒
	if bombed and _pause_after_bomb_turns > 0:
		_pause_left = maxi(_pause_left, _pause_after_bomb_turns)
	if stripped:
		_pause_left = maxi(_pause_left, 1)
	if _pause_left > 0:
		if not bombed and not stripped:
			_pause_left -= 1
		_window = "恢复"
		ctrl.hud._log("☣ 毒囊暴露：本回合停止挂毒（%d 层照常结算，清净可解）" % int(ctrl.player_status.get("poison", 0)))
		return
	var add: int = maxi(0, _dot_per_turn - int(ctrl.charm_dot_reduce))   # 蚀毒壁垒护符：挂毒量 -N/回合
	add += bonus
	stacks = int(ctrl.player_status.get("poison", 0)) + add
	ctrl.player_status["poison"] = stacks
	ctrl.hud._log("☣ 酸蚀恶鬼：玩家中毒 +%d 层（%d 层）" % [add, stacks])


func recovery_window(_ctrl) -> bool:
	return _window == "恢复"


func rhythm_window(_ctrl) -> String:
	return _window


func recovery_title(_ctrl) -> String:
	return "毒囊暴露"


func recovery_detail(_ctrl) -> String:
	return "本回合不再挂毒；已有毒层照常结算，可清净、治疗或趁机爆发。"
