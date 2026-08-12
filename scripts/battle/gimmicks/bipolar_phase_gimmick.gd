extends BossGimmick

const ICON := "🌊"   # 下一房预告横幅的机制图标（battle_hud 经 get_script_constant_map 读取）
# RoomData 直接使用全局类名（room_data.gd 的 class_name），无需 preload 常量（避免 SHADOWED_GLOBAL_IDENTIFIER）

# 幕二 BOSS·躁怒元素使「躁抑交替」（bipolar_phase，2026-08-10 定稿）：
# P1 躁狂发作（HP 100%→50%）：攻击 ×manic_atk_mult + 每回合自扣 max HP 的 manic_self_damage_pct——
#   高攻快节奏、自毁加速（竞速阶段：冰武克制 ×1.5 + 护盾撑 ×2 重击窗口）。
# P2 抑郁僵直（HP<50% 一次性）：属性切 ice（弱 fire，弱点翻转）+ 护甲重设 p2_armor + 攻击 ×depressed_atk_mult
#   + 意图覆盖 attack 50/heavy 20/jam 30（低攻厚甲 + 注废骚扰，jam 可净化）。
# 与低语者（干扰应变）错位：本 BOSS 验收「属性切换 = 弱点切换」——P1 冰武 ×1.5 → P2 冰武同元素 ×0.85，换火武 ×1.5。
# T24 参数化：manic_atk_mult/manic_self_damage_pct/phase2_hp_ratio/depressed_atk_mult/p2_armor 读 gimmick_params。
# 单侧性纪律：只操作本 BOSS 的 enemy_hp/enemy_armor/enemy_element/enemy_intent/boss_atk_mult（敌人侧），无跨侧共享。

var _manic_atk_mult := 2.0
var _manic_self_damage_pct := 0.05
var _phase2_hp_ratio := 0.5
var _depressed_atk_mult := 0.6
var _p2_armor := 45
var _phase2 := false
var _p2_room_data: RoomData

func on_room_start(ctrl) -> void:
	var p: Dictionary = ctrl.ROOMS[ctrl.room_index].gimmick_params if (ctrl.room_index >= 0 and ctrl.room_index < ctrl.ROOMS.size()) else {}
	_manic_atk_mult = float(p.get("manic_atk_mult", 2.0))
	_manic_self_damage_pct = float(p.get("manic_self_damage_pct", 0.05))
	_phase2_hp_ratio = float(p.get("phase2_hp_ratio", 0.5))
	_depressed_atk_mult = float(p.get("depressed_atk_mult", 0.6))
	_p2_armor = int(p.get("p2_armor", 45))
	_phase2 = false
	_p2_room_data = RoomData.new()
	_p2_room_data.kind = "boss"
	# P2 意图剖面 attack 50 / heavy 20 / jam 30（注废可净化）——须内联构建实例设权重：
	# 不能复用共享 intent .tres（weight 均为 1.0 → 33/33/33）且 untyped 数组赋 typed 字段会运行时类型错误
	_p2_room_data.intents = _build_p2_intents()
	ctrl.boss_atk_mult = _manic_atk_mult
	ctrl.hud._log("🌊 躁怒元素使：躁狂发作——攻击 ×%s，每回合自扣 %d%% max HP（HP<%d%% 坠入抑郁：切冰属性 + 厚甲 %d）" % [_manic_atk_mult, int(_manic_self_damage_pct * 100), int(_phase2_hp_ratio * 100), _p2_armor])

func on_turn_begin(ctrl) -> void:
	ctrl.boss_atk_mult = _depressed_atk_mult if _phase2 else _manic_atk_mult
	if _phase2:
		# 抑郁期意图剖面：attack 50 / heavy 20 / jam 30（注废可净化）——覆盖掷取，HUD 意图栏同步
		ctrl.enemy_intent = ctrl.status_system.roll_intent(_p2_room_data)
		return
	var self_dmg := int(ceil(float(ctrl.enemy_hp_max) * _manic_self_damage_pct))
	if self_dmg > 0:
		ctrl.enemy_hp = maxi(1, ctrl.enemy_hp - self_dmg)
		ctrl.hud._log("🌊 躁狂失控：自扣 %d（HP %d/%d）" % [self_dmg, int(ctrl.enemy_hp), int(ctrl.enemy_hp_max)])
		ctrl.hud._refresh_meta()
		_try_enter_phase2(ctrl)

func on_damaged(ctrl, _dmg: int) -> void:
	# _dmg 未使用：阶段切换只依赖 HP 阈值（_try_enter_phase2 读 enemy_hp），不依赖本次伤害量
	_try_enter_phase2(ctrl)

# P2 一次性触发（on_damaged / 自扣跨线均调用，防自毁跨过阈值错过阶段切换）
func _try_enter_phase2(ctrl) -> void:
	if _phase2 or _phase2_hp_ratio <= 0.0:
		return
	if ctrl.enemy_hp <= int(float(ctrl.enemy_hp_max) * _phase2_hp_ratio):
		_phase2 = true
		ctrl.enemy_element = "ice"
		ctrl.hud._update_enemy_element()
		ctrl.enemy_armor_max = _p2_armor
		ctrl.enemy_armor = _p2_armor
		ctrl.boss_atk_mult = _depressed_atk_mult
		ctrl.enemy_intent = ctrl.status_system.roll_intent(_p2_room_data)
		ctrl.hud._log("🌊 情绪坠入深渊：冰封防御展开——属性→冰（弱火），护甲 %d，攻击 ×%s，意图转入抑郁剖面" % [_p2_armor, _depressed_atk_mult])
		ctrl.hud._popup("🌊 冰封防御展开！", Palette.POP_STATUS, ctrl.hud._enemy_sprite_anchor())
		ctrl.hud._refresh_meta()


# P2 意图剖面（attack 50 / heavy 20 / jam 30）：内联构建 IntentData 实例并设权重——
# 不能复用共享 intent .tres（weight 恒 1.0）；返回 typed Array[IntentData] 避免赋值类型错误
func _build_p2_intents() -> Array[IntentData]:
	var att := IntentData.new()
	att.id = "attack"
	att.display_name = "攻击"
	att.icon = "⚔"
	att.weight = 50.0
	att.purifiable = false
	att.value_mult = 1.0
	var hvy := IntentData.new()
	hvy.id = "heavy"
	hvy.display_name = "重击"
	hvy.icon = "💥"
	hvy.weight = 20.0
	hvy.purifiable = false
	hvy.value_mult = 2.0
	var jam := IntentData.new()
	jam.id = "jam"
	jam.display_name = "注废"
	jam.icon = "❌"
	jam.weight = 30.0
	jam.purifiable = true
	jam.value_mult = 0.0
	return [att, hvy, jam]
