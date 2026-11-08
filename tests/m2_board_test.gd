extends Node

# ============================================================================
# M2 ACT1 棋盘灰盒 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/m2_board_test.tscn
#
# 覆盖：
# ① 开关关闭时线性流程零变化（ROOMS = 24+真·最终）；
# ② 固定 25 节点拓扑：共享骨架 + 两段岔路 + 四个 BOSS 结局；
# ③ 1D3 步数预算：逐格前进、每格结算、分支选择、不可跳过、不可后退；
# ④ 一次性节点：重复 advance / 重复点击不二次结算；
# ⑤ 全路径可达：不同骰子序列都能在有限步内抵达 BOSS，无软锁；
# ⑥ 节点接入：普通/精英/BOSS 战斗、商店、休整、武器、护符；
# ⑦ 棋盘胜利回棋盘、最终 BOSS 回元进度；商店离开后回棋盘。
# 测试结束还原 meta 与开关（不污染玩家真实存档）。
# ============================================================================

const GENERATOR = preload("res://scripts/board/board_generator.gd")

var _fails := 0
var _checks := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var duel: DuelController = await _boot()
	if duel == null:
		print("RESULT FAIL (boot)")
		get_tree().quit(2)
		return
	var meta_backup: Dictionary = duel.meta.duplicate(true)
	var cfg_was: bool = bool(duel.board_config.enabled)
	var acts_was: int = int(duel.board_config.acts)
	var shape_was := String(duel.board_config.shape_id)
	var special_was := String(duel.board_config.special_id)
	var template_was := String(duel.board_config.template_id)

	_test_linear_preserved(duel)
	_test_topology(duel)
	_test_branch_value(duel)
	_test_templates(duel)
	_test_content_guarantees(duel)
	_test_shape_variants(duel)
	_test_shape_template_matrix(duel)
	_test_per_act_board(duel)
	_test_generation_seeds(duel)
	_test_dice_and_legality(duel)
	_test_one_shot(duel)
	_test_full_traversal(duel)
	_test_rest_node(duel)
	_test_camp_to_boss(duel)
	_test_shop_node(duel)
	_test_weapon_node(duel)
	_test_charm_node(duel)
	_test_treasure_node(duel)
	_test_shrine_node(duel)
	_test_armory_node(duel)
	_test_theme_distribution(duel)
	_test_battle_nodes(duel)
	_test_after_victory(duel)
	_test_growth_next_room(duel)
	_test_board_screen_ui(duel)
	await _test_full_act1_run(duel)

	duel.board_config.enabled = cfg_was
	duel.board_config.acts = acts_was
	duel.board_config.shape_id = shape_was
	duel.board_config.special_id = special_was
	duel.board_config.template_id = template_was
	duel.meta.clear()
	for k in meta_backup:
		duel.meta[k] = meta_backup[k]
	duel._meta_store.save_meta()

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.board_config.enabled = false   # 先验证线性入口，再由 _build_board 显式开启
	duel._confirm_loadout()
	await get_tree().process_frame
	return duel


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _build_board(duel: DuelController) -> void:
	duel.board_config.enabled = true
	duel.board_config.act = 1
	# 2026-11-08：三幕成为默认（board_config.tres acts=3）后，本套仍验证「单幕 ACT1」契约，
	# 必须显式钉住 acts=1；三幕契约由 tests/g7_run3_test.gd 覆盖。
	duel.board_config.acts = 1
	duel.board_config.dice_sides = 3
	duel.board_config.boss_ria = 7
	duel.board_config.shape_id = "standard"   # 既有断言按标准 25 节点骨架写；长尾由 _test_shape_variants 覆盖
	duel.board_config.special_id = "treasure" # 既有断言按宝箱写；神龛由 _test_shrine_node 覆盖
	duel._loadout_system.full_reset()


# 测试内回退到指定节点：只改公开运行状态，不重掷房间/物品。
func _rewind(duel: DuelController, id: String) -> void:
	duel.board.consumed.clear()
	duel.board.current_id = id
	duel.board.consumed[id] = true
	duel.board.dice = 0
	duel.board.last_roll = 0
	duel.board.feedback = ""


func _node(duel: DuelController, id: String) -> Dictionary:
	return duel.board.node_by_id(id)


func _nodes_of(duel: DuelController, type: String) -> Array:
	var out: Array = []
	for n in duel.board.nodes:
		if String(n["type"]) == type:
			out.append(n)
	return out


# ---------------------------------------------------------------------------
# ① 线性入口保留
# ---------------------------------------------------------------------------

func _test_linear_preserved(duel: DuelController) -> void:
	_check(not duel.node_mode, "开关关闭：默认线性模式")
	_check(duel.ROOMS.size() >= 8, "线性模式房序列保留（%d 房）" % duel.ROOMS.size())
	_check(duel.board != null and not duel.board.generated, "线性模式不生成棋盘")


# ---------------------------------------------------------------------------
# ② 固定 25 节点拓扑
# ---------------------------------------------------------------------------

func _test_topology(duel: DuelController) -> void:
	_build_board(duel)
	var b = duel.board
	_check(duel.node_mode, "开启开关后进入棋盘模式")
	_check(b.generated, "棋盘已生成")
	_check(b.node_count() == 25, "固定 25 节点")
	_check(duel.ROOMS.size() == 15, "ROOMS = 15 场候选战斗（宝箱替换了 1 场普通）")
	_check(_nodes_of(duel, "start").size() == 1, "1 个起点")
	_check(_nodes_of(duel, "normal").size() == 8, "8 个普通战斗")
	_check(_nodes_of(duel, "elite").size() == 3, "3 个精英战斗")
	_check(_nodes_of(duel, "boss").size() == 4, "4 个 BOSS（一局只到达其中一个）")
	_check(_nodes_of(duel, "weapon").size() == 1, "1 个武器格")
	_check(_nodes_of(duel, "charm").size() == 1, "1 个护符格")
	_check(_nodes_of(duel, "shop").size() == 1, "1 个商店格")
	_check(_nodes_of(duel, "rest").size() == 5, "5 个休整格（中段 1 + 尾路 4）")
	_check(_nodes_of(duel, "treasure").size() == 1, "1 个宝箱（G4-04，替换一条尾路的普通战斗）")

	var seen_ids := {}
	for n in b.nodes:
		seen_ids[String(n["id"])] = true
	var edges_ok := true
	for n in b.nodes:
		for nx in n.get("next", []):
			if not seen_ids.has(String(nx)):
				edges_ok = false
			var target: Dictionary = _node(duel, String(nx))
			if int(target.get("depth", 0)) <= int(n["depth"]):
				edges_ok = false
	_check(edges_ok, "所有连线指向更深的已定义节点（无环、只向 BOSS 前进）")

	var rooms_ok := true
	for n in b.nodes:
		if String(n["type"]) in ["normal", "elite", "boss"]:
			var r: RoomData = n.get("room")
			if r == null or int(n.get("battle_index", -1)) < 0 or int(n["battle_index"]) >= duel.ROOMS.size():
				rooms_ok = false
			elif duel.ROOMS[int(n["battle_index"])] != r:
				rooms_ok = false
	_check(rooms_ok, "战斗节点均绑定 RoomData，battle_index 对齐 ROOMS")

	_check(b.boss_ids.size() == 4, "棋盘记录 4 个 BOSS 节点")
	var boss_ria := {}
	var boss_final := true
	for id in b.boss_ids:
		var bn: Dictionary = _node(duel, id)
		boss_ria[int(bn.get("ria", -1))] = true
		if not bool(bn.get("final", false)):
			boss_final = false
	_check(boss_ria.keys() == [7], "4 个 BOSS 幕内难度位置统一 ria = 7（%s）" % str(boss_ria.keys()))
	_check(boss_final, "4 个 BOSS 节点均标记为最终战")

	var seen_ria := {}
	for n in b.nodes:
		if String(n["type"]) in ["normal", "elite"]:
			seen_ria[int(n["ria"])] = true
	_check(seen_ria.size() == 7, "非 BOSS 战斗分配 ria 0..6（%s）" % str(seen_ria.keys()))

	_check(b.current_id == "n0", "开局棋子停在起点")
	_check(b.is_consumed("n0"), "起点已消耗，不会重复结算")
	var weapon_n: Dictionary = _nodes_of(duel, "weapon")[0]
	var charm_n: Dictionary = _nodes_of(duel, "charm")[0]
	_check(String(weapon_n.get("item_path", "")) != "", "武器格已预确定具体武器")
	_check(String(charm_n.get("item_path", "")) != "", "护符格已预确定具体护符")
	_check(String(b.progress_text()).find("1/13") >= 0, "进度文本 1/13（%s）" % b.progress_text())
	# 岔路提示写明下游 BOSS，保证选择有信息
	var fork_desc := String(_node(duel, "n6").get("desc", ""))
	_check(fork_desc.find("上路") >= 0 and fork_desc.find("下路") >= 0, "岔路 A 展示上下路 BOSS 信息")
	var fork_b := String(_node(duel, "n9").get("desc", ""))
	_check(fork_b.find("BOSS") >= 0 or fork_b.find("（") >= 0, "岔路 B 展示尾路 BOSS 信息")


# ---------------------------------------------------------------------------
# ② G2-02 分支价值校验：两侧战斗构成对等，差异只在商店/休整与尾路 BOSS
# ---------------------------------------------------------------------------

func _count_type(duel: DuelController, ids: Array, type: String) -> int:
	var n := 0
	for id in ids:
		if String(_node(duel, String(id)).get("type", "")) == type:
			n += 1
	return n


