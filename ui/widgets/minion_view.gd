class_name MinionView
extends Control
## 战场随从：圆角立绘 + 状态标识（嘲讽/圣盾/风怒/冻结/法术伤害/激怒）。
## 造型参考实体卡：职业色画框、底部数值宝石、嘲讽石框、圣盾金罩。

signal drag_started(view: MinionView)
signal drag_moved(view: MinionView)
signal drag_ended(view: MinionView, drop_position: Vector2)
signal hover_changed(view: MinionView, hovered: bool)

const VIEW_SIZE := Vector2(136, 182)
const PORTRAIT := Rect2(8, 8, 120, 112)
const GEM_R := 15.5
const ATK_CENTER := Vector2(21, 160)
const HP_CENTER := Vector2(115, 160)

var instance: CardInstance
var draggable := false
var dragging := false
var _hovered := false
var _pressed := false
var _press_pos := Vector2.ZERO
var _drag_offset := Vector2.ZERO
var _target_glow := false
var _origin := Vector2.ZERO

var _art: TextureRect
var _deco: Control
var _name: Label
var _atk: Label
var _hp: Label
var _status: Label
var _frozen_overlay: ColorRect


func setup(p_instance: CardInstance) -> void:
	instance = p_instance
	custom_minimum_size = VIEW_SIZE
	size = VIEW_SIZE
	pivot_offset = Vector2(VIEW_SIZE.x * 0.5, VIEW_SIZE.y * 0.5)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	_build()
	refresh()
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))


func _build() -> void:
	_art = UITheme.rounded_art(CardDB.art(instance.card_id), PORTRAIT.size, 11.0)
	_art.position = PORTRAIT.position
	add_child(_art)

	_deco = Control.new()
	_deco.size = VIEW_SIZE
	_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deco.draw.connect(_draw_deco)
	add_child(_deco)

	_status = UITheme.label("", 10, UITheme.GOLD, true)
	_status.position = Vector2(0, 1)
	_status.size = Vector2(VIEW_SIZE.x, 18)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_constant_override("outline_size", 5)
	add_child(_status)

	_name = UITheme.outline_label("", 11, UITheme.TEXT, 5)
	_name.position = Vector2(4, 119)
	_name.size = Vector2(VIEW_SIZE.x - 8, 20)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_name)

	_atk = UITheme.outline_label("", 18, Color.WHITE, 5)
	_atk.position = ATK_CENTER - Vector2(GEM_R, GEM_R)
	_atk.size = Vector2(GEM_R * 2, GEM_R * 2)
	_atk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_atk.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_atk)

	_hp = UITheme.outline_label("", 18, Color.WHITE, 5)
	_hp.position = HP_CENTER - Vector2(GEM_R, GEM_R)
	_hp.size = Vector2(GEM_R * 2, GEM_R * 2)
	_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_hp)

	_frozen_overlay = ColorRect.new()
	_frozen_overlay.color = Color(0.32, 0.66, 1.0, 0.20)
	_frozen_overlay.position = PORTRAIT.position
	_frozen_overlay.size = PORTRAIT.size
	_frozen_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frozen_overlay.visible = false
	add_child(_frozen_overlay)


func refresh() -> void:
	if instance == null:
		return
	_name.text = instance.name()
	_atk.text = str(instance.current_attack())
	_hp.text = str(instance.health)
	var parts: Array = []
	if instance.has_keyword("TAUNT"):
		parts.append("嘲讽")
	if instance.has_keyword("DIVINE_SHIELD"):
		parts.append("圣盾")
	if instance.has_keyword("WINDFURY"):
		parts.append("风怒")
	if instance.has_keyword("LIFESTEAL"):
		parts.append("吸血")
	if instance.spell_damage > 0:
		parts.append("法术+%d" % instance.spell_damage)
	if instance.dead:
		parts.append("死亡")
	_status.text = " · ".join(parts)
	_frozen_overlay.visible = instance.frozen
	_atk.add_theme_color_override("font_color",
		Color("a8f0a8") if instance.current_attack() > instance.attack else Color.WHITE)
	_hp.add_theme_color_override("font_color",
		Color("ff9a8a") if instance.is_damaged() else Color.WHITE)
	queue_redraw()
	_deco.queue_redraw()


func set_draggable(value: bool) -> void:
	if draggable == value:
		return
	draggable = value
	queue_redraw()


func set_target_glow(value: bool) -> void:
	_target_glow = value
	_deco.queue_redraw()


