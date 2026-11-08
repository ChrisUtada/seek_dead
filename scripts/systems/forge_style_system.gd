# ForgeStyleSystem — G6-05 横向铸式（首批 4 把代表武器）
# 运行时经 duel_controller preload 实例化（不注册全局 class_name——headless 测试环境不刷新类缓存）。
#
# 设计口径（docs/角色与武器成长_整体方案.md §7.3 / docs/棋盘探索_战后成长与局外生涯_制作执行方案.md §8.4）：
# - 每把武器最多一个铸式；在整备页选择，选择写入 anvil_meta.forge_styles，跨局保留。
# - 铸式不是永久强化：每项都同时给出优势与代价；标准形态始终可用，不成为绝对劣势。
# - 解锁条件：该武器在图鉴中的历史最高熟练达到 R2（跨局记录，见 CodexSystem.best_rank_of）。
# - 只做火焰剑 / 匕首 / 战斧 / 霜晶法杖 4 把；不扩展武器数量，不改共享 .tres。
#
# 数值全部是「运行时修正」：
#   power / hit / weights 由 ReelSystem.build_pool 与 ReelPreview 读取；
#   pierce_at（破城 2 连破甲）由 CombatSystem 读取；
#   status_bonus（霜鸣每次多 1 层霜冻）由 CombatSystem 读取。

var _ctrl  # DuelController

const META_KEY := "forge_styles"     # anvil_meta.forge_styles = {武器路径: 铸式 id}
const UNLOCK_RANK := 2               # 熟练 R2 解锁该武器的变体
const FILE_PREFIX := "res://resources/weapon_templates/"
const SYM_PREFIX := "res://resources/symbols/"

const STYLES := {
	"res://resources/weapon_templates/fire_sword.tres": {
		"id": "lie_ren",
		"name": "烈刃",
		"tag": "高攻低命中",
		"adv": "基础攻击 +2（18→20）",
		"cost": "命中率 -5%（88%→83%，MISS 权重上升）",
		"power": 2,
		"hit": -0.05,
		"weights": {},
		"pierce_at": 0,
		"status_bonus": 0,
	},
	"res://resources/weapon_templates/dagger.tres": {
		"id": "wen_shou",
		"name": "稳手",
		"tag": "稳定输出",
		"adv": "命中率 +8%（82%→90%，MISS 权重下降）",
		"cost": "基础攻击 -2（10→8）",
		"power": -2,
		"hit": 0.08,
		"weights": {},
		"pierce_at": 0,
		"status_bonus": 0,
	},
	"res://resources/weapon_templates/battle_axe.tres": {
		"id": "po_cheng",
		"name": "破城",
		"tag": "三连破甲",
		"adv": "斧斩 2 连即可破甲（原 3 连）",
		"cost": "斧斩权重 5→3（普通攻击格 4→3，直接输出下降）",
		"power": 0,
		"hit": 0.0,
		"weights": {"res://resources/symbols/axe_slash.tres": -2.0},
		"pierce_at": 2,
		"status_bonus": 0,
	},
	"res://resources/weapon_templates/ice_staff.tres": {
		"id": "shuang_ming",
		"name": "霜鸣",
		"tag": "状态构筑",
		"adv": "霜冻每次多 +1 层（状态更集中）",
		"cost": "冰霜晶弹权重 4→3（直接攻击格 -1）、基础攻击 -2（15→13）",
		"power": -2,
		"hit": 0.0,
		"weights": {"res://resources/symbols/ice_crystal.tres": -1.0},
		"pierce_at": 0,
		"status_bonus": 1,
	},
}


func _init(ctrl) -> void:
	_ctrl = ctrl
	_ensure_meta()


# 老档缺键补空；非法路径 / 非法 id 清掉，不写回其它键。
func _ensure_meta() -> void:
	if not (_ctrl.meta.get(META_KEY) is Dictionary):
		_ctrl.meta[META_KEY] = {}
		return
	var src: Dictionary = _ctrl.meta[META_KEY]
	var cleaned := {}
	for p in src.keys():
		var path := String(p)
		var sid := String(src[p])
		if STYLES.has(path) and String(STYLES[path]["id"]) == sid:
			cleaned[path] = sid
	if cleaned.size() != src.size():
		_ctrl.meta[META_KEY] = cleaned


func is_supported(path: String) -> bool:
	return STYLES.has(path)


func style_def(path: String) -> Dictionary:
	return STYLES.get(path, {})


# 已保存的选择（不校验解锁；解锁状态用 unlocked）。
func selected_id(path: String) -> String:
	var m = _ctrl.meta.get(META_KEY, {})
	return String(m.get(path, "")) if m is Dictionary else ""


# 实际生效的铸式定义：未选择 / 未解锁 / 非法路径 → 空字典（标准形态）。
func selected_def(path: String) -> Dictionary:
	if not is_supported(path):
		return {}
	var sid := selected_id(path)
	if sid == "" or not unlocked(path):
		return {}
	var d: Dictionary = STYLES[path]
	return d if String(d["id"]) == sid else {}