func _test_branch_value(duel: DuelController) -> void:
	var upper := ["n7", "n8", "n9"]
	var lower := ["n10", "n11", "n12"]
	_check(_count_type(duel, upper, "normal") == _count_type(duel, lower, "normal")
		and _count_type(duel, upper, "elite") == _count_type(duel, lower, "elite"),
		"岔路 A 两侧战斗构成相同：各 1 普通 + 1 精英")
	var t9 := String(_node(duel, "n9")["type"])
	var t12 := String(_node(duel, "n12")["type"])
	_check((t9 == "shop" and t12 == "rest") or (t9 == "rest" and t12 == "shop"),
		"商店/休整互为替代，不可同时获得（当前 n9=%s / n12=%s）" % [t9, t12])
	_check(int(_node(duel, "n9")["depth"]) == int(_node(duel, "n12")["depth"]),
		"商店与休整同深度（不因路线长短改变取舍）")

	var tails := [["n13", "n21", "n14"], ["n15", "n22", "n16"], ["n17", "n23", "n18"], ["n19", "n24", "n20"]]
	var tails_ok := true
	var treasure_tails := 0
	for t in tails:
		var combat: int = _count_type(duel, t, "normal") + _count_type(duel, t, "treasure")
		if combat != 1 or _count_type(duel, t, "rest") != 1 or _count_type(duel, t, "boss") != 1:
			tails_ok = false
		treasure_tails += _count_type(duel, t, "treasure")
	_check(tails_ok, "四条尾路同为 1 战斗（普通/宝箱）+ 1 休整 + 1 BOSS（BOSS 前保底补给）")
	_check(treasure_tails == 1, "宝箱恰好替换一条尾路的普通战斗")

	var names := {}
	for id in duel.board.boss_ids:
		var r: RoomData = _node(duel, String(id)).get("room")
		names[String(r.name) if r != null else String(id)] = true
	_check(names.size() == 4, "四条尾路 BOSS 互不相同（选择有信息）")

	var ria_ok := true
	var by_depth := {}
	for n in duel.board.nodes:
		if String(n["type"]) in ["normal", "elite", "boss"]:
			var d := int(n["depth"])
			var ria := int(n["ria"])
			if by_depth.has(d) and int(by_depth[d]) != ria:
				ria_ok = false
			by_depth[d] = ria
	_check(ria_ok, "同一深度的战斗 ria 一致（分支不改变难度）")


# ---------------------------------------------------------------------------
# ②b G4-01 分支价值模板：构成一致、同种子可复现、不同种子能抽到多套
# ---------------------------------------------------------------------------

func _test_templates(duel: DuelController) -> void:
	var ids := {}
	for t in GENERATOR.TEMPLATES:
		ids[String(t["id"])] = true
	_check(ids.size() >= 4 and ids.size() <= 6, "计划要求 4–6 套分支价值模板（%s）" % str(ids.keys()))

	var all_ok := true
	var battle_ok := true
	var detail: Array[String] = []
	for t in GENERATOR.TEMPLATES:
		var counts := {}
		var types := {}
		for spec in GENERATOR.TOPOLOGY:
			var id := String(spec[0])
			var type := String(spec[1])
			var ov: Dictionary = t.get("overrides", {})
			if ov.has(id):
				type = String(ov[id])
			types[id] = type
			counts[type] = int(counts.get(type, 0)) + 1
		var ok := int(counts.get("start", 0)) == 1 and int(counts.get("boss", 0)) == 4 			and int(counts.get("shop", 0)) == 1 and int(counts.get("rest", 0)) == 5 			and int(counts.get("weapon", 0)) == 1 and int(counts.get("charm", 0)) == 1 			and int(counts.get("normal", 0)) == 9 and int(counts.get("elite", 0)) == 3
		if not ok:
			all_ok = false
		# 模板只在战斗节点之间换精英/普通：BATTLE_ORDER 内必须仍是战斗，非战斗节点不得变战斗。
		for id in GENERATOR.BATTLE_ORDER:
			if not String(types.get(String(id), "")) in ["normal", "elite", "boss"]:
				battle_ok = false
		for id in types:
			if not String(id) in GENERATOR.BATTLE_ORDER and String(types[id]) in ["normal", "elite", "boss"]:
				battle_ok = false
		detail.append("%s 普%d/精%d" % [t["id"], int(counts.get("normal", 0)), int(counts.get("elite", 0))])
	_check(all_ok, "每套模板节点构成一致：%s" % ", ".join(detail))
	_check(battle_ok, "每套模板保持单局战斗节点集合不变（战斗数 8 / battle_index 不漂移）")

	# 非对称模板只前置一侧精英，另一侧保持「普通 → 精英」。
	var asym := {}
	for t in GENERATOR.TEMPLATES:
		asym[String(t["id"])] = t.get("overrides", {})
	var up: Dictionary = asym.get("elite_upper", {})
	var lo: Dictionary = asym.get("elite_lower", {})
	_check(String(up.get("n7", "")) == "elite" and String(up.get("n8", "")) == "normal" and not up.has("n10"),
		"elite_upper：上路精英前置、下路保持普通 → 精英")
	_check(String(lo.get("n10", "")) == "elite" and String(lo.get("n11", "")) == "normal" and not lo.has("n7"),
		"elite_lower：下路精英前置、上路保持普通 → 精英")

	var cfg = duel.board_config
	seed(9182)
	duel.board.generate(cfg)
	var a := String(duel.board.template_id)
	seed(9182)
	duel.board.generate(cfg)
	var b := String(duel.board.template_id)
	_check(a == b and ids.has(a), "同种子模板可复现（%s）" % a)

	# 固定模板（BoardConfig.template_id）：测试 / 采集按 id 生成，精英位置与定义一致。
	var fixed_ok := true
	var fixed_detail: Array[String] = []
	var expect := {
		"standard": ["n8", "n11"], "mirror": ["n8", "n11"],
		"elite_first": ["n7", "n10"], "elite_upper": ["n7", "n11"], "elite_lower": ["n8", "n10"],
	}
	for tid in ids.keys():
		cfg.template_id = String(tid)
		seed(31)
		duel.board.generate(cfg)
		var got := String(duel.board.template_id)
		var ue := _b_elite(duel.board, ["n7", "n8"])
		var le := _b_elite(duel.board, ["n10", "n11"])
		var want: Array = expect.get(String(tid), [])
		if got != String(tid) or (not want.is_empty() and (ue != String(want[0]) or le != String(want[1]))):
			fixed_ok = false
			fixed_detail.append("%s→%s(%s/%s)" % [tid, got, ue, le])
	_check(fixed_ok, "固定模板 id 生效且精英位置正确%s" % ("" if fixed_ok else "：" + ", ".join(fixed_detail)))
	cfg.template_id = ""

	var seen := {}
	for i in range(120):
		seed(1000 + i)
		duel.board.generate(cfg)
		seen[String(duel.board.template_id)] = true
	_check(seen.size() == ids.size(), "不同种子能抽到全部 %d 套模板（%s）" % [ids.size(), str(seen.keys())])
	_build_board(duel)


# ---------------------------------------------------------------------------
# ②c G4-02 内容保底：同盘战斗房不重复、同种子内容可复现
# ---------------------------------------------------------------------------

func _board_sig(duel: DuelController) -> String:
	var b = duel.board
	var parts: Array[String] = [String(b.template_id)]
	for n in b.nodes:
		var r: RoomData = n.get("room")
		parts.append("%s:%s:%s:%s:%s" % [String(n["id"]), String(n["type"]),
			"" if r == null else r.resource_path, String(n.get("item_path", "")),
			str(n.get("armory_paths", []))])
	return "|".join(parts)


func _test_content_guarantees(duel: DuelController) -> void:
	var cfg = duel.board_config
	seed(5150)
	duel.board.generate(cfg)
	var sig1 := _board_sig(duel)
	var rooms := {}
	var dup := false
	for n in duel.board.nodes:
		if String(n["type"]) in ["normal", "elite", "boss"]:
			var r: RoomData = n.get("room")
			if r == null:
				continue
			if rooms.has(r.resource_path):
				dup = true
			rooms[r.resource_path] = true
	_check(not dup, "同一棋盘战斗房不重复（%d 场）" % rooms.size())
	seed(5150)
	duel.board.generate(cfg)
	_check(sig1 == _board_sig(duel), "同种子棋盘内容可复现（模板 / 房间 / 物品）")
	_build_board(duel)


# ---------------------------------------------------------------------------
# ②d G4-02 骨架随机：长尾 29 节点 / 14 格 / 8 战（尾路 普通 → 营地 → 商店 → BOSS）
# ---------------------------------------------------------------------------

