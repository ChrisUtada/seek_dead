class_name LoadoutSystem
extends RefCounted

# T22：平衡常量收敛于 BalanceConfig（balance_config.tres）
const BALANCE = preload("res://resources/config/balance_config.tres")

# 整备勾选 / 槽位上限与成长 / 拥有池读取——从 duel_controller.gd 抽出。
#
# 由 controller 在 _ready 处实例化并注入：LoadoutSystem.new(ctrl)。
# 约定（与 docs/[已完成]duel_controller拆分方案B.md 步骤5一致，延续步骤1–4 的写法）：
# - 勾选状态 selected_loadout / selected_consumables / selected_charms / selected_skills 与槽位上限
#   loadout_max / skill_max / charm_max 仍由 controller 持有，本子系统经 _ctrl.xxx 读写（方案B §4 状态归属表）。
# - @export 常量（SLOT_INIT / CHARM_CAP / UNCAPPED / LOADOUT_MIN 等）留 controller，
#   本子系统动态读 _ctrl.xxx（RefCounted 无法在 Inspector 编辑）。
# - 战斗强耦合的 _confirm_loadout（触发 _full_reset / _build_pool 战斗准备）与 _apply_charms
#   （写 charm_* 战斗字段）留在 controller，不迁入。
# - ctrl 标类型 DuelController（已加 class_name），成员访问获得编译期检查。

var _ctrl: DuelController          # DuelController 实例（类型标注，编译期检查）

func _init(ctrl: DuelController) -> void:
	_ctrl = ctrl


# ---------------------------------------------------------------------------
# 整备勾选
# ---------------------------------------------------------------------------

func on_card_toggled(card: Dictionary) -> void:
	var cat = card.kind
	var arr = sel_arr(cat)
	if card["selected"]:
		card["selected"] = false
		arr.erase(card["path"])
	else:
		if arr.size() >= cat_max(cat):
			_ctrl.hud._log("%s已达上限 %d" % [cat_name(cat), cat_max(cat)])
			return
		card["selected"] = true
		arr.append(card["path"])
	_ctrl.hud._update_loadout_cards_visual()
	_ctrl.hud._update_loadout_count()
	_ctrl.invalidate_state()


func sel_arr(cat: String) -> Array:
	match cat:
		"weapon":  return _ctrl.selected_loadout
		"active":  return _ctrl.selected_consumables
		"passive": return _ctrl.selected_charms
		"skill":    return _ctrl.selected_skills
	return []


# 该类【当前】上限（随商店「买即开槽」成长）
func cat_max(cat: String) -> int:
	match cat:
		"weapon":  return _ctrl.loadout_max
		"active":  return int(BALANCE.slot_init["active"])   # 整备勾选上限 = 1（腰带容量见 CONSUMABLE_CAP）
		"passive": return _ctrl.charm_max
		"skill":    return _ctrl.skill_max
	return 0


# 该类【天花板】（当前上限的成长终点）。返回 UNCAPPED(-1) 表示无天花板（进池类）。
func cat_cap(cat: String) -> int:
	match cat:
		"weapon":  return 2   # 2026-08-07 用户拍板：武器上限 2（主手+副手），商店不可买第 3 把
		"skill":    return 3   # 2026-08-10 用户拍板：技能槽硬上限 3（初始 1 → 商店买到 3 封顶）——防技能符号无限挤占主输出带子（武器硬限 2 的不对称稀释，见 docs/[已完成]整备结构_技能槽上限与频率规范.md）
		"active":  return int(BALANCE.slot_init["active"])   # 整备天花板 = 1（消耗品不「买即开槽」，改为腰带追加，容量见 CONSUMABLE_CAP）
		"passive": return _ctrl.CHARM_CAP
	return 0


# 该类是否还能继续「买即开槽」（无天花板恒为 true）
func can_grow_slot(cat: String) -> bool:
	var ceiling = cat_cap(cat)
	return ceiling == _ctrl.UNCAPPED or cat_max(cat) < ceiling


# 天花板的显示文本（无天花板显示 ∞），供日志与 UI 复用
func cap_text(cat: String) -> String:
	var ceiling = cat_cap(cat)
	return "∞" if ceiling == _ctrl.UNCAPPED else str(ceiling)


# 「买即开槽」：把该类当前上限 +1（有天花板则不越过）
func grow_slot(cat: String) -> void:
	var ceiling = cat_cap(cat)
	match cat:
		"weapon":  _ctrl.loadout_max = (_ctrl.loadout_max + 1 if ceiling == _ctrl.UNCAPPED else min(_ctrl.loadout_max + 1, ceiling))
		"skill":   _ctrl.skill_max   = (_ctrl.skill_max + 1 if ceiling == _ctrl.UNCAPPED else min(_ctrl.skill_max + 1, ceiling))
		"passive": _ctrl.charm_max   = min(_ctrl.charm_max + 1, ceiling)
	_ctrl.invalidate_state()


func cat_name(cat: String) -> String:
	match cat:
		"weapon":  return "武器"
		"active":  return "消耗品"
		"passive": return "护符"
		"skill":    return "技能"
	return cat


func owned_arr(kind: String) -> Array:
	# 整备屏/商店读取拥有池（盘外跨局）。skills 暂用全池（待扩 owned_skills）。
	match kind:
		"weapon":  return _ctrl.meta["owned_weapons"]
		"passive": return _ctrl.meta["owned_charms"]
		"active":  return _ctrl.meta["owned_consumables"]
		"skill":   return _ctrl.SKILL_POOL
		_:         return []
