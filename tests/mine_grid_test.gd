extends Node

# ============================================================================
# 扫雷棋盘 Step 1 · 固定 4×4 内容灰盒 headless 回归（2026-11-10）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/mine_grid_test.tscn
#
# 覆盖（Step 1 出口）：
# ① 16 格完整、4×4 坐标唯一、四方向邻接对称、全图从起点可达（无孤立格）；
# ② 内容数量：起点 1 / 普通 6 / 精英 1 / BOSS 1 / 武器 2 / 护符 1 / 商店 2 / 休整 2；
# ③ BOSS 与精英开局可见；装备目标开局可见且具体物品已冻结；普通怪身份保持未知；
# ④ 战斗节点均已冻结 RoomData，类型与 kind 一致；装备路径真实存在；
# ⑤ 起点有安全/低风险首选格；BOSS 在右下、起点在左上；
# ⑥ 同 seed 生成结果完全一致；生成不消耗全局 RNG、不写 meta / 装配；
# ⑦ 不接入移动与数字：所有格 number = -1。
# 测试结束还原 meta（smoke 已把 APPDATA 指向临时目录）。
# ============================================================================

const GRID = preload("res://scripts/board/board_grid.gd")
const NODE = preload("res://scripts/board/board_node_data.gd")

const EXPECTED := {
	"start": 1,
	"normal": 6,
	"elite": 1,
	"boss": 1,
	"weapon": 2,
	"charm": 1,
	"shop": 2,
	"rest": 2,
}

