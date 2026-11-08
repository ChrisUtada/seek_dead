class_name ItemCard
extends Button

# 通用卡片组件（物品/奖励/BOSS战利品/元进度/商店/卖出/金币升级共用）。
# 静态结构在 scenes/ui/item_card.tscn（Button 复用 ui_button.tscn + Center > VBox > 三行 Label），
# 本脚本只填文本/字号/颜色——消灭 battle_hud 里六份重复的 CenterContainer.new()+VBoxContainer.new() 构造器。
#
# 布局：IconRect（美术预留，可选）→ TitleLabel（主名）→ DescLabel（描述，可选）→ StatusLabel（价格/状态行，可选）。
# 未填的行自动隐藏。configure 在节点入树前调用，故不依赖 @onready，用懒解析缓存子节点。

const VON_FONT = preload("res://assets/fonts/VonwaonBitmap-12px.tres")

var _title_label: Label
var _desc_label: Label
var _status_label: Label
var _icon_rect: TextureRect
var _fit_min_y := 0.0


func _resolve() -> void:
	if _title_label != null:
		return
	_title_label = $Center/VBox/TitleLabel
	_desc_label = $Center/VBox/DescLabel
	_status_label = $Center/VBox/StatusLabel
	_icon_rect = $Center/VBox/IconRect
	# 显式挂像素字体：不依赖主题/项目默认链，任何继承失效都保持像素字
	_title_label.add_theme_font_override("font", VON_FONT)
	_desc_label.add_theme_font_override("font", VON_FONT)
	_status_label.add_theme_font_override("font", VON_FONT)


func configure(title: String, desc: String = "", title_size: int = TypeScale.META, desc_min_width: float = 0.0, separation: int = 1) -> void:
	_resolve()
	_title_label.text = title
	_title_label.add_theme_font_size_override("font_size", title_size)
	_desc_label.text = desc
	_desc_label.visible = desc != ""
	_desc_label.custom_minimum_size = Vector2(desc_min_width, 0) if desc_min_width > 0.0 else Vector2.ZERO
	_desc_label.add_theme_color_override("font_color", Color.WHITE)
	_status_label.visible = false
	($Center/VBox as VBoxContainer).add_theme_constant_override("separation", separation)


func set_desc_color(color: Color) -> void:
	_resolve()
	_desc_label.add_theme_color_override("font_color", color)


# G8-05：Button 的最小尺寸只按自身 text 算，不包含子控件。卡片高度写死时，
# 长描述自动换行后会画到卡片外（战后成长槽实测内容 124px / 卡 96px）。
# 入树后按 Center/VBox 的真实最小高度把卡片撑够。必须等布局给出真实宽度再量：
# 宽度还是 0 时自动换行会按「一行一个字」算出离谱高度（卖出卡曾被撑到 95 高）。
# 只增不减：不会因为临时状态把卡片压矮。
func fit_min_height(min_y: float) -> void:
	_fit_min_y = min_y

func _ready() -> void:
	set_process(_fit_min_y > 0.0)

# 逐帧等到布局给出真实宽度再量（协程在卡片被回收时会踩已释放对象，这里用 _process 更稳）
func _process(_delta: float) -> void:
	if _apply_fit():
		set_process(false)

func _apply_fit() -> bool:
	if _fit_min_y <= 0.0 or not is_inside_tree():
		return false
	var vb := get_node_or_null("Center/VBox") as Control
	if vb == null or vb.size.x <= 20.0:
		return false
	# 必须等子标签拿到与 VBox 一致的宽度：布局前标签宽度是 0/半成品，
	# 自动换行会按窄宽算出一堆多余行，把卡片撑成整列高（卖出卡曾到 92px）。
	_resolve()
	if _title_label.size.x < vb.size.x - 0.5:
		return false
	if _desc_label.is_visible_in_tree() and _desc_label.size.x < vb.size.x - 0.5:
		return false
	var need: float = maxf(_fit_min_y, vb.get_combined_minimum_size().y + 6.0)
	if need > custom_minimum_size.y + 0.5:
		custom_minimum_size.y = need
		update_minimum_size()
	return true


# 卡片美术（预留位）：传 null / 不调用 = 保持 emoji 图标呈现，隐藏图格
# min_size 默认 48（大量美术预留位）；结算/奖励这类 60 高的小卡传 (24,24)，
# 否则 48 图格 + 两行文字会顶破卡片。图格本身只做居中显示，不做放大。
func set_art(tex: Texture2D, min_size: Vector2 = Vector2(48, 48)) -> void:
	_resolve()
	_icon_rect.texture = tex
	_icon_rect.custom_minimum_size = min_size
	_icon_rect.visible = tex != null


func set_status(text: String, color: Color) -> void:
	_resolve()
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)
	_status_label.visible = text != ""


# 物品悬停信息窗：按资源类型生成 BBCode 富文本（ItemTooltip 单一生成器，见 docs/物品悬停信息窗_设计.md）
func set_tooltip(res: Resource, kind: String = "") -> void:
	tooltip_text = ItemTooltip.for_resource(res, kind)


# 内置 tooltip 不支持 BBCode（Godot 4.7 实证），自定义返回 RichTextLabel 渲染富文本
func _make_custom_tooltip(for_text: String) -> Control:
	if for_text.is_empty():
		return null
	return ItemTooltip.tooltip_label(for_text)
