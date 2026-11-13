class_name ItemCard
extends Button

# 通用卡片组件（物品/奖励/BOSS战利品/元进度/商店/卖出/金币升级共用）。
# 静态结构在 scenes/ui/item_card.tscn（Button 复用 ui_button.tscn + Center > VBox > 三行 Label），
# 本脚本只填文本/字号/颜色——消灭 battle_hud 里六份重复的 CenterContainer.new()+VBoxContainer.new() 构造器。
#
# 布局：IconRect（美术预留，可选）→ TitleLabel（主名）→ DescLabel（描述，可选）→ StatusLabel（价格/状态行，可选）。
# 未填的行自动隐藏。configure 在节点入树前调用，故不依赖 @onready，用懒解析缓存子节点。

const VON_FONT = preload("res://assets/fonts/VonwaonBitmap-12px.tres")
const PX1_TEX = preload("res://assets/fx/fx_px1.png")   # 1px 点，图标火星专用（不能用 4x4 余烬，48px 下变成脏点）

var _title_label: Label
var _desc_label: Label
var _status_label: Label
var _icon_rect: TextureRect
var _fit_min_y := 0.0
var _art_fx: CPUParticles2D


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


# Step 7：标题取品质色（奖励卡 / BOSS 战利品卡）。只改这一张卡，不写共享主题。
func set_title_color(color: Color) -> void:
	_resolve()
	_title_label.add_theme_color_override("font_color", color)


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
func set_art(tex: Texture2D, min_size: Vector2 = Vector2(48, 48), fx_color := Color(0, 0, 0, 0)) -> void:
	_resolve()
	_icon_rect.texture = tex
	_icon_rect.custom_minimum_size = min_size
	_icon_rect.visible = tex != null
	if tex == null:
		return
	if fx_color.a > 0.0:
		_ensure_art_fx(fx_color, min_size)


func _ensure_art_fx(color: Color, min_size: Vector2) -> void:
	# 图标上的元素火星：1px 点、加色混合、极少数量，只做"活"的感觉，不做爆炸
	if _art_fx == null:
		_art_fx = CPUParticles2D.new()
		_art_fx.texture = PX1_TEX
		_art_fx.amount = 6
		_art_fx.lifetime = 2.1
		_art_fx.preprocess = 1.2
		_art_fx.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		_art_fx.emission_rect_extents = Vector2(9, 11)
		_art_fx.direction = Vector2(0, -1)
		_art_fx.spread = 26.0
		_art_fx.gravity = Vector2(0, -7)
		_art_fx.initial_velocity_min = 2.0
		_art_fx.initial_velocity_max = 6.0
		_art_fx.scale_amount_min = 1.0
		_art_fx.scale_amount_max = 1.0
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.0))
		g.add_point(0.22, Color(1, 1, 1, 1.0))
		g.add_point(0.7, Color(1, 1, 1, 0.75))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
		_art_fx.color_ramp = g
		_icon_rect.add_child(_art_fx)
	# 图格并非都是 48：商店 32、奖励 36、生涯解锁 24。粒子是 IconRect 的子节点，
	# 坐标相对图格左上；写死 48 口径会让火星飘到图标外，等于这把没加粒子。
	var k := clampf(minf(min_size.x, min_size.y) / 48.0, 0.45, 1.0)
	_art_fx.position = Vector2(28, 18) * k   # 图标对角线中上段（刃身）
	_art_fx.emission_rect_extents = Vector2(9, 11) * k
	_art_fx.color = color
	_art_fx.emitting = true


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
