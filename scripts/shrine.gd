# The one shrine on each map: the only place to swap skills mid-round.
# A carved two-step stone dais with a gold rim and a slowly turning ring of runes (holy gold on one
# half, demonic red on the other), two angel pillars with gold orbs and two horned demon pillars,
# gold sparkles and red embers drifting up, and a floating orb (gold on top, red underneath)
# inside two turning rings. Ted, Nov 19: "much more ornate". Only the look: its size and use are the same.
# When anyone uses it, a pillar of light shoots up and it chimes, so everyone
# on the map knows someone is standing there (and where to go pester them).
extends Node3D

const PropLib = preload("res://scripts/prop_library.gd")
const Sfx = preload("res://scripts/sfx.gd")

const RADIUS := 2.5           # how close you have to stand to use it
const SWAP_TIME := 3.0        # a swap takes this long in total

var _crystal: Node3D
var _pillar: MeshInstance3D
var _pillar_mat: StandardMaterial3D
var _voice: AudioStreamPlayer3D
var _glow := 0.0
var _runes: Node3D
var _rings := []               # the orb's two turning rings
var _halos := []               # the halos over the angel pillars
var _rune_mats := []
var _motes := []               # [mesh, base, speed, phase, drift]

static var _chime: AudioStreamWAV


func _ready() -> void:
	if _chime == null:
		_chime = Sfx.voice([[1047, 1047, 0.25, 0.8, 0.0], [1319, 1319, 0.25, 0.7, 0.0], [1568, 1568, 0.6, 0.6, 0.0]], 0.18, 0.0, 0.01, 0.01)
	var dais := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.6
	cyl.height = 0.25
	shape.shape = cyl
	shape.position.y = 0.125
	dais.add_child(shape)
	var dm := MeshInstance3D.new()
	var dmesh := CylinderMesh.new()
	dmesh.top_radius = 1.6
	dmesh.bottom_radius = 1.75
	dmesh.height = 0.25
	dm.mesh = dmesh
	dm.material_override = PropLib.mat(Color(0.75, 0.72, 0.68), "stone")
	dm.position.y = 0.125
	dais.add_child(dm)
	add_child(dais)
	_build_ornaments()

	_crystal = Node3D.new()
	_crystal.position.y = 1.6
	add_child(_crystal)
	# A big sparkly d20 (Wife's notes, Nov 21: the floating ball was dull): gold faces on top, ruby
	# underneath, glinting as it turns, numbered like a real one (opposite faces add up to 21).
	_crystal.add_child(_d20(0.34))

	_pillar = MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.9
	pm.bottom_radius = 0.9
	pm.height = 20.0
	_pillar.mesh = pm
	_pillar_mat = StandardMaterial3D.new()
	_pillar_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pillar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pillar_mat.albedo_color = Color(1.0, 0.95, 0.75, 0.0)
	_pillar.material_override = _pillar_mat
	_pillar.position.y = 10.0
	_pillar.visible = false
	add_child(_pillar)

	# A label over it so people can find it and know what it's for.
	var sign := Label3D.new()
	sign.text = "SHRINE\n%s: swap skills" % preload("res://scripts/keybinds.gd").key_name("shrine")
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.font_size = 48
	sign.outline_size = 10
	sign.pixel_size = 0.01
	sign.modulate = Color(1.0, 0.93, 0.7)
	sign.position.y = 2.7
	add_child(sign)

	_voice = AudioStreamPlayer3D.new()
	_voice.bus = Sfx.BUS
	_voice.unit_size = 12.0
	_voice.max_distance = 120.0
	_voice.position.y = 1.5
	add_child(_voice)


const HOLY := Color(1.0, 0.85, 0.35)

