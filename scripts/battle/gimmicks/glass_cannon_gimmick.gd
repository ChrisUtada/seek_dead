extends BossGimmick

const ICON := "🪨"   # 下一房预告横幅的机制图标（battle_hud 经 get_script_constant_map 读取）

# 幕一 BOSS·碎裂石像鬼「石屑反弹」（glass_cannon 玻璃大炮）：
# 高攻低甲（数值见房间 .tres）；玩家每轮结算后按本轮总伤害反弹石屑（微量自噬伤害）。
# 设计意图（T32 轮替 BOSS 差异化）：护盾同时挡重击与反弹（守备/铁壁双克制）；
# 击杀一击不反弹 = 抢杀奖励（强袭/充能/三连爆发直接兑收益）。
# T24 参数化：reflect_ratio/reflect_cap 读 RoomData.gimmick_params（空则回落默认值，行为不变）。

var _reflect_ratio := 0.15
var _reflect_cap := 5
# Step 5：反弹后下一回合石翼展开，不反弹（真实恢复窗）；本回合是否已反弹用于切换。
var _open := false
var _reflected_this_turn := false

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.ROOMS[ctrl.room_index].gimmick_params if (ctrl.room_index >= 0 and ctrl.room_index < ctrl.ROOMS.size()) else {}
	_reflect_ratio = float(p.get("reflect_ratio", 0.15))
	_reflect_cap = int(p.get("reflect_cap", 5))
	_open = false
	_reflected_this_turn = false
	ctrl.hud._log("🪨 石屑石壳：受击反弹 %d%% 石屑（单次上限 %d），击杀一击无反弹；反弹后次回合石翼展开" % [int(_reflect_ratio * 100.0), _reflect_cap])

func on_turn_begin(ctrl) -> void:
	_open = _reflected_this_turn
	_reflected_this_turn = false
	if _open:
		ctrl.hud._log("🪨 石翼展开：本回合不反弹石屑（输出/恢复窗口）")

func on_damaged(ctrl, dmg: int) -> void:
	if _open:
		return   # Step 5：石翼展开回合不反弹（给玩家一个可计算的输出/恢复窗口）
	if dmg <= 0 or ctrl.enemy_hp <= 0:
		return   # 击杀一击不反弹（抢杀奖励：最后一击直接兑收益）
	_reflected_this_turn = true
	var reflect: int = mini(_reflect_cap, roundi(dmg * _reflect_ratio))
	if reflect <= 0:
		return
	ctrl.combat.enemy_deal_damage(reflect)   # 唯一闸口：护盾可挡、飘字/受击动画/日志自动
	ctrl.hud._log("🪨 石屑反弹 -%d（护盾可挡）" % reflect)

func recovery_window(_ctrl) -> bool:
	return _open


func rhythm_window(_ctrl) -> String:
	return "恢复" if _open else ""


func recovery_title(_ctrl) -> String:
	return "石翼展开"


func recovery_detail(_ctrl) -> String:
	return "本回合不反弹石屑；可放心集中输出、治疗或整理资源。"
