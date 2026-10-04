shader_type spatial;
// Paso 11d: muelle con humedad por altura del mundo + luz de borde cálida.
// - Altura por fragmento vía varying (MODEL_MATRIX * VERTEX).y (corrección 11d-1).
// - Textura base del muelle (table) como albedo + muelle_roca_crema.jpg como
//   uniform sampler2D de micro-variación por luminancia (sin manchas de tono).
// - Iluminación PBR estándar (respeta dir/omni/ambiente), sin unshaded.
// - Efecto sutil: solo oscurece/satura cerca del agua, sin manchas.

uniform sampler2D base_tex;
uniform sampler2D table_tex;
uniform vec3 dry_tint : source_color = vec3(0.92, 0.70, 0.55);
uniform float wet_bottom = 0.0;
uniform float wet_top = 0.55;
uniform float wet_dark = 0.72;
uniform vec3 rim_tint : source_color = vec3(1.0, 0.8, 0.6);
uniform float rim_amount = 0.10;
uniform float rough_dry = 1.0;
uniform float rough_wet = 0.65;

varying float w_y;

void vertex() {
	w_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	// Albedo = textura base del muelle; la crema solo modula brillo (luma),
	// nunca tono: así no hay manchas aunque los UV no coincidan con ella.
	vec3 table = texture(table_tex, UV).rgb;
	float var_lum = dot(texture(base_tex, UV).rgb, vec3(0.299, 0.587, 0.114));
	vec3 base = table * (0.97 + 0.06 * clamp(var_lum * 1.4, 0.0, 1.0)) * dry_tint;
	float wet = 1.0 - smoothstep(wet_bottom, wet_top, w_y);
	// Húmedo: un poco más oscuro y saturado.
	vec3 wet_col = base * vec3(wet_dark, wet_dark * 0.97, wet_dark * 0.94);
	float lum = dot(wet_col, vec3(0.299, 0.587, 0.114));
	wet_col = mix(vec3(lum), wet_col, 1.18);
	vec3 col = mix(base, wet_col, wet);
	ALBEDO = col;
	ROUGHNESS = mix(rough_dry, rough_wet, wet);
	SPECULAR = 0.25;
	// Toque de luz de borde cálida en bordes superiores.
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float rim = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 3.0) * clamp(n.y, 0.0, 1.0);
	EMISSION = rim_tint * (rim * rim_amount);
}