var _checks := 0
var _fails := 0


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
	var loadout_backup: Array = duel.selected_loadout.duplicate()
	var meta_before := JSON.stringify(duel.meta)
	var layout_was := String(duel.board_config.layout_mode)
	var grid_seed_was := int(duel.board_config.grid_seed)
	var enabled_was := bool(duel.board_config.enabled)
	var acts_was := int(duel.board_config.acts)

	var grid = GRID.new(duel)
	var data: Dictionary = grid.generate(1, 20261110)
	var by_id: Dictionary = data["by_id"]

	# ① 结构与连通
	var errs: Array = grid.validate(data)
	_check(errs.is_empty(), "validate 无错误" + ("" if errs.is_empty() else "：%s" % str(errs)))
	_check(data["nodes"].size() == 16, "16 格")
	_check(data["rows"] == 4 and data["cols"] == 4, "4×4")
	_check(_degree_sum(data) == 48, "四方向邻接总度 48（4×4 网格）")
	_check(_all_symmetric(data), "邻接对称")
	_check(_reachable_count(data) == 16, "全图从起点可达（无孤立格）")
	_check(String(data["start_id"]) == "g00", "起点在左上 (0,0)")
	_check(String(data["boss_id"]) == "g33", "BOSS 在右下 (3,3)")

	# ② 内容数量
	var tally := _tally(data)
	for t in EXPECTED:
		_check(int(tally.get(t, 0)) == int(EXPECTED[t]),
			"类型 %s = %d" % [t, int(EXPECTED[t])])
	var battle_count := int(tally.get("normal", 0)) + int(tally.get("elite", 0)) + int(tally.get("boss", 0))
	_check(battle_count == 8, "战斗节点 8（6 普通 + 1 精英 + 1 BOSS）")

	# ③ 开局可见性
	var boss: Dictionary = by_id["g33"]
	var elite: Dictionary = by_id[String(data["elite_id"])]
	_check(bool(boss["visible"]) and bool(boss["revealed"]), "BOSS 开局可见")
	_check(bool(elite["visible"]) and bool(elite["revealed"]), "精英开局可见")
	for id in data["weapon_ids"]:
		var n: Dictionary = by_id[String(id)]
		_check(bool(n["visible"]) and bool(n["revealed"]), "武器 %s 开局可见" % id)
		_check(String(n["item_path"]) != "", "武器 %s 具体物品已冻结" % id)
	var charm: Dictionary = by_id[String(data["charm_id"])]
	_check(bool(charm["visible"]) and bool(charm["revealed"]), "护符开局可见")
	_check(String(charm["item_path"]) != "", "护符具体物品已冻结")
	var hidden_normals := 0
	for n in data["nodes"]:
		if String(n["type"]) == "normal":
			hidden_normals += 1
			_check(not bool(n["visible"]) and not bool(n["revealed"]), "普通怪 %s 身份保持未知" % n["id"])
			_check(n["room"] != null, "普通怪 %s 已冻结房间" % n["id"])
	_check(hidden_normals == 6, "6 个普通怪身份隐藏")
	# Step 4：每张棋盘至少放入 3 只带早期特性的普通怪样板（4 选 3，同 seed 可复现）。
	var trait_normals := 0
	for n in data["nodes"]:
		if String(n["type"]) != "normal":
			continue
		var room: RoomData = n.get("room")
		if room != null and room.gimmick_script != null:
			trait_normals += 1
	_check(trait_normals >= 3, "棋盘至少出现 3 只普通怪特性样板（%d）" % trait_normals)

	# ④ 战斗房与装备内容
	var room_paths := {}
	for n in data["nodes"]:
		var t := String(n["type"])
		if NODE.is_battle(t):
			var room: RoomData = n["room"]
			_check(room != null and String(room.kind) == t, "%s 房间 kind 与类型一致" % n["id"])
			if room != null:
				room_paths[room.resource_path] = true
			_check(int(n["ria"]) >= 0, "%s ria 已冻结" % n["id"])
	_check(room_paths.size() == 8, "8 个战斗房互不重复")
	_check(int(boss["ria"]) == 7, "BOSS ria = 7")
	for id in data["weapon_ids"]:
		var wd: WeaponData = load(String(by_id[String(id)]["item_path"]))
		_check(wd != null and wd.weapon_name != "", "武器 %s 可加载" % id)
	var cd: ItemData = load(String(charm["item_path"]))
	_check(cd != null and String(cd.category) == "passive", "护符为 passive 且可加载")

	# ⑤ 起点安全格 + 邻接规则
	var safe := false
	for nx in by_id["g00"]["next"]:
		if not NODE.is_battle(String(by_id[String(nx)]["type"])):
			safe = true
	_check(safe, "起点有安全/低风险首选格")
	_check(String(by_id["g01"]["type"]) == "weapon", "起点右侧是武器目标（安全首选）")
	_check((elite["next"] as Array).size() == 4, "精英位于内部格，四邻接")

	# ⑥ 冻结与确定性
	var data2: Dictionary = grid.generate(1, 20261110)
	_check(_signature(data) == _signature(data2), "同 seed 生成结果完全一致")
	seed(424242)
	var expected_roll := randi()
	seed(424242)
	grid.generate(1, 7)
	var actual_roll := randi()
	_check(expected_roll == actual_roll, "生成不消耗全局 RNG")
	_check(JSON.stringify(duel.meta) == meta_before, "生成不写 meta")
	_check(duel.selected_loadout.size() == loadout_backup.size(), "生成不改装配")

	# ⑦ Step 1 不接数字/移动
	var all_minus_one := true
	for n in data["nodes"]:
		if int(n["number"]) != -1:
			all_minus_one = false
	_check(all_minus_one, "内容层 number = -1（数字由 BoardSystem 实时计算）")
	_check(grid.ascii_map(data).split("\n").size() == 4, "文本地图 4 行")

	# ⑧ Step 2：BoardSystem 4×4 运行态（数字 / 揭示 / 一次性结算）
	_build_grid_board(duel)
	var b = duel.board
	_check(duel.node_mode and b.grid_mode, "本局切换到 4×4 扫雷棋盘")
	_check(b.node_count() == 16 and b.boss_ids.size() == 1, "16 格 / 唯一 BOSS")
	_check(b.current_id == "g00" and b.is_consumed("g00") and b.is_revealed("g00"),
		"起点已揭示且作为当前位置")
	_check(not b.can_roll() and b.roll_dice() == 0 and not b.has_steps(), "网格不掷骰")
	var expect_numbers := {
		"g00": 1, "g01": 1, "g02": 0, "g03": 2,
		"g10": 1, "g11": 2, "g12": 2, "g13": 0,
		"g20": 2, "g21": 2, "g22": 1, "g23": 1,
		"g30": 2, "g31": 1, "g32": 1, "g33": 0,
	}
	for id in expect_numbers:
		_check(b.number_of(id) == int(expect_numbers[id]),
			"数字 %s = %d" % [id, int(expect_numbers[id])])
	var rev_count := 0
	for n in b.nodes:
		if b.is_revealed(String(n["id"])):
			rev_count += 1
	_check(rev_count == 10, "开局揭示 10 格（起点/精英/BOSS/装备/商店/休整）")
	_check(not b.is_revealed("g10"), "普通怪 g10 身份未揭示")
	_check(b.legal_targets().size() == 2, "起点可进入两个相邻格")
	_check(b.advance_to("g33").is_empty(), "非相邻格不能直接进入")
	var w1: Dictionary = b.advance_to("g01")
	_check(not w1.is_empty() and b.current_id == "g01" and not b.last_move_revisit,
		"进入相邻武器格并揭示")
	_check(b.is_consumed("g01") and b.is_revealed("g01"), "武器格已消耗且已揭示")
	var back: Dictionary = b.advance_to("g00")
	_check(not back.is_empty() and b.last_move_revisit, "已消耗格只移动、标记为回访")
	var fight: Dictionary = b.advance_to("g10")
	_check(String(fight.get("type", "")) == "normal" and b.is_revealed("g10"),
		"进入普通怪格并揭示身份")
	_check(b.number_of("g00") == 1 and b.number_of("g11") == 2, "击败前数字保持")
	b.note_battle_won()
	_check(b.is_defeated("g10"), "普通怪胜利后标记已击败")
	_check(b.number_of("g00") == 0, "相邻数字移除已击败普通怪（g00 1→0）")
	_check(b.number_of("g11") == 1 and b.number_of("g20") == 1, "相邻数字同步更新（g11/g20 2→1）")
	var snap: Dictionary = b.numbers_snapshot()
	_check(snap.size() == 16, "数字快照覆盖 16 格")
	b.advance_to("g11")
	var revisit: Dictionary = b.advance_to("g10")
	_check(not revisit.is_empty() and b.last_move_revisit, "已击败格可再次经过")
	_check(b.number_of("g00") == 0 and b.number_of("g11") == 1, "回访不重复结算 / 不改数字")
	b.note_battle_won()
	_check(b.number_of("g00") == 0, "胜利标记幂等")
	_check(b.route_length() == 16 and b.progress_text().find("16") >= 0, "进度按 16 格显示")
	_check(_signature(data) == _signature(b._grid_data), "揭示 / 移动 / 击败不重抽内容")

	# ⑨ Step 2 UI：网格视图 / 未知格不泄露 / 悬停高亮 / 确认后再战斗
	_build_grid_board(duel)
	b = duel.board
	var scr = duel.hud.board_screen
	_check(scr != null and scr.visible, "4×4 棋盘视图已显示")
	_check(scr._buttons.size() == 16, "16 个透明热区")
	_check(not scr._advance_btn.visible, "网格隐藏「前进」按钮")
	_check(scr._dice_label.text.find("数字") >= 0, "底栏说明数字含义")
	_check(scr._node_title.text == "起点", "信息栏默认显示起点")
	var in_bounds := true
	for id in scr._buttons:
		var rect := Rect2((scr._buttons[id] as Button).position, (scr._buttons[id] as Button).size)
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > 480 or rect.end.y > 270:
			in_bounds = false
	_check(in_bounds, "所有格热区在 480×270 内")
	scr._on_node_hover("g10")
	_check(scr._node_title.text == "未知格", "未揭示普通怪显示「未知格」")
	_check(scr._node_desc.text.find("数字 1") >= 0, "信息栏显示数字含义")
	_check(scr._buttons["g10"].tooltip_text.find("未知格") >= 0, "tooltip 不泄露未知格身份")
	_check(scr._buttons["g10"].tooltip_text.find("数字 1") >= 0, "tooltip 显示数字")
	scr._on_node_hover("g33")
	var boss_room: RoomData = b.node_by_id("g33")["room"]
	_check(scr._node_title.text == String(boss_room.name), "BOSS 开局可见（信息栏显示名称）")
	scr._on_node_pressed("g33")
	_check(b.current_id == "g00", "点击非相邻格只查看、不移动")
	await scr._advance_to("g10")
	_check(b.current_id == "g10" and b.is_revealed("g10"), "点击相邻未知格进入并揭示")
	_check(scr._confirm_layer.visible and String(scr._pending_node.get("id", "")) == "g10",
		"普通怪先弹战斗确认")
	scr._pending_node = {}
	scr._confirm_layer.visible = false
	b.return_to_board()
	_check(b.is_defeated("g10") and b.number_of("g00") == 0, "胜利回棋盘后数字更新")
	await scr._advance_to("g00")
	_check(b.last_move_revisit and b.current_id == "g00", "点击已探索格只移动")
	_check(not scr._confirm_layer.visible, "回访不重复弹确认 / 结算")
	# 装备格按既有规则结算：未满直接入队；已满弹既有替换层（可取消，节点已消耗）。
	var wpath := String(b.node_by_id("g01")["item_path"])
	var cap_w := int(duel._loadout_system.cat_cap("weapon"))
	var full_before := duel.selected_loadout.size() >= cap_w
	await scr._advance_to("g01")
	if full_before:
		_check(duel.hud._replace_dialog != null and duel.hud._replace_dialog.visible,
			"武器槽已满时弹出既有替换层")
		if duel.hud._replace_cancel_cb.is_valid():
			duel.hud._replace_cancel_cb.call()
	else:
		_check(duel.selected_loadout.has(wpath), "武器格按既有规则加入转轮带")
	_check(b.is_consumed("g01") and not b.last_move_revisit, "武器格进入即消耗")
	var loadout_sig := str(duel.selected_loadout) + str(duel.selected_charms)
	await scr._advance_to("g00")
	await scr._advance_to("g01")
	_check(str(duel.selected_loadout) + str(duel.selected_charms) == loadout_sig,
		"再次进入装备格不重复获得")
	_check(_signature(data) == _signature(b._grid_data), "整段探索不重抽内容")

	# ⑩ Step 3：BOSS 确认层 / 精英预告 / 查看构筑 / 二次确认撤回
	_build_grid_board(duel)
	b = duel.board
	scr = duel.hud.board_screen
	_teleport(duel, "g23")   # BOSS 正上方商店格，直接相邻
	var snap_pre: Dictionary = b.numbers_snapshot()
	var visited_pre: int = int(b.visited_count())
	_check(b.defeated.size() == 0, "零击败也可挑战 BOSS（无收集率门票）")
	scr._on_node_pressed("g33")
	_check(scr._confirm_layer.visible and String(scr._pending_node.get("id", "")) == "g33",
		"点击 BOSS 打开确认层")
	_check(b.current_id == "g23" and not b.is_consumed("g33"),
		"确认层不移动 / 不消耗 BOSS 格")
	_check(scr._confirm_alt_btn.visible and scr._confirm_alt_btn.text == "继续探索",
		"BOSS 确认层提供「继续探索」")
	_check(scr._confirm_btn.text == "挑战 BOSS", "BOSS 确认层提供「挑战 BOSS」")
	_check(scr._confirm_stats.text.find("弱点") >= 0, "BOSS 预览显示真实弱点")
	boss_room = b.node_by_id("g33")["room"]
	_check(scr._confirm_enemy.text == String(boss_room.name), "BOSS 预览显示名称")
	scr._on_confirm_alt()
	_check(not scr._confirm_layer.visible and b.current_id == "g23", "继续探索：留在原格")
	_check(not b.is_consumed("g33") and b.defeated.size() == 0,
		"继续探索不消耗 BOSS / 不推进敌人")
	_check(str(b.numbers_snapshot()) == str(snap_pre) and b.visited_count() == visited_pre,
		"继续探索不改数字 / 进度")
	# 提前挑战：从一个相邻格直接开战，不需要击败任何普通怪。
	scr._on_node_pressed("g33")
	scr._on_confirm_battle()
	await get_tree().create_timer(0.4).timeout
	_check(b.current_id == "g33" and b.is_consumed("g33"), "挑战 BOSS：进入并消耗 BOSS 格")
	_check(not scr.visible, "挑战后进入战斗（棋盘收起）")
	b.return_to_board()
	_check(b.is_defeated("g33"), "BOSS 胜利后标记已击败")

	# 精英：点击相邻精英先看战利品与邻近目标，返回不消耗；挑战才进入。
	_teleport(duel, "g13")
	scr._on_node_pressed("g12")
	_check(scr._confirm_layer.visible and b.current_id == "g13" and not b.is_consumed("g12"),
		"点击精英先开预览，不移动 / 不消耗")
	_check(scr._confirm_alt_btn.visible and scr._confirm_alt_btn.text == "返回探索",
		"精英确认层提供「返回探索」")
	_check(scr._confirm_btn.text == "挑战精英", "精英确认层提供「挑战精英」")
	_check(scr._confirm_stats.text.find("战利品") >= 0 and scr._confirm_stats.text.find("高品质") >= 0,
		"精英预览显示高品质战利品")
	_check(scr._confirm_stats.text.find("邻近目标") >= 0 and scr._confirm_stats.text.find("武器「") >= 0,
		"精英预览显示邻近装备目标")
	scr._on_confirm_alt()
	_check(b.current_id == "g13" and not b.is_consumed("g12"), "返回探索不消耗精英格")
	scr._on_node_pressed("g12")
	scr._on_confirm_battle()
	await get_tree().create_timer(0.4).timeout
	_check(b.current_id == "g12" and b.is_consumed("g12"), "挑战精英：进入并消耗精英格")
	b.return_to_board()
	_check(b.is_defeated("g12"), "精英胜利后标记已击败")
	_teleport(duel, "g13")
	scr._on_node_pressed("g12")
	_check(b.current_id == "g12" and not scr._confirm_layer.visible,
		"已击败精英只移动 / 不重复开战")
	await get_tree().create_timer(0.25).timeout   # 等移动动画结束（按钮在移动中禁用）

	# 查看构筑：只读、含武器与符号，不改地图 / 数字，不消耗 RNG。
	var sig_before := _signature(data)
	var nums_before := str(b.numbers_snapshot())
	var hp_before := int(duel.player_hp)
	seed(90210)
	var rng_a := randi()
	seed(90210)
	scr._on_build_pressed()
	_check(scr._build_layer.visible, "查看构筑打开只读弹层")
	_check(scr._build_text.text.find("武器：") >= 0 and scr._build_text.text.find("转轮符号") >= 0,
		"构筑列出武器与转轮符号")
	if not duel.selected_loadout.is_empty():
		var wp := duel._shop_name(String(duel.selected_loadout[0]), "weapon")
		_check(scr._build_text.text.find(wp) >= 0, "构筑显示当前武器名")
	scr._on_build_closed()
	var rng_b := randi()
	_check(rng_a == rng_b, "查看构筑不消耗全局 RNG")
	_check(not scr._build_layer.visible, "关闭后返回棋盘")
	_check(_signature(data) == sig_before and str(b.numbers_snapshot()) == nums_before,
		"查看构筑不改地图 / 数字")
	_check(int(duel.player_hp) == hp_before, "查看构筑不改 HP")

	# 撤回整备：必须两次确认；取消不改变任何状态。
	var loadout_before := str(duel.selected_loadout)
	scr._on_retreat_pressed()
	_check(scr._retreat_layer.visible, "撤回打开第一次确认")
	_check(scr._retreat_text.text.find("撤回整备") >= 0 or scr._retreat_text.text.find("撤回") >= 0,
		"第一次确认说明代价")
	scr._on_retreat_cancel()
	_check(not scr._retreat_layer.visible, "取消撤回关闭弹层")
	_check(b.current_id == "g12" and int(duel.player_hp) == hp_before
		and str(duel.selected_loadout) == loadout_before, "取消撤回不改当前格 / HP / Build")
	scr._on_retreat_pressed()
	scr._on_retreat_confirm()
	_check(scr._retreat_text.text.find("再次确认") >= 0, "必须先过第二次确认")
	_check(str(duel.selected_loadout) == loadout_before, "第一次确认不改 Build")
	scr._on_retreat_cancel()
	_check(b.current_id == "g12" and scr.visible
		and String(duel._journal._data.get("result", "")) != "retreat", "二次确认前取消仍在本局")
	scr._on_retreat_pressed()
	scr._on_retreat_confirm()
	_check(scr._retreat_next_btn.text == "确认撤回", "第二次按钮变为「确认撤回」")
	scr._on_retreat_confirm()
	_check(String(duel._journal._data.get("result", "")) == "retreat", "终局原因记录为主动撤回")
	_check(duel.hud.loadout_screen != null and duel.hud.loadout_screen.visible, "撤回后回到整备页")
	_check(not scr.visible, "撤回后棋盘收起")

	# 还原
	duel.board_config.enabled = enabled_was
	duel.board_config.acts = acts_was
	duel.board_config.layout_mode = layout_was
	duel.board_config.grid_seed = grid_seed_was
	duel.meta.clear()
	for k in meta_backup:
		duel.meta[k] = meta_backup[k]
	duel._meta_store.save_meta()

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


