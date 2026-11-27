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
}
const STREET_KINDS := ["parking", "parking_spot", "parking_accessible", "asphalt", "concrete"]   # (Street/Road too)
const _KIND_ID := {"grass": 0, "dirt": 1, "gravel": 2, "landscaping": 3, "flowerbed": 4, "sand": 5, "parking": 6,
		"parking_spot": 7, "parking_accessible": 8, "asphalt": 9, "concrete": 10}
const END_MARGIN := 0.5   # a lot's plain asphalt past the first and last stalls (Ted's wife, Nov 27)
# Default sizes for new pieces of these kinds
const DEFAULT_SIZES := {"parking": Vector3(STALL_W * 5 + END_MARGIN * 2, 0.1, 5.2), "parking_spot": Vector3(STALL_W, 0.1, 5.2),
		"parking_accessible": Vector3(4.2, 0.1, 5.2), "asphalt": Vector3(6, 0.1, 6), "concrete": Vector3(4, 0.12, 4)}
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

void top_mat(vec2 p, float ac, out vec3 c, out float h) {
	if (kind == 0) grass_top(p, c, h);
	else if (kind == 1) soil_top(p, ac, c, h, true);
	else if (kind == 2) gravel_top(p, c, h);
	else if (kind == 3) mulch_top(p, c, h);
	else if (kind == 4) bed_top(p, c, h);
	else if (kind >= 6 && kind <= 8) parking_top(c, h);
	else if (kind >= 9) plain_top(p, c, h);
	else sand_top(p, c, h);
}

// ---- sides: layers going down from the top ----
void side_mat(vec2 s, out vec3 c, out float h) {      // s = (along the face, depth)
	float d = s.y + (fbm(vec2(s.x * 1.4, s.y * 2.0)) - 0.5) * 0.14;
	if (kind == 10) {  // concrete all the way down
		c = lin(vec3(0.72, 0.72, 0.7)) * (0.88 + 0.14 * h2(floor(s * 90.0)));
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
			vec2 p = up > 0.5 ? wp.xz : vec2(along, wp.y);
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
	var mi := MeshInstance3D.new()
	mi.name = "Block"
	mi.mesh = _box_mesh(size)
	mi.material_override = _mat(kind, q)
	mi.set_instance_shader_parameter("bsize", size)
	if color != Color.WHITE:
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
	for e in _get_extras(kind, size, q):
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
	return root


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

static func _box_mesh(sz: Vector3) -> ArrayMesh:
	var key := "%.3f|%.3f|%.3f" % [sz.x, sz.y, sz.z]
	if _meshes.has(key):
		return _meshes[key]
	var hx := sz.x / 2.0
	var hz := sz.z / 2.0
	var top := sz.y
	var b := minf(clampf(minf(sz.x, sz.z) * 0.035, 0.02, 0.07), sz.y * 0.45)
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
					out.append([_multi(_rock(), xf, cols), _clods_mat(), no_shadow])
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
					out.append([_multi(_rock(), pxf, pcols), _stones_mat(), no_shadow])
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
					out.append([_multi(_rock(), xf, cols), _stones_mat(), no_shadow])
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
	out.append([_multi(_rock(), xf, cols), _stones_mat(), shadow])


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


# ---- shared meshes ----

# A chunky faceted pebble about 2 units across (scaled per instance).
static func _rock() -> ArrayMesh:
	if _rock_mesh != null:
		return _rock_mesh
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 8
	sm.rings = 5
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
