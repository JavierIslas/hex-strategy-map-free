shader_type canvas_item;

// Color base del fog overlay (incluye alpha).
// El renderer actualiza este uniform según el FogState del hex.
uniform vec4 fog_color : source_color = vec4(0.02, 0.02, 0.04, 1.0);

// Radio exterior del hex (distance center → vertex).
// El renderer lo setea a _hex_size al crear el ShaderMaterial.
uniform float hex_radius = 32.0;

// Escala del ruido — valores altos = grano más fino.
uniform float noise_scale : hint_range(1.0, 10.0) = 4.0;

// Velocidad de animación del ruido — 0 = estático.
uniform float noise_speed : hint_range(0.0, 2.0) = 0.3;

// Cuánto se desvanece el borde del hex (0 = borde duro, 0.5 = gradiente amplio).
uniform float edge_softness : hint_range(0.05, 0.5) = 0.2;

varying vec2 local_pos;


float _hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}


// Value noise 2D
float _vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(_hash(i), _hash(i + vec2(1.0, 0.0)), f.x),
		mix(_hash(i + vec2(0.0, 1.0)), _hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}


void vertex() {
	local_pos = VERTEX;
}


void fragment() {
	float dist = length(local_pos) / hex_radius;

	// Gradiente suave en bordes: opacidad total al centro, fade a transparente en el borde.
	float edge = smoothstep(1.0, 1.0 - edge_softness, dist);

	// Ruido animado para movimiento sutil del fog.
	float n = _vnoise(local_pos * noise_scale * 0.02 + TIME * noise_speed);

	COLOR = fog_color;
	COLOR.a *= edge * (0.82 + 0.18 * n);
}
