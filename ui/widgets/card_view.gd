class_name CardView
extends Control
## 手牌 / 图鉴 / 换牌用的完整卡面。
## 画框、宝石、名牌全部自绘，贴近实体卡的层次：外框 → 美术 → 名牌/描述框 → 数值宝石。

signal drag_started(view: CardView)
signal drag_moved(view: CardView)
signal drag_ended(view: CardView, drop_position: Vector2)
signal hover_changed(view: CardView, hovered: bool)

const CARD_SIZE := Vector2(190, 278)
const CORNER := 13.0
const MANA_CENTER := Vector2(23, 21)
const MANA_R := 16.5
const GEM_R := 18.0
const LEGEND_GLOW := Color(1.0, 0.86, 0.42)

var card: CardInstance
var card_def: Dictionary = {}
var interactive := false
var dragging := false
var playable := true
var _hovered := false
var _drag_offset := Vector2.ZERO
var _pressed := false
var _press_pos := Vector2.ZERO
var _glow := 0.0

var _is_minion := true
var _art_rect := Rect2(9, 30, 172, 106)
var _name_rect := Rect2(8, 138, 174, 27)
var _text_rect := Rect2(14, 170, 162, 68)
var _atk_center := Vector2(23, 251)
var _hp_center := Vector2(167, 251)

var _art: TextureRect
var _deco: Control
var _name_label: Label
var _text_label: RichTextLabel
var _mana_label: Label
var _atk_label: Label
var _hp_label: Label
var _dim: ColorRect
var _race_label: Label
var _fit_pending := false


func setup(p_card: CardInstance, p_interactive := false) -> void:
	card = p_card
	card_def = CardDB.card(card.card_id)
	_prepare(p_interactive)


## 直接用一份卡牌定义渲染（自定义卡牌编辑器预览用，不经过 CardDB）。
func setup_def(def: Dictionary, p_interactive := false) -> void:
	card_def = def
	var inst := CardInstance.new()
	inst.instance_id = -1
	inst.card_id = str(def.get("id", ""))
	inst.attack = int(def.get("attack", 0))
	inst.health = int(def.get("health", 1))
	inst.max_health = inst.health
	inst.cost_override = int(def.get("cost", 0))
	for k in def.get("keywords", []):
		inst.keywords[str(k)] = true
	card = inst
	_prepare(p_interactive)


## 就地更新卡面（不改类型时不必重建节点）。
func apply_def(def: Dictionary) -> void:
	card_def = def
	if card == null:
		return
	card.attack = int(def.get("attack", 0))
	card.health = int(def.get("health", 1))
	card.max_health = card.health
	card.cost_override = int(def.get("cost", 0))
	card.keywords.clear()
	for k in def.get("keywords", []):
		card.keywords[str(k)] = true
	var tex := CardDB.texture(str(def.get("art", "")))
	if _art != null and _art.texture != tex:
		_art.texture = tex
	refresh()


func _prepare(p_interactive: bool) -> void:
	interactive = p_interactive
	_is_minion = str(card_def.get("type", "MINION")) == "MINION"
	if not _is_minion:
		_art_rect = Rect2(9, 30, 172, 146)
		_name_rect = Rect2(8, 146, 174, 27)
		_text_rect = Rect2(14, 178, 162, 74)
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	pivot_offset = Vector2(CARD_SIZE.x * 0.5, CARD_SIZE.y)
	clip_contents = false
	_build()
	refresh()


