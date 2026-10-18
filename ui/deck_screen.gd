class_name DeckScreen
extends Control
## 我的卡组：左侧卡组列表，中间收藏卡池，右侧卡组内容（30 张 + 费用曲线）。

signal navigate(target: String, data: Variant)

const LIST_X := 40.0
const POOL_X := 364.0
const DECK_X := 1084.0
const TOP_Y := 110.0
const BODY_H := 700.0

var _deck: Dictionary = {}
var _filter := "ALL"
var _search := ""

var _list_box: VBoxContainer
var _pool_grid: GridContainer
var _deck_vbox: VBoxContainer
var _name_edit: LineEdit
var _count_label: Label
var _legal_label: Label
var _curve: Control
var _filter_buttons: Dictionary = {}
var _pool_chips: Dictionary = {}
var _search_edit: LineEdit
var _pool_hint: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	DeckStore.ensure_loaded()
	CustomCards.ensure_loaded()
	var decks := DeckStore.all()
	if not decks.is_empty():
		_deck = decks[0]
	_build()
	_rebuild_all()


# ------------------------------------------------------------------ 布局
func _build() -> void:
	var back := Button.new()
	back.text = "← 返回"
	back.position = Vector2(40, 26)
	back.size = Vector2(112, 44)
	back.add_theme_font_size_override("font_size", 16)
	back.pressed.connect(func(): navigate.emit("menu", null))
	add_child(back)

	var title := UITheme.outline_label("我的卡组", 38, UITheme.GOLD, 8)
	title.position = Vector2(176, 16)
	title.size = Vector2(360, 56)
	add_child(title)

	var rule := UITheme.label("每套 30 张   ·   同名最多 2 张   ·   传说 1 张   ·   仅限本职业与中立",
		15, UITheme.MUTED, false)
	rule.position = Vector2(420, 38)
	rule.size = Vector2(700, 26)
	add_child(rule)

	# ---------------- 左侧：卡组列表
	_panel(Vector2(LIST_X, TOP_Y), Vector2(300, BODY_H))
	var list_title := UITheme.label("卡组列表", 15, UITheme.GOLD, true)
	list_title.position = Vector2(LIST_X + 14, TOP_Y + 10)
	list_title.size = Vector2(200, 22)
	add_child(list_title)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(LIST_X + 10, TOP_Y + 38)
	scroll.size = Vector2(280, BODY_H - 100)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.custom_minimum_size = Vector2(266, 0)
	_list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_list_box)

	_action_button("新建", Vector2(LIST_X + 10, TOP_Y + BODY_H - 52), Vector2(86, 42), _on_new)
	_action_button("复制", Vector2(LIST_X + 104, TOP_Y + BODY_H - 52), Vector2(86, 42), _on_duplicate)
	_action_button("删除", Vector2(LIST_X + 198, TOP_Y + BODY_H - 52), Vector2(90, 42), _on_delete)

	# ---------------- 中间：卡池
	_panel(Vector2(POOL_X, TOP_Y), Vector2(700, BODY_H))
	_build_filters()
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "搜索卡牌名称…"
	_search_edit.position = Vector2(POOL_X + 14, TOP_Y + 50)
	_search_edit.size = Vector2(220, 34)
	_search_edit.add_theme_font_size_override("font_size", 14)
	_search_edit.text_changed.connect(func(t):
		_search = t.strip_edges()
		_rebuild_pool()
	)
	add_child(_search_edit)

	_pool_hint = UITheme.label("点击卡牌加入卡组", 13, Color(UITheme.MUTED, 0.9), false)
	_pool_hint.position = Vector2(POOL_X + 250, TOP_Y + 56)
	_pool_hint.size = Vector2(300, 22)
	add_child(_pool_hint)

	var pool_scroll := ScrollContainer.new()
	pool_scroll.position = Vector2(POOL_X + 14, TOP_Y + 94)
	pool_scroll.size = Vector2(672, BODY_H - 108)
	pool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(pool_scroll)

	_pool_grid = GridContainer.new()
	_pool_grid.columns = 5
	_pool_grid.add_theme_constant_override("h_separation", 8)
	_pool_grid.add_theme_constant_override("v_separation", 10)
	pool_scroll.add_child(_pool_grid)

	# ---------------- 右侧：卡组内容
	_panel(Vector2(DECK_X, TOP_Y), Vector2(476, BODY_H))
	_name_edit = LineEdit.new()
	_name_edit.position = Vector2(DECK_X + 14, TOP_Y + 10)
	_name_edit.size = Vector2(300, 34)
	_name_edit.add_theme_font_size_override("font_size", 18)
	_name_edit.text_submitted.connect(func(_t): _commit_name())
	_name_edit.focus_exited.connect(_commit_name)
	add_child(_name_edit)

	_count_label = UITheme.outline_label("", 20, UITheme.GOLD, 5)
	_count_label.position = Vector2(DECK_X + 330, TOP_Y + 12)
	_count_label.size = Vector2(130, 30)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_count_label)

	_curve = Control.new()
	_curve.position = Vector2(DECK_X + 14, TOP_Y + 50)
	_curve.size = Vector2(448, 46)
	_curve.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curve.draw.connect(_draw_curve)
	add_child(_curve)

	_legal_label = UITheme.label("", 13, UITheme.MUTED, false)
	_legal_label.position = Vector2(DECK_X + 14, TOP_Y + 98)
	_legal_label.size = Vector2(448, 22)
	add_child(_legal_label)

	var deck_scroll := ScrollContainer.new()
	deck_scroll.position = Vector2(DECK_X + 10, TOP_Y + 126)
	deck_scroll.size = Vector2(456, BODY_H - 140)
	deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(deck_scroll)

	_deck_vbox = VBoxContainer.new()
	_deck_vbox.custom_minimum_size = Vector2(440, 0)
	_deck_vbox.add_theme_constant_override("separation", 2)
	deck_scroll.add_child(_deck_vbox)


