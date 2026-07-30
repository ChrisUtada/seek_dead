class_name PickupSpawner
extends Node
## 拾取物（金币 / 血球 / 装备 / 技能球 / 附魔台 / 奖励）与技能升级 / 选择弹窗的生成。
## 由 RoomManager（autoload）实例化并 add_child；init(rm) 注入 RoomManager，以读取
## 当前房间 / 配置 / 玩家等共享状态。所有掉落落点兜底使用 RoomManager 的 DROP_CENTER 常量。

var _rm: Node = null


func init(rm: Node):
	_rm = rm


func _get_room() -> Node2D:
	return _rm.get_current_room()


## 敌死掉落（原 _on_enemy_died）：按 EnemyConfig 掉落表生成金币/血球/装备，
## 精英怪额外触发三选一技能面板。
func on_enemy_died(enemy: Node2D):
	var room = _get_room()
	if room == null:
		return
	var cfg = enemy.get_config() if enemy.has_method("get_config") else null
	var pos = enemy.global_position
	if cfg is EnemyConfig and cfg.loot_table != null:
		for d in cfg.loot_table.roll():
			match d.type:
				LootEntry.ItemType.GOLD:
					spawn_gold_pickup(pos, d.amount)
				LootEntry.ItemType.HEAL:
					spawn_health_pickup(pos, d.amount)
				LootEntry.ItemType.EQUIPMENT:
					spawn_equip_drop(pos, d.quality_bonus, d.get("equip_template", null))
	else:
		var heal = cfg.drop_heal if cfg is EnemyConfig and cfg.drop_heal > 0 else 0
		var chance = cfg.drop_heal_chance if cfg is EnemyConfig else 0.0
		if heal > 0 and randf() < chance:
			spawn_health_pickup(pos, heal)
		var is_elite = enemy.is_in_group("elite")
		if is_elite or randf() < 0.6:
			var gold_val = 10 + randi() % 16
			if cfg is EnemyConfig and cfg.drop_gold > 0:
				gold_val = cfg.drop_gold
			spawn_gold_pickup(pos, gold_val)
		if cfg is EnemyConfig and cfg.drop_equip_chance > 0 and randf() < cfg.drop_equip_chance:
			spawn_equip_drop(pos, cfg.drop_equip_quality_bonus)
	if enemy.is_in_group("elite"):
		var cur_cfg = _rm.get_current_config()
		if not cur_cfg or not cur_cfg.has_elite:
			return
		show_skill_choice()


## 清房奖励（RoomManager._on_room_cleared 调用）：50% 概率弹出技能升级面板，
## 否则刷一个技能球。
func show_skill_upgrade():
	var player = _rm.get_player()
	if not player:
		return
	var sm = player.get_node_or_null("SkillManager") as SkillManager
	if not sm or sm.skills.is_empty():
		spawn_skill_pickup()
		return
	var hud = get_tree().root.find_child("HUD", true, false)
	if hud and hud.has_method("show_skill_upgrade"):
		var all_max = true
		for sk in sm.skills:
			if sk.level < sk.max_level:
				all_max = false
				break
		if all_max:
			spawn_skill_pickup()
		else:
			hud.show_skill_upgrade(sm)


func show_skill_choice():
	var player = _rm.get_player()
	if not player:
		return
	var hud = get_tree().root.find_child("HUD", true, false)
	if hud and hud.has_method("show_skill_choice"):
		var skills = SkillDatabase.get_all_skills()
		if skills.size() == 0:
			return
		skills.shuffle()
		var choices = skills.slice(0, 3)
		hud.show_skill_choice(choices)


func spawn_rewards(items: Array[EquipmentBase]):
	var room = _get_room()
	if room == null:
		return
	var center = _rm.get_drop_center()
	var spawn = room.find_child("PlayerSpawn", true, false)
	if spawn:
		center = spawn.global_position + Vector2(0, 60)
	var spread = 40
	for i in range(items.size()):
		var drop = EquipmentPickup.new()
		var pos = center + Vector2((i - (items.size() - 1) * 0.5) * spread, 0)
		room.add_child(drop)
		drop.global_position = pos
		drop.setup(items[i])


func spawn_equip_drop(world_pos: Vector2, quality_bonus: float, template: Resource = null):
	var room = _get_room()
	if room == null:
		return
	var item = EquipmentDrop.generate_drop(quality_bonus, -1, -1, template)
	var drop = EquipmentPickup.new()
	room.add_child(drop)
	drop.global_position = world_pos + Vector2(randf_range(-8, 8), randf_range(-8, 8))
	drop.call_deferred("setup", item)


func spawn_health_pickup(world_pos: Vector2, amount: int):
	var room = _get_room()
	if room == null:
		return
	var drop = HealthPickup.new()
	room.add_child(drop)
	drop.global_position = world_pos + Vector2(randf_range(-10, 10), randf_range(-10, 10))
	drop.setup(amount)


func spawn_gold_pickup(world_pos: Vector2, value: int):
	var room = _get_room()
	if room == null:
		return
	var drop = GoldPickup.new()
	room.add_child(drop)
	drop.global_position = world_pos + Vector2(randf_range(-10, 10), randf_range(-10, 10))
	drop.setup(value)


func spawn_enchantment_table():
	var room = _get_room()
	if room == null:
		return
	var table = EnchantmentTable.new()
	room.add_child(table)
	var center = _rm.get_drop_center()
	var offset = Vector2(randf_range(-100, 100), randf_range(-80, 80))
	table.global_position = center + offset


func spawn_skill_pickup():
	var room = _get_room()
	if room == null:
		return
	var sk = SkillDatabase.get_random_skill()
	if not sk:
		return
	var center = _rm.get_drop_center()
	var spawn = room.find_child("PlayerSpawn", true, false)
	if spawn:
		center = spawn.global_position + Vector2(0, 60)
	var drop = SkillPickup.new()
	room.add_child(drop)
	drop.global_position = center + Vector2(randf_range(-20, 20), -20)
	drop.setup(sk)


func get_player_inventory() -> EquipmentInventory:
	var player = _rm.get_player()
	if not player:
		return null
	return player.get_node_or_null("EquipmentInventory") as EquipmentInventory
