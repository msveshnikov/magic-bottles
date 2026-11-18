shader_type spatial;
// Painted backdrop on a camera-locked quad: slow drift, darker calm centre, vignette, cross-fade.
render_mode unshaded, depth_draw_never, cull_disabled;
uniform sampler2D tex_a : source_color, filter_linear_mipmap;
uniform sampler2D tex_b : source_color, filter_linear_mipmap;
uniform float mixv = 0.0;
uniform vec2 aspect_fit = vec2(1.0, 1.0);
uniform float center_dim = 0.28;
uniform float brightness = 1.0;
void fragment() {
	vec2 uv = (UV - 0.5) * aspect_fit * 0.96 + 0.5;
	uv += vec2(sin(TIME * 0.05), cos(TIME * 0.043)) * 0.012;
	vec3 a = texture(tex_a, uv).rgb;
	vec3 b = texture(tex_b, uv).rgb;
	vec3 c = mix(a, b, mixv);
	vec2 d = (UV - 0.5) * vec2(1.0, 1.0);
	float r = length(d * vec2(1.25, 0.9));
	c *= 1.0 - center_dim * (1.0 - smoothstep(0.05, 0.55, r));
	c *= 1.0 - 0.45 * smoothstep(0.45, 0.85, length(d) * 1.1);
	ALBEDO = c * brightness;
}
