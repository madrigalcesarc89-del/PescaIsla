shader_type canvas_item;

// El PNG del marco es transparente fuera de la tarjeta y también en el hueco.
// El crema solo puede verse en el hueco, nunca en el margen de arriba.
uniform sampler2D frame_tex : filter_linear, repeat_disable;

void fragment() {
	float a = texture(frame_tex, UV).a;
	float hole = 1.0 - smoothstep(0.04, 0.4, a);
	float inside_x = smoothstep(0.03, 0.08, UV.x) * smoothstep(0.97, 0.92, UV.x);
	float inside_y = smoothstep(0.035, 0.055, UV.y) * smoothstep(0.97, 0.94, UV.y);
	COLOR.a *= hole * inside_x * inside_y;
}