func _panel(pos: Vector2, size: Vector2) -> void:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color(0.06, 0.075, 0.10, 0.86), Color(UITheme.GOLD_DIM, 0.55), 1, 14, 10))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)


func _action_button(text: String, pos: Vector2, size: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(func():
		if Sfx != null:
			Sfx.ui_click()
		cb.call()
	)
	add_child(b)
	return b


func _build_filters() -> void:
	var filters := [["ALL", "全部"], ["NEUTRAL", "中立"], ["MAGE", "法师"],
		["WARRIOR", "战士"], ["PALADIN", "圣骑士"], ["CUSTOM", "自定义"]]
	var x := POOL_X + 14.0
	for f in filters:
		var b := Button.new()
		b.text = f[1]
		b.position = Vector2(x, TOP_Y + 8)
		b.size = Vector2(100, 34)
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func():
			_filter = f[0]
			_rebuild_pool()
		)
		add_child(b)
		_filter_buttons[f[0]] = b
		x += 106


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


# ------------------------------------------------------------------ 卡组列表
func _rebuild_list() -> void:
	_clear(_list_box)
	for d in DeckStore.all():
		_list_box.add_child(_make_list_item(d))


func _make_list_item(d: Dictionary) -> Control:
	var active: bool = d["id"] == str(_deck.get("id", ""))
	var row := Button.new()
	row.custom_minimum_size = Vector2(266, 62)
	row.add_theme_stylebox_override("normal", _row_style(active, false))
	row.add_theme_stylebox_override("hover", _row_style(active, true))
	row.add_theme_stylebox_override("pressed", _row_style(active, true))
	row.pressed.connect(func():
		_deck = d
		_rebuild_all()
	)

	var name_lbl := UITheme.label(str(d["name"]), 16, UITheme.TEXT if active else UITheme.MUTED, true)
	name_lbl.position = Vector2(14, 8)
	name_lbl.size = Vector2(180, 22)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	var meta := UITheme.label("%s · %d/30" % [CardDB.class_name_of(str(d["hero_class"])),
		d["cards"].size()], 12, Color(UITheme.MUTED, 0.9), false)
	meta.position = Vector2(14, 32)
	meta.size = Vector2(200, 20)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(meta)

	var dot := ColorRect.new()
	dot.color = CardDB.class_color(str(d["hero_class"]))
	dot.position = Vector2(0, 0)
	dot.size = Vector2(4, 62)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dot)
	return row


func _row_style(active: bool, hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1d2634") if active else (Color("171e29") if not hover
		else Color("1a222e"))
	sb.set_corner_radius_all(9)
	sb.border_color = UITheme.GOLD if active else Color(0, 0, 0, 0.35)
	sb.set_border_width_all(2 if active else 1)
	sb.content_margin_left = 0
	return sb


# ------------------------------------------------------------------ 卡池
func _rebuild_pool() -> void:
	_clear(_pool_grid)
	_pool_chips.clear()
	for key in _filter_buttons:
		_filter_buttons[key].button_pressed = key == _filter
	var cards := CardDB.all_cards()
	cards.sort_custom(func(a, b):
		var ca := int(a.get("cost", 0))
		var cb := int(b.get("cost", 0))
		if ca == cb:
			return str(a.get("name", "")) < str(b.get("name", ""))
		return ca < cb
	)
	var shown := 0
	for c in cards:
		var cid := str(c["id"])
		if CardDB.is_token(cid):
			continue
		var cls := str(c.get("class", "NEUTRAL"))
		if _filter == "CUSTOM":
			if not CardDB.is_custom(cid):
				continue
		elif _filter != "ALL":
			if cls != _filter and cls != "NEUTRAL":
				continue
		if _search != "" and not str(c.get("name", "")).contains(_search):
			continue
		shown += 1
		var chip := CardChip.new()
		chip.setup(c, DeckStore.copies_of(_deck, cid))
		chip.disabled = not _can_add(cid)
		chip.pressed.connect(func(chip_view: CardChip): _on_pool_pick(chip_view.card_id))
		_pool_grid.add_child(chip)
		_pool_chips[cid] = chip
	if _pool_hint != null:
		_pool_hint.text = "共 %d 张 · 点击加入卡组" % shown