const SIGIL_SHADER := """
shader_type spatial;
render_mode cull_disabled;
// false on Low graphics: no weave, folds, spatter or fraying (just the aged colours)
uniform bool detail = true;
// a fract-based hash: the usual sin() one loses precision far from the origin, and neighbouring noise
// cells then disagree, which shows up as hard-edged squares
float h(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
// octaves turned against each other, so thresholded noise doesn't show the square grid it's built on
const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * n2(p); p = ROT * p * 2.07 + 3.1; a *= 0.5; } return v; }
float fbm3(vec2 p) { p = mat2(vec2(0.6, -0.8), vec2(0.8, 0.6)) * p; float v = 0.0; float a = 0.5; for (int i = 0; i < 3; i++) { v += a * n2(p); p = ROT * p * 2.13 + 1.7; a *= 0.5; } return v / 0.875; }
// distance from p to the segment a-b
float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a; vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}
// a blocky rune: a 4x4 grid of strokes picked by the rune's number
float rune(vec2 p, float id) {
	if (abs(p.x) > 0.5 || abs(p.y) > 0.5) return 0.0;
	vec2 g = floor((p + 0.5) * 4.0);
	vec2 f = fract((p + 0.5) * 4.0);
	float on = step(0.45, h(g + id * 17.3));
	float bar = h(g * 3.1 + id) > 0.5 ? step(abs(f.y - 0.5), 0.22) : step(abs(f.x - 0.5), 0.22);
	return on * bar;
}
// plain-woven cloth: the height of the threads (1 on top of a thread, 0 in the gaps between them)
float weave(vec2 p, float F) {
	vec2 q = p * F;
	vec2 c = floor(q);
	vec2 f = fract(q);
	float over = mod(c.x + c.y, 2.0);
	float wx = sin(3.14159 * f.x);
	float wy = sin(3.14159 * f.y);
	return over > 0.5 ? wx * (0.55 + 0.45 * wy) : wy * (0.55 + 0.45 * wx);
}
// slow folds and creases in the cloth
float folds(vec2 p) {
	float a = sin(dot(p, vec2(0.83, 0.56)) * 11.0 + n2(p * 1.6) * 4.0) * smoothstep(0.35, 0.75, n2(p * 1.3 + 9.0));
	float b = sin(dot(p, vec2(-0.4, 0.92)) * 17.0 + n2(p * 2.1 + 4.0) * 5.0) * smoothstep(0.45, 0.8, n2(p * 1.7 + 2.0));
	return a + b * 0.5;
}
void fragment() {
	vec2 p = (UV - 0.5) * 2.24;           // metres from the middle
	float r = length(p);
	float ang = atan(p.y, p.x);
	// the ragged, charred edge of the cloth, with loose threads hanging off it
	float edge = 1.07 + (fbm(vec2(ang * 3.0, 1.0)) - 0.5) * 0.08 + (n2(vec2(ang * 40.0, 2.0)) - 0.5) * 0.02;
	float fibre = 0.0;
	if (r > edge) {
		if (!detail) discard;
		float fa = ang / 6.28318 * 420.0;
		float wig = sin(r * 70.0 + floor(fa) * 1.7) * 0.12;
		float ln = step(0.45, h(vec2(floor(fa), 5.0))) * pow(h(vec2(floor(fa), 3.0)), 2.0) * 0.04;
		if (r > edge + ln || abs(fract(fa + wig) - 0.5) > 0.22) discard;
		fibre = 1.0;
	}
	float grime = fbm(p * 3.0);
	float blotch = fbm(p * 1.4 + 7.0);
	// threadbare patches: the dye and the nap worn off, showing a coarser, looser weave (and the odd hole)
	float bare = smoothstep(0.6, 0.72, fbm3(p * 2.3 + 40.0) + smoothstep(0.9, 1.07, r) * 0.18);
	float F = mix(180.0, 80.0, step(0.5, bare));
	float wv = detail ? weave(p, F) : 0.6;
	// threads smaller than a pixel would shimmer: fade the weave out with distance
	float wfade = detail ? 1.0 - smoothstep(0.25, 0.6, fwidth(p.x * F) + fwidth(p.y * F)) : 0.0;
	if (detail && bare > 0.9 && wv < 0.06 && n2(p * 7.0 + 5.0) > 0.7) discard;
	vec3 crimson = mix(vec3(0.11, 0.008, 0.018), vec3(0.22, 0.014, 0.032), smoothstep(0.3, 0.75, blotch));
	crimson = mix(crimson, vec3(0.08, 0.035, 0.04), smoothstep(0.58, 0.72, fbm(p * 2.2 + 3.0)) * 0.8);   // dark scorch patches
	vec3 char_col = mix(vec3(0.03, 0.025, 0.03), vec3(0.2, 0.025, 0.04), smoothstep(0.55, 0.8, fbm(p * 2.6 + 11.0)));
	vec3 col = r > 0.86 ? char_col : crimson;
	// the star filled a richer crimson, the panels round it darker
	float R1 = 0.7;
	float R2 = 0.3;
	float a0 = ang - 1.5708;
	float k = 6.28318 / 5.0;
	float m = mod(a0 + k * 0.5, k) - k * 0.5;
	vec2 q = r * vec2(cos(m), abs(sin(m)));
	vec2 t0 = vec2(R1, 0.0);
	vec2 c0 = R2 * vec2(cos(k * 0.5), sin(k * 0.5));
	vec2 e = c0 - t0;
	float star = step((q.x - t0.x) * e.y - (q.y - t0.y) * e.x, 0.0);
	col = mix(col, mix(vec3(0.2, 0.011, 0.03), vec3(0.3, 0.018, 0.045), blotch), star * 0.9);
	float pent_r = R1 * cos(k * 0.5) / cos(m);
	float panel = (1.0 - star) * step(r, pent_r);
	col = mix(col, col * 0.55, panel);
	// gold: one distance to the nearest gold line (rings, studs, star, pentagon, spokes), so grime can
	// gather along the edges of the gold leaf
	float saw = (n2(vec2(ang * 120.0, r * 60.0)) - 0.5) * 0.006;      // the slightly chewed edges
	float gd = abs(r - 0.97) - 0.03;
	gd = min(gd, abs(r - 0.81) - 0.045);
	for (int i = 0; i < 9; i++) {
		float a = 6.28318 * (float(i) + 0.5) / 9.0;
		gd = min(gd, length(p - vec2(cos(a), sin(a)) * 0.885) - 0.027);
	}
	float line_d = 9.0;
	for (int i = 0; i < 5; i++) {
		float at = 1.5708 + 6.28318 * float(i) / 5.0;
		float ac = at + 6.28318 / 10.0;
		float an = at + 6.28318 / 5.0;
		vec2 tip = vec2(cos(at), sin(at)) * R1;
		vec2 cor = vec2(cos(ac), sin(ac)) * R2;
		vec2 nxt = vec2(cos(an), sin(an)) * R1;
		line_d = min(line_d, seg(p, tip, cor));
		line_d = min(line_d, seg(p, cor, nxt));
		line_d = min(line_d, seg(p, tip, nxt));
		line_d = min(line_d, seg(p, tip, vec2(cos(at), sin(at)) * 0.8));
	}
	gd = min(gd, line_d - 0.03) + saw;
	float gold = 1.0 - smoothstep(0.0, 0.008, gd);
	for (int i = 0; i < 5; i++) {
		float a = 1.5708 + 6.28318 * (float(i) + 0.5) / 5.0;
		vec2 c = vec2(cos(a), sin(a)) * 0.47;
		vec2 lp = mat2(vec2(cos(a - 1.5708), sin(a - 1.5708)), vec2(-sin(a - 1.5708), cos(a - 1.5708))) * (p - c);
		gold = max(gold, rune(lp / 0.17, float(i) + 1.0));
	}
	// old gold leaf: flaked off in little chips where it is most worn, tarnished brown-green in patches,
	// and gone entirely on the threadbare bits
	float wear = fbm3(p * 3.0 + 21.0);
	vec2 fc = floor(p * 55.0 + vec2(n2(p * 30.0), n2(p * 30.0 + 7.0)) * 1.5);
	float flaked = step(1.75 - wear * 1.6, h(fc));
	float gold_left = gold * (1.0 - flaked * 0.9) * (1.0 - bare * 0.85);
	float tarnish = smoothstep(0.3, 0.8, grime);
	vec3 gold_col = mix(vec3(0.55, 0.35, 0.07), vec3(0.27, 0.17, 0.06), tarnish);
	gold_col = mix(gold_col, vec3(0.27, 0.26, 0.13), smoothstep(0.6, 0.8, fbm3(p * 5.0 + 33.0)) * 0.6);
	// where a chip came off, a darker rim of old size (glue) and dirt
	col = mix(col, col * 0.6 + vec3(0.04, 0.025, 0.01), gold * flaked);
	col = mix(col, gold_col, gold_left);
	// grime packed in along the edges of the gold
	float recess = 1.0 - smoothstep(0.0, 0.018, abs(gd));
	col *= 1.0 - recess * 0.45 * (0.6 + 0.4 * grime);
	// threadbare: faded to the dull backing
	vec3 backing = vec3(0.24, 0.16, 0.12) * (0.75 + 0.5 * grime);
	col = mix(col, mix(backing, col, 0.35), bare * 0.85);
	// sun-faded, a touch greyed overall
	float lum = dot(col, vec3(0.3, 0.55, 0.15));
	col = mix(col, vec3(lum) * vec3(1.1, 0.95, 0.85), 0.12 * (1.0 - gold_left));
	// old blood: a couple of faded brown stains with darker dried rims, and a light spatter
	vec2 c1 = vec2(0.32, -0.28);
	vec2 c2 = vec2(-0.45, 0.4);
	vec2 c3 = vec2(-0.75, -0.55);
	float S = fbm3(p * 3.1 + 5.0) - 0.62 + 0.5 * exp(-dot(p - c1, p - c1) * 9.0) + 0.42 * exp(-dot(p - c2, p - c2) * 14.0)
			+ 0.3 * exp(-dot(p - c3, p - c3) * 30.0);
	float stain = smoothstep(0.0, 0.03, S);
	float rim = stain * (1.0 - smoothstep(0.015, 0.06, S));
	float spat = 0.0;
	if (detail) {
		for (int s = 0; s < 2; s++) {
			float sc = s == 0 ? 22.0 : 45.0;
			vec2 g = floor(p * sc);
			vec2 f = fract(p * sc) - 0.5;
			float hh = h(g + float(s) * 31.0);
			float near = exp(-length(p - c1) * 2.2) + 0.7 * exp(-length(p - c2) * 3.0);
			vec2 o = (vec2(h(g + 1.3), h(g + 7.7)) - 0.5) * 0.5;
			float rad = 0.12 + 0.25 * h(g + 4.1);
			spat = max(spat, step(1.0 - near * 0.35, hh) * (1.0 - smoothstep(rad * 0.75, rad, length(f - o))));
		}
	}
	float blood = max(stain * 0.55 + rim * 0.45, spat * 0.75);
	col = mix(col, col * vec3(0.42, 0.3, 0.24) + vec3(0.045, 0.02, 0.01), blood);
	// soot and grime ground into the weave: darkest at the charred rim and down between the threads
	float soot = smoothstep(0.4, 0.85, fbm3(p * 4.0 + 50.0)) * 0.5 + smoothstep(0.8, 1.07, r) * 0.4;
	col *= 1.0 - soot * 0.55;
	col *= mix(1.0, mix(0.7, 1.05, wv) * (1.0 + 0.12 * (h(floor(p * F * vec2(1.0, 0.1))) - 0.5)), wfade);
	// the weave and the folds, as bumps
	float fold = 0.0;
	vec3 nm = vec3(0.0, 0.0, 1.0);
	if (detail) {
		float ep = 0.2 / F;
		float wx = weave(p + vec2(ep, 0.0), F) - wv;
		float wy = weave(p + vec2(0.0, ep), F) - wv;
		float fe = 0.01;
		fold = folds(p);
		float fx = folds(p + vec2(fe, 0.0)) - fold;
		float fy = folds(p + vec2(0.0, fe)) - fold;
		vec2 grad = vec2(wx, wy) / ep * (0.3 / F) * (1.0 - fibre) * wfade + vec2(fx, fy) / fe * 0.012;
		nm = normalize(vec3(-grad.x, grad.y, 1.0));
	}
	// dust settled in the low parts of the folds and over everything a little
	float dust = smoothstep(0.4, 0.9, fbm3(p * 5.0 + 70.0)) * 0.14 + max(-fold, 0.0) * 0.08;
	col = mix(col, vec3(0.3, 0.25, 0.2), clamp(dust, 0.0, 1.0) * (1.0 - gold_left * 0.5));
	col = mix(col, vec3(0.07, 0.05, 0.045) * (0.6 + 0.6 * grime), fibre * 0.85);
	ALBEDO = col;
	NORMAL_MAP = nm * 0.5 + 0.5;
	METALLIC = gold_left * 0.4 * (1.0 - tarnish * 0.5);
	ROUGHNESS = clamp(mix(0.95, 0.42 + tarnish * 0.25, gold_left) + dust * 0.2, 0.0, 1.0);
	SPECULAR = mix(0.12, 0.55, gold_left);
}
"""

