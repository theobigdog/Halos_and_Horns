# A bouncy: step on it and it flings you high into the air (angels, demons,
# minions, everyone). Three kinds (Ted, Nov 19): one-use pads are wooden, permanent ones are
# solid metal, and super-bouncy ones are magical and shiny and throw you much higher. Alarm Cherubs and Vacuum Orbs that land on one go
# bouncing off too (cherub.gd's bounce_from, projectile.gd's bounces_on_pads). Permanent ones are part of the map; one-use ones vanish
# after their first bounce for the rest of the round.
#
# Each player's own game bounces them (movement is theirs to report); using up a
# one-use bouncy goes through the decider so everyone sees it go.
extends Node3D

const Surfaces = preload("res://scripts/surfaces.gd")

# Ted, Nov 19: higher (1.5x the height: speed x 1.22). First guesses.
const BOUNCE_VELOCITY := 18.4     # about 13 m up
const SUPER_BOUNCE_VELOCITY := 26.9   # about 27 m up (the map's ceiling stops it a bit lower on most maps)
const RADIUS := 0.9

var bouncy_id := 0
var one_use := false
var super_bouncy := false
var skin := 0                     # which colour (SKINS: Ted, Nov 24)

# Colours for each kind of pad: [name, base, top, trim/coil]
const SKINS := {
	"wood": [["Oak", Color(0.36, 0.22, 0.12), Color(0.62, 0.42, 0.24), Color(0.45, 0.45, 0.48)],
		["Dark walnut", Color(0.2, 0.12, 0.07), Color(0.36, 0.22, 0.13), Color(0.4, 0.4, 0.42)],
		["Birch", Color(0.6, 0.52, 0.4), Color(0.88, 0.8, 0.64), Color(0.5, 0.5, 0.52)],
		["Painted red", Color(0.3, 0.1, 0.08), Color(0.72, 0.16, 0.12), Color(0.85, 0.75, 0.4)],
		["Painted blue", Color(0.12, 0.16, 0.3), Color(0.2, 0.38, 0.72), Color(0.9, 0.9, 0.92)]],
	"metal": [["Steel", Color(0.32, 0.33, 0.36), Color(0.78, 0.8, 0.84), Color(0.7, 0.72, 0.76)],
		["Brass", Color(0.35, 0.27, 0.12), Color(0.85, 0.66, 0.3), Color(0.9, 0.75, 0.4)],
		["Copper", Color(0.3, 0.15, 0.1), Color(0.8, 0.45, 0.3), Color(0.55, 0.75, 0.65)],
		["Black iron", Color(0.12, 0.12, 0.13), Color(0.26, 0.26, 0.28), Color(0.6, 0.18, 0.12)],
		["Painted green", Color(0.12, 0.25, 0.15), Color(0.3, 0.62, 0.36), Color(0.9, 0.9, 0.85)]],
	# (Ted, Nov 27: "change the pattern on the Super Bouncy to something like" a heaven-and-hell yin-yang: the first
	# look now, so new pads and old ones on their first look get it; the others follow it)
	"super": [["Heaven & Hell", Color(0.12, 0.1, 0.16), Color(0.55, 0.55, 0.6), Color(0.85, 0.86, 0.92)],
		["Amethyst", Color(0.2, 0.12, 0.35), Color(0.35, 0.2, 0.7), Color(1.0, 0.8, 0.35)],
		["Emerald", Color(0.06, 0.25, 0.15), Color(0.1, 0.65, 0.4), Color(0.85, 1.0, 0.7)],
		["Ruby", Color(0.3, 0.05, 0.08), Color(0.75, 0.08, 0.2), Color(1.0, 0.8, 0.35)],
		["Sapphire", Color(0.06, 0.1, 0.3), Color(0.15, 0.35, 0.9), Color(0.75, 0.9, 1.0)],
		["Rainbow", Color(0.15, 0.15, 0.2), Color(0.8, 0.3, 0.5), Color(1.0, 1.0, 1.0)]],
}


static func skin_names(kind: String) -> Array:
	return SKINS[kind].map(func(s): return s[0])
var _magic: StandardMaterial3D    # the super pad's cushion: its colour drifts
var _magic_time := 0.0
var _rainbow := false
var _hue := 0.74
var _runes: Node3D
var _sparkles := []            # [mesh, spot, phase]
var on_used: Callable             # main: a one-use bouncy was used
var _used := false
var _top: MeshInstance3D
var _squish := 0.0