func _test_shape_variants(duel: DuelController) -> void:
	var cfg = duel.board_config

	# 随机骨架：同一 RNG 通道下三套都能出现
	cfg.shape_id = ""
	var seen := {}
	for i in range(60):
		seed(7200 + i)
		duel.board.generate(cfg)
		seen[String(duel.board.shape_id)] = true
	_check(seen.has("standard") and seen.has("long_tail") and seen.has("long_share"),
		"随机骨架能抽到 standard / long_tail / long_share（%s）" % str(seen.keys()))

	# 长尾骨架：结构、构成与路径
	cfg.shape_id = "long_tail"
	seed(4242)
	duel._loadout_system.full_reset()
	var b = duel.board
	_check(String(b.shape_id) == "long_tail", "长尾骨架已生成（%s）" % b.shape_id)
	_check(b.node_count() == 29, "长尾骨架 29 节点")
	_check(b.route_length() == 14, "长尾单局路径 14 格（%s）" % b.progress_text())
	_check(duel.ROOMS.size() == 15, "长尾仍是 15 场候选战斗（宝箱替换 1 场）")
	_check(_nodes_of(duel, "boss").size() == 4, "长尾 4 个 BOSS")
	_check(_nodes_of(duel, "shop").size() == 5, "长尾 5 个商店（中段 1 + 尾路 4）")
	_check(_nodes_of(duel, "rest").size() == 5, "长尾 5 个休整（中段 1 + 尾路营地 4）")
	_check(_nodes_of(duel, "treasure").size() == 1, "长尾同样 1 个宝箱")

	var tails := [
		["n13", "n21", "n25", "n14"], ["n15", "n22", "n26", "n16"],
		["n17", "n23", "n27", "n18"], ["n19", "n24", "n28", "n20"],
	]
	var tails_ok := true
	for t in tails:
		var head := String(_node(duel, t[0]).get("type", ""))
		if head != "normal" and head != "treasure":
			tails_ok = false
		var want := ["rest", "shop", "boss"]
		for i in range(1, 4):
			if String(_node(duel, t[i]).get("type", "")) != want[i - 1]:
				tails_ok = false
			if i < 3:
				var nxt: Array = _node(duel, t[i]).get("next", [])
				if nxt.size() != 1 or String(nxt[0]) != t[i + 1]:
					tails_ok = false
		var head_next: Array = _node(duel, t[0]).get("next", [])
		if head_next.size() != 1 or String(head_next[0]) != t[1]:
			tails_ok = false
	_check(tails_ok, "四条尾路同为 普通/宝箱 → 营地 → 商店 → BOSS（BOSS 前仍有营地）")

	# 实地走一条长尾路：13 格 / 14 节点 / 8 场战斗 / 尾路商店进过一次
	_rewind(duel, "n0")
	var steps := 0
	var battles := 0
	var tail_shop := false
	var treasure_seen := false
	var stuck := false
	while not b.current_is_boss() and steps < 30:
		b.dice = 3
		var legal: Array = b.legal_targets()
		if legal.is_empty():
			stuck = true
			break
		var node: Dictionary = b.advance_to(String(legal[0]["id"]))
		if node.is_empty():
			stuck = true
			break
		if String(node["type"]) in ["normal", "elite", "boss"]:
			battles += 1
		if String(node["type"]) == "treasure":
			treasure_seen = true
		if String(node["id"]) in ["n25", "n26", "n27", "n28"]:
			tail_shop = true
		steps += 1
	_check(not stuck and b.current_is_boss(), "长尾路径全程有合法落点并抵达 BOSS")
	_check(steps == 13 and b.visited_count() == 14,
		"长尾走满 13 格 / 14 节点（%d / %d）" % [steps, b.visited_count()])
	_check(battles + (1 if treasure_seen else 0) == 8,
		"长尾单局战斗位共 8 个（实际战斗 %d + 宝箱 %d）" % [battles, 1 if treasure_seen else 0])
	_check(tail_shop, "长尾尾路商店实际经过（BOSS 前可消费）")

	# 长尾尾路接入：营地可补给、尾路商店可开可离（多商店共用同一货架逻辑）
	duel.player_hp_max = 100
	duel.player_hp = 40
	var camp: Dictionary = _enter(duel, "n13", 1, "n21")
	_check(not camp.is_empty() and duel.hud._camp_dialog != null and duel.hud._camp_dialog.visible,
		"长尾尾路营地打开补给")
	duel._camp_leave()
	var shop: Dictionary = _enter(duel, "n21", 1, "n25")
	_check(not shop.is_empty() and duel.hud.shop_screen_is_open(), "长尾尾路商店可打开")
	duel._on_shop_leave_pressed()
	_check(duel.hud.board_screen.visible, "长尾尾路商店离开后回到棋盘")

	# 29 个节点按钮仍在 480×270 内
	duel.hud.show_board_screen(b)
	var scr = duel.hud.board_screen
	_check(scr._buttons.size() == 29, "长尾棋盘有 29 个节点按钮")
	var in_bounds := true
	var bad: Array[String] = []
	for id in scr._buttons:
		var btn: Button = scr._buttons[id]
		var r := Rect2(btn.position, btn.size)
		if r.position.x < 0 or r.position.y < 0 or r.end.x > 480.0 or r.end.y > 270.0:
			in_bounds = false
			bad.append("%s=%s" % [id, str(r)])
	_check(in_bounds, "长尾节点按钮全部在 480×270 内%s" % ("" if bad.is_empty() else "（%s）" % ", ".join(bad)))
	_check(scr._node_w == 30.0 and scr._pos.size() == 29, "长尾布局使用 30px 节点宽 / 29 个坐标")

	# 延展共享段骨架：26 节点 / 14 格 / 共享段多一间商店，岔路与尾路后移 1 格
	cfg.shape_id = "long_share"
	seed(5252)
	duel._loadout_system.full_reset()
	var sb = duel.board
	_check(String(sb.shape_id) == "long_share", "延展共享段骨架已生成（%s）" % sb.shape_id)
	_check(sb.node_count() == 26, "延展共享段 26 节点")
	_check(sb.route_length() == 14, "延展共享段单局路径 14 格（%s）" % sb.progress_text())
	_check(duel.ROOMS.size() == 15, "延展共享段仍是 15 场候选战斗（宝箱替换 1 场）")
	_check(_nodes_of(duel, "boss").size() == 4, "延展共享段 4 个 BOSS")
	_check(_nodes_of(duel, "shop").size() == 2, "延展共享段 2 个商店（共享段 n29 + 中段其一）")
	_check(_nodes_of(duel, "rest").size() == 5, "延展共享段 5 个休整（中段 1 + 尾路营地 4）")
	_check(_nodes_of(duel, "treasure").size() == 1, "延展共享段同样 1 个宝箱")
	var n29: Dictionary = _node(duel, "n29")
	_check(String(n29.get("type", "")) == "shop" and int(n29.get("depth", -1)) == 6,
		"n29 是共享段第 6 列商店")
	var mid_rest_ok := true
	for id in ["n9", "n12"]:
		var mid: Dictionary = _node(duel, id)
		if String(mid.get("type", "")) == "rest" and String(mid.get("title", "")) != "休整":
			mid_rest_ok = false
	_check(mid_rest_ok, "中段休整在深度 10 仍显示「休整」而不是尾路营地")
	var share_tails := [
		["n13", "n21", "n14"], ["n15", "n22", "n16"],
		["n17", "n23", "n18"], ["n19", "n24", "n20"],
	]
	var share_tails_ok := true
	for t in share_tails:
		var head := String(_node(duel, t[0]).get("type", ""))
		if head != "normal" and head != "treasure":
			share_tails_ok = false
		if String(_node(duel, t[1]).get("type", "")) != "rest":
			share_tails_ok = false
		if String(_node(duel, t[2]).get("type", "")) != "boss":
			share_tails_ok = false
		if int(_node(duel, t[2]).get("depth", -1)) != 13:
			share_tails_ok = false
	_check(share_tails_ok, "四条尾路同为 普通/宝箱 → 营地 → BOSS，BOSS 在第 13 列")

	# 实地走一条延展共享段路线：13 格 / 14 节点 / 8 场战斗 / 共享段商店经过
	_rewind(duel, "n0")
	steps = 0
	battles = 0
	treasure_seen = false
	var shared_shop := false
	stuck = false
	while not sb.current_is_boss() and steps < 30:
		sb.dice = 3
		var legal_s: Array = sb.legal_targets()
		if legal_s.is_empty():
			stuck = true
			break
		var node_s: Dictionary = sb.advance_to(String(legal_s[0]["id"]))
		if node_s.is_empty():
			stuck = true
			break
		if String(node_s["type"]) in ["normal", "elite", "boss"]:
			battles += 1
		if String(node_s["type"]) == "treasure":
			treasure_seen = true
		if String(node_s["id"]) == "n29":
			shared_shop = true
		steps += 1
	_check(not stuck and sb.current_is_boss(), "延展共享段路径全程有合法落点并抵达 BOSS")
	_check(steps == 13 and sb.visited_count() == 14,
		"延展共享段走满 13 格 / 14 节点（%d / %d）" % [steps, sb.visited_count()])
	_check(battles + (1 if treasure_seen else 0) == 8,
		"延展共享段单局战斗位共 8 个（实际战斗 %d + 宝箱 %d）" % [battles, 1 if treasure_seen else 0])
	_check(shared_shop, "共享段商店 n29 实际经过")

	duel.hud.show_board_screen(sb)
	scr = duel.hud.board_screen
	_check(scr._buttons.size() == 26, "延展共享段棋盘有 26 个节点按钮")
	var share_bounds := true
	var share_bad: Array[String] = []
	for id in scr._buttons:
		var btn_s: Button = scr._buttons[id]
		var rs := Rect2(btn_s.position, btn_s.size)
		if rs.position.x < 0 or rs.position.y < 0 or rs.end.x > 480.0 or rs.end.y > 270.0:
			share_bounds = false
			share_bad.append("%s=%s" % [id, str(rs)])
	_check(share_bounds, "延展共享段节点按钮全部在 480×270 内%s"
		% ("" if share_bad.is_empty() else "（%s）" % ", ".join(share_bad)))

	# 回到标准骨架，后续测试沿用 25 节点断言
	_build_board(duel)


# ---------------------------------------------------------------------------
# ②f G4 收口：每套骨架 × 每套模板都能走完整路线（3 × 5 = 15 条）
# ---------------------------------------------------------------------------

