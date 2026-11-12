extends BossGimmick

# ============================================================================
# 普通怪早期特性模块（扫雷棋盘 Step 4，2026-11-11；Step 2 ACT1 12 只；Step 3 ACT2/ACT3 各 12 只）
# 规格：docs/全怪物个性机制设计与制作计划_2026-11-12.md §4 / §5 / §6、§10 Step 2–3
#
# 设计纪律：
# - 每只普通怪只配置 1 个 trait（gimmick_params.trait），不允许叠加多机制；
# - 触发点固定在「入场」「首次转轮前」「首次受击」「首次破甲」「周期」「HP 阈值」，玩家在动作前可读；
# - 不加锁血 / 强制复活 / 阶段变化 / 固定伤害上限；高爆发仍可 1–2 回合击杀；
# - 只改本房临时状态，不根据玩家 Build 动态调值；所有提示与计时确定性，不消耗 RNG；
# - 周期类统一用 turn_count % N == 0（首回合为 1），ACT2/ACT3 难度来自「不同的问题」而非更高数值。
#
# ACT1（Step 2）
#   shell          入场获得一次性护甲（破甲后不再补充）                 毒壳壁垒
#   frost_open     首回合冻结 1 列（次回合自消，清净可解）                冰锋群蝠
#   jam_open       首次转轮前注废 1 列（仅一次）                          窃语咒师
#   first_hit_ward 首次受击后获得一次性护甲（不挡当次）                   辉光游侠
#   charge         入场蓄力：下一次行动改为重击                           重锤蛮兵
#   break_skip     首次破甲：下一次行动失效                               裂石像
#   rust_jam       首次受击：下一轮注废一列                               锈盲蝠
#   poison_hit     首次受击：玩家中毒 1 层                                腐化史莱姆
#   ember_heal     每回合首次受火伤：回复 6 HP                            余烬傀儡
#   frost_hit      每次受击：自身 +1 层霜                                 寒鳞蝠
#   spore          HP 首次 <50%：玩家中毒 2 层                            毒孢菌
#   lock_open      首次转轮前：锁定一列当前符号                           暗影诡匠
#
# ACT2（Step 3）
#   periodic_heavy   每 3 回合重击                                       暮色蛮兵
#   first_hit_heavy  首次受击：本次行动改为重击                           铁臂蛮兵
#   armor_regen      首次破甲后 2 回合补 8 甲（一次）                      圣壳壁垒
#   break_heavy      首次破甲：本次行动改为重击                           石壳壁垒
#   chaos_open       入场乱权（转轮带注入 20% 废铁，整房）                 毒雾术士
#   blind_open       入场目盲 2 回合                                      暗行游侠
#   double_light     每 3 回合两次 60% 攻击                               炎锋群蝠
#   shift_hit        首次受击：三列符号位序平移一位（内容不变）             迷面诡匠
#   auto_stop_cycle  每 3 回合下轮自动停轮                                迷魂灯笼
#   backlash_triple  玩家首次三连：下回合反噬                             亵渎书吏
#   sacrifice_heavy  每 4 回合自损 4% maxHP 后重击                        暗影信徒
#   echo_half        每 3 回合以 50% 数值重复上一意图                      虚空低语者
#
# ACT3（Step 3）
#   weak_open        入场虚弱 1 回合                                      辉铁蛮兵
#   heavy_pause      每 2 回合重击；破甲后下一次重击延后一轮               深渊蛮兵
#   burn_on_hit      有甲时每回合首次受击：玩家灼烧 +1                    熔壳壁垒
#   armor_periodic   入场 +10 甲，每 4 回合补 10 甲                       黑曜壁垒
#   frost_two_cycle  每 3 回合冻结 2 列                                   霜语术士
#   pierce_heavy     每 3 回合重击 + 25% 伤害穿透护盾                     圣辉游侠
#   double_poison    每 3 回合两次 60% 攻击，各附 1 层毒                   毒针群蝠
#   drain_cycle      每 3 回合吸能 -2                                     深渊诡匠
#   big_heavy_self   每 4 回合 250% 重击，之后自损 3%                      湮灭使徒
#   vulnerable_phase HP 首次 <40%：易伤 2 回合                            坍缩星核
#   entangle_cycle   每 3 回合缠绕 1 回合（方向逐次交替）                  裂界游魂
#   echo_full        每 4 回合完整重复上一意图                             虚空回响
#
# 玩家 DoT（poison_hit / spore / double_poison / burn_on_hit）：
# 本脚本在玩家回合开始结算「每层 poison_base 点、每回合 -1 层」，
# 走 enemy_deal_damage 唯一闸口（护盾可挡、飘字/动画自动），清净药剂可清零。
# ============================================================================

