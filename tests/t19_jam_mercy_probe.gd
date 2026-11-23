extends Node

# T1.9 第 1 步：jam 真实接入与来源区分只读探针（不改生产代码）。
# 验证：
# ① 敌人注废列(pending_jam_reel)按停落点为 TRASH_SYMBOL，且不进入 mercy 分支(mercy_used 不增加)；
# ② 建带层 MISS_SYMBOL(精度未命中) 与 TRASH_SYMBOL(敌人注入) 资源身份可区分；
# ③ 玩家按停落在精度 MISS 格时 mercy 当前会触发(证明旧语义对两类来源一视同仁)。

var _checks := 0
var _fails := 0

func _ready() -> void:
	await _run()
	print("T19JAM|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0)   # 探针恒 0 退出，仅打印

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
	print("T19JAM|%s|%s" % ["PASS" if cond else "FAIL", msg])

func _boot() -> DuelController:
	var scene: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.board_config.enabled = false
	duel.selected_consumables.clear()
	duel.selected_charms.clear()
	duel.selected_skills.clear()
	duel._confirm_loadout()
	await get_tree().process_frame
	return duel

func _grant_mercy(duel: DuelController) -> void:
	duel.reel_controls["mercy"] = true

func _run() -> void:
	var duel := await _boot()
	var rs := duel.reel_system
	rs._timer.stop()
	duel.pending_jam_reel = -1
	duel.pending_lock_reel = -1
	duel.pending_chaos = false
	duel.pending_auto_stop = false
	_grant_mercy(duel)

	# ② 建带层身份：两种废铁资源路径不同
	var miss_path := "res://resources/symbols/miss.tres"
	var trash_path := "res://resources/symbols/trash.tres"
	_check(miss_path != trash_path, "两种废铁资源路径不同")
	var miss_obj = load(miss_path)
	var trash_obj = load(trash_path)
	_check(miss_obj != trash_obj, "MISS_SYMBOL 与 TRASH_SYMBOL 是不同资源对象")
	_check(String(miss_obj.kind) == "trash" and String(trash_obj.kind) == "trash", "两者 kind 同为 trash（旧代码按 kind 抹平）")

	# ① jam 真实接入：设置 jam 列，按停，观察落点与 mercy_used
	duel.pending_jam_reel = 0
	rs.reel_stopped.assign([false, true, true])
	rs._pending_stops.clear()
	var gold_before := duel.gold
	var mercy_before: int = duel.readability.mercy_used
	rs.stop_next_reel(false, "player")   # 应锁第 0 列（jam 列）
	await get_tree().create_timer(0.35).timeout   # 等吸附 tween 完成落子
	var land_sym = duel.grid[0][0]
	var land_path := String(land_sym.resource_path) if land_sym != null else ""
	print("T19JAM|INFO jam land path=%s gold_delta=%d mercy_delta=%d" % [
		land_path, duel.gold - gold_before, duel.readability.mercy_used - mercy_before])
	_check(land_path == trash_path, "jam 列按停落点为 TRASH_SYMBOL")
	_check(duel.readability.mercy_used == mercy_before, "jam 列不进入 mercy 分支（mercy_used 不变）")
	_check(duel.gold == gold_before, "jam 列不触发 mercy 的 +2 金")

	# ③ 玩家按停落在精度 MISS 格：当前 mercy 语义会触发
	duel.pending_jam_reel = -1
	duel.readability.mercy_used = 0
	rs.begin_spin()
	rs._timer.stop()
	rs.reel_stopped.assign([false, true, true])
	rs._pending_stops.clear()
	# 构造带子：第 0 列首格为 MISS，游标置于 0，禁用视觉对齐以落在 idx=0
	var strip0 = [[miss_obj, "none", ""], [load("res://resources/symbols/fire_slash.tres"), "fire", ""]]
	rs.reel_strips[0] = strip0
	rs.reel_cursor[0] = 0
	duel.readability.visual_stop = false
	duel.readability.buffer_enabled = false
	gold_before = duel.gold
	mercy_before = duel.readability.mercy_used
	rs.stop_next_reel(false, "player")
	await get_tree().create_timer(0.35).timeout   # 等吸附完成
	print("T19JAM|INFO miss land path=%s gold_delta=%d mercy_delta=%d" % [
		String(duel.grid[0][0].resource_path) if duel.grid[0][0] != null else "",
		duel.gold - gold_before, duel.readability.mercy_used - mercy_before])
	_check(duel.gold == gold_before + 2, "精度 MISS 格当前触发 mercy +2 金（旧语义一视同仁）")
	_check(duel.readability.mercy_used == mercy_before + 1, "精度 MISS 格消耗一次 mercy")

	duel.queue_free()
	await get_tree().process_frame
