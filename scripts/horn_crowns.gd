# The demons' wardrobe horns (Ted, Nov 26: "the same quality as the shrine's devil horns, but on the actual
# wardrobe horns... all unique, and awesome looking"). Every kind is a real swept tube like the shrine's
# (shrine.gd _horn_mesh): a curved centre line, a cross-section that tapers, twists and has a keel, ridged
# growth rings, and its own colouring in one shared shader (dark keratin, worn crests, cracks, and for some
# an ember heat creeping up to the tip).
#
# Built in the head bone's space (KayKit units, the top of the head about 1.15 up), for the right-hand
# horn; the left one is its mirror image. Nothing random: every computer draws the same horns.
extends RefCounted

const Graphics = preload("res://scripts/graphics.gd")

# kind -> how it looks. "rings" must match between the mesh (ridges) and the shader (colour bands).
const LOOKS := {
	"horns": {"base": Color(0.06, 0.012, 0.012), "crest": Color(0.3, 0.05, 0.04), "tip": Color(0.9, 0.08, 0.02),
			"rings": 9.0, "heat": 1.0, "cracks": 0.6, "gloss": 0.65},
	"horns_ram": {"base": Color(0.22, 0.17, 0.12), "crest": Color(0.55, 0.47, 0.36), "tip": Color(0.3, 0.24, 0.17),
			"rings": 26.0, "heat": 0.0, "cracks": 0.0, "gloss": 0.25},
	"horns_goat": {"base": Color(0.07, 0.045, 0.03), "crest": Color(0.24, 0.16, 0.1), "tip": Color(0.03, 0.02, 0.02),
			"rings": 11.0, "heat": 0.25, "cracks": 0.3, "gloss": 0.45},
	"horns_nubs": {"base": Color(0.05, 0.04, 0.04), "crest": Color(0.13, 0.1, 0.09), "tip": Color(1.0, 0.35, 0.05),
			"rings": 3.0, "heat": 0.55, "cracks": 1.0, "gloss": 0.3},
	# (Ted, Nov 26: "more wicked... mostly black, with angry red streaks": glowing streaks follow the twist)
	"horns_twist": {"base": Color(0.025, 0.018, 0.02), "crest": Color(0.12, 0.03, 0.03), "tip": Color(1.0, 0.12, 0.02),
			"rings": 0.0, "heat": 0.5, "cracks": 0.7, "gloss": 0.8, "streaks": 2.25},
	"horns_four": {"base": Color(0.03, 0.02, 0.035), "crest": Color(0.2, 0.08, 0.22), "tip": Color(0.75, 0.15, 1.0),
			"rings": 7.0, "heat": 0.8, "cracks": 0.5, "gloss": 0.6},
}

