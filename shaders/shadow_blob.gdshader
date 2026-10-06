shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// Sombra de contacto del gato: mancha eliptica suave sobre la cubierta.
// La textura aporta solo el alfa (marron calido uniforme en RGB).

uniform sampler2D tex : source_color;
uniform float opacity : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	float a = texture(tex, UV).a * opacity;
	// Recorta el alfa en el borde del plano para que nunca se vea un filo
	// recto aunque el quad roce el borde de la cubierta.
	// (Solo operaciones escalares: min(vec2,vec2) no devolvia lo esperado.)
	float edge_x = min(UV.x, 1.0 - UV.x);
	float edge_y = min(UV.y, 1.0 - UV.y);
	float edge_fade = smoothstep(0.0, 0.05, min(edge_x, edge_y));
	ALBEDO = vec3(0.37, 0.24, 0.17);
	ALPHA = a * edge_fade;
}
