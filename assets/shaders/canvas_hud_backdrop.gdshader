// W19-HUD v0.12 overlay backdrop (design/ux/hud-v0.12.md §2): re-draws the
// screen behind the HUD widgets desaturated, dimmed and softened. Death: grey
// at 45%; Tab / Armory: blurred and dimmed; match end: blurred, dimmed, muted.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
// 1 = full colour, 0 = greyscale.
uniform float saturation : hint_range(0.0, 1.0) = 1.0;
uniform float brightness : hint_range(0.0, 1.0) = 1.0;
// Mip level used as a cheap blur (0 = sharp).
uniform float blur_lod : hint_range(0.0, 5.0) = 0.0;

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(vec3(l), c, saturation) * brightness, 1.0);
}
