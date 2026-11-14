shader_type canvas_item;

// 0 normal, 1 dorado, 2 albino. shine se anima solo en la ficha y la tarjeta.
uniform int variant = 0;
uniform float shine = 0.35;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 rgb = tex.rgb;
	float l = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	if (tex.a >= 0.02 && variant == 1) {
		vec3 shadow = vec3(0.45, 0.26, 0.06);
		vec3 mid = vec3(0.93, 0.70, 0.20);
		vec3 hi = vec3(1.0, 0.95, 0.68);
		vec3 gold = mix(shadow, mid, smoothstep(0.04, 0.52, l));
		gold = mix(gold, hi, smoothstep(0.52, 0.95, l));
		float band = UV.x * 0.72 + UV.y * 0.28;
		float dist = abs(fract(band - shine) - 0.5);
		float stripe = smoothstep(0.16, 0.0, dist);
		gold += vec3(1.0, 0.97, 0.78) * stripe * 0.5;
		rgb = gold;
	} else if (tex.a >= 0.02 && variant == 2) {
		vec3 pale = mix(tex.rgb, vec3(l), 0.85);
		pale *= 1.2;
		pale = mix(pale, vec3(0.97, 0.88, 0.95), 0.18);
		pale += vec3(1.0, 0.92, 0.97) * 0.07;
		rgb = pale;
	}
	COLOR = vec4(rgb, tex.a);
}