func _build() -> void:
	# 美术（圆角遮罩）
	var art_pos := _art_rect.position
	var art_size := _art_rect.size
	_art = UITheme.rounded_art(CardDB.texture(str(card_def.get("art", ""))), art_size, 9.0)
	_art.position = art_pos
	add_child(_art)

	# 名牌、描述框、宝石画在美术之上
	_deco = Control.new()
	_deco.size = CARD_SIZE
	_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deco.draw.connect(_draw_deco)
	add_child(_deco)

	_name_label = UITheme.outline_label("", 15, UITheme.TEXT, 7)
	_name_label.position = Vector2(_name_rect.position.x + 2, _name_rect.position.y + 1)
	_name_label.size = Vector2(_name_rect.size.x - 4, _name_rect.size.y - 2)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_name_label)

	_text_label = RichTextLabel.new()
	_text_label.position = _text_rect.position
	_text_label.size = _text_rect.size
	_text_label.bbcode_enabled = true
	_text_label.fit_content = false
	_text_label.scroll_active = false
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.add_theme_font_override("normal_font", UITheme.regular())
	_text_label.add_theme_font_size_override("normal_font_size", 12)
	_text_label.add_theme_constant_override("line_separation", 0)
	_text_label.add_theme_constant_override("outline_size", 0)
	_text_label.add_theme_color_override("default_color", UITheme.TEXT)
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text_label)

	_mana_label = UITheme.outline_label("0", 21, Color.WHITE, 6)
	_mana_label.position = MANA_CENTER - Vector2(MANA_R, MANA_R) + Vector2(0, -1)
	_mana_label.size = Vector2(MANA_R * 2, MANA_R * 2 + 2)
	_mana_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mana_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_mana_label)

	_atk_label = UITheme.outline_label("", 20, Color.WHITE, 6)
	_atk_label.position = _atk_center - Vector2(GEM_R, GEM_R)
	_atk_label.size = Vector2(GEM_R * 2, GEM_R * 2)
	_atk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_atk_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_atk_label)

	_hp_label = UITheme.outline_label("", 20, Color.WHITE, 6)
	_hp_label.position = _hp_center - Vector2(GEM_R, GEM_R)
	_hp_label.size = Vector2(GEM_R * 2, GEM_R * 2)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_hp_label)

	# 种族：美术右下角的小标签（只做展示，不参与规则）
	_race_label = UITheme.outline_label("", 10, Color(0.96, 0.92, 0.82), 4)
	_race_label.position = Vector2(_art_rect.end.x - 62, _art_rect.end.y - 21)
	_race_label.size = Vector2(58, 17)
	_race_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_race_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_race_label)

	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.03, 0.05, 0.46)
	_dim.position = Vector2.ZERO
	_dim.size = CARD_SIZE
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.visible = false
	add_child(_dim)

	if interactive:
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)


func refresh() -> void:
	if card == null:
		return
	_name_label.text = str(card_def.get("name", ""))
	_text_label.text = CardDB.format_text(card_def)
	_mana_label.text = str(card.cost())
	var race := CardDB.race_name(str(card_def.get("race", "")))
	_race_label.text = race
	_race_label.visible = race != "" and _is_minion
	if _is_minion:
		_atk_label.text = str(card.current_attack())
		_atk_label.visible = true
		_hp_label.text = str(card.health)
		_hp_label.visible = true
		_atk_label.add_theme_color_override("font_color",
			Color("a8f0a8") if card.current_attack() > card.attack else Color.WHITE)
		_hp_label.add_theme_color_override("font_color",
			Color("ff9a8a") if card.is_damaged() else Color.WHITE)
	else:
		_atk_label.visible = false
		_hp_label.visible = false
	_dim.visible = not playable
	queue_redraw()
	_deco.queue_redraw()
	_fit_text()


## 描述过长时自动缩小字号，避免溢出卡面。
## 用字体度量直接算换行高度，不依赖控件是否已完成布局。
func _fit_text() -> void:
	_fit_pending = false
	if card == null:
		return
	var plain: String = str(card_def.get("text", ""))
	var font := UITheme.regular()
	var chosen := 9
	for s in [12, 11, 10, 9]:
		var measured: Vector2 = font.get_multiline_string_size(plain,
			HORIZONTAL_ALIGNMENT_LEFT, _text_rect.size.x - 2.0, float(s))
		if measured.y <= _text_rect.size.y - 2.0:
			chosen = s
			break
	_text_label.add_theme_font_size_override("normal_font_size", chosen)


