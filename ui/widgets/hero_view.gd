class_name HeroView
extends Control
## 英雄：立绘 + 名字/职业 + 生命宝石 + 护甲徽章 + 冻结/目标高亮。纯展示。

const VIEW_SIZE := Vector2(204, 186)
const ART_RECT := Rect2(6, 6, 192, 174)
const GEM_CENTER := Vector2(181, 154)
const GEM_R := 21.5
const ARMOR_CENTER := Vector2(24, 30)

var player_state: PlayerState
var is_player := true
var _target_glow := false
var _flash := 0.0

var _art: TextureRect
var _deco: Control
var _name: Label
var _class_label: Label
var _hp: Label
var _armor: Label


func setup(p_state: PlayerState, p_is_player: bool) -> void:
	player_state = p_state
	is_player = p_is_player
	custom_minimum_size = VIEW_SIZE
	size = VIEW_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	refresh()


func _build() -> void:
	_art = UITheme.rounded_art(CardDB.texture(player_state.portrait), ART_RECT.size, 14.0)
	_art.position = ART_RECT.position
	add_child(_art)

	# 底部渐隐，让名字可读
	var scrim := TextureRect.new()
	scrim.texture = _scrim_texture()
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.position = ART_RECT.position + Vector2(0, ART_RECT.size.y - 82)
	scrim.size = Vector2(ART_RECT.size.x, 82)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.material = _round_material(Vector2(ART_RECT.size.x, 82), 14.0)
	add_child(scrim)

	# 名字/职业整体避开右下角生命宝石（宝石外圈从 x≈156 起），只占左侧 144px
	_name = UITheme.outline_label("", 15, Color.WHITE, 7)
	_name.position = Vector2(ART_RECT.position.x + 2, ART_RECT.size.y - 68)
	_name.size = Vector2(144, 24)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_name)

	_class_label = UITheme.outline_label("", 10, Color(UITheme.GOLD, 0.95), 5)
	_class_label.position = Vector2(ART_RECT.position.x + 2, ART_RECT.size.y - 44)
	_class_label.size = Vector2(144, 18)
	_class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_class_label)

	_deco = Control.new()
	_deco.size = VIEW_SIZE
	_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deco.draw.connect(_draw_deco)
	add_child(_deco)

	_hp = UITheme.outline_label("30", 23, Color.WHITE, 9)
	_hp.position = GEM_CENTER - Vector2(GEM_R, GEM_R)
	_hp.size = Vector2(GEM_R * 2, GEM_R * 2)
	_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_deco.add_child(_hp)

	_armor = UITheme.outline_label("", 15, Color.WHITE, 7)
	_armor.position = ARMOR_CENTER - Vector2(15, 15)
	_armor.size = Vector2(30, 30)
	_armor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_armor.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_deco.add_child(_armor)


func _round_material(view_size: Vector2, radius: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/shaders/rounded_mask.gdshader")
	mat.set_shader_parameter("rect_size", view_size)
	mat.set_shader_parameter("radius", radius)
	return mat


func _scrim_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([
		Color(0.02, 0.03, 0.05, 0.0),
		Color(0.02, 0.03, 0.05, 0.45),
		Color(0.02, 0.03, 0.05, 0.92),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 8
	tex.height = 64
	return tex


func refresh() -> void:
	if player_state == null:
		return
	_name.text = player_state.hero_name
	_class_label.text = _class_title(player_state.hero_class)
	_hp.text = str(player_state.hp)
	_armor.text = str(player_state.armor)
	_armor.visible = player_state.armor > 0
	_hp.add_theme_color_override("font_color",
		Color("ff8a7a") if player_state.hp <= 10 else Color.WHITE)
	if _art.texture == null:
		_art.texture = CardDB.texture(player_state.portrait)
	_deco.queue_redraw()
	queue_redraw()


## 受击时闪一下，供伤害动画调用。
func flash(color: Color) -> void:
	modulate = color
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.28)


func _class_title(cls: String) -> String:
	match cls:
		"MAGE": return "法  师"
		"WARRIOR": return "战  士"
		"PALADIN": return "圣骑士"
	return "英  雄"


func set_target_glow(value: bool) -> void:
	_target_glow = value
	if _deco != null:
		_deco.queue_redraw()


func _draw() -> void:
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.5)
	shadow.set_corner_radius_all(16)
	shadow.shadow_color = Color(0, 0, 0, 0.55)
	shadow.shadow_size = 12
	shadow.shadow_offset = Vector2(0, 5)
	draw_style_box(shadow, Rect2(ART_RECT.position + Vector2(0, 3), ART_RECT.size))

	var body := StyleBoxFlat.new()
	body.bg_color = Color("0b1018")
	body.set_corner_radius_all(16)
	body.border_color = Color(UITheme.GOLD, 0.55)
	body.set_border_width_all(2)
	draw_style_box(body, ART_RECT)

	var bevel := StyleBoxFlat.new()
	bevel.bg_color = Color(0, 0, 0, 0)
	bevel.border_color = Color(1, 1, 1, 0.10)
	bevel.set_border_width_all(1)
	bevel.set_corner_radius_all(12)
	draw_style_box(bevel, Rect2(ART_RECT.position + Vector2(4, 4), ART_RECT.size - Vector2(8, 8)))


func _draw_deco() -> void:
	if player_state == null:
		return

	if player_state.frozen:
		_deco.draw_rect(ART_RECT, Color(0.35, 0.7, 1.0, 0.24))

	if _target_glow:
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(1.0, 0.75, 0.25, 0.06)
		glow.border_color = Color(1.0, 0.82, 0.35, 0.98)
		glow.set_border_width_all(4)
		glow.set_corner_radius_all(18)
		_deco.draw_style_box(glow, Rect2(ART_RECT.position - Vector2(4, 4),
			ART_RECT.size + Vector2(8, 8)))

	# 生命宝石
	var gc := GEM_CENTER
	_deco.draw_circle(gc, GEM_R + 3.0, Color(0, 0, 0, 0.8))
	_deco.draw_circle(gc, GEM_R, Color("5d1414"))
	_deco.draw_circle(gc, GEM_R - 2.5, Color("a52f2f"))
	_deco.draw_circle(gc + Vector2(0, GEM_R * 0.42), GEM_R - 4.0, Color(0, 0, 0, 0.10))
	_deco.draw_arc(gc, GEM_R - 1.0, 0, TAU, 48, Color("f2b09a"), 1.8, true)
	_deco.draw_circle(gc + Vector2(-7, -9), 6.0, Color(1, 1, 1, 0.18))

	# 护甲
	if player_state.armor > 0:
		var ac := ARMOR_CENTER
		_deco.draw_circle(ac, 17.0, Color(0, 0, 0, 0.8))
		_deco.draw_circle(ac, 15.0, Color("48535f"))
		_deco.draw_circle(ac, 11.5, Color("707d8d"))
		_deco.draw_arc(ac, 14.0, 0, TAU, 36, Color("d3dde9"), 1.6, true)
