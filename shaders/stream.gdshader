shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 color : source_color = vec4(1.0);
void fragment() {
	float ndv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float ripple = sin(UV.y * 60.0 - TIME * 28.0) * 0.5 + 0.5;
	vec3 c = color.rgb * (0.75 + 0.25 * ndv) + vec3(ripple * 0.08);
	c += vec3(1.0) * smoothstep(0.75, 0.95, ndv) * 0.25;
	ALBEDO = c;
}