func set_cost(value: int) -> void:
	_mana_label.text = str(value)
	if card != null and value < card.cost():
		_mana_label.add_theme_color_override("font_color", Color("7ee089"))
	elif card != null and value > card.cost():
		_mana_label.add_theme_color_override("font_color", Color("ff8a7a"))
	else:
		_mana_label.add_theme_color_override("font_color", Color.WHITE)


func set_playable(value: bool) -> void:
	if playable == value:
		return
	playable = value
	if _dim != null:
		_dim.visible = not value
	queue_redraw()
	_deco.queue_redraw()


func set_glow(value: float) -> void:
	_glow = value
	queue_redraw()


func _draw() -> void:
	var rarity: String = card_def.get("rarity", "COMMON")
	var class_color := CardDB.class_color(card_def.get("class", "NEUTRAL"))
	var border := CardDB.rarity_color(rarity)
	if rarity == "LEGENDARY":
		border = LEGEND_GLOW

	# 投影
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.55)
	shadow.set_corner_radius_all(int(CORNER) + 2)
	shadow.shadow_color = Color(0, 0, 0, 0.5)
	shadow.shadow_size = 12
	shadow.shadow_offset = Vector2(0, 6)
	draw_style_box(shadow, Rect2(Vector2(0, 3), CARD_SIZE - Vector2(0, 3)))

	# 外框（职业色）
	var frame := StyleBoxFlat.new()
	frame.bg_color = class_color.darkened(0.74)
	frame.set_corner_radius_all(int(CORNER))
	frame.border_color = border.darkened(0.15)
	frame.set_border_width_all(2)
	draw_style_box(frame, Rect2(Vector2.ZERO, CARD_SIZE))

	# 外框内侧金色倒角
	var bevel := StyleBoxFlat.new()
	bevel.bg_color = Color(0, 0, 0, 0)
	bevel.border_color = Color(UITheme.GOLD, 0.42)
	bevel.set_border_width_all(1)
	bevel.set_corner_radius_all(int(CORNER) - 3)
	draw_style_box(bevel, Rect2(Vector2(4, 4), CARD_SIZE - Vector2(8, 8)))

	# 顶部高光、底部暗部，让卡面有立体感
	draw_rect(Rect2(5, 5, CARD_SIZE.x - 10, 2), Color(1, 1, 1, 0.05))
	draw_rect(Rect2(5, CARD_SIZE.y - 8, CARD_SIZE.x - 10, 3), Color(0, 0, 0, 0.18))

	# 美术底框
	var art_bg := StyleBoxFlat.new()
	art_bg.bg_color = Color("0a0d12")
	art_bg.set_corner_radius_all(10)
	art_bg.border_color = Color(0, 0, 0, 0.55)
	art_bg.set_border_width_all(2)
	draw_style_box(art_bg, Rect2(_art_rect.position - Vector2(3, 3), _art_rect.size + Vector2(6, 6)))

	# 稀有度标记
	var rc := CardDB.rarity_color(rarity)
	var ry: float = 245.0 if _is_minion else 262.0
	var rp := Vector2(CARD_SIZE.x * 0.5, ry)
	if rarity == "LEGENDARY":
		var pts := PackedVector2Array([
			rp + Vector2(0, -7), rp + Vector2(6, 0), rp + Vector2(0, 7), rp + Vector2(-6, 0),
		])
		draw_colored_polygon(pts, rc)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 0.93, 0.7, 0.9), 1.0, true)
	elif rarity == "EPIC" or rarity == "RARE":
		draw_circle(rp, 4.5, rc)
		draw_circle(rp, 2.2, rc.lightened(0.4))

	# 传说：四角金色描纹 + 外发光
	if rarity == "LEGENDARY":
		var g := StyleBoxFlat.new()
		g.bg_color = Color(0, 0, 0, 0)
		g.border_color = Color(LEGEND_GLOW, 0.55)
		g.set_border_width_all(2)
		g.set_corner_radius_all(int(CORNER) + 2)
		draw_style_box(g, Rect2(Vector2(-2, -2), CARD_SIZE + Vector2(4, 4)))
		for corner in [Vector2(16, 16), Vector2(CARD_SIZE.x - 16, 16),
				Vector2(16, CARD_SIZE.y - 16), Vector2(CARD_SIZE.x - 16, CARD_SIZE.y - 16)]:
			draw_arc(corner, 7.0, 0.0, TAU, 18, Color(1, 0.9, 0.6, 0.5), 1.2, true)

	# 可打出：绿色呼吸描边
	if interactive and playable and _dim.visible == false:
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(0, 0, 0, 0)
		glow.border_color = Color(0.45, 0.95, 0.6, 0.32 + 0.16 * sin(Time.get_ticks_msec() / 420.0))
		glow.set_border_width_all(2)
		glow.set_corner_radius_all(int(CORNER) + 1)
		draw_style_box(glow, Rect2(Vector2(-2, -2), CARD_SIZE + Vector2(4, 4)))

	if _glow > 0.01:
		var sel := StyleBoxFlat.new()
		sel.bg_color = Color(0, 0, 0, 0)
		sel.border_color = Color(UITheme.GOLD, 0.4 + 0.45 * _glow)
		sel.set_border_width_all(3)
		sel.set_corner_radius_all(int(CORNER) + 3)
		draw_style_box(sel, Rect2(Vector2(-3, -3), CARD_SIZE + Vector2(6, 6)))