const SHADER := """
shader_type spatial;
uniform vec3 base_col;
uniform vec3 crest_col;
uniform vec3 tip_col;
uniform float rings = 9.0;
uniform float heat_amount = 1.0;
uniform float crack_glow = 0.5;
uniform float gloss = 0.5;
uniform float streaks = 0.0;   // >0: glowing streaks spiralling round the horn this many turns
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
	float ring = rings > 0.0 ? 0.5 + 0.5 * cos(6.28318 * u * rings) : 0.5;
	float ridge = pow(ring, 6.0);
	float groove = smoothstep(0.3, 0.0, ring) * step(0.5, rings);
	float g = n3(lp * 30.0);
	float g2 = n3(lp * 90.0);
	float fine = 0.5 + 0.5 * sin(u * 140.0 + g * 5.0);
	vec3 col = mix(base_col * 0.7, base_col * 1.3, g);
	col = mix(col, crest_col, ridge * 0.7 * (1.0 - smoothstep(0.75, 0.95, u)));
	col *= (1.0 - groove * 0.5) * (0.84 + 0.16 * fine) * (0.75 + 0.25 * g2);
	float crack = 1.0 - smoothstep(0.0, 0.05, abs(n3(lp * vec3(14.0, 45.0, 14.0) + vec3(0.0, u * 6.0, 0.0)) - 0.5));
	crack *= smoothstep(0.45, 0.6, n3(lp * 9.0 + 3.0)) * crack_glow;
	col *= 1.0 - crack * 0.7;
	// toward the tip: the tip colour (and with heat, an ember glow)
	float tipw = smoothstep(0.55, 1.0, u);
	col = mix(col, tip_col * (heat_amount > 0.0 ? 0.3 : 1.0), tipw * 0.85);
	float flick = 0.85 + 0.15 * sin(TIME * 3.0 + u * 12.0) * sin(TIME * 1.7 + 2.0);
	float glow = heat_amount * (pow(tipw, 3.0) * 2.0 + groove * tipw) + crack * (0.4 + heat_amount) * 1.4;
	if (streaks > 0.0) {
		// angry red veins running up the horn with its twist, wavering, brighter toward the tip
		float sv = fract(UV.x * 3.0 - u * streaks + 0.06 * sin(u * 40.0 + g * 6.0));
		float streak = 1.0 - smoothstep(0.0, 0.07, abs(sv - 0.5));
		streak *= 0.45 + 0.55 * smoothstep(0.0, 0.7, u);
		col = mix(col, tip_col * 0.35, streak * 0.8);
		glow += streak * 1.6;
	}
	ALBEDO = col;
	EMISSION = tip_col * glow * flick;
	ROUGHNESS = mix(0.9, 0.35, gloss * (0.5 + 0.5 * ridge));
	SPECULAR = 0.25 + 0.3 * gloss;
	// bump (Nov 26: "bump maps" for detail without more triangles): growth lines, grooves and cracks given
	// relief, worked out on screen from the height (no tangents needed), like structure_look.gd's
	float height = fine * 0.002 - groove * 0.006 - crack * 0.008 + g2 * 0.003;
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec3 r1 = cross(dpy, NORMAL);
	vec3 r2 = cross(NORMAL, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dFdx(height) * r1 + dFdy(height) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
}
"""

static var _cache := {}
const SCALE := 1.5
const ROOT_DROP := -0.1


static func kinds() -> Array:
	return LOOKS.keys()


static func material(kind: String) -> ShaderMaterial:
	var key := "mat_" + kind
	if not _cache.has(key):
		var look: Dictionary = LOOKS.get(kind, LOOKS["horns"])
		if not _cache.has("shader"):
			var sh := Shader.new()
			sh.code = SHADER
			_cache["shader"] = sh
		var m := ShaderMaterial.new()
		m.shader = _cache["shader"]
		var base: Color = look["base"]
		var crest: Color = look["crest"]
		var tip: Color = look["tip"]
		m.set_shader_parameter("base_col", Vector3(base.r, base.g, base.b))
		m.set_shader_parameter("crest_col", Vector3(crest.r, crest.g, crest.b))
		m.set_shader_parameter("tip_col", Vector3(tip.r, tip.g, tip.b))
		m.set_shader_parameter("rings", look["rings"])
		m.set_shader_parameter("heat_amount", look["heat"])
		m.set_shader_parameter("crack_glow", look["cracks"])
		m.set_shader_parameter("gloss", look["gloss"])
		m.set_shader_parameter("streaks", look.get("streaks", 0.0))
		_cache[key] = m
	return _cache[key]


# Both horns (and any extras) of this kind, for a head whose top is at `top`. Given the head's points
# (`hull`, head bone space), each horn is moved so its root sits just inside the head's surface, in the
# direction it was drawn from the head's centre, so it grows out of the skull instead of hovering by it.
static func make(kind: String, top: float, hull := PackedVector3Array()) -> Node3D:
	if not LOOKS.has(kind):
		kind = "horns"
	var n := Node3D.new()
	# (the KayKit heads are big and round: the horns are drawn at 1.5x)
	n.position.y = top + ROOT_DROP
	n.scale = Vector3.ONE * SCALE
	for part in _parts(kind):
		for side: float in [-1.0, 1.0]:
			# (each side finds its own spot: heads and helmets aren't quite symmetric, and a mirrored left horn
			# floated a little on the Skeleton Warrior's helmet; Ted, Nov 27)
			var off := _root_shift(kind, part, n.position, hull, side)
			var mi := MeshInstance3D.new()
			mi.mesh = _mesh(kind, part, side)
			mi.material_override = material(kind)
			mi.position = off
			n.add_child(mi)
	return n


