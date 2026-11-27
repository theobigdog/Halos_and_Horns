# Finer materials for the built structures and props (walls, buildings, furniture, dungeon pieces,
# roads, cars...): more refined surfaces than the flat KayKit colours. (Ted, Nov 24.) Models.instance()
# calls apply() on every model that NatureLook.is_nature() doesn't claim.
#
# Every KayKit model has one material: a small atlas of flat colour cells. We swap it (per surface, as an
# override: meshes, shapes and sizes untouched) for a shader that keeps the atlas colour and adds fine
# detail suited to what the colour is on that kind of model: stone courses and per-block tone on masonry,
# painted brick on city facades, wood grain on browns, brushed metal on kitchen steel, clear-coated paint
# on cars, asphalt grit on roads, weave on soft furnishings, reflective glass on windows. Detail is drawn
# in the model's own space (metres), so it sticks to a prop that gets knocked about and every copy of a
# model looks the same (demons disguised as a prop look exactly like the real one). One material per
# atlas texture and model family, shared by every copy. Low graphics keeps the original materials.
extends RefCounted

const WoodGrain = preload("res://scripts/wood_grain.gd")

enum { GENERIC, MASONRY, BUILDING, WOOD, METAL, ROAD, CAR, FLOOR, FABRIC, LIT, TILE }