## 只刷新数量与可用状态，不重建控件（避免打断点击）。
func _refresh_counts() -> void:
	for cid in _pool_chips:
		var chip: CardChip = _pool_chips[cid]
		if not is_instance_valid(chip):
			continue
		chip.set_count(DeckStore.copies_of(_deck, str(cid)))
		chip.disabled = not _can_add(str(cid))
		chip.refresh()


func _can_add(card_id: String) -> bool:
	var probe := {"hero_class": _deck.get("hero_class", "NEUTRAL"),
		"cards": _deck.get("cards", []).duplicate()}
	return bool(DeckStore.add_card(probe, card_id).get("ok", false))


func _on_pool_pick(card_id: String) -> void:
	var result := DeckStore.add_card(_deck, card_id)
	if not result.get("ok", false):
		_toast(str(result.get("reason", "无法加入")))
		if Sfx != null:
			Sfx.error()
		return
	if Sfx != null:
		Sfx.card_draw()
	DeckStore.update(_deck)
	_refresh_deck_side()

# ------------------------------------------------------------------ 卡组内容
func _rebuild_deck_rows() -> void:
	_clear(_deck_vbox)
	var groups := DeckStore.grouped(_deck)
	if groups.is_empty():
		var empty := UITheme.label("卡组还是空的，从左边的卡池里点几张牌吧", 14,
			Color(UITheme.MUTED, 0.85), false)
		empty.custom_minimum_size = Vector2(440, 40)
		_deck_vbox.add_child(empty)
		return
	var index := 0
	for g in groups:
		_deck_vbox.add_child(_make_deck_row(g, index))
		index += 1


func _make_deck_row(g: Dictionary, index: int) -> Control:
	var def: Dictionary = g["def"]
	var row := Control.new()
	row.custom_minimum_size = Vector2(428, 36)
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.03) if index % 2 == 0 else Color(0, 0, 0, 0.12)
	bg.size = Vector2(428, 36)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bg)

	var cost := UITheme.outline_label(str(int(def.get("cost", 0))), 15, Color("9fd8ff"), 4)
	cost.position = Vector2(6, 4)
	cost.size = Vector2(28, 28)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(cost)

	var name_lbl := UITheme.label(str(def.get("name", "")), 15, UITheme.TEXT, false)
	name_lbl.position = Vector2(40, 6)
	name_lbl.size = Vector2(212, 24)
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_lbl)

	var type_lbl := UITheme.label(_type_text(def), 12, Color(UITheme.MUTED, 0.8), false)
	type_lbl.position = Vector2(254, 8)
	type_lbl.size = Vector2(72, 20)
	row.add_child(type_lbl)

	var copies := int(g["count"])
	var num := UITheme.label("×%d" % copies, 15, UITheme.GOLD, true)
	num.position = Vector2(330, 6)
	num.size = Vector2(40, 24)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(num)

	var minus := _tiny_button("−", Vector2(372, 4), row)
	minus.pressed.connect(func(): _change_copies.call_deferred(str(g["card_id"]), -1))
	var plus := _tiny_button("+", Vector2(396, 4), row)
	plus.pressed.connect(func(): _change_copies.call_deferred(str(g["card_id"]), 1))
	return row


func _type_text(def: Dictionary) -> String:
	if str(def.get("type", "MINION")) == "SPELL":
		return "法术"
	var race := CardDB.race_name(str(def.get("race", "")))
	if race != "":
		return race
	return "随从"


