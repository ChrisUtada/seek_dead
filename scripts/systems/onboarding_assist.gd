class_name OnboardingAssist
extends RefCounted

# ============================================================================
# G7-5 新手引导与辅助选项（2026-11-20）
# 权威方案 §11.4：首局只教四件事，不堆教程弹窗；回路/签名/铸式遇到时再解释。
# §11.3：速度/预览辅助选项与奖励遥测分开记录。
#
# 纯查询 + 一次性提示：注入 ctrl；提示走 HUD._log（不弹窗）；进度写 meta 跨局保留。
# ============================================================================

const META_KEY := "onboarding"

# 首局四件事（按玩家自然 encounter 顺序）
const STEPS := [
	{"id": "stop", "text": "💡 按停落线符号即结算；空格/回车可停当前列。"},
	{"id": "weapon", "text": "💡 武器决定符号带：换武器会真实改变带内符号与格数。"},
	{"id": "draft", "text": "💡 战后三选一会真实改造机器，下一场就能感知变化。"},
	{"id": "intent", "text": "💡 敌人意图提示本回合对策，按提示调整按停目标。"},
]

var _ctrl


func _init(ctrl) -> void:
	_ctrl = ctrl


func _state() -> Dictionary:
	var meta = _ctrl.meta
	if not (meta is Dictionary):
		return {}
	var st = meta.get(META_KEY, {})
	return st if st is Dictionary else {}


# 该步骤是否已提示过
func is_shown(id: String) -> bool:
	return bool(_state().get("shown", {}).get(id, false))


# 首次遇到某情境时给一句提示；返回是否实际提示了。
# id 取 STEPS 的 id，或用 "circuit"/"forge_style"/"signature" 做 contextual 解释。
func hint(id: String) -> bool:
	if is_shown(id):
		return false
	var text := _text_for(id)
	if text.is_empty():
		return false
	# 标记已提示（跨局保留）
	var meta = _ctrl.meta
	if not (meta is Dictionary):
		return false
	var st: Dictionary = meta.get(META_KEY, {}).duplicate(true)
	if not (st.get("shown") is Dictionary):
		st["shown"] = {}
	st["shown"][id] = true
	meta[META_KEY] = st
	if _ctrl._meta_store != null:
		_ctrl._meta_store.save_meta()
	if _ctrl.hud != null:
		_ctrl.hud._log(text)
	return true


func _text_for(id: String) -> String:
	for s in STEPS:
		if String(s["id"]) == id:
			return String(s["text"])
	# contextual：遇到时才解释（不在开局堆）
	match id:
		"circuit":
			return "💡 回路：本局习得的事件监听，占 2 槽；装备后按声明事件触发。"
		"forge_style":
			return "💡 铸式：武器的横向形态，有优势也有代价；达成行为条件后可解锁。"
		"signature":
			return "💡 签名：专属武器自带的牌谱效果，随武器生效。"
	return ""


# 首局四件事是否全部提示完
func all_done() -> bool:
	for s in STEPS:
		if not is_shown(String(s["id"])):
			return false
	return true


# ---- 辅助选项来源标注（§11.3：与奖励遥测分开）----

# 当前速度/预览设置的来源：assist（玩家主动辅助选项）/ reward（奖励卡）/ default
func assist_source() -> String:
	var rd = _ctrl.readability
	if rd == null:
		return "none"
	# 奖励卡 slow_ramp 走 reel_controls；辅助预设走 readability.preset
	var from_reward: bool = _ctrl.reel_controls.has("slow_ramp") if (_ctrl.reel_controls is Dictionary) else false
	if from_reward and String(rd.preset) == "control":
		return "reward"
	if String(rd.preset) == "readable":
		return "assist"
	return "default"


# 供遥测记录的辅助快照（与 reward_choices 等奖励数据分离）
func assist_snapshot() -> Dictionary:
	var rd = _ctrl.readability
	return {
		"source": assist_source(),
		"preset": String(rd.preset) if rd != null else "",
		"preview_slots": int(rd.preview_slots) if rd != null else 0,
	}
