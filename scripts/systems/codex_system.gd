extends RefCounted

# G6-04 图鉴详情：装备路线 / 机制 / 真实来源 / 使用次数 / 最高熟练 / 铭印组合。
#
# 职责：
# - 读静态资源生成「路线 / 机制」文本；
# - 读 meta.item_sources 生成真实来源；
# - 维护 meta.codex 的跨局使用统计（使用次数 / 最高熟练 / 铭印组合）；
# - 给图鉴面板提供分类列表与详情行。
#
# 边界：
# - 只读战斗与资源；不改数值、奖励、掉落、RNG。
# - meta.codex 只新增键，老档缺键按空统计处理；不删除已有收藏/来源。
# - 使用统计只在整备确认（装备）与消耗品实际使用、BOSS 结算/战败时写入。

const META_KEY := "codex"
const NODE = preload("res://scripts/board/board_node_data.gd")

const KIND_LABEL := {"weapon": "武器", "passive": "护符", "active": "消耗品", "skill": "技能"}
const KIND_ICON := {"weapon": "🗡", "passive": "📿", "active": "🧪", "skill": "✨"}
const SYMBOL_KIND_LABEL := {
	"damage": "伤害", "shield": "护盾", "heal": "回复", "status": "状态",
	"special": "特殊", "buff": "增益", "trash": "废铁",
}
const STATUS_LABEL := {"burn": "灼烧", "frost": "霜冻", "poison": "中毒"}
const RARITY_LABEL := {"common": "普通", "uncommon": "精良", "rare": "稀有", "epic": "史诗"}

var _ctrl
var _stats: Dictionary = {}


func _init(ctrl) -> void:
	_ctrl = ctrl
	_load()


func _load() -> void:
	var raw = _ctrl.meta.get(META_KEY, {})
	_stats = raw.duplicate(true) if raw is Dictionary else {}
	# 自愈：只保留字典条目；非法条目丢弃（不主动删除老档其它键）。
	for p in _stats.keys():
		if not (_stats[p] is Dictionary):
			_stats.erase(p)
	_write()   # 老档缺键自动补空，便于图鉴与后续统计直接读 meta


func _write() -> void:
	_ctrl.meta[META_KEY] = _stats.duplicate(true)


func _save() -> void:
	_write()
	if _ctrl._meta_store != null:
		_ctrl._meta_store.save_meta()


func _stat(path: String) -> Dictionary:
	if not _stats.has(path) or not (_stats[path] is Dictionary):
		_stats[path] = {}
	return _stats[path]


# 只读查询：不创建空条目，避免浏览图鉴把全池写进存档。
func _read_stat(path: String) -> Dictionary:
	var st = _stats.get(path, {})
	return st if st is Dictionary else {}


# ---------------------------------------------------------------------------
# 统计写入
# ---------------------------------------------------------------------------

# 整备确认：武器/护符/技能按「被带进一局」计一次使用（G7-C 起技能也进图鉴）。
func note_equipped(weapons: Array, charms: Array, skills: Array = []) -> void:
	var changed := false
	for p in weapons:
		var st := _stat(String(p))
		st["uses"] = int(st.get("uses", 0)) + 1
		changed = true
	for p in charms:
		var st := _stat(String(p))
		st["uses"] = int(st.get("uses", 0)) + 1
		changed = true
	for p in skills:
		var st := _stat(String(p))
		st["uses"] = int(st.get("uses", 0)) + 1
		changed = true
	if changed:
		_save()


# 消耗品实际消耗一次。
func note_used(path: String) -> void:
	if path == "":
		return
	var st := _stat(path)
	st["uses"] = int(st.get("uses", 0)) + 1
	_save()


# 本局结算：记录武器历史最高熟练与当时的铭印组合（只在刷新纪录时覆盖）。
func record_run(mastery) -> void:
	if mastery == null:
		return
	var changed := false
	for p in mastery.mastery:
		var pts := int(mastery.mastery[p])
		if pts <= 0:
			continue
		var path := String(p)
		var rank := int(mastery.r_level(path))
		var st := _stat(path)
		var best_pts := int(st.get("best_mastery", 0))
		var best_rank := int(st.get("best_rank", 0))
		if pts < best_pts and rank <= best_rank:
			continue
		st["best_rank"] = maxi(rank, best_rank)
		st["best_mastery"] = maxi(pts, best_pts)
		var im: Dictionary = mastery.imprints.get(path, {})
		st["forge"] = int(im.get("forge", 0))
		var tune: Dictionary = im.get("tune", {})
		st["tune"] = tune.duplicate(true) if tune is Dictionary else {}
		st["calibrate"] = int(im.get("calibrate", 0))   # G7-A S2
		st["tyrant"] = int(im.get("tyrant", 0))
		changed = true
	if changed:
		_save()


