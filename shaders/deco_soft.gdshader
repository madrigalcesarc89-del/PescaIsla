shader_type spatial;
// El dibujo ya trae su luz. No usamos las normales: en el móvil
// se rompen al girar y dejan manchas negras.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float fill : hint_range(0.2, 1.2) = 0.92;

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	if (tex.a < 0.08) {
		discard;
	}
	ALBEDO = tex.rgb * fill;
}
