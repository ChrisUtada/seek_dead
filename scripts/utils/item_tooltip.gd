class_name ItemTooltip
extends RefCounted

# 物品悬停信息窗（Item Tooltip）——设计见 docs/物品悬停信息窗_设计.md
# 单一生成器：按资源类型生成 BBCode 富文本，经 Godot 内置 tooltip_text 显示（主题已像素化）。
# 所有物品卡片（商店/整备/铁砧/腰带）统一走本生成器——格式一处改全生效。
#
# 内容结构（图标位预留）：
#   第一行 = [图标] 名称 · 稀有度（emoji 现用；未来美术图只换显示层不改结构）
#   第二行 = 核心数值；后续 = 符号表 / 效果描述
# 稀有度色见 Palette.RARITY_*；字段缺失兜底文件名（防 load 失败白框）。

static func for_resource(res: Resource, kind: String = "") -> String:
	if res == null:
		return "[color=#aaa]（缺失资源）[/color]"
	if res is WeaponData:
		return _weapon(res as WeaponData)
	if res is SkillData:
		return _skill(res as SkillData)
	if res is ItemData:
		return _item(res as ItemData)
	if res is RewardData:
		return _reward(res as RewardData)
	return "[color=#aaa]%s[/color]" % res.resource_path.get_file().get_basename()


# —— 内部：BBCode 工具 ——

static func _rarity_color(r: String) -> Color:
	match r:
		"uncommon": return Palette.RARITY_UNCOMMON
		"rare":     return Palette.RARITY_RARE
		"epic":     return Palette.RARITY_EPIC
	return Palette.RARITY_COMMON


static func _c(c: Color) -> String:
	return "#%02x%02x%02x" % [int(c.r * 255), int(c.g * 255), int(c.b * 255)]


# —— 各类型生成器 ——

static func _weapon(w: WeaponData) -> String:
	var icon := ""
	if w.symbols != null and w.symbols.size() > 0 and w.symbols[0] != null and w.symbols[0].symbol != null:
		icon = w.symbols[0].symbol.label   # 武器暂无 icon 字段，首符号 label 占位（图标位预留）
	var name := w.weapon_name if w.weapon_name != "" else w.resource_path.get_file().get_basename()
	var lines: Array[String] = ["%s [color=%s]%s[/color] · [color=%s]%s[/color]" % [icon, _c(Palette.TITLE), name, _c(_rarity_color(w.rarity)), w.rarity]]
	lines.append("%s · 攻%d · 命中%d%%" % [ElementCounter.label(w.element), int(w.base_power), int(w.hit_rate * 100.0)])
	if w.symbols != null and not w.symbols.is_empty():
		var arr := w.symbols.duplicate()
		arr.sort_custom(func(a, b): return a.weight > b.weight)
		var parts: Array[String] = []
		for i in mini(3, arr.size()):
			var sw = arr[i]
			if sw != null and sw.symbol != null:
				parts.append("%s×%d" % [sw.symbol.label, int(sw.weight)])
		var sym_txt := " ".join(parts)
		if arr.size() > 3:
			sym_txt += " …"
		lines.append(sym_txt)
	return "\n".join(lines)


static func _item(it: ItemData) -> String:
	var icon := it.icon if it.icon != "" else "◆"
	var cat := "护符" if it.category == "passive" else "消耗品"
	var lines: Array[String] = ["%s [color=%s]%s[/color] · %s" % [icon, _c(Palette.TITLE), it.item_name, cat]]
	if it.description != "":
		lines.append(it.description)
	if it.category == "active" and it.charges > 1:
		lines.append("可用 %d 次" % it.charges)
	if it.downside_effect != "":
		lines.append("[color=%s]负面：%s[/color]" % [_c(Palette.ENEMY), it.downside_effect])
	return "\n".join(lines)


static func _skill(sd: SkillData) -> String:
	var icon := sd.icon if sd.icon != "" else "✦"
	var lines: Array[String] = ["%s [color=%s]%s[/color] · [color=%s]%s[/color]" % [icon, _c(Palette.TITLE), sd.buff_name, _c(_rarity_color(sd.rarity)), sd.rarity]]
	if sd.description != "":
		lines.append(sd.description)
	if sd.symbol != null:
		lines.append("%s×%d · 攻%d · 命中%d%%" % [sd.symbol.label, int(sd.weight), int(sd.base_power), int(sd.hit_rate * 100.0)])
	return "\n".join(lines)


static func _reward(rw: RewardData) -> String:
	var lines: Array[String] = ["%s [color=%s]%s[/color]" % [rw.icon, _c(Palette.TITLE), rw.label]]
	if rw.desc != "":
		lines.append(rw.desc)
	return "\n".join(lines)
