# Scenery past the map's walls (Ted's wife's notes, Nov 21): a map setting, "backdrop":
#   none, hills, ocean, mountains or city.
# (Ted, Nov 26: "a nice first attempt, but very basic... not believable as actual scenery. Add a bit more detail
# and graphical refinement so it feels more immersive.") Now it's real terrain: a ring of ground round the map
# with its own shape for each kind, coloured by height and steepness, with patchwork fields and hedgerows on the
# hills, woods in clumps, snowy ridged peaks with pine forests on their lower slopes, a beach shelving into a sea
# with foam, wooded islands, a lighthouse and sailing boats, and a city of towers with lit windows, rooftop
# clutter and a ring of suburban houses along the roads in.
# All of it is just to look at: no collision (nobody can get past the walls). Laid out from the map's name with
# its own random numbers, so every screen sees the same scenery.
extends RefCounted

const Surfaces = preload("res://scripts/surfaces.gd")

const KINDS := ["none", "hills", "ocean", "mountains", "city"]
const NAMES := ["None", "Rolling hills", "Ocean", "Mountains", "City skyline"]

const SEA_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 deep = vec3(0.04, 0.18, 0.3);
uniform vec3 shallow = vec3(0.12, 0.45, 0.5);
uniform float shore = 60.0;
varying vec3 wp;
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wp.x * 0.15 + TIME * 0.8) * 0.12 + sin(wp.z * 0.21 + TIME * 0.6) * 0.1;
}
void fragment() {
	float d = length(wp.xz) - shore;
	float near = clamp(1.0 - d / 40.0, 0.0, 1.0);
	vec2 q = wp.xz * 0.35 + vec2(TIME * 0.3, TIME * 0.2);
	float ripple = n2(q) * 0.6 + n2(q * 2.7 - TIME * 0.4) * 0.4;
	vec3 c = mix(deep, shallow, near * near) * (0.9 + 0.2 * ripple);
	// foam where the waves come in on the beach, and flecks of white further out
	float foam = smoothstep(0.55, 0.85, n2(wp.xz * 0.6 + TIME * 0.5)) * smoothstep(8.0, 0.0, abs(d - 2.0 - sin(TIME * 0.7) * 1.5));
	foam += smoothstep(0.86, 0.95, n2(wp.xz * 0.25 - TIME * 0.2)) * 0.25;
	c = mix(c, vec3(0.92, 0.95, 0.95), clamp(foam, 0.0, 1.0));
	ALBEDO = c;
	NORMAL_MAP = normalize(vec3(n2(q * 3.0) - 0.5, n2(q * 3.0 + 7.0) - 0.5, 2.0)) * 0.5 + 0.5;
	ROUGHNESS = 0.06 + foam * 0.6;
	SPECULAR = 0.8;
}
"""

# City towers: a grid of windows on every face, some lit; lit ones glow more as it gets dark (the sky's fog
# softens them by day).
const TOWER_SHADER := """
shader_type spatial;
uniform vec3 wall = vec3(0.55, 0.58, 0.65);
uniform float seed = 0.0;
// (Sara, Nov 28: "give more variety to the skyscrapers") how its windows are set out: 0 punched windows, 1 a glass
// curtain wall with thin mullions, 2 ribbon windows running round every floor, 3 tall narrow windows between piers
uniform int style = 0;
uniform vec2 pitch = vec2(2.6, 3.4);          // a window bay: width and storey height
uniform vec3 glass = vec3(0.16, 0.2, 0.27);
varying vec3 wp;
varying vec3 wn;
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 c = wall;
	vec3 e = vec3(0.0);
	if (abs(wn.y) < 0.5) {
		float u = abs(wn.x) > abs(wn.z) ? wp.z : wp.x;
		vec2 cell = vec2(u, wp.y) / pitch;
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float win = step(0.18, f.x) * step(f.x, 0.82) * step(0.25, f.y) * step(f.y, 0.85);
		if (style == 1) { win = step(0.05, f.x) * step(0.1, f.y); }
		else if (style == 2) { win = step(0.38, f.y) * step(f.y, 0.82); id.x = floor(cell.x * 0.5); }
		else if (style == 3) { win = step(0.3, f.x) * step(f.x, 0.7) * step(0.08, f.y) * step(f.y, 0.94); }
		win *= step(1.0, wp.y);
		float lit = step(0.62, h2(id + seed));
		c = mix(c, glass * (0.85 + 0.3 * h2(id * 0.37 + seed)), win);
		e = vec3(1.0, 0.82, 0.5) * win * lit * (0.6 + 0.6 * h2(id * 1.7 + seed));
		// a band every few floors
		c *= 1.0 - 0.15 * step(0.92, fract(wp.y / 13.6));
	} else {
		c *= 0.75;
	}
	ALBEDO = c;
	ROUGHNESS = style == 1 ? 0.25 : 0.55;
	EMISSION = e * 0.9;
}
"""


static func make(kind: String, half: float, seed_text: String) -> Node3D:
	var n := Node3D.new()
	n.name = "Backdrop"
	if not kind in KINDS or kind == "none":
		return n
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text + kind)
	match kind:
		"hills":
			_hills(n, half, rng)
		"ocean":
			_ocean(n, half, rng)
		"mountains":
			_mountains(n, half, rng)
		"city":
			_city(n, half, rng)
	for c in n.find_children("*", "GeometryInstance3D", true, false):
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


static func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _vmat(kind := "ground") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	Surfaces.apply(m, kind)
	m.roughness = 0.95
	m.metallic = 0.0
	m.uv1_scale *= 0.12   # (big ground: the detail texture spread wider)
	return m


static func _around(half: float, rng: RandomNumberGenerator, near: float, far: float) -> Vector3:
	var a := rng.randf_range(0.0, TAU)
	var d := half * 1.42 + rng.randf_range(near, far)
	return Vector3(cos(a) * d, 0.0, sin(a) * d)


static func _noise(seed: int, freq: float, kind := FastNoiseLite.TYPE_SIMPLEX_SMOOTH, octaves := 4) -> FastNoiseLite:
	var f := FastNoiseLite.new()
	f.seed = seed
	f.frequency = freq
	f.noise_type = kind
	f.fractal_octaves = octaves
	return f


# A ring of ground from just past the map's corners out to `outer`: height(x, z) and colour(x, z, height, slope)
# decide its shape and look. Returns the mesh's node.
static func _terrain(n: Node3D, half: float, outer: float, height: Callable, colour: Callable, kind := "ground") -> MeshInstance3D:
	var inner := half * 1.42 + 2.0
	var around := 180
	var radial := 46
	var pts := []
	for i in radial + 1:
		var t := float(i) / radial
		var r := inner + (outer - inner) * pow(t, 1.7)   # (closer rings near the map, where you look most)
		var row := []
		for j in around:
			var a := TAU * j / around
			var x := cos(a) * r
			var z := sin(a) * r
			row.append(Vector3(x, height.call(x, z), z))
		pts.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in radial:
		for j in around:
			var j1 := (j + 1) % around
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i + 1][j]
			var c: Vector3 = pts[i + 1][j1]
			var d: Vector3 = pts[i][j1]
			for tri in [[a, b, c], [a, c, d]]:
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				var nrm := (p1 - p0).cross(p2 - p0).normalized()
				if nrm.y < 0.0:
					nrm = -nrm
					var tmp := p1
					p1 = p2
					p2 = tmp
				# (wound so it faces up)
				for p in [p0, p2, p1]:
					var pv: Vector3 = p
					st.set_color(colour.call(pv.x, pv.z, pv.y, 1.0 - nrm.y))
					st.add_vertex(pv)
	st.index()
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _vmat(kind)
	n.add_child(mi)
	# the flat ground between the walls and the ring
	var apron := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(inner * 2.0 + 4.0, inner * 2.0 + 4.0)
	apron.mesh = pm
	apron.material_override = _mat(colour.call(inner, 0.0, 0.0, 0.0))
	apron.position.y = -0.05
	n.add_child(apron)
	return mi


# Rises from nothing at the inner edge of the ring (so the walls and the map's corners stay clear).
static func _ramp(x: float, z: float, half: float, over: float) -> float:
	return smoothstep(half * 1.42 + 2.0, half * 1.42 + 2.0 + over, Vector2(x, z).length())


# ---------------------------------------------------------------- trees

static var _tree_meshes := {}


# A low-poly tree for the distance: a trunk and a few lumpy blobs of leaves (round), or a stack of drooping
# cones (pine). Vertex colours, shaded a little darker underneath; instances tint it.
static func _tree_mesh(pine: bool) -> ArrayMesh:
	var key := "pine" if pine else "round"
	if _tree_meshes.has(key):
		return _tree_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := Color(0.32, 0.22, 0.14)
	_cone(st, Vector3.ZERO, 0.22, 0.12, 1.6 if not pine else 1.2, 6, trunk, trunk)
	if pine:
		for k in 4:
			var y := 0.9 + k * 1.05
			var r := 1.5 - k * 0.32
			_cone(st, Vector3(0, y, 0), r, 0.0, 1.7, 9, Color(0.1, 0.26, 0.14), Color(0.18, 0.38, 0.2))
	else:
		for b in [[Vector3(0, 2.6, 0), 1.5], [Vector3(0.7, 2.2, 0.3), 1.0], [Vector3(-0.6, 2.3, -0.4), 1.05], [Vector3(0.1, 3.3, -0.2), 1.0]]:
			_blob(st, b[0], b[1], Color(0.16, 0.34, 0.12), Color(0.3, 0.5, 0.2))
	st.generate_normals()
	_tree_meshes[key] = st.commit()
	return _tree_meshes[key]


static func _cone(st: SurfaceTool, base: Vector3, r0: float, r1: float, h: float, sides: int, c0: Color, c1: Color) -> void:
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var b0 := base + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var b1 := base + Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		var t0 := base + Vector3(cos(a0) * r1, h, sin(a0) * r1)
		var t1 := base + Vector3(cos(a1) * r1, h, sin(a1) * r1)
		for tri in [[b0, t0, t1, c0, c1, c1], [b0, t1, b1, c0, c1, c0]]:
			st.set_color(tri[3])
			st.add_vertex(tri[0])
			st.set_color(tri[5])
			st.add_vertex(tri[2])
			st.set_color(tri[4])
			st.add_vertex(tri[1])
		if r0 > 0.3:   # (the underside of a pine's skirt)
			st.set_color(c0.darkened(0.3))
			st.add_vertex(base)
			st.set_color(c0.darkened(0.3))
			st.add_vertex(b0)
			st.set_color(c0.darkened(0.3))
			st.add_vertex(b1)


static func _blob(st: SurfaceTool, c: Vector3, r: float, dark: Color, light: Color) -> void:
	var rings := 5
	var sides := 8
	var pts := []
	for i in rings + 1:
		var t := -PI * 0.5 + PI * i / rings
		var row := []
		for j in sides:
			var a := TAU * j / sides + i * 0.4
			var w := 1.0 + 0.15 * sin(a * 3.0 + i)
			row.append(c + Vector3(cos(t) * cos(a) * w, sin(t) * 0.85, cos(t) * sin(a) * w) * r)
		pts.append(row)
	for i in rings:
		for j in sides:
			var j1 := (j + 1) % sides
			var q := [pts[i][j], pts[i + 1][j], pts[i + 1][j1], pts[i][j1]]
			var col0 := dark.lerp(light, float(i) / rings)
			var col1 := dark.lerp(light, float(i + 1) / rings)
			for tri in [[q[0], col0, q[2], col1, q[1], col1], [q[0], col0, q[3], col0, q[2], col1]]:
				st.set_color(tri[1])
				st.add_vertex(tri[0])
				st.set_color(tri[3])
				st.add_vertex(tri[2])
				st.set_color(tri[5])
				st.add_vertex(tri[4])


static func _forest(n: Node3D, spots: Array, pine: bool, tints: Array) -> void:
	if spots.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _tree_mesh(pine)
	mm.instance_count = spots.size()
	for i in spots.size():
		var s: Array = spots[i]
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, s[2]).scaled(Vector3.ONE * float(s[1])), s[0]))
		mm.set_instance_color(i, tints[i % tints.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.9
	mmi.material_override = m
	n.add_child(mmi)


# Trees in woods: clumps where the noise says so, on ground the height function says isn't too high or steep.
static func _woods(half: float, rng: RandomNumberGenerator, count: int, near: float, far: float, height: Callable,
		where: FastNoiseLite, max_h := 999.0) -> Array:
	var out := []
	var tries := 0
	while out.size() < count and tries < count * 12:
		tries += 1
		var at := _around(half, rng, near, far)
		if where.get_noise_2d(at.x, at.z) < 0.05:
			continue
		var y: float = height.call(at.x, at.z)
		if y > max_h:
			continue
		out.append([Vector3(at.x, y - 0.2, at.z), rng.randf_range(1.0, 2.2), rng.randf() * TAU])
	return out


# ---------------------------------------------------------------- hills: farmland and woods

static func _hills(n: Node3D, half: float, rng: RandomNumberGenerator) -> void:
	var s := rng.randi()
	var lump := _noise(s, 0.006, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 4)
	var fields := _noise(s + 1, 0.022, FastNoiseLite.TYPE_CELLULAR, 1)
	fields.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var hedges := _noise(s + 1, 0.022, FastNoiseLite.TYPE_CELLULAR, 1)
	hedges.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var detail := _noise(s + 2, 0.08, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3)
	var height := func(x: float, z: float) -> float:
		return (lump.get_noise_2d(x, z) * 0.5 + 0.5) * 38.0 * _ramp(x, z, half, 70.0) + detail.get_noise_2d(x, z) * 1.2 * _ramp(x, z, half, 10.0)
	var crops := [Color(0.38, 0.56, 0.24), Color(0.46, 0.62, 0.28), Color(0.72, 0.66, 0.34), Color(0.5, 0.4, 0.26), Color(0.32, 0.5, 0.22), Color(0.6, 0.6, 0.3)]
	var colour := func(x: float, z: float, h: float, slope: float) -> Color:
		var v := fields.get_noise_2d(x, z) * 0.5 + 0.5
		var c: Color = crops[int(v * crops.size()) % crops.size()]
		c = c.lerp(Color(0.36, 0.52, 0.24), smoothstep(0.25, 0.5, slope))   # steep: rough grass
		c = c.darkened(0.08 * detail.get_noise_2d(x * 3.0, z * 3.0))
		var edge := hedges.get_noise_2d(x, z)
		if edge > -0.04 and Vector2(x, z).length() > half * 1.5:
			c = Color(0.16, 0.3, 0.12)   # hedgerows between the fields
		return c
	_terrain(n, half, 520.0, height, colour)
	var where := _noise(s + 3, 0.012)
	_forest(n, _woods(half, rng, 900, 10.0, 260.0, height, where), false,
			[Color(1, 1, 1), Color(0.85, 0.95, 0.8), Color(1.1, 1.05, 0.9), Color(0.9, 1.0, 0.85)])
	# a farmhouse or two and a church spire on the hills
	_houses(n, half, rng, height, 10, 40.0, 200.0)


# Little houses (walls, a pitched roof, a chimney), sat on the ground.
# Returns where they stand: [[centre, radius], ...] (so nothing else is planted on top of them).
# (Sara, Nov 28: houses stood inside one another and trees grew through them; and "add a limited amount windows
# and doors": a door and two windows on the front, two windows at the back, one in each gable end.)
static func _houses(n: Node3D, half: float, rng: RandomNumberGenerator, height: Callable, count: int, near: float, far: float, roads := false) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := [Color(0.92, 0.88, 0.78), Color(0.85, 0.75, 0.6), Color(0.78, 0.5, 0.4), Color(0.9, 0.9, 0.88)]
	var roofs := [Color(0.55, 0.22, 0.16), Color(0.3, 0.3, 0.34), Color(0.45, 0.3, 0.2)]
	var doors := [Color(0.45, 0.2, 0.14), Color(0.2, 0.3, 0.45), Color(0.25, 0.4, 0.28), Color(0.3, 0.22, 0.16)]
	var placed := []
	var tries := 0
	while placed.size() < count and tries < count * 8:
		tries += 1
		var at := _around(half, rng, near, far)
		if roads:   # (along the four roads in)
			var axis := rng.randi() % 4
			var d := half * 1.42 + rng.randf_range(near, far)
			var off := rng.randf_range(9.0, 16.0) * (1.0 if rng.randf() < 0.5 else -1.0)
			at = Vector3(cos(axis * PI * 0.5) * d - sin(axis * PI * 0.5) * off, 0, sin(axis * PI * 0.5) * d + cos(axis * PI * 0.5) * off)
		var y: float = height.call(at.x, at.z)
		var w := rng.randf_range(6.0, 9.0)
		var dpt := rng.randf_range(5.0, 7.0)
		var clear := true
		for other in placed:
			if Vector2(at.x - (other[0] as Vector3).x, at.z - (other[0] as Vector3).z).length() < float(other[1]) + w * 0.62 + 4.0:
				clear = false
				break
		if not clear:
			continue
		placed.append([Vector3(at.x, y, at.z), w * 0.62])
		var hh := rng.randf_range(3.0, 5.5)
		var bas := Basis(Vector3.UP, rng.randf() * TAU if not roads else atan2(at.x, at.z))
		var wc: Color = walls[rng.randi() % walls.size()]
		var rc: Color = roofs[rng.randi() % roofs.size()]
		var c := Vector3(at.x, y, at.z)
		var hw := bas.x * w * 0.5
		var hd := bas.z * dpt * 0.5
		var corners := [c - hw - hd, c + hw - hd, c + hw + hd, c - hw + hd]
		for i in 4:
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[(i + 1) % 4]
			_quad_up(st, a - Vector3.UP, b - Vector3.UP, b + Vector3.UP * hh, a + Vector3.UP * hh, wc.darkened(0.08 * (i % 2)))
		var ridge := Vector3.UP * (hh + w * 0.35)
		var r0 := c - hw * 1.08 + ridge
		var r1 := c + hw * 1.08 + ridge
		for sd in [-1.0, 1.0]:
			var e: Vector3 = hd * 1.15 * sd
			_quad_up(st, c - hw * 1.08 + e + Vector3.UP * (hh - 0.3), c + hw * 1.08 + e + Vector3.UP * (hh - 0.3), r1, r0, rc.darkened(0.12 if sd > 0.0 else 0.0))
		for sx in [-1.0, 1.0]:   # the gable ends
			var g: Vector3 = hw * sx
			_tri_up(st, c + g - hd + Vector3.UP * hh, c + g + hd + Vector3.UP * hh, c + g + ridge, wc)
		# a door and windows: panes a hand's breadth proud of the wall, each in a pale frame
		var glass := Color(0.2, 0.27, 0.36)
		var frame := Color(0.95, 0.94, 0.9)
		var put := func(a: Vector3, b: Vector3, x0: float, x1: float, y0: float, y1: float, col: Color, lift: float) -> void:
			var dir := (b - a).normalized()
			var mid := (a + b) * 0.5
			var out := Vector3(mid.x - c.x, 0, mid.z - c.z)
			out = (out - dir * out.dot(dir)).normalized() * lift
			var len := a.distance_to(b)
			var p0 := mid + dir * x0 + out
			var p1 := mid + dir * x1 + out
			_quad_up(st, p0 + Vector3.UP * y0, p1 + Vector3.UP * y0, p1 + Vector3.UP * y1, p0 + Vector3.UP * y1, col)
		var sill := minf(1.1, hh * 0.3)
		var head := minf(sill + 1.3, hh - 0.5)
		var window := func(a: Vector3, b: Vector3, x: float) -> void:
			put.call(a, b, x - 0.75, x + 0.75, sill - 0.12, head + 0.12, frame, 0.05)
			put.call(a, b, x - 0.6, x + 0.6, sill, head, glass, 0.09)
			put.call(a, b, x - 0.04, x + 0.04, sill, head, frame, 0.12)
		window.call(corners[2], corners[3], -w * 0.28)
		window.call(corners[2], corners[3], w * 0.28)
		put.call(corners[2], corners[3], -0.7, 0.7, 0.0, minf(2.3, hh - 0.4), frame, 0.05)
		put.call(corners[2], corners[3], -0.55, 0.55, 0.0, minf(2.15, hh - 0.5), doors[rng.randi() % doors.size()], 0.09)
		window.call(corners[0], corners[1], -w * 0.25)
		window.call(corners[0], corners[1], w * 0.25)
		window.call(corners[1], corners[2], 0.0)
		window.call(corners[3], corners[0], 0.0)
		# a chimney
		var ch := c + hw * 0.5 + Vector3.UP * (hh + w * 0.2)
		_quad_up(st, ch - bas.x * 0.4 - bas.z * 0.4, ch + bas.x * 0.4 - bas.z * 0.4, ch + bas.x * 0.4 - bas.z * 0.4 + Vector3.UP * 2.0, ch - bas.x * 0.4 - bas.z * 0.4 + Vector3.UP * 2.0, Color(0.5, 0.35, 0.3))
		_quad_up(st, ch + bas.x * 0.4 + bas.z * 0.4, ch - bas.x * 0.4 + bas.z * 0.4, ch - bas.x * 0.4 + bas.z * 0.4 + Vector3.UP * 2.0, ch + bas.x * 0.4 + bas.z * 0.4 + Vector3.UP * 2.0, Color(0.5, 0.35, 0.3))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	mi.material_override = m
	n.add_child(mi)
	return placed


static func _quad_up(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for p in [a, c, b, a, d, c]:
		st.set_color(col)
		st.add_vertex(p)


static func _tri_up(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for p in [a, c, b]:
		st.set_color(col)
		st.add_vertex(p)


# ---------------------------------------------------------------- ocean: a beach, the sea, islands

static func _ocean(n: Node3D, half: float, rng: RandomNumberGenerator) -> void:
	var s := rng.randi()
	var shore := half * 1.42 + 22.0
	var bumps := _noise(s, 0.01)
	var isles := []
	for k in 6:
		var at := _around(half, rng, 110.0, 300.0)
		isles.append([Vector2(at.x, at.z), rng.randf_range(18.0, 40.0), rng.randf_range(8.0, 22.0)])
	var height := func(x: float, z: float) -> float:
		var d := Vector2(x, z).length()
		var h := -smoothstep(shore - 14.0, shore + 30.0, d) * 6.0 + bumps.get_noise_2d(x, z) * 0.6   # the beach shelving away
		for il in isles:
			var r: float = il[1]
			var k := 1.0 - (Vector2(x, z) - (il[0] as Vector2)).length() / r
			if k > 0.0:
				h = maxf(h, -3.0 + (float(il[2]) + 3.0) * pow(k, 0.7) + bumps.get_noise_2d(x * 3.0, z * 3.0) * 2.0)
		return h
	var colour := func(x: float, z: float, h: float, slope: float) -> Color:
		var c := Color(0.86, 0.79, 0.6).lerp(Color(0.72, 0.64, 0.46), clampf(-h / 2.0, 0.0, 1.0))   # dry sand, wet sand
		if h > 1.2:
			c = Color(0.34, 0.5, 0.25).lerp(Color(0.45, 0.42, 0.38), smoothstep(0.3, 0.6, slope))     # island grass and rock
		c = c.darkened(0.06 * bumps.get_noise_2d(x * 4.0, z * 4.0))
		return c
	_terrain(n, half, 560.0, height, colour, "ground")
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1200, 1200)
	pm.subdivide_width = 80
	pm.subdivide_depth = 80
	sea.mesh = pm
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SEA_SHADER
	m.shader = sh
	m.set_shader_parameter("shore", shore)
	sea.material_override = m
	sea.position.y = -0.4
	n.add_child(sea)
	# trees on the islands, a lighthouse on one, and a few sailing boats
	var spots := []
	for il in isles:
		for k in int(float(il[1]) * 0.8):
			var a := rng.randf() * TAU
			var r := rng.randf_range(0.0, float(il[1]) * 0.6)
			var p := (il[0] as Vector2) + Vector2(cos(a), sin(a)) * r
			var y: float = height.call(p.x, p.y)
			if y > 1.0:
				spots.append([Vector3(p.x, y - 0.2, p.y), rng.randf_range(1.2, 2.2), rng.randf() * TAU])
	_forest(n, spots, false, [Color(1, 1, 1), Color(0.9, 1.0, 0.85)])
	var first: Array = isles[0]
	var lp := first[0] as Vector2
	var ly: float = height.call(lp.x, lp.y)
	_lighthouse(n, Vector3(lp.x, ly - 0.5, lp.y))
	for k in 5:
		var at := _around(half, rng, 40.0, 180.0)
		if height.call(at.x, at.z) > -1.5:
			continue
		_boat(n, Vector3(at.x, -0.35, at.z), rng.randf() * TAU, rng)


static func _lighthouse(n: Node3D, at: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 6:   # red and white bands, tapering
		var y0 := k * 3.0
		var c := Color(0.85, 0.15, 0.12) if k % 2 == 0 else Color(0.95, 0.95, 0.92)
		_cone(st, at + Vector3(0, y0, 0), 3.0 - k * 0.3, 3.0 - (k + 1) * 0.3, 3.0, 14, c, c)
	_cone(st, at + Vector3(0, 18.0, 0), 1.6, 1.6, 2.2, 12, Color(0.95, 0.9, 0.6), Color(1.0, 0.95, 0.7))
	_cone(st, at + Vector3(0, 20.2, 0), 2.0, 0.0, 1.6, 12, Color(0.15, 0.15, 0.18), Color(0.2, 0.2, 0.22))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.7
	mi.material_override = m
	n.add_child(mi)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.9, 0.6)
	lamp.light_energy = 2.0
	lamp.omni_range = 30.0
	lamp.position = at + Vector3(0, 19.0, 0)
	n.add_child(lamp)


static func _boat(n: Node3D, at: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hull := Color(0.92, 0.92, 0.9) if rng.randf() < 0.5 else Color(0.25, 0.32, 0.5)
	var L := rng.randf_range(5.0, 8.0)
	var W := L * 0.32
	var deck := [Vector3(0, 0.6, L * 0.5), Vector3(W * 0.5, 0.6, L * 0.1), Vector3(W * 0.45, 0.6, -L * 0.5), Vector3(-W * 0.45, 0.6, -L * 0.5), Vector3(-W * 0.5, 0.6, L * 0.1)]
	var keel := [Vector3(0, -0.4, L * 0.45), Vector3(0, -0.5, -L * 0.45)]
	for i in 5:
		var a: Vector3 = deck[i]
		var b: Vector3 = deck[(i + 1) % 5]
		_tri_up(st, a, b, keel[0] if i < 2 or i == 4 else keel[1], hull)
	_tri_up(st, deck[0], deck[2], deck[3], Color(0.6, 0.45, 0.3))
	_tri_up(st, deck[0], deck[1], deck[2], Color(0.6, 0.45, 0.3))
	_tri_up(st, deck[0], deck[3], deck[4], Color(0.6, 0.45, 0.3))
	var mast := Vector3(0, 0.6, L * 0.05)
	_tri_up(st, mast, mast + Vector3(0, L * 1.1, 0), mast + Vector3(0, 0.3, -L * 0.45), Color(0.97, 0.96, 0.92))
	_tri_up(st, mast + Vector3(0, L * 0.9, 0.02), mast + Vector3(0, 0.3, L * 0.4), mast + Vector3(0, 0.25, 0.02), Color(0.95, 0.93, 0.88))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.position = at
	mi.rotation.y = yaw
	n.add_child(mi)


# ---------------------------------------------------------------- mountains: foothills, forests, snowy peaks

static func _mountains(n: Node3D, half: float, rng: RandomNumberGenerator) -> void:
	var s := rng.randi()
	var ridge := _noise(s, 0.007, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 5)
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var hills := _noise(s + 1, 0.012)
	var detail := _noise(s + 2, 0.06)
	var height := func(x: float, z: float) -> float:
		var d := Vector2(x, z).length() - half * 1.42
		var peaks := (ridge.get_noise_2d(x, z) * 0.5 + 0.5)
		var h := pow(peaks, 1.6) * 210.0 * smoothstep(60.0, 260.0, d)
		h += (hills.get_noise_2d(x, z) * 0.5 + 0.5) * 22.0 * _ramp(x, z, half, 50.0)
		return h + detail.get_noise_2d(x, z) * 2.0 * _ramp(x, z, half, 10.0)
	var colour := func(x: float, z: float, h: float, slope: float) -> Color:
		var c := Color(0.36, 0.5, 0.27).lerp(Color(0.3, 0.42, 0.24), detail.get_noise_2d(x * 2.0, z * 2.0) * 0.5 + 0.5)
		var rock := Color(0.44, 0.42, 0.45).lerp(Color(0.52, 0.47, 0.42), detail.get_noise_2d(x, z) * 0.5 + 0.5)
		c = c.lerp(rock, smoothstep(0.25, 0.45, slope) * smoothstep(20.0, 60.0, h) + smoothstep(55.0, 95.0, h))
		var snow := smoothstep(95.0, 125.0, h + detail.get_noise_2d(x * 2.0, z * 2.0) * 20.0) * (1.0 - smoothstep(0.45, 0.7, slope))
		return c.lerp(Color(0.95, 0.96, 1.0), snow)
	_terrain(n, half, 620.0, height, colour)
	var where := _noise(s + 3, 0.01)
	_forest(n, _woods(half, rng, 1400, 8.0, 330.0, height, where, 70.0), true,
			[Color(1, 1, 1), Color(0.85, 0.95, 0.9), Color(0.95, 1.05, 0.95)])


# ---------------------------------------------------------------- city: roads in, suburbs, towers

static func _city(n: Node3D, half: float, rng: RandomNumberGenerator) -> void:
	var s := rng.randi()
	var detail := _noise(s, 0.03)
	var flat := func(x: float, z: float) -> float: return detail.get_noise_2d(x, z) * 0.3 * _ramp(x, z, half, 20.0)
	var colour := func(x: float, z: float, h: float, slope: float) -> Color:
		var c := Color(0.4, 0.52, 0.3).lerp(Color(0.34, 0.44, 0.27), detail.get_noise_2d(x * 2.0, z * 2.0) * 0.5 + 0.5)
		var d := Vector2(x, z).length()
		return c.lerp(Color(0.45, 0.45, 0.46), smoothstep(half * 1.42 + 140.0, half * 1.42 + 170.0, d))   # paved downtown
	_terrain(n, half, 560.0, flat, colour)
	# roads leading off from each side of the map toward the city, with kerbs and dashes, and street lamps
	var asphalt := _mat(Color(0.2, 0.2, 0.22), 0.8)
	var kerb := _mat(Color(0.62, 0.62, 0.6), 0.9)
	var paint := _mat(Color(0.95, 0.85, 0.3), 0.6)
	for k in 4:
		var dir := Vector3(cos(k * PI / 2.0), 0, sin(k * PI / 2.0))
		var yaw := atan2(dir.x, dir.z)
		var road := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(8.0, 0.1, 240.0)
		road.mesh = rb
		road.material_override = asphalt
		road.position = dir * (half + 121.0) + Vector3.UP * 0.25
		road.rotation.y = yaw
		n.add_child(road)
		for sd in [-1.0, 1.0]:
			var kb := MeshInstance3D.new()
			var km := BoxMesh.new()
			km.size = Vector3(0.4, 0.3, 240.0)
			kb.mesh = km
			kb.material_override = kerb
			kb.position = road.position + Basis(Vector3.UP, yaw) * Vector3(sd * 4.2, 0.0, 0.0)
			kb.rotation.y = yaw
			n.add_child(kb)
		var dashes := MultiMesh.new()
		dashes.transform_format = MultiMesh.TRANSFORM_3D
		var dm := BoxMesh.new()
		dm.size = Vector3(0.22, 0.04, 2.4)
		dashes.mesh = dm
		dashes.instance_count = 55
		for i in 55:
			dashes.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), dir * (half + 3.0 + i * 4.4) + Vector3(0, 0.32, 0)))
		var dmi := MultiMeshInstance3D.new()
		dmi.multimesh = dashes
		dmi.material_override = paint
		n.add_child(dmi)
	var homes := _houses(n, half, rng, flat, 46, 8.0, 120.0, true)
	var where := _noise(s + 5, 0.02)
	# trees: none in a house, none on a road
	var grown := []   # (and none inside another)
	var trees := _woods(half, rng, 260, 8.0, 130.0, flat, where).filter(func(spot) -> bool:
		var tp: Vector3 = spot[0]
		if minf(absf(tp.x), absf(tp.z)) < 7.0 and maxf(absf(tp.x), absf(tp.z)) > half:
			return false
		for home in homes:
			if Vector2(tp.x - (home[0] as Vector3).x, tp.z - (home[0] as Vector3).z).length() < float(home[1]) + 5.0:
				return false
		for other in grown:
			if (tp - (other as Vector3)).length() < 4.5:
				return false
		grown.append(tp)
		return true)
	_forest(n, trees, false, [Color(1, 1, 1), Color(0.9, 1.0, 0.85)])
	# the skyline: towers in a band, some stepped back as they rise, with rooftop clutter
	# (Sara, Nov 28: "give more variety to the skyscrapers", and none standing inside another. They used to be
	# five greys of the same punched-window box, some stepped. Now: stone, brick, concrete, steel and glass in
	# more colours; four ways of setting out the windows (the shader's `style`); slabs, slender towers and low
	# wide blocks; and tops that are flat, stepped like a ziggurat, pitched, pyramid-capped or spired.)
	var shades := [Vector3(0.55, 0.58, 0.65), Vector3(0.45, 0.48, 0.55), Vector3(0.66, 0.62, 0.58), Vector3(0.38, 0.4, 0.48), Vector3(0.7, 0.68, 0.62),
			Vector3(0.52, 0.3, 0.24), Vector3(0.78, 0.72, 0.6), Vector3(0.28, 0.31, 0.36), Vector3(0.84, 0.84, 0.82), Vector3(0.44, 0.36, 0.3)]
	var glasses := [Vector3(0.16, 0.2, 0.27), Vector3(0.2, 0.36, 0.48), Vector3(0.17, 0.36, 0.33), Vector3(0.38, 0.3, 0.2), Vector3(0.1, 0.12, 0.16)]
	var bm := BoxMesh.new()
	var pyramid := CylinderMesh.new()   # (four-sided: a square pyramid, its corners on the axes)
	pyramid.top_radius = 0.0
	pyramid.bottom_radius = 0.7071
	pyramid.height = 1.0
	pyramid.radial_segments = 4
	pyramid.rings = 1
	var gable := PrismMesh.new()
	var sh := Shader.new()
	sh.code = TOWER_SHADER
	var roof := _mat(Color(0.3, 0.3, 0.32), 0.8)
	var stood := []   # [where, radius]
	for i in 170:
		var at := _around(half, rng, 150.0, 260.0)
		var ang := fposmod(atan2(at.z, at.x), PI / 2.0)
		if ang < 0.07 or ang > PI / 2.0 - 0.07:
			continue   # (leave the roads clear)
		var build := rng.randf()   # which sort: a slender tower, a low wide block, or the usual
		var w := rng.randf_range(10.0, 22.0)
		var h := rng.randf_range(25.0, 70.0) * (1.6 if rng.randf() < 0.18 else 1.0)
		if build < 0.14:
			w = rng.randf_range(9.0, 12.0)
			h = rng.randf_range(85.0, 125.0)
		elif build < 0.3:
			w = rng.randf_range(24.0, 34.0)
			h = rng.randf_range(12.0, 22.0)
		var dpt := w * rng.randf_range(0.7, 1.3)
		var clear := true
		for other in stood:
			if (at - (other[0] as Vector3)).length() < float(other[1]) + maxf(w, dpt) * 0.62 + 2.0:
				clear = false
				break
		if not clear:
			continue
		stood.append([at, maxf(w, dpt) * 0.62])
		var m := ShaderMaterial.new()
		m.shader = sh
		var style := rng.randi() % 4
		m.set_shader_parameter("wall", shades[rng.randi() % shades.size()])
		m.set_shader_parameter("seed", float(i) * 3.7)
		m.set_shader_parameter("style", style)
		m.set_shader_parameter("pitch", Vector2(rng.randf_range(2.2, 3.4) if style != 1 else rng.randf_range(1.4, 2.0), rng.randf_range(3.2, 4.0)))
		m.set_shader_parameter("glass", glasses[0] if style == 0 else glasses[rng.randi() % glasses.size()])
		var yaw := atan2(at.x, at.z)
		var crown := rng.randi() % 5   # 0 flat, 1 stepped (2 or 3 tiers), 2 a ziggurat, 3 pitched or pyramid, 4 a spire
		var tiers := 1
		if crown == 1:
			tiers = rng.randi_range(2, 3)
		elif crown == 2:
			tiers = 5
		var base := 0.0
		var top_k := 1.0
		for t in tiers:
			var th := h
			if tiers > 1:
				th = h * (0.6 if t == 0 else 0.4 / (tiers - 1))
			var k := 1.0 - (0.18 if tiers <= 3 else 0.13) * t
			top_k = k
			var mi := MeshInstance3D.new()
			mi.mesh = bm
			mi.material_override = m
			mi.position = at + Vector3(0, base + th / 2.0, 0)
			mi.scale = Vector3(w * k, th, dpt * k)
			mi.rotation.y = yaw
			n.add_child(mi)
			base += th
		if crown == 3:
			var cap := MeshInstance3D.new()
			var cap_h := minf(w, dpt) * rng.randf_range(0.35, 0.8)
			if absf(w - dpt) < w * 0.12:   # square enough for a pyramid
				cap.mesh = pyramid
				cap.scale = Vector3(minf(w, dpt) * top_k, cap_h, minf(w, dpt) * top_k)
				cap.rotation.y = yaw + PI * 0.25
			else:
				cap.mesh = gable
				cap.scale = Vector3(w * top_k, cap_h * 0.7, dpt * top_k)
				cap.rotation.y = yaw
				cap_h *= 0.7
			cap.material_override = _mat(Color(0.25, 0.33, 0.3) if rng.randf() < 0.5 else Color(0.36, 0.24, 0.2), 0.6)
			cap.position = at + Vector3.UP * (base + cap_h * 0.5)
			n.add_child(cap)
			continue
		if crown == 4:
			var spire := MeshInstance3D.new()
			var sm := CylinderMesh.new()
			sm.top_radius = 0.0
			sm.bottom_radius = minf(w, dpt) * top_k * 0.28
			sm.height = h * rng.randf_range(0.25, 0.45)
			sm.radial_segments = 6
			sm.rings = 1
			spire.mesh = sm
			spire.material_override = roof
			spire.position = at + Vector3.UP * (base + sm.height * 0.5)
			n.add_child(spire)
			continue
		w *= top_k
		dpt *= top_k
		# rooftop: a water tank, an aerial, a plant room
		var top := at + Vector3.UP * base
		var b := Basis(Vector3.UP, yaw)
		var box := MeshInstance3D.new()
		box.mesh = bm
		box.material_override = roof
		box.position = top + b * Vector3(w * 0.15, 1.5, -dpt * 0.15)
		box.scale = Vector3(w * 0.3, 3.0, dpt * 0.25)
		box.rotation.y = yaw
		n.add_child(box)
		if rng.randf() < 0.45:
			var tank := MeshInstance3D.new()
			var tm := CylinderMesh.new()
			tm.top_radius = 1.6
			tm.bottom_radius = 1.6
			tm.height = 3.0
			tm.radial_segments = 10
			tank.mesh = tm
			tank.material_override = _mat(Color(0.45, 0.32, 0.22))
			tank.position = top + b * Vector3(-w * 0.2, 2.5, dpt * 0.15)
			n.add_child(tank)
		if rng.randf() < 0.5:
			var aer := MeshInstance3D.new()
			var am := CylinderMesh.new()
			am.top_radius = 0.1
			am.bottom_radius = 0.2
			am.height = rng.randf_range(6.0, 14.0)
			am.radial_segments = 5
			aer.mesh = am
			aer.material_override = roof
			aer.position = top + Vector3.UP * am.height * 0.5
			n.add_child(aer)
