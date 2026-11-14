class_name LootPool
extends RefCounted

# 四级品质战利品 Step 3：统一候选池。
# 输入「来源 + 幕次 + 过滤条件」，输出同品质层的具体物品候选。
#
# 职责边界：
#   - 品质概率只来自 LootSourceTable（本类不读物品 rarity 做权重）；
#   - 合法性只读 Step 1 元数据：source_tags / act_min / act_max，加类别与主题白名单；
#   - 不在候选层补跨品质物品：该层为空就返回 empty_tier，由上层（Step 4）给同层转化或明确空原因；
#   - 抽取使用本类持有的专用 RNG 流，不消耗全局/地图 RNG；
#   - 商店用 roll_ladder 的确定性品质阶梯，不走随机来源表。
#
# 候选索引来自资源目录扫描（与 Step 1 的 200 项内容同源），不用 controller 过滤后的池，
# 避免「奖励池已按旧稀有度/白名单裁剪」的隐式耦合；demo 白名单在这里显式应用。

const DIRS := {
	"weapon": "res://resources/weapon_templates",
	"passive": "res://resources/charms",
	"active": "res://resources/consumables",
	"skill": "res://resources/skills",
}

var _ctrl                        # DuelController；可为 null（纯池测试）
var _index: Array = []           # [{path, kind, rarity, tags, act_min, act_max, relic}]
var _by_path := {}               # Step 8：path → 索引项（O(1) 查找；生成一组三选一会查十几次）
var _res_by_path := {}           # Step 8：path → 已加载资源（避免每次生成都重新解析 .tres）
var _rng := RandomNumberGenerator.new()
var _seed := 0


func _init(ctrl = null) -> void:
	_ctrl = ctrl
	reset_run()


# 新一局：只取一次种子（允许测试传入固定种子），之后所有抽取走专用流。
func reset_run(seed_value: int = -1) -> void:
	_seed = seed_value if seed_value >= 0 else randi()
	_rng.seed = _seed


func seed_value() -> int:
	return _seed


# ---------------------------------------------------------------------------
# 候选
# ---------------------------------------------------------------------------

# opts:
#   category      String 或 Array（weapon/passive/active/skill）
#   theme         Array[String] 主题白名单；键存在但为空 = 明确空主题池
#   exclude       Array[String] 排除路径（已装备/已带/信物等）
#   include_relics bool，默认 false（BOSS 信物默认不进普通候选）
# 返回 {ok, reason, items, source, act}
func candidates(source: String, act: int, opts: Dictionary = {}) -> Dictionary:
	if not LootSourceTable.is_valid_source(source):
		return _fail("invalid_source", source, act)
	if not LootSourceTable.is_valid_act(act):
		return _fail("invalid_act", source, act)
	if opts.has("theme") and (opts["theme"] as Array).is_empty():
		return _fail("empty_theme", source, act)
	var cats: Array = _categories(opts.get("category", []))
	var theme: Array = opts.get("theme", [])
	var theme_set := {}
	for p in theme:
		theme_set[String(p)] = true
	var exclude := {}
	for p in opts.get("exclude", []):
		exclude[String(p)] = true
	var include_relics := bool(opts.get("include_relics", false))
	if _index.is_empty():
		_build_index()
	var out: Array[String] = []
	for e in _index:
		if not cats.is_empty() and not cats.has(String(e["kind"])):
			continue
		if not include_relics and bool(e["relic"]):
			continue
		if exclude.has(String(e["path"])):
			continue
		if opts.has("theme") and not theme_set.has(String(e["path"])):
			continue
		if not (act >= int(e["act_min"]) and act <= int(e["act_max"])):
			continue
		if not (source in (e["tags"] as Array)):
			continue
		if not _demo_allows(e):
			continue
		out.append(String(e["path"]))
	out.sort()
	return {"ok": true, "reason": "" if not out.is_empty() else "no_candidates",
		"items": out, "source": source, "act": act}


# 抽一个同层候选。forced_quality 供测试/上层已定品质时使用。
# 返回 {ok, reason, quality, path, item}
func roll(source: String, act: int, opts: Dictionary = {}, forced_quality: String = "") -> Dictionary:
	var pool := candidates(source, act, opts)
	if not bool(pool["ok"]):
		return {"ok": false, "reason": pool["reason"], "quality": "", "path": "", "item": {}}
	var quality := forced_quality
	if quality == "":
		quality = LootSourceTable.roll_quality(source, act, _rng)
		if quality == "":
			return {"ok": false, "reason": "source_not_random:" + source, "quality": "", "path": "", "item": {}}
	var tier := _tier(pool["items"], quality)
	if tier.is_empty():
		# 该来源在当前类别下没有这一层（例：消耗品没有 epic）。
		# 与 pick_explore_loot 同口径：改抽「池里真实存在」的品质层，权重仍取来源表，
		# 不静默返回空奖励。forced_quality 由调用方指定，保持原样失败。
		if forced_quality != "":
			return {"ok": false, "reason": "empty_tier", "quality": quality, "path": "", "item": {}}
		var avail := _available_weights(pool["items"], source, act)
		var alt := _roll_quality_from(avail, _rng)
		if alt == "":
			return {"ok": false, "reason": "empty_tier", "quality": quality, "path": "", "item": {}}
		quality = alt
		tier = _tier(pool["items"], quality)
		if tier.is_empty():
			return {"ok": false, "reason": "empty_tier", "quality": quality, "path": "", "item": {}}
	var idx := _rng.randi_range(0, tier.size() - 1)
	return {"ok": true, "reason": "", "quality": quality, "path": String(tier[idx]), "item": _entry(String(tier[idx]))}


