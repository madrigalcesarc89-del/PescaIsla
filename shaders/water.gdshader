shader_type spatial;
render_mode depth_draw_opaque, cull_disabled, unshaded;

// Agua barata para móvil: sin reflejos en tiempo real.
// Turquesa #5CC8C2 cerca -> azul noche #2B3A67 lejos, ondas seno por vértice + fresnel.

uniform vec4 shallow_color : source_color = vec4(0.246, 0.657, 0.636, 1.0);
uniform vec4 deep_color : source_color = vec4(0.75, 0.62, 0.72, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.988, 0.722, 0.632, 1.0);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.80, 0.62);
uniform float wave_height : hint_range(0.0, 0.5) = 0.12;
uniform float wave_speed = 1.2;
uniform float wave_freq = 0.6;
uniform float fresnel_power = 5.0;
uniform float sun_glint = 0.15;
uniform float haze_start = 12.0;
uniform float haze_end = 40.0;
// 0 deja el brillo como antes. Un valor bajo apaga el reflejo lejos, para que no pinte una franja bajo el cielo.
uniform float glint_far = 80.0;

varying vec2 w_xz;
varying float crest;

void vertex() {
	float w1 = sin(VERTEX.x * wave_freq + TIME * wave_speed) * wave_height;
	float w2 = sin(VERTEX.z * wave_freq * 1.3 + TIME * wave_speed * 1.2) * wave_height * 0.6;
	// Mar calmada a lo lejos: borde del plano recto.
	float calm = 1.0 - smoothstep(20.0, 40.0, distance((MODEL_MATRIX * vec4(VERTEX, 1.0)).xz, vec2(0.0, 2.0)));
	VERTEX.y += (w1 + w2) * calm;
	w_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	// Cresta normalizada 0..1 para destellos (0 valle, 1 cresta).
	crest = clamp(0.5 + (w1 + w2) / (3.2 * max(wave_height, 0.001)), 0.0, 1.0);
}

void fragment() {
	// Dos tramos por distancia mundo: 3-25 m turquesa->lila, 25-95 m lila->cielo.
	float d = distance(w_xz, vec2(0.0, 2.0));
	float m1 = clamp((d - 3.0) / 22.0, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, m1);
	float m2 = smoothstep(haze_start, haze_end, d);
	col = mix(col, horizon_color.rgb, m2);

	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	float glint_mask = (1.0 - m2) * (1.0 - smoothstep(glint_far * 0.5, glint_far, d));
	col += fres * sun_tint * sun_glint * glint_mask;

	float ca = sin(w_xz.x * 1.35 + TIME * 0.5) * sin(w_xz.y * 1.7 - TIME * 0.42);
	ca = smoothstep(0.55, 0.95, ca) * 0.05 * glint_mask;
	col += sun_tint * ca;

	float gl = smoothstep(0.78, 1.0, crest) * 0.09 * glint_mask;
	col += sun_tint * gl;

	float haze = smoothstep(haze_end - 10.0, haze_end, d);
	col = mix(col, horizon_color.rgb, haze * 0.35);

	ALBEDO = col;
}