# 测试内把当前位置移到指定格（只改公开运行状态，不结算 / 不重抽）。
func _teleport(duel: DuelController, id: String) -> void:
	var b = duel.board
	b.current_id = id
	b.consumed[id] = true
	b.revealed[id] = true
	b.last_move_revisit = false
	var scr = duel.hud.board_screen
	scr._pending_node = {}
	scr._confirm_layer.visible = false
	scr._selected_id = id
	scr.refresh()


# 以 4×4 网格重新开一局（full_reset 内部 board.generate 直接走 grid 分支）。
func _build_grid_board(duel: DuelController) -> void:
	duel.board_config.enabled = true
	duel.board_config.acts = 1
	duel.board_config.layout_mode = "grid4x4"
	duel.board_config.grid_seed = 20261110
	duel._loadout_system.full_reset()


func _boot() -> DuelController:
	var scene: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.board_config.enabled = false
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


func _tally(data: Dictionary) -> Dictionary:
	var out := {}
	for n in data["nodes"]:
		var t := String(n["type"])
		out[t] = int(out.get(t, 0)) + 1
	return out


func _degree_sum(data: Dictionary) -> int:
	var total := 0
	for n in data["nodes"]:
		total += (n["next"] as Array).size()
	return total


func _all_symmetric(data: Dictionary) -> bool:
	var by_id: Dictionary = data["by_id"]
	for n in data["nodes"]:
		for nx in n["next"]:
			var tgt: Dictionary = by_id.get(String(nx), {})
			if tgt.is_empty() or not (String(n["id"]) in (tgt["next"] as Array)):
				return false
	return true


func _reachable_count(data: Dictionary) -> int:
	var by_id: Dictionary = data["by_id"]
	var seen := {}
	var stack: Array = [String(data["start_id"])]
	while not stack.is_empty():
		var id: String = stack.pop_back()
		if seen.has(id):
			continue
		seen[id] = true
		for nx in by_id[id]["next"]:
			stack.append(String(nx))
	return seen.size()


func _signature(data: Dictionary) -> String:
	var parts: Array[String] = []
	for n in data["nodes"]:
		var room_path := ""
		if n.get("room") != null:
			room_path = String((n["room"] as RoomData).resource_path)
		parts.append("%s|%s|%s|%s" % [n["id"], n["type"], room_path, String(n.get("item_path", ""))])
	return "\n".join(parts)
