extends Button

# 整备屏物品卡专用按钮脚本（2026-11-08 排版验收）。
# ui_button.tscn 本身没有脚本，无法返回富文本悬停窗；card_factory 造整备物品卡时
# set_script 挂上本脚本，其余 ui_button 实例（商店/铁砧/棋盘/战斗 HUD）不受影响。
# 生成器与 ItemCard 相同：ItemTooltip（见 docs/物品悬停信息窗_设计.md）。
func _make_custom_tooltip(for_text: String) -> Control:
	if for_text.is_empty():
		return null
	return ItemTooltip.tooltip_label(for_text)
