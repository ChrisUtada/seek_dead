extends RefCounted

# G8 第二切片（2026-11-08）：卡片构造从 battle_hud.gd 抽出。
#
# 职责：只按数据造控件（ItemCard / ui_button），不持有局内状态、不做布局挂载；
# 点击信号仍由 HUD 发出（`_hud.<signal>.emit`），所以外部监听点与调用点完全不变。
# HUD 保留同名薄包装（`_make_reward_card` / `_make_shop_card` / `_source_tag` 等），
# reward_screen / shop_screen / meta_screen / loadout_scene / 测试可直接沿用旧接口。
#
# 边界：不改任何数值、文案与布局参数；卡片外观必须与原实现逐字段一致。

const ITEM_CARD = preload("res://scenes/ui/item_card.tscn")
const UI_BUTTON = preload("res://scenes/ui/ui_button.tscn")
const ITEM_BUTTON = preload("res://scripts/ui/item_button.gd")   # 整备卡悬停信息窗

var _hud            # BattleHud
var _ctrl           # DuelController


func _init(hud, ctrl) -> void:
	_hud = hud
	_ctrl = ctrl


# 来源标签：让玩家一眼看懂「同一效果为何出现在不同分类（常驻/主动/转轮）」
func source_tag(kind: String) -> String:
	match kind:
		"weapon":  return "【武器】"
		"passive": return "【常驻】"
		"active":  return "【主动】"
		"skill":   return "【转轮】"
		_:         return ""


# 整备屏物品卡（返回 card 字典，选中态由调用方维护）
func item_card(data: Resource, path: String, kind: String) -> Dictionary:
	# 重要：根节点是 Button（来自 ui_button.tscn），它只渲染自己 text 字段。
	# 之前 btn.add_child(VBox) 是被 Button 忽略的——必须用 \n 拼多行 + 紧凑 line_spacing。
	var btn = UI_BUTTON.instantiate()
	btn.set_script(ITEM_BUTTON)   # 富文本悬停窗：本文件末尾 _short_desc 只放摘要
	btn.custom_minimum_size = Vector2(0, 26)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_constant_override("line_spacing", 0)
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	# 2026-11-08 整备屏排版验收：176px 卡宽下技能/护符描述（最宽 591px）原本被 clip_text 直接裁掉，
	# 玩家看不到生效条件。改为自动换行 + 不裁切，卡片高度按内容长；列表本来就可滚动。
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.clip_text = false
	btn.text = ""
	var title := ""
	var line1 := ""   # 图标/核心信息
	var line2 := ""   # 数值/权重
	var line3 := ""   # 武器第三行（暴击/机制），见下方拆行说明
	if kind == "weapon":
		title = data.weapon_name if (data != null) else path.get_file().get_basename()
		if data != null:
			var wd := data as WeaponData
			# line1 = 符号概览（主攻 + 特殊机制符号的 label，不显示权重——2026-08-07 重构后武器只带主攻+机制）
			if wd != null and wd.symbols != null and not wd.symbols.is_empty():
				var parts := []
				for sw in wd.symbols:
					if sw == null or sw.symbol == null:
						continue
					parts.append(sw.symbol.label)
				line1 = "🗡️ " + " ".join(parts)
			# line2 = 强度轴（2026-08-09 更新）：攻击力 · 元素 · 命中率 · 非三连暴击率 · 特殊机制（MISS 恢复后命中率复活）
			var elem_txt := "无"
			if wd != null and wd.element != "":
				elem_txt = ElementCounter.label(wd.element)
			var crit_total: int = int((_ctrl.BALANCE.crit_chance + (wd.crit_chance if wd != null else 0.0)) * 100)
			var hit_pct: int = int(_ctrl.weapon_hit(path) * 100)
			var mech_name := "—"
			if wd != null and wd.symbols != null:
				for sw in wd.symbols:
					if sw == null or sw.symbol == null:
						continue
					if sw.symbol.kind == "special" or sw.symbol.kind == "status":
						mech_name = sw.symbol.name
						break
			# 元素小图标（整备副屏武器行）：一眼看出元素，文字行仍然保留元素名
			var eico := WeaponIcons.element_icon(String(wd.element) if wd != null else "none")
			if eico != null:
				btn.icon = eico
				btn.expand_icon = false
			# G0-02：攻击显示锋铸后的真实基础攻击；G6-05：再显示铸式后的命中/攻击。
			var forge_n: int = _ctrl.mastery.forge_bonus(path) if _ctrl.mastery != null else 0
			var atk_txt := "攻%d" % _ctrl.weapon_power(path)
			if forge_n > 0:
				atk_txt += "（+%d）" % forge_n
			# 2026-11-08 排版验收：整行「攻 · 元素 · 命中 · 暴 · 机制」实测 182px，超卡内宽 178px；
			# 自动换行只会把「· —」挤到下一行。改为按语义拆两行：line2 攻/元素/命中，line3 暴击/机制。
			line2 = "%s · %s · 命中%d%%" % [atk_txt, elem_txt, hit_pct]
			line3 = "暴%d%% · %s" % [crit_total, mech_name]
	elif kind == "skill":
		title = data.buff_name if (data != null) else path.get_file().get_basename()
		if data != null:
			line1 = "%s %s" % [data.icon, _short_desc(String(data.description))]
			# 技能强度轴（2026-08-09 更新）：攻击力 · 命中率 · 非三连暴击率 · 符号回合
			var sym_txt := "无符号"
			if data.symbol != null:
				sym_txt = "×%d·%dT" % [int(data.weight), data.symbol.buff_turns]
			var s_crit: int = int((_ctrl.BALANCE.crit_chance + data.crit_chance) * 100)
			var s_hit: int = int(data.hit_rate * 100)
			line2 = "攻%d · 命中%d%% · 暴%d%% · %s" % [int(data.base_power), s_hit, s_crit, sym_txt]
	else:
		title = data.item_name if (data != null) else path.get_file().get_basename()
		if data != null:
			line1 = "%s %s" % [data.icon, _short_desc(String(data.description))]
			line2 = "持有 %d" % data.charges if (kind == "active" and data.get("charges") != null) else "被动"

	title = source_tag(kind) + title
	# Button 多行：title(line1)line2(line3)。靠 \n 排版；首行用 BBCode 强调名字(可选)
	var body := title
	if line1 != "":
		body += "\n" + line1
	if line2 != "":
		body += "\n" + line2
	if line3 != "":
		body += "\n" + line3
	btn.text = body
	# M3-03：通用图标绑定（武器 / 技能 / 消耗品 / 护符）；无图保持 emoji 文本。
	if data != null and data.get("icon_tex") != null:
		btn.icon = data.icon_tex
	if data != null:
		btn.tooltip_text = ItemTooltip.for_resource(data, kind)
	var card := {"path": path, "btn": btn, "selected": false, "kind": kind}
	btn.connect("pressed", _hud.card_toggled.emit.bind(card))
	return card