# 选择 / 清除（"" = 标准形态）。未解锁或非法 id 拒绝。
func set_style(path: String, id: String) -> bool:
	if not is_supported(path):
		return false
	if id == "":
		var m: Dictionary = _ctrl.meta.get(META_KEY, {})
		if m.has(path):
			m.erase(path)
			_ctrl.meta[META_KEY] = m
			_ctrl._meta_store.save_meta()
		return true
	if not unlocked(path):
		return false
	var d: Dictionary = STYLES[path]
	if String(d["id"]) != id:
		return false
	if not (_ctrl.meta.get(META_KEY) is Dictionary):
		_ctrl.meta[META_KEY] = {}
	_ctrl.meta[META_KEY][path] = id
	_ctrl._meta_store.save_meta()
	return true


func current_rank(path: String) -> int:
	if _ctrl._codex == null:
		return 1
	return maxi(1, int(_ctrl._codex.best_rank_of(path)))


func unlocked(path: String) -> bool:
	if not is_supported(path):
		return false
	return current_rank(path) >= UNLOCK_RANK


func unlock_text(path: String) -> String:
	if unlocked(path):
		return "已解锁"
	return "熟练 R%d 解锁（当前 R%d）" % [UNLOCK_RANK, current_rank(path)]


# ---- 运行时修正（供 ReelSystem / CombatSystem 读取）----

func power_bonus(path: String) -> int:
	return int(selected_def(path).get("power", 0))


func hit_delta(path: String) -> float:
	return float(selected_def(path).get("hit", 0.0))


func weight_delta(path: String, sym_path: String) -> float:
	var w: Dictionary = selected_def(path).get("weights", {})
	return float(w.get(sym_path, 0.0))


# 破甲所需连数：3 = 原始；破城为 2。
func pierce_at(path: String) -> int:
	var v := int(selected_def(path).get("pierce_at", 0))
	return v if v > 0 else 3


func status_bonus(path: String) -> int:
	return int(selected_def(path).get("status_bonus", 0))


# ReelPreview 用的「当前选择」映射：{武器路径: 铸式定义}（仅已解锁）。
func preview_map() -> Dictionary:
	var out := {}
	for p in STYLES.keys():
		var d := selected_def(String(p))
		if not d.is_empty():
			out[String(p)] = d
	return out


# 汇总一行（整备卡片 / 日志）。
func describe(path: String) -> String:
	var d := selected_def(path)
	if d.is_empty():
		return ""
	return "铸式「%s」：%s；代价 %s" % [String(d["name"]), String(d["adv"]), String(d["cost"])]


# 铸式相对标准形态的真实带子差异（方向：标准 → 该铸式）。
# 只隔离这一把武器的变化：其它武器保持标准形态，避免多个铸式互相掩盖。
# 未装备该武器时返回空数组（调用方展示「装备后可预览」）。
func strip_diff(path: String) -> Array:
	var d: Dictionary = STYLES.get(path, {})
	if d.is_empty() or not _ctrl.selected_loadout.has(path):
		return []
	var std := {}
	var styled := {path: d}
	return ReelPreview.diff_lines(_ctrl.selected_loadout, _ctrl.selected_loadout,
		_ctrl.selected_skills, _ctrl.selected_charms, _ctrl.room_element_mult,
		_ctrl._reward_system.run_symbol_bonus, _ctrl.deprived_level,
		_ctrl.pending_chaos, int(_ctrl.boss_trash),
		_ctrl.mastery.tune_map(), _ctrl.mastery.tune_map(), std, styled)


# 属性差异行（不依赖是否装备）。
func stat_line(path: String) -> String:
	var wd: WeaponData = load(path)
	if wd == null:
		return ""
	var d: Dictionary = STYLES.get(path, {})
	if d.is_empty():
		return ""
	var forge_n: int = _ctrl.mastery.forge_bonus(path) if _ctrl.mastery != null else 0
	var atk0: int = int(wd.base_power) + forge_n
	var atk1: int = atk0 + int(d["power"])
	var hit0: int = int(round(float(wd.hit_rate) * 100.0))
	var hit1: int = int(round(clampf(float(wd.hit_rate) + float(d["hit"]), 0.0, 1.0) * 100.0))
	var parts: Array[String] = []
	parts.append("攻 %d→%d" % [atk0, atk1])
	parts.append("命中 %d%%→%d%%" % [hit0, hit1])
	if int(d.get("pierce_at", 0)) > 0:
		parts.append("破甲 %d连→%d连" % [3, int(d["pierce_at"])])
	if int(d.get("status_bonus", 0)) > 0:
		parts.append("状态 +%d层/次" % int(d["status_bonus"]))
	var wtxt: Array[String] = []
	var weights: Dictionary = d.get("weights", {})
	for sp in weights.keys():
		var sym: SymbolData = load(String(sp))
		if sym != null and float(weights[sp]) != 0.0:
			wtxt.append("%s 权重 %+.0f" % [sym.name, float(weights[sp])])
	if not wtxt.is_empty():
		parts.append("、".join(wtxt))
	return "属性：" + " · ".join(parts)


# 首版 4 把武器的固定展示顺序。
func supported_paths() -> Array:
	return [
		"res://resources/weapon_templates/fire_sword.tres",
		"res://resources/weapon_templates/dagger.tres",
		"res://resources/weapon_templates/battle_axe.tres",
		"res://resources/weapon_templates/ice_staff.tres",
	]