const D20_SHADER := """
shader_type spatial;
varying float face;
void vertex() { face = UV.x; }
void fragment() {
	vec3 c = COLOR.rgb;
	// each face glints now and then (a slow twinkle, different per face) on top of the real reflections
	float tw = pow(max(sin(TIME * 2.3 + face * 7.13) * 0.5 + 0.5, 0.0), 12.0);
	ALBEDO = c;
	METALLIC = 0.55;
	ROUGHNESS = 0.2;
	EMISSION = c * (0.08 + tw * 2.5);
}
"""


# An icosahedron with flat faces (gold above, ruby below) and the numbers 1-20 on them.
func _d20(r: float) -> Node3D:
	var n := Node3D.new()
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array[Vector3] = []
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			v.append(Vector3(0, a, b * t))
			v.append(Vector3(a, b * t, 0))
			v.append(Vector3(b * t, 0, a))
	# stand it on a point, one corner straight up (Ted, Nov 24: a tidier pattern)
	var turn := Quaternion(Vector3(0, 1, t).normalized(), Vector3.UP)
	for i in v.size():
		v[i] = turn * v[i]
	var faces := []
	for i in v.size():
		for j in range(i + 1, v.size()):
			for k in range(j + 1, v.size()):
				if absf(v[i].distance_to(v[j]) - 2.0) < 0.01 and absf(v[j].distance_to(v[k]) - 2.0) < 0.01 \
						and absf(v[i].distance_to(v[k]) - 2.0) < 0.01:
					faces.append([v[i], v[j], v[k]])
	# number them so opposite faces add up to 21
	var nums := {}
	var next := 1
	for fi in faces.size():
		if nums.has(fi):
			continue
		var c: Vector3 = (faces[fi][0] + faces[fi][1] + faces[fi][2]) / 3.0
		for fj in faces.size():
			var cj: Vector3 = (faces[fj][0] + faces[fj][1] + faces[fj][2]) / 3.0
			if (cj + c).length() < 0.01:
				nums[fi] = next
				nums[fj] = 21 - next
		next += 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sc := r / sqrt(1.0 + t * t)
	var gold_c := Color(0.8, 0.52, 0.08)
	var ruby_c := Color(0.5, 0.01, 0.03)
	for fi in faces.size():
		var f: Array = faces[fi]
		var c: Vector3 = (f[0] + f[1] + f[2]) / 3.0
		var nrm := c.normalized()
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var d: Vector3 = f[2]
		if (b - a).cross(d - a).dot(nrm) > 0.0:   # (Godot wants clockwise from the outside)
			var tmp := b
			b = d
			d = tmp
		# a gold crown of five faces on top, a zigzag band of alternating ruby and gold round the
		# middle, and a ruby cap underneath
		var ny := c.normalized().y
		var upper := ny > 0.5 or (ny < 0.0 and ny > -0.5)
		var col := gold_c if upper else ruby_c
		for q in [a, b, d]:
			st.set_normal(nrm)
			st.set_color(col)
			st.set_uv(Vector2(float(fi), 0.0))
			st.add_vertex(q * sc)
		# its number, flat on the face
		var lbl := Label3D.new()
		lbl.text = str(nums.get(fi, fi + 1))
		lbl.font_size = 64
		lbl.pixel_size = 0.0022
		lbl.outline_size = 0
		lbl.modulate = Color(0.3, 0.1, 0.02) if upper else Color(1.0, 0.9, 0.6)
		lbl.double_sided = false
		lbl.shaded = false
		lbl.basis = Basis.looking_at(-nrm, Vector3.UP if absf(nrm.y) < 0.95 else Vector3.FORWARD)
		lbl.position = c * sc * 1.03
		n.add_child(lbl)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = D20_SHADER
	mat.shader = sh
	mi.material_override = mat
	n.add_child(mi)
	return n

