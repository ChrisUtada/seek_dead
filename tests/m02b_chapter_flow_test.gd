extends Node

# M-02b 第3步：真实跨幕流程接入验收（线性模式 ACT1→2→3）。
# 验证：
# ① 每幕首个战斗房前显示章节头一次，确认后锻魂+进对房（act 正确）；
# ② 快速跳过只跳过展示，锻魂与房间初始化照常；
# ③ 重复输入/重复确认不双发、不重复进房、RNG 不偏移；
# ④ 真·最终 Boss 房不弹普通幕章节头；
# ⑤ 跨局重置清空显示记录。
# 隔离 APPDATA 运行。

const DUEL_SCENE := "res://scenes/duel/duel.tscn"

var _checks := 0
var _fails := 0
var _duel = null

func _ready() -> void:
	await _run()
	print("M02BFLOW|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("M02BFLOW|FAIL|" + msg)

func _boot() -> void:
	var scene: PackedScene = load(DUEL_SCENE)
	_duel = scene.instantiate()
	add_child(_duel)
	for i in 3:
		await get_tree().process_frame
	_duel.demo_config.enabled = false
	_duel.demo_config.act_only = false
	_duel._confirm_loadout()
	for i in 3:
		await get_tree().process_frame
	_duel.reel_system._timer.stop()

# 找 act 从 from_act 变到更大值的边界下标（ROOMS 线性序列中第一房属于新幕）
func _first_idx_of_act(act: int) -> int:
	for i in range(_duel.ROOMS.size()):
		if int((_duel.ROOMS[i] as RoomData).act) == act:
			return i
	return -1

func _last_idx_before_act(act: int) -> int:
	var first := _first_idx_of_act(act)
	return first - 1 if first > 0 else -1

func _reset_chapter() -> void:
	_duel._chapter_shown_acts.clear()
	_duel._chapter_pending_next_idx = -1
	if _duel._chapter_intro != null:
		_duel._chapter_intro.reset_shown()
		_duel._chapter_intro.hide()

func _run() -> void:
	await _boot()
	var rooms = _duel.ROOMS
	print("M02BFLOW|INFO rooms=%d acts=%s" % [rooms.size(), str(_act_seq())])

	# --- R2：ACT1 开局路径（_confirm_loadout 后已显示并记录，不阻塞进房） ---
	_check(_duel._chapter_intro.visible, "ACT1 开局显示章节头")
	_check(_duel._chapter_shown_acts.has(1), "ACT1 记为已显示")
	_check(_duel._chapter_pending_next_idx == -1, "ACT1 不设 pending（不阻塞进房）")

	# --- R1：章节头可见时全局空格必须被吞掉，不得隔着屏开转 ---
	var ev_space := InputEventKey.new()
	ev_space.pressed = true
	ev_space.keycode = KEY_SPACE
	_duel._input(ev_space)
	_check(not _duel.reel_system.spinning, "章节头可见时空格不开转")

	# 确认后关闭且不重置当前房（ACT1 开局路径，不是跨幕路径）
	_duel._chapter_intro.continue_btn.pressed.emit()
	_check(not _duel._chapter_intro.visible, "ACT1 开局确认后关闭")
	_check(_duel.room_index == 0, "ACT1 开局确认不重置当前房")

	# --- ① ACT1 -> ACT2：章节头在跨幕首房前显示，确认后锻魂+进对房 ---
	_reset_chapter()
	var a2first := _first_idx_of_act(2)
	_check(a2first > 0, "存在 ACT2 首房下标（%d）" % a2first)
	if a2first > 0:
		# 摆到 ACT1 最后一房，current_act=1，模拟清完上一房的间歇态
		_duel.room_index = a2first - 1
		_duel.current_act = 1
		_duel.in_interroom = true
		var rng0 := int(_duel._reward_system._loot.seed_value())
		# 触发下一房
		_duel._on_next_room_pressed()
		_check(_duel._chapter_intro.visible, "跨幕：章节头显示")
		_check(_duel._chapter_pending_next_idx == a2first, "待进房下标暂存正确")
		_check(_duel.room_index == a2first - 1, "显示期间未提前进房")
		_check(int(_duel._reward_system._loot.seed_value()) == rng0, "显示章节头不耗 RNG")
		# 章节头 Boss 名 = 本局 ROOMS 中该幕 Boss（防 D1 回归）
		var run_boss_name := ""
		for r in _duel.ROOMS:
			if r is RoomData and int(r.act) == 2 and String(r.kind) == "boss" and not bool(r.final_boss):
				run_boss_name = String(r.name)
				break
		var shown_boss_text := ""
		if _duel._chapter_intro.boss_info != null:
			for c in _duel._chapter_intro.boss_info.get_children():
				if c is Label:
					shown_boss_text += String(c.text) + "\n"
		_check(shown_boss_text.contains(run_boss_name), "章节头 Boss 名=本局 ACT2 Boss（%s）" % run_boss_name)
		# F4 新增：挂起期间二次触发不得绕过章节头进房
		var idx0: int = int(_duel._chapter_pending_next_idx)
		var room0: int = int(_duel.room_index)
		var granted_before_dup: int = int((_duel.growth.granted_acts as Dictionary).size())
		_duel._on_next_room_pressed()   # 二次触发
		_check(int(_duel.room_index) == room0, "挂起期间二次触发不进房")
		_check(int(_duel._chapter_pending_next_idx) == idx0, "pending 未被二次触发改写")
		_check(_duel._chapter_intro.visible, "章节头仍挂着")
		_check(int((_duel.growth.granted_acts as Dictionary).size()) == granted_before_dup, "挂起期间二次触发不发锻魂")
		# 确认
		var granted0: int = int((_duel.growth.granted_acts as Dictionary).size())
		_duel._chapter_intro.continue_btn.pressed.emit()
		_check(not _duel._chapter_intro.visible, "确认后章节头关闭")
		_check(_duel.room_index == a2first, "确认后进入 ACT2 首房")
		_check(int(_duel.current_act) == 2, "current_act 更新为 2")
		_check(int((_duel.growth.granted_acts as Dictionary).size()) == granted0 + 1, "确认后幕间锻魂发放一次")
		# 同幕再次跨幕入口（模拟重复点击）不应再弹章节头
		_reset_chapter_keep_shown()
		_duel.in_interroom = true
		_duel.room_index = a2first
		_duel._on_next_room_pressed()
		_check(not _duel._chapter_intro.visible, "同幕重复跨幕入口不重复弹章节头（幂等）")

	# --- ② ACT2 -> ACT3：快速跳过只跳过展示，锻魂+进房照常 ---
	_reset_chapter()
	var a3first := _first_idx_of_act(3)
	_check(a3first > 0, "存在 ACT3 首房下标（%d）" % a3first)
	if a3first > 0:
		_duel.room_index = a3first - 1
		_duel.current_act = 2
		_duel.in_interroom = true
		var granted1: int = int((_duel.growth.granted_acts as Dictionary).size())
		_duel._on_next_room_pressed()
		_check(_duel._chapter_intro.visible, "ACT2→3：章节头显示")
		# 快速跳过（按键）→ 只关闭展示
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.keycode = KEY_SPACE
		_duel._chapter_intro._unhandled_input(ev)
		_check(not _duel._chapter_intro.visible, "快速跳过关闭展示")
		_check(_duel.room_index == a3first, "快速跳过仍进入 ACT3 首房")
		_check(int(_duel.current_act) == 3, "快速跳过后 current_act=3")
		_check(int((_duel.growth.granted_acts as Dictionary).size()) == granted1 + 1, "快速跳过仍发放幕间锻魂")

	# --- ③ 重复确认不双发 ---
	_reset_chapter()
	var a3f := _first_idx_of_act(3)
	if a3f > 1:
		_duel.room_index = a3f - 1
		_duel.current_act = 2
		_duel.in_interroom = true
		_duel._on_next_room_pressed()
		var rng_before := int(_duel._reward_system._loot.seed_value())
		# 连续多次确认
		_duel._on_chapter_intro_continued(3)
		_duel._on_chapter_intro_continued(3)
		_duel._chapter_intro.continue_btn.pressed.emit()
		_check(_duel.room_index == a3f, "重复确认只进房一次（下标正确）")
		_check(int(_duel._reward_system._loot.seed_value()) == rng_before, "重复确认不额外耗 RNG")

	# --- ④ 真·最终 Boss 房不弹章节头 ---
	_reset_chapter()
	var final_idx := -1
	for i in range(_duel.ROOMS.size()):
		if int((_duel.ROOMS[i] as RoomData).act) == 3 and bool((_duel.ROOMS[i] as RoomData).final_boss):
			final_idx = i
			break
	if final_idx > 0:
		_duel.room_index = final_idx - 1
		_duel.current_act = 3
		_duel.in_interroom = true
		_duel._on_next_room_pressed()
		_check(not _duel._chapter_intro.visible, "真·最终 Boss 房不弹普通幕章节头")

	# --- ⑤ 跨局重置 ---
	_duel._chapter_shown_acts[1] = true
	_duel._chapter_pending_next_idx = 5
	_duel._reset_run_state()
	_check(_duel._chapter_shown_acts.is_empty(), "跨局重置清空章节头显示记录")
	_check(_duel._chapter_pending_next_idx == -1, "跨局重置清空待进房下标")
	_check(not _duel._chapter_intro.visible, "跨局重置隐藏章节头")

	_duel.queue_free()
	await get_tree().process_frame

# 保留 shown 记录但清 pending/隐藏，用于测同幕幂等
func _reset_chapter_keep_shown() -> void:
	_duel._chapter_pending_next_idx = -1
	if _duel._chapter_intro != null:
		_duel._chapter_intro.hide()

func _act_seq() -> Array:
	var seq := []
	var last := -1
	for r in _duel.ROOMS:
		var a := int((r as RoomData).act)
		if a != last:
			seq.append(a)
			last = a
	return seq
