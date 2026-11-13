shader_type canvas_item;

uniform vec4 dim : source_color = vec4(0.18, 0.10, 0.07, 0.58);
uniform vec2 screen_px = vec2(1080.0, 1920.0);
uniform int holes = 0;
uniform vec4 hole_a = vec4(0.0);
uniform vec4 hole_b = vec4(0.0);
uniform float radius = 36.0;

float sd_box(vec2 p, vec2 h, float r) {
	vec2 q = abs(p) - h + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = UV * screen_px;
	float a = dim.a;
	if (holes >= 1) {
		float d = sd_box(p - hole_a.xy, hole_a.zw, radius);
		a *= smoothstep(-2.0, 26.0, d);
	}
	if (holes >= 2) {
		float d2 = sd_box(p - hole_b.xy, hole_b.zw, radius);
		a *= smoothstep(-2.0, 26.0, d2);
	}
	COLOR = vec4(dim.rgb, a);
}