func uses_of(path: String) -> int:
	return int(_read_stat(path).get("uses", 0))


func best_rank_of(path: String) -> int:
	return int(_read_stat(path).get("best_rank", 0))


func best_mastery_of(path: String) -> int:
	return int(_read_stat(path).get("best_mastery", 0))


# ---------------------------------------------------------------------------
# 查询：分类列表
# ---------------------------------------------------------------------------

# 池内全部装备（含未拥有），按「已拥有优先、名称」排序；未拥有行只显示占位名。
func list_entries(kind: String) -> Array:
	var out: Array = []
	var pool: Array = _ctrl.SKILL_POOL if kind == "skill" else (_ctrl.WEAPON_POOL if kind == "weapon" else _ctrl.ITEM_POOL)
	for p in pool:
		var path := String(p)
		var res = load(path)
		if res == null:
			continue
		if kind == "weapon":
			if not (res is WeaponData):
				continue
		elif kind == "skill":
			if not (res is SkillData):
				continue
		else:
			if not (res is ItemData and String(res.category) == kind):
				continue
		var owned := _owned(path)
		out.append({
			"path": path,
			"kind": kind,
			"name": _display_name(path) if owned else "？？？",
			"owned": owned,
			"uses": uses_of(path),
			"rank": best_rank_of(path),
			"rarity": String(res.get("rarity")),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["owned"]) != bool(b["owned"]):
			return bool(a["owned"])
		return String(a["name"]) < String(b["name"]))
	return out


func owned_count(kind: String) -> int:
	var n := 0
	for e in list_entries(kind):
		if bool(e["owned"]):
			n += 1
	return n


func total_count(kind: String) -> int:
	return list_entries(kind).size()


# ---------------------------------------------------------------------------
# 查询：详情行（UI 与测试共用）
# ---------------------------------------------------------------------------

func detail_lines(path: String) -> Array[String]:
	var res = load(path)
	if res == null:
		return []
	var kind := _kind_of(res)
	var out: Array[String] = []
	out.append("类别：%s · 稀有度 %s" % [
		String(KIND_LABEL.get(kind, kind)), String(RARITY_LABEL.get(String(res.get("rarity")), String(res.get("rarity"))))])
	out.append("路线：" + _route_text(res, kind))
	out.append("机制：" + _mechanism_text(res, kind))
	var srcs := source_lines(path)
	if srcs.is_empty():
		out.append("来源：未记录（老档或尚未获取）")
	else:
		for s in srcs:
			out.append("来源：" + s)
	out.append("使用：%d 次" % uses_of(path))
	if kind == "weapon":
		var rank := best_rank_of(path)
		if rank > 0:
			out.append("熟练：历史最高 R%d · %d 点" % [rank, best_mastery_of(path)])
		else:
			out.append("熟练：暂无记录")
		out.append("铭印：" + _imprint_text(path))
	else:
		out.append("熟练 / 铭印：不适用")
	return out


# 真实来源：meta.item_sources 的最近 3 条不同来源。
func source_lines(path: String) -> Array[String]:
	var all: Dictionary = _ctrl.meta.get("item_sources", {})
	var arr: Array = all.get(path, []) if all is Dictionary else []
	var seen := {}
	var texts: Array[String] = []
	for i in range(arr.size() - 1, -1, -1):
		var e: Dictionary = arr[i]
		var t := _source_text(e)
		if t == "" or seen.has(t):
			continue
		seen[t] = true
		texts.append(t)
		if texts.size() >= 3:
			break
	return texts


# ---------------------------------------------------------------------------
# 内部：静态描述
# ---------------------------------------------------------------------------

func _kind_of(res) -> String:
	if res is WeaponData:
		return "weapon"
	if res is SkillData:
		return "skill"
	if res is ItemData:
		return String(res.category)
	return ""


func _owned(path: String) -> bool:
	for key in ["owned_weapons", "owned_charms", "owned_consumables", "owned_skills"]:
		var arr: Array = _ctrl.meta.get(key, [])
		if arr.has(path):
			return true
	return false


func _display_name(path: String) -> String:
	var res = load(path)
	if res is WeaponData:
		return String(res.weapon_name)
	if res is SkillData:
		return String(res.buff_name) if String(res.buff_name) != "" else path.get_file().get_basename()
	if res is ItemData:
		return String(res.item_name)
	return path.get_file().get_basename()


