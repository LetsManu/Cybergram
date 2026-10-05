// W18-LIFE: route sampling shared by the ambient mover / trail shaders.
// Mirrors TrafficPaths.sample(): one route per texture row, SAMPLES texels wide.
uniform sampler2D path_tex : filter_nearest, repeat_disable;
uniform int path_samples = 64;
uniform bool path_closed = true;

vec3 amb_path(float row, float u) {
	int r = int(row + 0.5);
	if (path_closed) {
		float f = fract(u) * float(path_samples);
		int i0 = int(floor(f)) % path_samples;
		int i1 = (i0 + 1) % path_samples;
		return mix(texelFetch(path_tex, ivec2(i0, r), 0).xyz, texelFetch(path_tex, ivec2(i1, r), 0).xyz, fract(f));
	}
	float g = clamp(u, 0.0, 1.0) * float(path_samples - 1);
	int j0 = min(int(floor(g)), path_samples - 2);
	return mix(texelFetch(path_tex, ivec2(j0, r), 0).xyz, texelFetch(path_tex, ivec2(j0 + 1, r), 0).xyz, g - float(j0));
}

// Orthonormal frame (right, up, fwd) along the route at u.
mat3 amb_frame(float row, float u) {
	vec3 a = amb_path(row, u - 0.002);
	vec3 b = amb_path(row, u + 0.002);
	vec3 fwd = b - a;
	fwd = length(fwd) > 1e-4 ? normalize(fwd) : vec3(0.0, 0.0, -1.0);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd) + vec3(1e-5, 0.0, 0.0));
	vec3 up = cross(fwd, right);
	return mat3(right, up, fwd);
}
