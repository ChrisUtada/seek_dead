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
		return {"ok": false, "reason": "empty_tier", "quality": quality, "path": "", "item": {}}
	var idx := _rng.randi_range(0, tier.size() - 1)
	return {"ok": true, "reason": "", "quality": quality, "path": String(tier[idx]), "item": _entry(String(tier[idx]))}


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


# 商店确定性阶梯：每格按指定品质抽一个，跨格无放回（类别混合；类别确定性留给 Step 5）。
# 返回 Array[{ok, quality, path, reason}]
func roll_ladder(act: int, tiers: Array, opts: Dictionary = {}) -> Array:
	var out: Array = []
	if tiers.is_empty():
		return out
	_build_index()
	var used := {}
	for p in opts.get("exclude", []):
		used[String(p)] = true
	for q in tiers:
		var quality := String(q)
		var cand: Array[String] = []
		for e in _index:
			if bool(e["relic"]) and not bool(opts.get("include_relics", false)):
				continue
			if used.has(String(e["path"])):
				continue
			if String(e["rarity"]) != quality:
				continue
			if not (act >= int(e["act_min"]) and act <= int(e["act_max"])):
				continue
			if not ("shop" in (e["tags"] as Array)):
				continue
			if not _demo_allows(e):
				continue
			cand.append(String(e["path"]))
		cand.sort()
		if cand.is_empty():
			out.append({"ok": false, "quality": quality, "path": "", "reason": "empty_tier"})
			continue
		var path := String(cand[_rng.randi_range(0, cand.size() - 1)])
		used[path] = true
		out.append({"ok": true, "quality": quality, "path": path, "reason": ""})
	return out


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
	for e in _index:
		if String(e["path"]) == path:
			return e
	return {}


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
			_index.append({
				"path": path,
				"kind": String(kind),
				"rarity": String(res.get("rarity")) if res.get("rarity") != null else "common",
				"tags": tags,
				"act_min": int(amin) if amin != null else 1,
				"act_max": int(amax) if amax != null else 99,
				"relic": f.contains("_relic"),
			})