const SHADER := """
shader_type spatial;
render_mode cull_back;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform int family = 0;
uniform float base_rough = 0.5;
uniform vec4 glass_rect = vec4(-1.0);   // the atlas cell holding window glass (x0, y0, x1, y1)
// (the same per-copy seed and look as the grime overlay on this model: Models._add_grime)
instance uniform float seed : instance_index(0) = 0.0;
instance uniform int look : instance_index(1) = 0;
global uniform float grime_amount;

varying vec3 lp;      // position in the model's own space, in metres
varying vec3 ln;      // normal in the model's own space
varying float win;    // city window panes (Models._mark_windows)
varying float my;     // height in the mesh's own units (unscaled)

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
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
	for (int i = 0; i < OCTAVES; i++) {
		v += a * noise3(p);
		p = p * 2.07 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}
vec3 hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
// Masonry: offset courses of blocks on a face. Returns (mortar 0..1, block id hash).
vec2 blocks(vec2 uv, vec2 size, float aa) {
	float row = floor(uv.y / size.y);
	uv.x += hash2(vec2(row, 3.0)) * size.x;
	vec2 cell = floor(uv / size);
	vec2 f = fract(uv / size) * size;
	float d = min(min(f.x, size.x - f.x), min(f.y, size.y - f.y));
	float m = 1.0 - smoothstep(0.006, 0.006 + max(aa, 0.012), d);
	return vec2(m, hash2(cell + row * 7.31));
}

// distance-ish to the nearest edge between random cells (2D): the crack network
float cell_edge2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++)
	for (int x = -1; x <= 1; x++) {
		vec2 g = vec2(float(x), float(y));
		vec2 o = vec2(hash2(i + g), hash2(i + g + 19.1));
		float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
	}
	return (d2 - d1) * 0.5;
}
// Cracks in a wall face (Ted, Nov 26: they looked like shading, and ran over windows and doors). p: the
// face's own coordinates in metres. Returns (the open crack, 0..1; its broken edges, 0..1). The lines are
// jagged at two scales, each one thickens, thins and stops along its length, and fine hairlines branch
// off near the main cracks. Widths are real (millimetres), with a pixel of softening, so they stay
// sharp up close and fade out at a distance instead of turning into grey smudges.
vec2 wall_cracks(vec2 p, float px) {
	vec2 w = p + vec2(fbm(vec3(p * 1.7, 1.0)), fbm(vec3(p * 1.7, 7.0))) * 0.5;
	w += vec2(noise3(vec3(p * 13.0, 3.0)), noise3(vec3(p * 13.0, 9.0))) * 0.035;
	float e = cell_edge2(w * 1.1) / 1.1;
	float along = fbm(vec3(p * 1.3, 21.0));
	float width = 0.007 * smoothstep(0.4, 0.6, along) * (0.6 + 0.8 * noise3(vec3(p * 4.0, 5.0)));
	float aa = px * 1.2;
	float core = 1.0 - smoothstep(width * 0.5, width * 0.5 + aa, e);
	core *= step(0.0005, width);
	float edge = (1.0 - smoothstep(width, width * 2.5 + 0.004 + aa, e)) * step(0.0005, width);
	// hairlines: a finer network, only within a hand's breadth of a main crack
	vec2 w2 = p * 3.4 + vec2(noise3(vec3(p * 20.0, 11.0)), noise3(vec3(p * 20.0, 17.0))) * 0.12 + 40.0;
	float e2 = cell_edge2(w2) / 3.4;
	float near_main = 1.0 - smoothstep(0.015, 0.07, e);
	float hw = 0.0009 * near_main * smoothstep(0.5, 0.72, noise3(vec3(p * 6.0, 2.0)));
	float hair = (1.0 - smoothstep(hw, hw + aa, e2)) * step(0.0002, hw);
	return vec2(max(core, hair * 0.7), edge);
}

void vertex() {
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	lp = VERTEX * s;
	ln = NORMAL;
	win = CUSTOM0.x;
	my = VERTEX.y;
}

void fragment() {
	vec3 c = texture(tex, UV).rgb;
	vec3 h = hsv(sqrt(c));                       // (judged by the colour as painted, not linear)
	vec3 n = normalize(ln);
	vec3 an = abs(n);
	// the face's own flat coordinates: across (u) and up (v); tops use x/z
	vec2 face = an.y > 0.7 ? lp.xz : vec2(an.x > an.z ? lp.z : lp.x, lp.y);
	float px = length(fwidth(lp));               // metres per pixel here
	float near = 1.0 - smoothstep(18.0, 45.0, length(VERTEX));
	float fine = near * (1.0 - smoothstep(0.004, 0.012, px));   // only where a few mm still show

	float grey = 1.0 - smoothstep(0.1, 0.2, h.y);
	float warm = smoothstep(0.015, 0.03, h.x) * (1.0 - smoothstep(0.11, 0.14, h.x));
	float wood = warm * smoothstep(0.28, 0.38, h.y) * (1.0 - smoothstep(0.8, 0.86, h.y)) * smoothstep(0.22, 0.32, h.z) * (1.0 - smoothstep(0.9, 0.98, h.z));
	// City facades: the KayKit city atlas is 8 x 4 colour cells, and a building's plain wall faces all sample
	// one texel column of a cell (28 or 60 px into it, the gradient running up the wall), so their UV.x is
	// constant across the face. Doors, shades, posters, frames, signs and awnings spread their UVs over the
	// cell (or sit at other columns), so brick goes only where all of this holds.
	float cell_x = fract(UV.x * 8.0) * 128.0;
	float wall_col = max(step(25.0, cell_x) * step(cell_x, 33.0), step(57.0, cell_x) * step(cell_x, 65.0));
	// (and the gradient is stretched over a whole storey: an awning's valance squeezes it into a hand's height)
	// (per KayKit unit, unscaled so stretched pieces judge alike: walls under 0.32, valances 0.63 and up)
	float v_rate = fwidth(UV.y) / max(fwidth(my), 1e-5);
	float wall = wall_col * (1.0 - step(2e-5, fwidth(UV.x))) * (1.0 - step(0.45, v_rate));
	float glass = max(step(0.5, win), (step(glass_rect.x, UV.x) * step(UV.x, glass_rect.z) * step(glass_rect.y, UV.y) * step(UV.y, glass_rect.w)));

	float height = 0.0;       // relief (metres-ish, for the bump)
	float tone = 1.0;         // albedo multiplier
	float rough = base_rough;
	float metal = 0.0;
	float spec = 0.5;
	float coat = 0.0;
	float rim = 0.12;
	float bump_k = 1.0;
	vec3 emit = vec3(0.0);

	float g1 = noise3(lp * 7.0);
	float mottle = fbm(lp * 3.0);
	tone *= 1.0 + (mottle - 0.5) * 0.08 * near;            // a little unevenness everywhere
	rough += (g1 - 0.5) * 0.12;

	if (family == 1 || family == 2) {
		// MASONRY / BUILDING
		if (family == 2 && wall > 0.5 && h.y > 0.22 && an.y < 0.5 && glass < 0.5) {
			// painted brick facade
			vec2 b = blocks(face, vec2(0.36, 0.13), px * 1.5);
			float m = b.x * near * (1.0 - smoothstep(0.01, 0.025, px));
			tone *= mix(1.0 + (b.y - 0.5) * 0.07, 0.84, m);
			height += -m * 0.006 + noise3(lp * 40.0) * 0.0012 * fine;
			rough = 0.82 + (b.y - 0.5) * 0.1;
			// cracks (the grime overlay leaves these walls to us: own_cracks), only on the plain wall, in
			// patches, on some buildings and not others, and never with the Clean look
			float some = step(0.4, fract(sin(seed * 91.37) * 4375.85)) * (look == 1 ? 0.0 : 1.0) * grime_amount;
			vec3 zp = lp * 2.2 + vec3(seed * 13.7, seed * 7.3, seed * 3.1);
			float zone = smoothstep(0.42, 0.62, fbm(zp * 0.35 + 40.0));
			if (some * zone > 0.01) {
				vec2 ck = wall_cracks(face + seed * 3.7, px) * some * zone;
				tone *= (1.0 - ck.x * 0.72) * (1.0 - ck.y * 0.14);
				height -= ck.x * 0.004 + ck.y * 0.0012;
				rough = mix(rough, 1.0, ck.x);
			}
		} else if (h.y < 0.3 && h.z > 0.86 && wood < 0.5) {
			// whitewash / plaster: soft trowel marks, no courses
			float trowel = fbm(lp * vec3(4.0, 9.0, 4.0));
			tone *= 1.0 + (trowel - 0.5) * 0.07 * near;
			height += trowel * 0.002 * near + noise3(lp * 60.0) * 0.0006 * fine;
			rough = 0.9;
		} else if (h.y < 0.3 && wood < 0.5) {
			// stone: ashlar courses with a tone per block, grain and pits
			vec2 b = blocks(face, an.y > 0.7 ? vec2(0.6, 0.45) : vec2(0.7, 0.34), px * 1.5);
			float course = family == 2 ? 0.0 : 1.0;
			float m = b.x * course * near * (1.0 - smoothstep(0.015, 0.035, px));
			tone *= 1.0 + (b.y - 0.5) * 0.1 * course;
			tone *= 1.0 - m * 0.13;
			float grain = noise3(lp * 26.0);
			float pits = smoothstep(0.72, 0.85, noise3(lp * 14.0 + 31.0));
			tone *= 1.0 - pits * 0.12 * fine;
			tone *= 1.0 + (grain - 0.5) * 0.07 * near;
			height += -m * 0.004 + grain * 0.0015 * fine - pits * 0.002 * fine;
			rough = 0.88 + (grain - 0.5) * 0.1;
		} else if (wood < 0.5 && glass < 0.5) {
			// painted boards and tiles (roofs, shutters): soft brush grain
			float g = fbm(lp * vec3(14.0, 1.2, 14.0));
			tone *= 1.0 + (g - 0.5) * 0.1 * near;
			height += g * 0.0012 * fine;
			rough = 0.6 + (g - 0.5) * 0.15;
		}
	} else if (family == 7 && wood < 0.5) {
		// FLOOR (flagstones and dirt are modelled): grain and pits only
		float grain = noise3(lp * 26.0);
		float pits = smoothstep(0.72, 0.85, noise3(lp * 14.0 + 31.0));
		tone *= (1.0 - pits * 0.12 * fine) * (1.0 + (grain - 0.5) * 0.08 * near);
		height += grain * 0.0015 * fine - pits * 0.002 * fine;
		rough = 0.88 + (grain - 0.5) * 0.1;
	} else if (family == 10) {
		// TILES (kitchen floors): small glazed tiles with grout lines
		vec2 t = fract(lp.xz / 0.25 + 0.5) - 0.5;
		float d = 0.5 - max(abs(t.x), abs(t.y));
		float grout = (1.0 - smoothstep(0.02, 0.02 + max(px * 6.0, 0.03), d)) * (an.y > 0.7 ? 1.0 : 0.0) * near;
		float tile = hash2(floor(lp.xz / 0.25 + 0.5));
		tone *= mix(1.0 + (tile - 0.5) * 0.05, 0.78, grout);
		height -= grout * 0.003;
		rough = mix(0.18 + tile * 0.1, 0.9, grout);
		spec = 0.6;
	}
	if (wood > 0.5 && glass < 0.5 && family != 2 && family != 6) {
		// wood: the shared grain (wood_grain.gd, the same as the buildings' boards and the hand-built
		// props: Ted, Nov 26), running up uprights and along x on tops
		vec2 gg = an.y > 0.7 ? lp.xz : vec2(lp.y, face.x);
		vec3 wg = wood_grain(gg, 0.45);
		tone *= mix(1.0, wg.x / 0.9, near);
		height += wg.y * fine;
		rough = wg.z;
	}
	if ((family == 0 || family == 3 || family == 8 || family == 9) && grey > 0.5 && h.z > 0.22 && h.z < 0.8 && glass < 0.5) {
		// iron fittings on props: bands, hinges, nails
		float hammered = noise3(lp * 22.0);
		metal = 0.5;
		rough = 0.42 + (hammered - 0.5) * 0.2;
		tone *= 1.0 + (hammered - 0.5) * 0.1 * near;
		height += hammered * 0.0015 * fine;
	}
	if (family == 4 || family == 6) {
		// METAL / CAR: greys are steel and chrome, brushed
		if (grey > 0.5 && glass < 0.5) {
			float dark = 1.0 - smoothstep(0.25, 0.4, h.z);
			vec2 bu = an.y > 0.7 ? lp.xz : face;
			float brush = noise3(vec3(bu.x * 3.0, bu.y * 160.0, 0.5));
			metal = mix(0.55, 0.0, dark);
			rough = mix(0.3 + brush * 0.16, 0.85, dark);     // (dark greys on cars: tyres and grilles)
			tone *= 1.0 + (brush - 0.5) * 0.08 * fine;
			spec = 0.6;
		}
	}
	if (family == 6 && grey < 0.5 && glass < 0.5) {
		// car paint: smooth with a clear coat and a faint metallic flake
		float flake = hash3(floor(lp * 900.0));
		rough = 0.26;
		coat = 1.0;
		metal = 0.25;
		spec = 0.6 + flake * 0.3 * fine;
		height = 0.0;
		tone = 1.0;
	}
	if (family == 5) {
		// ROAD: asphalt grit on the dark greys, concrete on light greys; painted lines a bit worn
		float grit = noise3(lp * 55.0);
		float stones = smoothstep(0.66, 0.8, noise3(lp * 30.0 + 7.0));
		if (h.z < 0.5 && grey > 0.5) {
			float agg = noise3(lp * 13.0 + 3.0);
			tone *= 1.0 + (grit - 0.5) * 0.22 * fine + stones * 0.12 * fine + (agg - 0.5) * 0.12 * near;
			tone *= 1.0 + (fbm(lp * 0.6) - 0.5) * 0.14 * near;   // patches of newer/older tarmac
			height += grit * 0.002 * fine;
			rough = 0.9;
		} else if (grey > 0.5) {
			tone *= 1.0 + (grit - 0.5) * 0.08 * fine;
			rough = 0.85;
		} else {
			float wear = smoothstep(0.55, 0.75, fbm(lp * 4.0));
			tone *= 1.0 - wear * 0.18;
			rough = 0.6;
		}
	}
	if (family == 8 && wood < 0.5 && glass < 0.5) {
		// fabric: a fine weave, soft sheen at grazing angles
		vec2 w = (an.y > 0.7 ? lp.xz : face) * 420.0;
		float weave = (sin(w.x) * 0.5 + 0.5) * (sin(w.y + step(0.0, sin(w.x * 0.5)) * 3.14159) * 0.5 + 0.5);
		float lump = noise3(lp * 18.0);
		tone *= 1.0 - (weave * 0.12 * fine) - (lump - 0.5) * 0.08 * near;
		height += weave * 0.0008 * fine + lump * 0.002 * near;
		rough = 0.95;
		rim = 0.35;
	}
	if (family == 0 || family == 9 || family == 3) {
		// everyday painted / plastic things: smooth with an orange-peel sheen; light greys are a bit metallic
		if (wood < 0.5 && grey < 0.5) {
			float peel = noise3(lp * 90.0);
			height += peel * 0.0004 * fine;
			rough = clamp(base_rough - 0.05 + (peel - 0.5) * 0.1, 0.25, 0.9);
		}
	}
	if (family == 9) {
		// lit things: flames and glowing insides
		float flame = smoothstep(0.75, 0.9, h.z) * smoothstep(0.45, 0.6, h.y) * step(0.05, h.x) * step(h.x, 0.18);
		emit = c * flame * 1.6;
	}
	if (glass > 0.5) {
		// glass: dark, glossy, reflecting the sky, with a couple of slanted glints
		float sl = fract((face.x + face.y * 0.7) * 0.9);
		float glint = smoothstep(0.0, 0.03, sl) * (1.0 - smoothstep(0.08, 0.11, sl)) + smoothstep(0.16, 0.18, sl) * (1.0 - smoothstep(0.2, 0.22, sl)) * 0.6;
		tone = 0.5 + glint * 0.35;
		rough = 0.04;
		metal = 0.35;
		spec = 1.0;
		height = 0.0;
		rim = 0.0;
	}

	ALBEDO = c * tone;
	ROUGHNESS = clamp(rough, 0.03, 1.0);
	METALLIC = metal;
	SPECULAR = spec;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = 0.08;
	RIM = rim;
	RIM_TINT = 0.6;
	EMISSION = emit;
#ifdef BUMP
	// bump from the relief, worked out on screen (no tangents needed)
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	float dhx = dFdx(height);
	float dhy = dFdy(height);
	vec3 r1 = cross(dpy, NORMAL);
	vec3 r2 = cross(NORMAL, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * 1.0 * bump_k);
#endif
}
"""

