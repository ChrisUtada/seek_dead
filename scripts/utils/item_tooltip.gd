class_name ItemTooltip
extends RefCounted

# 物品悬停信息窗（Item Tooltip）——设计见 docs/物品悬停信息窗_设计.md
# 单一生成器：按资源类型生成 BBCode 富文本，经各卡片 _make_custom_tooltip → RichTextLabel 显示。
# 所有物品卡片（商店/整备/铁砧/腰带）统一走本生成器——格式一处改全生效。
#
# 内容结构（图标位预留）：
#   第一行 = [图标] 名称（+ 稀有度）（emoji 现用；未来美术图只换显示层不改结构）
#   第二行 = 核心数值；后续 = 符号表 / 效果描述
# 稀有度色见 Palette.RARITY_*；字段缺失兜底文件名（防 load 失败白框）。

const VON_FONT := preload("res://assets/fonts/VonwaonBitmap-12px.tres")

# 内置 tooltip 用普通 Label.set_text() 渲染、BBCode 不生效（Godot 4.7 viewport.cpp 实证），
# 富文本必须走各卡片 _make_custom_tooltip → 本构建器。
# 字体/字号/字色显式覆盖（像素字），不依赖主题链——任何挂载环境都保持复古像素观感。
# 字号=10：与商店卡片标题统一（TypeScale.TITLE=10）。
# 关键：RichTextLabel 的 theme 属性名与 Label 不同——字体是 normal_font、
# 字号是 normal_font_size、颜色是 default_color（Label 是 font/font_size/font_color）。
# 用 Label 属性名会静默无效（实证：字号只能靠 BBCode 生效、字体落到 default_font 11px 缩放发虚）。
# 尺寸实证（2026-08-11）：
# - fit_content 必须配 custom_minimum_size 宽度，否则最小宽为 1px（弹窗塌成竖条）；
# - 10px 缓存位图布局行距约 13px（字形高度），无需额外补偿。
static func tooltip_label(for_text: String) -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.custom_minimum_size = Vector2(280, 0)
	rtl.add_theme_font_override("normal_font", VON_FONT)
	rtl.add_theme_font_size_override("normal_font_size", TypeScale.TITLE)
	rtl.add_theme_color_override("default_color", Color(0.92, 0.9, 0.86))
	rtl.text = for_text
	return rtl


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


# 描述截断：超长描述压缩为单行（280px 宽 ≈ 26 个中文全角），防弹窗又宽又高
static func _cap(s: String, n: int = 26) -> String:
	if s.length() <= n:
		return s
	return s.left(n) + "…"


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
	var lines: Array[String] = ["%s [color=%s]%s[/color]" % [icon, _c(Palette.TITLE), it.item_name]]
	if it.description != "":
		lines.append(_cap(it.description))
	if it.category == "active" and it.charges > 1:
		lines.append("可用 %d 次" % it.charges)
	if it.downside_effect != "":
		lines.append("[color=%s]负面：%s[/color]" % [_c(Palette.ENEMY), _cap(it.downside_effect)])
	return "\n".join(lines)


static func _skill(sd: SkillData) -> String:
	var icon := sd.icon if sd.icon != "" else "✦"
	var lines: Array[String] = ["%s [color=%s]%s[/color] · [color=%s]%s[/color]" % [icon, _c(Palette.TITLE), sd.buff_name, _c(_rarity_color(sd.rarity)), sd.rarity]]
	if sd.description != "":
		lines.append(_cap(sd.description))
	if sd.symbol != null:
		lines.append("%s×%d · 攻%d · 命中%d%%" % [sd.symbol.label, int(sd.weight), int(sd.base_power), int(sd.hit_rate * 100.0)])
	return "\n".join(lines)


static func _reward(rw: RewardData) -> String:
	var lines: Array[String] = ["%s [color=%s]%s[/color]" % [rw.icon, _c(Palette.TITLE), rw.label]]
	if rw.desc != "":
		lines.append(_cap(rw.desc))
	return "\n".join(lines)
