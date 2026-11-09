extends Node

# ============================================================================
# G7-A S5 · 三幕 bot 基线采集（2026-11-08）
#
# 目的：在同一套协议下跑「单幕」与「三幕」，按幕出尺寸化对照：
#   每战回合 / 承伤 / 格挡 / 停中率 / 每房 TTK / 金币收支 / 商店·营地购买次数。
#
# 协议（写进报告，便于复现）：
#   - headless --fixed-fps 60；真实平衡：不改 BALANCE、不改任何 .tres 数值；
#   - 假人生命 99999：只测「每战承伤/回合」，不测存活与战败率（那是真人项）；
#   - bot 停轮策略固定（每列转起来就按停），同一种子可复现；
#   - 商店按价格升序最多买 2 件；营地买 1 件非武器补给（营地不买武器，避免替换弹层）；
#   - BOSS 战利品优先「信物/铁砧」，只有武器候选时跳过（同上）；
#   - 每组 4 个种子；三幕组按幕切分统计。
#
# 运行（必须隔离 APPDATA，会写 meta）：
#   set APPDATA=%TEMP%\seek_dead_probe_appdata
#   Godot_v4.7-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tools/g7_s5_baseline.tscn
# 产物：docs/baseline/2026-11-08_run3_baseline/report.txt + data.json
#       -- --out=res://docs/baseline/<新目录> 可改输出目录（复测时避免覆盖基线）。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-08_run3_baseline"
const GROWTH := preload("res://scripts/systems/growth_system.gd")
const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const BASE_SEED := 5150
const RUNS := 4                       # 可用 --runs=N 覆盖；--seed=S 覆盖起始种子（单点复核用）
const DUMMY_HP := 99999

var _duel: DuelController
var _lines: Array[String] = []
var _rows: Array[Dictionary] = []      # 每条 = 一局的一幕（单幕局只有一条）
var _bt: Dictionary = {}               # 当前战斗起点快照（用于逐战拆分）
var _runs := RUNS                      # 可用命令行覆盖：-- --runs=1（快速自检）
var _seed0 := BASE_SEED                # -- --seed=5151：只复核某颗种子
var _out_dir: String = OUT_DIR         # -- --out=res://docs/baseline/<新目录>：复测不覆盖基线
var _no_boon := false                  # -- --no-boon：关掉幕间锻魂，做同代码 A/B
var _base_loadout: Array[String] = []
var _base_skills: Array[String] = []
var _base_charms: Array[String] = []
var _base_consumables: Array[String] = []
var _base_meta: Dictionary = {}


func _ready() -> void:
	await _run()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--runs="):
			_runs = maxi(1, int(String(a).get_slice("=", 1)))
		elif String(a).begins_with("--seed="):
			_seed0 = int(String(a).get_slice("=", 1))
		elif String(a).begins_with("--out="):
			_out_dir = String(a).get_slice("=", 1)
		elif String(a) == "--no-boon":
			_no_boon = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	_duel = load(DUEL_SCENE).instantiate() as DuelController
	add_child(_duel)
	await _frames(8)
	_duel.board_config.enabled = true
	_duel.board_config.act = 1
	_duel.board_config.acts = 1
	_duel.board_config.shape_id = ""
	_duel.board_config.special_id = ""
	_duel.board_config.template_id = ""
	if _no_boon:
		_duel.growth.boon_enabled = false
	_duel._confirm_loadout()
	await _frames(8)
	_base_loadout = _duel.selected_loadout.duplicate()
	_base_skills = _duel.selected_skills.duplicate()
	_base_charms = _duel.selected_charms.duplicate()
	_base_consumables = _duel.selected_consumables.duplicate()
	_base_meta = _duel.meta.duplicate(true)

	for cfg in [{"label": "single", "acts": 1}, {"label": "run3", "acts": 3}]:
		for i in range(_runs):
			await _play_run(String(cfg["label"]), int(cfg["acts"]), _seed0 + i)

	_write_report()
	print("G7_S5_BASELINE|DONE rows=%d" % _rows.size())
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# 一局：按幕收集
# ---------------------------------------------------------------------------

