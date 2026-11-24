extends Node

# S5-5 双式军刀可获得性实测探针（2026-11-21）
# 新档、线性房间、无 AnvilSystem。
# 分别核查：战斗武器奖励路径、商店、主题掉落、生涯定向候选、领取后装配。

const SABER := "res://resources/weapon_templates/dueling_saber.tres"

var _duel: DuelController

func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	_duel = duel
	await get_tree().process_frame
	await get_tree().process_frame
	duel.demo_config.enabled = false
	duel._confirm_loadout()
	await get_tree().process_frame

	var loot = duel._reward_system._loot

	# ① 各来源候选池是否含双式军刀（category=weapon）
	for source in ["normal", "elite", "boss", "shop", "chest"]:
		var pool: Dictionary = loot.candidates(source, 1, {"category": "weapon"})
		var items: Array = pool.get("items", [])
		var found := items.has(SABER)
		var uncommon_in_pool := 0
		for pth in items:
			var res = load(String(pth))
			if res != null and "rarity" in res and String(res.rarity) == "uncommon":
				uncommon_in_pool += 1
		print("CAND source=%s ok=%s total=%d uncommon=%d saber=%s" % [
			source, str(pool.get("ok", false)), items.size(), uncommon_in_pool, str(found)])

	# ② 强制 uncommon 抽取：战斗武器奖励路径是否真的能产出 saber
	for source in ["normal", "elite", "boss"]:
		var hits := 0
		var tries := 300
		for i in range(tries):
			var res: Dictionary = loot.roll(source, 1, {"category": "weapon"}, "uncommon")
			if String(res.get("path", "")) == SABER: hits += 1
		print("ROLL source=%s forced=uncommon saber_hits=%d/%d" % [source, hits, tries])

	# ③ 生涯定向候选是否含 saber + 排位
	var cands: Array = duel._career.directed_candidates()
	var saber_pos := -1
	for i in range(cands.size()):
		if String(cands[i].get("path", "")) == SABER: saber_pos = i; break
	print("CAREER candidates_total=%d saber_pos=%d first3=%s" % [
		cands.size(), saber_pos,
		str([cands[0].get("path", ""), cands[1].get("path", ""), cands[2].get("path", "")] if cands.size() >= 3 else [])])

	# ④ 逐次领取观察：saber 何时进入前三（模拟确定性队列前进）
	if saber_pos >= 0:
		var pos_now := saber_pos
		var rounds := 0
		while pos_now >= 3 and rounds < 40:
			var visible: Array = duel._career.directed_candidates().slice(0, 3)
			if visible.is_empty(): break
			duel._career._directed_balance += 1
			var r: Dictionary = duel._career.claim_directed(String(visible[0].get("path", "")))
			if not bool(r.get("ok", false)): break
			rounds += 1
			var newc: Array = duel._career.directed_candidates()
			pos_now = -1
			for i in range(newc.size()):
				if String(newc[i].get("path", "")) == SABER: pos_now = i; break
		print("QUEUE saber_enters_top3_after=%d claims final_pos=%d" % [rounds, pos_now])

	# ④b 商店实际货架：多次 roll_shop 检查 saber 是否出现
	var shop_hits := 0
	for i in range(60):
		duel._shop_system.roll_shop()
		for off in duel._shop_system.shop_offers:
			if String(off.get("path", "")) == SABER: shop_hits += 1
	print("SHOP saber_in_offers=%d over 60 rolls" % shop_hits)

	# ⑤ 通过生涯领取 saber 后写 owned_weapons + 下局可选配
	if saber_pos >= 0:
		duel._career._directed_balance += 1
		var r2: Dictionary = duel._career.claim_directed(SABER)
		print("CLAIM saber ok=%s reason=%s owned=%s" % [
			str(r2.get("ok", false)), String(r2.get("reason", "")),
			str((duel.meta.get("owned_weapons", []) as Array).has(SABER))])

	get_tree().quit(0)
