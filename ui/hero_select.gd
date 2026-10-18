class_name HeroSelectScreen
extends Control
## 选择英雄 / 职业。三张大幅职业卡，右侧信息，底部确认。

signal navigate(target: String, data: Variant)

const PANEL_SIZE := Vector2(380, 508)
const PANEL_POS := [Vector2(170, 168), Vector2(610, 168), Vector2(1050, 168)]

var _selected := "MAGE"
var _panels: Array = []
var _start_btn: Button
var _deck_row: HBoxContainer
var _deck_hint: Label
var _selected_deck_id := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	DeckStore.ensure_loaded()
	CustomCards.ensure_loaded()
	_build()


func _build() -> void:
	var title := UITheme.outline_label("选择你的英雄", 46, UITheme.GOLD, 10)
	title.position = Vector2(0, 54)
	title.size = Vector2(1600, 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var sub := UITheme.label("每位英雄拥有专属技能，出战卡组可在下方切换", 17, UITheme.MUTED, false)
	sub.position = Vector2(0, 120)
	sub.size = Vector2(1600, 28)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)

	var heroes := CardDB.heroes()
	for i in heroes.size():
		var panel := _build_panel(heroes[i], PANEL_POS[i])
		_panels.append(panel)
		add_child(panel)

	_build_deck_bar()

	_start_btn = Button.new()
	_start_btn.text = "开始对战"
	_start_btn.position = Vector2(1180, 754)
	_start_btn.size = Vector2(300, 62)
	_start_btn.add_theme_stylebox_override("normal",
		UITheme.panel_style(UITheme.PANEL_LIGHT, UITheme.GOLD, 2, 12, 8))
	_start_btn.add_theme_stylebox_override("hover",
		UITheme.panel_style(Color("2a3342"), Color("ffd98f"), 2, 12, 8))
	_start_btn.add_theme_font_size_override("font_size", 23)
	_start_btn.pressed.connect(_on_start)
	add_child(_start_btn)

	var back := Button.new()
	back.text = "返回"
	back.position = Vector2(120, 754)
	back.size = Vector2(180, 56)
	back.pressed.connect(func(): navigate.emit("menu", null))
	add_child(back)

	var hint := UITheme.label("对手将随机选择另外两个职业之一", 15, UITheme.MUTED, false)
	hint.position = Vector2(320, 768)
	hint.size = Vector2(700, 30)
	add_child(hint)

	_refresh_selection()


## 出战卡组栏：横向列出该职业的所有卡组，可直接切换。
func _build_deck_bar() -> void:
	var frame := Panel.new()
	frame.position = Vector2(170, 690)
	frame.size = Vector2(1260, 52)
	frame.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color(0.06, 0.075, 0.10, 0.85), Color(UITheme.GOLD_DIM, 0.5), 1, 10))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	var title := UITheme.label("出战卡组", 15, UITheme.GOLD, true)
	title.position = Vector2(170, 704)
	title.size = Vector2(90, 24)
	add_child(title)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(272, 696)
	scroll.size = Vector2(1020, 42)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_deck_row = HBoxContainer.new()
	_deck_row.add_theme_constant_override("separation", 8)
	scroll.add_child(_deck_row)

	_deck_hint = UITheme.label("", 12, Color("ffb08a"), false)
	_deck_hint.position = Vector2(272, 727)
	_deck_hint.size = Vector2(720, 18)
	add_child(_deck_hint)

	var manage := Button.new()
	manage.text = "管理"
	manage.position = Vector2(1306, 696)
	manage.size = Vector2(112, 40)
	manage.add_theme_font_size_override("font_size", 15)
	manage.pressed.connect(func(): navigate.emit("decks", null))
	add_child(manage)


func _build_panel(hero: Dictionary, pos: Vector2) -> Control:
	var panel := Control.new()
	panel.position = pos
	panel.size = PANEL_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_meta("hero_id", hero["id"])
	panel.set_meta("hero", hero)
	panel.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			_selected = panel.get_meta("hero_id")
			_refresh_selection()
	)

	var portrait_clip := Control.new()
	portrait_clip.position = Vector2(20, 20)
	portrait_clip.size = Vector2(340, 296)
	portrait_clip.clip_contents = true
	portrait_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(portrait_clip)

	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.size = portrait_clip.size
	portrait.texture = CardDB.texture(str(hero["portrait"]))
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_clip.add_child(portrait)

	var name_label := UITheme.outline_label(hero["name"], 25, UITheme.TEXT, 6)
	name_label.position = Vector2(22, 322)
	name_label.size = Vector2(336, 34)
	panel.add_child(name_label)

	var title_badge := UITheme.outline_label(hero_title(hero["id"]), 16, UITheme.GOLD, 5)
	title_badge.position = Vector2(22, 360)
	title_badge.size = Vector2(200, 24)
	panel.add_child(title_badge)

	var power: Dictionary = hero["hero_power"]
	var power_label := UITheme.label("英雄技能 · %s（%d 费）" % [power["name"], power["cost"]],
		15, UITheme.TEXT, true)
	power_label.position = Vector2(22, 394)
	power_label.size = Vector2(336, 24)
	panel.add_child(power_label)

	var power_text := UITheme.label(power["text"], 14, UITheme.MUTED, false)
	power_text.position = Vector2(22, 420)
	power_text.size = Vector2(336, 46)
	power_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(power_text)

	var deck_label := UITheme.label("30 张卡组  ·  点击选择出战", 13, Color(UITheme.MUTED, 0.9), false)
	deck_label.position = Vector2(22, 470)
	deck_label.size = Vector2(336, 22)
	panel.add_child(deck_label)

	panel.draw.connect(_draw_panel.bind(panel))
	return panel