func _play_run(label: String, acts: int, s: int) -> void:
	_reset_fixture(acts)
	seed(s)
	_duel._loadout_system.full_reset()
	_duel.player_hp_max = DUMMY_HP
	_duel.player_hp = DUMMY_HP
	_duel.game_state = DuelController.FlowState.PLAYING

	var accs: Array[Dictionary] = []
	accs.append(_snap_start())
	var act_before: int = int(_duel.board.act)
	var result := ""
	var guard := 0

	while guard < 20000:
		guard += 1
		if _duel.game_state == DuelController.FlowState.LOST:
			result = "LOST"
			break
		if _duel.game_state == DuelController.FlowState.WON:
			_finish_battle(accs[-1])
			if _duel.reward_is_boss:
				_take_boss_reward()
			elif _duel.room_flow.post_battle_active and _duel.room_flow.post_battle_has_growth():
				_duel.room_flow.auto_pick_post_battle(["growth"])
			else:
				_duel._on_reward_skip_pressed()
			await get_tree().process_frame
			if _duel.board.act != act_before:
				accs[-1] = _snap_end(accs[-1])
				act_before = int(_duel.board.act)
				accs.append(_snap_start())
			if _duel.hud.meta_screen.visible:
				result = "CLEAR"
				break
			continue
		if _duel.hud.board_screen.visible:
			var b = _duel.board
			if b.dice == 0:
				b.roll_dice()
			var legal: Array = b.legal_targets()
			if legal.is_empty():
				result = "NO_LEGAL"
				break
			var pick: Dictionary = legal[randi() % legal.size()]
			var node: Dictionary = b.advance_to(String(pick["id"]))
			if node.is_empty():
				result = "ADVANCE_FAIL"
				break
			var t := String(node.get("type", ""))
			_duel._on_board_node_entered(node)
			if t in ["normal", "elite", "boss"] and not _duel.hud.board_screen.visible:
				accs[-1]["battles"] += 1
				_begin_battle(t)
			await get_tree().process_frame
			if _duel.hud.shop_screen_is_open():
				_buy_shop(accs[-1])
				_duel._on_shop_leave_pressed()
			elif _duel.hud._camp_dialog != null and _duel.hud._camp_dialog.visible:
				_buy_camp(accs[-1])
				# 买到东西时 _camp_buy 自己已经收摊（再看一眼，避免重复「未购买」日志）。
				if _duel.hud._camp_dialog != null and _duel.hud._camp_dialog.visible:
					_duel._camp_leave()
			if _duel.hud._replace_dialog != null and _duel.hud._replace_dialog.visible:
				_duel.hud._on_replace_cancelled()
			continue
		if _duel.game_state != DuelController.FlowState.PLAYING:
			continue
		var turn := await _play_one_turn()
		if turn != "OK":
			result = turn
			break

	accs[-1] = _snap_end(accs[-1])
	for a in accs:
		a["label"] = label
		a["acts"] = acts
		a["seed"] = s
		a["run_result"] = result
		_rows.append(a)
	_duel.hud.hide_meta_screen()
	_duel.game_state = DuelController.FlowState.PLAYING
	_duel.hud.hide_board_screen(false)


# 刷新之间把「局外」状态复位：每局从同一套整备与 meta 起步（购买不会污染下一局）。
func _reset_fixture(acts: int) -> void:
	_duel.selected_loadout.assign(_base_loadout.duplicate())
	_duel.selected_skills.assign(_base_skills.duplicate())
	_duel.selected_charms.assign(_base_charms.duplicate())
	_duel.selected_consumables.assign(_base_consumables.duplicate())
	_duel.consumable_slots.clear()
	_duel.meta.clear()
	for k in _base_meta:
		var v = _base_meta[k]
		# 嵌套的 owned_* 是数组：必须深拷贝，否则本局的购买会写回基线快照。
		_duel.meta[k] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	_duel.board_config.acts = acts


