shader_type spatial;
render_mode blend_mix, depth_draw_alpha_prepass, cull_disabled, diffuse_lambert, specular_schlick_ggx;

// Agua barata para móvil: sin reflejos en tiempo real.
// Turquesa #5CC8C2 cerca -> azul noche #2B3A67 lejos, ondas seno por vértice + fresnel.

uniform vec4 shallow_color : source_color = vec4(0.36, 0.78, 0.76, 1.0);
uniform vec4 deep_color : source_color = vec4(0.17, 0.23, 0.40, 1.0);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.80, 0.62);
uniform float wave_height : hint_range(0.0, 0.5) = 0.12;
uniform float wave_speed = 1.2;
uniform float wave_freq = 0.6;
uniform float fresnel_power = 3.0;
uniform float sun_glint = 0.35;
uniform float alpha : hint_range(0.0, 1.0) = 0.88;

void vertex() {
	float w1 = sin(VERTEX.x * wave_freq + TIME * wave_speed) * wave_height;
	float w2 = sin(VERTEX.z * wave_freq * 1.3 + TIME * wave_speed * 1.2) * wave_height * 0.6;
	VERTEX.y += w1 + w2;
}

void fragment() {
	// Degradado cerca->lejos usando UV del PlaneMesh (v=0 cerca isla, v=1 lejos).
	float far_mix = clamp(UV.y, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, far_mix);

	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	col += fres * sun_tint * sun_glint;

	ALBEDO = col;
	ALPHA = alpha;
	ROUGHNESS = 0.35;
	SPECULAR = 0.4;
	METALLIC = 0.0;
}