func _draw_panel(panel: Control) -> void:
	var hero: Dictionary = panel.get_meta("hero")
	var selected: bool = panel.get_meta("hero_id") == _selected
	var color := CardDB.class_color(hero["id"])
	if selected:
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(0, 0, 0, 0)
		glow.border_color = Color(1.0, 0.84, 0.45, 0.55)
		glow.set_border_width_all(5)
		glow.set_corner_radius_all(18)
		panel.draw_style_box(glow, Rect2(Vector2(-5, -5), PANEL_SIZE + Vector2(10, 10)))

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("11161f")
	sb.set_corner_radius_all(14)
	sb.border_color = UITheme.GOLD if selected else Color("4a3f2d")
	sb.set_border_width_all(3 if selected else 1)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 6)
	panel.draw_style_box(sb, Rect2(Vector2.ZERO, PANEL_SIZE))

	panel.draw_rect(Rect2(20, 296, 340, 6), color)
	panel.draw_rect(Rect2(20, 20, 340, 4), Color(color, 0.55))
	if selected:
		panel.draw_circle(Vector2(340, 40), 15, Color("0d1118"))
		panel.draw_circle(Vector2(340, 40), 13, UITheme.GOLD)
		panel.draw_line(Vector2(333, 40), Vector2(338, 46), Color("1a1a1a"), 3.0)
		panel.draw_line(Vector2(338, 46), Vector2(347, 34), Color("1a1a1a"), 3.0)


func hero_title(cls: String) -> String:
	match cls:
		"MAGE": return "法师"
		"WARRIOR": return "战士"
		"PALADIN": return "圣骑士"
	return "英雄"


func _refresh_selection() -> void:
	for p in _panels:
		p.queue_redraw()
	_rebuild_deck_row()


func _rebuild_deck_row() -> void:
	_clear(_deck_row)
	var decks := DeckStore.decks_for_class(_selected)
	if decks.is_empty():
		_selected_deck_id = ""
	else:
		var found := false
		for d in decks:
			if d["id"] == _selected_deck_id:
				found = true
				break
		if not found:
			_selected_deck_id = decks[0]["id"]
	for d in decks:
		var active: bool = d["id"] == _selected_deck_id
		var b := Button.new()
		var n: int = d["cards"].size()
		b.text = "%s  %d/30" % [str(d["name"]), n]
		b.custom_minimum_size = Vector2(228, 40)
		b.add_theme_font_size_override("font_size", 14)
		var border := UITheme.GOLD if active else Color(UITheme.GOLD_DIM, 0.55)
		b.add_theme_stylebox_override("normal",
			UITheme.panel_style(Color("1d2634") if active else Color("121821"), border,
				2 if active else 1, 8))
		b.add_theme_stylebox_override("hover",
			UITheme.panel_style(Color("26313f"), UITheme.GOLD, 2, 8))
		b.add_theme_stylebox_override("pressed",
			UITheme.panel_style(Color("11161f"), UITheme.GOLD, 2, 8))
		b.add_theme_color_override("font_color",
			UITheme.TEXT if active else Color(UITheme.MUTED, 0.95))
		b.pressed.connect(func():
			_selected_deck_id = d["id"]
			_rebuild_deck_row()
		)
		_deck_row.add_child(b)
	if decks.is_empty():
		var none := UITheme.label("这个职业还没有卡组，点右侧「管理」新建一套", 14,
			Color("e08a6a"), false)
		_deck_row.add_child(none)
	_update_start_state()


func _current_deck() -> Dictionary:
	if _selected_deck_id == "":
		return {}
	return DeckStore.get_deck(_selected_deck_id)


func _update_start_state() -> void:
	var deck := _current_deck()
	var ok := not deck.is_empty() and DeckStore.is_legal(deck)
	if _start_btn != null:
		_start_btn.disabled = not ok
	if _deck_hint == null:
		return
	if deck.is_empty():
		_deck_hint.text = "请先选择或新建一套卡组"
	elif not ok:
		var errs: Array = DeckStore.validate(deck).get("errors", [])
		_deck_hint.text = "卡组不可用：%s（可点「管理」补全）" % (str(errs[0]) if not errs.is_empty() else "")
	else:
		_deck_hint.text = ""


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _on_start() -> void:
	var deck := _current_deck()
	if deck.is_empty() or not DeckStore.is_legal(deck):
		_update_start_state()
		if Sfx != null:
			Sfx.error()
		return
	navigate.emit("battle", {
		"hero_class": _selected,
		"deck": deck["cards"].duplicate(),
	})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _selected = "MAGE"; _refresh_selection()
			KEY_2: _selected = "WARRIOR"; _refresh_selection()
			KEY_3: _selected = "PALADIN"; _refresh_selection()
			KEY_ENTER: _on_start()
			KEY_ESCAPE: navigate.emit("menu", null)