# ---------------------------------------------------------------------------
# 采样：一幕的起点 / 终点
# ---------------------------------------------------------------------------

func _snap_start() -> Dictionary:
	var b = _duel.board
	return {
		"act": int(b.act) if b != null else 1,
		"shape": String(b.shape_id) if b != null else "",
		"battles": 0,
		"turns0": _duel._telemetry.turns,
		"dmg0": _duel._telemetry.damage_taken,
		"blocked0": _duel._telemetry.damage_blocked,
		"atk0": _duel._telemetry.enemy_attacks,
		"stop0": _duel._telemetry.stop_total,
		"hit0": _duel._telemetry.target_hits,
		"spins0": _duel._telemetry.spins,
		"spinsec0": _duel._telemetry.spin_seconds,
		"rooms0": _duel._telemetry.room_times.size(),
		"ttk0": _ttk_sum(),
		"gold0": int(_duel.gold),
		"shop_buys": 0,
		"shop_spend": 0,
		"shop_slot_block": 0,
		"shop_gold_block": 0,
		"camp_buys": 0,
		"camp_spend": 0,
		"hp0": int(_duel.player_hp),
		"battles_detail": [],
	}


# 逐战拆分：记录本场用了多少回合、吃多少伤、敌人底子（用于解释 ACT II/III 的陡增）。
func _begin_battle(node_type: String) -> void:
	var t = _duel._telemetry
	_bt = {
		"act": int(_duel.board.act), "type": node_type,
		"room": String(_duel.enemy_name), "gimmick": _gimmick_name(),
		"enemy_hp": int(_duel.enemy_hp_max), "enemy_atk": int(_duel.enemy_atk),
		"turns0": t.turns, "dmg0": t.damage_taken, "hits0": t.target_hits, "stops0": t.stop_total,
	}


# 本战挂的机制脚本名（无机制 = ""）；用于统计 ACT2/ACT3 的 gimmick 实际使用覆盖。
func _gimmick_name() -> String:
	if _duel.current_gimmick == null:
		return ""
	var s: Script = _duel.current_gimmick.get_script()
	if s == null:
		return ""
	return s.resource_path.get_file().get_basename().replace("_gimmick", "")


func _finish_battle(acc: Dictionary) -> void:
	if _bt.is_empty():
		return
	var t = _duel._telemetry
	var turns: int = t.turns - int(_bt["turns0"])
	var hits: int = t.target_hits - int(_bt["hits0"])
	var stops: int = t.stop_total - int(_bt["stops0"])
	acc["battles_detail"].append({
		"act": int(_bt["act"]), "type": String(_bt["type"]), "room": String(_bt["room"]),
		"gimmick": String(_bt.get("gimmick", "")),
		"enemy_hp": int(_bt["enemy_hp"]), "enemy_atk": int(_bt["enemy_atk"]),
		"turns": turns, "dmg": t.damage_taken - int(_bt["dmg0"]),
		"hit_rate": (float(hits) / float(stops)) if stops > 0 else 0.0,
	})
	_bt = {}


func _snap_end(s: Dictionary) -> Dictionary:
	var t = _duel._telemetry
	var rooms: int = t.room_times.size() - int(s["rooms0"])
	var ttk: float = _ttk_sum() - float(s["ttk0"])
	var shop_spend := int(s["shop_spend"])
	var camp_spend := int(s["camp_spend"])
	var gold_end := int(_duel.gold)
	s["turns"] = t.turns - int(s["turns0"])
	s["dmg"] = t.damage_taken - int(s["dmg0"])
	s["blocked"] = t.damage_blocked - int(s["blocked0"])
	s["atk"] = t.enemy_attacks - int(s["atk0"])
	s["stops"] = t.stop_total - int(s["stop0"])
	s["hits"] = t.target_hits - int(s["hit0"])
	s["spins"] = t.spins - int(s["spins0"])
	s["spin_sec"] = t.spin_seconds - float(s["spinsec0"])
	s["rooms"] = rooms
	s["ttk_sec"] = ttk
	s["gold_start"] = int(s["gold0"])
	s["gold_end"] = gold_end
	s["gold_spend"] = shop_spend + camp_spend
	s["gold_income"] = gold_end - int(s["gold0"]) + shop_spend + camp_spend
	s["gold_net"] = gold_end - int(s["gold0"])
	s["hp_end"] = int(_duel.player_hp)
	s["boss"] = String(_duel.board.summary().get("boss", "")) if _duel.board != null else ""
	return s


