class_name ChapterInfo
extends RefCounted

# M-02b 章节头 / Boss 信息公开 —— 只读数据契约（2026-11-23）。
# 纯函数：只从 RoomData 与元素克制表读取客观信息，不读 RNG、不改战斗状态、不生成文案推荐。
# 机制文案唯一源 = RoomData.mechanic_summary；不从 gimmick 脚本动态生成。
# 真·最终 Boss（final_boss=true）不纳入普通幕章节头。

const EC = preload("res://scripts/battle/element_counter.gd")
const Palette = preload("res://scripts/ui/palette.gd")

# 本幕房间流程摘要（kind -> 中文标签）。只展示顺序，不暴露具体房间名。
const FLOW_LABEL := {
	"normal": "普通", "elite": "精英", "chest": "宝箱", "event": "事件",
	"camp": "营地", "boss": "Boss",
}

# 每幕简短氛围描述（客观氛围文案，非推荐/准备方向）。只读常量表。
const AMBIENCE := {
	1: "锈火初燃，旧城的阴影尚浅。",
	2: "铜锈深处，镜中的自己开始回望。",
	3: "万象归影，最后的对手就在幕布之后。",
}


# 返回给定幕的章节头数据字典；无常规 Boss 时返回空字典。
# run_rooms 必须是本局 ROOMS（由 _build_run 抽定的 24+1 房），
# 不是 ALL_ROOMS 全量池——传错会显示别的 Boss 并列出整池房型。
# act: int（1..3）。
static func for_run(run_rooms: Array, act: int) -> Dictionary:
	if run_rooms.is_empty() or act < 1 or act > 3:
		return {}
	var boss_room: RoomData = null
	for r in run_rooms:
		if not (r is RoomData):
			continue
		if int(r.act) != act:
			continue
		if String(r.kind) != "boss":
			continue
		if bool(r.final_boss):   # 真·最终不进普通幕章节头
			continue
		boss_room = r
		break
	if boss_room == null:
		return {}

	# 本幕房间顺序摘要（按 run_rooms 出现顺序，过滤非本幕与真·最终）
	var flow: Array[String] = []
	for r in run_rooms:
		if not (r is RoomData) or int(r.act) != act:
			continue
		if bool(r.final_boss):
			continue
		var lbl: String = String(FLOW_LABEL.get(String(r.kind), String(r.kind)))
		flow.append(lbl)

	var elem: String = String(boss_room.element)
	var weak: Array[String] = EC.weakness(elem)
	var resist: Array[String] = EC.resists(elem)
	var weak_labels: Array[String] = []
	for e in weak:
		weak_labels.append(EC.label(e))
	var resist_labels: Array[String] = []
	for e in resist:
		resist_labels.append(EC.label(e))

	return {
		"act": act,
		"chapter_name": Palette.act_name(act),
		"ambience": String(AMBIENCE.get(act, "")),
		"boss": boss_room,
		"boss_name": String(boss_room.name),
		"boss_art": boss_room.art,
		"boss_element": elem,
		"boss_element_label": EC.label(elem),
		"weakness": weak_labels,
		"resistance": resist_labels,
		"mechanic_summary": String(boss_room.mechanic_summary),
		"flow": flow,
	}


# 是否应在本幕显示章节头：存在常规 Boss 且尚未显示过（显示状态由调用方/流程层持有）。
static func has_chapter_boss(run_rooms: Array, act: int) -> bool:
	return not for_run(run_rooms, act).is_empty()
