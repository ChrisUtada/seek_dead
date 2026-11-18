class_name RewardPresentation
extends RefCounted

# 战后三选一重构 P1：DraftResult → UI view 数据契约（Presentation Model）。
#
# 职责：把新系统的 RewardDefinition 翻译成现有 reward_screen / card_factory 能读的 view 字典，
# 让 UI 改动最小化。UI 只展示，不执行效果（v2.0 §20.5）。
#
# 字段兼容现有 loot_offer_card(opt)（card_factory.gd:243）：
#   quality / quality_name / title / result / condition / tooltip / icon
# 卡面标题格式 "【品质名】标题" + set_title_color 已由 card_factory 实现，
# 天然满足附录 B.4「卡面直接显示品质名与颜色」。

const QUALITY_LABELS := {
	"common": "普通", "uncommon": "进阶", "rare": "稀有", "epic": "传说"
}


# 把一次 Draft 转成 reward_screen.show_loot_offer(view) 可读的字典。
static func draft_to_view(draft: DraftResult, source_label: String = "战利品") -> Dictionary:
	var options: Array[Dictionary] = []
	for def in draft.rewards:
		options.append(definition_to_option(def))
	return {
		"ok": not draft.rewards.is_empty(),
		"source_label": source_label,
		# 新系统三张卡品质各异，不再写"同层三选一"（B.4）
		"quality_name": "",
		"growth_only": true,
		"options": options,
		"draft_id": draft.draft_id,
	}


# 单张卡 → option 字典（字段对齐 card_factory.loot_offer_card）。
static func definition_to_option(def: RewardDefinition) -> Dictionary:
	var q := def.rarity
	var qname := String(QUALITY_LABELS.get(q, q))
	var params := _first_params(def)
	var effect_id := def.first_effect_id()

	return {
		"kind": "reward_definition",
		"id": def.id,
		"quality": q,
		"quality_name": qname,
		"title": def.name,
		"desc": def.desc,
		"result": _result_text(def, params),
		"condition": _condition_text(def),
		"tooltip": def.desc,
		"icon": def.icon,
		"icon_glyph": _glyph(effect_id),   # 无美术时的 emoji 占位（card_factory 暂未用，供后续接入）
		"effect_id": effect_id,
		"tags": def.tags,
	}


static func _glyph(effect_id: String) -> String:
	match effect_id:
		"heal": return "✚"
		"shield_next_battle": return "🛡"
		"run_power_bonus": return "⚔"
		"flame_affinity": return "🔥"
		_: return "🎁"


static func _first_params(def: RewardDefinition) -> Dictionary:
	if def.effects.is_empty():
		return {}
	var e: Dictionary = def.effects[0]
	var p = e.get("params", {})
	return p if p is Dictionary else {}


# 结果文案：优先用卡自己的 desc；没有则用 effect_id + params 生成简短结果。
static func _result_text(def: RewardDefinition, params: Dictionary) -> String:
	if not def.desc.is_empty():
		return def.desc
	match def.first_effect_id():
		"heal": return "恢复生命"
		"shield_next_battle": return "下战护盾 +%d" % int(params.get("amount", 10))
		"run_power_bonus": return "本局伤害 +%d" % int(params.get("amount", 2))
		"flame_affinity": return "火焰构筑 +%d" % int(params.get("amount", 1))
		_: return def.name


# 条件文案：本局/下一战/触发后消失等生效范围提示（B.4 要求醒目）。
static func _condition_text(def: RewardDefinition) -> String:
	match def.first_effect_id():
		"shield_next_battle": return "下一战生效"
		"run_power_bonus": return "本局生效"
		"flame_affinity": return "本局构筑"
		_: return ""