const ICON := "✳"

var _trait := ""
var _params: Dictionary = {}
var _done := false            # 一次性触发（首次受击 / 首次破甲 / 阈值）
var _ember_turn := -1
var _burn_turn := -1
var _poison_base := 2
var _burn_base := 2
var _regen_at := -1           # 圣壳壁垒：护甲补回的计划回合
var _paused := false          # 深渊蛮兵：破甲后暂停一次重击
var _flip := false            # 裂界游魂：缠绕方向交替


func on_room_start(ctrl) -> void:
	_trait = ""
	_done = false
	_params = {}
	_ember_turn = -1
	_burn_turn = -1
	_poison_base = 2
	_burn_base = 2
	_regen_at = -1
	_paused = false
	_flip = false
	var room: RoomData = ctrl.current_room
	if room != null:
		_params = room.gimmick_params
		_trait = String(_params.get("trait", ""))
	_poison_base = _int_param("poison_base", 2)
	_burn_base = _int_param("burn_base", 2)
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
		"charge":
			ctrl.hud._log("🔨 蓄力：下一次行动改为重击，之后恢复普通攻击（入场即可见）")
		"break_skip":
			ctrl.hud._log("🪨 裂壳：首次破甲后下一次行动失效（集中输出窗口）")
		"rust_jam":
			ctrl.hud._log("🦇 锈蚀：首次受击后下一轮注废 1 列（仅一次，净化可解）")
		"poison_hit":
			ctrl.hud._log("🟢 腐蚀黏液：首次受击使你中毒 %d 层（清净可解）" % _int_param("stacks", 1))
		"ember_heal":
			ctrl.hud._log("🔥 余烬：每回合首次受到火系伤害会回复 %d HP（换元素或集中爆发）" % _int_param("heal", 6))
		"frost_hit":
			ctrl.hud._log("❄ 寒鳞：每次受击获得 1 层霜（下一次攻击降低，可连续小攻击削弱）")
		"spore":
			ctrl.hud._log("🍄 毒孢：HP 首次低于 %d%% 时使你中毒 %d 层（爆发收尾或清净）" % [
				int(float(_params.get("hp", 0.5)) * 100.0), _int_param("stacks", 2)])
		"lock_open":
			ctrl.hud._log("🔒 诡计：首次转轮前锁定 1 列当前符号（照常结算，本轮后解除）")
		# —— ACT2 ——
		"periodic_heavy":
			ctrl.hud._log("🪓 暮色重锤：每 3 回合一次重击（提前留盾或抢在重击前击杀）")
		"first_hit_heavy":
			ctrl.hud._log("🛡 铁臂：首次受击后本次行动改为重击（首击前先备盾）")
		"armor_regen":
			ctrl.hud._log("🏛 圣壳：首次破甲后 2 回合补回 %d 护甲（破甲要持续压制）" % _int_param("armor", 8))
		"break_heavy":
			ctrl.hud._log("🗿 石壳：首次破甲后本次行动改为重击（破甲≠安全）")
		"chaos_open":
			ctrl.hud._log("🌫 毒雾：入场乱权，整轮转轮带被注入 20% 废铁（净化无效，靠目押）")
			# build_strips 在 on_room_start 之前已执行一次；此处重排以让乱权立即生效。
			ctrl.pending_chaos = true
			ctrl.reel_system.build_strips()
			ctrl.reel_system.reset_grid()
		"blind_open":
			ctrl.hud._log("🕶 暗行：入场目盲 2 回合，后续预览不可见（看当前格或净化）")
			ctrl.apply_debuff("blind", 2)
		"double_light":
			ctrl.hud._log("🦇 炎锋：每 3 回合改为两次较低攻击（每段约 60%）")
		"shift_hit":
			ctrl.hud._log("🎭 迷面：首次受击后三列符号位序平移一位（内容不变，需重新读格）")
		"auto_stop_cycle":
			ctrl.hud._log("🏮 迷魂：每 3 回合夺轮，下轮转轮自动停止（无法目押）")
		"backlash_triple":
			ctrl.hud._log("📜 亵渎：你首次三连后，下回合反噬（连续同符号受代价）")
		"sacrifice_heavy":
			ctrl.hud._log("🕯 暗影信徒：每 4 回合自损 4% 后重击（可拖过献祭回合）")
		"echo_half":
			ctrl.hud._log("🌀 虚空低语：每 3 回合以 50% 数值重复上一行动")
		# —— ACT3 ——
		"weak_open":
			ctrl.hud._log("💢 辉铁：入场虚弱 1 回合（攻击收益 -20%）")
			ctrl.apply_debuff("weak", 1)
		"heavy_pause":
			ctrl.hud._log("🔨 深渊蛮兵：每 2 回合重击；破甲会让下一次重击延后一轮")
		"burn_on_hit":
			ctrl.hud._log("🔥 熔壳：有护甲时每回合首次受击使你灼烧 +1（先破甲可避免）")
		"armor_periodic":
			var armor2 := _int_param("armor", 10)
			ctrl.enemy_armor_max += armor2
			ctrl.enemy_armor += armor2
			ctrl.hud._log("⬛ 黑曜：入场 +%d 护甲，每 4 回合补 %d 甲（需持续破甲）" % [armor2, armor2])
		"frost_two_cycle":
			ctrl.hud._log("❄ 霜语：每 3 回合冻结 2 列（清净可当回合解除）")
		"pierce_heavy":
			ctrl.hud._log("✨ 圣辉：每 3 回合重击，其中 25% 伤害穿透护盾")
		"double_poison":
			ctrl.hud._log("🧪 毒针：每 3 回合两次较低攻击，各附 1 层毒（清净可解）")
		"drain_cycle":
			ctrl.hud._log("🔋 深渊诡匠：每 3 回合吸能 -2（爆发需提前）")
		"big_heavy_self":
			ctrl.hud._log("💥 湮灭使徒：每 4 回合 250% 重击，之后自损 3%（重击后是窗口）")
		"vulnerable_phase":
			ctrl.hud._log("🩸 坍缩星核：HP 首次低于 40% 时进入易伤 2 回合（爆发窗口）")
		"entangle_cycle":
			ctrl.hud._log("🪢 裂界游魂：每 3 回合缠绕，需按指定方向逐列停止（方向逐次交替）")
		"echo_full":
			ctrl.hud._log("🌀 虚空回响：每 4 回合完整重复上一行动")


