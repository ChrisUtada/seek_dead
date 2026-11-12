class_name WeaponIcons
extends RefCounted
## 武器图标解析与元素配色。
## 约定：图标文件名 = icon_<资源文件名>.png，放在 assets/icons/weapons/。
## 缺失图标时返回 null（卡片自动回落 emoji / 纯文字），不会报错。

const DIR := "res://assets/icons/weapons/"

## 元素主色（与 docs/武器图标绘制清单.md 的配色表一致，粒子用同一套）
const ELEMENT_COLORS := {
	"fire": Color(0.91, 0.46, 0.16),    # #E8762A
	"ice": Color(0.44, 0.72, 0.79),     # #6FB7C9
	"poison": Color(0.50, 0.64, 0.23),  # #7FA33A
	"light": Color(0.91, 0.85, 0.60),   # #E8D89A
	"dark": Color(0.42, 0.31, 0.53),    # #6C4E86
	"none": Color(0.56, 0.54, 0.51),    # #8E8A82
}

static var _cache := {}
static var _elem_cache := {}


## 资源路径 → 图标贴图（不存在则 null）
static func icon_for_path(path: String) -> Texture2D:
	if path == "":
		return null
	if _cache.has(path):
		return _cache[path]
	var id := path.get_file().get_basename()
	var icon_path := DIR + "icon_" + id + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(icon_path):
		tex = load(icon_path) as Texture2D
	_cache[path] = tex
	return tex


## 元素小图标（24px，列表行 / 文字卡用）。缺失时依次回落 16px 旧图 → null
static func element_icon(element: String) -> Texture2D:
	var e := element if element != "" else "none"
	if _elem_cache.has(e):
		return _elem_cache[e]
	var tex: Texture2D = null
	for path in ["res://assets/icons/elements/24/%s.png" % e,
			"res://assets/icons/elements/%s.png" % e,
			"res://assets/icons/elements/icon_%s_16.png" % e]:
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
			break
	_elem_cache[e] = tex
	return tex


static func color_for(element: String) -> Color:
	return ELEMENT_COLORS.get(element, ELEMENT_COLORS["none"])


## 把图标 + 元素粒子套到一张 ItemCard 上；没图标就什么都不做（保持原样）
static func apply(card, path: String, element: String, size := Vector2(40, 40)) -> bool:
	var tex := icon_for_path(path)
	if tex == null:
		return false
	card.set_art(tex, size, color_for(element))
	return true