static var _shaders := {}      # "high"/"medium" -> Shader
static var _mats := {}         # "quality|texture|family" -> ShaderMaterial
static var _glass := {"citybits_texture": Vector4(0.0, 0.75, 0.25, 1.0), "restaurantbits_texture": Vector4(0.0, 0.75, 0.25, 1.0)}


static func _quality() -> int:
	var g = load("res://scripts/graphics.gd")   # (not preloaded: graphics.gd preloads models.gd, which preloads us)
	return int(g.quality)


static func family(id: String) -> int:
	var pack := id.get_slice("/", 0)
	var name := id.get_slice("/", 1)
	if name.ends_with("_lit") or name.contains("jackolantern") or name.contains("lantern") or name.contains("candles") \
			or name == "streetlight" or name == "skull_candle":
		return LIT
	if pack == "city":
		if name.begins_with("building"):
			return BUILDING
		if name.begins_with("car_"):
			return CAR
		if name.begins_with("road") or name == "base":
			return ROAD
		if name in ["dumpster", "trash_A", "trash_B", "streetlight", "watertower"] or name.begins_with("trafficlight"):
			return METAL
		return GENERIC
	for k in ["couch", "armchair", "bed_", "pillow", "rug_", "tablecloth", "banner", "tent", "flag_", "towel"]:
		if name.contains(k):
			return FABRIC
	if name.begins_with("floor") or name.begins_with("path_"):
		return TILE if pack == "restaurant" else FLOOR
	if pack == "restaurant":
		for k in ["fridge", "oven", "stove", "extractor", "pot_", "pan_", "lid", "dishrack", "towelrail", "knife",
				"kitchencounter", "kitchentable", "sink", "papertowel"]:
			if name.contains(k):
				return METAL
		if name.begins_with("wall") or name.begins_with("pillar"):
			return MASONRY
		return GENERIC
	if pack == "dungeon":
		for k in ["wall", "stairs", "pillar", "column", "barrier", "rubble"]:
			if name.begins_with(k):
				return FLOOR if name == "stairs_wood" or name == "stairs_wood_decorated" else MASONRY
		return WOOD
	if pack == "halloween":
		for k in ["grave", "crypt", "pillar", "arch", "shrine", "plaque", "fence_pillar"]:
			if name.begins_with(k):
				return MASONRY
		return WOOD if name.begins_with("fence") or name.begins_with("coffin") or name.begins_with("bench") or name.begins_with("post") else GENERIC
	if pack == "medieval":
		if name.begins_with("building") or name.begins_with("wall") or name.begins_with("fence_stone"):
			return MASONRY
		return WOOD
	if pack == "furniture":
		return WOOD
	return GENERIC