func _test_shape_template_matrix(duel: DuelController) -> void:
	var cfg = duel.board_config
	var shapes := {"standard": 25, "long_tail": 29, "long_share": 26}
	var tpl_ids: Array[String] = []
	for t in GENERATOR.TEMPLATES:
		tpl_ids.append(String(t["id"]))
	var walks_ok := true
	var bad: Array[String] = []
	for sid in shapes:
		for tid in tpl_ids:
			cfg.shape_id = String(sid)
			cfg.template_id = String(tid)
			seed(8800)
			duel._loadout_system.full_reset()
			var b = duel.board
			var steps := 0
			var battles := 0
			var special := 0
			var stuck := false
			while not b.current_is_boss() and steps < 30:
				b.dice = 3
				var legal: Array = b.legal_targets()
				if legal.is_empty():
					stuck = true
					break
				var node: Dictionary = b.advance_to(String(legal[0]["id"]))
				if node.is_empty():
					stuck = true
					break
				var t := String(node["type"])
				if t in ["normal", "elite", "boss"]:
					battles += 1
				elif t in ["treasure", "shrine", "armory"]:
					special += 1
				steps += 1
			var ok: bool = not stuck and b.current_is_boss()
			ok = ok and b.node_count() == int(shapes[sid])
			ok = ok and steps == b.route_length() - 1 and b.visited_count() == b.route_length()
			ok = ok and battles + special == 8
			ok = ok and String(b.shape_id) == String(sid) and String(b.template_id) == String(tid)
			if not ok:
				walks_ok = false
				bad.append("%s/%s 步%d 战%d 特%d 形%s 模%s" % [
					sid, tid, steps, battles, special, b.shape_id, b.template_id])
	_check(walks_ok, "3 套骨架 × 5 套模板全部走到 BOSS（15 条路线 · 每条 8 个战斗位）%s"
		% ("" if bad.is_empty() else "：" + ", ".join(bad)))
	cfg.shape_id = ""
	cfg.template_id = ""
	_build_board(duel)


# ---------------------------------------------------------------------------
# ②e G4 自动验收：500 个种子全部可生成、4 BOSS 可达、节点数与骨架一致
# ---------------------------------------------------------------------------

# G7-A S3：三幕棋盘按幕参数化（3 幕 × 3 骨架 × 5 模板）。
# BOSS 节点必须取本幕 BOSS 房（不再静默回退普通房）；ACT3 的第四条尾路由最终 BOSS 承担；
# ACT1/ACT2 不得出现最终 BOSS；每张棋盘都能走到 BOSS（无软锁）。
func _test_per_act_board(duel: DuelController) -> void:
	var cfg = duel.board_config
	var shapes := ["standard", "long_tail", "long_share"]
	var tpl_ids: Array[String] = []
	for t in GENERATOR.TEMPLATES:
		tpl_ids.append(String(t["id"]))
	var acts := [1, 2, 3]
	var runs := 0
	var bad: Array[String] = []
	var finals := {1: 0, 2: 0, 3: 0}
	var boss_rooms := {1: {}, 2: {}, 3: {}}
	var labels_ok := true
	for act in acts:
		for sid in shapes:
			for tid in tpl_ids:
				cfg.act = act
				cfg.shape_id = String(sid)
				cfg.template_id = String(tid)
				cfg.special_id = ""
				seed(9300 + act * 100 + runs)
				if not duel.board.generate(cfg):
					bad.append("ACT%d/%s/%s 生成失败" % [act, sid, tid])
					runs += 1
					continue
				runs += 1
				var b = duel.board
				if int(b.act) != act:
					bad.append("ACT%d act 字段错为 %d" % [act, int(b.act)])
				if b.act_label() != ["ACT I", "ACT II", "ACT III"][act - 1]:
					bad.append("ACT%d 幕名错 %s" % [act, b.act_label()])
					labels_ok = false
				if String(b.progress_text()).begins_with(b.act_label()) == false:
					bad.append("ACT%d 进度文本未带幕名" % act)
				if b.boss_ids.size() != 4:
					bad.append("ACT%d BOSS 节点数 %d" % [act, b.boss_ids.size()])
				var final_here := 0
				for id in b.boss_ids:
					var node: Dictionary = b.node_by_id(id)
					var room: RoomData = node.get("room")
					if room == null:
						bad.append("ACT%d %s 无房" % [act, id])
						continue
					if String(room.kind) != "boss":
						bad.append("ACT%d %s 是非 BOSS 房(%s)" % [act, id, room.kind])
					if int(room.act) != act:
						bad.append("ACT%d 出现他幕房 act=%d" % [act, int(room.act)])
					if room.final_boss:
						final_here += 1
					boss_rooms[act][room.resource_path] = true
				if final_here > 1:
					bad.append("ACT%d 出现 %d 个最终 BOSS" % [act, final_here])
				finals[act] += final_here
				# 同一张棋盘内战斗房不重复
				var rooms_seen := {}
				for n in b.nodes:
					var rm: RoomData = n.get("room")
					if rm == null:
						continue
					if rooms_seen.has(rm.resource_path):
						bad.append("ACT%d 房间重复 %s" % [act, rm.resource_path.get_file()])
					rooms_seen[rm.resource_path] = true
				# 全路径可走：每次 3 步、取第一个合法格
				var steps := 0
				while not b.current_is_boss() and steps < 30:
					b.dice = 3
					var legal: Array = b.legal_targets()
					if legal.is_empty():
						bad.append("ACT%d 软锁（%s/%s）" % [act, sid, tid])
						break
					if b.advance_to(String(legal[0]["id"])).is_empty():
						bad.append("ACT%d 无法前进" % act)
						break
					steps += 1
				if not b.current_is_boss():
					bad.append("ACT%d 30 步内未到 BOSS" % act)
	_check(runs == 45, "三幕矩阵共 45 张棋盘（%d）" % runs)
	_check(bad.is_empty(), "三幕 × 3 骨架 × 5 模板全部合法（异常 %d：%s）" % [bad.size(), ",".join(bad.slice(0, 4))])
	_check(labels_ok, "每幕棋盘幕名正确（ACT I / II / III）")
	_check(finals[1] == 0 and finals[2] == 0, "ACT1/ACT2 不出现最终 BOSS（%d/%d）" % [finals[1], finals[2]])
	_check(finals[3] == 15, "ACT3 每张棋盘恰好 1 个最终 BOSS（%d/15）" % finals[3])
	_check(boss_rooms[3].size() == 4, "ACT3 的四条尾路用满 4 个 BOSS（%d）" % boss_rooms[3].size())
	cfg.act = 1
	cfg.shape_id = "standard"
	cfg.template_id = ""
	cfg.special_id = "treasure"


func _test_generation_seeds(duel: DuelController) -> void:
	var cfg = duel.board_config
	cfg.shape_id = ""
	cfg.special_id = ""
	var ok := true
	var shapes := {}
	var specials := {}
	var templates := {}
	var theme_ok := true
	var adjacent_ok := true
	var elite_ok := true
	var bad_seed := -1
	for i in range(500):
		seed(10000 + i)
		if not duel.board.generate(cfg):
			ok = false
			bad_seed = i
			break
		var b = duel.board
		var sid := String(b.shape_id)
		shapes[sid] = true
		templates[String(b.template_id)] = true
		var bosses := 0
		var special := 0
		for n in b.nodes:
			var t := String(n["type"])
			if t == "boss":
				bosses += 1
			elif t in ["treasure", "shrine", "armory"]:
				specials[t] = true
				special += 1
		var want := int({"standard": 25, "long_tail": 29, "long_share": 26}.get(sid, -1))
		if bosses != 4 or special != 1 or b.node_count() != want:
			ok = false
			bad_seed = i
			break
		# G4 主题分布：尾路首战主题 = BOSS 元素；相邻战斗不同元素；同路径精英不同元素
		for pair in [["n13", "n14"], ["n15", "n16"], ["n17", "n18"], ["n19", "n20"]]:
			var head: Dictionary = b.node_by_id(String(pair[0]))
			var be := _b_elem(b, String(pair[1]))
			if be == "" or String(head.get("theme", "")) != be:
				theme_ok = false
		for seq in [["n1", "n3", "n4", "n6", "n7", "n8"],
				["n1", "n3", "n4", "n6", "n10", "n11"]]:
			var prev_e := ""
			for id in seq:
				var e := _b_elem(b, String(id))
				if prev_e != "" and e == prev_e:
					adjacent_ok = false
				prev_e = e
		var ue := _b_elite(b, ["n7", "n8"])
		var le := _b_elite(b, ["n10", "n11"])
		if _b_elem(b, "n4") == _b_elem(b, ue) or _b_elem(b, "n4") == _b_elem(b, le):
			elite_ok = false
	_check(ok, "500 个种子生成合法（4 BOSS 可达 / 1 特殊格 / 节点数与骨架一致）%s"
		% ("" if ok else "（首个失败 %d）" % bad_seed))
	_check(theme_ok, "500 个种子：四条尾路首战主题均与 BOSS 同元素")
	_check(adjacent_ok, "500 个种子：共享段 / 中段相邻战斗不同元素")
	_check(elite_ok, "500 个种子：同一路径两个精英不同元素")
	_check(shapes.has("standard") and shapes.has("long_tail") and shapes.has("long_share"),
		"500 个种子三套骨架都出现（%s）" % str(shapes.keys()))
	_check(templates.size() == GENERATOR.TEMPLATES.size(),
		"500 个种子全部模板都出现（%s）" % str(templates.keys()))
	_check(specials.has("treasure") and specials.has("shrine") and specials.has("armory"),
		"500 个种子宝箱 / 神龛 / 武器藏库都出现（%s）" % str(specials.keys()))
	_build_board(duel)


# ---------------------------------------------------------------------------
# ③ 1D3 步数预算 / 逐格移动 / 分支
# ---------------------------------------------------------------------------

