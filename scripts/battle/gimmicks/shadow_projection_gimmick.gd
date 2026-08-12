extends BossGimmick

const ICON := "🌘"   # 下一房预告横幅的机制图标（battle_hud 经 get_script_constant_map 读取）
const RoomData = preload("res://scripts/battle/room_data.gd")
const P2_INTENTS := [
	preload("res://resources/intents/attack.tres"),
	preload("res://resources/intents/heavy.tres"),
	preload("res://resources/intents/chaos.tres"),
]

# 真·最终 BOSS·勇者的阴影「万象投影」（shadow_projection，2026-08-10 定稿，草案原型 §12 荣格阴影）：
# P1 躯体与焦虑的投影（HP 100%→66%）：每 projection_every 回合随机复刻前 8 个 BOSS 机制之一——
#   gimmick 实例复用（实例化既有 gimmick 脚本调其 on_turn_begin，BossGimmick 统一签名，零复制代码；
#   不调 on_room_start——房级副作用（剥护符/重置 boss_trash）不触发）。
# P2 深渊与创伤的镜像（HP<66% 一次性）：投影池追加 Act3 机制（abyss_erosion 注废/split_ego 人格切换）
#   + 每回合镜像玩家停轮符号（boss_atk_mult ×（1 + base×mirror_base_per））+ 意图 attack 40/heavy 30/chaos 30。
# P3 终极和解（HP<20% 一次性，非暴力）：enemy_hp 锁 1（无法击杀）+ 意图 none（敌人放下武器）——
#   达成任一和解条件即通关（resolve_peaceful_win）：a) 任意三连（on_special_triple）b) 转出 heal 符号
#   （on_turn_resolved 检测 grid）c) 使用 heal/purify/cleanse 消耗品（on_consumable_used 钩子）。
# 组合型新解法规范豁免：真·最终 = 复刻验收（前 11 个 BOSS 全部组合型新解法之和），不新增内容（2026-08-10 拍板）。
# T24 参数化：projection_every/mirror_base_per/phase2_hp_ratio/phase3_hp_ratio 读 gimmick_params。
# 单侧性纪律：只操作本 BOSS 的 enemy_hp/enemy_intent/boss_atk_mult（敌人侧），复刻机制由既有 gimmick 自管。

const PROJECTION_P1 := [
	preload("res://scripts/battle/gimmicks/rust_armor_gimmick.gd"),
	preload("res://scripts/battle/gimmicks/glass_cannon_gimmick.gd"),
	preload("res://scripts/battle/gimmicks/acid_bomb_gimmick.gd"),
	preload("res://scripts/battle/gimmicks/cocoon_cycle_gimmick.gd"),
	preload("res://scripts/battle/gimmicks/whisper_lock_gimmick.gd"),
	preload("res://scripts/battle/gimmicks/bipolar_phase_gimmick.gd"),
	preload("res://scripts/battle/gimmicks/compulsion_rule_gimmick.gd"),
	preload("res://scripts/battle/gimmicks/emotional_vacuum_gimmick.gd"),
]
const PROJECTION_P2 := [
	preload("res://scripts/battle/gimmicks/abyss_erosion_gimmick.gd"),
	preload("res://scripts/battle/gimmicks/split_ego_gimmick.gd"),
]
const PROJECTION_NAMES := [
	"熔铸护甲", "石屑反弹", "酸蚀挂毒", "茧居节律", "呓语锁轮", "躁抑交替", "律法强迫", "情感剥离",
	"深渊侵蚀", "人格裂变",
]

var _projection_every := 2
var _mirror_base_per := 0.05
var _phase2_hp_ratio := 0.66
var _phase3_hp_ratio := 0.2
var _phase2 := false
var _phase3 := false
var _turns := 0
var _projected := false
var _instances: Array = []
var _p2_room_data: RoomData

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.ROOMS[ctrl.room_index].gimmick_params if (ctrl.room_index >= 0 and ctrl.room_index < ctrl.ROOMS.size()) else {}
	_projection_every = maxi(1, int(p.get("projection_every", 2)))
	_mirror_base_per = float(p.get("mirror_base_per", 0.05))
	_phase2_hp_ratio = float(p.get("phase2_hp_ratio", 0.66))
	_phase3_hp_ratio = float(p.get("phase3_hp_ratio", 0.2))
	_phase2 = false
	_phase3 = false
	_turns = 0
	_projected = false
	# 实例化全部投影 gimmick（不调 on_room_start——房级副作用不触发，on_turn_begin 用参数缺省默认值）
	_instances = []
	for s in PROJECTION_P1 + PROJECTION_P2:
		_instances.append(s.new())
	_p2_room_data = RoomData.new()
	_p2_room_data.kind = "boss"
	_p2_room_data.intents = P2_INTENTS
	ctrl.hud._log("🌘 勇者的阴影：万象投影——每 %d 回合复刻 1 个 BOSS 机制（HP<%d%% 深渊镜像，HP<%d%% 终极和解：非暴力通关）" % [_projection_every, int(_phase2_hp_ratio * 100), int(_phase3_hp_ratio * 100)])