static func _shader(q: int) -> Shader:
	var key := "high" if q >= 2 else "medium"
	if not _shaders.has(key):
		var sh := Shader.new()
		sh.code = SHADER.replace("void fragment() {", WoodGrain.GLSL + "\nvoid fragment() {").replace("render_mode cull_back;", "render_mode cull_back;\n"
				+ ("#define BUMP\n#define OCTAVES 3" if q >= 2 else "#define OCTAVES 2"))
		_shaders[key] = sh
	return _shaders[key]


static func material_for(src: StandardMaterial3D, fam: int, q: int) -> ShaderMaterial:
	var tex := src.albedo_texture
	var tname := tex.resource_path.get_file().get_basename() if tex != null else ""
	var key := "%d|%s|%d" % [q, tex.resource_path if tex != null else "", fam]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = _shader(q)
		m.set_shader_parameter("tex", tex)
		m.set_shader_parameter("family", fam)
		m.set_shader_parameter("base_rough", src.roughness)
		m.set_shader_parameter("glass_rect", _glass.get(tname, Vector4(-1, -1, -1, -1)))
		_mats[key] = m
	return _mats[key]


static func apply(id: String, model: Node3D) -> void:
	var q := _quality()
	if q <= 0:
		return   # (Low: the original flat materials, cheapest)
	var name := id.get_slice("/", 1)
	if name.begins_with("tree"):
		return   # (trees can be turned green by Models._make_green, which needs the original material)
	var fam := family(id)
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si) as StandardMaterial3D
			if src == null or src.albedo_texture == null or src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			mi.set_surface_override_material(si, material_for(src, fam, q))
		if fam == BUILDING:
			mi.set_instance_shader_parameter("own_cracks", 1.0)   # (the grime overlay leaves cracks to us)