func on_turn_begin(ctrl) -> void:
	if _trait == "":
		return
	# 玩家 DoT：每回合开始结算一次（护盾可挡），每回合 -1 层；清净可提前清零。
	if _trait == "poison_hit" or _trait == "spore" or _trait == "double_poison":
		_tick_player_poison(ctrl)
	if _trait == "burn_on_hit":
		_tick_player_burn(ctrl)
	# 圣壳壁垒：计划回合补甲（与时序无关，先处理）
	if _trait == "armor_regen" and _regen_at >= 0 and int(ctrl.turn_count) >= _regen_at:
		_regen_at = -1
		var amt := _int_param("armor", 8)
		ctrl.enemy_armor_max += amt
		ctrl.enemy_armor += amt
		ctrl.hud._log("🏛 圣壳回补：获得 %d 护甲（再次破甲才能重置）" % amt)
	if _done:
		return
	match _trait:
		"frost_open":
			_done = true
			ctrl.player_frost = maxi(int(ctrl.player_frost), 1)
		"jam_open":
			_done = true
			ctrl.pending_jam_reel = clampi(_int_param("column", 0), 0, 2)
		"charge":
			_done = true
			_set_heavy(ctrl, "🔨 蓄力完成：本次行动为重击")
		"lock_open":
			_done = true
			var col := _int_param("column", -1)
			if col < 0:
				col = randi() % DuelController.REELS
			ctrl.pending_lock_reel = clampi(col, 0, DuelController.REELS - 1)
			ctrl.hud._log("🔒 暗影诡匠锁定第 %d 列：本轮固定不转，符号照常结算" % (ctrl.pending_lock_reel + 1))
		# —— ACT2 周期 ——
		"periodic_heavy":
			if _every(ctrl, 3):
				_set_heavy(ctrl, "🪓 暮色重锤：本次行动为重击")
		"double_light":
			if _every(ctrl, 3):
				_set_double(ctrl, 0, 0.6)
		"auto_stop_cycle":
			if _every(ctrl, 3):
				ctrl.pending_auto_stop = true
				ctrl.hud._log("🏮 迷魂夺轮：下轮转轮将自动停止，无法目押")
		"sacrifice_heavy":
			if _every(ctrl, 4):
				var loss := maxi(1, int(round(float(ctrl.enemy_hp_max) * _float_param("self_pct", 0.04))))
				ctrl.enemy_hp = maxi(1, int(ctrl.enemy_hp) - loss)
				ctrl.hud._log("🕯 献祭：自损 %d HP（剩余 %d），本次行动为重击" % [loss, int(ctrl.enemy_hp)])
				_set_heavy(ctrl, "🕯 献祭后的重击")
		"echo_half":
			if _every(ctrl, 3):
				_echo(ctrl, 0.5, "🌀 虚空低语：重复上一行动（50%）")
		# —— ACT3 周期 ——
		"heavy_pause":
			if _every(ctrl, 2):
				if _paused:
					_paused = false
					ctrl.hud._log("🔨 深渊蛮兵：破甲未愈，本次重击延后（本轮普通攻击）")
				else:
					_set_heavy(ctrl, "🔨 深渊蛮兵：本次行动为重击")
		"armor_periodic":
			if _every(ctrl, 4):
				var amt2 := _int_param("armor", 10)
				ctrl.enemy_armor_max += amt2
				ctrl.enemy_armor += amt2
				ctrl.hud._log("⬛ 黑曜回补：获得 %d 护甲（现 %d）" % [amt2, int(ctrl.enemy_armor)])
		"frost_two_cycle":
			if _every(ctrl, 3):
				ctrl.player_frost = maxi(int(ctrl.player_frost), 2)
				ctrl.hud._log("❄ 霜语：冻结 2 列（本轮无法转动冻结列）")
		"pierce_heavy":
			if _every(ctrl, 3):
				_set_heavy(ctrl, "✨ 圣辉重击（25% 穿透护盾）", 0.25)
		"double_poison":
			if _every(ctrl, 3):
				_set_double(ctrl, 1, 0.6)
		"drain_cycle":
			if _every(ctrl, 3):
				ctrl.apply_debuff("drain")
		"big_heavy_self":
			if _every(ctrl, 4):
				_set_heavy(ctrl, "💥 湮灭重击（250%）", 0.0, 2.5)
				ctrl.enemy_self_damage_after = maxi(1, int(round(float(ctrl.enemy_hp_max) * _float_param("self_pct", 0.03))))
		"entangle_cycle":
			if _every(ctrl, 3):
				var dir := "ltr" if not _flip else "rtl"
				_flip = not _flip
				ctrl.apply_debuff("entangle", 1, 1, {"order": dir})
				ctrl.hud._log("🪢 裂界缠绕：本轮需按%s逐列停止" % ("从左到右" if dir == "ltr" else "从右到左"))
		"echo_full":
			if _every(ctrl, 4):
				_echo(ctrl, 1.0, "🌀 虚空回响：完整重复上一行动")


