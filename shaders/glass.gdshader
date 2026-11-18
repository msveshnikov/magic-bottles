shader_type spatial;
// Stylised glass: fresnel edge, two specular stripes, gold rim when selected. Unshaded so it looks
// the same on every renderer.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 tint : source_color = vec4(0.82, 0.92, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.82, 0.3, 1.0);
uniform float select_glow = 0.0;
uniform float hint_glow = 0.0;
uniform float base_alpha = 0.07;

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 2.2);
	vec3 col = mix(tint.rgb * 0.55, vec3(1.0), fres * 0.65);
	float a = base_alpha + fres * 0.5;
	float nx = NORMAL.x;
	float s1 = smoothstep(-0.82, -0.66, nx) * (1.0 - smoothstep(-0.56, -0.40, nx));
	float s2 = smoothstep(0.42, 0.50, nx) * (1.0 - smoothstep(0.54, 0.62, nx));
	float s3 = smoothstep(0.86, 0.95, NORMAL.y);
	col += vec3(1.0) * (s1 * 0.9 + s2 * 0.35 + s3 * 0.3);
	a += s1 * 0.42 + s2 * 0.14 + s3 * 0.2;
	if (!FRONT_FACING) {
		a *= 0.35;
	}
	vec3 g = mix(glow_color.rgb, vec3(0.45, 0.85, 1.0), step(0.01, hint_glow) * (1.0 - step(0.01, select_glow)));
	float gl = max(select_glow, hint_glow);
	col = mix(col, g * 1.6, gl * clamp(fres * 1.6, 0.0, 1.0));
	a = clamp(a + gl * fres * 0.7, 0.0, 1.0);
	ALBEDO = col;
	ALPHA = a;
}