const HELL := Color(0.95, 0.15, 0.08)


func _glow_mat(c: Color, energy := 1.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	(parent if parent else self).add_child(mi)
	return mi


func _cyl(top: float, bottom: float, h: float, sides := 24) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = sides
	return c


func _build_ornaments() -> void:
	var stone := PropLib.mat(Color(0.82, 0.8, 0.76), "stone")
	var dark := PropLib.mat(Color(0.22, 0.18, 0.2), "stone")
	var gold := PropLib.mat(Color(0.95, 0.75, 0.3), "metal")
	# A smaller second step on top, and a gold band around the edge
	_mesh(_cyl(1.15, 1.25, 0.12), stone, Vector3(0, 0.31, 0))
	var band := TorusMesh.new()
	band.inner_radius = 1.62
	band.outer_radius = 1.72
	_mesh(band, gold, Vector3(0, 0.24, 0)).scale.y = 0.5
	# The sigil rug under the d20 (Ted, Nov 25, from a picture he liked): a charred, ragged-edged cloth,
	# two worn gold rings studded with gold dots, a crimson field, a gold pentagram with the star filled
	# in, and a gold rune in each of the five panels between its points. All drawn by a shader.
	# Ted, Nov 25 later: aged to match the grimy models: a woven texture with folds, threadbare patches,
	# frayed threads at the edge, soot, dust, faded old blood stains, and flaking tarnished gold.
	var rug := MeshInstance3D.new()
	var rq := PlaneMesh.new()
	rq.size = Vector2(2.24, 2.24)
	rug.mesh = rq
	var rug_mat := ShaderMaterial.new()
	var rug_sh := Shader.new()
	rug_sh.code = SIGIL_SHADER
	rug_mat.shader = rug_sh
	rug_mat.set_shader_parameter("detail", preload("res://scripts/graphics.gd").quality > 0)
	rug.material_override = rug_mat
	rug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rug.position.y = 0.373
	add_child(rug)
	# The rune ring: glowing glyphs laid in the top, gold on the heavenly half, red on the hellish half
	_runes = Node3D.new()
	_runes.position.y = 0.255
	add_child(_runes)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1777   # the same runes on every screen
	var count := 14
	for i in count:
		var a := TAU * (i + 0.5) / count
		var holy := i < count / 2
		var mat := _gold_mat() if holy else _glow_mat(HELL, 1.3)
		if not holy:
			_rune_mats.append(mat)
		var glyph := Node3D.new()
		glyph.position = Vector3(cos(a), 0, sin(a)) * 1.38
		glyph.rotation.y = -a + PI / 2
		_runes.add_child(glyph)
		# Each rune: a stem and two or three strokes, a different shape every time
		_mesh(_box(Vector3(0.035, 0.01, 0.26)), mat, Vector3.ZERO, glyph)
		for k in rng.randi_range(2, 3):
			var stroke := _mesh(_box(Vector3(0.03, 0.01, rng.randf_range(0.1, 0.18))), mat,
					Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.1, 0.1)), glyph)
			stroke.rotation.y = rng.randf_range(-1.2, 1.2)
		if holy and i % 2 == 0:   # some holy runes get a little ring
			var ring := TorusMesh.new()
			ring.inner_radius = 0.06
			ring.outer_radius = 0.085
			_mesh(ring, mat, Vector3(0, 0, -0.17), glyph).scale.y = 0.2
	# Four pillars at the corners of the dais, angels and demons facing each other across it (Ted, Nov 20):
	# ivory angel pillars with a floating halo, dark demon pillars topped with horns and a trident.
	var ivory := PropLib.mat(Color(1.0, 0.96, 0.86), "marble")
	ivory.roughness = 0.25
	var iron := PropLib.mat(Color(0.2, 0.17, 0.17), "metal")
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var at := Vector3(cos(a), 0, sin(a)) * 1.45
		var holy := k % 2 == 0   # opposite corners match
		var pil := Node3D.new()
		pil.position = at + Vector3(0, 0.25, 0)
		add_child(pil)
		_mesh(_cyl(0.11, 0.15, 0.12, 12 if holy else 8), gold if holy else dark, Vector3(0, 0.06, 0), pil)
		_mesh(_cyl(0.08, 0.1, 1.1, 12 if holy else 8), ivory if holy else dark, Vector3(0, 0.67, 0), pil)
		_mesh(_cyl(0.13, 0.1, 0.1, 12 if holy else 8), gold if holy else dark, Vector3(0, 1.27, 0), pil)
		if holy:
			var halo := TorusMesh.new()
			halo.inner_radius = 0.1
			halo.outer_radius = 0.135
			var h := _mesh(halo, _gold_mat(), Vector3(0, 1.55, 0), pil)
			h.rotation.x = 0.25
			_halos.append(h)
		else:
			# big curved horns sweeping out and up from the top (Wife's notes, Nov 21: instead of a trident).
			# Ted, Nov 25: "more wicked, cruel twisting": gnarled, spiralling horns with ridged rings,
			# a twisting keel, little barbs, and a hooked tip glowing ember-hot (see _horn_mesh)
			for side in [-1.0, 1.0]:
				_mesh(_horn_mesh(side), _horn_mat(), Vector3.ZERO, pil).cast_shadow = \
						GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			# an iron collar round the base of the horns
			_mesh(_cyl(0.12, 0.13, 0.05, 8), iron, Vector3(0, 1.34, 0), pil)
	# Gold sparkles rising on the holy side, red embers on the hellish side
	_add_motes(HOLY, Vector3(0, 0.4, -0.7), 0.3)
	_add_motes(HELL, Vector3(0, 0.4, 0.7), -0.3)
	# A soft light, so it glows on whatever's around it
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.6)
	light.light_energy = 0.8
	light.omni_range = 5.0
	light.position.y = 1.6
	add_child(light)


