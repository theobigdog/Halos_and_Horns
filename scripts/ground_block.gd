# Rectangular ground blocks for map floors: grass, dirt, gravel, landscaping (mulch bed), flowerbed, sand.
# (Ted's wife, Nov 25: "Can I have rectangular grass structure blocks floor options".)
#
# make(kind, size) builds a box of `size` (x width, y thickness, z depth) standing on y = 0 with a
# slightly rounded top edge, plus a StaticBody3D with a BoxShape3D covering exactly the box.
# How it looks: one shared shader (one ShaderMaterial per kind, made once) paints the top in world-space
# metres, so blocks of any size never stretch and neighbouring blocks line up; the sides show soil layers
# (topsoil, subsoil, clay, stones) measured down from the top, with the top material lipping over the
# edge. Small extras are MultiMeshes placed with a seed from the kind and size (identical blocks look
# identical, nothing random at run time): grass tufts, soil clods, a few bigger stones, an edging of
# stones or timber boards, shrubs and flowers. Low graphics: a cheaper shader and no small extras
# (edgings, shrubs and flowers stay, since they are what the bed is).
extends RefCounted

const Surfaces = preload("res://scripts/surfaces.gd")
const NatureLook = preload("res://scripts/nature_look.gd")

const KINDS := {
	"grass": "Grass",
	"dirt": "Dirt",
	"gravel": "Gravel",
	"landscaping": "Landscaping (mulch bed)",
	"flowerbed": "Flowerbed",
	"sand": "Sand",
	"parking": "Parking lot",
	# Ted's wife, Nov 27: single spots (an accessible one too), and plain road surfaces with no markings
	"parking_spot": "Parking spot",
	"parking_accessible": "Accessible parking spot",
	"asphalt": "Plain asphalt",
	"concrete": "Plain concrete",
	# Ted, Nov 28: paving that covers any area without stretching (Sara had stretched and repeated a dungeon floor
	# tile under a whole town), a real concrete sidewalk with a joint between every slab, and edgings to line
	# things with. NEW KINDS GO AT THE END: a map stores a block's kind as its place in this list ("look").
	"paving": "Paving: flagstones",
	"crazy": "Paving: crazy paving",
	"cobbles": "Paving: cobblestones",
	"pavers": "Paving: brick pavers",
	"sidewalk": "Sidewalk (concrete slabs)",
	"edge_rocks": "Edging: rocks",
	"edge_fence": "Edging: little picket fence",
	"edge_logs": "Edging: log roll",
	"edge_ceramic": "Edging: glazed ceramic scallops",
	"edge_brick": "Edging: bricks on the slant",
	"edge_stone": "Edging: cut stone kerb",
	"edge_hedge": "Edging: low box hedge",
}
const STREET_KINDS := ["parking", "parking_spot", "parking_accessible", "asphalt", "concrete", "paving", "crazy",
		"cobbles", "pavers", "sidewalk"]   # (Street/Road too)
const PAVINGS := ["paving", "crazy", "cobbles", "pavers"]
# Edgings: a thin line of rocks, pickets, tiles... along the block's longer side. "size" is still x, y, z: the
# longer of x and z is the run, the shorter how thick it is, y how tall. No slab under them. Their colour is
# REPLACED by the block's colour when it has one (white: as they come), so a rock edging can be white marble
# and the ceramic one any glaze.
const EDGINGS := ["edge_rocks", "edge_fence", "edge_logs", "edge_ceramic", "edge_brick", "edge_stone", "edge_hedge"]
const EDGE_COLORS := {"edge_rocks": Color(0.56, 0.54, 0.5), "edge_fence": Color(0.66, 0.5, 0.33), "edge_logs": Color(0.74, 0.58, 0.39),
		"edge_ceramic": Color(0.74, 0.33, 0.2), "edge_brick": Color(0.62, 0.3, 0.22), "edge_stone": Color(0.6, 0.6, 0.58),
		"edge_hedge": Color(0.2, 0.42, 0.16)}
const _KIND_ID := {"grass": 0, "dirt": 1, "gravel": 2, "landscaping": 3, "flowerbed": 4, "sand": 5, "parking": 6,
		"parking_spot": 7, "parking_accessible": 8, "asphalt": 9, "concrete": 10, "paving": 11, "crazy": 12, "cobbles": 13,
		"pavers": 14, "sidewalk": 15}
const END_MARGIN := 0.5   # a lot's plain asphalt past the first and last stalls (Ted's wife, Nov 27)
# Default sizes for new pieces of these kinds
const DEFAULT_SIZES := {"parking": Vector3(STALL_W * 5 + END_MARGIN * 2, 0.1, 5.2), "parking_spot": Vector3(STALL_W, 0.1, 5.2),
		"parking_accessible": Vector3(4.2, 0.1, 5.2), "asphalt": Vector3(6, 0.1, 6), "concrete": Vector3(4, 0.12, 4),
		"paving": Vector3(3, 0.1, 3), "crazy": Vector3(3, 0.1, 3), "cobbles": Vector3(3, 0.1, 3), "pavers": Vector3(3, 0.1, 3),
		"sidewalk": Vector3(1.5, 0.15, 1.5),   # one slab: pull a tab to run it on, swing sideways to turn a corner
		"edge_rocks": Vector3(2, 0.14, 0.2), "edge_fence": Vector3(2, 0.3, 0.1), "edge_logs": Vector3(2, 0.22, 0.1),
		"edge_ceramic": Vector3(2, 0.2, 0.1), "edge_brick": Vector3(2, 0.12, 0.12), "edge_stone": Vector3(2, 0.14, 0.15),
		"edge_hedge": Vector3(2, 0.38, 0.32)}


# What Creative calls it: "Grass block", but "Sidewalk (concrete slabs)" and "Edging: rocks" as they are.
static func label(kind: String) -> String:
	var name: String = KINDS.get(kind, "Grass")
	return name if kind in PAVINGS or kind in EDGINGS or kind == "sidewalk" else name + " block"
# Parking lots (Ted's wife, Nov 26: "a parking lot or parking spaces that are tilable"): asphalt with painted
# stalls 2.6 m wide and 5 m deep, measured from the block's own back-left corner, so blocks set side by side
# (or back to back) carry on the same pattern. A block 10.5 m deep or more gets a row of stalls along each side
# with the aisle between. Each stall has a concrete wheel stop.
const STALL_W := 2.6
const STALL_D := 5.0