func _ttk_sum() -> float:
	var t := 0.0
	for v in _duel._telemetry.room_times:
		t += float(v)
	return t


# ---------------------------------------------------------------------------
# 采购（每处 1 件最便宜的、买得起的）
# ---------------------------------------------------------------------------

func _buy_shop(acc: Dictionary) -> void:
	# 按价格升序尝试，最多买 2 件（真人一店的量级）；买不起即停。
	var offers: Array = _duel._shop_system.shop_offers.duplicate()
	offers.sort_custom(func(a, b): return int(a.get("price", 0)) < int(b.get("price", 0)))
	var bought := 0
	for o in offers:
		if bought >= 2:
			break
		if bool(o.get("sold", false)):
			continue
		# 记下「买不了」的原因：钱不够 / 槽位饱和。区分「不想买」与「买不了」。
		var kind := String(o.get("kind", ""))
		if _slot_blocked(kind, String(o.get("path", ""))):
			acc["shop_slot_block"] += 1
			continue
		if int(o.get("price", 0)) > int(_duel.gold):
			acc["shop_gold_block"] += 1
			break
		var before := int(_duel.gold)
		_duel._shop_system.on_shop_buy_pressed(o)
		var spent := before - int(_duel.gold)
		if spent > 0:
			bought += 1
			acc["shop_buys"] += 1
			acc["shop_spend"] += spent


# 与 ShopSystem.on_shop_buy_pressed 的拦截条件一致（只判断「买了会不会被拒」）。
func _slot_blocked(kind: String, path: String) -> bool:
	if kind == "active":
		return _duel.consumable_slots.size() >= _duel.CONSUMABLE_CAP
	var arr: Array = _duel._loadout_system.sel_arr(kind)
	if arr.has(path):
		return true
	if arr.size() >= _duel._loadout_system.cat_max(kind) and not _duel._loadout_system.can_grow_slot(kind):
		return true
	return false


# BOSS 战利品：优先拿信物/铁砧（不弹替换层），只有武器时跳过。
# 与真人相比仍偏保守（真人多半会换武器），但避免了弹层死循环。
func _take_boss_reward() -> void:
	for c in _duel.reward_choices:
		var k := String(c.get("kind", ""))
		if k == "boss_relic" or k == "boss_anvil":
			_duel._on_boss_reward_chosen(c)
			return
	_duel._on_reward_skip_pressed()


func _buy_camp(acc: Dictionary) -> void:
	var best: Dictionary = {}
	for o in _duel._camp_offers:
		if String(o.get("kind", "")) == "weapon":
			continue   # 武器满槽会弹替换层；基线不测换武器
		if bool(o.get("sold", false)):
			continue
		if int(o.get("price", 0)) > int(_duel.gold):
			continue
		if best.is_empty() or int(o["price"]) < int(best["price"]):
			best = o
	if best.is_empty():
		return
	var before := int(_duel.gold)
	_duel._camp_buy(best)
	var spent := before - int(_duel.gold)
	if spent > 0:
		acc["camp_buys"] += 1
		acc["camp_spend"] += spent


func _play_one_turn() -> String:
	_duel._on_spin_pressed()
	var waited := 0
	while waited < 900:
		if _duel.reel_system.spinning:
			_duel._on_spin_button_pressed()
		elif not _duel._busy:
			return "OK"
		waited += 1
		await get_tree().process_frame
	return "TURN_TIMEOUT"