func _tiny_button(text: String, pos: Vector2, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(20, 28)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_stylebox_override("normal",
		UITheme.panel_style(Color("1d2634"), Color(UITheme.GOLD_DIM, 0.6), 1, 6))
	b.add_theme_stylebox_override("hover",
		UITheme.panel_style(Color("2a3646"), UITheme.GOLD, 1, 6))
	b.add_theme_stylebox_override("pressed",
		UITheme.panel_style(Color("11161f"), UITheme.GOLD, 1, 6))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b


func _change_copies(card_id: String, delta: int) -> void:
	if delta > 0:
		var result := DeckStore.add_card(_deck, card_id)
		if not result.get("ok", false):
			_toast(str(result.get("reason", "")))
			return
	else:
		DeckStore.remove_card(_deck, card_id)
	DeckStore.update(_deck)
	_refresh_deck_side()


# ------------------------------------------------------------------ 刷新
func _rebuild_all() -> void:
	_rebuild_list()
	_rebuild_pool()
	_refresh_deck_side()


func _refresh_deck_side() -> void:
	if _deck.is_empty():
		return
	_name_edit.text = str(_deck["name"])
	var n: int = _deck["cards"].size()
	_count_label.text = "%d / 30" % n
	_count_label.add_theme_color_override("font_color",
		UITheme.GOLD if n == DeckStore.DECK_SIZE else Color("e08a6a"))
	var verdict := DeckStore.validate(_deck)
	if verdict.get("ok", false):
		_legal_label.text = "✓ 卡组可用"
		_legal_label.add_theme_color_override("font_color", Color("7ed49a"))
	else:
		var errs: Array = verdict.get("errors", [])
		_legal_label.text = ("· " + str(errs[0])) if not errs.is_empty() else ""
		_legal_label.add_theme_color_override("font_color", Color("e08a6a"))
	_curve.queue_redraw()
	_rebuild_deck_rows()
	_refresh_list_meta()
	_refresh_counts()


## 只更新左侧列表里的张数，不重建按钮（避免打断当前点击）。
func _refresh_list_meta() -> void:
	var decks := DeckStore.all()
	var idx := 0
	for child in _list_box.get_children():
		if idx >= decks.size():
			break
		var meta := child.get_child(1) as Label
		if meta != null:
			meta.text = "%s · %d/30" % [CardDB.class_name_of(str(decks[idx]["hero_class"])),
				decks[idx]["cards"].size()]
		idx += 1


func _draw_curve() -> void:
	if _deck.is_empty():
		return
	var buckets := DeckStore.curve(_deck)
	var peak := 1
	for b in buckets:
		peak = maxi(peak, int(b))
	var w := 30.0
	var font := UITheme.regular()
	for i in buckets.size():
		var h := 34.0 * float(buckets[i]) / float(peak)
		var x := 8.0 + i * (w + 6.0)
		_curve.draw_rect(Rect2(x, 38.0, w, 2), Color(UITheme.GOLD, 0.25))
		if h > 0.5:
			_curve.draw_rect(Rect2(x, 38.0 - h, w, h), Color(0.42, 0.66, 0.86, 0.75))
			_curve.draw_rect(Rect2(x, 38.0 - h, w, 1.5), Color(1, 1, 1, 0.25))
		_curve.draw_string(font, Vector2(x + w * 0.5 - 4, 12), str(buckets[i]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(UITheme.MUTED, 0.95))
		_curve.draw_string(font, Vector2(x + w * 0.5 - 4, 54), str(i if i < 7 else "7+"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(UITheme.MUTED, 0.6))


# ------------------------------------------------------------------ 动作
func _commit_name() -> void:
	if _deck.is_empty():
		return
	var new_name := _name_edit.text.strip_edges()
	if new_name == "" or new_name == str(_deck["name"]):
		_name_edit.text = str(_deck["name"])
		return
	DeckStore.rename(str(_deck["id"]), new_name)
	_deck = DeckStore.get_deck(str(_deck["id"]))
	_rebuild_list()


func _on_new() -> void:
	var cls := str(_deck.get("hero_class", "MAGE")) if not _deck.is_empty() else "MAGE"
	var count := DeckStore.decks_for_class(cls).size() + 1
	var deck := DeckStore.create("%s 卡组 %d" % [CardDB.class_name_of(cls), count], cls)
	_deck = deck
	_rebuild_all()
	_toast("已新建卡组，从卡池里选 30 张牌")


func _on_duplicate() -> void:
	if _deck.is_empty():
		return
	_deck = DeckStore.duplicate_deck(str(_deck["id"]))
	_rebuild_all()


func _on_delete() -> void:
	if _deck.is_empty():
		return
	if DeckStore.count() <= 1:
		_toast("至少要保留一套卡组")
		return
	var removed_id := str(_deck["id"])
	DeckStore.erase(removed_id)
	var decks := DeckStore.all()
	_deck = decks[0] if not decks.is_empty() else {}
	_rebuild_all()
	_toast("卡组已删除")


# ------------------------------------------------------------------ 提示
func _toast(text: String) -> void:
	if text == "":
		return
	var lbl := UITheme.outline_label(text, 17, Color("ffe3b0"), 6)
	lbl.position = Vector2(0, 830)
	lbl.size = Vector2(1600, 30)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.modulate = Color(1, 1, 1, 0)
	add_child(lbl)
	var tw := create_tween()
	tw.tween_property(lbl, "modulate:a", 1.0, 0.12)
	tw.tween_interval(1.4)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.4)
	tw.tween_callback(lbl.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			navigate.emit("menu", null)
