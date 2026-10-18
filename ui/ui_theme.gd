class_name UITheme
extends RefCounted
## 统一视觉：深色木质牌桌 + 暖金描边。所有样式在代码里生成，便于整体调色。

const BG := Color("0a0d13")
const BG_LIGHT := Color("131a24")
const PANEL := Color("151b25")
const PANEL_LIGHT := Color("1e2633")
const PANEL_DARK := Color("0d121a")
const GOLD := Color("e3c07b")
const GOLD_DIM := Color("8d7448")
const TEXT := Color("eae3d4")
const MUTED := Color("98a2b3")
const RED := Color("d9534f")
const GREEN := Color("57b57a")
const BLUE := Color("4aa3d8")
const PURPLE := Color("a674e0")

static var _font_regular: FontFile
static var _font_bold: FontFile


static func regular() -> FontFile:
	if _font_regular == null:
		_font_regular = load("res://assets/fonts/NotoSansSC-Regular.otf")
	return _font_regular


static func bold() -> FontFile:
	if _font_bold == null:
		_font_bold = load("res://assets/fonts/NotoSansSC-Bold.otf")
	return _font_bold


static func make() -> Theme:
	var t := Theme.new()
	t.default_font = regular()
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "RichTextLabel", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_constant("line_separation", "RichTextLabel", 3)

	t.set_stylebox("normal", "Button", button_style(PANEL, GOLD_DIM, 1))
	t.set_stylebox("hover", "Button", button_style(PANEL_LIGHT, GOLD, 1))
	t.set_stylebox("pressed", "Button", button_style(PANEL_DARK, GOLD, 2))
	t.set_stylebox("disabled", "Button", button_style(Color("11151c"), Color("3a3327"), 1))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color("fff3d6"))
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color("6b6f78"))
	t.set_font("font", "Button", bold())
	t.set_font_size("font_size", "Button", 19)

	t.set_stylebox("panel", "Panel", panel_style(PANEL, GOLD_DIM, 1, 14))
	t.set_stylebox("panel", "PanelContainer", panel_style(PANEL, GOLD_DIM, 1, 14))

	# 输入框 / 下拉框 / 多行文本：编辑器页统一观感
	t.set_stylebox("normal", "LineEdit", input_style(PANEL_DARK, Color(GOLD_DIM, 0.8)))
	t.set_stylebox("focus", "LineEdit", input_style(PANEL_DARK, GOLD))
	t.set_stylebox("read_only", "LineEdit",
		input_style(Color("0a0e14"), Color(GOLD_DIM, 0.35)))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.7))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(0.55, 0.45, 0.26, 0.45))
	t.set_font_size("font_size", "LineEdit", 16)

	t.set_stylebox("normal", "TextEdit", input_style(PANEL_DARK, Color(GOLD_DIM, 0.8)))
	t.set_stylebox("focus", "TextEdit", input_style(PANEL_DARK, GOLD))
	t.set_color("font_color", "TextEdit", TEXT)
	t.set_color("caret_color", "TextEdit", GOLD)
	t.set_color("selection_color", "TextEdit", Color(0.55, 0.45, 0.26, 0.45))
	t.set_font_size("font_size", "TextEdit", 15)

	t.set_stylebox("normal", "OptionButton", button_style(PANEL, GOLD_DIM, 1))
	t.set_stylebox("hover", "OptionButton", button_style(PANEL_LIGHT, GOLD, 1))
	t.set_stylebox("pressed", "OptionButton", button_style(PANEL_DARK, GOLD, 1))
	t.set_stylebox("disabled", "OptionButton", button_style(Color("11151c"), Color("3a3327"), 1))
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("font_hover_color", "OptionButton", Color("fff3d6"))
	t.set_font("font", "OptionButton", regular())
	t.set_font_size("font_size", "OptionButton", 15)

	t.set_stylebox("panel", "PopupMenu",
		panel_style(Color("141a23"), Color(GOLD_DIM, 0.9), 1, 8, 12))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color("fff3d6"))
	t.set_font("font", "PopupMenu", regular())
	t.set_font_size("font_size", "PopupMenu", 15)

	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color("fff3d6"))
	t.set_font("font", "CheckBox", regular())
	t.set_font_size("font_size", "CheckBox", 14)
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.45))

	# 滚动条压窄压暗，别抢视线
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, scrollbar_style())
		t.set_stylebox("grabber", bar, scrollbar_grabber(Color(GOLD_DIM, 0.7)))
		t.set_stylebox("grabber_highlight", bar, scrollbar_grabber(GOLD))
		t.set_stylebox("grabber_pressed", bar, scrollbar_grabber(GOLD))

	var empty := StyleBoxEmpty.new()
	t.set_stylebox("normal", "RichTextLabel", empty)
	t.set_stylebox("focus", "RichTextLabel", empty)
	return t


static func input_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := panel_style(bg, border, 1, 8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


static func scrollbar_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.18)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	return sb


static func scrollbar_grabber(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	return sb


static func panel_style(bg: Color, border: Color, border_width := 1, radius := 14,
		shadow := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if shadow > 0:
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = shadow
		sb.shadow_offset = Vector2(0, 5)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func button_style(bg: Color, border: Color, border_width := 1) -> StyleBoxFlat:
	var sb := panel_style(bg, border, border_width, 10, 0)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func label(text: String, size := 18, color := TEXT, is_bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if is_bold:
		l.add_theme_font_override("font", bold())
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 4)
	return l


static func outline_label(text: String, size := 18, color := TEXT,
		outline := 4) -> Label:
	var l := label(text, size, color, true)
	l.add_theme_constant_override("outline_size", outline)
	return l


## 深色字 + 浅色描边：给浅色牌桌/浅色面板用，保证在米色底上也能读清。
static func ink(text: String, size := 15, color := Color("3a2f22"), outline := 3) -> Label:
	var l := label(text, size, color, true)
	l.add_theme_color_override("font_outline_color", Color(1.0, 0.98, 0.92, 0.9))
	l.add_theme_constant_override("outline_size", outline)
	return l


## 圆角贴图（卡面美术、英雄立绘），避免直角戳出画框。
static func rounded_art(tex: Texture2D, view_size: Vector2, radius := 12.0) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.size = view_size
	t.custom_minimum_size = view_size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/shaders/rounded_mask.gdshader")
	mat.set_shader_parameter("rect_size", view_size)
	mat.set_shader_parameter("radius", radius)
	t.material = mat
	return t


static func crystal_points(center: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0, -r),
		center + Vector2(r * 0.78, -r * 0.4),
		center + Vector2(r * 0.78, r * 0.4),
		center + Vector2(0, r),
		center + Vector2(-r * 0.78, r * 0.4),
		center + Vector2(-r * 0.78, -r * 0.4),
	])


static func drop_points(center: Vector2, r: float) -> PackedVector2Array:
	# 血滴形：圆 + 下方尖角
	return PackedVector2Array([
		center + Vector2(-r * 0.72, r * 0.62),
		center + Vector2(0, r * 1.5),
		center + Vector2(r * 0.72, r * 0.62),
		center + Vector2(r, 0),
		center + Vector2(0, -r),
		center + Vector2(-r, 0),
	])