# How far to move one (right-hand) horn, in the horns' own scaled space, to plant its root in the head.
static func _root_shift(kind: String, part: int, origin: Vector3, hull: PackedVector3Array, side := 1.0) -> Vector3:
	if hull.is_empty():
		return Vector3.ZERO
	var box := AABB(hull[0], Vector3.ZERO)
	for v in hull:
		box = box.expand(v)
	var centre := box.get_center()
	var p0 := _path(kind, part, 0.0)
	var root := origin + Vector3(p0.x * side, p0.y, p0.z) * SCALE
	var dir := (root - centre).normalized()
	# the head's surface that way: the farthest point within a narrow cone around it
	var reach := -1.0
	for v in hull:
		var d := v - centre
		var along := d.dot(dir)
		if along > 0.0 and along > d.length() * 0.94 and along > reach:
			reach = along
	if reach <= 0.0:
		return Vector3.ZERO
	var sink := _radius(kind, part, 0.0) * SCALE * 0.8   # buried most of its thickness: no gap shows from any side
	var anchor := centre + dir * (reach - sink)
	return (anchor - root) / SCALE


static func _parts(kind: String) -> Array:
	return [0, 1] if kind == "horns_four" else [0]


# ---- the shapes: centre line (right-hand horn, relative to the head's top) and thickness ----

static func _path(kind: String, part: int, u: float) -> Vector3:
	match kind:
		"horns_ram":
			# a heavy curl: up off the side of the head, back, down round behind the ear and forward
			var th := u * PI * 1.65
			var r := 0.2 * (1.0 - 0.42 * u)
			return Vector3(0.25 + 0.03 * u + 0.15 * u * u, -0.32 + r * cos(th), 0.02 - r * sin(th))
		"horns_goat":
			# a long scimitar sweep, up and back, with a slight outward flare
			var a := u * 1.5
			return Vector3(0.24 + 0.05 * u + 0.07 * u * u, -0.12 + 0.5 * sin(a), 0.04 - 0.5 * (1.0 - cos(a)))
		"horns_nubs":
			return Vector3(0.24 + 0.04 * u, -0.1 + 0.17 * u, 0.06 + 0.03 * u)
		"horns_twist":
			# a corkscrew: a straight shaft leaning out and back, its centre line spiralling round it
			var axis := Vector3(0.38, 1.0, -0.25).normalized()
			var side_a := axis.cross(Vector3.FORWARD).normalized()
			var side_b := axis.cross(side_a)
			var th := u * TAU * 2.25
			var hr := 0.045 * (1.0 - 0.75 * u)
			return Vector3(0.25, -0.1, 0.04) + axis * 0.68 * u + (side_a * cos(th) + side_b * sin(th)) * hr - side_a * 0.045
		"horns_four":
			if part == 1:   # the smaller pair on the brow, jutting forward and up (in the head bone's space the face is toward +Z)
				return Vector3(0.15 + 0.07 * u, -0.17 + 0.15 * u + 0.05 * u * u, 0.2 + 0.13 * u - 0.03 * u * u)
			return _devil(u) * Vector3(1.0, 1.15, 1.0) + Vector3(0.02, 0.0, -0.04)
	return _devil(u)


# The classic devil horn: out and up, leaning back, the tip hooking in.
static func _devil(u: float) -> Vector3:
	var p := Vector3(0.25 + 0.09 * u + 0.08 * sin(u * PI), -0.12 + 0.48 * u, 0.05 - 0.05 * u - 0.08 * u * u)
	var t := clampf((u - 0.65) / 0.35, 0.0, 1.0)
	p += Vector3(-0.09 * t * t, -0.01 * t * t, 0.04 * t * t)
	return p


static func _radius(kind: String, part: int, u: float) -> float:
	match kind:
		"horns_ram":
			return 0.115 * pow(1.0 - u, 0.7) + 0.022
		"horns_goat":
			return 0.085 * pow(1.0 - u, 0.85) + 0.006
		"horns_nubs":
			return 0.105 * pow(1.0 - u, 0.55) + 0.012
		"horns_twist":
			return 0.07 * pow(1.0 - u, 0.9) + 0.004
		"horns_four":
			return (0.05 if part == 1 else 0.085) * pow(1.0 - u, 0.9) + 0.004
	return 0.095 * pow(1.0 - u, 0.9) + 0.004