func on_turn_begin(ctrl) -> void:
	_turns += 1
	if _phase3:
		# 和解期：敌人放下武器（意图 none，无复刻无镜像）
		ctrl.enemy_intent = {"data": null, "type": "none", "value": 0}
		ctrl.boss_atk_mult = 1.0
		return
	ctrl.boss_atk_mult = 1.0
	_projected = false
	# 投影：随机复刻 1 个既有 gimmick 机制（其 on_turn_begin 自管 boss_atk_mult/意图/boss_trash 等）
	if _turns % _projection_every == 0:
		var idx: int = randi() % _instances.size()
		_projected = true
		ctrl.hud._log("🌘 投影：复刻【%s】机制！" % PROJECTION_NAMES[idx])
		_instances[idx].on_turn_begin(ctrl)
	if _phase2:
		# 镜像：随机抽玩家停轮符号回敬（伤害 ×（1 + base×mirror_base_per））
		var g: Array = ctrl.grid
		if g.size() > 0 and g[0].size() > 0:
			var sym = g[randi() % g.size()][0]
			if sym != null:
				var b: float = sym.base if sym.get("base") != null else 0.0
				if b > 0.0:
					ctrl.boss_atk_mult *= 1.0 + b * _mirror_base_per
					ctrl.hud._log("🌗 深渊镜像：「%s」被回敬——本回合伤害额外 +%d%%" % [sym.name, int(b * _mirror_base_per * 100)])
		# 意图：非复刻回合掷 P2 表（复刻回合由复刻机制决定，如律法覆盖）
		if not _projected:
			ctrl.enemy_intent = ctrl.status_system.roll_intent(_p2_room_data)

func on_turn_resolved(ctrl) -> void:
	if not _phase3:
		return
	# 和解条件 b)：本回合转轮打出治疗（heal）符号
	var g: Array = ctrl.grid
	for reel in g:
		if reel.size() > 0 and reel[0] != null and reel[0].kind == "heal":
			ctrl.resolve_peaceful_win()
			return

func on_special_triple(ctrl) -> void:
	# 和解条件 a)：任意符号三连匹配
	if _phase3:
		ctrl.resolve_peaceful_win()

func on_consumable_used(ctrl, effect: String) -> void:
	# 和解条件 c)：使用恢复/净化类消耗品
	if _phase3 and effect in ["heal", "purify", "cleanse"]:
		ctrl.resolve_peaceful_win()

func on_damaged(ctrl, dmg: int) -> void:
	if not _phase2 and _phase2_hp_ratio > 0.0 and ctrl.enemy_hp <= int(float(ctrl.enemy_hp_max) * _phase2_hp_ratio):
		_phase2 = true
		ctrl.hud._log("🌗 深渊镜像：投影升级——追加 Act3 机制，你的符号将被回敬")
		ctrl.hud._popup("🌗 深渊镜像！", Palette.POP_STATUS, ctrl.hud._enemy_sprite_anchor())
		ctrl.hud._refresh_meta()
		return
	if _phase2 and not _phase3 and _phase3_hp_ratio > 0.0 and ctrl.enemy_hp <= int(float(ctrl.enemy_hp_max) * _phase3_hp_ratio):
		_phase3 = true
		ctrl.enemy_hp = maxi(1, ctrl.enemy_hp)   # 非暴力：HP 锁 1，无法击杀
		ctrl.enemy_intent = {"data": null, "type": "none", "value": 0}
		ctrl.boss_atk_mult = 1.0
		ctrl.hud._log("🌕 勇者放下武器，走向投影——达成和解（任意三连 / 治疗符号 / 恢复净化消耗品）即通关")
		ctrl.hud._popup("🌕 放下武器……", Palette.POP_HEAL, ctrl.hud._enemy_sprite_anchor())
		ctrl.hud._refresh_meta()
		return
	if _phase3:
		ctrl.enemy_hp = maxi(1, ctrl.enemy_hp)   # 非暴力：锁 1 兜底（防 DoT/爆炸等旁路击杀）