func on_damaged(ctrl, dmg: int) -> void:
	if _trait == "" or dmg <= 0:
		return
	match _trait:
		"first_hit_ward":
			if _done:
				return
			_done = true
			var ward := _int_param("ward", 10)
			if ward > 0:
				ctrl.enemy_armor_max += ward
				ctrl.enemy_armor += ward
				ctrl.hud._log("✨ 辉光护体：获得 %d 护甲（仅一次，之后不再触发）" % ward)
		"rust_jam":
			if _done:
				return
			_done = true
			var col := _int_param("column", -1)
			if col < 0:
				col = randi() % DuelController.REELS
			ctrl.pending_jam_reel = clampi(col, 0, DuelController.REELS - 1)
			ctrl.hud._log("🦇 锈蚀：下一轮第 %d 列被注废（仅一次，净化可解）" % (ctrl.pending_jam_reel + 1))
		"poison_hit":
			if _done:
				return
			_done = true
			var add := maxi(1, _int_param("stacks", 1))
			ctrl.player_status["poison"] = int(ctrl.player_status.get("poison", 0)) + add
			ctrl.hud._log("🟢 腐蚀黏液：你中毒 %d 层（现 %d 层，清净可解）" % [add, int(ctrl.player_status.get("poison", 0))])
		"ember_heal":
			if _ember_turn == int(ctrl.turn_count):
				return
			if not ctrl.turn_damage_elems.has("fire"):
				return
			_ember_turn = int(ctrl.turn_count)
			var heal := _int_param("heal", 6)
			var before: int = int(ctrl.enemy_hp)
			ctrl.enemy_hp = mini(int(ctrl.enemy_hp_max), before + heal)
			var gained: int = int(ctrl.enemy_hp) - before
			if gained > 0:
				ctrl.hud._popup("🔥+%d" % gained, Palette.POP_HEAL, ctrl.hud._enemy_sprite_anchor())
				ctrl.hud._log("🔥 余烬：火系伤害被吸收，回复 %d HP（每回合一次）" % gained)
			else:
				ctrl.hud._log("🔥 余烬：火系伤害被吸收，但已满血（每回合一次）")
		"frost_hit":
			ctrl.enemy_status["frost"] = int(ctrl.enemy_status.get("frost", 0)) + 1
			ctrl.hud._log("❄ 寒鳞：自身获得 1 层霜（现 %d 层，下一次攻击降低）" % int(ctrl.enemy_status["frost"]))
		"spore":
			if _done:
				return
			var pct: float = float(_params.get("hp", 0.5))
			if float(ctrl.enemy_hp) / float(maxi(1, int(ctrl.enemy_hp_max))) > pct:
				return
			_done = true
			var add2 := maxi(1, _int_param("stacks", 2))
			ctrl.player_status["poison"] = int(ctrl.player_status.get("poison", 0)) + add2
			ctrl.hud._log("🍄 毒孢爆裂：你中毒 %d 层（现 %d 层，清净可解）" % [add2, int(ctrl.player_status.get("poison", 0))])
		# —— ACT2 ——
		"first_hit_heavy":
			if _done:
				return
			_done = true
			_set_heavy(ctrl, "🛡 铁臂反击：本次行动改为重击")
		"shift_hit":
			if _done:
				return
			_done = true
			_shift_symbols(ctrl)
		# —— ACT3 ——
		"burn_on_hit":
			if _burn_turn == int(ctrl.turn_count):
				return
			if int(ctrl.enemy_armor) <= 0:
				return
			_burn_turn = int(ctrl.turn_count)
			ctrl.player_status["burn"] = int(ctrl.player_status.get("burn", 0)) + 1
			ctrl.hud._log("🔥 熔壳：你被灼烧 +1 层（现 %d 层；破甲后不再触发）" % int(ctrl.player_status.get("burn", 0)))
		"vulnerable_phase":
			if _done:
				return
			if float(ctrl.enemy_hp) / float(maxi(1, int(ctrl.enemy_hp_max))) > _float_param("hp", 0.4):
				return
			_done = true
			ctrl.apply_debuff("vulnerable", 2)
			ctrl.hud._log("🩸 坍缩：核心进入易伤 2 回合（承伤 +25%，爆发窗口）")


