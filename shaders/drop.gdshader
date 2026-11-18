shader_type spatial;
// Opaque-looking liquid droplet billboard (splashes), alpha-blended.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d) * 2.0;
	float a = 1.0 - smoothstep(0.75, 1.0, r);
	vec3 c = COLOR.rgb * (0.85 + 0.3 * (1.0 - r)) + vec3(1.0) * smoothstep(0.35, 0.0, length(d + vec2(0.15, 0.15))) * 0.5;
	ALBEDO = c;
	ALPHA = a * COLOR.a;
}
