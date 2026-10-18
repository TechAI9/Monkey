class_name MainMenuScreen
extends Control
## 主菜单：标题、装饰卡牌、入口按钮。

signal navigate(target: String, data: Variant)

var _title: Label
var _start_btn: Button
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_decor()
	_build_content()


func _build_content() -> void:
	var emblem := TextureRect.new()
	emblem.position = Vector2(760, 92)
	emblem.size = Vector2(80, 80)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_path := "res://assets/ui/tavern-icon.png"
	if ResourceLoader.exists(icon_path):
		emblem.texture = load(icon_path)
	emblem.modulate = Color(1, 0.92, 0.75, 0.9)
	add_child(emblem)

	_title = UITheme.outline_label("小猴子卡牌", 82, UITheme.GOLD, 14)
	_title.position = Vector2(0, 168)
	_title.size = Vector2(1600, 110)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)

	var subtitle := UITheme.label("EMBER  DUEL   ·   单机卡牌对决", 18, UITheme.MUTED, false)
	subtitle.position = Vector2(0, 282)
	subtitle.size = Vector2(1600, 30)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_constant_override("outline_size", 6)
	add_child(subtitle)

	var rule := Control.new()
	rule.position = Vector2(600, 330)
	rule.size = Vector2(400, 24)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.draw.connect(func():
		rule.draw_line(Vector2(0, 12), Vector2(170, 12), Color(UITheme.GOLD_DIM, 0.7), 1.0)
		rule.draw_line(Vector2(230, 12), Vector2(400, 12), Color(UITheme.GOLD_DIM, 0.7), 1.0)
		rule.draw_circle(Vector2(200, 12), 4.0, UITheme.GOLD)
	)
	add_child(rule)

	_start_btn = _make_button("开始对战", Vector2(650, 410), Vector2(300, 62), true)
	_start_btn.pressed.connect(func(): navigate.emit("select", null))
	_make_button("我的卡组", Vector2(650, 490), Vector2(300, 52), false) \
		.pressed.connect(func(): navigate.emit("decks", null))
	_make_button("自定义卡牌", Vector2(650, 554), Vector2(300, 52), false) \
		.pressed.connect(func(): navigate.emit("custom", null))
	_make_button("卡牌图鉴", Vector2(650, 618), Vector2(300, 52), false) \
		.pressed.connect(func(): navigate.emit("collection", null))
	_make_button("退出游戏", Vector2(650, 682), Vector2(300, 52), false) \
		.pressed.connect(func(): navigate.emit("quit", null))

	var footer := UITheme.label("100 张官方卡牌   ·   三大职业   ·   人机对战   ·   卡组与自定义卡牌自由编辑",
		15, Color(UITheme.MUTED, 0.85), false)
	footer.position = Vector2(0, 812)
	footer.size = Vector2(1600, 26)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(footer)


func _make_button(text: String, pos: Vector2, size: Vector2, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.focus_mode = Control.FOCUS_ALL
	if primary:
		b.add_theme_stylebox_override("normal", _primary_style(UITheme.PANEL_LIGHT, UITheme.GOLD))
		b.add_theme_stylebox_override("hover", _primary_style(Color("2a3342"), Color("ffd98f")))
		b.add_theme_stylebox_override("pressed", _primary_style(Color("11161f"), UITheme.GOLD))
		b.add_theme_font_size_override("font_size", 23)
	add_child(b)
	return b


func _primary_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := UITheme.panel_style(bg, border, 2, 12, 8)
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


func _build_decor() -> void:
	# 先加"远处"的卡，再加大卡，保证离画面中心近的那张在上层
	var left2 := _decor_card("EX1_279", Vector2(-46, 328), -0.36, 1.0)
	left2.modulate = Color(0.8, 0.8, 0.86, 0.7)
	var right2 := _decor_card("EX1_563", Vector2(1428, 322), 0.36, 1.0)
	right2.modulate = Color(0.8, 0.8, 0.86, 0.7)
	var left := _decor_card("CS2_029", Vector2(88, 448), -0.15, 1.3)
	left.modulate = Color(1, 1, 1, 0.95)
	var right := _decor_card("NEW1_030", Vector2(1308, 448), 0.15, 1.3)
	right.modulate = Color(1, 1, 1, 0.95)


func _decor_card(card_id: String, pos: Vector2, rot: float, sc: float) -> CardView:
	var inst := CardInstance.new()
	inst.setup(1, card_id, -1)
	var v := CardView.new()
	v.setup(inst, false)
	v.position = pos
	v.rotation = rot
	v.scale = Vector2(sc, sc)
	v.modulate = Color(1, 1, 1, 0.9)
	add_child(v)
	var tw := create_tween().set_loops()
	tw.tween_property(v, "position:y", pos.y - 10, 2.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(v, "position:y", pos.y, 2.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return v


func _process(delta: float) -> void:
	_t += delta
	if _start_btn != null:
		_start_btn.modulate = Color(1, 1, 1, 0.9 + 0.1 * sin(_t * 2.2))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			navigate.emit("select", null)
			get_viewport().set_input_as_handled()