# How each kind's cross-section is shaped: [ring ridge height, twist turns, keel, flatten, knobs on the front]
static func _section(kind: String) -> Array:
	match kind:
		"horns_ram":
			return [0.1, 0.0, 0.0, 0.22, 0.0]      # flat-sided and deeply ridged all along
		"horns_goat":
			return [0.03, 0.15, 0.1, 0.12, 0.28]   # big knobs on the front edge, like an ibex
		"horns_nubs":
			return [0.12, 0.0, 0.0, 0.0, 0.0]
		"horns_twist":
			return [0.0, 2.25, 0.32, 0.18, 0.0]    # a sharp keel twisting with the spiral
		"horns_four":
			return [0.1, 0.8, 0.15, 0.08, 0.0]
	return [0.12, 1.2, 0.18, 0.1, 0.0]


static func _mesh(kind: String, part: int, side: float) -> ArrayMesh:
	var q: int = Graphics.quality
	var key := "%s_%d_%d_%d" % [kind, part, int(side), q]
	if _cache.has(key):
		return _cache[key]
	var look: Dictionary = LOOKS[kind]
	var sec := _section(kind)
	var ring_count: float = look["rings"]
	var segs: int = [14, 26, 36][q] if kind != "horns_ram" else [20, 40, 56][q]
	if kind == "horns_nubs" or part == 1:
		segs = [8, 12, 16][q]
	var sides: int = [7, 10, 12][q]
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var tan0 := (_path(kind, part, 0.01) - _path(kind, part, 0.0)).normalized()
	var nrm := (Vector3.UP - tan0 * Vector3.UP.dot(tan0)).normalized()
	if nrm.length() < 0.1:
		nrm = Vector3.FORWARD
	var last := []
	for i in segs + 1:
		var u := float(i) / segs
		var c := _path(kind, part, u)
		var tg := (_path(kind, part, minf(u + 0.01, 1.0)) - _path(kind, part, maxf(u - 0.01, 0.0))).normalized()
		nrm = (nrm - tg * nrm.dot(tg)).normalized()
		var bin := tg.cross(nrm)
		var rad := _radius(kind, part, u)
		var ridge := 1.0
		if ring_count > 0.0:
			ridge += sec[0] * pow(0.5 + 0.5 * cos(TAU * u * ring_count), 6.0) * (1.0 - smoothstep(0.8, 0.95, u))
		var tw: float = u * PI * 2.0 * sec[1]
		last = [c, tg]
		for j in sides:
			var ph := TAU * j / sides
			var shape: float = 1.0 - sec[3] * cos(2.0 * (ph - tw)) + sec[2] * pow(maxf(cos(ph - tw), 0.0), 6.0)
			if sec[4] > 0.0:   # knobs along the front edge (the side facing forward and out)
				shape += sec[4] * pow(maxf(cos(ph - PI * 0.5), 0.0), 4.0) * pow(0.5 + 0.5 * cos(TAU * u * ring_count), 4.0)
			shape *= 1.0 + 0.04 * sin(ph * 3.0 + u * 23.0)   # a gnarled, uneven surface
			pts.append(c + (nrm * cos(ph) + bin * sin(ph)) * rad * ridge * shape)
			uvs.append(Vector2(float(j) / sides, u))
	for i in segs:
		for j in sides:
			var a := i * sides + j
			var b := i * sides + (j + 1) % sides
			idx.append_array([a, a + sides, b, b, a + sides, b + sides])
	# the point
	var tip := pts.size()
	pts.append(last[0] + last[1] * 0.02)
	uvs.append(Vector2(0.5, 1.0))
	for j in sides:
		idx.append_array([segs * sides + j, tip, segs * sides + (j + 1) % sides])
	# the root, closed (in case it shows at the side of the head)
	var root := pts.size()
	pts.append(_path(kind, part, 0.0) - tan0 * 0.02)
	uvs.append(Vector2(0.5, 0.0))
	for j in sides:
		idx.append_array([j, (j + 1) % sides, root])
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
	_cache[key] = mesh
	return mesh