func _ready() -> void:
	# The base you can stand on
	var base := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS
	cyl.height = 0.25
	shape.shape = cyl
	shape.position.y = 0.125
	base.add_child(shape)
	base.add_to_group("bouncy_pad")   # thrown things that hit it bounce (projectile.gd)
	add_child(base)
	_build_look()
	# The trigger: anyone landing on (or walking onto) the cushion
	var area := Area3D.new()
	var tshape := CollisionShape3D.new()
	var tcyl := CylinderShape3D.new()
	tcyl.radius = RADIUS + 0.2       # (walking up against its edge counts too)
	tcyl.height = 0.9
	tshape.shape = tcyl
	tshape.position.y = 0.45
	area.add_child(tshape)
	area.monitorable = false
	area.body_entered.connect(_on_body_entered)
	add_child(area)


func velocity() -> float:
	return SUPER_BOUNCE_VELOCITY if super_bouncy else BOUNCE_VELOCITY


func _build_look() -> void:
	var kind := "super" if super_bouncy else ("wood" if one_use else "metal")
	var sk: Array = SKINS[kind][clampi(skin, 0, SKINS[kind].size() - 1)]
	_rainbow = kind == "super" and sk[0] == "Rainbow"
	_hue = sk[2].h
	# The base plate it all sits on
	var base := _disc(RADIUS, RADIUS, 0.08, 0.04)
	base.material_override = _surface(sk[1], "wood" if kind == "wood" else "metal")
	# The coil
	var coil: Color = sk[3]
	for i in 3:
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.rings = 32   # (Godot's default 64 x 32 is ~4000 triangles; Nov 26 audit)
		t.ring_segments = 12
		t.inner_radius = RADIUS * 0.55
		t.outer_radius = RADIUS * 0.7
		ring.mesh = t
		ring.material_override = _surface(coil, "metal")
		ring.position.y = 0.1 + i * 0.06
		add_child(ring)
	# The top you land on
	_top = _disc(RADIUS, RADIUS * 0.9, 0.12, 0.28)
	match kind:
		"wood":
			# A round wooden lid: grainy planks with dark gaps, held by an iron band
			var lid := _surface(sk[2], "wood")
			lid.uv1_scale = Vector3(2.0, 2.0, 2.0 / 7.0)   # grain running along the planks (the top face)
			_top.material_override = lid
			for i in range(-2, 3):
				var gap := MeshInstance3D.new()
				var b := BoxMesh.new()
				b.size = Vector3(0.025, 0.01, sqrt(maxf(RADIUS * RADIUS - pow(i * 0.33, 2.0), 0.01)) * 2.0 - 0.06)
				gap.mesh = b
				gap.material_override = _plain((sk[2] as Color).darkened(0.65))
				gap.position = Vector3(i * 0.33 + 0.165, 0.065, 0)
				_top.add_child(gap)
			var band := MeshInstance3D.new()
			var tb := TorusMesh.new()
			tb.rings = 32   # (Godot's default 64 x 32 is ~4000 triangles; Nov 26 audit)
			tb.ring_segments = 12
			tb.inner_radius = RADIUS - 0.04
			tb.outer_radius = RADIUS + 0.03
			band.mesh = tb
			band.material_override = _surface((sk[3] as Color).darkened(0.45), "metal")
			band.scale.y = 0.6
			_top.add_child(band)
		"metal":
			# A riveted steel plate
			var plate := _surface(sk[2], "metal")
			plate.metallic = 0.5   # (fully metal looks black wherever there's little sky to reflect)
			_top.material_override = plate
			for i in 8:
				var rivet := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radial_segments = 8   # (Godot's default is 64 x 32: ~4000 triangles each; Nov 26 audit)
				sm.rings = 4
				sm.radius = 0.045
				sm.height = 0.05
				rivet.mesh = sm
				rivet.material_override = _surface((sk[3] as Color).darkened(0.35), "metal")
				var a := TAU * i / 8.0
				rivet.position = Vector3(cos(a), 0, sin(a)) * (RADIUS - 0.12) + Vector3.UP * 0.06
				_top.add_child(rivet)
		"super" when sk[0] == "Heaven & Hell":
			_top.material_override = _yin_yang()
			var rim2 := MeshInstance3D.new()
			var tr2 := TorusMesh.new()
			tr2.rings = 32
			tr2.ring_segments = 12
			tr2.inner_radius = RADIUS - 0.05
			tr2.outer_radius = RADIUS + 0.04
			rim2.mesh = tr2
			var silver := StandardMaterial3D.new()
			silver.albedo_color = sk[3]
			silver.metallic = 0.9
			silver.roughness = 0.2
			rim2.material_override = silver
			rim2.scale.y = 0.6
			rim2.position.y = 0.05
			_top.add_child(rim2)
		"super":
			# Magic: glassy, glowing, colour slowly shifting, with sparkles rising off it
			_magic = StandardMaterial3D.new()
			_magic.albedo_color = sk[2]
			_magic.metallic = 0.6
			_magic.roughness = 0.1
			_magic.emission_enabled = true
			_magic.emission = sk[2]
			_magic.emission_energy_multiplier = 0.7
			_magic.clearcoat_enabled = true
			_top.material_override = _magic
			# A glowing gold rim, and a ring of runes (little glowing stars) slowly turning on top
			var rim := MeshInstance3D.new()
			var tr := TorusMesh.new()
			tr.rings = 32   # (Godot's default 64 x 32 is ~4000 triangles; Nov 26 audit)
			tr.ring_segments = 12
			tr.inner_radius = RADIUS - 0.06
			tr.outer_radius = RADIUS + 0.04
			rim.mesh = tr
			rim.material_override = _mat(sk[3], true)
			rim.scale.y = 0.6
			rim.position.y = 0.05
			_top.add_child(rim)
			_runes = Node3D.new()
			_runes.position.y = 0.065
			_top.add_child(_runes)
			for i in 7:
				var star := MeshInstance3D.new()
				var pm := PrismMesh.new()
				pm.size = Vector3(0.16, 0.16, 0.01)
				star.mesh = pm
				star.material_override = _mat(Color(1.0, 0.92, 0.6), true)
				var a := TAU * i / 7.0
				star.position = Vector3(cos(a), 0, sin(a)) * RADIUS * 0.6
				star.rotation = Vector3(-PI / 2, -a, 0)
				_runes.add_child(star)
			var core := MeshInstance3D.new()
			var cc := CylinderMesh.new()
			cc.top_radius = RADIUS * 0.28
			cc.bottom_radius = RADIUS * 0.28
			cc.height = 0.01
			cc.radial_segments = 24
			cc.rings = 1
			core.mesh = cc
			core.material_override = _mat(Color(1.0, 0.9, 1.0), true)
			core.position.y = 0.065
			_top.add_child(core)
			# Sparkles rising off it, animated by hand (particle systems would use the shared random numbers)
			var mote := SphereMesh.new()
			mote.radius = 0.035
			mote.height = 0.07
			mote.radial_segments = 6
			mote.rings = 3
			mote.material = _mat(Color(1.0, 0.9, 1.0), true)
			for i in 10:
				var mi := MeshInstance3D.new()
				mi.mesh = mote
				add_child(mi)
				var a := TAU * i / 10.0
				_sparkles.append([mi, Vector3(cos(a), 0, sin(a)) * RADIUS * (0.3 + 0.5 * fmod(i * 0.37, 1.0)), fmod(i * 0.618, 1.0)])