func _draw() -> void:
	var def := instance.def()
	var rarity: String = def.get("rarity", "COMMON")
	var class_color := CardDB.class_color(def.get("class", "NEUTRAL"))
	var border := CardDB.rarity_color(rarity)
	if rarity == "LEGENDARY":
		border = Color(1.0, 0.85, 0.45)

	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.5)
	shadow.set_corner_radius_all(14)
	shadow.shadow_color = Color(0, 0, 0, 0.5)
	shadow.shadow_size = 8
	shadow.shadow_offset = Vector2(0, 4)
	draw_style_box(shadow, Rect2(Vector2(0, 3), VIEW_SIZE - Vector2(0, 3)))

	var frame := StyleBoxFlat.new()
	frame.bg_color = class_color.darkened(0.78)
	frame.set_corner_radius_all(13)
	frame.border_color = border.darkened(0.1)
	frame.set_border_width_all(2)
	draw_style_box(frame, Rect2(Vector2.ZERO, VIEW_SIZE))

	var bevel := StyleBoxFlat.new()
	bevel.bg_color = Color(0, 0, 0, 0)
	bevel.border_color = Color(UITheme.GOLD, 0.35)
	bevel.set_border_width_all(1)
	bevel.set_corner_radius_all(10)
	draw_style_box(bevel, Rect2(Vector2(4, 4), VIEW_SIZE - Vector2(8, 8)))

	# 立绘底框
	var art_bg := StyleBoxFlat.new()
	art_bg.bg_color = Color("080b10")
	art_bg.set_corner_radius_all(12)
	art_bg.border_color = Color(0, 0, 0, 0.55)
	art_bg.set_border_width_all(2)
	draw_style_box(art_bg, Rect2(PORTRAIT.position - Vector2(2, 2), PORTRAIT.size + Vector2(4, 4)))

	# 名字下面的小缎带
	var ribbon := StyleBoxFlat.new()
	ribbon.bg_color = Color(class_color.darkened(0.84), 0.95)
	ribbon.set_corner_radius_all(6)
	ribbon.border_color = Color(UITheme.GOLD, 0.4)
	ribbon.set_border_width_all(1)
	draw_style_box(ribbon, Rect2(6, 117, VIEW_SIZE.x - 12, 22))

	# 数值宝石
	_draw_attack_gem(ATK_CENTER, GEM_R)
	_draw_health_gem(HP_CENTER, GEM_R)

	# 嘲讽：石质厚框
	if instance.has_keyword("TAUNT"):
		var stone := StyleBoxFlat.new()
		stone.bg_color = Color(0, 0, 0, 0)
		stone.border_color = Color("8a6f45")
		stone.set_border_width_all(4)
		stone.set_corner_radius_all(13)
		draw_style_box(stone, Rect2(PORTRAIT.position - Vector2(3, 3), PORTRAIT.size + Vector2(6, 6)))
		var inner := StyleBoxFlat.new()
		inner.bg_color = Color(0, 0, 0, 0)
		inner.border_color = Color(UITheme.GOLD, 0.55)
		inner.set_border_width_all(1)
		inner.set_corner_radius_all(12)
		draw_style_box(inner, Rect2(PORTRAIT.position - Vector2(1, 1), PORTRAIT.size + Vector2(2, 2)))

	# 圣盾：金色气泡
	if instance.has_keyword("DIVINE_SHIELD"):
		var ring := StyleBoxFlat.new()
		ring.bg_color = Color(1.0, 0.88, 0.5, 0.06)
		ring.border_color = Color(1.0, 0.86, 0.5, 0.9)
		ring.set_border_width_all(3)
		ring.set_corner_radius_all(15)
		draw_style_box(ring, Rect2(Vector2(-2, -2), VIEW_SIZE + Vector2(4, 4)))

	if instance.frozen:
		draw_rect(Rect2(PORTRAIT.position, PORTRAIT.size), Color(0.3, 0.65, 1.0, 0.10))

	if instance.enrage_attack > 0 and instance.is_damaged():
		draw_circle(Vector2(VIEW_SIZE.x - 16, 18), 4.0, Color("ff6a4a"))
		draw_arc(Vector2(VIEW_SIZE.x - 16, 18), 6.0, 0, TAU, 16, Color(1, 0.5, 0.35, 0.5), 1.2, true)