func _test_dice_and_legality(duel: DuelController) -> void:
	var b = duel.board
	var all_ok := true
	for i in range(200):
		_rewind(duel, "n0")
		var r: int = b.roll_dice()
		if r < 1 or r > 3:
			all_ok = false
	_check(all_ok, "1D3 结果恒在 1..3（200 次）")

	_rewind(duel, "n0")
	b.dice = 1
	_check(_ids(b.legal_targets()) == ["n1"], "起点剩 1 步 → 唯一落点 n1")
	b.dice = 3
	_check(_ids(b.legal_targets()) == ["n1"], "起点剩 3 步 → 仍只走一格（不再跳过 n1）")
	var first: Dictionary = b.advance_to("n1")
	_check(not first.is_empty(), "前进一格成功")
	_check(b.dice == 2, "前进一格只消耗 1 步（剩余 2）")
	_check(_ids(b.legal_targets()) == ["n2"], "剩余步数可继续走下一格")
	b.advance_to("n2")
	_check(b.dice == 1 and b.current_id == "n2", "连续走格：n0 → n1 → n2，剩余 1 步")

	_rewind(duel, "n6")
	b.dice = 2
	var fork: Array = _ids(b.legal_targets())
	_check(fork.size() == 2 and fork.has("n7") and fork.has("n10"), "岔路 A：上路 n7 / 下路 n10")
	b.advance_to("n7")
	_check(b.current_id == "n7" and b.dice == 1, "选择上路后停在 n7，剩余 1 步")
	_check(_ids(b.legal_targets()) == ["n8"], "岔路选择后另一侧不可回头")
	b.advance_to("n8")
	_check(b.current_id == "n8" and b.dice == 0, "步数用完后停在 n8，需重新掷骰")

	_rewind(duel, "n13")
	b.dice = 3
	_check(_ids(b.legal_targets()) == ["n21"], "尾路战斗后唯一去路是休整")
	b.advance_to("n21")
	_check(b.current_id == "n21" and b.dice == 2, "进入休整后仍可用剩余步数前进")
	_check(_ids(b.legal_targets()) == ["n14"], "休整后唯一去路是 BOSS")
	b.advance_to("n14")
	_check(b.current_id == "n14" and b.dice == 0, "进入 BOSS 自动清空剩余步数")

	_rewind(duel, "n14")
	b.dice = 2
	_check(b.legal_targets().is_empty(), "BOSS 节点无合法落点")
	b.dice = 0
	_check(b.roll_dice() == 0, "BOSS 节点不再掷骰")

	_rewind(duel, "n0")
	b.dice = 1
	var bad: Dictionary = b.advance_to("n6")   # 非相邻节点
	_check(bad.is_empty(), "非法落点被拒绝（不能跳格）")
	_check(b.current_id == "n0", "拒绝非法落点后仍在起点")


func _ids(nodes: Array) -> Array:
	var out: Array = []
	for n in nodes:
		out.append(String(n["id"]))
	out.sort()
	return out


# ---------------------------------------------------------------------------
# ④ 一次性节点
# ---------------------------------------------------------------------------

func _test_one_shot(duel: DuelController) -> void:
	var b = duel.board
	_rewind(duel, "n0")
	b.dice = 1
	var first: Dictionary = b.advance_to("n1")
	var visited: int = b.visited_count()
	var second: Dictionary = b.advance_to("n1")
	_check(not first.is_empty(), "首次进入节点成功")
	_check(second.is_empty(), "重复 advance 被拒绝（一次性）")
	_check(b.visited_count() == visited, "重复调用不增加已探索数")
	_check(b.current_id == "n1", "重复调用不改变当前节点")
	# 回到分支再前进：已消耗分支节点不再出现在合法落点
	_rewind(duel, "n6")
	b.consumed["n7"] = true
	b.dice = 1
	_check(_ids(b.legal_targets()) == ["n10"], "已消耗分支节点不再作为落点")


# ---------------------------------------------------------------------------
# ⑤ 全路径可达 / 无软锁
# ---------------------------------------------------------------------------