# Heaven and hell swirled together as a yin-yang on top of the pad (Ted, Nov 27, with a picture; redone Nov 28 to
# look like it: the first try was pastel clouds). Deep space on one side: near-black, with violet and blue nebula,
# thin teal and pink filaments, stars of every size and colour (thick as glitter along the seam) and one bright
# star with long rays. Fire on the other: black char with glowing cracks, tongues of flame from deep red to
# yellow-white, sparks drifting (a few over the seam into the stars). A dark red eye in each: a smoke ring round
# the one in the fire, a thin ring of light round the one in the stars. A fine metal band round the lot, silver
# on the star side and copper on the fire side. The whole picture turns slowly as one. It is drawn as its own
# light (emission), so it stays dark and rich in full sun. All in the shader (time-driven, no particles), shared
# by every such pad.
const YIN_YANG := """
shader_type spatial;
render_mode cull_back;
varying vec3 lp;
float h(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float n2(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
float fbm(vec2 p) { float v = 0.0, a = 0.5; for (int k = 0; k < 5; k++) { v += a * n2(p); p = p * 2.03 + 3.1; a *= 0.5; } return v; }
// one layer of stars: `cells` to the metre, `dens` of the cells lit, each star `size` of its cell across
float star_layer(vec2 p, float cells, float dens, float size, out vec3 tint) {
	vec2 g = p * cells;
	vec2 id = floor(g);
	float rnd = h(id);
	vec2 off = vec2(h(id + 7.1), h(id + 13.7)) * 0.6 + 0.2;
	float d = length(fract(g) - off);
	float tw = 0.65 + 0.35 * sin(TIME * (1.5 + rnd * 5.0) + rnd * 40.0);
	float hue = h(id + 3.3);
	tint = hue < 0.6 ? vec3(1.0, 0.97, 1.0) : (hue < 0.75 ? vec3(0.65, 0.82, 1.0) : (hue < 0.9 ? vec3(1.0, 0.65, 0.95) : vec3(1.0, 0.88, 0.55)));
	return step(1.0 - dens, rnd) * smoothstep(size, 0.0, d) * tw;
}
// sparks: little streaks drifting along `drift`
float sparks(vec2 p, float cells, vec2 drift, float dens) {
	vec2 g = p * cells + drift * TIME;
	vec2 id = floor(g);
	float rnd = h(id);
	vec2 off = vec2(h(id + 5.1), h(id + 9.7)) * 0.6 + 0.2;
	float d = length((fract(g) - off) * vec2(1.0, 0.55));
	return step(1.0 - dens, rnd) * smoothstep(0.17, 0.0, d) * (0.55 + 0.45 * sin(TIME * 3.0 + rnd * 50.0));
}
void vertex() { lp = VERTEX; }
void fragment() {
	vec2 p0 = lp.xz;   // (the pad's radius is about 1 m)
	float r = length(p0) / 0.9;
	float t = TIME * 0.12;
	mat2 rot = mat2(vec2(cos(t), sin(t)), vec2(-sin(t), cos(t)));
	vec2 p = rot * (p0 / 0.9);
	// which half: the stars on the left with their head at the bottom, the fire on the right with its head on top
	float heaven = step(p.x, 0.0);
	if (length(p - vec2(0.0, 0.5)) < 0.5) heaven = 1.0;
	if (length(p - vec2(0.0, -0.5)) < 0.5) heaven = 0.0;
	// how far from the S between them (the left half of the top circle, the right half of the bottom one)
	float seam = min(abs(length(p - vec2(0.0, -0.5)) - 0.5) + step(0.0, p.x) * 9.0, abs(length(p - vec2(0.0, 0.5)) - 0.5) + step(p.x, 0.0) * 9.0);

	// ---- the stars ----
	vec2 q = p * 2.4;
	vec2 nw = vec2(fbm(q + vec2(TIME * 0.02, 3.0)), fbm(q + vec2(7.0, -TIME * 0.015)));
	float n1 = fbm(q + nw * 1.6);
	float fil = pow(1.0 - abs(2.0 * fbm(q * 0.9 + nw * 2.2 + 11.0) - 1.0), 3.0);   // soft wisps
	vec3 neb = vec3(0.012, 0.006, 0.035);
	neb = mix(neb, vec3(0.17, 0.05, 0.4), smoothstep(0.35, 0.7, n1));
	neb = mix(neb, vec3(0.07, 0.15, 0.55), smoothstep(0.5, 0.8, fbm(q * 1.5 + 4.0 + nw)) * 0.7);
	neb += vec3(0.75, 0.3, 0.85) * smoothstep(0.62, 0.9, n1) * 0.35;
	neb += vec3(0.2, 0.6, 0.8) * fil * 0.22;
	neb += vec3(0.85, 0.7, 1.0) * pow(fil, 4.0) * 0.3;
	vec3 tint;
	vec3 stars = vec3(0.0);
	float s1 = star_layer(p, 70.0, 0.35, 0.22, tint);
	stars += tint * s1 * 0.6;
	float s2 = star_layer(p + 3.7, 34.0, 0.16, 0.26, tint);
	stars += tint * s2 * 1.3;
	float s3 = star_layer(p + 9.1, 13.0, 0.12, 0.3, tint);
	stars += tint * s3 * 2.4;
	float s4 = star_layer(p + 5.5, 95.0, 0.6, 0.25, tint);
	stars += tint * s4 * smoothstep(0.26, 0.0, seam) * 1.0;
	// the bright star: a hot core, four long rays, four short ones, a violet halo
	vec2 dd = p - vec2(-0.46, 0.06);
	float core = 0.012 / (dot(dd, dd) + 0.0008);
	float rays = 0.0035 / (abs(dd.x) + 0.0035) * exp(-abs(dd.y) * 7.0) + 0.0035 / (abs(dd.y) + 0.0035) * exp(-abs(dd.x) * 7.0);
	vec2 dg = vec2(dd.x + dd.y, dd.x - dd.y) * 0.7071;
	float short_rays = 0.002 / (abs(dg.x) + 0.002) * exp(-abs(dg.y) * 16.0) + 0.002 / (abs(dg.y) + 0.002) * exp(-abs(dg.x) * 16.0);
	vec3 flare = vec3(1.0, 0.97, 1.0) * min(core * 0.35, 3.0) + vec3(0.9, 0.85, 1.0) * (rays + short_rays * 0.6) * 1.2
			+ vec3(0.6, 0.35, 0.95) * exp(-length(dd) * 9.0) * 0.6;
	flare *= 0.9 + 0.1 * sin(TIME * 2.3);
	vec3 heaven_c = neb + stars + flare;
	// a few sparks from the fire over the seam
	heaven_c += vec3(1.0, 0.45, 0.08) * sparks(p, 26.0, vec2(-0.5, -0.9), 0.3) * smoothstep(0.3, 0.02, seam) * 1.6;

	// ---- the fire ----
	vec2 fq = p * 2.6;
	vec2 warp = vec2(fbm(fq * 1.3 + vec2(1.7, -TIME * 0.35)), fbm(fq * 1.3 + vec2(8.3, -TIME * 0.28)));
	float f = fbm(fq + warp * 1.8 + vec2(0.0, -TIME * 0.25));
	float ridge = 1.0 - abs(2.0 * fbm(fq * 1.6 + warp * 2.4 + vec2(3.0, -TIME * 0.45)) - 1.0);
	float burns = smoothstep(0.36, 0.62, fbm(p * 1.5 + vec2(4.0, TIME * 0.05)));   // (the rest is black char)
	float heat = clamp((f * 1.12 + pow(ridge, 3.0) * 0.5) * burns, 0.0, 1.0);
	float cracks = pow(1.0 - abs(2.0 * fbm(p * 5.0 + 20.0) - 1.0), 8.0);
	vec3 fire = vec3(0.035, 0.012, 0.008) + vec3(0.3, 0.035, 0.0) * cracks * 0.6;
	fire = mix(fire, vec3(0.45, 0.03, 0.0), smoothstep(0.25, 0.45, heat));
	fire = mix(fire, vec3(0.95, 0.28, 0.02), smoothstep(0.42, 0.6, heat));
	fire = mix(fire, vec3(1.0, 0.62, 0.12), smoothstep(0.58, 0.75, heat));
	fire = mix(fire, vec3(1.0, 0.9, 0.55), smoothstep(0.84, 0.98, heat));
	vec3 hell_c = fire + vec3(1.0, 0.5, 0.1) * (sparks(p, 22.0, vec2(0.3, -1.1), 0.22) * 2.2 + sparks(p + 4.4, 40.0, vec2(-0.6, -1.6), 0.2) * 1.4);

	vec3 col = mix(hell_c, heaven_c, heaven);
	// the seam: a thin line of light
	col += vec3(0.95, 0.8, 1.0) * (0.0035 / (seam + 0.0035)) * 0.35;

	// ---- the two eyes: dark red balls ----
	for (int k = 0; k < 2; k++) {
		vec2 ec = vec2(0.0, k == 0 ? -0.5 : 0.5);
		float d = length(p - ec);
		float er = 0.14;
		vec2 nrm = (p - ec) / er;
		float sph = sqrt(max(0.0, 1.0 - dot(nrm, nrm)));
		vec3 ball = mix(vec3(0.05, 0.005, 0.005), vec3(0.42, 0.06, 0.03), pow(sph, 1.5) * (0.6 + 0.4 * n2(p * 30.0 + float(k) * 9.0)));
		ball += vec3(0.5, 0.12, 0.05) * pow(max(0.0, dot(normalize(vec3(nrm, sph)), normalize(vec3(-0.4, -0.5, 0.75)))), 6.0) * 0.4;
		if (k == 0) {
			// in the fire: a ring of grey smoke round it
			float smoke = smoothstep(er + 0.14, er + 0.01, d) * (0.5 + 0.7 * fbm(p * 9.0 + vec2(TIME * 0.1, 0.0)));
			col = mix(col, vec3(0.2, 0.17, 0.16) * (0.5 + 0.9 * fbm(p * 14.0 + 3.0)), clamp(smoke, 0.0, 0.9));
			col = mix(col, vec3(0.02, 0.01, 0.01), smoothstep(er + 0.035, er, d) * 0.8);
		} else {
			// in the stars: a thin ring of light
			col += vec3(0.95, 0.85, 1.0) * (0.004 / (abs(d - er - 0.012) + 0.004)) * 0.5 * smoothstep(er + 0.2, er, d);
		}
		col = mix(col, ball, smoothstep(er, er - 0.012, d));
	}
	// a fine metal band round it: silver by the stars, copper by the fire
	vec3 metal = mix(vec3(0.75, 0.72, 0.92), vec3(0.9, 0.48, 0.2), smoothstep(-0.5, 0.5, p.x));
	float band = smoothstep(0.022, 0.012, abs(r - 1.0));
	col = mix(col, metal * (0.55 + 0.45 * n2(vec2(atan(p.y, p.x) * 6.0, 2.0))), band);
	// outside it: dark
	col = mix(col, vec3(0.02, 0.02, 0.03), smoothstep(1.02, 1.035, r));
	col = pow(max(col, vec3(0.0)), vec3(2.2));   // (the colours above are as seen; light adds up in linear)
	ALBEDO = col * 0.12;
	EMISSION = col * 1.5;
	ROUGHNESS = 0.35;
	SPECULAR = 0.3;
}
"""
static var _yy_mat: ShaderMaterial