# Polished metallic gold, like the base's band, with a faint glow (Wife's notes, Nov 21).
var _gold: StandardMaterial3D


func _gold_mat() -> StandardMaterial3D:
	if _gold == null:
		_gold = StandardMaterial3D.new()
		_gold.albedo_color = Color(1.0, 0.78, 0.3)
		_gold.metallic = 1.0
		_gold.roughness = 0.22
		_gold.emission_enabled = true
		_gold.emission = Color(1.0, 0.75, 0.3)
		_gold.emission_energy_multiplier = 0.25
	return _gold


# Half a thin disc (the rug is two halves of different cloth).
func _half_disc(r: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 24
	for i in segs:
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(0, h, 0))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(cos(a1) * r, h, -sin(a1) * r))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(cos(a0) * r, h, -sin(a0) * r))
	return st.commit()


# The demon horns' surface: dark keratin with ridged growth rings (lighter, worn crests and grimy grooves),
# fine growth lines, cracks, and an ember heat creeping up to a red-hot tip (cracks and grooves glow first).
const HORN_SHADER := """
shader_type spatial;
varying vec3 lp;
void vertex() { lp = VERTEX; }
float h3(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
float n3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void fragment() {
	float u = UV.y;
	float ring = 0.5 + 0.5 * cos(6.28318 * u * 12.0);   // the same rings as the mesh's ridges
	float ridge = pow(ring, 6.0);
	float groove = smoothstep(0.3, 0.0, ring);
	float g = n3(lp * 18.0);
	float g2 = n3(lp * 60.0);
	float fine = 0.5 + 0.5 * sin(u * 160.0 + g * 5.0);   // fine growth lines between the rings
	vec3 col = mix(vec3(0.025, 0.018, 0.02), vec3(0.07, 0.042, 0.038), g);
	col = mix(col, vec3(0.17, 0.12, 0.095), ridge * 0.6 * (1.0 - smoothstep(0.7, 0.9, u)));
	col *= (1.0 - groove * 0.55) * (0.82 + 0.18 * fine) * (0.72 + 0.28 * g2);
	// splits running along the horn
	float crack = 1.0 - smoothstep(0.0, 0.04, abs(n3(lp * vec3(9.0, 30.0, 9.0) + vec3(0.0, u * 6.0, 0.0)) - 0.5));
	crack *= smoothstep(0.45, 0.6, n3(lp * 6.0 + 3.0));
	col *= 1.0 - crack * 0.75;
	// heat toward the tip
	float heat = smoothstep(0.6, 1.0, u);
	float flick = 0.85 + 0.15 * sin(TIME * 3.0 + u * 12.0) * sin(TIME * 1.7 + 2.0);
	col = mix(col, vec3(0.22, 0.025, 0.012), heat * 0.8);
	vec3 ember = mix(vec3(0.9, 0.08, 0.02), vec3(1.0, 0.28, 0.06), pow(heat, 4.0));
	float glow = pow(heat, 3.0) * 1.9 + crack * smoothstep(0.3, 0.8, u) * 1.6 + groove * heat * 1.0;
	ALBEDO = col;
	EMISSION = ember * glow * flick;
	ROUGHNESS = mix(0.85, 0.5, ridge);
	SPECULAR = 0.3;
}
"""

