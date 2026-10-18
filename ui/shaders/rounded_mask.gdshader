shader_type canvas_item;
// 圆角裁切：给 TextureRect 用，避免美术直角戳出卡框。
// rect_size 用控件像素尺寸，radius 为圆角半径。

uniform vec2 rect_size = vec2(172.0, 112.0);
uniform float radius = 12.0;
uniform float feather : hint_range(0.5, 3.0) = 1.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 p = UV * rect_size;
	vec2 half_size = rect_size * 0.5;
	vec2 d = abs(p - half_size) - (half_size - vec2(radius));
	float dist = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - radius;
	float mask = 1.0 - smoothstep(-feather, feather, dist);
	COLOR = vec4(tex.rgb, tex.a * mask) * COLOR;
}
