extends BossGimmick

# 幕一 BOSS·碎裂石像鬼「石屑反弹」（glass_cannon 玻璃大炮）：
# 高攻低甲（数值见房间 .tres）；玩家每轮结算后按本轮总伤害反弹石屑（微量自噬伤害）。
# 设计意图（T32 轮替 BOSS 差异化）：护盾同时挡重击与反弹（守备/铁壁双克制）；
# 击杀一击不反弹 = 抢杀奖励（强袭/充能/三连爆发直接兑收益）。
# T24 参数化：reflect_ratio/reflect_cap 读 RoomData.gimmick_params（空则回落默认值，行为不变）。

var _reflect_ratio := 0.15
var _reflect_cap := 5

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.ROOMS[ctrl.room_index].gimmick_params if (ctrl.room_index >= 0 and ctrl.room_index < ctrl.ROOMS.size()) else {}
	_reflect_ratio = float(p.get("reflect_ratio", 0.15))
	_reflect_cap = int(p.get("reflect_cap", 5))
	ctrl.hud._log("🪨 石屑石壳：受击反弹 %d%% 石屑（单次上限 %d），击杀一击无反弹" % [int(_reflect_ratio * 100.0), _reflect_cap])

func on_damaged(ctrl, dmg: int) -> void:
	if dmg <= 0 or ctrl.enemy_hp <= 0:
		return   # 击杀一击不反弹（抢杀奖励：最后一击直接兑收益）
	var reflect: int = mini(_reflect_cap, roundi(dmg * _reflect_ratio))
	if reflect <= 0:
		return
	ctrl.combat.enemy_deal_damage(reflect)   # 唯一闸口：护盾可挡、飘字/受击动画/日志自动
	ctrl.hud._log("🪨 石屑反弹 -%d（护盾可挡）" % reflect)
