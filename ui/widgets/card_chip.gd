class_name CardChip
extends Control
## 卡池 / 卡组里的小卡片：126×176，只保留识别所需信息（费用、立绘、名称、攻血）。

signal pressed(chip: CardChip)

const SIZE := Vector2(126, 176)
const ART := Rect2(6, 22, 114, 98)

var card_def: Dictionary = {}
var card_id := ""
var count := 0
var selected := false
var disabled := false

var _hover := 0.0
var _art: TextureRect
var _name: Label
var _cost: Label
var _atk: Label
var _hp: Label
var _badge: Label


func setup(def: Dictionary, p_count := 0) -> void:
	card_def = def
	card_id = str(def.get("id", ""))
	count = p_count
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = Vector2(SIZE.x * 0.5, SIZE.y * 0.5)
	_build()
	refresh()


func _build() -> void:
	_art = UITheme.rounded_art(CardDB.texture(str(card_def.get("art", ""))), ART.size, 6.0)
	_art.position = ART.position
	add_child(_art)

	_cost = UITheme.outline_label(str(int(card_def.get("cost", 0))), 15, Color.WHITE, 5)
	_cost.position = Vector2(3, 3)
	_cost.size = Vector2(26, 26)
	_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_cost)

	_name = UITheme.outline_label(str(card_def.get("name", "")), 11, UITheme.TEXT, 4)
	_name.position = Vector2(4, 121)
	_name.size = Vector2(SIZE.x - 8, 16)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_name)

	if str(card_def.get("type", "MINION")) == "MINION":
		_atk = UITheme.outline_label(str(int(card_def.get("attack", 0))), 14, Color.WHITE, 5)
		_atk.position = Vector2(3, 148)
		_atk.size = Vector2(28, 26)
		_atk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_atk.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_atk)

		_hp = UITheme.outline_label(str(int(card_def.get("health", 1))), 14, Color.WHITE, 5)
		_hp.position = Vector2(SIZE.x - 31, 148)
		_hp.size = Vector2(28, 26)
		_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_hp)

	_badge = UITheme.outline_label("", 13, Color("ffe6a8"), 5)
	_badge.position = Vector2(SIZE.x - 40, -4)
	_badge.size = Vector2(38, 24)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_badge)


func refresh() -> void:
	_badge.text = "×%d" % count if count > 1 else ""
	modulate = Color(1, 1, 1, 0.55) if disabled else Color.WHITE
	queue_redraw()


func set_count(value: int) -> void:
	count = value
	refresh()


func _draw() -> void:
	var class_color := CardDB.class_color(str(card_def.get("class", "NEUTRAL")))
	var border := CardDB.rarity_color(str(card_def.get("rarity", "COMMON")))

	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.45)
	shadow.set_corner_radius_all(10)
	shadow.shadow_color = Color(0, 0, 0, 0.45)
	shadow.shadow_size = 8
	shadow.shadow_offset = Vector2(0, 4)
	draw_style_box(shadow, Rect2(Vector2(0, 2), SIZE))

	var frame := StyleBoxFlat.new()
	frame.bg_color = class_color.darkened(0.78)
	frame.set_corner_radius_all(9)
	frame.border_color = border.darkened(0.1)
	frame.set_border_width_all(2)
	draw_style_box(frame, Rect2(Vector2.ZERO, SIZE))

	# 名称条底
	var strip := StyleBoxFlat.new()
	strip.bg_color = class_color.darkened(0.86)
	strip.set_corner_radius_all(6)
	strip.border_color = Color(UITheme.GOLD, 0.35)
	strip.set_border_width_all(1)
	draw_style_box(strip, Rect2(6, 119, SIZE.x - 12, 21))

	# 费用 / 攻血底座
	draw_circle(Vector2(16, 16), 13.5, Color("0d2540"))
	draw_circle(Vector2(16, 16), 11.5, Color("2f7fc0"))
	draw_arc(Vector2(16, 16), 13.5, 0, TAU, 24, Color("9fd8ff"), 1.4, true)
	if str(card_def.get("type", "MINION")) == "MINION":
		draw_circle(Vector2(17, 161), 13.5, Color("2a1f10"))
		draw_circle(Vector2(17, 161), 11.0, Color("c79a4d"))
		draw_arc(Vector2(17, 161), 13.5, 0, TAU, 24, Color("f4dda6"), 1.2, true)
		draw_circle(Vector2(SIZE.x - 17, 161), 13.5, Color("2a0f10"))
		draw_circle(Vector2(SIZE.x - 17, 161), 11.0, Color("b23a3a"))
		draw_arc(Vector2(SIZE.x - 17, 161), 13.5, 0, TAU, 24, Color("f0a090"), 1.2, true)

	if selected or _hover > 0.01:
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(0, 0, 0, 0)
		glow.border_color = Color(1.0, 0.84, 0.45, 0.85 if selected else _hover * 0.6)
		glow.set_border_width_all(3)
		glow.set_corner_radius_all(11)
		draw_style_box(glow, Rect2(Vector2(-3, -3), SIZE + Vector2(6, 6)))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		accept_event()
		pressed.emit(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		if Sfx != null:
			Sfx.ui_hover()
		var tw := create_tween()
		tw.tween_method(_set_hover, _hover, 1.0, 0.12)
		z_index = 10
	elif what == NOTIFICATION_MOUSE_EXIT:
		var tw := create_tween()
		tw.tween_method(_set_hover, _hover, 0.0, 0.12)
		z_index = 0


func _set_hover(value: float) -> void:
	_hover = value
	queue_redraw()