# 整备卡描述摘要（2026-11-08 排版验收）：
# 物品描述里常带「——P2 高攻窗口容错…」「（草案克制解）」这类设计备注，且长度可达 591px，
# 176px 卡宽放不下。这里只保留玩家要看的「效果句」，备注与超额文字去掉；
# 完整条目由 ItemTooltip 悬停信息窗给出。不改任何资源文本。
func _short_desc(s: String, max_chars: int = 34) -> String:
	var dash: int = s.find("——")   # 设计备注统一以破折号引出
	if dash >= 6:
		s = s.left(dash)
	if s.length() <= max_chars:
		return s
	var cut: String = s.left(max_chars)
	# 优先在完整句号处收尾，避免「护盾 +」这种半截断句
	for sep in ["。", "；", "！", "？"]:
		var p: int = cut.rfind(sep)
		if p >= 6:
			return cut.left(p + 1)
	return cut + "…"


# 房奖励卡（三选一 / BOSS 前）
func reward_card(rw: RewardData, index: int = -1, slot_label: String = "") -> Button:
	var card: ItemCard = ITEM_CARD.instantiate()
	# Step 4：有 24px 主图时卡片需要更高，否则「图 24 + 标题 + 描述」会顶出卡片（原 60 高）
	card.custom_minimum_size = Vector2(84, 96)
	# M1-01：候选在展示前已确定具体物品（payload），卡片直接显示真实结果
	var payload: Dictionary = _ctrl._reward_system.payload_at(index) if index >= 0 else {}
	# Step 4：卡片主图优先用「候选物品自身的美术」（payload.path → art/icon_tex），
	# 其次用奖励类型美术（rw.art），都没有则保持 emoji 文本。
	var art: Texture2D = rw.art
	if not payload.is_empty():
		var p := String(payload.get("path", ""))
		if p != "":
			var res: Resource = load(p)
			if res != null:
				if res.get("art") != null:
					art = res.get("art")
				elif art == null and res.get("icon_tex") != null:
					art = res.get("icon_tex")
	# 有主图时不再重复显示 emoji 图标前缀（否则图 + emoji 并列重复）
	# 武器图标（assets/icons/weapons）：有图就顶掉 emoji，并挂元素色粒子
	var wp := String(payload.get("path", "")) if not payload.is_empty() else ""
	var wico: Texture2D = WeaponIcons.icon_for_path(wp) if wp != "" else null
	var elem := ""
	if wico != null and art == null:
		art = wico
		var wr: Resource = load(wp)
		if wr != null and wr.get("element") != null:
			elem = String(wr.get("element"))
	var prefix: String = "" if art != null else rw.icon + " "
	var title_text: String = String(payload.get("title", rw.label)) if not payload.is_empty() else rw.label
	var desc_text: String = String(payload.get("desc", rw.desc)) if not payload.is_empty() else rw.desc
	if slot_label != "":
		title_text = "[%s] %s" % [slot_label, title_text]
	card.configure(prefix + title_text, desc_text)
	if wico != null:
		card.set_art(wico, Vector2(36, 36), WeaponIcons.color_for(elem))
	else:
		card.set_art(art, Vector2(24, 24))
	# 槽位标签 + 具体物品名可能超出 84px 卡宽：标题允许换行，避免撑破三列布局。
	(card.get_node("Center/VBox/TitleLabel") as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# G8-05：高度按真实内容算（图 24 + 换行标题 + 描述），固定 96 只在短文案时够用
	card.fit_min_height(96.0)
	card.tooltip_text = desc_text   # 卡片只放短文案，完整前后变化走 tooltip
	card.pressed.connect(func() -> void: _hud.reward_chosen.emit(rw.id, index))
	return card


# M1：战后成长屏的成长位卡（技艺 / 铭印 / 下一房对策）。
func post_growth_card(cand: Dictionary) -> Button:
	var card: ItemCard = ITEM_CARD.instantiate()
	card.custom_minimum_size = Vector2(84, 96)
	var icon := String(cand.get("icon", ""))
	var prefix := (icon + " ") if icon != "" else ""
	# G8-05：成长槽描述 50+ 字（含提示语）在 76px 内容宽里会折 8–9 行顶出卡片；
	# 卡面只留效果句，完整说明在 tooltip（与整备物品卡同一显示层截断策略）。
	card.configure("%s[%s] %s" % [prefix, cand.get("slot_label", "成长"), cand.get("title", "")],
		_short_desc(String(cand.get("desc", ""))))
	(card.get_node("Center/VBox/TitleLabel") as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# G8-05：成长槽描述常带提示语、换行 5–6 行；固定 96 高会把文字画到卡片外
	card.fit_min_height(96.0)
	card.tooltip_text = String(cand.get("tooltip", cand.get("desc", "")))
	card.pressed.connect(_hud.post_battle_growth_chosen.emit.bind(cand))
	return card


# BOSS 战利品卡（候选为 dict，点击调 _on_boss_reward_chosen；完整说明进 tooltip，卡片只放短文案）
func boss_reward_card(cand: Dictionary) -> Button:
	var card: ItemCard = ITEM_CARD.instantiate()
	card.custom_minimum_size = Vector2(84, 60)
	card.fit_min_height(60.0)
	card.configure("%s %s" % [cand.get("icon", ""), cand.get("label", "")], cand.get("desc", ""))
	card.set_art(cand.get("art", null))
	card.tooltip_text = String(cand.get("tip", cand.get("desc", "")))
	card.pressed.connect(_hud.boss_reward_chosen.emit.bind(cand))
	return card


# 每局结束元进度三选一（仅 3 张、覆盖层空间充足，放大提升可读性）
func meta_card(opt: Dictionary) -> Button:
	var card: ItemCard = ITEM_CARD.instantiate()
	card.custom_minimum_size = Vector2(130, 60)
	card.fit_min_height(60.0)
	card.configure("%s %s" % [opt.get("icon", ""), opt.get("label", "")], opt.get("desc", ""), TypeScale.META, 110.0)
	card.pressed.connect(_hud.meta_choice_chosen.emit.bind(opt))
	return card


# G6-02：生涯定向解锁卡（未拥有装备三选一；点击立即写入图鉴/拥有池）。
func unlock_card(cand: Dictionary) -> Button:
	var card: ItemCard = ITEM_CARD.instantiate()
	card.custom_minimum_size = Vector2(130, 84)
	card.fit_min_height(84.0)
	card.configure("%s %s" % [cand.get("icon", ""), cand.get("name", "")],
		String(cand.get("desc", "")), TypeScale.META, 110.0)
	card.set_art(cand.get("art", null), Vector2(24, 24))
	card.tooltip_text = String(cand.get("tip", cand.get("desc", "")))
	card.pressed.connect(func() -> void:
		_hud.career_unlock_chosen.emit(String(cand.get("path", ""))))
	return card


# 商店货架卡（含槽位/替换/价格状态文案）
func shop_card(offer: Dictionary) -> Button:
	var card: ItemCard = ITEM_CARD.instantiate()
	card.custom_minimum_size = Vector2(0, 46)
	card.fit_min_height(46.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var kind_name = {"weapon": "武器", "passive": "护符", "active": "物品", "skill": "技能"}.get(offer["kind"], "物品")
	card.configure("%s%s · %s" % [source_tag(offer["kind"]), kind_name, offer["name"]], "", TypeScale.TITLE, 0.0, 2)
	# G8-05：三列各约 131px 内容宽，长物品名（如「【常驻】护符 · 破甲符」实测 137px）
	# 原本直接画到卡片边框外；标题允许换行，卡片高度由内容自适应。
	(card.get_node("Center/VBox/TitleLabel") as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.set_tooltip(load(offer["path"]), offer["kind"])   # 物品悬停信息窗（ItemTooltip 生成器）
	if offer["kind"] == "weapon":
		var woff: Resource = load(offer["path"])
		var welem := String(woff.get("element")) if woff != null and woff.get("element") != null else ""
		WeaponIcons.apply(card, String(offer["path"]), welem, Vector2(32, 32))
	var price = offer.get("price", _ctrl._shop_price(offer["kind"], -1, offer["path"]))   # 2026-08-10 fix：显示货架锁定报价（不再每次重算 jitter 随机）
	var is_active = (offer["kind"] == "active")
	var cap = _ctrl.state.CONSUMABLE_CAP if is_active else _ctrl._loadout_system.cat_max(offer["kind"])          # 消耗品按腰带总容量 4；其余按整备上限
	var cur = _ctrl.state.consumable_slots.size() if is_active else _ctrl._loadout_system.sel_arr(offer["kind"]).size()   # 消耗品按腰带实占数
	var can_grow_slot = (not is_active) and _ctrl._loadout_system.can_grow_slot(offer["kind"])   # 消耗品不「开槽」、仅追加腰带格
	var slot_full = (cur >= cap) and not can_grow_slot
	# 2026-08-07 武器替换：武器槽满（上限 2）时可点——触发替换弹层（换装），不禁用
	var weapon_replace: bool = (offer["kind"] == "weapon" and cur >= cap and not can_grow_slot)
	if weapon_replace:
		slot_full = false
	var can_buy = (not offer["sold"]) and _ctrl.state.gold >= price and not slot_full
	var status: String
	if offer["sold"]:
		status = "已购入"
	elif _ctrl.state.gold < price:
		status = "金币不足"
	elif weapon_replace:
		status = "替换 %d 金" % price   # 槽满 2：点击弹替换选择（旧武器回收藏库）
	elif slot_full:
		var cap_txt = _ctrl.state.CONSUMABLE_CAP if is_active else _ctrl._loadout_system.cap_text(offer["kind"])
		status = "槽位已满 %d/%s" % [cur, cap_txt]
	elif cur >= cap:
		status = "开槽 %d 金" % price   # 本次购买会把该类槽 +1
	else:
		status = "%d 金" % price
	var col: Color = Palette.ACCENT_GOLD
	if offer["sold"]:
		col = Palette.MUTED_DIM
	elif not can_buy:
		col = Palette.ENEMY
	card.set_status(status, col)
	card.disabled = not can_buy
	card.pressed.connect(_hud.shop_card_pressed.emit.bind(offer))
	return card


# 商店「卖出」区：四列列出已持有物品，点击回收约50%金币并释放槽位
# 卖出卡：四列等宽，卡片高度按「标题 + 最多两行状态」留够，
# 否则「最后一把/不可卖」这类两行文案会画出卡片下沿压到下一张卡。
func sell_card(title_text: String, sub_text: String, disabled: bool, cb: Callable, res: Resource = null) -> Button:
	var card: ItemCard = ITEM_CARD.instantiate()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 40)
	card.fit_min_height(40.0)
	card.configure(title_text, sub_text, TypeScale.TINY)
	card.set_desc_color(Palette.ACCENT_GOLD if not disabled else Palette.MUTED_DIM)
	if res != null:
		card.set_tooltip(res)   # 物品悬停信息窗（ItemTooltip 生成器）
	card.disabled = disabled
	if not cb.is_null():
		card.pressed.connect(cb)
	return card

