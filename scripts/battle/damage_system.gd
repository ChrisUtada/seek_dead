class_name DamageSystem
extends RefCounted

enum DamageType {
	PUNCTURE,
	SLASH,
	SMASH,
	FIRE,
	LIGHTNING,
	ICE,
	POISON,
	WIND
}

enum HitResult {
	NORMAL,
	CRITICAL,
	RESISTED,
	WEAKNESS
}

# 属性克制表: [攻击类型] = {克制类型: 倍率}
const TYPE_ADVANTAGE: Dictionary = {
	DamageType.SLASH: { DamageType.POISON: 1.5, DamageType.WIND: 1.2 },
	DamageType.SMASH: { DamageType.ICE: 1.5, DamageType.SLASH: 1.2 },
	DamageType.PUNCTURE: { DamageType.LIGHTNING: 1.5, DamageType.SMASH: 1.2 },
	DamageType.FIRE: { DamageType.POISON: 1.3, DamageType.ICE: 1.5 },
	DamageType.ICE: { DamageType.FIRE: 0.8, DamageType.WIND: 1.3 },
	DamageType.LIGHTNING: { DamageType.WIND: 1.3, DamageType.ICE: 0.8 },
	DamageType.POISON: { DamageType.FIRE: 0.8, DamageType.LIGHTNING: 0.8 },
	DamageType.WIND: { DamageType.POISON: 1.3, DamageType.LIGHTNING: 1.3 },
}

static func calculate(attacker: CombatStats, defender: CombatStats, damage_type: DamageType, base_damage: float) -> Dictionary:
	var result = {
		damage = base_damage,
		hit_result = HitResult.NORMAL,
		final_damage = 0.0,
		is_critical = false,
		is_resisted = false,
		is_weakness = false,
		breakdown = {}
	}

	# 1. 攻击加成
	var attack_bonus = attacker.bonus_for(damage_type)
	result.damage *= (1.0 + attack_bonus)
	result.breakdown["attack_bonus"] = attack_bonus
	result.breakdown["after_attack_bonus"] = result.damage

	# 2. 防御减免
	var defense_ratio = defender.defense_for(damage_type)
	defense_ratio = clamp(defense_ratio, 0.0, 0.85)
	result.damage *= (1.0 - defense_ratio)
	result.breakdown["defense_ratio"] = defense_ratio
	result.breakdown["after_defense"] = result.damage
	result.is_resisted = defense_ratio > 0.5

	# 3. 属性克制
	var advantage = _get_type_advantage(damage_type, defender.innate_type)
	if advantage != 1.0:
		result.damage *= advantage
		result.breakdown["type_advantage"] = advantage
		result.breakdown["after_type"] = result.damage
		if advantage > 1.0:
			result.is_weakness = true
		else:
			result.is_resisted = true

	# 4. 暴击
	var crit_rate = attacker.crit_rate
	var crit_dmg = attacker.crit_damage
	result.is_critical = randf() < crit_rate
	if result.is_critical:
		result.damage *= crit_dmg
		result.breakdown["crit_damage"] = crit_dmg
		result.hit_result = HitResult.CRITICAL
	result.breakdown["after_crit"] = result.damage

	# 5. 最终伤害（整数）
	result.final_damage = round(max(result.damage, 1.0))

	# 判定命中结果
	if result.is_weakness:
		result.hit_result = HitResult.WEAKNESS
	elif result.is_resisted:
		result.hit_result = HitResult.RESISTED

	return result

static func calculate_simple(base_damage: float, damage_type: DamageType, target: CombatStats = null) -> float:
	var defense = target.defense_for(damage_type) if target != null else 0.0
	return round(max(base_damage * (1.0 - clamp(defense, 0.0, 0.9)), 1.0))

static func get_color(damage_type: DamageType) -> Color:
	match damage_type:
		DamageType.PUNCTURE: return Color(0.8, 0.8, 0.8)
		DamageType.SLASH: return Color(1.0, 0.8, 0.6)
		DamageType.SMASH: return Color(0.6, 0.4, 0.2)
		DamageType.FIRE: return Color(1.0, 0.4, 0.1)
		DamageType.LIGHTNING: return Color(0.6, 0.6, 1.0)
		DamageType.ICE: return Color(0.4, 0.8, 1.0)
		DamageType.POISON: return Color(0.4, 1.0, 0.4)
		DamageType.WIND: return Color(0.8, 1.0, 1.0)
	return Color.WHITE

static func hit_result_to_string(r: HitResult) -> String:
	match r:
		HitResult.CRITICAL: return "暴击!"
		HitResult.RESISTED: return "抵抗"
		HitResult.WEAKNESS: return "弱点!"
		_: return ""

static func _get_type_advantage(attack_type: DamageType, defender_innate_type: int) -> float:
	if defender_innate_type < 0:
		return 1.0
	if TYPE_ADVANTAGE.has(attack_type) and TYPE_ADVANTAGE[attack_type].has(defender_innate_type):
		return TYPE_ADVANTAGE[attack_type][defender_innate_type]
	return 1.0

static var _texture_cache: Dictionary = {}

static func get_circle_texture(size: int, outer_color: Color, inner_color: Color = Color(-1, -1, -1)) -> Texture2D:
	var key = "%d_%s" % [size, outer_color.to_html(false)]
	if inner_color.a >= 0:
		key += "_" + inner_color.to_html(false)
	if _texture_cache.has(key):
		return _texture_cache[key]
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var radius = size >> 1
	var inner_r2 = (radius * radius) >> 1
	for x in range(size):
		for y in range(size):
			var dx = x - radius
			var dy = y - radius
			var d = dx * dx + dy * dy
			if d < radius * radius:
				if inner_color.a >= 0 and d < inner_r2:
					img.set_pixel(x, y, inner_color)
				else:
					img.set_pixel(x, y, outer_color)
	var tex = ImageTexture.create_from_image(img)
	_texture_cache[key] = tex
	return tex

static func damage_type_to_string(t: DamageType) -> String:
	match t:
		DamageType.PUNCTURE: return "穿刺"
		DamageType.SLASH: return "斩击"
		DamageType.SMASH: return "打击"
		DamageType.FIRE: return "火焰"
		DamageType.LIGHTNING: return "雷电"
		DamageType.ICE: return "冰霜"
		DamageType.POISON: return "毒素"
		DamageType.WIND: return "风系"
	return "未知"