static var _horn_cache := {}


func _horn_mat() -> ShaderMaterial:
	if not _horn_cache.has("mat"):
		var m := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = HORN_SHADER
		m.shader = sh
		_horn_cache["mat"] = m
	return _horn_cache["mat"]


# The horn's centre line (for the right-hand horn; the left one is its mirror image): out sideways and
# up like before, the line itself corkscrewing a little, and the last fifth hooking in and forward.
func _horn_path(u: float) -> Vector3:
	var p := Vector3(0.06 + 0.31 * sin(u * PI * 0.8), 1.34 + 0.36 * u * u, 0.1 * sin(u * PI) * u)
	var th := u * PI * 3.5
	var a := 0.02 * (1.0 - 0.4 * u)
	p += Vector3(0.0, a * sin(th), a * (cos(th) - 1.0))
	var t := clampf((u - 0.78) / 0.22, 0.0, 1.0)
	p += Vector3(-0.07 * t * t, -0.015 * t * t, 0.07 * t * t)
	return p


# A twisted, ridged horn swept along _horn_path: rings of bumps along its length, a cross-section that is
# flattened and keeled and turns as it goes (so it reads as twisting), little swept-back barbs, and a
# sharp hooked tip. Built once per side and quality and shared.
func _horn_mesh(side: float) -> ArrayMesh:
	var q: int = preload("res://scripts/graphics.gd").quality
	var key := "%d_%d" % [int(side), q]
	if _horn_cache.has(key):
		return _horn_cache[key]
	var segs := 18 if q == 0 else 40
	var sides := 8 if q == 0 else 12
	var pts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	var idx: Array[int] = []
	# parallel-transported frames along the path
	var tan_prev := (_horn_path(0.01) - _horn_path(0.0)).normalized()
	var nrm := (Vector3.UP - tan_prev * Vector3.UP.dot(tan_prev)).normalized()
	var centres := []
	for i in segs + 1:
		var u := float(i) / segs
		var c := _horn_path(u)
		var tg := (_horn_path(minf(u + 0.01, 1.0)) - _horn_path(maxf(u - 0.01, 0.0))).normalized()
		nrm = (nrm - tg * nrm.dot(tg)).normalized()
		var bin := tg.cross(nrm)
		var rad := 0.088 * pow(1.0 - u, 0.9) + 0.004
		var rings := 1.0 + 0.16 * pow(0.5 + 0.5 * cos(TAU * u * 12.0), 8.0) * (1.0 - smoothstep(0.8, 0.95, u))
		var tw := u * PI * 2.5
		centres.append([c, tg, nrm, bin, rad * rings, tw])
		for j in sides:
			var ph := TAU * j / sides
			var shape := 1.0 - 0.1 * cos(2.0 * (ph - tw)) + 0.2 * pow(maxf(cos(ph - tw), 0.0), 6.0)
			shape *= 1.0 + 0.05 * sin(ph * 3.0 + u * 23.0)   # a gnarled, uneven surface
			pts.append(c + (nrm * cos(ph) + bin * sin(ph)) * rad * rings * shape)
			uvs.append(Vector2(float(j) / sides, u))
	var row := sides
	for i in segs:
		for j in sides:
			var a := i * row + j
			var b := i * row + (j + 1) % sides
			idx.append_array([a, a + row, b, b, a + row, b + row])
	# the sharp tip
	var last: Array = centres[segs]
	var tip := pts.size()
	pts.append(last[0] + last[1] * 0.03)
	uvs.append(Vector2(0.5, 1.0))
	for j in sides:
		idx.append_array([segs * row + j, tip, segs * row + (j + 1) % sides])
	# barbs on the keel, swept back toward the base, the last one near the tip a cruel hook
	for bu: float in [0.3, 0.47, 0.63, 0.84]:
		var i := int(round(bu * segs))
		var f: Array = centres[i]
		var dir: Vector3 = f[2] * cos(f[5]) + f[3] * sin(f[5])
		if bu > 0.8:
			dir = -dir
		var base: Vector3 = f[0] + dir * f[4] * 0.85
		var axis: Vector3 = (dir - f[1] * 0.7).normalized()
		var length := 0.075 * (1.0 - bu * 0.45)
		var br := 0.026 * (1.0 - bu * 0.55)
		var side_a := axis.cross(f[1]).normalized()
		var side_b := axis.cross(side_a)
		var b0 := pts.size()
		for j in 6:
			var ph := TAU * j / 6.0
			pts.append(base + (side_a * cos(ph) + side_b * sin(ph)) * br - axis * 0.01)
			uvs.append(Vector2(0.0, bu))
		pts.append(base + axis * length)
		uvs.append(Vector2(0.0, minf(bu + 0.35, 1.0)))
		for j in 6:
			idx.append_array([b0 + j, b0 + 6, b0 + (j + 1) % 6])
	# the left horn is the mirror image (flip x, and the winding with it)
	if side < 0.0:
		for i in pts.size():
			pts[i].x = -pts[i].x
		for t in range(0, idx.size(), 3):
			var tmp := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = tmp
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size():
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])
	for i in idx:
		st.add_index(i)
	st.generate_normals()
	var mesh := st.commit()
	_horn_cache[key] = mesh
	return mesh


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


