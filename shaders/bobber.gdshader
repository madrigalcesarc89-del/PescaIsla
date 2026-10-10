shader_type spatial;
// 20g: flotador de dos colores (rojo arriba, crema abajo) por Y objeto.
render_mode unshaded;

uniform vec4 top_color : source_color = vec4(0.85, 0.15, 0.12, 1.0);
uniform vec4 bottom_color : source_color = vec4(1.0, 0.95, 0.88, 1.0);

varying float obj_y;

void vertex() {
	obj_y = VERTEX.y;
}

void fragment() {
	float k = smoothstep(-0.004, 0.004, obj_y);
	ALBEDO = mix(bottom_color.rgb, top_color.rgb, k);
}
