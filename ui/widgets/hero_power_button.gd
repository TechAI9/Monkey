class_name HeroPowerButton
extends Control
## 英雄技能按钮：圆形技能图标 + 费用宝石，可用时金色呼吸光。

signal pressed

const SIZE := Vector2(104, 122)

var power: Dictionary = {}
var _available := false
var _used := false
var _icon: TextureRect
var _cost: Label
var _name: Label
var _ring_alpha := 0.0


func setup(p_power: Dictionary) -> void:
	power = p_power
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = SIZE * 0.5
	_build()
	refresh_state(false, false)


func _build() -> void:
	_icon = TextureRect.new()
	_icon.position = Vector2(16, 8)
	_icon.size = Vector2(72, 72)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_icon.texture = CardDB.art(power.get("icon", ""))
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = length(UV - vec2(0.5));
	c.a *= smoothstep(0.5, 0.46, d);
	COLOR = c;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_icon.material = mat
	add_child(_icon)

	_cost = UITheme.outline_label(str(int(power.get("cost", 2))), 17, Color.WHITE, 6)
	_cost.position = Vector2(62, 54)
	_cost.size = Vector2(34, 34)
	_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_cost)

	_name = UITheme.outline_label(power.get("name", ""), 11, Color(UITheme.TEXT, 0.9), 5)
	_name.position = Vector2(-4, 90)
	_name.size = Vector2(SIZE.x + 8, 20)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.clip_text = true
	add_child(_name)

	mouse_entered.connect(func():
		if _available:
			create_tween().tween_property(self, "scale", Vector2(1.06, 1.06), 0.1)
	)
	mouse_exited.connect(func():
		create_tween().tween_property(self, "scale", Vector2.ONE, 0.1)
	)


func refresh_state(available: bool, used: bool) -> void:
	_available = available
	_used = used
	modulate = Color(1, 1, 1, 1) if available else Color(0.58, 0.6, 0.66, 1)
	queue_redraw()


func _process(_delta: float) -> void:
	if _available:
		_ring_alpha = 0.5 + 0.35 * sin(Time.get_ticks_msec() / 420.0)
		queue_redraw()


func _draw() -> void:
	var center := Vector2(SIZE.x * 0.5, 44)
	draw_circle(center, 42, Color(0, 0, 0, 0.5))
	draw_circle(center, 39, Color("101821"))
	draw_circle(center, 37, Color("1b2634"))
	draw_arc(center, 39, 0, TAU, 56, Color(UITheme.GOLD_DIM, 0.9), 1.6, true)
	draw_arc(center, 36, 0, TAU, 56, Color(1, 1, 1, 0.06), 1.0, true)
	if _available:
		draw_arc(center, 43, 0, TAU, 56,
			Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, _ring_alpha), 2.8, true)
		draw_arc(center, 46, 0, TAU, 56,
			Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, _ring_alpha * 0.35), 5.0, true)
	if _used:
		draw_circle(center, 37, Color(0, 0, 0, 0.42))

	# 费用宝石
	var gc := Vector2(81, 74)
	draw_circle(gc, 14.5, Color(0, 0, 0, 0.8))
	draw_circle(gc, 13.0, Color("1c4a70"))
	draw_circle(gc, 11.0, Color("2f7fc0"))
	draw_arc(gc, 12.0, 0, TAU, 28, Color("9fd8ff"), 1.2, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and _available:
		pressed.emit()
		accept_event()