func _draw_deco() -> void:
	var class_color := CardDB.class_color(card_def.get("class", "NEUTRAL"))
	var rarity: String = card_def.get("rarity", "COMMON")

	# 名牌：压在美术下沿的深色缎带
	var name_bg := StyleBoxFlat.new()
	name_bg.bg_color = Color(class_color.darkened(0.82), 0.95)
	name_bg.set_corner_radius_all(7)
	name_bg.border_color = Color(UITheme.GOLD, 0.52 if rarity != "LEGENDARY" else 0.85)
	name_bg.set_border_width_all(1)
	_deco.draw_style_box(name_bg, _name_rect)
	# 缎带两侧小菱形
	for dx in [_name_rect.position.x - 1.0, _name_rect.end.x + 1.0]:
		var c := Vector2(dx, _name_rect.get_center().y)
		var pts := PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0),
			c + Vector2(0, 4), c + Vector2(-4, 0)])
		_deco.draw_colored_polygon(pts, Color(UITheme.GOLD, 0.7))

	# 描述框
	var text_bg := StyleBoxFlat.new()
	text_bg.bg_color = Color(0.02, 0.03, 0.045, 0.42)
	text_bg.set_corner_radius_all(7)
	text_bg.border_color = Color(1, 1, 1, 0.07)
	text_bg.set_border_width_all(1)
	_deco.draw_style_box(text_bg, Rect2(_text_rect.position - Vector2(2, 3),
		_text_rect.size + Vector2(4, 6)))

	# 种族标签底
	if _is_minion and str(card_def.get("race", "")) != "":
		var pill := StyleBoxFlat.new()
		pill.bg_color = Color(0.06, 0.05, 0.04, 0.78)
		pill.set_corner_radius_all(8)
		pill.border_color = Color(UITheme.GOLD, 0.45)
		pill.set_border_width_all(1)
		_deco.draw_style_box(pill, Rect2(Vector2(_art_rect.end.x - 62, _art_rect.end.y - 21),
			Vector2(58, 17)))

	# 法力水晶
	_draw_mana_gem(MANA_CENTER, MANA_R)
	if _is_minion:
		_draw_attack_gem(_atk_center, GEM_R)
		_draw_health_gem(_hp_center, GEM_R)


