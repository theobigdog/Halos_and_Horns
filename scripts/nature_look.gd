# Finer materials for natural structures: hills, mountains, rocks, trees, bushes, grass, dirt...
# (Ted, Nov 24: "the grassy hill structures have comically poor graphics".) Models.instance() calls
# apply() on every structure/prop model for which is_nature() is true.
#
# How it works: the KayKit models are coloured from a small palette atlas (flat colour cells). Each
# surface gets a ShaderMaterial that reads the same atlas colour, works out what the colour IS (grass,
# soil, rock, bark, leaves...) from its hue, and paints procedural detail for it: grass gets patchy
# colour and blade streaks, soil gets strata, pebbles and roots, rock gets facets, cracks and lichen,
# bark gets grain, leaves get leafy clumps with a soft back-light and a rustling shimmer. Detail is in
# the model's own space (in metres), so it sticks to a prop that's knocked about and every copy of a
# model looks the same (a demon disguised as a rock looks exactly like the rock). Geometry is never
# moved (the grime overlay and snow pass are drawn over the same vertices). On Medium/High, grassy tops
# also get little tufts of grass blades (a MultiMesh, placed by a fixed seed per model id; not part of
# the collision shape). Low graphics gets a cheap version (colour finish only, no tufts).
extends RefCounted

# What a model is, which decides how its colours are read.
enum { TERRAIN, TREE, PINE, ROCK, FLOOR, PATH, BUSH, PLANT }