const SHADER := """
shader_type spatial;
render_mode cull_back;

uniform int kind = 0;
instance uniform vec3 bsize = vec3(4.0, 0.3, 4.0);   // the block's size (parking: where the stalls go)
instance uniform vec3 tint = vec3(1.0);              // Creative's colour for the block (white: as it comes)
global uniform float snow_cover;

varying vec3 wp;      // world position (metres)
varying vec3 lp;      // the same, turned the block's way (not shifted): paving runs square to its block, and
                      // blocks turned the same way carry one pattern across the join
varying vec3 op;      // object position (metres: the mesh is built at full size)
varying vec3 on;      // object normal
varying float across; // coordinate across the block's long axis (furrows run along it)
varying float dep;    // depth below the top surface (metres)

vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
float h2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1.0, 0.0)), f.x), mix(h2(i + vec2(0.0, 1.0)), h2(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	return (n2(p) * 0.5 + n2(p * 2.03 + vec2(5.2, 1.3)) * 0.25 + n2(p * 4.1 + vec2(1.7, 9.2)) * 0.125) / 0.875;
}
// x: distance to the nearest point, y: distance to the nearest cell edge, z: the cell's random value
vec3 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++)
	for (int x = -1; x <= 1; x++) {
		vec2 g = vec2(float(x), float(y));
		vec2 o = vec2(h2(i + g), h2(i + g + 19.1)) * 0.8 + 0.1;
		float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; id = h2(i + g + 3.3); } else if (d < d2) { d2 = d; }
	}
	return vec3(d1, d2 - d1, id);
}

// ---- top surfaces: colour (linear) and a small height for the bump ----
void grass_top(vec2 p, out vec3 c, out float h) {
	float pat = fbm(p * 0.45);
	c = mix(lin(vec3(0.22, 0.42, 0.13)), lin(vec3(0.36, 0.58, 0.19)), smoothstep(0.3, 0.72, pat));
	c = mix(c, lin(vec3(0.52, 0.6, 0.25)), smoothstep(0.6, 0.85, fbm(p * 0.2 + 7.0)) * 0.5);
	// blades: a fine stipple of light and dark blade tips
	float bl = h2(floor(p * 55.0)) * 0.5 + h2(floor(p * 23.0 + 0.5)) * 0.3 + n2(p * 9.0) * 0.2;
	c *= 0.8 + 0.38 * bl;
	h = bl * 0.004;
#ifndef LOW
	vec3 k = cells(p * 2.6 + 11.0);         // clover clumps and tiny flowers
	float clump = smoothstep(0.42, 0.2, k.x) * step(0.72, k.z) * step(k.z, 0.9);
	c = mix(c, lin(vec3(0.30, 0.55, 0.20)) * (0.85 + 0.3 * bl), clump * 0.55);
	if (k.z > 0.94) {
		float r = smoothstep(0.075, 0.045, k.x);
		vec3 fc = k.z > 0.975 ? lin(vec3(1.0, 0.88, 0.35)) : lin(vec3(0.97, 0.96, 1.0));
		c = mix(c, fc, r);
		h += r * 0.004;
	}
#endif
}

void soil_top(vec2 p, float ac, out vec3 c, out float h, bool furrows) {
	float big = fbm(p * 0.6);
	c = mix(lin(vec3(0.33, 0.22, 0.14)), lin(vec3(0.46, 0.32, 0.21)), smoothstep(0.3, 0.75, big));
	h = 0.0;
	if (furrows) {
		float wob = (n2(p * 1.3) - 0.5) * 0.12;
		float r = 0.5 + 0.5 * cos((ac + wob) * 6.2832 / 0.42);     // ridges every 42 cm
		h += r * 0.05;
		c *= mix(0.6, 1.15, r);                                // damp dark troughs, dry ridge tops
	}
#ifndef LOW
	vec3 k = cells(p * 9.0);                                   // clods: rounded lumps
	float clod = smoothstep(0.75, 0.15, k.x) * step(0.35, k.z);
	h += clod * (0.008 + 0.01 * k.z);
	c *= 0.8 + 0.3 * clod;
	vec3 k2 = cells(p * 30.0 + 5.0);                           // crumbs
	float cr = smoothstep(0.6, 0.1, k2.x);
	c *= 0.84 + 0.22 * cr;
	h += cr * 0.003;
	// a few pale pebbles
	if (k2.z > 0.97) { float pb = smoothstep(0.3, 0.2, k2.x); c = mix(c, lin(vec3(0.52, 0.47, 0.4)), pb); h += pb * 0.004; }
#else
	c *= 0.82 + 0.3 * n2(p * 14.0);
#endif
}

void gravel_top(vec2 p, out vec3 c, out float h) {
#ifndef LOW
	vec3 k = cells(p * 17.0);
	vec3 k2 = cells(p * 37.0 + 3.7);
	float in1 = smoothstep(0.0, 0.1, k.y) * smoothstep(0.62, 0.4, k.x);
	float in2 = smoothstep(0.0, 0.14, k2.y) * smoothstep(0.65, 0.35, k2.x);
	vec3 pc = mix(lin(vec3(0.6, 0.6, 0.59)), lin(vec3(0.68, 0.63, 0.54)), smoothstep(0.35, 0.65, k.z));
	pc = mix(pc, lin(vec3(0.45, 0.45, 0.46)), step(0.82, k.z));
	pc = mix(pc, lin(vec3(0.82, 0.78, 0.7)), step(0.93, k.z));
	vec3 small = mix(lin(vec3(0.46, 0.45, 0.43)), lin(vec3(0.6, 0.56, 0.5)), k2.z) * (0.35 + 0.65 * in2);
	float dome = sqrt(in1);
	c = mix(small * 0.8, pc * (0.65 + 0.5 * (0.6 - k.x)), in1);
	h = dome * 0.012 + in2 * 0.004;
	c *= 0.9 + 0.2 * n2(p * 60.0);
#else
	float a = n2(p * 26.0);
	float b = n2(p * 61.0);
	c = mix(lin(vec3(0.42, 0.41, 0.39)), lin(vec3(0.7, 0.66, 0.58)), a * 0.6 + b * 0.4);
	h = 0.0;
#endif
}

void mulch_top(vec2 p, out vec3 c, out float h) {
	c = lin(vec3(0.24, 0.13, 0.08)) * (0.8 + 0.35 * fbm(p * 0.8));
	h = 0.0;
#ifndef LOW
	// two layers of wood chips: stretched cells at different angles
	vec2 q1 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p;
	vec2 q2 = mat2(vec2(0.3, -0.95), vec2(0.95, 0.3)) * p;
	vec3 a = cells(vec2(q1.x * 9.0, q1.y * 22.0));
	vec3 b = cells(vec2(q2.x * 10.0 + 4.0, q2.y * 24.0));
	float ia = smoothstep(0.0, 0.18, a.y);
	float ib = smoothstep(0.0, 0.18, b.y) * step(0.45, b.z);
	vec3 ca = mix(lin(vec3(0.24, 0.15, 0.1)), lin(vec3(0.4, 0.27, 0.17)), a.z);
	vec3 cb = mix(lin(vec3(0.3, 0.2, 0.12)), lin(vec3(0.47, 0.33, 0.21)), b.z);
	c = mix(c * 0.55, ca * (0.75 + 0.3 * ia), ia);
	c = mix(c, cb * (0.8 + 0.3 * ib), ib);
	h = ia * 0.006 + ib * 0.01;
	c *= 0.85 + 0.25 * n2(vec2(q1.x * 90.0, q1.y * 20.0));    // grain on the chips
#else
	c *= 0.75 + 0.45 * n2(vec2(p.x * 20.0, p.y * 45.0));
#endif
}

void bed_top(vec2 p, out vec3 c, out float h) {        // rich dark garden soil
	c = mix(lin(vec3(0.2, 0.13, 0.09)), lin(vec3(0.3, 0.2, 0.13)), fbm(p * 0.9));
	h = 0.0;
#ifndef LOW
	vec3 k = cells(p * 14.0);
	float cr = smoothstep(0.7, 0.15, k.x);
	c *= 0.75 + 0.35 * cr + 0.12 * k.z;
	h = cr * 0.006 * (0.5 + k.z);
	vec3 k2 = cells(p * 40.0 + 2.0);
	c *= 0.88 + 0.18 * smoothstep(0.6, 0.2, k2.x);
#else
	c *= 0.8 + 0.3 * n2(p * 20.0);
#endif
}

void sand_top(vec2 p, out vec3 c, out float h) {
	float w = fbm(p * 0.35) * 2.5;
	float rip = 0.5 + 0.5 * sin((p.x * 0.8 + p.y * 0.35 + w) * 6.2832 / 0.11);
	rip *= smoothstep(0.35, 0.7, fbm(p * 0.9 + 3.0));          // ripples only in patches
	c = mix(lin(vec3(0.82, 0.72, 0.5)), lin(vec3(0.92, 0.84, 0.63)), fbm(p * 0.7));
	c *= 0.96 + 0.06 * rip;
	h = rip * 0.004 + n2(p * 6.0) * 0.006;
	float g = h2(floor(p * 160.0));
	c *= 0.9 + 0.18 * g;
	c = mix(c, lin(vec3(0.5, 0.45, 0.4)), step(0.985, g) * 0.6);
}

// The road pieces' asphalt (KayKit City's road grey, sampled from its texture) and concrete.
vec3 asphalt_col(vec2 pw) {
	vec3 c = lin(vec3(0.435, 0.463, 0.482)) * (0.88 + 0.2 * fbm(pw * 0.4));
	float g = h2(floor(pw * 90.0));
	c *= 0.9 + 0.18 * g;                                                       // aggregate
	return mix(c, lin(vec3(0.55, 0.57, 0.58)), step(0.97, g) * 0.5);
}

// the white (or blue) stall paint; `w` is a line's half width
float stripe(float d, float w) { return 1.0 - smoothstep(w - 0.008, w + 0.008, d); }
float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// Parking (kinds 6, 7, 8), measured from the block's corner (object space, so it turns with the block):
//   6 a lot: stalls 2.6 m wide from 0.5 m in at each end, a row at the back (and one at the front too if
//     it's 10.5 m deep or more); 7 one spot: half a line on each side (two spots side by side make one line);
//   8 an accessible spot: a 2.6 m stall in blue, a wheelchair sign painted in it, and a striped access aisle.
void parking_top(out vec3 c, out float h) {
	vec2 q = op.xz + bsize.xz * 0.5;         // metres from the back-left corner
	vec2 pw = q + vec2(bsize.x * 0.37, bsize.z * 0.61) + op.y;
	c = asphalt_col(pw);
	h = n2(pw * 40.0) * 0.003;
#ifndef LOW
	vec3 k = cells(pw * 0.5);
	float crack = smoothstep(0.03, 0.0, k.y) * smoothstep(0.6, 0.8, fbm(pw * 0.8 + 7.0));
	c *= 1.0 - crack * 0.45;
#endif
	vec3 white = lin(vec3(0.9, 0.9, 0.86));
	vec3 blue = lin(vec3(0.08, 0.3, 0.72));
	float paint = 0.0;
	float bpaint = 0.0;
	float in_stall = 0.0;   // where oil drips (and the stall's middle)
	vec2 sc = vec2(0.0);
	if (kind == 6) {
		float m = 0.5;
		float n = floor((bsize.x - 2.0 * m) / 2.6 + 0.001);
		float rows = bsize.z >= 10.5 ? 2.0 : 1.0;
		bool in_row = q.y <= 5.0 || (rows > 1.5 && q.y >= bsize.z - 5.0);
		float x = q.x - m;
		float u = x - clamp(round(x / 2.6), 0.0, n) * 2.6;
		paint = in_row ? stripe(abs(u), 0.07) : 0.0;
		float stall = floor(x / 2.6);
		in_stall = (in_row && x > 0.0 && stall < n) ? 1.0 : 0.0;
		sc = vec2(m + (stall + 0.5) * 2.6, q.y < bsize.z * 0.5 ? 2.6 : bsize.z - 2.6);
	} else if (kind == 7) {
		bool in_row = q.y <= 5.0;
		paint = in_row ? max(stripe(q.x, 0.07), stripe(bsize.x - q.x, 0.07)) : 0.0;
		in_stall = in_row ? 1.0 : 0.0;
		sc = vec2(bsize.x * 0.5, 2.6);
	} else {
		// the stall (left 2.6 m), then the access aisle beside it, striped diagonally
		float sw = min(2.6, bsize.x);
		bool in_row = q.y <= 5.0;
		float edges = max(max(stripe(q.x, 0.07), stripe(abs(q.x - sw), 0.06)), stripe(bsize.x - q.x, 0.07));
		bpaint = in_row ? edges : 0.0;
		if (in_row && q.x > sw && q.x < bsize.x) {
			float hatch = stripe(abs(fract((q.x + q.y) / 0.6) - 0.5) * 0.6, 0.06);
			bpaint = max(bpaint, hatch * step(0.2, q.y) * step(q.y, 4.8) * step(sw + 0.15, q.x) * step(q.x, bsize.x - 0.15));
		}
		in_stall = (in_row && q.x < sw) ? 1.0 : 0.0;
		sc = vec2(sw * 0.5, 2.6);
		// the wheelchair sign, white on a blue square, in the middle of the stall
		if (in_row && q.x < sw) {
			vec2 p = (q - vec2(sw * 0.5, 3.1)) / 0.55;   // -1..1 over the square
			float sq = step(max(abs(p.x), abs(p.y)), 1.0);
			vec2 s = p * vec2(1.0, -1.0);
			float wheel = abs(length(s - vec2(-0.05, -0.25)) - 0.42);
			float fig = min(min(seg(s, vec2(-0.15, 0.55), vec2(-0.1, 0.0)), seg(s, vec2(-0.1, 0.0), vec2(0.35, 0.0))),
					min(seg(s, vec2(0.35, 0.0), vec2(0.45, -0.55)), seg(s, vec2(-0.12, 0.32), vec2(0.25, 0.3))));
			float head = length(s - vec2(-0.18, 0.78)) - 0.13;
			float sign_white = sq * max(max(stripe(wheel, 0.06), stripe(fig, 0.07)), step(head, 0.0));
			bpaint = max(bpaint, sq * (1.0 - sign_white));
			paint = max(paint, sign_white);
		}
	}
	// oil stains in the middle of some stalls
	float oil = smoothstep(0.9, 0.2, length((q - sc) * vec2(1.0, 0.6)) + fbm(q * 3.0) * 0.5)
			* step(0.45, h2(vec2(floor(sc.x / 2.6), sc.y)));
	c = mix(c, lin(vec3(0.12, 0.12, 0.13)), oil * 0.55 * in_stall);
	float worn = 0.55 + 0.45 * smoothstep(0.25, 0.55, fbm(pw * 2.5));
	c = mix(c, blue, bpaint * worn);
	c = mix(c, white, paint * worn);
	h += max(paint, bpaint) * 0.001;
}

// plain asphalt (9) and plain concrete (10): no markings at all
void plain_top(vec2 p, out vec3 c, out float h) {
	vec2 pw = op.xz + bsize.xz * 0.5 + vec2(bsize.x * 0.37, bsize.z * 0.61) + op.y;
	if (kind == 9) {
		c = asphalt_col(pw);
		h = n2(pw * 40.0) * 0.003;
	} else {
		c = lin(vec3(0.78, 0.78, 0.76)) * (0.9 + 0.12 * fbm(pw * 0.7)) * (0.96 + 0.06 * h2(floor(pw * 60.0)));
		h = n2(pw * 25.0) * 0.002;
	}
}

// ---- paving (kinds 11 to 14) and the sidewalk (15) ----
// One stone: `d` is how far in from its edge (metres), `rnd` its own random number, `jw` half the joint.
void stone(vec2 p, float d, float rnd, float jw, vec3 a, vec3 b, float dome, out vec3 c, out float h) {
	float in_s = smoothstep(jw, jw + 0.01, d);
	c = mix(a, b, fract(rnd * 7.3)) * (0.84 + 0.26 * rnd);
	c *= 0.9 + 0.16 * fbm(p * 3.5);
	c *= 0.95 + 0.09 * h2(floor(p * 80.0));
	c *= 0.86 + 0.14 * smoothstep(jw, jw + 0.06, d);          // dirt gathers along the edges
	vec3 joint = lin(vec3(0.27, 0.24, 0.2)) * (0.75 + 0.4 * n2(p * 40.0));
	c = mix(joint, c, in_s);
	h = in_s * (0.004 + dome * smoothstep(jw, jw + 0.05, d)) + in_s * n2(p * 22.0) * 0.0012;
}

// squared flagstones in courses 45 cm deep, each stone a different length
float flag_end(float i, float row) { return i * 0.62 + (h2(vec2(i, row)) - 0.5) * 0.3; }
void flag_top(vec2 p, out vec3 c, out float h) {
	float ch = 0.45;
	float row = floor(p.y / ch);
	float fy = p.y - row * ch;
	float x = p.x + h2(vec2(row, 7.0)) * 3.0;
	float i = floor(x / 0.62);
	float b0 = flag_end(i, row);
	float b1 = flag_end(i + 1.0, row);
	if (x < b0) { i -= 1.0; b1 = b0; b0 = flag_end(i, row); }
	else if (x > b1) { i += 1.0; b0 = b1; b1 = flag_end(i + 1.0, row); }
	float d = min(min(x - b0, b1 - x), min(fy, ch - fy));
	stone(p, d, h2(vec2(i, row) + 0.37), 0.008, lin(vec3(0.62, 0.6, 0.57)), lin(vec3(0.7, 0.64, 0.54)), 0.003, c, h);
}

// crazy paving: broken slabs fitted together
void crazy_top(vec2 p, out vec3 c, out float h) {
	vec3 k = cells(p * 1.9);
	stone(p, k.y * 0.26, k.z, 0.011, lin(vec3(0.6, 0.57, 0.52)), lin(vec3(0.72, 0.62, 0.5)), 0.003, c, h);
}

// cobblestones: small domed setts in rows, every row shifted along
void cobble_top(vec2 p, out vec3 c, out float h) {
	float rh = 0.105;
	float sl = 0.15;
	float row = floor(p.y / rh);
	float fy = p.y - row * rh;
	float x = p.x + (mod(row, 2.0) * 0.5 + (h2(vec2(row, 3.0)) - 0.5) * 0.3) * sl;
	float i = floor(x / sl);
	float fx = x - i * sl;
	vec2 q = abs(vec2(fx - sl * 0.5, fy - rh * 0.5)) - vec2(sl, rh) * 0.5 + 0.03;
	float d = 0.03 - (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0));     // in from a rounded rectangle
	stone(p, d, h2(vec2(i, row) + 0.61), 0.007, lin(vec3(0.42, 0.42, 0.43)), lin(vec3(0.55, 0.5, 0.45)), 0.012, c, h);
}

// brick pavers, herringbone: every brick two squares long, lying across the end of the last
void pavers_top(vec2 p, out vec3 c, out float h) {
	vec2 q = p / 0.105;
	vec2 o = floor(q);            // the brick's first square
	float m = mod(o.x - o.y, 4.0);
	vec2 sz = vec2(2.0, 1.0);
	if (m > 0.5 && m < 1.5) { o.x -= 1.0; }
	else if (m > 2.5) { sz = vec2(1.0, 2.0); }
	else if (m > 1.5) { o.y -= 1.0; sz = vec2(1.0, 2.0); }
	vec2 l = q - o;
	float d = min(min(l.x, sz.x - l.x), min(l.y, sz.y - l.y)) * 0.105;
	stone(p, d, h2(o + 0.23), 0.004, lin(vec3(0.64, 0.31, 0.22)), lin(vec3(0.5, 0.27, 0.2)), 0.0015, c, h);
}

// A concrete sidewalk, measured from the block's own corner: a tooled joint between slabs (spread evenly, as near
// 1.5 m as fits; a walk wider than about 2.7 m gets them lengthways too), a smooth trowelled margin beside every
// joint, a broom finish across the rest, the odd hairline crack and stain.
void sidewalk_top(out vec3 c, out float h) {
	vec2 q = op.xz + bsize.xz * 0.5;
	bool lx = bsize.x >= bsize.z;
	float len = lx ? bsize.x : bsize.z;
	float wid = lx ? bsize.z : bsize.x;
	float a = lx ? q.x : q.y;     // along the walk
	float b = lx ? q.y : q.x;     // across it
	float sa = len / max(1.0, floor(len / 1.5 + 0.5));
	float sb = wid / max(1.0, floor(wid / 1.8 + 0.5));
	float d = min(abs(a - floor(a / sa + 0.5) * sa), abs(b - floor(b / sb + 0.5) * sb));
	vec2 slab = vec2(floor(a / sa), floor(b / sb));
	float rnd = h2(slab + bsize.xz * 3.1);
	vec2 pw = q + vec2(bsize.x * 0.37, bsize.z * 0.61);
	c = lin(vec3(0.74, 0.735, 0.71)) * (0.93 + 0.1 * rnd) * (0.92 + 0.12 * fbm(pw * 0.9));
	float broom = n2(vec2(a * 260.0, b * 7.0));
	float margin = smoothstep(0.03, 0.045, d);
	c *= (1.0 + (broom - 0.5) * 0.1 * margin) * (0.95 + 0.05 * margin);
	float groove = 1.0 - smoothstep(0.004, 0.011, d);
	c = mix(c, lin(vec3(0.33, 0.33, 0.32)), groove * 0.85);
#ifndef LOW
	if (rnd > 0.72) {
		vec2 sp = vec2(a - slab.x * sa, b - slab.y * sb);
		float cr = abs(sp.x - sa * (0.3 + 0.4 * fract(rnd * 17.0)) - (n2(vec2(sp.y * 5.0, rnd * 40.0)) - 0.5) * 0.35);
		c *= 1.0 - 0.28 * (1.0 - smoothstep(0.0, 0.004, cr));
	}
	c = mix(c, c * vec3(0.8, 0.78, 0.74), smoothstep(0.62, 0.8, fbm(pw * 1.7 + 9.0)) * 0.6);
#endif
	h = -groove * 0.004 + (broom - 0.5) * 0.0012 * margin + smoothstep(0.0, 0.03, d) * 0.002;
}

void top_mat(vec2 p, float ac, out vec3 c, out float h) {
	if (kind == 0) grass_top(p, c, h);
	else if (kind == 1) soil_top(p, ac, c, h, true);
	else if (kind == 2) gravel_top(p, c, h);
	else if (kind == 3) mulch_top(p, c, h);
	else if (kind == 4) bed_top(p, c, h);
	else if (kind >= 6 && kind <= 8) parking_top(c, h);
	else if (kind == 9 || kind == 10) plain_top(p, c, h);
	else if (kind == 11) flag_top(p, c, h);
	else if (kind == 12) crazy_top(p, c, h);
	else if (kind == 13) cobble_top(p, c, h);
	else if (kind == 14) pavers_top(p, c, h);
	else if (kind == 15) sidewalk_top(c, h);
	else sand_top(p, c, h);
}

// ---- sides: layers going down from the top ----
void side_mat(vec2 s, out vec3 c, out float h) {      // s = (along the face, depth)
	float d = s.y + (fbm(vec2(s.x * 1.4, s.y * 2.0)) - 0.5) * 0.14;
	if (kind == 10 || kind == 15) {  // concrete all the way down
		c = lin(vec3(0.72, 0.72, 0.7)) * (0.88 + 0.14 * h2(floor(s * 90.0)));
		h = 0.0;
		return;
	}
	if (kind >= 11) {   // the edge of the stones, over their bed of sand and gravel
		vec3 st = (kind == 14 ? lin(vec3(0.5, 0.27, 0.2)) : lin(vec3(0.5, 0.48, 0.45))) * (0.85 + 0.2 * h2(floor(s * 70.0)));
		vec3 bed = mix(lin(vec3(0.5, 0.44, 0.34)), lin(vec3(0.36, 0.33, 0.29)), h2(floor(s * 60.0)));
		c = mix(st, bed, smoothstep(0.06, 0.08, d));
		h = 0.0;
		return;
	}
	if (kind >= 6) {   // asphalt over a gravel base
		vec3 asph = lin(vec3(0.4, 0.43, 0.45)) * (0.85 + 0.25 * h2(floor(s * 120.0)));
		vec3 base = mix(lin(vec3(0.42, 0.4, 0.37)), lin(vec3(0.3, 0.28, 0.26)), h2(floor(s * 60.0)));
		c = mix(asph, base, smoothstep(0.07, 0.1, d));
		h = 0.0;
		return;
	}
	if (kind == 5) {
		c = mix(lin(vec3(0.84, 0.74, 0.52)), lin(vec3(0.72, 0.6, 0.4)), smoothstep(0.1, 0.7, d));
		c *= 0.97 + 0.03 * sin(d * 50.0 + n2(s * 3.0) * 3.0);
		c *= 0.9 + 0.18 * h2(floor(s * 140.0));
		h = 0.0;
		return;
	}
	vec3 top = lin(vec3(0.25, 0.17, 0.11));
	vec3 sub = lin(vec3(0.4, 0.28, 0.18));
	vec3 clay = lin(vec3(0.52, 0.4, 0.28));
	c = mix(top, sub, smoothstep(0.16, 0.32, d));
	c = mix(c, clay, smoothstep(0.65, 0.85, d));
	c = mix(c, lin(vec3(0.5, 0.36, 0.24)), smoothstep(1.4, 1.6, d) * (0.5 + 0.5 * sin(d * 6.0)));
	c *= 0.9 + 0.12 * sin(d * 38.0 + n2(s * vec2(2.0, 6.0)) * 4.0);   // thin bands
	c *= 0.85 + 0.28 * n2(s * vec2(18.0, 30.0));
	h = 0.0;
#ifndef LOW
	vec3 k = cells(s * 5.0);
	float rs = 0.16 + 0.14 * fract(k.z * 13.0);
	float stone = smoothstep(rs, rs - 0.05, k.x) * step(0.8, k.z) * smoothstep(0.08, 0.3, d);
	vec3 sc = mix(lin(vec3(0.45, 0.43, 0.41)), lin(vec3(0.58, 0.52, 0.44)), fract(k.z * 7.0));
	c = mix(c, sc * (0.7 + 0.5 * (rs - k.x) / rs), stone);
	h += stone * (rs - k.x) * 0.08;
	if (kind == 0 || kind == 4) {    // roots near the top
		float rt = abs(n2(vec2(s.x * 6.0, s.y * 2.0)) - 0.5);
		float root = smoothstep(0.03, 0.0, rt) * (1.0 - smoothstep(0.1, 0.3, d));
		c = mix(c, lin(vec3(0.55, 0.42, 0.3)), root * 0.8);
	}
#endif
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lp = transpose(mat3(MODEL_MATRIX)) * wp;
	op = VERTEX;
	on = NORMAL;
	across = UV.x;
	dep = UV.y;
}

void fragment() {
	float up = on.y;
	vec3 col;
	float h;
	if (up < -0.5) {                       // underneath
		col = lin(vec3(0.3, 0.2, 0.13));
		h = 0.0;
	} else {
		float along = (abs(on.x) > abs(on.z) ? op.z : op.x) + wp.x + wp.z - op.x - op.z;
		// how far the top layer lips over the edge
		float lip = kind == 0 ? 0.05 : kind == 2 ? 0.1 : kind == 3 ? 0.08 : kind == 4 ? 0.05 : (kind >= 5) ? 0.0 : 0.03;
		lip += (n2(vec2(along * 7.0, 0.0)) - 0.5) * lip * 0.7;
		if (kind == 0) { lip += smoothstep(0.75, 1.0, n2(vec2(along * 19.0, 3.0))) * 0.05; }   // grass hanging down
		float on_top = smoothstep(0.5, 0.8, up);
		float lipw = 1.0 - smoothstep(lip - 0.006, lip + 0.006, dep);
		float tw = max(on_top, lipw);
		vec3 tc = vec3(0.0); float th = 0.0;
		vec3 sc = vec3(0.0); float sh = 0.0;
		if (tw > 0.001) {
			vec2 p = up > 0.5 ? ((kind >= 11 && kind <= 14) ? lp.xz : wp.xz) : vec2(along, wp.y);
			top_mat(p, across, tc, th);
			if (up <= 0.5) { tc *= 0.8; }
		}
		if (tw < 0.999) { side_mat(vec2(along, dep), sc, sh); }
		col = mix(sc, tc, tw);
		h = mix(sh, th, tw);
		// a thin dark line where the top layer meets the soil, and contact shading under it
		if (up <= 0.5) { col *= mix(0.6, 1.0, smoothstep(lip, lip + 0.05, dep)) * (1.0 - lipw * 0.0) + lipw * 0.0; }
	}
	// snow lies on top
	float sn = smoothstep(0.35, 0.75, up + (n2(wp.xz * 2.5) - 0.5) * 0.35 - (1.0 - snow_cover) * 0.4) * clamp(snow_cover * 1.4, 0.0, 1.0);
	col = mix(col, vec3(0.85, 0.88, 0.95), sn);
	ALBEDO = col * tint;
	ROUGHNESS = kind == 2 ? 0.85 : 0.95;
	SPECULAR = 0.3;
#ifndef LOW
	// bump from the painted height (screen-space surface gradient)
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * (1.0 - sn));
	AO = clamp(0.55 + h * 30.0, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.3;
#endif
}
"""