# Motes drifting up, animated by hand: Godot's particle systems draw from the game's shared random
# numbers, which would shift the seeded layouts the tests rely on.
func _add_motes(color: Color, at: Vector3, drift: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 if drift > 0.0 else 666
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = _glow_mat(color, 3.0)
	for i in 14:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var base := at + Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-0.6, 0.6))
		_motes.append([mi, base, rng.randf_range(0.3, 0.7), rng.randf(), drift])


func _move_motes() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for m in _motes:
		var k := fmod(t * m[2] / 1.8 + m[3], 1.0)   # 0 -> 1 as it rises, then starts over
		m[0].position = m[1] + Vector3(m[4] * k + sin(t * 2.0 + m[3] * 9.0) * 0.05, k * 1.8, 0.0)
		m[0].scale = Vector3.ONE * sin(k * PI)


# Someone started swapping here: light it up for everyone to see and hear.
func flare() -> void:
	_glow = SWAP_TIME + 0.5
	_voice.stream = _chime
	_voice.play()


func _process(delta: float) -> void:
	_crystal.rotation.y += delta * (4.0 if _glow > 0.0 else 0.6)
	for h in _halos:
		h.position.y = 1.55 + sin(Time.get_ticks_msec() / 500.0) * 0.04
	for i in _rings.size():
		_rings[i].rotation.x += delta * (1.1 if i == 0 else -0.8) * (3.0 if _glow > 0.0 else 1.0)
	_runes.rotation.y -= delta * (1.5 if _glow > 0.0 else 0.15)
	var pulse := 1.1 + 0.4 * sin(Time.get_ticks_msec() / 400.0) + (2.0 if _glow > 0.0 else 0.0)
	for m in _rune_mats:
		m.emission_energy_multiplier = pulse
	_move_motes()
	_crystal.position.y = 1.6 + sin(Time.get_ticks_msec() / 600.0) * 0.1
	_glow = maxf(_glow - delta, 0.0)
	_pillar.visible = _glow > 0.0
	_pillar_mat.albedo_color.a = minf(_glow, 1.0) * 0.35
