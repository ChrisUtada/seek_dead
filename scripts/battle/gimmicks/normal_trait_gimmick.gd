extends BossGimmick

# ============================================================================
# 普通怪早期特性样板（扫雷棋盘 Step 4，2026-11-11）
# 规格：docs/扫雷装备探索_棋盘重设计与执行计划_2026-11-10.md §7.1、§12 Step 4
#
# 设计纪律：
# - 每只普通怪只配置 1 个 trait（gimmick_params.trait），不允许叠加多机制；
# - 触发点固定在「入场」「首次转轮前」「首次受击」，玩家在动作发生前就能读到；
# - 不加锁血 / 强制复活 / 阶段变化 / 固定伤害上限；高爆发仍可 1–2 回合击杀；
# - 只改本房临时状态（护甲 / 冻结列 / 注废列），不根据玩家 Build 动态调值。
#
# 支持的 trait：
#   shell          入场获得一次性护甲（破甲后不再补充）
#   frost_open     首回合冻结 1 列（次回合自消，清净药剂可当回合解除）
#   jam_open       首次转轮前注废 1 列（仅一次）
#   first_hit_ward 首次受击后获得一次性护甲（不抵挡当次伤害，只影响后续）
# ============================================================================

const ICON := "✳"

var _trait := ""
var _params: Dictionary = {}
var _done := false


func on_room_start(ctrl) -> void:
	_trait = ""
	_done = false
	_params = {}
	var room: RoomData = ctrl.current_room
	if room != null:
		_params = room.gimmick_params
		_trait = String(_params.get("trait", ""))
	match _trait:
		"shell":
			var armor := _int_param("armor", 20)
			if armor > 0:
				ctrl.enemy_armor_max += armor
				ctrl.enemy_armor += armor
				ctrl.hud._log("🐚 硬壳：入场即拥有 %d 护甲（破甲后不再补充）" % armor)
		"frost_open":
			ctrl.hud._log("❄ 寒意先至：首回合冻结 1 列（次回合自消，清净药剂可当回合解除）")
		"jam_open":
			ctrl.hud._log("🗣 窃语：首次转轮前第 %d 列将被注废（仅一次）" % (_int_param("column", 0) + 1))
		"first_hit_ward":
			ctrl.hud._log("✨ 辉光护体：首次受击后获得 %d 护甲（仅一次）" % _int_param("ward", 10))


func on_turn_begin(ctrl) -> void:
	if _done or _trait == "":
		return
	match _trait:
		"frost_open":
			_done = true
			ctrl.player_frost = maxi(int(ctrl.player_frost), 1)
		"jam_open":
			_done = true
			ctrl.pending_jam_reel = clampi(_int_param("column", 0), 0, 2)


func on_damaged(ctrl, dmg: int) -> void:
	if _done or _trait != "first_hit_ward" or dmg <= 0:
		return
	_done = true
	var ward := _int_param("ward", 10)
	if ward > 0:
		ctrl.enemy_armor_max += ward
		ctrl.enemy_armor += ward
		ctrl.hud._log("✨ 辉光护体：获得 %d 护甲（仅一次，之后不再触发）" % ward)


func _int_param(key: String, def: int) -> int:
	return int(_params.get(key, def))