# Shrubs and flower leaves: lumpy, leafy clumps, colour from the instance colour.
const PLANT_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform float lumpy = 0.2;
uniform float leafy = 1.0;
global uniform float snow_cover;
varying vec3 tint;
varying vec3 lp;
varying float upw;
float h3(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float n3(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void vertex() {
	tint = pow(COLOR.rgb, vec3(2.2));
	vec3 seed = MODEL_MATRIX[3].xyz * 0.0 + vec3(float(INSTANCE_ID) * 3.7);
	lp = VERTEX + seed;
	VERTEX += NORMAL * (n3(VERTEX * 3.2 + seed) - 0.5) * lumpy * 2.0;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.xz += vec2(sin(TIME * 1.3 + w.x), cos(TIME * 1.1 + w.z)) * 0.012 * max(VERTEX.y, 0.0);
	upw = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}
void fragment() {
	float l = n3(lp * 11.0);
	float l2 = n3(lp * 23.0 + 4.0);
	float clump = mix(1.0, 0.62 + 0.55 * smoothstep(0.25, 0.8, l) + 0.15 * l2, leafy);
	vec3 c = tint * clump * (0.8 + 0.3 * clamp(upw, 0.0, 1.0));
	c = mix(c, vec3(0.88, 0.9, 0.96), smoothstep(0.3, 0.8, upw) * clamp(snow_cover * 1.3, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	BACKLIGHT = c * 0.35;
}
"""

static var _shaders := {}        # "full"/"low" -> Shader
static var _mats := {}           # kind|q -> ShaderMaterial
static var _meshes := {}         # size key -> ArrayMesh
static var _extras := {}         # kind|size|q -> Array of [Mesh/MultiMesh, Material, Transform3D or null]
static var _rock_mesh: ArrayMesh
static var _plant_mat: ShaderMaterial
static var _flower_mat: StandardMaterial3D
static var _stone_mat: StandardMaterial3D
static var _clod_mat: StandardMaterial3D
static var _wood_mat: StandardMaterial3D
static var _tuft_mat: ShaderMaterial


# A ground block of `size` (x width, y thickness, z depth), bottom-centre at the origin, top at y = size.y.
static func make(kind: String, size: Vector3, color := Color.WHITE) -> Node3D:
	if not KINDS.has(kind):
		kind = "grass"
	size = Vector3(maxf(size.x, 0.1), maxf(size.y, 0.02), maxf(size.z, 0.1))
	var q := _quality()
	_globals()
	var root := Node3D.new()
	root.name = "GroundBlock"
	if kind in EDGINGS:
		return _make_edging(root, kind, size, color)
	var mi := MeshInstance3D.new()
	mi.name = "Block"
	# (paving: next to no rounding, so a path made of several blocks reads as one; a sidewalk: a tooled edge)
	mi.mesh = _box_mesh(size, 0.006 if kind in PAVINGS else (0.02 if kind == "sidewalk" else 0.0))
	mi.material_override = _mat(kind, q)
	mi.set_instance_shader_parameter("bsize", size)
	# (always written, white included: never left to whatever the per-instance slot held before)
	var lc := color.srgb_to_linear()
	mi.set_instance_shader_parameter("tint", Vector3(lc.r, lc.g, lc.b))
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position.y = size.y / 2.0
	body.add_child(cs)
	root.add_child(body)
	_add_parts(root, _get_extras(kind, size, q))
	return root


# Parts are [MultiMesh, material, shadows] or [Mesh, material, shadows, where].
static func _add_parts(root: Node3D, parts: Array) -> void:
	for e in parts:
		var item: Array = e
		if item[0] is MultiMesh:
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = item[0]
			mmi.material_override = item[1]
			mmi.cast_shadow = item[2]
			root.add_child(mmi)
		else:
			var m := MeshInstance3D.new()
			m.mesh = item[0]
			m.material_override = item[1]
			m.cast_shadow = item[2]
			m.transform = item[3]
			root.add_child(m)


static func _quality() -> int:
	return int(load("res://scripts/graphics.gd").quality)


# The snow_cover global shader parameter is registered with the grime material.
static func _globals() -> void:
	load("res://scripts/models.gd").grime_material()


static func _shader(low: bool) -> Shader:
	var k := "low" if low else "full"
	if not _shaders.has(k):
		var sh := Shader.new()
		sh.code = SHADER.replace("render_mode cull_back;", "render_mode cull_back;\n#define LOW") if low else SHADER
		_shaders[k] = sh
	return _shaders[k]


static func _mat(kind: String, q: int) -> ShaderMaterial:
	var key := "%s|%d" % [kind, 0 if q == 0 else 1]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = _shader(q == 0)
		m.set_shader_parameter("kind", _KIND_ID[kind])
		_mats[key] = m
	return _mats[key]


# ---- the block mesh: a box with a rounded top edge. UV.x = across the long axis, UV.y = depth below the top ----

static func _box_mesh(sz: Vector3, bevel := 0.0) -> ArrayMesh:
	var key := "%.3f|%.3f|%.3f|%.3f" % [sz.x, sz.y, sz.z, bevel]
	if _meshes.has(key):
		return _meshes[key]
	var hx := sz.x / 2.0
	var hz := sz.z / 2.0
	var top := sz.y
	var b := minf(clampf(minf(sz.x, sz.z) * 0.035, 0.02, 0.07), sz.y * 0.45)
	if bevel > 0.0:
		b = minf(bevel, sz.y * 0.45)
	var long_x := sz.x >= sz.z
	var rings := []    # [inset, y, horizontal normal part, vertical normal part]
	for i in 4:
		var a := PI / 2.0 * float(i) / 3.0
		rings.append([b * (1.0 - sin(a)), top - b * (1.0 - cos(a)), sin(a), cos(a)])
	rings.append([0.0, 0.0, 1.0, 0.0])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# top
	var t0: float = rings[0][0]
	_quad(st, [Vector3(-hx + t0, top, -hz + t0), Vector3(hx - t0, top, -hz + t0), Vector3(hx - t0, top, hz - t0), Vector3(-hx + t0, top, hz - t0)],
			[Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP], top, long_x)
	# sides: [outward, along, half-length along, half-extent outward]
	var faces := [[Vector3.RIGHT, Vector3.BACK, hz, hx], [Vector3.LEFT, Vector3.BACK, hz, hx],
			[Vector3.BACK, Vector3.RIGHT, hx, hz], [Vector3.FORWARD, Vector3.RIGHT, hx, hz]]
	for f in faces:
		var fa: Array = f
		var d: Vector3 = fa[0]
		var t: Vector3 = fa[1]
		var ln: float = fa[2]
		var ex: float = fa[3]
		for r in rings.size() - 1:
			var r0: Array = rings[r]
			var r1: Array = rings[r + 1]
			var n0: Vector3 = (d * float(r0[2]) + Vector3.UP * float(r0[3])).normalized()
			var n1: Vector3 = (d * float(r1[2]) + Vector3.UP * float(r1[3])).normalized()
			var i0: float = r0[0]
			var i1: float = r1[0]
			var y0: float = r0[1]
			var y1: float = r1[1]
			var a0 := d * (ex - i0) - t * (ln - i0) + Vector3.UP * y0
			var b0 := d * (ex - i0) + t * (ln - i0) + Vector3.UP * y0
			var a1 := d * (ex - i1) - t * (ln - i1) + Vector3.UP * y1
			var b1 := d * (ex - i1) + t * (ln - i1) + Vector3.UP * y1
			_quad(st, [a0, b0, b1, a1], [n0, n0, n1, n1], top, long_x)
	# bottom
	_quad(st, [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)],
			[Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN], top, long_x)
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


# Two triangles, wound so they face along the given normal (Godot: clockwise = front).
static func _quad(st: SurfaceTool, p: Array, n: Array, top: float, long_x: bool) -> void:
	var a: Vector3 = p[0]
	var b: Vector3 = p[1]
	var c: Vector3 = p[2]
	var nn: Vector3 = (n[0] as Vector3) + (n[2] as Vector3)
	var order := [0, 1, 2, 0, 2, 3]
	if (b - a).cross(c - a).dot(nn) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for i in order:
		var v: Vector3 = p[i]
		st.set_normal(n[i])
		st.set_uv(Vector2(v.z if long_x else v.x, top - v.y))
		st.add_vertex(v)


# ---- extras ----

static func _get_extras(kind: String, sz: Vector3, q: int) -> Array:
	var key := "%s|%.3f|%.3f|%.3f|%d" % [kind, sz.x, sz.y, sz.z, q]
	if not _extras.has(key):
		_extras[key] = _build_extras(kind, sz, q)
	return _extras[key]


static func _build_extras(kind: String, sz: Vector3, q: int) -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%.2f|%.2f|%.2f" % [kind, sz.x, sz.y, sz.z])
	var area := sz.x * sz.z
	var top := sz.y
	var no_shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	match kind:
		"parking":
			# a concrete wheel stop at the back of every whole stall
			var stop := BoxMesh.new()
			stop.size = Vector3(1.7, 0.12, 0.2)
			var conc := StandardMaterial3D.new()
			conc.albedo_color = Color(0.72, 0.71, 0.68)
			Surfaces.apply(conc, "stone")
			var rows := [[-sz.z * 0.5 + 0.75, 0.0]]
			if sz.z >= 10.5:
				rows.append([sz.z * 0.5 - 0.75, PI])
			var n := int(floor((sz.x - END_MARGIN * 2.0) / STALL_W + 0.001))
			for row in rows:
				for i in n:
					var x := -sz.x * 0.5 + END_MARGIN + (i + 0.5) * STALL_W
					out.append([stop, conc, GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
							Transform3D(Basis(Vector3.UP, row[1]), Vector3(x, top + 0.06, row[0]))])
		"parking_spot", "parking_accessible":
			var stop1 := BoxMesh.new()
			stop1.size = Vector3(1.7, 0.12, 0.2)
			var conc1 := StandardMaterial3D.new()
			conc1.albedo_color = Color(0.72, 0.71, 0.68)
			Surfaces.apply(conc1, "stone")
			var sw := minf(STALL_W, sz.x) if kind == "parking_accessible" else sz.x
			out.append([stop1, conc1, GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
					Transform3D(Basis(), Vector3(-sz.x * 0.5 + sw * 0.5, top + 0.06, -sz.z * 0.5 + 0.75))])
		"grass":
			if q >= 1:
				var n := clampi(int(area * (15.0 if q >= 2 else 5.0)), 0, 900 if q >= 2 else 260)   # (Nov 27: thicker)
				if n >= 2:
					var xf := []
					var cols := []
					for i in n:
						var pos := Vector3(rng.randf_range(-0.5, 0.5) * (sz.x - 0.12), top, rng.randf_range(-0.5, 0.5) * (sz.z - 0.12))
						var s := rng.randf_range(0.6, 1.1)
						xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.6, 1.0), s)), pos))
						var sh := rng.randf_range(0.8, 1.15)
						cols.append(Color(sh * rng.randf_range(0.95, 1.08), sh, sh * rng.randf_range(0.85, 1.0)))
					out.append([_multi(NatureLook._tuft(), xf, cols), _tufts_mat(), no_shadow])
				# clover and tiny wildflowers dotted through it
				var fn := clampi(int(area * (1.2 if q >= 2 else 0.4)), 0, 80)
				if fn >= 1:
					var fxf := []
					var fcols := []
					for i in fn:
						var pos := Vector3(rng.randf_range(-0.5, 0.5) * (sz.x - 0.15), top + 0.06, rng.randf_range(-0.5, 0.5) * (sz.z - 0.15))
						fxf.append(Transform3D(Basis().scaled(Vector3(1.0, 0.5, 1.0) * rng.randf_range(0.018, 0.03)), pos - Vector3(0, 0.035, 0)))
						fcols.append([Color(0.98, 0.97, 0.92), Color(0.98, 0.85, 0.2), Color(0.75, 0.55, 0.9)][rng.randi() % 3])
					out.append([_multi(_head(), fxf, fcols), _flowers_mat(), no_shadow])
		"dirt":
			if q >= 1:
				var n := clampi(int(area * (9.0 if q >= 2 else 3.0)), 0, 320 if q >= 2 else 100)   # (Nov 27: more clods)
				if n >= 1:
					var xf := []
					var cols := []
					for i in n:
						var pos := Vector3(rng.randf_range(-0.5, 0.5) * (sz.x - 0.1), top, rng.randf_range(-0.5, 0.5) * (sz.z - 0.1))
						var s := rng.randf_range(0.05, 0.11)
						xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(1.0, 1.5), s * 0.6, s)), pos))
						var v := rng.randf_range(0.8, 1.15)
						cols.append(Color(0.44 * v, 0.29 * v, 0.18 * v))
					out.append([_multi(_rock(true), xf, cols), _clods_mat(), no_shadow])
				# pebbles, and the odd weed pushing through
				var pn := clampi(int(area * 2.0), 0, 80)
				var pxf := []
				var pcols := []
				for i in pn:
					var s := rng.randf_range(0.025, 0.05)
					pxf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.3, s * 0.7, s)), Vector3(rng.randf_range(-0.5, 0.5) * (sz.x - 0.1), top, rng.randf_range(-0.5, 0.5) * (sz.z - 0.1))))
					var gv := rng.randf_range(0.5, 0.75)
					pcols.append(Color(gv, gv * 0.96, gv * 0.9))
				if pn >= 1:
					out.append([_multi(_rock(true), pxf, pcols), _stones_mat(), no_shadow])
				var wn := clampi(int(area * 0.5), 0, 30)
				if wn >= 1:
					var wxf := []
					var wcols := []
					for i in wn:
						var s := rng.randf_range(0.4, 0.8)
						wxf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(rng.randf_range(-0.5, 0.5) * (sz.x - 0.15), top, rng.randf_range(-0.5, 0.5) * (sz.z - 0.15))))
						wcols.append(Color(0.75, 0.8, 0.55))
					out.append([_multi(NatureLook._tuft(), wxf, wcols), _tufts_mat(), no_shadow])
		"gravel":
			if q >= 1:
				var n := clampi(int(area * (1.6 if q >= 2 else 0.7)), 0, 60 if q >= 2 else 24)
				if n >= 1:
					var xf := []
					var cols := []
					for i in n:
						var pos := Vector3(rng.randf_range(-0.5, 0.5) * (sz.x - 0.12), top - 0.005, rng.randf_range(-0.5, 0.5) * (sz.z - 0.12))
						var s := rng.randf_range(0.04, 0.08)
						xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.3, s * 0.6, s)), pos))
						var g := rng.randf_range(0.5, 0.8)
						cols.append(Color(g, g * rng.randf_range(0.93, 1.0), g * rng.randf_range(0.82, 0.98)))
					out.append([_multi(_rock(true), xf, cols), _stones_mat(), no_shadow])
		"landscaping":
			var edge := 0.16
			_stone_edging(out, sz, rng, edge)
			_plants(out, sz, rng, edge + 0.05, clampi(int(area / 1.6), 1, 16), clampi(int(area * 1.2), 1, 26), q)   # (Nov 27: fuller beds)
			if q >= 1:
				var rn := clampi(int(area / 3.0), 0, 8)
				var rxf := []
				var rcols := []
				for i in rn:
					var s := rng.randf_range(0.1, 0.22)
					rxf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.3, s * 0.7, s)), Vector3(rng.randf_range(-0.4, 0.4) * sz.x, top, rng.randf_range(-0.4, 0.4) * sz.z)))
					var gv := rng.randf_range(0.5, 0.7)
					rcols.append(Color(gv, gv * 0.97, gv * 0.93))
				if rn >= 1:
					out.append([_multi(_rock(), rxf, rcols), _stones_mat(), shadow])   # a few landscaping boulders
		"flowerbed":
			var edge := 0.08
			_timber_edging(out, sz, edge)
			_plants(out, sz, rng, edge + 0.04, clampi(int(area / 8.0), 0, 3), clampi(int(area * 2.2), 2, 40), q)
	return out


static func _multi(mesh: Mesh, xf: Array, cols: Array) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
	return mm


# A ring of chunky stones around the top, half sunk into the mulch.
static func _stone_edging(out: Array, sz: Vector3, rng: RandomNumberGenerator, w: float) -> void:
	var xf := []
	var cols := []
	var top := sz.y
	var hx := sz.x / 2.0 - w / 2.0 - 0.01
	var hz := sz.z / 2.0 - w / 2.0 - 0.01
	# walk the rectangle's perimeter
	var lines := [[Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz)], [Vector3(hx, 0, -hz), Vector3(hx, 0, hz)],
			[Vector3(hx, 0, hz), Vector3(-hx, 0, hz)], [Vector3(-hx, 0, hz), Vector3(-hx, 0, -hz)]]
	for l in lines:
		var la: Array = l
		var a: Vector3 = la[0]
		var b: Vector3 = la[1]
		var len := a.distance_to(b)
		var n := maxi(1, int(round(len / 0.2)))
		var dir := (b - a).normalized()
		for i in n:
			var p := a.lerp(b, float(i) / float(n))
			var s := rng.randf_range(0.85, 1.1)
			var rot := atan2(-dir.z, dir.x)    # lengthwise along the edge
			var basis := Basis(Vector3.UP, rot + rng.randf_range(-0.2, 0.2)).scaled(Vector3(0.12 * s, 0.075 * s * rng.randf_range(0.85, 1.15), 0.085 * s))
			xf.append(Transform3D(basis, p + Vector3(0, top + 0.012, 0)))
			var g := rng.randf_range(0.42, 0.6)
			cols.append(Color(g, g * rng.randf_range(0.95, 1.0), g * rng.randf_range(0.86, 0.97)))
	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	out.append([_multi(_rock(true), xf, cols), _stones_mat(), shadow])   # (hundreds round a big bed: the lighter stone)


# Four timber boards standing round the edge (lapped at the corners).
static func _timber_edging(out: Array, sz: Vector3, w: float) -> void:
	var hgt := 0.16
	var y := sz.y - 0.06 + hgt / 2.0
	# (the wood grain runs along the mesh's y, so each board is built standing up and laid down)
	var along_x := Basis(Vector3.BACK, PI / 2.0)
	var along_z := Basis(Vector3.RIGHT, PI / 2.0)
	var boards := [[Vector3(hgt, sz.x, w), along_x, Vector3(0, y, -sz.z / 2.0 + w / 2.0)], [Vector3(hgt, sz.x, w), along_x, Vector3(0, y, sz.z / 2.0 - w / 2.0)],
			[Vector3(w, sz.z - w * 2.0, hgt), along_z, Vector3(-sz.x / 2.0 + w / 2.0, y, 0)], [Vector3(w, sz.z - w * 2.0, hgt), along_z, Vector3(sz.x / 2.0 - w / 2.0, y, 0)]]
	for bd in boards:
		var ba: Array = bd
		var bm := BoxMesh.new()
		bm.size = ba[0]
		out.append([bm, _timber_mat(), GeometryInstance3D.SHADOW_CASTING_SETTING_ON, Transform3D(ba[1], ba[2])])


# Shrubs and flower clusters scattered on the bed (kept off the edging and off each other).
static func _plants(out: Array, sz: Vector3, rng: RandomNumberGenerator, margin: float, shrubs: int, flowers: int, q: int) -> void:
	var top := sz.y
	var hx := sz.x / 2.0 - margin
	var hz := sz.z / 2.0 - margin
	if hx <= 0.05 or hz <= 0.05:
		return
	var taken := []    # [Vector2, radius]
	var bush_xf := []
	var bush_col := []
	var head_xf := []
	var head_col := []
	var shrub_greens := [Color(0.2, 0.42, 0.14), Color(0.16, 0.36, 0.17), Color(0.3, 0.46, 0.16), Color(0.22, 0.4, 0.24)]
	var petals := [Color(0.95, 0.35, 0.5), Color(1.0, 0.82, 0.25), Color(0.96, 0.95, 1.0), Color(0.62, 0.4, 0.9), Color(1.0, 0.5, 0.22), Color(0.9, 0.2, 0.25)]
	for i in shrubs:
		var r := minf(rng.randf_range(0.22, 0.4), minf(hx, hz))
		var p := _spot(rng, hx - r * 0.6, hz - r * 0.6, r, taken)
		if p.x > 1e5:
			continue
		taken.append([p, r])
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r, r * rng.randf_range(0.75, 0.95), r))
		bush_xf.append(Transform3D(basis, Vector3(p.x, top + r * 0.35, p.y)))
		bush_col.append(shrub_greens[rng.randi() % shrub_greens.size()])
	for i in flowers:
		var r := minf(rng.randf_range(0.1, 0.16), minf(hx, hz))
		var p := _spot(rng, hx - r * 0.5, hz - r * 0.5, r, taken)
		if p.x > 1e5:
			continue
		taken.append([p, r])
		bush_xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r, r * 0.7, r)), Vector3(p.x, top + r * 0.2, p.y)))
		bush_col.append(Color(0.26, 0.5, 0.2) * rng.randf_range(0.85, 1.1))
		var pc: Color = petals[rng.randi() % petals.size()]
		var heads := rng.randi_range(3, 6)
		for k in heads:
			var a := TAU * float(k) / float(heads) + rng.randf_range(-0.4, 0.4)
			var d := r * rng.randf_range(0.2, 0.7)
			var hp := Vector3(p.x + cos(a) * d, top + r * rng.randf_range(0.75, 1.0), p.y + sin(a) * d)
			var s := rng.randf_range(0.035, 0.05)
			head_xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.55, s)), hp))
			head_col.append(pc * rng.randf_range(0.9, 1.08))
	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if not bush_xf.is_empty():
		out.append([_multi(_bush(), bush_xf, bush_col), _plants_mat(), shadow])
	if not head_xf.is_empty():
		out.append([_multi(_head(), head_xf, head_col), _flowers_mat(), GeometryInstance3D.SHADOW_CASTING_SETTING_OFF])


# A free spot (x, z) inside +-hx, +-hz not overlapping taken ones, or a huge vector when none is found.
static func _spot(rng: RandomNumberGenerator, hx: float, hz: float, r: float, taken: Array) -> Vector2:
	for attempt in 12:
		var p := Vector2(rng.randf_range(-maxf(hx, 0.0), maxf(hx, 0.0)), rng.randf_range(-maxf(hz, 0.0), maxf(hz, 0.0)))
		var ok := true
		for t in taken:
			var ta: Array = t
			if p.distance_to(ta[0]) < (r + float(ta[1])) * 0.85:
				ok = false
				break
		if ok:
			return p
	return Vector2(1e6, 1e6)


# ---- edgings (Ted, Nov 28): a thin line of something along the block's longer side ----
# Everything is placed with a seed from the kind and size, like the other extras, so the same edging always
# looks the same, on every screen. One box to bump into, the size of the block.

static var _edge_cache := {}     # kind|size|colour|quality -> parts
static var _edge_meshes := {}    # name -> Mesh
static var _edge_mats := {}      # name -> Material


static func _make_edging(root: Node3D, kind: String, size: Vector3, color: Color) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position.y = size.y / 2.0
	body.add_child(cs)
	root.add_child(body)
	var q := _quality()
	var key := "%s|%.3f|%.3f|%.3f|%s|%d" % [kind, size.x, size.y, size.z, color.to_html(false), q]
	if not _edge_cache.has(key):
		_edge_cache[key] = _build_edging(kind, size, color, q)
	_add_parts(root, _edge_cache[key])
	return root


static func _vary(base: Color, rng: RandomNumberGenerator, amount: float) -> Color:
	var v := rng.randf_range(1.0 - amount, 1.0 + amount)
	return Color(clampf(base.r * v * rng.randf_range(0.96, 1.04), 0.0, 1.0), clampf(base.g * v, 0.0, 1.0),
			clampf(base.b * v * rng.randf_range(0.94, 1.04), 0.0, 1.0))


static func _build_edging(kind: String, size: Vector3, color: Color, q: int) -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%.2f|%.2f|%.2f" % [kind, size.x, size.y, size.z])
	var len := maxf(size.x, size.z)      # the run
	var thick := minf(size.x, size.z)
	var tall := size.y
	# (built along x, then turned if the block's long side is z)
	var turn := Basis() if size.x >= size.z else Basis(Vector3.UP, PI / 2.0)
	var base: Color = color
	if color.is_equal_approx(Color.WHITE):
		base = EDGE_COLORS[kind]
	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var xf := []
	var cols := []
	match kind:
		"edge_rocks":
			# rocks nose to tail, every one its own length, width, height and lie
			var x := -len / 2.0
			while x < len / 2.0 - thick * 0.25:
				var l := maxf(minf(thick * rng.randf_range(0.7, 1.3), len / 2.0 - x), thick * 0.3)
				var w := thick * rng.randf_range(0.72, 1.0)
				var hh := tall * rng.randf_range(0.65, 1.0)
				var b := Basis(Vector3.UP, rng.randf_range(-0.35, 0.35) + (PI if rng.randf() < 0.5 else 0.0)) * Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12))
				b = b * Basis.from_scale(Vector3(l / 2.0 * 1.32, hh / 1.3, w / 2.0 * 1.12))
				xf.append(Transform3D(turn * b, turn * Vector3(x + l / 2.0, hh * 0.27, rng.randf_range(-1.0, 1.0) * (thick - w) * 0.5)))
				cols.append(_vary(base, rng, 0.18))
				x += l * 0.9
			out.append([_multi(_rock(q == 0 or len > 60.0), xf, cols), _stones_mat(), shadow])   # (a very long run: the lighter stone)
		"edge_fence":
			# pointed pickets a hand high, two rails behind them and a stake every metre or so
			var pitch := 0.085
			var n := maxi(1, int(floor(len / pitch)))
			var th := minf(0.022, thick * 0.3)
			var x0 := -(n - 1) * pitch / 2.0
			for i in n:
				var b := Basis(Vector3.BACK, rng.randf_range(-0.03, 0.03)) * Basis.from_scale(Vector3(0.065, tall * rng.randf_range(0.93, 1.0), th))
				xf.append(Transform3D(turn * b, turn * Vector3(x0 + i * pitch, 0.0, th)))
				cols.append(_vary(base, rng, 0.12))
			out.append([_multi(_picket(), xf, cols), _edge_mat("wood"), shadow])
			var rxf := []
			var rcols := []
			for ry in [0.3, 0.68]:
				rxf.append(Transform3D(turn * Basis.from_scale(Vector3(len, 0.03, th)), turn * Vector3(0.0, tall * float(ry), 0.0)))
				rcols.append(base * 0.82)
			var stakes := maxi(2, int(round(len / 1.1)) + 1)
			for i in stakes:
				var sx := lerpf(-len / 2.0 + 0.04, len / 2.0 - 0.04, float(i) / float(stakes - 1))
				rxf.append(Transform3D(turn * Basis.from_scale(Vector3(0.04, tall * 0.86, 0.035)), turn * Vector3(sx, tall * 0.43, -th * 1.3)))
				rcols.append(base * 0.75)
			out.append([_multi(_unit_box(), rxf, rcols), _edge_mat("wood"), shadow])
		"edge_logs":
			# a log roll: short logs stood side by side, their tops up and down
			var n := maxi(1, int(round(len / clampf(thick * 0.92, 0.05, 0.2))))
			var d := len / n
			for i in n:
				var hh := tall * (0.8 + 0.2 * (0.5 + 0.5 * sin(i * 1.9))) * rng.randf_range(0.94, 1.0)
				var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(d, hh, minf(d, thick)))
				xf.append(Transform3D(turn * b, turn * Vector3(-len / 2.0 + (i + 0.5) * d, 0.0, 0.0)))
				cols.append(_vary(base, rng, 0.12))
			out.append([_multi(_log(), xf, cols), _edge_mat("wood"), shadow])
		"edge_ceramic":
			# glazed tiles with a round top, edge to edge
			var n := maxi(1, int(round(len / 0.2)))
			var tl := len / n
			var th := clampf(thick * 0.38, 0.025, 0.08)
			for i in n:
				var b := Basis(Vector3.BACK, rng.randf_range(-0.02, 0.02)) * Basis.from_scale(Vector3(tl * 0.985, tall * rng.randf_range(0.96, 1.0), th))
				xf.append(Transform3D(turn * b, turn * Vector3(-len / 2.0 + (i + 0.5) * tl, 0.0, 0.0)))
				cols.append(_vary(base, rng, 0.07))
			out.append([_multi(_scallop(), xf, cols), _edge_mat("ceramic"), shadow])
		"edge_brick":
			# bricks leaning on each other at 45 degrees, half buried: a row of teeth
			var bl := 0.2
			var bt := 0.065
			var pitch := bt / sin(PI / 4.0)
			var reach := (bl + bt) * 0.5 * sin(PI / 4.0)   # how far a leaning brick's corners are from its middle
			var n := maxi(1, int(floor((len - reach * 2.0) / pitch)) + 1)
			var x0 := -(n - 1) * pitch / 2.0
			for i in n:
				var b := Basis(Vector3.BACK, PI / 4.0 + rng.randf_range(-0.03, 0.03)) * Basis.from_scale(Vector3(bl, bt, thick * rng.randf_range(0.95, 1.0)))
				xf.append(Transform3D(turn * b, turn * Vector3(x0 + i * pitch, tall - reach, 0.0)))
				cols.append(_vary(base, rng, 0.16))
			out.append([_multi(_unit_box(), xf, cols), _edge_mat("brick"), shadow])
		"edge_stone":
			# squared kerb stones, each a different length, a thin joint between
			var x := -len / 2.0
			while x < len / 2.0 - 0.02:
				var l := rng.randf_range(0.22, 0.36)
				if len / 2.0 - (x + l) < 0.12:
					l = len / 2.0 - x
				var b := Basis(Vector3.UP, rng.randf_range(-0.025, 0.025)) * Basis.from_scale(Vector3(maxf(l - 0.008, 0.02), tall * rng.randf_range(0.93, 1.0), thick * rng.randf_range(0.94, 1.0)))
				xf.append(Transform3D(turn * b, turn * Vector3(x + l / 2.0, 0.0, 0.0)))
				cols.append(_vary(base, rng, 0.1))
				x += l
			out.append([_multi(_kerb(), xf, cols), _stones_mat(), shadow])
		"edge_hedge":
			out.append([_hedge(len, tall, thick, base, rng), _edge_mat("hedge"), shadow, Transform3D(turn, Vector3.ZERO)])
	return out


# One triangle facing along `n` (Godot: clockwise = front), each corner with its own normal and colour.
static func _tri(st: SurfaceTool, p: Array, nrm: Array, col: Array, n: Vector3) -> void:
	var order := [0, 1, 2]
	if ((p[1] as Vector3) - (p[0] as Vector3)).cross((p[2] as Vector3) - (p[0] as Vector3)).dot(n) > 0.0:
		order = [0, 2, 1]
	for i in order:
		st.set_normal(nrm[i])
		st.set_color(col[i])
		st.add_vertex(p[i])


# A flat outline (x, y; anticlockwise, bulging nowhere inward) pushed through from z = -0.5 to 0.5. `round_from`:
# the points from there on have smooth sides (a curved top), the rest flat faces.
static func _prism(pts: PackedVector2Array, round_from := 9999, centre := Vector2.ZERO) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := [Color.WHITE, Color.WHITE, Color.WHITE]
	var n := pts.size()
	for side in [1.0, -1.0]:
		var fn := Vector3(0, 0, side)
		for i in range(1, n - 1):
			_tri(st, [Vector3(pts[0].x, pts[0].y, 0.5 * side), Vector3(pts[i].x, pts[i].y, 0.5 * side), Vector3(pts[i + 1].x, pts[i + 1].y, 0.5 * side)],
					[fn, fn, fn], white, fn)
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var e := (b - a).normalized()
		var flat := Vector3(e.y, -e.x, 0.0)
		var na := flat
		var nb := flat
		if i >= round_from and (i + 1) % n >= round_from:
			na = Vector3(a.x - centre.x, a.y - centre.y, 0.0).normalized()
			nb = Vector3(b.x - centre.x, b.y - centre.y, 0.0).normalized()
		var a0 := Vector3(a.x, a.y, 0.5)
		var b0 := Vector3(b.x, b.y, 0.5)
		var a1 := Vector3(a.x, a.y, -0.5)
		var b1 := Vector3(b.x, b.y, -0.5)
		_tri(st, [a0, b0, b1], [na, nb, nb], white, flat)
		_tri(st, [a0, b1, a1], [na, nb, na], white, flat)
	return st.commit()


# A picket: 1 wide, 1 tall with a point, 1 thick, standing on the origin.
static func _picket() -> Mesh:
	if not _edge_meshes.has("picket"):
		_edge_meshes["picket"] = _prism(PackedVector2Array([Vector2(-0.5, 0), Vector2(0.5, 0), Vector2(0.5, 0.8), Vector2(0, 1), Vector2(-0.5, 0.8)]))
	return _edge_meshes["picket"]


# A tile with a half-round top: 1 wide, 1 tall, 1 thick.
static func _scallop() -> Mesh:
	if not _edge_meshes.has("scallop"):
		var pts := PackedVector2Array([Vector2(-0.5, 0), Vector2(0.5, 0)])
		for i in 11:
			var a := PI * float(i) / 10.0
			pts.append(Vector2(0.5 * cos(a), 0.5 + 0.5 * sin(a)))
		_edge_meshes["scallop"] = _prism(pts, 2, Vector2(0, 0.5))
	return _edge_meshes["scallop"]


static func _unit_box() -> Mesh:
	if not _edge_meshes.has("box"):
		_edge_meshes["box"] = BoxMesh.new()
	return _edge_meshes["box"]


# A kerb stone: 1 x 1 x 1 standing on the origin, its top edges cut off.
static func _kerb() -> Mesh:
	if not _edge_meshes.has("kerb"):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var white := [Color.WHITE, Color.WHITE, Color.WHITE]
		var rings := [[0.5, 0.5, 0.0], [0.5, 0.5, 0.8], [0.46, 0.36, 1.0]]   # half x, half z, y
		for r in 2:
			var lo: Array = rings[r]
			var hi: Array = rings[r + 1]
			for c in 4:
				var s0: Vector2 = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)][c]
				var s1: Vector2 = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)][(c + 1) % 4]
				var a := Vector3(s0.x * lo[0], lo[2], s0.y * lo[1])
				var b := Vector3(s1.x * lo[0], lo[2], s1.y * lo[1])
				var a2 := Vector3(s0.x * hi[0], hi[2], s0.y * hi[1])
				var b2 := Vector3(s1.x * hi[0], hi[2], s1.y * hi[1])
				var fn := (b - a).cross(a2 - a).normalized()
				if fn.dot(Vector3(a.x + b.x, 0.0, a.z + b.z)) < 0.0:
					fn = -fn
				_tri(st, [a, b, b2], [fn, fn, fn], white, fn)
				_tri(st, [a, b2, a2], [fn, fn, fn], white, fn)
		var t: Array = rings[2]
		var up := [Vector3.UP, Vector3.UP, Vector3.UP]
		_tri(st, [Vector3(-t[0], 1, -t[1]), Vector3(t[0], 1, -t[1]), Vector3(t[0], 1, t[1])], up, white, Vector3.UP)
		_tri(st, [Vector3(-t[0], 1, -t[1]), Vector3(t[0], 1, t[1]), Vector3(-t[0], 1, t[1])], up, white, Vector3.UP)
		_edge_meshes["kerb"] = st.commit()
	return _edge_meshes["kerb"]


# A short log stood on end: 1 across, 1 tall. Bark down the side (darker), the sawn top as the colour comes.
static func _log() -> Mesh:
	if not _edge_meshes.has("log"):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var bark := Color(0.5, 0.42, 0.36)
		var sides := 10
		for i in sides:
			var a0 := TAU * float(i) / sides
			var a1 := TAU * float(i + 1) / sides
			var n0 := Vector3(cos(a0), 0, sin(a0))
			var n1 := Vector3(cos(a1), 0, sin(a1))
			var p0 := n0 * 0.5
			var p1 := n1 * 0.5
			_tri(st, [p0, p1, p1 + Vector3.UP], [n0, n1, n1], [bark, bark, bark], n0 + n1)
			_tri(st, [p0, p1 + Vector3.UP, p0 + Vector3.UP], [n0, n1, n0], [bark, bark, bark], n0 + n1)
			_tri(st, [Vector3.UP, p0 + Vector3.UP, p1 + Vector3.UP], [Vector3.UP, Vector3.UP, Vector3.UP],
					[Color(0.8, 0.76, 0.7), Color.WHITE, Color.WHITE], Vector3.UP)
		_edge_meshes["log"] = st.commit()
	return _edge_meshes["log"]


# A low clipped hedge `len` long: a rounded ridge the plant shader makes lumpy and leafy.
static func _hedge(len: float, tall: float, thick: float, base: Color, rng: RandomNumberGenerator) -> ArrayMesh:
	var prof := [Vector2(-0.5, 0.0), Vector2(-0.5, 0.78), Vector2(-0.4, 0.96), Vector2(0.0, 1.0), Vector2(0.4, 0.96), Vector2(0.5, 0.78), Vector2(0.5, 0.0)]
	var rings := maxi(2, int(ceil(len / 0.12)) + 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pos := []
	var nrm := []
	var col := []
	for r in rings:
		var x := -len / 2.0 + len * float(r) / float(rings - 1)
		var shade := rng.randf_range(0.82, 1.12)
		var end := -1.0 if r == 0 else (1.0 if r == rings - 1 else 0.0)
		for k in prof.size():
			var pt: Vector2 = prof[k]
			pos.append(Vector3(x, pt.y * tall, pt.x * thick))
			nrm.append(Vector3(end * 0.8, pt.y - 0.45, pt.x * 1.4).normalized())
			var v := shade * rng.randf_range(0.9, 1.1)
			col.append(Color(clampf(base.r * v, 0.0, 1.0), clampf(base.g * v, 0.0, 1.0), clampf(base.b * v, 0.0, 1.0)))
	var np := prof.size()
	for r in rings - 1:
		for k in np - 1:
			var a := r * np + k
			var b := a + 1
			var c := a + np
			var d := c + 1
			var out_n: Vector3 = (nrm[a] as Vector3) + (nrm[d] as Vector3)
			_tri(st, [pos[a], pos[b], pos[d]], [nrm[a], nrm[b], nrm[d]], [col[a], col[b], col[d]], out_n)
			_tri(st, [pos[a], pos[d], pos[c]], [nrm[a], nrm[d], nrm[c]], [col[a], col[d], col[c]], out_n)
	for r in [0, rings - 1]:   # the two ends
		var en := Vector3(-1 if r == 0 else 1, 0, 0)
		for k in range(1, np - 1):
			var a: int = r * np
			_tri(st, [pos[a], pos[a + k], pos[a + k + 1]], [nrm[a], nrm[a + k], nrm[a + k + 1]], [col[a], col[a + k], col[a + k + 1]], en)
	return st.commit()


static func _edge_mat(name: String) -> Material:
	if _edge_mats.has(name):
		return _edge_mats[name]
	if name == "hedge":
		var sh := Shader.new()
		sh.code = PLANT_SHADER
		var hm := ShaderMaterial.new()
		hm.shader = sh
		hm.set_shader_parameter("lumpy", 0.014)   # (metres here: the hedge is built at full size)
		_edge_mats[name] = hm
		return hm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	match name:
		"wood":
			Surfaces.apply(m, "wood")
		"brick":
			Surfaces.apply(m, "stone")
		"ceramic":
			Surfaces.apply(m, "glossy")
			m.roughness = 0.16
			m.metallic_specular = 0.7
			m.clearcoat_enabled = true
			m.clearcoat = 0.7
			m.clearcoat_roughness = 0.1
	_edge_mats[name] = m
	return m


# ---- shared meshes ----

# A chunky faceted pebble about 2 units across (scaled per instance). `small`: the same with half the facets, for
# the clods, pebbles and gravel no bigger than a fist that get scattered by the hundred (Nov 27 audit: a dirt
# block was 7,800 triangles of them).
static var _pebble_mesh: ArrayMesh


static func _rock(small := false) -> ArrayMesh:
	if small and _pebble_mesh != null:
		return _pebble_mesh
	if not small and _rock_mesh != null:
		return _rock_mesh
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 6 if small else 8
	sm.rings = 3 if small else 5
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v := verts[i]
		var k := Vector3i(roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0))
		var hsh := hash(k)
		var j := 0.82 + float(hsh % 1000) / 1000.0 * 0.3
		v *= j
		v.y = maxf(v.y, -0.35)      # flat bottom
		verts[i] = v
	arr[Mesh.ARRAY_VERTEX] = verts
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st := SurfaceTool.new()
	st.create_from(tmp, 0)
	st.deindex()
	st.generate_normals()     # flat facets
	if small:
		_pebble_mesh = st.commit()
		return _pebble_mesh
	_rock_mesh = st.commit()
	return _rock_mesh


static var _bush_mesh: SphereMesh
static var _head_mesh: SphereMesh


static func _bush() -> SphereMesh:
	if _bush_mesh == null:
		_bush_mesh = SphereMesh.new()
		_bush_mesh.radius = 1.0
		_bush_mesh.height = 2.0
		_bush_mesh.radial_segments = 14
		_bush_mesh.rings = 8
	return _bush_mesh


static func _head() -> SphereMesh:
	if _head_mesh == null:
		_head_mesh = SphereMesh.new()
		_head_mesh.radius = 1.0
		_head_mesh.height = 2.0
		_head_mesh.radial_segments = 6
		_head_mesh.rings = 3
	return _head_mesh


# ---- shared materials ----

static func _tufts_mat() -> ShaderMaterial:
	if _tuft_mat == null:
		var sh := Shader.new()
		sh.code = NatureLook.TUFT_SHADER
		_tuft_mat = ShaderMaterial.new()
		_tuft_mat.shader = sh
		_tuft_mat.set_shader_parameter("base_col", Color(0.36, 0.6, 0.2))
	return _tuft_mat


static func _plants_mat() -> ShaderMaterial:
	if _plant_mat == null:
		var sh := Shader.new()
		sh.code = PLANT_SHADER
		_plant_mat = ShaderMaterial.new()
		_plant_mat.shader = sh
	return _plant_mat


static func _flowers_mat() -> StandardMaterial3D:
	if _flower_mat == null:
		_flower_mat = StandardMaterial3D.new()
		_flower_mat.vertex_color_use_as_albedo = true
		_flower_mat.vertex_color_is_srgb = true
		_flower_mat.roughness = 0.6
		_flower_mat.emission_enabled = true
		_flower_mat.emission = Color(0.08, 0.06, 0.06)
	return _flower_mat


static func _stones_mat() -> StandardMaterial3D:
	if _stone_mat == null:
		_stone_mat = StandardMaterial3D.new()
		_stone_mat.vertex_color_use_as_albedo = true
		_stone_mat.vertex_color_is_srgb = true
		Surfaces.apply(_stone_mat, "stone")
	return _stone_mat


static func _clods_mat() -> StandardMaterial3D:
	if _clod_mat == null:
		_clod_mat = StandardMaterial3D.new()
		_clod_mat.vertex_color_use_as_albedo = true
		_clod_mat.vertex_color_is_srgb = true
		Surfaces.apply(_clod_mat, "ground")
	return _clod_mat


static func _timber_mat() -> StandardMaterial3D:
	if _wood_mat == null:
		_wood_mat = StandardMaterial3D.new()
		_wood_mat.albedo_color = Color(0.5, 0.33, 0.2)
		Surfaces.apply(_wood_mat, "wood")
	return _wood_mat
