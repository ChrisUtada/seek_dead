extends Resource

class_name PatternData

# ============================================================================
# PatternData —— 牌谱资源定义（2026-11-15，转轮凑牌 Step 1）
# 方案：docs/转轮凑牌战斗重构_24种牌型与制作执行方案_2026-11-15.md §9.1
#
# 通用牌型（G01–G04）与装备牌谱（S01–S20）共用这套字段：
# 判定条件放在 match_rule 里，由 PatternMatcher / PatternSystem 解析，
# 不允许在 UI 或 24 个独立 if 里各写一份判定。
# ============================================================================

@export var id: String = ""
@export var name: String = ""
@export var desc: String = ""
@export var icon: String = ""
# universal（通用牌型，玩家总有）| equipment（装备牌谱，需要解锁）
@export var kind: String = "equipment"
# 三轨（2026-11-15 转轮凑牌 Step 2）：
#   weapon_public  公共武器牌型（G01-G03），只读武器牌
#   weapon_attack  武器攻击牌谱（W01-W06），只读武器牌
#   skill_support  技能辅助术式（T01-T03），恰好一张技能牌 + 两张武器牌
@export var track: String = "weapon_attack"
# 同时满足多条装备牌谱时的处理顺序：数值大的先。同优先级按 id 升序。
@export var priority: int = 0
# 解锁条件：三选一（路径精确 / 标签 / 数量），任一满足即可
@export var unlock_paths: Array[String] = []
@export var unlock_tags: Array[String] = []
@export var unlock_count: int = 0
# 判定条件（结构化，由匹配器解释）：{"all": [...], "any": [...]} 形式
@export var match_rule: Dictionary = {}
# 效果标识与参数：结算层按 effect_id 找实现，本资源不写数值逻辑
@export var effect_id: String = ""
@export var effect_params: Dictionary = {}
# 装备牌谱是否允许被「连携卷轴」补牌凑成；通用牌型固定 false
@export var assist_allowed: bool = true
# 顺子用（G04 及序列类牌谱）：同 sequence_id、rank 1/2/3
@export var sequence_id: String = ""


func is_universal() -> bool:
	return kind == "universal"


# 该牌谱在当前构筑下是否满足解锁条件。
# 语义（AND）：unlock_paths 里的**每一条**都要装备；unlock_tags 里的**每一个**标签
# 都要有至少 unlock_count 件（默认 1 件）装备满足。
#   S01「两件火装备」   = tags ["element:fire"], count 2
#   S02「冰火各一件」   = tags ["element:ice","element:fire"], count 1
#   S03「圣辉长剑+破晓之弓」= paths [两者], 全都要有
# loadout_paths：当前武器/护符路径；tag_of：Callable(path) -> Array[String]
func unlocked(loadout_paths: Array, tag_of: Callable) -> bool:
	if is_universal():
		return true
	# 既没有路径条件也没有标签条件 = 无解锁门槛（测试牌谱、以及未来的「 zawsze 可用」类内容）
	if unlock_paths.is_empty() and unlock_tags.is_empty():
		return true
	if not unlock_paths.is_empty():
		var all_have := true
		for p in unlock_paths:
			if not loadout_paths.has(String(p)):
				all_have = false
				break
		if all_have:
			return true
	if not unlock_tags.is_empty():
		var need := maxi(1, unlock_count)
		var ok_all := true
		for t in unlock_tags:
			var matched := 0
			for p in loadout_paths:
				var tags: Array = tag_of.call(String(p))
				if tags != null and (tags as Array).has(String(t)):
					matched += 1
			if matched < need:
				ok_all = false
				break
		if ok_all:
			return true
	return false