const SHADER := """
shader_type spatial;
render_mode cull_back;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform int kind = 0;
uniform bool green = false;
uniform mat4 to_obj = mat4(1.0);   // mesh space -> the model's own space in metres
global uniform float snow_cover;

varying vec3 lp;
varying vec3 ln;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}
// (Models.GREEN_SHADER's version, which keeps the full hue: used for the green pines so they match)
vec3 hsv2rgb_full(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * clamp(p - 1.0, 0.0, 1.0);
}
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * noise3(p);
		p = p * 2.07 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v / 0.875;
}
#ifndef LOW
// x: distance to the nearest random point, y: distance to the nearest edge, z: that cell's random value
vec3 cells(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int z = -1; z <= 1; z++)
	for (int y = -1; y <= 1; y++)
	for (int x = -1; x <= 1; x++) {
		vec3 g = vec3(float(x), float(y), float(z));
		vec3 o = vec3(hash3(i + g), hash3(i + g + 19.1), hash3(i + g + 47.7));
		float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; id = hash3(i + g + 3.3); } else if (d < d2) { d2 = d; }
	}
	return vec3(d1, d2 - d1, id);
}
#endif

void vertex() {
	lp = (to_obj * vec4(VERTEX, 1.0)).xyz;
	ln = normalize(mat3(to_obj) * NORMAL);
}

void fragment() {
	vec3 c = texture(tex, UV).rgb * tint.rgb;      // (linear)
	vec3 hl = rgb2hsv(c);                           // hue/sat/value of the linear colour (as Models.GREEN_SHADER)
	vec3 h = rgb2hsv(pow(c, vec3(1.0 / 2.2)));      // ... and of the colour as painted (sRGB): what's used to sort it
	float up = ln.y;
	vec3 p = lp;

	// ---- what is this colour? (weights; the atlas cells are flat, so these are near 0 or 1) ----
	float sat = smoothstep(0.3, 0.45, h.y);
	float grass = 0.0;    // grassy ground
	float leaf = 0.0;     // tree / bush leaves
	float soil = 0.0;     // dirt, earth
	float bark = 0.0;     // wood
	float rock = 0.0;     // stone
	float yel = smoothstep(0.1, 0.13, h.x) * (1.0 - smoothstep(0.27, 0.32, h.x)) * sat;     // olive / yellow-green
	float teal = smoothstep(0.27, 0.33, h.x) * (1.0 - smoothstep(0.55, 0.62, h.x)) * sat;   // green / blue-green
	float brown = (1.0 - smoothstep(0.1, 0.13, h.x)) * smoothstep(0.25, 0.4, h.y);          // red-brown / orange
	float grey = 1.0 - smoothstep(0.22, 0.35, h.y);
	if (kind == 0) {          // hills, mountains, dirt patches (may have trees on them)
		grass = yel;
		leaf = teal;
		bark = brown * smoothstep(0.64, 0.66, h.z);
		soil = brown * (1.0 - smoothstep(0.64, 0.66, h.z));
		rock = grey;
	} else if (kind == 1) {   // trees, stumps, logs
		leaf = max(teal, yel);
		bark = max(brown, grey * (1.0 - smoothstep(0.8, 0.9, h.z)));
	} else if (kind == 2) {   // halloween pines and dead trees: bright orange/yellow leaves, grey-brown bark
		float warm = max(1.0 - smoothstep(0.17, 0.22, h.x), smoothstep(0.93, 0.97, h.x));
		leaf = max(warm * smoothstep(0.42, 0.52, h.y) * smoothstep(0.3, 0.4, h.z), smoothstep(0.24, 0.3, h.x) * (1.0 - smoothstep(0.55, 0.62, h.x)) * sat);
		bark = (1.0 - leaf) * (1.0 - smoothstep(0.75, 0.85, h.z));
	} else if (kind == 3) {   // rocks
		rock = 1.0;
	} else if (kind == 4) {   // dirt floors (with the odd weeds)
		leaf = 0.0;
		grass = max(teal, yel);
		soil = 1.0 - grass;
	} else if (kind == 5) {   // stone paths
		rock = 1.0;
	} else if (kind == 6) {   // a bush (in a pot: the pot is left alone)
		leaf = max(teal, yel);
	} else {                  // water plants
		leaf = 1.0;
	}

	// The green pines: the same yellow/orange -> green mapping as Models.GREEN_SHADER
	if (green) {
		float gl = smoothstep(0.03, 0.07, hl.x) * (1.0 - smoothstep(0.2, 0.26, hl.x)) * smoothstep(0.35, 0.5, hl.y) * smoothstep(0.3, 0.45, hl.z);
		vec3 g = hsv2rgb_full(vec3(0.3 + (hl.x - 0.12) * 0.3, min(hl.y * 0.95, 0.85), hl.z * 0.62));
		c = mix(c, g, gl);
		h = rgb2hsv(pow(c, vec3(1.0 / 2.2)));
	}

	vec3 col = c;
	float rough = 0.85;
	float bump = 0.0;         // a height for the bumps
	float bump_k = 0.0;       // how strong
	float big = fbm(p * 0.35 + 3.0);
	float mid = fbm(p * 1.3 + 11.0);

	// ---- grass: lusher green, patches, blades ----
	if (grass > 0.01) {
		vec3 gh = h;
		if (kind == 0) {
			gh.x = mix(gh.x, 0.27, 0.7);            // olive -> a fresher green
			gh.y = gh.y * 0.72;
			gh.z = gh.z * 0.8;
		}
		vec3 g = lin(hsv2rgb(gh));
		vec3 dry = g * vec3(1.12, 1.06, 0.78);   // sunny, slightly dry patches
		vec3 lush = g * vec3(0.78, 0.92, 0.82);  // deep green patches
		g = mix(lush, dry, smoothstep(0.3, 0.75, big));
		g *= 0.9 + 0.2 * mid;
		float side = 1.0 - smoothstep(0.35, 0.75, abs(up));
#ifndef LOW
		// blades: fine streaks, upright on the sides and a soft fleck on the tops
		float st = smoothstep(0.5, 0.75, noise3(vec3(p.x * 22.0, p.y * 3.5, p.z * 22.0)));
		float st2 = smoothstep(0.55, 0.8, noise3(vec3(p.x * 40.0, p.y * 5.0, p.z * 40.0) + 9.0));
		float fl = noise3(p * vec3(30.0, 30.0, 30.0));
		float blades = mix(fl, 1.0 - st * 0.7 + st2 * 0.4, side);
		g *= 0.86 + 0.28 * blades;
		// darker and lighter clumps across the turf, so a big top isn't one flat colour
		float tuft = noise3(p * 3.0 + 50.0);
		g *= mix(1.0, 0.82 + 0.3 * smoothstep(0.25, 0.75, tuft), 1.0 - side);
		g = mix(g, g * vec3(1.25, 1.2, 0.85), smoothstep(0.78, 0.95, fl) * (1.0 - side) * 0.6);   // light tips
		float clover = smoothstep(0.82, 0.88, noise3(p * 7.0 + 31.0)) * (1.0 - side);
		g = mix(g, g * vec3(0.8, 1.05, 0.85), clover * 0.5);
		bump += blades * 0.5;
		bump_k += 0.6 * grass;
#endif
		g *= mix(1.0, 0.8, side);                // the turf's sides sit in shadow
		col = mix(col, g, grass);
		rough = mix(rough, 0.93, grass);
	}

	// ---- soil: richer brown, strata, pebbles, roots ----
	if (soil > 0.01) {
		vec3 sh = h;
		vec3 s;
		if (kind == 0) {
			sh.x = mix(sh.x, 0.065, 0.55);           // salmon -> earthy brown
			sh.y = sh.y * 0.85;
			sh.z = sh.z * 0.82;
			s = lin(hsv2rgb(sh));
		} else {
			s = c * vec3(1.0, 0.95, 0.88);           // the pale floors keep their tone, a touch warmer
		}
		float warp = fbm(p * vec3(0.8, 0.3, 0.8));
		float layer = sin(p.y * 9.0 + warp * 6.0) + 0.5 * sin(p.y * 23.0 + warp * 11.0);
		float band = smoothstep(-0.6, 1.0, layer);
		s *= 0.8 + 0.3 * band;
		s = mix(s, s * vec3(1.08, 1.0, 0.9), smoothstep(0.3, 0.9, sin(p.y * 4.0 + warp * 3.0)) * 0.6);   // a sandier layer
		s *= 0.88 + 0.24 * mid;
#ifndef LOW
		vec3 pc = cells(p * vec3(4.5, 6.0, 4.5));
		float pebble = (1.0 - smoothstep(0.16, 0.26, pc.x)) * step(0.6, pc.z);
		float pshade = fract(pc.z * 7.0);
		vec3 pcol = mix(s * vec3(0.55, 0.55, 0.58), mix(s, vec3(dot(s, vec3(0.33))), 0.6) * 1.35, pshade);
		pcol *= 0.85 + 0.3 * smoothstep(0.24, 0.0, pc.x);     // rounded: lighter in the middle
		s = mix(s, pcol, pebble * 0.85);
		// roots: thin dark wandering lines, mostly in the upper layers
		float r = abs(noise3(vec3(p.x * 6.0, p.y * 1.6, p.z * 6.0) + 17.0) - 0.5);
		float root = (1.0 - smoothstep(0.008, 0.022, r)) * smoothstep(0.55, 0.7, noise3(p * 1.2 + 4.0));
		s = mix(s, s * vec3(0.6, 0.5, 0.42), root * 0.6 * (1.0 - abs(up)));
		float crumb = noise3(p * 22.0);
		s *= 0.9 + 0.2 * crumb;
		bump += band * 0.4 + pebble * 0.6 + crumb * 0.5 - root * 0.3;
		bump_k += 0.9 * soil;
#endif
		col = mix(col, s, soil);
		rough = mix(rough, 0.97, soil);
	}

	// ---- rock: facets, cracks, lichen ----
	if (rock > 0.01) {
		vec3 r = c;
		r *= 0.9 + 0.2 * big;
		r = mix(r, r * vec3(1.04, 1.0, 0.94), mid * 0.6);   // a little warm/cool variation
#ifndef LOW
		vec3 fc = cells(p * (kind == 5 ? vec3(2.2) : vec3(0.9, 1.6, 0.9)));
		r *= 0.92 + 0.16 * fc.z;                            // facets: each chip a slightly different shade
		r *= 0.95 + 0.1 * smoothstep(0.0, 0.5, fc.x);        // ... gently domed
		// layered rock: soft horizontal bands, warped
		float strata = sin(p.y * 5.0 + fbm(p * vec3(0.6, 0.2, 0.6)) * 5.0);
		r *= 0.94 + 0.08 * strata;
		// the odd crack, only in some places
		float crack = (1.0 - smoothstep(0.01, 0.035, fc.y)) * smoothstep(0.55, 0.68, noise3(p * 0.7 + 8.0));
		if (kind == 5) {
			crack = 1.0 - smoothstep(0.03, 0.09, fc.y);      // the gaps between the path's stones
			r = mix(r, r * vec3(0.55, 0.68, 0.5), crack * 0.6);
		}
		r *= 1.0 - crack * 0.45;
		float grain = noise3(p * 18.0);
		r *= 0.93 + 0.14 * grain;
		// lichen and moss on the upward faces
		float lich = smoothstep(0.6, 0.72, fbm(p * 2.5 + 21.0)) * smoothstep(0.1, 0.6, up);
		float spot = smoothstep(0.8, 0.86, noise3(p * 24.0 + 5.0)) * smoothstep(-0.2, 0.4, up) * smoothstep(0.4, 0.6, noise3(p * 1.3));
		r = mix(r, lin(vec3(0.55, 0.63, 0.32)) * (0.7 + 0.5 * h.z), lich * 0.55);
		r = mix(r, lin(vec3(0.8, 0.74, 0.52)) * (0.8 + 0.4 * h.z), spot * 0.3);
		bump += fc.y * 1.5 + grain * 0.3 - crack;
		bump_k += 0.8 * rock;
		rough = mix(rough, 0.72 + 0.2 * grain, rock);
#else
		rough = mix(rough, 0.8, rock);
#endif
		col = mix(col, r, rock);
	}

	// ---- bark: vertical grain ----
	if (bark > 0.01) {
		vec3 b = c;
		if (kind == 0 || kind == 1) {
			vec3 bh = h;
			bh.x = mix(bh.x, 0.07, 0.4);
			bh.y *= 0.68;
			bh.z *= 0.8;
			b = lin(hsv2rgb(bh));
		}
		float upright = 1.0 - smoothstep(0.6, 0.85, abs(up));
		float gr = noise3(vec3(p.x * 30.0, p.y * 2.5, p.z * 30.0));
		float gr2 = noise3(vec3(p.x * 70.0, p.y * 5.0, p.z * 70.0));
		float rings = 0.5;
#ifndef LOW
		if (upright < 0.99) {   // cut ends: growth rings
			rings = 0.5 + 0.5 * sin(cells(vec3(p.x, 0.0, p.z) * 2.5).x * 70.0 + noise3(p * 6.0) * 2.0);
		}
#endif
		float g = mix(rings, gr * 0.7 + gr2 * 0.3, upright);
		b *= 0.78 + 0.34 * g;
		b *= 0.92 + 0.16 * mid;
		bump += g;
		bump_k += 0.7 * bark;
		col = mix(col, b, bark);
		rough = mix(rough, 0.9, bark);
	}

	// ---- leaves: clumps, depth, a soft back-light, rustling ----
	float lf = leaf;
	if (lf > 0.01) {
		vec3 l = c;
		if (kind == 0 || kind == 1 || kind == 6 || kind == 7 || green) {
			vec3 lh = h;
			lh.x = mix(lh.x, 0.36, green ? 0.55 : 0.35);
			lh.y *= green ? 0.72 : 0.82;
			lh.z *= green ? 0.78 : 1.0;
			l = lin(hsv2rgb(lh));
		}
		l *= 0.85 + 0.3 * big;
#ifndef LOW
		// soft clumps of foliage at two sizes, and fine needle/leaf strokes inside them
		float clump = smoothstep(0.3, 0.75, fbm(p * 3.2 + 7.0)) * 0.65 + smoothstep(0.35, 0.8, noise3(p * 9.0)) * 0.35;
		l *= 0.78 + 0.36 * clump;
		l = mix(l, l * vec3(1.12, 1.16, 0.88), smoothstep(0.55, 0.9, fbm(p * 1.4 + 2.0)) * 0.5);   // sunnier sprays
		float fine = noise3(vec3(p.x * 38.0, p.y * 12.0, p.z * 38.0));
		l *= 0.88 + 0.24 * fine;
		l *= 1.0 - smoothstep(0.72, 0.9, noise3(p * 14.0 + 40.0)) * 0.25;                        // little gaps
		// layered sprays of branches on the sloping sides: soft scalloped rows, darker under each row
		float slope = smoothstep(0.1, 0.4, up) * (1.0 - smoothstep(0.85, 0.98, up));
		float row = fract(p.y * 5.0 + noise3(vec3(p.x * 7.0, p.y * 2.0, p.z * 7.0)) * 0.9);
		l *= 1.0 - slope * (smoothstep(0.55, 1.0, row) * 0.17 - smoothstep(0.0, 0.25, row) * (1.0 - smoothstep(0.25, 0.5, row)) * 0.08);
		// rustling: a soft brightness that drifts through the leaves with the wind
		float wind = noise3(vec3(p.x * 1.5 - TIME * 0.9, p.y * 1.5, p.z * 1.5 + TIME * 0.4));
		l *= 0.95 + 0.12 * smoothstep(0.45, 0.85, wind) * (0.5 + clump);
		bump += clump * 1.2 + fine * 0.3;
		bump_k += 0.8 * lf;
#endif
		l *= mix(0.82, 1.08, smoothstep(-0.6, 0.8, up));     // lighter on top, darker underneath
		col = mix(col, l, lf);
		rough = mix(rough, 0.8, lf);
		BACKLIGHT = l * 0.45 * lf;
		RIM = 0.35 * lf;
		RIM_TINT = 0.6;
	}

	// soft cavity shading where the surface turns away from the sky
	col *= mix(0.88, 1.0, smoothstep(-0.9, 0.3, up));

#ifndef LOW
	// bumps from the detail heights (screen-space surface gradient)
	if (bump_k > 0.0) {
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		float dhx = dFdx(bump);
		float dhy = dFdy(bump);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
		vec3 nn = normalize(abs(det) * NORMAL - grad * 0.012 * min(bump_k, 1.0));
		if (abs(det) > 1e-9) {
			NORMAL = nn;
		}
	}
#endif
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
"""

