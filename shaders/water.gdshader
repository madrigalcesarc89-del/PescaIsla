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
	// 14c: bruma corta 12-40 m: a 40 m el agua ya es horizon_color plano.
	float m2 = smoothstep(12.0, 40.0, d);
	col = mix(col, horizon_color.rgb, m2);

	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	col += fres * sun_tint * sun_glint * (1.0 - m2);

	// 11c: cáustica suave procedural que se desplaza lento (2 senos baratos).
	// Solo cerca/medio: se apaga con m2 para no mover el tono del horizonte.
	float ca = sin(w_xz.x * 1.35 + TIME * 0.5) * sin(w_xz.y * 1.7 - TIME * 0.42);
	ca = smoothstep(0.55, 0.95, ca) * 0.05 * (1.0 - m2);
	col += sun_tint * ca;

	// 11c: destellos pequeños en crestas de ola.
	float gl = smoothstep(0.78, 1.0, crest) * 0.09 * (1.0 - m2);
	col += sun_tint * gl;

	// 14c: remate de bruma dentro del tramo corto (termina plano en 40 m).
	float haze = smoothstep(30.0, 40.0, d);
	col = mix(col, horizon_color.rgb, haze * 0.35);

	ALBEDO = col;
}
