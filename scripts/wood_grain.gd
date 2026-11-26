# One wood grain for everything wooden (Ted, Nov 26: "if we're adding real wood-grain texture to this
# structure, we should probably make sure it's the same for all wooden structures and props"). The same
# GLSL goes into the walk-in buildings' boards and beams (hollow_buildings.gd), the KayKit structures and
# props (structure_look.gd), and is baked (tools/make_wood_texture.py, the same maths) into the texture the
# hand-built props' wood uses (surfaces.gd). Each board or beam starts at its own place in the grain, so no
# two look alike ("make the grain at least somewhat random, so all beams look a little different").
extends RefCounted

const TEXTURE := "res://assets/textures/wood_grain.png"
const NORMALS := "res://assets/textures/wood_grain_normal.png"
const TILE := Vector2(0.5, 5.0)   # the baked texture covers 0.5 m across the grain by 5 m along it

# Lattice frequencies are chosen so the baked texture tiles (every one times TILE is a whole number).
const GLSL := """
float wg_h(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}
float wg_n(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(wg_h(i), wg_h(i + vec2(1.0, 0.0)), f.x), mix(wg_h(i + vec2(0.0, 1.0)), wg_h(i + vec2(1.0, 1.0)), f.x), f.y);
}
// g: metres, x along the grain, y across it. age: 0 planed furniture .. 1 old, split timber.
// Returns (shade to multiply the colour by, bump height in metres, roughness).
vec3 wood_grain(vec2 g, float age) {
	float ring = wg_n(vec2(g.x * 0.8, g.y * 30.0)) * 0.6 + wg_n(vec2(g.x * 3.0, g.y * 90.0)) * 0.4;
	float split = (1.0 - smoothstep(0.0, 0.035, abs(wg_n(vec2(g.x * 0.6, g.y * 14.0)) - 0.5)))
			* step(0.55, wg_n(vec2(g.x * 0.4 + 7.0, g.y * 4.0))) * age;
	vec2 kc = vec2(g.x * 1.0, g.y * 6.0);
	vec2 kcell = floor(kc);
	vec2 kat = 0.5 + (vec2(wg_h(kcell + 3.1), wg_h(kcell + 8.7)) - 0.5) * 0.6;   // knots scattered, not on a grid
	float knot = (1.0 - smoothstep(0.05, 0.12, length(fract(kc) - kat))) * step(0.86, wg_h(kcell));
	float shade = (mix(0.8, 0.7, age) + mix(0.3, 0.42, age) * ring) * (1.0 - split * 0.6) * (1.0 - knot * 0.5)
			* (0.9 + 0.1 * wg_n(g * 2.0));
	return vec3(shade, ring * 0.0012 - split * 0.003 - knot * 0.001, mix(0.72, 0.92, age));
}
"""


# A starting point in the grain for one board or beam, from where it is (the same on every computer).
static func offset_for(p: Vector3) -> Vector2:
	var h := absf(sin(p.dot(Vector3(12.9898, 78.233, 37.719))) * 43758.5453)
	return Vector2(fmod(h, 1.0) * 40.0, fmod(h * 7.13, 1.0) * 3.0)