# Grass tufts on the grassy tops (Medium and High).
const TUFT_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 base_col : source_color = vec4(0.3, 0.45, 0.15, 1.0);
global uniform float snow_cover;
varying float k;
varying vec3 tint;
void vertex() {
	k = COLOR.a;                                  // 0 at the root, 1 at the tip
	tint = COLOR.rgb;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.7 + w.x * 0.8 + w.z * 0.6) * 0.6 + sin(TIME * 3.1 + w.x * 2.3) * 0.25;
	VERTEX.xz += vec2(sway * 0.035, sway * 0.02) * k * k;
	VERTEX.y *= 1.0 - snow_cover * 0.5;           // flattened under snow
}
void fragment() {
	vec3 c = base_col.rgb * tint * mix(0.65, 1.35, k);
	c = mix(c, vec3(0.9, 0.93, 0.98), smoothstep(0.2, 0.9, snow_cover) * k);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
	BACKLIGHT = c * 0.4;
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
"""

static var _shaders := {}      # "full"/"low" -> Shader
static var _mats := {}         # key -> ShaderMaterial
static var _tufts := {}        # id -> MultiMesh (or null for none)
static var _tuft_mesh: ArrayMesh
static var _tuft_mats := {}    # colour -> ShaderMaterial
static var _images := {}       # texture -> Image


# Is this model one of the natural ones this file dresses up?
static func is_nature(id: String) -> bool:
	return _kind(id) >= 0


static func _kind(id: String) -> int:
	var pack := id.get_slice("/", 0)
	var name := id.get_slice("/", 1)
	match pack:
		"medieval":
			if name.begins_with("hill") or name.begins_with("mountain") or name == "building_dirt":
				return TERRAIN
			if name.begins_with("rock") or name == "resource_stone":
				return ROCK
			if name.begins_with("tree") or name == "resource_lumber":
				return TREE
			if name.begins_with("waterlily") or name.begins_with("waterplant"):
				return PLANT
		"halloween":
			if name.begins_with("tree_"):
				return PINE
			if name.begins_with("floor_dirt"):
				return FLOOR
			if name.begins_with("path_"):
				return PATH
		"dungeon":
			if name.begins_with("floor_dirt"):
				return FLOOR
		"city":
			if name == "bush":
				return BUSH
	return -1


# Dress up the model's meshes (model = the KayKit scene under the instance's holder). `extra` is the
# catalog entry's "extra" ("green": the green versions of the yellow pines, whose leaves must turn
# green: Models._make_green no longer runs for natural models).
static func apply(id: String, model: Node3D, extra: String) -> void:
	var kind := _kind(id)
	if kind < 0:
		return
	var q := _quality()
	var green := extra == "green"
	_globals()
	var e: Dictionary = load("res://scripts/models.gd").entry(id)
	var cat_scale := float(e.get("scale", 1.0))
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		if mi.mesh == null:
			continue
		var rel := Transform3D.IDENTITY.scaled(Vector3.ONE * cat_scale) * _rel(mi, model)
		for si in mi.mesh.get_surface_count():
			var src = mi.get_active_material(si)
			if not src is StandardMaterial3D:
				continue
			var sm: StandardMaterial3D = src
			var key := "%s|%s|%d|%d|%s|%d" % [id, mi.name, si, kind, green, 0 if q == 0 else 1]
			if not _mats.has(key):
				var m := ShaderMaterial.new()
				m.shader = _shader(q == 0)
				m.set_shader_parameter("tex", sm.albedo_texture)
				m.set_shader_parameter("tint", sm.albedo_color)
				m.set_shader_parameter("kind", kind)
				m.set_shader_parameter("green", green)
				m.set_shader_parameter("to_obj", Projection(rel))
				_mats[key] = m
			mi.set_surface_override_material(si, _mats[key])
	if q >= 1 and (kind == TERRAIN or kind == FLOOR):
		_add_tufts(id, model, cat_scale, q)


static func _quality() -> int:
	var g = load("res://scripts/graphics.gd")
	return int(g.quality)


# The snow_cover global (registered by Models.grime_material) is used by these shaders too.
static func _globals() -> void:
	load("res://scripts/models.gd").grime_material()


static func _shader(low: bool) -> Shader:
	var k := "low" if low else "full"
	if not _shaders.has(k):
		var sh := Shader.new()
		sh.code = SHADER.replace("render_mode cull_back;", "render_mode cull_back;\n#define LOW") if low else SHADER
		_shaders[k] = sh
	return _shaders[k]


# The mesh node's transform relative to the model's root (not counting the root's own transform).
static func _rel(n: Node, model: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while n != null and n != model:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _image(t: Texture2D) -> Image:
	if t == null:
		return null
	if not _images.has(t):
		var img := t.get_image()
		if img != null and img.is_compressed():
			img.decompress()
		_images[t] = img
	return _images[t]


static func _is_grass(c: Color, kind: int) -> bool:
	var h := c.h
	if c.s < 0.4:
		return false
	if kind == FLOOR:
		return h > 0.12 and h < 0.6
	return h > 0.11 and h < 0.29


# ---- grass tufts ----

static func _add_tufts(id: String, model: Node3D, cat_scale: float, q: int) -> void:
	var key := "%s@%d" % [id, q]
	if not _tufts.has(key):
		_tufts[key] = _build_tufts(id, model, cat_scale, q)
	var data = _tufts[key]
	if data == null:
		return
	var holder := model.get_parent()
	if holder == null:
		return
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "NatureTufts"
	mmi.set_meta("extra", true)
	mmi.multimesh = data[0]
	mmi.material_override = data[1]
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.transform = model.transform   # (the points are in the model's space, like the model's meshes)
	holder.add_child(mmi)


# Returns [MultiMesh, material] or null. Points are found on upward faces of grass colour, scattered by
# area with a fixed seed from the model id, so every copy is identical.
static func _build_tufts(id: String, model: Node3D, cat_scale: float, q: int):
	var pts := []      # [pos in model space, colour]
	var total := 0.0
	var tris := []
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		if mi.mesh == null:
			continue
		var rel := _rel(mi, model)
		var kind := _kind(id)
		for si in mi.mesh.get_surface_count():
			var src = mi.mesh.surface_get_material(si)   # (the model's own: apply() has overridden it by now)
			if not src is StandardMaterial3D:
				continue
			var img := _image((src as StandardMaterial3D).albedo_texture)
			if img == null:
				continue
			var arr := mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var uvs = arr[Mesh.ARRAY_TEX_UV]
			var idx = arr[Mesh.ARRAY_INDEX]
			if uvs == null:
				continue
			var n_tri: int = (idx.size() if idx != null else verts.size()) / 3
			for t in n_tri:
				var ia: int = idx[t * 3] if idx != null else t * 3
				var ib: int = idx[t * 3 + 1] if idx != null else t * 3 + 1
				var ic: int = idx[t * 3 + 2] if idx != null else t * 3 + 2
				var a := rel * verts[ia]
				var b := rel * verts[ib]
				var cc := rel * verts[ic]
				var cr := (b - a).cross(cc - a)
				var area := cr.length() * 0.5
				if area < 0.0000001:
					continue
				var nrm := cr.normalized()
				# winding: glTF is counter-clockwise; check against the stored normal
				var nr = arr[Mesh.ARRAY_NORMAL]
				if nr != null and nrm.dot(rel.basis * (nr[ia] as Vector3)) < 0.0:
					nrm = -nrm
				if nrm.y < 0.8:
					continue
				var uv: Vector2 = (uvs[ia] + uvs[ib] + uvs[ic]) / 3.0
				var px := Vector2i(clampi(int(fposmod(uv.x, 1.0) * img.get_width()), 0, img.get_width() - 1),
						clampi(int(fposmod(uv.y, 1.0) * img.get_height()), 0, img.get_height() - 1))
				var col := img.get_pixelv(px)
				if not _is_grass(col, kind):
					continue
				tris.append([a, b, cc, col])
				total += area
	if tris.is_empty():
		return null
	# areas are in the model's space: the catalog scale turns them into metres
	var ms := cat_scale
	var density := 12.0 if q >= 2 else 5.0        # tufts per square metre
	var count := clampi(int(total * ms * ms * density), 0, 450 if q >= 2 else 180)
	if count < 3:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	# cumulative areas for picking triangles by area
	var cum := PackedFloat32Array()
	var acc := 0.0
	for t in tris:
		var tt: Array = t
		acc += ((tt[1] - tt[0]) as Vector3).cross(tt[2] - tt[0]).length() * 0.5
		cum.append(acc)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _tuft()
	mm.instance_count = count
	var avg := Color(0, 0, 0)
	for i in count:
		var r := rng.randf() * acc
		var lo := 0
		var hi := cum.size() - 1
		while lo < hi:
			var mid := (lo + hi) / 2
			if cum[mid] < r:
				lo = mid + 1
			else:
				hi = mid
		var t: Array = tris[lo]
		var u := rng.randf()
		var v := rng.randf()
		if u + v > 1.0:
			u = 1.0 - u
			v = 1.0 - v
		var pos: Vector3 = t[0] + (t[1] - t[0]) * u + (t[2] - t[0]) * v
		var s := rng.randf_range(0.7, 1.3) / ms     # (undo the model's scale: tufts are in metres)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
		mm.set_instance_transform(i, Transform3D(basis, pos))
		var shade := rng.randf_range(0.8, 1.15)
		mm.set_instance_color(i, Color(shade * rng.randf_range(0.95, 1.08), shade, shade * rng.randf_range(0.85, 1.0), 1.0))
		avg += t[3]
	avg /= float(count)
	# the same colour shift as the shader's grass (olive -> fresher green)
	var gc := Color.from_hsv(lerpf(avg.h, 0.27, 0.7), avg.s * 0.72, avg.v * 0.8) if _kind(id) == TERRAIN else avg
	var ck := gc.to_html(false)
	if not _tuft_mats.has(ck):
		var sh := Shader.new()
		sh.code = TUFT_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh if _tuft_mats.is_empty() else (_tuft_mats.values()[0] as ShaderMaterial).shader
		m.set_shader_parameter("base_col", gc)
		_tuft_mats[ck] = m
	return [mm, _tuft_mats[ck]]


# One tuft: five thin tapered blades leaning out from a point, about 16 cm tall.
static func _tuft() -> ArrayMesh:
	if _tuft_mesh != null:
		return _tuft_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261124
	for i in 5:
		var a := TAU * float(i) / 5.0 + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var hgt := rng.randf_range(0.16, 0.28)
		var lean := rng.randf_range(0.04, 0.1)
		var w := 0.022
		var root := dir * 0.015
		var midp := root + dir * lean * 0.4 + Vector3(0, hgt * 0.55, 0)
		var tip := root + dir * lean + Vector3(0, hgt, 0)
		var n := (dir + Vector3.UP * 0.6).normalized()
		var c0 := Color(1, 1, 1, 0.0)
		var c1 := Color(1, 1, 1, 0.55)
		var c2 := Color(1, 1, 1, 1.0)
		for tri in [[root - side * w, c0, root + side * w, c0, midp + side * w * 0.6, c1],
				[root - side * w, c0, midp + side * w * 0.6, c1, midp - side * w * 0.6, c1],
				[midp - side * w * 0.6, c1, midp + side * w * 0.6, c1, tip, c2]]:
			for k in 3:
				st.set_normal(n)
				st.set_color(tri[k * 2 + 1])
				st.add_vertex(tri[k * 2])
	_tuft_mesh = st.commit()
	return _tuft_mesh
