class_name Backdrop
extends Control
## 全屏背景：暖色渐晕 + 缓慢漂浮的火星。

var _shader_rect: ColorRect
var _embers: CPUParticles2D


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shader_rect = ColorRect.new()
	_shader_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shader_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 top_color : source_color = vec4(0.035, 0.043, 0.062, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.075, 0.06, 0.052, 1.0);
uniform vec4 glow_color : source_color = vec4(0.62, 0.38, 0.16, 1.0);
void fragment() {
	vec2 uv = UV;
	vec3 col = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, uv.y));
	float d = distance(uv, vec2(0.5, 0.42));
	col += glow_color.rgb * smoothstep(0.85, 0.05, d) * 0.30;
	float vig = smoothstep(1.05, 0.25, distance(uv, vec2(0.5, 0.5)));
	col *= 0.68 + 0.32 * vig;
	float n = fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
	col += (n - 0.5) * 0.012;
	COLOR = vec4(col, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_shader_rect.material = mat
	add_child(_shader_rect)

	_embers = CPUParticles2D.new()
	_embers.amount = 26
	_embers.lifetime = 16.0
	_embers.preprocess = 12.0
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_embers.emission_rect_extents = Vector2(820, 470)
	_embers.direction = Vector2(0, -1)
	_embers.spread = 30.0
	_embers.initial_velocity_min = 6.0
	_embers.initial_velocity_max = 26.0
	_embers.gravity = Vector2(0, -2.5)
	_embers.scale_amount_min = 0.4
	_embers.scale_amount_max = 1.4
	_embers.color = Color(1.0, 0.78, 0.42, 0.30)
	_embers.texture = _dot_texture()
	_embers.position = Vector2(800, 450)
	add_child(_embers)


func _dot_texture() -> Texture2D:
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	for y in 12:
		for x in 12:
			var d := Vector2(x - 5.5, y - 5.5).length()
			var a := clampf(1.0 - d / 5.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 0.85, 0.6, a * a))
	return ImageTexture.create_from_image(img)
