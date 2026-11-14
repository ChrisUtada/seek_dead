extends RefCounted

# ============================================================================
# MapProgress — 新地图的战斗奖励分流（Step 5B）
# 规格：docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md
#       §6 Step 5B 任务 1–5 与出口、§7「奖励 / 成长队列」
#
# 分流规则（不另立一套奖励逻辑，全部委托现有系统）：
#   battle  → post_battle.build("normal") → 补给 / 构筑 / 成长 三选一
#   elite   → post_battle.build("elite")  → 同三选一，但补给池含 elite_* 档、构筑池保证可给武器
#   boss    → reward_system.roll_boss_rewards(room) → 主题武器 / 信物 / 铁砧兜底
#   战败    → 不给奖励（节点仍消耗）
#
# 边界：
# - 本类只「生成卡片」与「结算历练」，不扣金币、不入腰带、不改掉落来源；
# - 成长只在本类 `apply_victory` 里结算一次，调用方必须保证每场战斗只调一次；
# - 宝箱 / 商店的装备获取仍走 MapReward（Step 5A），不在这里重复实现。
# ============================================================================

const PIPELINE_POST_BATTLE := "post_battle"
const PIPELINE_BOSS := "boss_loot"
const PIPELINE_NONE := "none"

# 与 growth_system.ROOM_XP 同口径。
const XP_BY_KIND := {"normal": 1, "elite": 2, "boss": 3}


# 节点 → 结算类型。巡逻遭遇按普通战处理（它本身就是一场普通战）。
static func kind_of(node: Dictionary) -> String:
	match String(node.get("type", "")):
		"battle", "patrol":
			return "normal"
		"elite":
			return "elite"
		"boss":
			return "boss"
	return ""


static func plan(node: Dictionary) -> Dictionary:
	var kind := kind_of(node)
	if kind == "":
		return {"pipeline": PIPELINE_NONE, "kind": "", "xp": 0, "cards": 0, "elite_bonus": false}
	if kind == "boss":
		return {"pipeline": PIPELINE_BOSS, "kind": kind,
			"xp": int(XP_BY_KIND.get(kind, 0)), "cards": 3, "elite_bonus": false}
	return {"pipeline": PIPELINE_POST_BATTLE, "kind": kind,
		"xp": int(XP_BY_KIND.get(kind, 0)), "cards": 3, "elite_bonus": kind == "elite"}


# 生成奖励卡（不发放）。boss 卡由 room 的主题池 / 信物决定，永不为空（含铁砧兜底）。
static func build(node: Dictionary, ctrl) -> Dictionary:
	var p: Dictionary = plan(node)
	var out := {
		"kind": String(p["kind"]), "pipeline": String(p["pipeline"]),
		"xp": int(p["xp"]), "cards": [],
	}
	if ctrl == null or String(p["pipeline"]) == PIPELINE_NONE:
		return out
	if String(p["pipeline"]) == PIPELINE_BOSS:
		out["cards"] = ctrl._reward_system.roll_boss_rewards(node.get("room"))
	else:
		out["cards"] = ctrl._post_battle.build(String(p["kind"]))
	out["growth_pending"] = int(ctrl.growth.pending_picks)
	out["queue_size"] = (ctrl._post_battle.queue as Array).size()
	return out


# 房间胜利：发历练 + 结算回春/积蓄（与 room_flow._settle_victory 同序）。
# 不碰掉落、不改房间数值、不发奖励卡。
static func apply_victory(node: Dictionary, ctrl) -> Dictionary:
	var kind := kind_of(node)
	if kind == "" or ctrl == null:
		return {"ok": false}
	var xp_before := int(ctrl.growth.xp)
	var level_before := int(ctrl.growth.level)
	ctrl.growth.grant_room_xp(kind)
	ctrl.growth.apply_victory_perks(kind)
	return {
		"ok": true,
		"kind": kind,
		"xp_gained": int(ctrl.growth.xp) - xp_before,
		"level": int(ctrl.growth.level),
		"level_up": int(ctrl.growth.level) > level_before,
		"pending": int(ctrl.growth.pending_picks),
	}