func _test_full_traversal(duel: DuelController) -> void:
	var b = duel.board
	var patterns := [
		[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
		[3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3],
		[1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1],
		[2, 1, 3, 2, 1, 3, 2, 1, 3, 2, 1, 3, 2],
	]
	for pi in range(patterns.size()):
		var pattern: Array = patterns[pi]
		_rewind(duel, "n0")
		var steps := 0
		var stuck := false
		while not b.current_is_boss() and steps < 24:
			if b.dice == 0:
				b.dice = int(pattern[steps % pattern.size()])
			var legal: Array = b.legal_targets()
			if legal.is_empty():
				stuck = true
				break
			# 交替选第一/最后一个合法落点，覆盖岔路两侧
			var pick: Dictionary = legal[legal.size() - 1] if (steps % 2 == 1) else legal[0]
			if b.advance_to(String(pick["id"])).is_empty():
				stuck = true
				break
			steps += 1
		_check(not stuck, "骰子序列 %d：全程有合法落点" % (pi + 1))
		_check(b.current_is_boss(), "骰子序列 %d：%d 格抵达 BOSS" % [pi + 1, steps])
		_check(steps == 12, "骰子序列 %d：路径固定 12 格（实际 %d）" % [pi + 1, steps])
		_check(b.visited_count() == 13, "骰子序列 %d：经过 13 个节点（含起点）" % (pi + 1))


# ---------------------------------------------------------------------------
# ⑥ 节点接入
# ---------------------------------------------------------------------------

func _enter(duel: DuelController, from_id: String, dice: int, target_id: String) -> Dictionary:
	_rewind(duel, from_id)
	duel.board.dice = dice
	var n: Dictionary = duel.board.advance_to(target_id)
	if n.is_empty():
		return {}
	duel._on_board_node_entered(n)
	return n


# 中段岔路 B 的商店/休整节点（模板可能左右互换）
func _mid_node_of_type(duel: DuelController, type: String) -> Dictionary:
	for id in ["n9", "n12"]:
		var n: Dictionary = _node(duel, id)
		if String(n.get("type", "")) == type:
			return n
	return {}


func _prev_of(id: String) -> String:
	return {"n12": "n11", "n2": "n1", "n5": "n4"}.get(id, "n8")


func _test_rest_node(duel: DuelController) -> void:
	duel.player_hp_max = 100
	duel.player_hp = 50
	# 真实路径：休整发生在棋盘主视图可见、战斗 HUD 隐藏时（BoardScreen.show_board 会 hud.hide()）。
	duel.hud.show_board_screen(duel.board)
	var rest_node := _mid_node_of_type(duel, "rest")
	var n: Dictionary = _enter(duel, _prev_of(String(rest_node["id"])), 1, String(rest_node["id"]))
	_check(not n.is_empty(), "进入休整格")
	_check(duel.player_hp == 75, "休整恢复 25% 最大 HP（50 → 75）")
	_check(duel.hud._camp_dialog != null and duel.hud._camp_dialog.visible, "休整后打开营地补给")
	_check(duel.hud._camp_dialog != null and duel.hud._camp_dialog.is_visible_in_tree(), "营地补给在棋盘视图下真实可见（不被隐藏的战斗 HUD 吞掉）")
	_check(duel._camp_offers.size() == 3, "营地提供武器/护符/消耗品各 1")
	_check(not duel.in_interroom, "营地不进入线性间歇态")
	# 买 1 件消耗品：扣金币、关闭营地、回棋盘（一局限 1 件）
	var offer := {}
	for o in duel._camp_offers:
		if String(o.get("kind", "")) == "active":
			offer = o
			break
	if not offer.is_empty():
		var gold_before: int = duel.gold
		duel.gold = 999
		duel._camp_buy(offer)
		_check(duel.gold == 999 - int(offer["price"]), "营地购买扣除对应金币")
		_check(not duel.hud._camp_dialog.visible, "购买后营地关闭")
		_check(duel.hud.board_screen.visible, "购买后回到棋盘")
		duel.gold = gold_before
	# 满血再次休整：不溢出，仍可进营地；离开回棋盘
	duel.player_hp = 100
	duel._board_rest()
	_check(duel.player_hp == 100, "满血休整不溢出")
	_check(duel.hud._camp_dialog.visible, "满血休整仍可进入营地")
	duel._camp_leave()
	_check(duel.hud.board_screen.visible and String(duel.board.feedback).find("营地") >= 0, "离开营地回到棋盘")


# 回归（2026-11-07 真机）：营地弹层必须挂在棋盘同级节点，否则被 hud.hide() 一起藏掉，
# 补给留在「不可见但仍 visible」状态，进 BOSS 时才弹出并卡住战斗。
func _test_camp_to_boss(duel: DuelController) -> void:
	var b = duel.board
	_rewind(duel, "n13")
	duel.hud.show_board_screen(b)
	b.dice = 1
	var rest: Dictionary = b.advance_to("n21")
	duel._on_board_node_entered(rest)
	_check(not rest.is_empty() and duel.hud._camp_dialog.is_visible_in_tree(), "营地弹出时在棋盘视图上真实可见")
	duel.hud._on_camp_close_pressed()   # 真实「离开营地」按钮回调
	_check(duel.hud.board_screen.visible and not duel.hud._camp_dialog.is_visible_in_tree(),
		"离开营地后回到棋盘且弹层完全消失")
	b.dice = 1
	var boss: Dictionary = b.advance_to("n14")
	_check(not boss.is_empty() and String(boss.get("type", "")) == "boss", "补给结束后可前进到 BOSS 节点")
	duel.hud.board_screen._pending_node = boss
	duel.hud.board_screen._on_confirm_battle()
	_check(duel.hud.visible and not duel.hud.board_screen.visible, "补给后 BOSS 战真正开启（切回战斗 HUD）")
	_check(duel.enemy_name != "" and duel.current_room != null, "BOSS 战敌人与房间已加载")
	_check(not duel.hud._camp_dialog.is_visible_in_tree(), "BOSS 战中无残留营地弹层遮挡")
	duel.game_state = DuelController.FlowState.PLAYING


func _test_shop_node(duel: DuelController) -> void:
	var shop_node := _mid_node_of_type(duel, "shop")
	var n: Dictionary = _enter(duel, _prev_of(String(shop_node["id"])), 1, String(shop_node["id"]))
	_check(not n.is_empty(), "进入商店格")
	_check(duel.in_interroom, "商店格进入商店态")
	_check(duel.hud.shop_screen_is_open(), "商店抽屉已打开")
	_check(not duel.hud.board_screen.visible, "商店打开时棋盘隐藏")
	_check(duel.hud.visible, "商店打开时战斗 HUD 可见")
	var offers: Array = duel._shop_system.shop_offers
	var cfg = load("res://resources/config/shop_config.tres")
	_check(offers.size() == 6, "商店固定 6 件货架（%d）" % offers.size())
	var prices_ok := true
	var kinds := {}
	for o in offers:
		if int(o.get("price", 0)) < int(cfg.price_floor):
			prices_ok = false
		kinds[String(o.get("kind", ""))] = true
	_check(prices_ok, "货架报价不低于价格下限（展示价锁定）")
	_check(kinds.size() >= 2, "货架覆盖多类商品（金币可定向购买）")
	# G2-01：金币不足时点武器不打开替换层（避免选完旧武器才提示买不起）
	var weapon_offer := {}
	for o in offers:
		if String(o.get("kind", "")) == "weapon" and not bool(o.get("sold", false)):
			weapon_offer = o
			break
	if not weapon_offer.is_empty():
		var gold_was: int = duel.gold
		duel.gold = 0
		duel.hud.shop_screen._on_shop_card_pressed(weapon_offer)
		var dlg_open: bool = duel.hud._replace_dialog != null and duel.hud._replace_dialog.visible
		_check(not dlg_open, "金币不足时不打开替换层")
		duel.gold = gold_was
	duel._on_shop_leave_pressed()
	_check(not duel.hud.shop_screen_is_open(), "离开商店后抽屉关闭")
	_check(duel.hud.board_screen.visible, "离开商店后回到棋盘")
	_check(not duel.in_interroom, "离开商店不残留间歇态")


func _test_weapon_node(duel: DuelController) -> void:
	# 空出一把武器 → 落地直接入槽
	if duel.selected_loadout.size() >= 2:
		duel.selected_loadout.pop_back()
	var wid := String(_nodes_of(duel, "weapon")[0]["id"])
	var n: Dictionary = _enter(duel, _prev_of(wid), 1, wid)
	var item := String(n.get("item_path", ""))
	_check(not n.is_empty() and item != "", "进入武器格（具体物品 %s）" % item)
	_check(duel.selected_loadout.has(item), "武器格落地直接获得预确定武器")
	_check(duel.selected_loadout.size() == 2, "武器槽回到 2 把")
	_check(duel.hud.board_screen.visible, "武器授予后回到棋盘")
	# 满槽 → 替换弹层；取消后回棋盘，节点不重复结算
	var other := ""
	for p in duel.WEAPON_POOL:
		if not duel.selected_loadout.has(p):
			other = String(p)
			break
	if other != "":
		duel._board_weapon({"type": "weapon", "item_path": other})
		_check(duel.hud._replace_dialog != null and duel.hud._replace_dialog.visible,
			"双武器满时打开替换预览")
		duel.hud._on_replace_cancelled()
		_check(duel.hud.board_screen.visible, "取消替换后回到棋盘")
		_check(not duel.selected_loadout.has(other), "取消替换不获得武器")


func _test_charm_node(duel: DuelController) -> void:
	duel.selected_charms.clear()
	var cid := String(_nodes_of(duel, "charm")[0]["id"])
	var n: Dictionary = _enter(duel, _prev_of(cid), 1, cid)
	var item := String(n.get("item_path", ""))
	_check(not n.is_empty() and item != "", "进入护符格（具体物品 %s）" % item)
	_check(duel.selected_charms.has(item), "护符格落地入槽")
	_check(duel.hud.board_screen.visible, "护符授予后回到棋盘")
	# 护符满 3：折算金币，不越上限
	while duel.selected_charms.size() < 3:
		var extra := ""
		for p in duel.ITEM_POOL:
			var res: Resource = load(p)
			if res != null and String(res.get("category")) == "passive" and not duel.selected_charms.has(p):
				extra = String(p)
				break
		if extra == "":
			break
		duel.selected_charms.append(extra)
	var gold_before: int = duel.gold
	var another := ""
	for p in duel.ITEM_POOL:
		var res2: Resource = load(p)
		if res2 != null and String(res2.get("category")) == "passive" and not duel.selected_charms.has(p):
			another = String(p)
			break
	if another != "" and duel.selected_charms.size() >= 3:
		duel._board_charm({"type": "charm", "item_path": another})
		_check(duel.selected_charms.size() == 3, "护符上限保持 3")
		_check(duel.gold > gold_before, "护符满槽折算金币（+%d）" % (duel.gold - gold_before))
	duel.selected_charms.clear()


func _test_treasure_node(duel: DuelController) -> void:
	var t: Dictionary = _nodes_of(duel, "treasure")[0]
	var tid := String(t["id"])
	_check(int(t["depth"]) == 10 and String(t.get("title", "")) == "宝箱",
		"宝箱位于尾路首格（%s）且标题为宝箱" % tid)
	var kind := String(t.get("treasure_kind", ""))
	_check(kind in ["weapon", "charm", "active", "gold"], "宝箱类别合法（%s）" % kind)
	var desc := String(t.get("desc", ""))
	_check(desc.begins_with("宝箱 · ") and desc.find("具体物品") >= 0,
		"宝箱公开类别、不直接公开具体物品（%s）" % desc)
	if kind != "gold":
		var p := String(t.get("item_path", ""))
		_check(p != "", "宝箱具体物品已在生成时冻结（%s）" % p.get_file().get_basename())
		_check(desc.find(duel._shop_name(p, kind)) < 0, "节点文案不泄露具体物品名")

	# 同种子：宝箱位置 / 类别 / 物品可复现
	var cfg = duel.board_config
	seed(31337)
	duel.board.generate(cfg)
	var a: Dictionary = _nodes_of(duel, "treasure")[0]
	var sig := "%s|%s|%s" % [String(a["id"]), String(a.get("treasure_kind", "")),
		String(a.get("item_path", ""))]
	seed(31337)
	duel.board.generate(cfg)
	var b: Dictionary = _nodes_of(duel, "treasure")[0]
	_check(sig == "%s|%s|%s" % [String(b["id"]), String(b.get("treasure_kind", "")),
		String(b.get("item_path", ""))], "同种子宝箱位置 / 类别 / 物品可复现")
	_build_board(duel)

	# 三类授予：提示统一以「宝箱」开头，不回退成武器格/护符格文案
	var loadout_before: Array = duel.selected_loadout.duplicate()
	var charms_before: Array = duel.selected_charms.duplicate()
	var belt_before: Array = duel.consumable_slots.duplicate(true)
	var gold_before: int = duel.gold
	while duel.selected_loadout.size() >= 2:
		duel.selected_loadout.pop_back()
	var wid := ""
	for p in duel.WEAPON_POOL:
		if not duel.selected_loadout.has(p):
			wid = String(p)
			break
	if wid != "":
		duel._board_treasure({"treasure_kind": "weapon", "item_path": wid})
		_check(duel.selected_loadout.has(wid) and String(duel.board.feedback).begins_with("宝箱"),
			"宝箱武器：入槽且提示「宝箱」")
	duel.selected_charms.clear()
	var cid := ""
	for p in duel.ITEM_POOL:
		var res: Resource = load(p)
		if res != null and String(res.get("category")) == "passive":
			cid = String(p)
			break
	if cid != "":
		duel._board_treasure({"treasure_kind": "charm", "item_path": cid})
		_check(duel.selected_charms.has(cid) and String(duel.board.feedback).begins_with("宝箱"),
			"宝箱护符：入槽且提示「宝箱」")
	var aid := ""
	for p in duel.ITEM_POOL:
		var res2: Resource = load(p)
		if res2 != null and String(res2.get("category")) == "active":
			aid = String(p)
			break
	if aid != "":
		duel.consumable_slots.clear()
		duel._board_treasure({"treasure_kind": "active", "item_path": aid})
		_check(duel.consumable_slots.size() == 1 and String(duel.board.feedback).begins_with("宝箱"),
			"宝箱消耗品：入腰带且提示「宝箱」")
		while duel.consumable_slots.size() < duel.CONSUMABLE_CAP:
			duel.consumable_slots.append({"path": aid, "item_id": "", "charges": 1,
				"uid": "t%d" % duel.consumable_slots.size()})
		var gold0: int = duel.gold
		duel._board_treasure({"treasure_kind": "active", "item_path": aid})
		_check(duel.gold > gold0 and String(duel.board.feedback).find("折算金币") >= 0,
			"宝箱消耗品腰带满时折算金币（+%d）" % (duel.gold - gold0))

	duel.selected_loadout.assign(loadout_before)
	duel.selected_charms.assign(charms_before)
	duel.consumable_slots.assign(belt_before)
	duel.gold = gold_before
	duel._apply_charms()
	duel._build_pool(duel.selected_loadout)


func _test_shrine_node(duel: DuelController) -> void:
	var cfg = duel.board_config
	cfg.shape_id = "standard"
	cfg.special_id = "shrine"
	seed(6161)
	duel._loadout_system.full_reset()
	var sn: Dictionary = _nodes_of(duel, "shrine")[0]
	_check(_nodes_of(duel, "shrine").size() == 1 and _nodes_of(duel, "treasure").size() == 0,
		"固定神龛时恰好 1 个神龛、无宝箱")
	_check(int(sn["depth"]) == 10 and String(sn.get("title", "")) == "神龛",
		"神龛位于尾路首格且标题为神龛")
	var kind := String(sn.get("shrine_kind", ""))
	_check(kind in ["heal", "maxhp", "ward"], "神龛效果类型合法（%s）" % kind)
	var desc := String(sn.get("desc", ""))
	_check(desc.begins_with("神龛 · ") and desc.find("落地生效") >= 0,
		"神龛开局公开效果（%s）" % desc)

	# 同种子：位置与效果可复现
	seed(6161)
	duel.board.generate(cfg)
	var a: Dictionary = _nodes_of(duel, "shrine")[0]
	var sig := "%s|%s" % [String(a["id"]), String(a.get("shrine_kind", ""))]
	seed(6161)
	duel.board.generate(cfg)
	var a2: Dictionary = _nodes_of(duel, "shrine")[0]
	_check(sig == "%s|%s" % [String(a2["id"]), String(a2.get("shrine_kind", ""))],
		"同种子神龛位置 / 效果可复现")

	# 三类效果：沿用既有奖励数值，提示统一以「神龛」开头
	duel.player_hp_max = 100
	duel.player_hp = 40
	duel._board_shrine({"shrine_kind": "heal"})
	_check(duel.player_hp == 75 and String(duel.board.feedback).begins_with("神龛"),
		"神龛恢复 35% 最大 HP（40 → 75）")
	duel.player_hp_max = 100
	duel.player_hp = 100
	duel._board_shrine({"shrine_kind": "maxhp"})
	_check(duel.player_hp_max == 112 and duel.player_hp == 112,
		"神龛最大 HP +12 并恢复 20%（100/100 → 112/112）")
	duel._reward_system.run_shield_next = 0
	duel._board_shrine({"shrine_kind": "ward"})
	_check(duel._reward_system.run_shield_next == 15,
		"神龛给予下一场 +15 护盾（%d）" % duel._reward_system.run_shield_next)

	# 回到宝箱 + 标准骨架，后续测试沿用既有断言
	_build_board(duel)


func _test_armory_node(duel: DuelController) -> void:
	var cfg = duel.board_config
	cfg.shape_id = "standard"
	cfg.special_id = "armory"
	duel._loadout_system.full_reset()
	# full_reset 会预选默认配装且消耗随机数：测试内清空装配后再定种子，保证可复现。
	while not duel.selected_loadout.is_empty():
		duel.selected_loadout.pop_back()
	seed(7171)
	duel.board.generate(cfg)
	var ans := _nodes_of(duel, "armory")
	_check(ans.size() == 1 and _nodes_of(duel, "treasure").is_empty()
		and _nodes_of(duel, "shrine").is_empty(),
		"固定武器藏库时恰好 1 个藏库、无宝箱 / 神龛")
	var an: Dictionary = ans[0]
	_check(int(an["depth"]) == 10 and String(an.get("title", "")) == "武器藏库",
		"武器藏库位于尾路首格且标题为武器藏库")
	var paths: Array = an.get("armory_paths", [])
	_check(paths.size() == 2 and String(paths[0]) != String(paths[1]),
		"藏库冻结两把不同武器（%s）" % str(paths))
	var valid := true
	for p in paths:
		if not (String(p) in duel.WEAPON_POOL):
			valid = false
	_check(valid, "藏库候选均为武器池内合法武器")
	var desc := String(an.get("desc", ""))
	_check(desc.find("二选一") >= 0
		and desc.find(duel._shop_name(String(paths[0]), "weapon")) >= 0
		and desc.find(duel._shop_name(String(paths[1]), "weapon")) >= 0,
		"藏库开局公开两把武器名字（%s）" % desc)

	# 同种子：两把武器可复现（装配未变）
	seed(7171)
	duel.board.generate(cfg)
	var an2: Dictionary = _nodes_of(duel, "armory")[0]
	_check(str(paths) == str(an2.get("armory_paths", [])), "同种子藏库两把武器可复现")

	var arm: Dictionary = _nodes_of(duel, "armory")[0]
	var two: Array = arm.get("armory_paths", [])

	# 空槽：落地弹出二选一面板，选中直接入槽
	duel._board_armory(arm)
	_check(duel.hud._armory_dialog != null and duel.hud._armory_dialog.visible,
		"藏库落地弹出二选一面板")
	duel.hud._on_armory_pick_pressed(String(two[0]))
	_check(duel.selected_loadout.has(String(two[0]))
		and String(duel.board.feedback).begins_with("武器藏库"),
		"藏库选中武器直接入槽")
	_check(duel.board.current_id != "" and not duel.hud._armory_dialog.visible,
		"选择后面板关闭并回到棋盘")

	# 满槽：选第二把 → 接续替换弹层，替换成功
	while duel.selected_loadout.size() < duel._loadout_system.cat_cap("weapon"):
		for p in duel.WEAPON_POOL:
			if not duel.selected_loadout.has(p) and String(p) != String(two[1]):
				duel.selected_loadout.append(String(p))
				break
	var old := String(duel.selected_loadout[0])
	duel._board_armory(arm)
	duel.hud._on_armory_pick_pressed(String(two[1]))
	_check(duel.hud._replace_dialog != null and duel.hud._replace_dialog.visible,
		"武器槽满时接续替换弹层")
	duel.hud._on_replace_chosen(old)
	_check(duel.selected_loadout.has(String(two[1])) and not duel.selected_loadout.has(old),
		"替换为藏库所选武器")
	_check(String(duel.board.feedback).begins_with("武器藏库"),
		"替换提示仍以「武器藏库」开头")

	# 跳过：节点消耗，不获得武器
	var before_n: int = duel.selected_loadout.size()
	duel._board_armory(arm)
	duel.hud._on_armory_skip_pressed()
	_check(duel.selected_loadout.size() == before_n
		and String(duel.board.feedback).find("放弃选择") >= 0,
		"藏库可跳过（节点已消耗）")

	# 已持有 / 空池兜底：统一折算金币
	duel.selected_loadout[0] = String(two[0])
	var gold0: int = duel.gold
	duel._board_armory_pick(String(two[0]))
	_check(duel.gold > gold0 and String(duel.board.feedback).find("折算金币") >= 0,
		"藏库候选已持有时折算金币（+%d）" % (duel.gold - gold0))
	var gold1: int = duel.gold
	duel._board_armory({"armory_paths": []})
	_check(duel.gold > gold1 and String(duel.board.feedback).find("折算金币") >= 0,
		"藏库无候选时折算金币（+%d）" % (duel.gold - gold1))

	# 回到宝箱 + 标准骨架，后续测试沿用既有断言
	_build_board(duel)


func _test_theme_distribution(duel: DuelController) -> void:
	_build_board(duel)
	var pairs := [["n13", "n14"], ["n15", "n16"], ["n17", "n18"], ["n19", "n20"]]
	var themes_ok := true
	var desc_ok := true
	for p in pairs:
		var head: Dictionary = _node(duel, String(p[0]))
		var be := _elem(duel, String(p[1]))
		if be == "" or String(head.get("theme", "")) != be:
			themes_ok = false
		if String(head["type"]) in ["normal", "elite", "boss"]:
			var d := String(head.get("desc", ""))
			if not d.begins_with("主题：") or d.find("与 BOSS 同系") < 0:
				desc_ok = false
	_check(themes_ok, "四条尾路首战主题均与 BOSS 同元素")
	_check(desc_ok, "普通尾路首战文案前置主题说明")

	var upper_ok := true
	var prev := ""
	for id in ["n1", "n3", "n4", "n6", "n7", "n8"]:
		var e := _elem(duel, id)
		if prev != "" and e == prev:
			upper_ok = false
		prev = e
	var lower_ok := true
	prev = ""
	for id in ["n1", "n3", "n4", "n6", "n10", "n11"]:
		var e2 := _elem(duel, id)
		if prev != "" and e2 == prev:
			lower_ok = false
		prev = e2
	_check(upper_ok, "上路共享段 / 中段相邻战斗不同元素")
	_check(lower_ok, "下路共享段 / 中段相邻战斗不同元素")
	var ue := _elite_of(duel, ["n7", "n8"])
	var le := _elite_of(duel, ["n10", "n11"])
	_check(_elem(duel, "n4") != _elem(duel, ue) and _elem(duel, "n4") != _elem(duel, le),
		"同一路径两个精英不同元素（n4=%s / %s=%s / %s=%s）" % [
			_elem(duel, "n4"), ue, _elem(duel, ue), le, _elem(duel, le)])


func _elem(duel: DuelController, id: String) -> String:
	var r: RoomData = _node(duel, id).get("room")
	return String(r.element) if r != null else ""


func _elite_of(duel: DuelController, ids: Array) -> String:
	for id in ids:
		if String(_node(duel, String(id)).get("type", "")) == "elite":
			return String(id)
	return ""


func _b_elem(b, id: String) -> String:
	var r: RoomData = b.node_by_id(id).get("room")
	return String(r.element) if r != null else ""


func _b_elite(b, ids: Array) -> String:
	for id in ids:
		if String(b.node_by_id(String(id)).get("type", "")) == "elite":
			return String(id)
	return ""


func _test_battle_nodes(duel: DuelController) -> void:
	# 普通战斗
	var n: Dictionary = _enter(duel, "n0", 1, "n1")
	var r: RoomData = n.get("room")
	_check(not n.is_empty() and r != null, "进入普通战斗节点")
	_check(duel.room_index == int(n["battle_index"]), "room_index = battle_index")
	_check(duel.current_room == r, "current_room 显式指向节点 RoomData")
	_check(duel.current_room_ria == int(n["ria"]), "current_room_ria 使用节点分配值")
	_check(duel.enemy_name == r.name, "战斗敌人来自节点 RoomData")
	_check(not duel.run_final, "普通战斗不是最终战")
	_check(not duel.hud.board_screen.visible and duel.hud.visible, "战斗开始切回战斗 HUD")
	# BOSS（四条尾路任意一个）
	var bn: Dictionary = _enter(duel, "n21", 1, "n14")
	_check(not bn.is_empty(), "进入 BOSS 节点")
	_check(duel.run_final, "BOSS 节点标记 run_final")
	_check(duel._is_run_final(duel.room_index), "棋盘模式最终战判定读取 run_final")
	_check(duel.current_room_ria == 7, "BOSS 使用 ria 7")
	duel.game_state = DuelController.FlowState.PLAYING


func _test_after_victory(duel: DuelController) -> void:
	# 普通战斗胜利 → 回棋盘（不是线性间歇）
	var n: Dictionary = _enter(duel, "n0", 1, "n1")
	if not n.is_empty():
		duel.game_state = DuelController.FlowState.WON
		duel.room_flow._after_victory()
		_check(duel.hud.board_screen.visible, "非最终战胜利后回棋盘")
		_check(not duel.in_interroom, "非最终战胜利不进入线性间歇态")
	# 最终 BOSS 胜利 → 元进度三选一
	var bn: Dictionary = _enter(duel, "n21", 1, "n14")
	if not bn.is_empty():
		duel.game_state = DuelController.FlowState.WON
		duel.room_flow._after_victory()
		_check(duel.hud.meta_screen.visible, "最终 BOSS 胜利后进入元进度三选一")
		_check(not duel.hud.board_screen.visible, "最终 BOSS 结算时棋盘不遮挡")
		duel.hud.hide_meta_screen()
	duel.game_state = DuelController.FlowState.PLAYING


func _test_growth_next_room(duel: DuelController) -> void:
	_enter(duel, "n0", 1, "n1")
	_check(duel.has_next_battle(), "普通战斗后仍有下一场（成长位给出下一房对策）")
	_enter(duel, "n21", 1, "n14")
	_check(not duel.has_next_battle(), "最终 BOSS 后无下一场（成长位折算金币）")
	duel.game_state = DuelController.FlowState.PLAYING


# ---------------------------------------------------------------------------
# ⑦ 棋盘主视图布局（480×270 内、25 节点按钮、信息栏）
# ---------------------------------------------------------------------------

func _test_board_screen_ui(duel: DuelController) -> void:
	_build_board(duel)
	var scr = duel.hud.board_screen
	_check(scr != null and scr.visible, "棋盘主视图已显示")
	_check(duel.hud.visible == false, "棋盘显示时战斗 HUD 隐藏")
	_check(scr._buttons.size() == duel.board.node_count(), "棋盘视图节点按钮数 = 棋盘节点数（%d）" % duel.board.node_count())
	var in_bounds := true
	var bad_rects: Array[String] = []
	for id in scr._buttons:
		var b: Button = scr._buttons[id]
		var r := Rect2(b.position, b.size)
		if r.position.x < 0 or r.position.y < 0 or r.end.x > 480 or r.end.y > 270:
			in_bounds = false
			bad_rects.append("%s=%s" % [id, str(r)])
	_check(in_bounds, "所有节点按钮在 480×270 内%s" % ("" if bad_rects.is_empty() else "（%s）" % ", ".join(bad_rects)))
	var ab: Button = scr._advance_btn
	_check(ab.position.y + ab.size.y <= 270, "前进按钮在屏幕内（y %.0f + h %.0f）" % [ab.position.y, ab.size.y])
	_check(scr._node_title.text != "" and scr._node_desc.text != "", "节点信息栏有标题与说明")
	_check(scr._summary.text.find("武器") >= 0 and scr._summary.text.find("成长") >= 0, "右栏有当前构筑摘要")
	_check(scr._piece.position.x > 0 and scr._piece.position.y > 0, "棋子定位在当前节点")
	# 有剩余步数：按钮变「继续」，不再要求选落点
	duel.board.dice = 1
	scr.refresh()
	_check(not ab.disabled and ab.text.find("继续") >= 0, "剩余步数时显示「继续」")
	_check(scr._dice_label.text.find("1") >= 0, "显示剩余步数提示")
	duel.board.dice = 0
	scr.refresh()
	_check(ab.text.find("前进") >= 0, "步数用完后恢复「前进」")
	# BOSS 节点：按钮禁用
	duel.board.dice = 0
	duel.board.current_id = "n14"
	duel.board.consumed["n14"] = true
	scr.refresh()
	_check(ab.disabled, "BOSS 节点禁用前进按钮")
	# 战斗节点：先弹确认，由玩家点击后才开打
	_rewind(duel, "n0")
	duel.board.dice = 1
	scr._show_battle_confirm(_node(duel, "n1"))
	_check(scr._confirm_layer.visible, "落到战斗节点先弹确认层")
	_check(not duel.hud.visible, "确认前不进入战斗（棋盘仍在）")
	_check(ab.disabled, "确认期间前进按钮禁用")
	scr._on_confirm_battle()
	_check(not scr._confirm_layer.visible and duel.hud.visible, "点击确认后进入战斗")
	duel.game_state = DuelController.FlowState.PLAYING
	duel.board.current_id = "n0"

	# G4-03：武器格 tooltip 公开「替换影响」（攻击 / 命中差值，含熟练与铸式修正）
	var other := ""
	for p in duel.WEAPON_POOL:
		if not duel.selected_loadout.has(String(p)):
			other = String(p)
			break
	if other != "":
		var imp: String = scr._equip_impact({"type": "weapon", "item_path": other})
		_check(imp.find("替换") >= 0 and imp.find("攻") >= 0 and imp.find("命中") >= 0,
			"武器格 tooltip 显示替换影响（%s）" % imp.replace("\n", " / "))
	# 精英节点公开奖励方向（保底护符），不只说「进入战后成长」
	var e_desc := String(_node(duel, "n4").get("desc", ""))
	_check(e_desc.find("保底护符") >= 0, "精英节点公开奖励方向（保底护符）")


# ---------------------------------------------------------------------------
# ⑧ 完整 ACT1：棋盘移动 + 真实战斗 + 节点效果 + BOSS 结算
# ---------------------------------------------------------------------------

func _test_full_act1_run(duel: DuelController) -> void:
	seed(20261105)
	duel.board_config.enabled = true
	duel._loadout_system.full_reset()
	duel.player_hp_max = 1000000
	duel.player_hp = 1000000
	duel.game_state = DuelController.FlowState.PLAYING
	var bal: Resource = DuelController.BALANCE
	var orig_dmg: float = float(bal.player_dmg_mult)
	bal.player_dmg_mult = orig_dmg * 40.0

	var terminal := ""
	var battles := 0
	var moves := 0
	var guard := 0
	var seen_nodes := {}
	while guard < 900:
		guard += 1
		if duel.game_state == DuelController.FlowState.LOST:
			terminal = "LOST"
			break
		if duel.game_state == DuelController.FlowState.WON:
			# M1 战后成长：有成长取成长位，否则放弃本次成长。
			if duel.room_flow.post_battle_active and duel.room_flow.post_battle_has_growth():
				duel.room_flow.auto_pick_post_battle(["growth"])
			else:
				duel._on_reward_skip_pressed()
			await get_tree().process_frame
			if duel.hud.meta_screen.visible:
				terminal = "WON_GAME"
				break
			continue
		if duel.hud.board_screen.visible:
			# 棋盘待机：掷骰 → 逐格前进 → 执行节点效果。
			var b = duel.board
			if b.dice == 0:
				b.roll_dice()
			var legal: Array = b.legal_targets()
			if legal.is_empty():
				_check(false, "棋盘待机时存在合法落点")
				terminal = "NO_LEGAL"
				break
			var pick: Dictionary = legal[randi() % legal.size()]
			var node: Dictionary = b.advance_to(String(pick["id"]))
			if node.is_empty():
				_check(false, "合法落点 advance 成功")
				terminal = "ADVANCE_FAIL"
				break
			moves += 1
			seen_nodes[String(node["id"])] = true
			duel._on_board_node_entered(node)
			await get_tree().process_frame
			# 营地补给 / 商店格 / 满槽武器替换由测试立即收尾，推进下一次移动。
			if duel.hud._camp_dialog != null and duel.hud._camp_dialog.visible:
				duel._camp_leave()
			if duel.hud.shop_screen_is_open():
				duel._on_shop_leave_pressed()
			if duel.hud._replace_dialog != null and duel.hud._replace_dialog.visible:
				duel.hud._on_replace_cancelled()
			continue
		# 战斗中：打一个回合（同 smoke_root 的确定性停列节奏）。
		if duel.game_state != DuelController.FlowState.PLAYING:
			continue
		if duel.room_index >= 0 and not seen_nodes.has("battle_" + str(duel.room_index)):
			seen_nodes["battle_" + str(duel.room_index)] = true
			battles += 1
		var turn := await _play_one_turn(duel)
		if turn != "OK":
			terminal = turn
			break

	bal.player_dmg_mult = orig_dmg
	_check(terminal == "WON_GAME", "完整 ACT1 棋盘跑通至元进度（terminal=%s，移动 %d 步，战斗 %d 场）" % [terminal, moves, battles])
	_check(battles >= 1, "完整 ACT1 至少经历一场战斗通过节点入口（%d 场）" % battles)
	_check(duel.board.current_is_boss(), "完整 ACT1 最终停在某个 BOSS 节点")
	_check(duel.board.visited_count() == 13,
		"完整 ACT1 走满 13 个节点（%d）" % duel.board.visited_count())
	_check(moves == 12, "完整 ACT1 移动 12 格（%d）" % moves)
	duel.hud.hide_meta_screen()
	duel.game_state = DuelController.FlowState.PLAYING


func _play_one_turn(duel: DuelController) -> String:
	duel._on_spin_pressed()
	var waited := 0
	while waited < 900:
		if duel.reel_system.spinning:
			duel._on_spin_button_pressed()
		elif not duel._busy:
			return "OK"
		waited += 1
		await get_tree().process_frame
	return "TURN_TIMEOUT"
