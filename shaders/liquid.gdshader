shader_type spatial;
// Layered liquid inside a bottle. Layer boundaries are world-horizontal planes given as heights
// above the bottle origin (computed on the CPU from the volume tables), so the liquid looks right
// at any tilt. Back faces seen through the cut top are drawn as the liquid surface.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 colors[6];
uniform float bounds[7];
uniform float hidden[6];
uniform int nseg = 0;
uniform vec2 wobble = vec2(0.0);
uniform float glow = 0.0;
uniform float flash = 0.0;

varying vec3 rel;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	rel = w - MODEL_MATRIX[3].xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	float h = rel.y + wobble.x * rel.x + wobble.y * rel.z;
	if (nseg <= 0 || h > bounds[nseg]) {
		discard;
	}
	int k = 0;
	for (int i = 1; i < 6; i++) {
		if (i < nseg && h > bounds[i]) {
			k = i;
		}
	}
	vec3 base = colors[k].rgb;
	float lo = bounds[k];
	float hi = bounds[k + 1];
	float t = clamp((h - lo) / max(hi - lo, 0.001), 0.0, 1.0);
	bool hid = hidden[k] > 0.5;
	if (hid) {
		float sw = sin(rel.x * 9.0 + TIME * 1.3 + sin(h * 11.0 - TIME)) * 0.5 + 0.5;
		base = mix(vec3(0.16, 0.13, 0.24), vec3(0.32, 0.26, 0.42), sw * 0.6);
	}
	vec3 col;
	if (!FRONT_FACING) {
		// liquid surface (seen through the open top)
		vec3 top = colors[nseg - 1].rgb;
		if (hidden[nseg - 1] > 0.5) top = vec3(0.3, 0.25, 0.4);
		col = mix(top, vec3(1.0), 0.22);
		float ring = smoothstep(0.0, 1.0, sin(length(rel.xz) * 30.0 - TIME * 2.0) * 0.5 + 0.5);
		col += ring * 0.05;
	} else {
		float ndv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
		col = base * (0.86 + 0.2 * t);
		col *= 0.62 + 0.38 * pow(ndv, 0.7);
		// soft rim light and a vertical specular stripe
		col += base * pow(1.0 - ndv, 3.0) * 0.5;
		float nx = NORMAL.x;
		float s1 = smoothstep(-0.78, -0.6, nx) * (1.0 - smoothstep(-0.48, -0.3, nx));
		col += vec3(1.0) * s1 * 0.22;
		// boundary between layers + meniscus highlight at the very top
		if (k > 0 && h - lo < 0.018) col *= 0.82;
		if (bounds[nseg] - h < 0.025) col = mix(col, vec3(1.0), 0.35);
		// tiny rising bubbles
		vec2 cell = floor(vec2(atan(rel.z, rel.x) * 5.0, (rel.y - TIME * 0.35) * 9.0));
		vec2 f = fract(vec2(atan(rel.z, rel.x) * 5.0, (rel.y - TIME * 0.35) * 9.0)) - 0.5;
		float b = step(0.93, hash(cell)) * (1.0 - smoothstep(0.08, 0.16, length(f)));
		col += vec3(b) * 0.25 * (hid ? 0.3 : 1.0);
	}
	col += base * glow * 0.6 + vec3(flash);
	ALBEDO = col;
}
