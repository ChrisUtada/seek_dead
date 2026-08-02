extends BossGimmick

# 幕三 BOSS·深渊监视者「深渊侵蚀」：
# 每回合向转轮带注入废铁（在 _build_strips 经 ctrl.boss_trash 落实），
# 注入量 = 当前符号池大小比例，且敌人 HP 越低注入越快。
# 设计意图：直接强化「稀释刹车」，与「进池类无天花板」形成对抗——带越多武器，侵蚀越狠。

const BASE_RATIO := 0.10       # 满血时每回合注入量占当前池比例
const LOW_HP_BONUS := 0.30     # 残血时额外追加比例
const MAX_TRASH := 24          # boss_trash 累计上限（每列废铁格数，防失控）

func on_room_start(ctrl) -> void:
	ctrl.boss_trash = 0
	ctrl.hud._log("🕳 深渊侵蚀：每回合向转轮注入废铁，池越大/血越低注入越多")

func on_turn_begin(ctrl) -> void:
	var pool_size = ctrl.pool.size()
	var hp_ratio = float(ctrl.enemy_hp) / float(ctrl.enemy_hp_max)
	var ratio = BASE_RATIO + (1.0 - hp_ratio) * LOW_HP_BONUS
	var add = int(round(pool_size * ratio))
	ctrl.boss_trash = min(MAX_TRASH, ctrl.boss_trash + add)
	if add > 0:
		ctrl.hud._log("🕳 深渊侵蚀 +%d 废铁（池 %d，HP %d%%）" % [add, pool_size, int(hp_ratio * 100)])