func _draw_deco() -> void:
	# 可攻击：绿色呼吸环
	if draggable:
		var pulse := 0.35 + 0.2 * sin(Time.get_ticks_msec() / 380.0)
		var ring := StyleBoxFlat.new()
		ring.bg_color = Color(0, 0, 0, 0)
		ring.border_color = Color(0.4, 0.95, 0.55, pulse)
		ring.set_border_width_all(2)
		ring.set_corner_radius_all(14)
		_deco.draw_style_box(ring, Rect2(Vector2(-2, -2), VIEW_SIZE + Vector2(4, 4)))

	if _target_glow:
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(1.0, 0.75, 0.25, 0.08)
		glow.border_color = Color(1.0, 0.82, 0.35, 0.98)
		glow.set_border_width_all(3)
		glow.set_corner_radius_all(16)
		_deco.draw_style_box(glow, Rect2(Vector2(-4, -4), VIEW_SIZE + Vector2(8, 8)))

	# 嘲讽盾徽（压在立绘上方居中）
	if instance.has_keyword("TAUNT"):
		var cx := VIEW_SIZE.x * 0.5
		var pts := PackedVector2Array([
			Vector2(cx - 12, 3), Vector2(cx + 12, 3), Vector2(cx + 12, 13),
			Vector2(cx, 23), Vector2(cx - 12, 13),
		])
		_deco.draw_colored_polygon(pts, Color("3b2d17"))
		var inner := PackedVector2Array([
			Vector2(cx - 8, 6), Vector2(cx + 8, 6), Vector2(cx + 8, 12),
			Vector2(cx, 19), Vector2(cx - 8, 12),
		])
		_deco.draw_colored_polygon(inner, Color("a5814a"))
		var o := pts.duplicate()
		o.append(pts[0])
		_deco.draw_polyline(o, Color("f0d79a"), 1.4, true)

	# 冻结冰晶
	if instance.frozen:
		for p in [Vector2(14, 16), Vector2(VIEW_SIZE.x - 16, 14), Vector2(18, PORTRAIT.end.y - 8),
				Vector2(VIEW_SIZE.x - 22, PORTRAIT.end.y - 10)]:
			var s := 6.0
			_deco.draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -s), p + Vector2(s * 0.7, 0),
				p + Vector2(0, s), p + Vector2(-s * 0.7, 0),
			]), Color(0.75, 0.92, 1.0, 0.55))
			_deco.draw_circle(p, 2.0, Color(1, 1, 1, 0.8))


func _draw_attack_gem(center: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := -PI * 0.5 + TAU * float(i) / 8.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, Color("2a1f10"))
	var inner := PackedVector2Array()
	for i in 8:
		var a := -PI * 0.5 + TAU * float(i) / 8.0
		inner.append(center + Vector2(cos(a), sin(a)) * (r - 2.4))
	draw_colored_polygon(inner, Color("c79a4d"))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -r + 3), center + Vector2(r - 4, 0),
		center + Vector2(0, r * 0.3), center + Vector2(-r + 4, 0),
	]), Color(1, 1, 1, 0.15))
	var o := pts.duplicate()
	o.append(pts[0])
	draw_polyline(o, Color("f4dda6"), 1.3, true)


func _draw_health_gem(center: Vector2, r: float) -> void:
	var pts := UITheme.drop_points(center, r)
	draw_colored_polygon(pts, Color("2a0f10"))
	draw_colored_polygon(UITheme.drop_points(center + Vector2(0, -0.6), r - 2.6), Color("b23a3a"))
	draw_colored_polygon(UITheme.drop_points(center + Vector2(-1.2, -2.0), r * 0.45),
		Color(1, 1, 1, 0.12))
	var o := pts.duplicate()
	o.append(pts[0])
	draw_polyline(o, Color("f0a090"), 1.3, true)


# ------------------------------------------------------------------ input
func _gui_input(event: InputEvent) -> void:
	if not draggable:
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
				dragging = false
				drag_ended.emit(self, get_global_mouse_position())
			accept_event()
	elif event is InputEventMouseMotion and _pressed and not dragging:
		if event.position.distance_to(_press_pos) > 8.0:
			dragging = true
			_origin = position
			z_index = 300
			drag_started.emit(self)
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		global_position = get_global_mouse_position() - _drag_offset
		drag_moved.emit(self)
		accept_event()


func _on_hover(value: bool) -> void:
	_hovered = value
	z_index = 40 if value else 10
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.08, 1.08) if value else Vector2.ONE, 0.1)
	if value and Sfx != null:
		Sfx.ui_hover()
	hover_changed.emit(self, value)


func cancel_drag() -> void:
	dragging = false
	z_index = 0
	position = _origin