static func _yin_yang() -> ShaderMaterial:
	if _yy_mat == null:
		var sh := Shader.new()
		sh.code = YIN_YANG
		_yy_mat = ShaderMaterial.new()
		_yy_mat.shader = sh
	return _yy_mat


func _disc(top_r: float, bottom_r: float, h: float, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = h
	c.radial_segments = 40   # (round to a couple of millimetres at this size; the default is 64 x 4)
	c.rings = 1
	mi.mesh = c
	mi.position.y = y
	add_child(mi)
	return mi


func _surface(color: Color, kind: String) -> StandardMaterial3D:
	var m := _plain(color)
	Surfaces.apply(m, kind)
	return m


func _plain(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


func _mat(color: Color, glow: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 0.6
	return m


func _on_body_entered(body: Node) -> void:
	if _used:
		return
	if body.has_method("bounce_from"):   # an Alarm Cherub: it flies off, away from the middle
		if body.bounce_from(global_position, velocity()):   # (true only in the deciding game)
			squish()
			if one_use:
				shot()   # ...and that uses up a one-use pad, like a player would
		return
	if not body.has_method("bounce"):
		return
	if not body.bounce(velocity()):
		return
	_squish = 0.25
	if one_use and body.get("net_mode") != null:
		# Our own player used it up: tell the decider (it tells everyone).
		_used = true
		if on_used.is_valid():
			on_used.call(bouncy_id)


# Something an angel threw hit it (projectile.gd) or a cherub landed on it: a one-use pad is used up.
# Only the deciding game (host / practice) calls this; it tells everyone the pad's gone.
func shot() -> void:
	if not one_use or _used:
		return
	_used = true
	_squish = 0.25
	if on_used.is_valid():
		on_used.call(bouncy_id)


func squish() -> void:
	_squish = 0.25


func use_up() -> void:
	_used = true
	queue_free()


func _process(delta: float) -> void:
	if _magic:
		_magic_time += delta
		# (its colour drifts a little round its own hue; the rainbow one goes all the way round)
		var hue := fposmod(_magic_time * 0.12, 1.0) if _rainbow else fposmod(_hue + 0.06 * sin(_magic_time * 0.9), 1.0)
		var c := Color.from_hsv(hue, 0.75, 0.75)
		_magic.albedo_color = c
		_magic.emission = c
		_runes.rotation.y = _magic_time * 0.6
		for sp in _sparkles:
			var k := fmod(_magic_time * 0.7 + sp[2], 1.0)
			sp[0].position = sp[1] + Vector3(0, 0.35 + k * 1.4, 0)
			sp[0].scale = Vector3.ONE * sin(k * PI)
	if _squish > 0.0:
		_squish -= delta
		var s := 1.0 - 0.5 * sin(clampf(_squish / 0.25, 0.0, 1.0) * PI)
		_top.scale = Vector3(1.0 + (1.0 - s) * 0.3, s, 1.0 + (1.0 - s) * 0.3)