# 池内真实存在的品质层 → 来源表权重（供空层改抽，不改变来源）。
func _available_weights(items: Array, source: String, act: int) -> Dictionary:
	var present := {}
	for p in items:
		var r := String(_entry(String(p)).get("rarity", ""))
		if r != "":
			present[r] = true
	var weights: Dictionary = LootSourceTable.weights_for(source, act).get("weights", {})
	var out := {}
	for q in LootSourceTable.QUALITIES:
		if present.has(q) and int(weights.get(q, 0)) > 0:
			out[q] = int(weights[q])
	return out


func _roll_quality_from(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0
	for q in LootSourceTable.QUALITIES:
		total += int(weights.get(q, 0))
	if total <= 0:
		return ""
	var roll := rng.randf() * float(total)
	for q in LootSourceTable.QUALITIES:
		roll -= float(weights.get(q, 0))
		if roll <= 0.0:
			return q
	return ""


# 同层无放回抽至多 n 个。pool 非空但该层不足 n 时返回 ok + short_tier（由上层补同层转化）。
func roll_n(source: String, act: int, n: int, opts: Dictionary = {}, forced_quality: String = "") -> Dictionary:
	var result := {"ok": false, "reason": "", "quality": "", "paths": [], "count": 0}
	if n <= 0:
		result["reason"] = "invalid_count"
		return result
	var pool := candidates(source, act, opts)
	if not bool(pool["ok"]):
		result["reason"] = String(pool["reason"])
		return result
	var quality := forced_quality
	if quality == "":
		quality = LootSourceTable.roll_quality(source, act, _rng)
		if quality == "":
			result["reason"] = "source_not_random:" + source
			return result
	result["quality"] = quality
	var tier := _tier(pool["items"], quality)
	if tier.is_empty():
		result["reason"] = "empty_tier"
		return result
	var picked := _sample(tier, mini(n, tier.size()))
	result["ok"] = true
	result["paths"] = picked
	result["count"] = picked.size()
	result["reason"] = "short_tier" if picked.size() < n else ""
	return result


# 商店确定性阶梯：每格按指定品质抽一个，跨格无放回。
# Step 5：opts.categories 按格给出确定性类别（与 tiers 同下标）；指定类别在该层无候选时
# 回退到该层任意类别，保证货架格数不缩水。类别确定性来自 BalanceConfig.loot_shop_categories。
# 返回 Array[{ok, quality, path, reason}]
func roll_ladder(act: int, tiers: Array, opts: Dictionary = {}) -> Array:
	var out: Array = []
	if tiers.is_empty():
		return out
	# 允许调用方传入确定性 RNG（地图固定种子冻结货架）；不传则沿用本池 RNG。
	var rng: RandomNumberGenerator = _rng
	if opts.get("rng") is RandomNumberGenerator:
		rng = opts["rng"]
	_build_index()
	var used := {}
	for p in opts.get("exclude", []):
		used[String(p)] = true
	var cats: Array = opts.get("categories", [])
	for i in tiers.size():
		var quality := String(tiers[i])
		var want_cat := String(cats[i]) if i < cats.size() else ""
		var cand := _ladder_candidates(act, quality, want_cat, used, opts)
		if cand.is_empty() and want_cat != "":
			cand = _ladder_candidates(act, quality, "", used, opts)
		if cand.is_empty():
			out.append({"ok": false, "quality": quality, "path": "", "reason": "empty_tier"})
			continue
		var path := String(cand[rng.randi_range(0, cand.size() - 1)])
		used[path] = true
		out.append({"ok": true, "quality": quality, "path": path, "reason": ""})
	return out


# 阶梯单格候选：来源标签 shop + 幕次 + 品质 +（可选）类别 + 未使用 + demo 白名单。
func _ladder_candidates(act: int, quality: String, category: String, used: Dictionary,
		opts: Dictionary) -> Array[String]:
	var cand: Array[String] = []
	for e in _index:
		if bool(e["relic"]) and not bool(opts.get("include_relics", false)):
			continue
		if used.has(String(e["path"])):
			continue
		if String(e["rarity"]) != quality:
			continue
		if category != "" and String(e["kind"]) != category:
			continue
		if not (act >= int(e["act_min"]) and act <= int(e["act_max"])):
			continue
		if not ("shop" in (e["tags"] as Array)):
			continue
		if not _demo_allows(e):
			continue
		cand.append(String(e["path"]))
	cand.sort()
	return cand


# 打乱顺序也走专用流，不消耗地图 RNG。
func shuffle_in_place(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ---------------------------------------------------------------------------
# Step 4：同层三选一支持
# ---------------------------------------------------------------------------

# 用专用流抽一个品质（LootOffer 一次定层；重抽不得再调用）。
func roll_quality(source: String, act: int) -> String:
	return LootSourceTable.roll_quality(source, act, _rng)


# 指定品质层的合法候选（已按字典序排序）。
# 返回 {ok, reason, items}
func tier_items(source: String, act: int, quality: String, opts: Dictionary = {}) -> Dictionary:
	var pool := candidates(source, act, opts)
	if not bool(pool["ok"]):
		return {"ok": false, "reason": pool["reason"], "items": []}
	var tier := _tier(pool["items"], quality)
	if tier.is_empty():
		return {"ok": false, "reason": "empty_tier", "items": []}
	return {"ok": true, "reason": "", "items": tier}


# 专用流无放回取至多 n 个（返回新数组，不改入参）。
func pick_n(paths: Array, n: int) -> Array:
	if n <= 0 or paths.is_empty():
		return []
	return _sample(paths, mini(n, paths.size()))


# 路径元数据副本（供 LootOffer 冻结卡片文案；不改索引本体）。
func entry_of(path: String) -> Dictionary:
	if _index.is_empty():
		_build_index()
	return _entry(path).duplicate(true)


# Step 8：生成热路径只读单个字段，不做深拷贝（一组三选一会查上百次）。
func group_of(path: String) -> String:
	if _index.is_empty():
		_build_index()
	return String(_entry(path).get("unique_group", ""))


# Step 8：已加载资源（生成卡面文案要读 role / family_tags / 名称 / 描述）。
# 资源引用放在池上单独持有，不放进索引项——entry_of() 会 duplicate(true) 索引项。
# 否则 load() 每次调用都因引用归零而重新解析 .tres（实测约 3ms/次）。
func resource_of(path: String) -> Resource:
	if _index.is_empty():
		_build_index()
	return _res_by_path.get(path, null)


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _fail(reason: String, source: String, act: int) -> Dictionary:
	return {"ok": false, "reason": reason, "items": [], "source": source, "act": act}


func _categories(raw: Variant) -> Array:
	if raw is String:
		return [] if String(raw) == "" else [String(raw)]
	if raw is Array:
		return raw
	return []


func _tier(items: Array, quality: String) -> Array:
	var out: Array = []
	for p in items:
		var e := _entry(String(p))
		if String(e.get("rarity", "")) == quality:
			out.append(String(p))
	return out


func _sample(pool: Array, n: int) -> Array:
	var copy := pool.duplicate()
	for i in range(copy.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = copy[i]
		copy[i] = copy[j]
		copy[j] = tmp
	return copy.slice(0, n)


func _entry(path: String) -> Dictionary:
	return _by_path.get(path, {})


func _demo_allows(e: Dictionary) -> bool:
	if _ctrl == null or not _ctrl.demo_active():
		return true
	match String(e["kind"]):
		"weapon": return _ctrl.demo_config.allows_weapon(String(e["path"]))
		"skill": return _ctrl.demo_config.allows_skill(String(e["path"]))
		"passive": return _ctrl.demo_config.allows_charm(String(e["path"]))
		"active": return _ctrl.demo_config.allows_consumable(String(e["path"]))
	return true


func _build_index() -> void:
	_index.clear()
	_by_path.clear()
	_res_by_path.clear()
	for kind in DIRS:
		var dir := DirAccess.open(String(DIRS[kind]))
		if dir == null:
			continue
		for f in dir.get_files():
			if not f.ends_with(".tres"):
				continue
			var path := String(DIRS[kind]) + "/" + f
			var res: Resource = load(path)
			if res == null:
				continue
			var tags: Array = []
			var raw_tags: Variant = res.get("source_tags")
			if raw_tags is Array:
				tags = raw_tags
			var amin: Variant = res.get("act_min")
			var amax: Variant = res.get("act_max")
			var fams: Variant = res.get("family_tags")
			_index.append({
				"path": path,
				"kind": String(kind),
				"rarity": String(res.get("rarity")) if res.get("rarity") != null else "common",
				"tags": tags,
				# Step 8：unique_group 必须进索引——LootOffer 的「同机制不重复」贪心读的是
				# entry_of(...).unique_group；此前缺字段导致三项可能只是换皮。
				"unique_group": String(res.get("unique_group")) if res.get("unique_group") != null else "",
				"family_tags": fams if fams is Array else [],
				"act_min": int(amin) if amin != null else 1,
				"act_max": int(amax) if amax != null else 99,
				"relic": f.contains("_relic"),
			})
			_by_path[path] = _index[_index.size() - 1]
			_res_by_path[path] = res
