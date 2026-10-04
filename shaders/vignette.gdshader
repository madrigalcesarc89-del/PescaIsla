shader_type canvas_item;
// Viñeta barata Paso 11b: velo cálido solo en bordes (~8 % más oscuro),
// tinte cálido + grano muy sutil conmutable. Una sola pasada, sin texturas.
uniform vec3 veil_color : source_color = vec3(0.32, 0.20, 0.12);
uniform float edge_amount = 0.08;
uniform float grain_amount = 0.02;
uniform bool grain_enabled = true;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 q = UV - vec2(0.5);
	q.x *= 0.5625; // compensa retrato 1080x1920
	float d = clamp(length(q) * 1.55, 0.0, 1.0);
	float v = pow(d, 2.2) * edge_amount;
	float a = v;
	if (grain_enabled) {
		float g = hash12(UV * vec2(1080.0, 1920.0) + fract(TIME) * 61.7) - 0.5;
		a += g * grain_amount;
	}
	COLOR = vec4(veil_color, clamp(a, 0.0, 0.14));
}