func on_armor_break(ctrl) -> void:
	match _trait:
		"break_skip":
			if _done:
				return
			_done = true
			# 「下一回合不攻击」= 本次玩家结算后的敌人行动失效；清掉意图显示，避免玩家以为还会挨打。
			ctrl.enemy_stunned = maxi(int(ctrl.enemy_stunned), 1)
			ctrl.enemy_intent = {"data": null, "type": "none", "value": 0}
			ctrl.hud._log("🪨 裂石像崩解：下一次行动失效（本次是输出窗口）")
		"armor_regen":
			if _done:
				return
			_done = true
			_regen_at = int(ctrl.turn_count) + maxi(1, _int_param("delay", 2))
			ctrl.hud._log("🏛 圣壳破损：%d 回合后补回 %d 护甲（仅一次）" % [
				maxi(1, _int_param("delay", 2)), _int_param("armor", 8)])
		"break_heavy":
			if _done:
				return
			_done = true
			_set_heavy(ctrl, "🗿 石壳裂开：破甲后本次行动改为重击")
		"heavy_pause":
			_paused = true
			ctrl.hud._log("🔨 深渊蛮兵：护甲被破，下一次重击延后一轮")


func on_special_triple(ctrl) -> void:
	if _trait == "backlash_triple" and not _done:
		_done = true
		ctrl.apply_debuff("backlash", 1)
		ctrl.hud._log("📜 亵渎书吏：下回合反噬生效（连续同符号会受代价）")


