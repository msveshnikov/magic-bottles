shader_type spatial;
// Additive soft particle (sparkles, fireflies, droplets glow).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform float star = 0.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d) * 2.0;
	float core = exp(-r * r * 6.0);
	float rays = 0.0;
	if (star > 0.5) {
		rays = (exp(-abs(d.x) * 60.0) + exp(-abs(d.y) * 60.0)) * (1.0 - smoothstep(0.0, 0.5, length(d)));
	}
	float a = clamp(core + rays * 0.8, 0.0, 1.0) * COLOR.a;
	ALBEDO = COLOR.rgb * a * 1.5;
}
