# 说明：不注册 class_name，用 preload 常量引用，避免 headless 首次加载的全局类缓存问题
# （与项目里 demo_config / debuff_system 等同类处理方式一致）。
extends RefCounted

# N-03（2026-11-21）：双方攻击前血量预览的只读账本。
#
# 设计铁律：本对象只记录「结算层在真实扣血的同一处顺带算出的分解值」。
# UI 与测试只读、绝不反向驱动任何数值——这是「预览值 = 最终结算」的唯一保证。
# 结算数值仍然只在 combat_system.apply_enemy_damage / enemy_deal_damage、
# enemy_system._do_attack 的穿透旁路三处变更，本账本不新增任何 HP 扣减。
#
# 幽灵值：命中前 HUD 显示 *_ghost_*，命中帧才切到真实值。幽灵值取自 *_before，
# 也不是重算出来的——它就是扣血前的真实快照。

var turn_index: int = 0

# —— 玩家侧（敌人 → 玩家），多段攻击在本回合聚合 ——
var player_hp_before: int = 0            # 第一段攻击前玩家真实 HP
var player_raw_attack: int = 0           # 敌方原始攻击（闸口乘区后的 eff，多段累加）
var player_shield_blocked: int = 0       # 护盾格挡（多段累加）
var player_hp_loss: int = 0              # 实际 HP 损失（多段累加）
var player_pierce_bypass: int = 0        # 穿透护盾直扣 HP（圣辉游侠旁路，多段累加）
var player_segment_count: int = 0        # 敌人攻击段数（主攻击 + 追加攻击）
var player_ghost_hp: int = -1            # 玩家幽灵 HP（命中前显示；-1 = 不显示，跟随真实值）

# —— 敌人侧（玩家 → 敌人）——
var enemy_hp_before: int = 0             # 玩家出手前敌人真实 HP
var enemy_armor_before: int = 0
var enemy_armor_loss: int = 0            # 护甲损失（非穿透吃掉的 + 整段清甲）
var enemy_hp_loss: int = 0               # HP 损失（非穿透溢出部分，不含穿透）
var enemy_pierce_damage: int = 0         # 穿透伤害（直击 HP，不吃护甲）
var enemy_ghost_hp: int = -1             # 敌人幽灵 HP
var enemy_ghost_armor: int = -1          # 敌人幽灵护甲

# 玩家侧是否已有攻击账本（有值才显示预览）
func has_player_attack() -> bool:
	return player_segment_count > 0

# 敌人侧是否已有攻击账本（本回合玩家是否打出伤害或破甲）
func has_enemy_attack() -> bool:
	return enemy_armor_loss > 0 or enemy_hp_loss > 0 or enemy_pierce_damage > 0

# 敌人总 HP 损失（非穿透 + 穿透），用于「合计 -N」聚合飘字
func enemy_total_hp_loss() -> int:
	return enemy_hp_loss + enemy_pierce_damage

# 玩家总 HP 损失（护盾后 + 穿透旁路），用于「合计 -N」聚合飘字
func player_total_hp_loss() -> int:
	return player_hp_loss + player_pierce_bypass

# 逐段累计玩家侧一段攻击（闸口 eff/blocked/dealt 已经是乘区后结果，这里只求和）。
# hp_before 只在第一段记录，保证幽灵值 = 出手前真实 HP。
func add_player_segment(hp_before_hit: int, eff: int, blocked: int, dealt: int) -> void:
	if player_segment_count == 0:
		player_hp_before = hp_before_hit
	player_segment_count += 1
	player_raw_attack += eff
	player_shield_blocked += blocked
	player_hp_loss += dealt

# 记录一次穿透护盾旁路直扣 HP（enemy_system._do_attack 的圣辉游侠 pierce_pct）。
# 该路径绕过 enemy_deal_damage，故单独累加；同样只在第一段记 hp_before。
func add_player_pierce(hp_before_hit: int, pierce: int) -> void:
	if player_segment_count == 0:
		player_hp_before = hp_before_hit
	player_segment_count += 1
	player_pierce_bypass += pierce

# 新回合/新房间重置全部账本
func reset(turn: int) -> void:
	turn_index = turn
	player_hp_before = 0
	player_raw_attack = 0
	player_shield_blocked = 0
	player_hp_loss = 0
	player_pierce_bypass = 0
	player_segment_count = 0
	player_ghost_hp = -1
	enemy_hp_before = 0
	enemy_armor_before = 0
	enemy_armor_loss = 0
	enemy_hp_loss = 0
	enemy_pierce_damage = 0
	enemy_ghost_hp = -1
	enemy_ghost_armor = -1
