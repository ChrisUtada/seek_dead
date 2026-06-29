class_name RoomContext
extends RefCounted


enum RoomSize { SMALL, MEDIUM, LARGE, BOSS }


static func get_current_room_size() -> int:
	if not RoomManager or not RoomManager.has_method("get_current_room_size"):
		return RoomSize.SMALL
	return RoomManager.get_current_room_size()


static func get_enemy_count() -> int:
	return EntityRegistry.get_enemy_count()


static func get_wave_index() -> int:
	if not RoomManager or not RoomManager.has_method("get_current_wave_index"):
		return 0
	return RoomManager.get_current_wave_index()


static func scale_chance(base_chance: float, event: int) -> float:
	var room_size = get_current_room_size()
	var enemies = get_enemy_count()
	var scaled = base_chance
	match room_size:
		RoomSize.MEDIUM:
			scaled += enemies * 0.02
		RoomSize.LARGE:
			scaled += enemies * 0.03
		RoomSize.BOSS:
			scaled += enemies * 0.04
	return clamp(scaled, 0.0, 1.0)


static func scale_radius(base_radius: float) -> float:
	var room_size = get_current_room_size()
	var enemies = get_enemy_count()
	match room_size:
		RoomSize.MEDIUM:
			return base_radius * (1.0 + enemies * 0.05)
		RoomSize.LARGE:
			return base_radius * (1.0 + enemies * 0.08)
		RoomSize.BOSS:
			return base_radius * (1.0 + enemies * 0.10)
	return base_radius


static func scale_chain_count(base_count: int) -> int:
	var room_size = get_current_room_size()
	var enemies = get_enemy_count()
	match room_size:
		RoomSize.LARGE:
			return mini(base_count + 2, enemies)
		RoomSize.BOSS:
			return mini(base_count + 4, enemies)
	return mini(base_count, enemies)


static func scale_projectile_count(base_count: int) -> int:
	var enemies = get_enemy_count()
	return base_count + floori(enemies / 5.0)


static func scale_damage(base_damage: float) -> float:
	var wave = get_wave_index()
	return base_damage * (1.0 + wave * 0.15)