# ---------------------------------------------------------------------------
# 报告
# ---------------------------------------------------------------------------

func _write_report() -> void:
	_lines.append("# G7-A S5 三幕 bot 基线 %s" % Time.get_datetime_string_from_system())
	_lines.append("")
	_lines.append("协议：headless --fixed-fps 60 · 真实平衡（未改 BALANCE / .tres）· 假人生命 %d（不测存活）·" % DUMMY_HP)
	_lines.append("      bot 每列转起即按停（同种子可复现）· 商店最多买 2 件、营地 1 件非武器 · BOSS 战利品优先信物/铁砧 · 每组 %d 局" % _runs)
	_lines.append("种子：%d..%d；三幕组按幕切分。" % [_seed0, _seed0 + _runs - 1])
	_lines.append("")

	_lines.append("## 1. 单局明细")
	_lines.append("")
	_lines.append("| 组 | 种子 | 幕 | 骨架 | 战斗 | 回合/战 | 承伤/战 | 格挡/战 | 停中率 | 回合 | TTK/房(秒) | 金币 收/支/余 | 商店买 | 营地买 | 结局 |")
	_lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for r in _rows:
		_lines.append("| %s | %d | %s | %s | %d | %.1f | %.1f | %.1f | %.0f%% | %d | %.1f | %d/%d/%d | %d | %d | %s |" % [
			_group_label(r), int(r["seed"]), _act_label(r), String(r["shape"]), int(r["battles"]),
			_per(r["turns"], r["battles"]), _per(r["dmg"], r["battles"]), _per(r["blocked"], r["battles"]),
			_rate(r["hits"], r["stops"]) * 100.0, int(r["turns"]), _per(r["ttk_sec"], r["rooms"]),
			int(r["gold_income"]), int(r["gold_spend"]), int(r["gold_end"]),
			int(r["shop_buys"]), int(r["camp_buys"]), String(r["run_result"])])
	_lines.append("")

	_lines.append("## 2. 分组均值")
	_lines.append("")
	_lines.append("| 指标 | 单幕 ACT I | 三幕 ACT I | 三幕 ACT II | 三幕 ACT III |")
	_lines.append("|---|---|---|---|---|")
	var cols := [_agg("single", 1), _agg("run3", 1), _agg("run3", 2), _agg("run3", 3)]
	var metrics := [
		["局数", "runs", "int"], ["战斗/局", "battles", "f1"], ["回合/局", "turns", "f1"],
		["回合/战", "turns_per", "f1"], ["承伤/战", "dmg_per", "f1"], ["格挡/战", "blocked_per", "f1"],
		["停中率", "hit_rate", "pct"], ["TTK/房(秒)", "ttk_per", "f2"], ["金币收入/局", "income", "f1"],
		["金币支出/局", "spend", "f1"], ["金币结余/局", "net", "f1"], ["商店购买/局", "shop", "f2"],
		["商店·槽满受阻/局", "shop_slot_block", "f2"], ["商店·钱少受阻/局", "shop_gold_block", "f2"],
		["营地购买/局", "camp", "f2"],
	]
	for m in metrics:
		var cells: Array[String] = []
		for c in cols:
			var v: float = float(c.get(String(m[1]), 0.0))
			match String(m[2]):
				"int": cells.append("%d" % int(v))
				"pct": cells.append("%.0f%%" % (v * 100.0))
				"f2": cells.append("%.2f" % v)
				_: cells.append("%.1f" % v)
		_lines.append("| %s | %s |" % [String(m[0]), " | ".join(cells)])
	_lines.append("")

	_lines.append("## 3. 逐战拆分（敌方底子，按幕汇总）")
	_lines.append("")
	_lines.append("| 组/幕 | 战数 | 敌人HP 均/最大 | 敌人ATK 均/最大 | 回合/战 | 玩家输出/回合* | 最贵的一战（房间 · 回合 · 承伤 · 敌HP） |")
	_lines.append("|---|---|---|---|---|---|---|")
	for spec in [["single", 1, "单幕 ACT I"], ["run3", 1, "三幕 ACT I"], ["run3", 2, "三幕 ACT II"], ["run3", 3, "三幕 ACT III"]]:
		var b := _battle_agg(String(spec[0]), int(spec[1]))
		if int(b["n"]) == 0:
			_lines.append("| %s | 0 | - | - | - | - | - |" % String(spec[2]))
			continue
		_lines.append("| %s | %d | %.0f / %d | %.1f / %d | %.1f | %.0f | %s · %d 回合 · %d 承伤 · HP %d |" % [
			String(spec[2]), int(b["n"]), float(b["hp_sum"]) / float(b["n"]), int(b["hp_max"]),
			float(b["atk_sum"]) / float(b["n"]), int(b["atk_max"]), float(b["turns_sum"]) / float(b["n"]),
			_output_per_turn(b), String(b["worst_room"]), int(b["worst_turns"]), int(b["worst_dmg"]), int(b["worst_hp"])])
	_lines.append("")
	_lines.append("注 *：玩家输出/回合 = Σ敌人HP ÷ Σ回合（含护甲与溢出伤害，只是量级近似，用来对照「敌方 HP 涨了多少、玩家输出涨了多少」）。")
	_lines.append("    逐战数据按「进入战斗节点 → 胜利」的遥测差值切分，不含奖励/商店；")
	_lines.append("    「最贵的一战」按承伤排序，通常就是该幕 BOSS。")
	_lines.append("")

	_lines.append("## 4. G7-A 待办：ACT2/ACT3 gimmick 实际使用覆盖")
	_lines.append("")
	for act in [2, 3]:
		var g := _gimmick_tally(act)
		_lines.append("- ACT %s：%s" % ["II" if act == 2 else "III", "、".join(g) if not g.is_empty() else "（本次种子未碰到带机制的房）"])
	_lines.append("")
	_lines.append("统计口径：bot 逐战记录 `current_gimmick` 的脚本名（含普通/精英/BOSS 房），括号内为本次开打次数。")
	_lines.append("")
	_lines.append("## 5. 与 ACT I 的偏离（三幕自身第一幕为基准）")
	_lines.append("")
	_lines.append("| 指标 | ACT II vs ACT I | ACT III vs ACT I |")
	_lines.append("|---|---|---|")
	var base: Dictionary = cols[1]
	for m in metrics:
		var key := String(m[1])
		if not ["turns_per", "dmg_per", "blocked_per", "ttk_per", "income", "shop"].has(key):
			continue
		var b: float = float(base.get(key, 0.0))
		var c2: float = float(cols[2].get(key, 0.0))
		var c3: float = float(cols[3].get(key, 0.0))
		_lines.append("| %s | %s | %s |" % [String(m[0]), _delta(c2, b), _delta(c3, b)])
	_lines.append("")
	_lines.append("注：TTK 是 headless 帧时间（每房墙钟秒），只可在同一探针内横向比较，不能与真人 TTK 绝对值对照；")
	_lines.append("    节奏口径以「回合/战」为主。停中率为 bot 固定停轮策略下的读数，不代表真人目押水平。")
	_lines.append("    承伤/战的假人生命为 %d，不会战败；存活与战败率由作者真人局提供。" % DUMMY_HP)

	var f := FileAccess.open("%s/report.txt" % _out_dir, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	var j := FileAccess.open("%s/data.json" % _out_dir, FileAccess.WRITE)
	if j != null:
		j.store_string(JSON.stringify({"protocol": {"acts": [1, 3], "runs": _runs, "seed": _seed0,
			"dummy_hp": DUMMY_HP, "boon_enabled": not _no_boon,
			"act_boon_power": GROWTH.ACT_BOON_POWER, "act_boon_hp": GROWTH.ACT_BOON_HP},
			"rows": _rows}, "\t"))
		j.close()


func _group_label(r: Dictionary) -> String:
	return "单幕" if String(r["label"]) == "single" else "三幕"


func _act_label(r: Dictionary) -> String:
	return Palette.act_name(int(r["act"]))


func _per(a, b) -> float:
	return float(a) / float(b) if int(b) > 0 else 0.0


func _rate(a, b) -> float:
	return float(a) / float(b) if int(b) > 0 else 0.0


func _agg(label: String, act: int) -> Dictionary:
	var out := {}
	var n := 0
	for r in _rows:
		if String(r["label"]) != label or int(r["act"]) != act:
			continue
		n += 1
		for k in ["battles", "turns", "dmg", "blocked", "atk", "stops", "hits", "rooms", "ttk_sec",
				"gold_income", "gold_spend", "gold_net", "shop_buys", "shop_slot_block",
				"shop_gold_block", "camp_buys"]:
			out[k] = float(out.get(k, 0.0)) + float(r[k])
	if n == 0:
		return out
	for k in out:
		out[k] = float(out[k]) / float(n)
	out["runs"] = n
	out["turns_per"] = _per(out["turns"], out["battles"])
	out["dmg_per"] = _per(out["dmg"], out["battles"])
	out["blocked_per"] = _per(out["blocked"], out["battles"])
	out["ttk_per"] = _per(out["ttk_sec"], out["rooms"])
	out["hit_rate"] = _rate(out["hits"], out["stops"])
	out["shop"] = out["shop_buys"]
	out["camp"] = out["camp_buys"]
	out["income"] = out["gold_income"]
	out["spend"] = out["gold_spend"]
	out["net"] = out["gold_net"]
	return out


func _output_per_turn(b: Dictionary) -> float:
	var t: float = float(b["turns_sum"])
	return (float(b["hp_sum"]) / t) if t > 0.0 else 0.0


# 逐战：某幕里实际开打过的机制（按次数降序）。
func _gimmick_tally(act: int) -> Array[String]:
	var counts := {}
	for r in _rows:
		if String(r["label"]) != "run3":
			continue
		for b in r.get("battles_detail", []):
			if int(b["act"]) != act:
				continue
			var g := String(b.get("gimmick", ""))
			if g != "":
				counts[g] = int(counts.get(g, 0)) + 1
	var names: Array = counts.keys()
	names.sort_custom(func(a, b): return int(counts[a]) > int(counts[b]))
	var out: Array[String] = []
	for n in names:
		out.append("%s×%d" % [String(n), int(counts[n])])
	return out


# 逐战：按组/幕汇总敌方底子与「最贵的一战」。
func _battle_agg(label: String, act: int) -> Dictionary:
	var out := {"n": 0, "hp_sum": 0, "hp_max": 0, "atk_sum": 0.0, "atk_max": 0, "turns_sum": 0,
		"worst_dmg": -1, "worst_turns": 0, "worst_hp": 0, "worst_room": ""}
	for r in _rows:
		if String(r["label"]) != label or int(r["act"]) != act:
			continue
		for b in r.get("battles_detail", []):
			out["n"] = int(out["n"]) + 1
			out["hp_sum"] = int(out["hp_sum"]) + int(b["enemy_hp"])
			out["hp_max"] = maxi(int(out["hp_max"]), int(b["enemy_hp"]))
			out["atk_sum"] = float(out["atk_sum"]) + float(b["enemy_atk"])
			out["atk_max"] = maxi(int(out["atk_max"]), int(b["enemy_atk"]))
			out["turns_sum"] = int(out["turns_sum"]) + int(b["turns"])
			if int(b["dmg"]) > int(out["worst_dmg"]):
				out["worst_dmg"] = int(b["dmg"])
				out["worst_turns"] = int(b["turns"])
				out["worst_hp"] = int(b["enemy_hp"])
				out["worst_room"] = String(b["room"])
	return out


func _delta(v: float, base: float) -> String:
	if base == 0.0:
		return "-"
	var d := (v - base) / base * 100.0
	var flag := " ⚠" if absf(d) > 30.0 else ""
	return "%+.0f%%%s" % [d, flag]


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
