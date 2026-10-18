class_name CardBackView
extends Control
## 对手手牌的卡背。纯代码绘制：深蓝绒面 + 金色纹章，不依赖外部贴图。

const VIEW_SIZE := Vector2(100, 146)


func setup() -> void:
	custom_minimum_size = VIEW_SIZE
	size = VIEW_SIZE
	pivot_offset = VIEW_SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, VIEW_SIZE)

	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.55)
	shadow.set_corner_radius_all(9)
	shadow.shadow_color = Color(0, 0, 0, 0.55)
	shadow.shadow_size = 10
	shadow.shadow_offset = Vector2(0, 4)
	draw_style_box(shadow, Rect2(Vector2(0, 3), VIEW_SIZE - Vector2(0, 3)))

	var base := StyleBoxFlat.new()
	base.bg_color = Color("0a0e16")
	base.set_corner_radius_all(9)
	base.border_color = Color(UITheme.GOLD, 0.85)
	base.set_border_width_all(2)
	draw_style_box(base, rect)

	var field := StyleBoxFlat.new()
	field.bg_color = Color("141f36")
	field.set_corner_radius_all(6)
	field.border_color = Color(UITheme.GOLD, 0.28)
	field.set_border_width_all(1)
	draw_style_box(field, Rect2(Vector2(4, 4), VIEW_SIZE - Vector2(8, 8)))

	# 斜向高光
	draw_colored_polygon(PackedVector2Array([
		Vector2(5, 5), Vector2(46, 5), Vector2(5, 112),
	]), Color(1, 1, 1, 0.055))
	draw_colored_polygon(PackedVector2Array([
		Vector2(VIEW_SIZE.x - 5, VIEW_SIZE.y - 5), Vector2(VIEW_SIZE.x - 38, VIEW_SIZE.y - 5),
		Vector2(VIEW_SIZE.x - 5, VIEW_SIZE.y - 86),
	]), Color(0, 0, 0, 0.10))

	# 织物暗纹
	for i in range(1, 7):
		var y := 6.0 + i * 19.0
		draw_line(Vector2(6, y), Vector2(VIEW_SIZE.x - 6, y), Color(1, 1, 1, 0.018), 1.0)

	var c := VIEW_SIZE * 0.5
	# 放射线
	for i in 12:
		var a := TAU * float(i) / 12.0
		draw_line(c + Vector2(cos(a), sin(a)) * 20.0,
			c + Vector2(cos(a), sin(a)) * 34.0, Color(UITheme.GOLD, 0.16), 1.0)

	draw_circle(c, 34.0, Color("0b1424"))
	draw_arc(c, 34.0, 0, TAU, 56, Color(UITheme.GOLD, 0.65), 1.6, true)
	draw_arc(c, 29.5, 0, TAU, 56, Color(UITheme.GOLD, 0.28), 1.0, true)
	draw_arc(c, 22.0, 0, TAU, 48, Color(UITheme.GOLD, 0.20), 1.0, true)

	# 中央纹章
	var diamond := PackedVector2Array([
		c + Vector2(0, -18), c + Vector2(14, 0), c + Vector2(0, 18), c + Vector2(-14, 0),
	])
	draw_colored_polygon(diamond, Color("22375e"))
	var inner := PackedVector2Array([
		c + Vector2(0, -11), c + Vector2(8.5, 0), c + Vector2(0, 11), c + Vector2(-8.5, 0),
	])
	draw_colored_polygon(inner, Color("2f4b7c"))
	var ring := diamond.duplicate()
	ring.append(diamond[0])
	draw_polyline(ring, Color(UITheme.GOLD, 0.85), 1.3, true)
	draw_circle(c, 3.4, Color(UITheme.GOLD, 0.95))
	draw_circle(c + Vector2(-1, -1), 1.3, Color(1, 1, 1, 0.8))

	# 四角金饰
	for p in [Vector2(11, 11), Vector2(VIEW_SIZE.x - 11, 11),
			Vector2(11, VIEW_SIZE.y - 11), Vector2(VIEW_SIZE.x - 11, VIEW_SIZE.y - 11)]:
		draw_arc(p, 5.0, 0.0, TAU, 16, Color(UITheme.GOLD, 0.38), 1.0, true)

	# 顶部与底部小菱形
	for y in [16.0, VIEW_SIZE.y - 16.0]:
		var p2 := Vector2(VIEW_SIZE.x * 0.5, y)
		draw_colored_polygon(PackedVector2Array([
			p2 + Vector2(0, -4), p2 + Vector2(3.5, 0), p2 + Vector2(0, 4), p2 + Vector2(-3.5, 0),
		]), Color(UITheme.GOLD, 0.5))