# —— 行动改写 ——
func _set_heavy(ctrl, msg: String, pierce := 0.0, mult_override := 0.0) -> void:
	var sd: IntentData = ctrl.status_system.intent_def("heavy")
	var mult: float = mult_override
	if mult <= 0.0:
		mult = sd.value_mult if sd != null else 2.0
	var v: int = int(round(float(ctrl.enemy_atk) * mult))
	ctrl.enemy_intent = {"data": sd, "type": "heavy", "value": v}
	if pierce > 0.0:
		ctrl.enemy_attack_pierce_pct = pierce
	ctrl.hud._log("%s（%d）" % [msg, v])


# 双段攻击：主段 + 追加段，各为 60%（可由 mult 参数覆盖）；poison_per_hit > 0 时两段各附毒。
func _set_double(ctrl, poison_per_hit: int, mult: float) -> void:
	var sd: IntentData = ctrl.status_system.intent_def("attack")
	var v: int = maxi(1, int(round(float(ctrl.enemy_atk) * mult)))
	ctrl.enemy_intent = {"data": sd, "type": "attack", "value": v}
	ctrl.enemy_extra_attacks = [{"value": v, "poison": poison_per_hit}]
	if poison_per_hit > 0:
		ctrl.enemy_attack_poison = poison_per_hit
		ctrl.hud._log("🧪 双段毒针：两次 %d 攻击，各附 %d 层毒" % [v, poison_per_hit])
	else:
		ctrl.hud._log("🦇 双段攻击：两次 %d（合计 %d）" % [v, v * 2])


func _echo(ctrl, scale: float, msg: String) -> void:
	var last: Dictionary = ctrl.last_enemy_intent
	if last.is_empty():
		return
	var t := String(last.get("type", "attack"))
	if t == "none" or t == "":
		return
	var it: Dictionary = last.duplicate(true)
	if t == "attack" or t == "heavy":
		it["value"] = maxi(1, int(round(float(last.get("value", ctrl.enemy_atk)) * scale)))
	ctrl.enemy_intent = it
	ctrl.hud._log("%s（%s %d）" % [msg, t, int(it.get("value", 0))])


func _every(ctrl, n: int) -> bool:
	return int(ctrl.turn_count) % maxi(1, n) == 0


# —— 迷面诡匠：三列符号位序平移一位（内容不变）——
# 同时平移「已停住的当前行」与「后续转轮带」，让玩家必须重新读格而不是背位置。
func _shift_symbols(ctrl) -> void:
	var sym0: Array = []
	var elem0: Array[String] = []
	for r in DuelController.REELS:
		if ctrl.grid.size() > r and ctrl.grid[r].size() > 0:
			sym0.append(ctrl.grid[r][0])
			elem0.append(String(ctrl.grid_elem[r][0]))
	if sym0.size() == 3:
		for r in DuelController.REELS:
			var src := (r + 2) % 3   # 向右平移一位
			ctrl.grid[r][0] = sym0[src]
			ctrl.grid_elem[r][0] = elem0[src]
			ctrl.hud._refresh_cell(r, 0)
	for r in DuelController.REELS:
		var strips: Array = ctrl.reel_system.reel_strips
		if strips.size() <= r or strips[r].size() < 2:
			continue
		var strip: Array = strips[r]
		var first = strip.pop_front()
		strip.push_back(first)
	ctrl.hud._log("🎭 迷面：三列符号位序平移一位（内容不变，下一轮按新位序判读）")


func _tick_player_poison(ctrl) -> void:
	var stacks: int = int(ctrl.player_status.get("poison", 0))
	if stacks <= 0:
		return
	var dmg: int = stacks * maxi(1, _poison_base)
	ctrl.combat.enemy_deal_damage(dmg)   # 唯一闸口：护盾可挡、飘字/受击动画/日志自动
	ctrl.hud._log("☣ 中毒：%d 层造成 %d 伤害（每回合 -1 层，清净可解）" % [stacks, dmg])
	ctrl.player_status["poison"] = maxi(0, stacks - 1)


func _tick_player_burn(ctrl) -> void:
	var stacks: int = int(ctrl.player_status.get("burn", 0))
	if stacks <= 0:
		return
	var dmg: int = stacks * maxi(1, _burn_base)
	ctrl.combat.enemy_deal_damage(dmg)
	ctrl.hud._log("🔥 灼烧：%d 层造成 %d 伤害（每回合 -1 层，清净可解）" % [stacks, dmg])
	ctrl.player_status["burn"] = maxi(0, stacks - 1)


func _int_param(key: String, def: int) -> int:
	return int(_params.get(key, def))


func _float_param(key: String, def: float) -> float:
	return float(_params.get(key, def))