func _route_text(res, kind: String) -> String:
	if kind == "skill":
		var s = res.symbol
		if s == null:
			return "技能"
		var sk := String(SYMBOL_KIND_LABEL.get(String(s.kind), String(s.kind)))
		var se := ElementCounter.label(String(s.element))
		return "技能 · " + sk + (" · " + se if se != "" and se != "无" else "")
	if kind != "weapon":
		var elem := ElementCounter.label(String(res.element))
		return String(KIND_LABEL.get(kind, kind)) + (" · " + elem if elem != "" and elem != "无" else "")
	var bits: Array[String] = []
	var elem := ElementCounter.label(String(res.element))
	if elem != "" and elem != "无":
		bits.append(elem)
	var syms: Array[String] = []
	for sw in res.symbols:
		if sw == null or sw.symbol == null:
			continue
		var s = sw.symbol
		var nm := String(s.name)
		if nm == "":
			nm = String(s.label)
		var k := String(SYMBOL_KIND_LABEL.get(String(s.kind), String(s.kind)))
		syms.append("%s(%s)" % [nm, k])
		if syms.size() >= 4:
			break
	if not syms.is_empty():
		bits.append("、".join(syms))
	return " · ".join(bits) if not bits.is_empty() else "无"


func _mechanism_text(res, kind: String) -> String:
	if kind == "skill":
		# 技能没有 downside_effect 字段；只给描述，避免按 ItemData 读键报错。
		var sd := String(res.description)
		return sd if sd != "" else "无"
	if kind != "weapon":
		var desc := String(res.description)
		var bits: Array[String] = []
		if desc != "":
			bits.append(desc)
		if String(res.downside_effect) != "":
			bits.append("有代价")
		return " · ".join(bits) if not bits.is_empty() else "无"
	var bits: Array[String] = []
	bits.append("攻%d" % int(res.base_power))
	bits.append("命中%d%%" % int(round(res.hit_rate * 100.0)))
	bits.append("三连×%.1f" % float(res.crit_mult))
	var pierce := bool(res.triple_pierce)
	var has_status := false
	var has_shield := false
	var has_heal := false
	for sw in res.symbols:
		if sw == null or sw.symbol == null:
			continue
		var s = sw.symbol
		if bool(s.pierce_armor):
			pierce = true
		var sk := String(s.kind)
		if sk == "status":
			has_status = true
		elif sk == "shield":
			has_shield = true
		elif sk == "heal":
			has_heal = true
	if pierce:
		bits.append("破甲")
	if has_status:
		bits.append("状态")
	if has_shield:
		bits.append("护盾")
	if has_heal:
		bits.append("回复")
	return " · ".join(bits)


func _imprint_text(path: String) -> String:
	var st := _read_stat(path)
	var bits: Array[String] = []
	var forge := int(st.get("forge", 0))
	if forge > 0:
		bits.append("锋铸×%d" % forge)
	var tune: Dictionary = st.get("tune", {})
	for sym_path in tune:
		var n := int(tune[sym_path])
		if n <= 0:
			continue
		bits.append("调律 %s×%d" % [_sym_name(String(sym_path)), n])
	var calibrate := int(st.get("calibrate", 0))
	if calibrate > 0:
		bits.append("校准×%d" % calibrate)
	var tyrant := int(st.get("tyrant", 0))
	if tyrant > 0:
		bits.append("暴虐×%d" % tyrant)
	if bits.is_empty():
		return "暂无记录"
	return " · ".join(bits)


func _sym_name(sym_path: String) -> String:
	var s = load(sym_path)
	if s is SymbolData:
		return String(s.name) if String(s.name) != "" else String(s.label)
	return sym_path.get_file().get_basename()


func _source_text(e: Dictionary) -> String:
	if e.is_empty():
		return ""
	var bits: Array[String] = []
	bits.append("ACT%d" % int(e.get("act", 1)))
	bits.append("棋盘" if String(e.get("mode", "")) == "board" else "线性")
	var nt := String(e.get("node_type", ""))
	if nt != "":
		bits.append(String(NODE.label(nt)))
	else:
		var rk := String(e.get("room_kind", ""))
		if rk == "boss":
			bits.append("BOSS 房")
		elif rk == "elite":
			bits.append("精英房")
		elif rk == "normal":
			bits.append("普通房")
	var where := String(e.get("room", ""))
	if where == "":
		where = String(e.get("item", ""))
	if where != "":
		bits.append(where)
	return " · ".join(bits)
