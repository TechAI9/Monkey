class_name TargetArrow
extends Control
## 拖拽出牌 / 攻击时的指向箭头。用三层描边模拟发光。

var active := false
var start := Vector2.ZERO
var end := Vector2.ZERO
var valid := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func begin(from: Vector2) -> void:
	start = from
	end = from
	active = true
	visible = true
	queue_redraw()


func update_to(pos: Vector2) -> void:
	end = pos
	queue_redraw()


func stop() -> void:
	active = false
	visible = false
	queue_redraw()


func _curve_points() -> PackedVector2Array:
	var mid := (start + end) * 0.5
	var dir := end - start
	var normal := Vector2(-dir.y, dir.x).normalized()
	var bend := clampf(dir.length() * 0.18, 20.0, 120.0)
	var control := mid + normal * bend
	var pts := PackedVector2Array()
	for i in 25:
		var t := i / 24.0
		var p := start.lerp(control, t).lerp(control.lerp(end, t), t)
		pts.append(p)
	return pts


func _draw() -> void:
	if not active:
		return
	var pts := _curve_points()
	if pts.size() < 2:
		return
	var base := Color(1.0, 0.84, 0.42, 1.0) if valid else Color(0.9, 0.35, 0.3, 1.0)
	draw_polyline(pts, Color(base.r, base.g, base.b, 0.12), 16.0, true)
	draw_polyline(pts, Color(base.r, base.g, base.b, 0.3), 8.0, true)
	draw_polyline(pts, base, 3.0, true)

	var tip := pts[pts.size() - 1]
	var prev := pts[pts.size() - 2]
	var dir := (tip - prev).normalized()
	var normal := Vector2(-dir.y, dir.x)
	var p1 := tip + dir * 22.0
	var p2 := tip + normal * 11.0
	var p3 := tip - normal * 11.0
	draw_colored_polygon(PackedVector2Array([tip, p1 + normal * 2.0, tip + dir * 4.0,
		p2, p3]), base)
	draw_circle(tip, 5.0, Color(1, 1, 1, 0.85))