func _draw_mana_gem(center: Vector2, r: float) -> void:
	var pts := UITheme.crystal_points(center, r)
	_deco.draw_colored_polygon(pts, Color("0c2136"))
	var inner := UITheme.crystal_points(center, r - 3.2)
	_deco.draw_colored_polygon(inner, Color("2f7fc0"))
	var lower := UITheme.crystal_points(center + Vector2(0, r * 0.28), r * 0.62)
	_deco.draw_colored_polygon(lower, Color("1d5c96"))
	# 顶部高光切面
	_deco.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -r + 2.5), center + Vector2(r * 0.6, -r * 0.28),
		center + Vector2(0, r * 0.2), center + Vector2(-r * 0.6, -r * 0.28),
	]), Color(1, 1, 1, 0.16))
	var outline := pts.duplicate()
	outline.append(pts[0])
	_deco.draw_polyline(outline, Color("9fd8ff"), 1.5, true)


func _draw_attack_gem(center: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := -PI * 0.5 + TAU * float(i) / 8.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	_deco.draw_colored_polygon(pts, Color("2a1f10"))
	var inner := PackedVector2Array()
	for i in 8:
		var a := -PI * 0.5 + TAU * float(i) / 8.0
		inner.append(center + Vector2(cos(a), sin(a)) * (r - 2.6))
	_deco.draw_colored_polygon(inner, Color("c79a4d"))
	_deco.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -r + 3), center + Vector2(r - 4, 0),
		center + Vector2(0, r * 0.35), center + Vector2(-r + 4, 0),
	]), Color(1, 1, 1, 0.14))
	var o := pts.duplicate()
	o.append(pts[0])
	_deco.draw_polyline(o, Color("f4dda6"), 1.4, true)


func _draw_health_gem(center: Vector2, r: float) -> void:
	var pts := UITheme.drop_points(center, r)
	_deco.draw_colored_polygon(pts, Color("2a0f10"))
	var shrink := UITheme.drop_points(center + Vector2(0, -0.6), r - 2.8)
	_deco.draw_colored_polygon(shrink, Color("b23a3a"))
	_deco.draw_colored_polygon(UITheme.drop_points(center + Vector2(-1.2, -2.0), r * 0.45),
		Color(1, 1, 1, 0.12))
	var o := pts.duplicate()
	o.append(pts[0])
	_deco.draw_polyline(o, Color("f0a090"), 1.4, true)


# ------------------------------------------------------------------ hover
func _on_mouse_entered() -> void:
	if dragging:
		return
	_hovered = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.14, 1.14), 0.11) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if Sfx != null:
		Sfx.ui_hover()
	hover_changed.emit(self, true)


func _on_mouse_exited() -> void:
	_hovered = false
	if not dragging:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(self, "scale", Vector2.ONE, 0.1)
	hover_changed.emit(self, false)


# ------------------------------------------------------------------ drag
func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_press_pos = event.position
			_drag_offset = get_global_mouse_position() - global_position
			accept_event()
		elif _pressed:
			_pressed = false
			if dragging:
				_end_drag()
			accept_event()
	elif event is InputEventMouseMotion and _pressed and not dragging:
		if event.position.distance_to(_press_pos) > 8.0:
			_start_drag()
	elif event is InputEventMouseMotion and dragging:
		follow_mouse()
		drag_moved.emit(self)
		accept_event()


func _start_drag() -> void:
	dragging = true
	top_level = true
	z_index = 400
	global_position = global_position
	scale = Vector2.ONE
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.94, 0.94), 0.08)
	tw.tween_property(self, "rotation", 0.0, 0.08)
	drag_started.emit(self)


func follow_mouse() -> void:
	global_position = get_global_mouse_position() - _drag_offset


func _end_drag() -> void:
	dragging = false
	drag_ended.emit(self, get_global_mouse_position())


func cancel_drag(_return_position: Vector2) -> void:
	dragging = false
	top_level = false
	z_index = 0
	scale = Vector2.ONE
	rotation = 0.0
