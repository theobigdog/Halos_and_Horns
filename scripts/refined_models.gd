# Refined models (Ted's wife, Nov 27: "refine the cars and street light, bush, oak and birch trees, wheelbarrow,
# bench, grass, dirt, fence separate, dumpster, fire hydrants, all graveyard props and structures, landscaping, all
# trees"; Ted: "refine all of them... they all matter the most"). Each of these KayKit models is rebuilt here in
# code with real detail, the same size and footprint as the original (its catalog size), standing with its
# bottom-centre on (0, 0, 0) and facing the same way, so maps, rows, disguises and collision all carry on.
# Models._raw() uses build() instead of loading the model; the collision follows the new shape, except parts
# marked "no_collide" (leaves, little bits). Meshes are made once and shared by every copy.
extends RefCounted

const CP = preload("res://scripts/classic_props.gd")

static var _cache := {}

# Models rebuilt bigger than the KayKit original (Models.size uses these, so a prop's box fits too)
const SIZES := {"city/bench": Vector3(1.8, 0.9, 0.72)}


static var _grave: GDScript


static func _graveyard() -> GDScript:
	if _grave == null:
		_grave = load("res://scripts/refined_graveyard.gd")
	return _grave


static var _trees: GDScript


static func _tree_script() -> GDScript:
	if _trees == null:
		_trees = load("res://scripts/refined_trees.gd")
	return _trees


static var _furn: GDScript


static func _furniture() -> GDScript:
	if _furn == null:
		_furn = load("res://scripts/refined_furniture.gd")
	return _furn


static var _vehicles: GDScript


static func _script_for(id: String) -> GDScript:
	if id.begins_with("city/car_"):
		if _vehicles == null:
			_vehicles = load("res://scripts/vehicles.gd")
		return _vehicles if _vehicles.BUILDERS.has(id) else null
	if BUILDERS.has(id):
		return load("res://scripts/refined_models.gd")
	if id.begins_with("furniture/") and _furniture().BUILDERS.has(id):
		return _furniture()
	if (id.begins_with("halloween/") or id.begins_with("medieval/")) and _tree_script().BUILDERS.has(id):
		return _tree_script()
	if id.begins_with("halloween/") and _graveyard().BUILDERS.has(id):
		return _graveyard()
	return null


static func has(id: String) -> bool:
	return _script_for(id) != null


const BUILDERS := {
	"city/firehydrant": "_hydrant",
	"city/streetlight": "_streetlight",
	"city/streetlight_flicker": "_streetlight",
	"city/dumpster": "_dumpster",
	"city/bench": "_park_bench",
	"city/bush": "_potted_bush",
	"medieval/wheelbarrow": "_wheelbarrow",
	"halloween/bench": "_grave_bench",
}


static func build(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = id.get_slice("/", 1)
	var s := _script_for(id)
	s.call(s.BUILDERS[id], root, id)
	_stand(root)
	return root


# Stand it on the ground, centred over the origin, the way the catalog's offset stands the KayKit models (their
# rows, extending and footprints all count on it). Moves the parts, and any flame spots with them.
static func _stand(root: Node3D) -> void:
	var box := AABB()
	var first := true
	var inv := root.transform.affine_inverse()
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var at: Node = mi
		while at != null and at != root:
			if at is Node3D:
				xf = (at as Node3D).transform * xf
			at = at.get_parent()
		var b: AABB = xf * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var shift := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	if shift.length() < 0.001:
		return
	for c in root.get_children():
		if c is Node3D:
			(c as Node3D).position -= shift
	if root.has_meta("flame_spots"):
		var moved := []
		for sp in root.get_meta("flame_spots"):
			moved.append((sp as Vector3) - shift)
		root.set_meta("flame_spots", moved)


static func _cached(key: String, make: Callable) -> Array:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


static func _put(root: Node3D, mesh: Mesh, mat: Material, collide := true, at := Transform3D.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = at
	if not collide:
		mi.set_meta("no_collide", true)
	root.add_child(mi)
	return mi


static func _glass() -> StandardMaterial3D:
	if not _cache.has("glass"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.1, 0.13, 0.16)
		m.metallic = 0.6
		m.roughness = 0.04
		m.clearcoat_enabled = true
		_cache["glass"] = m
	return _cache["glass"]


static func _glow(c: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "glow_%s_%s" % [c.to_html(), energy]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
		_cache[key] = m
	return _cache[key]


# The police light bar (Sara, Nov 27: "flash blue and red like it's pulling someone over"): red and blue take turns,
# each a quick double blink, bright when on and a dim coloured lens when off. Time-driven: no script per car.
const FLASH_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec4 col : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float half_cycle = 0.0;   // 0: red's turn first, 1: blue's
void fragment() {
	float t = fract(TIME * 1.6 + half_cycle * 0.5);          // one cycle: red's half, then blue's
	float mine = step(t, 0.5);
	float k = fract(t * 2.0);                                // where we are in our half
	float blink = step(k, 0.22) + step(0.32, k) * step(k, 0.54);
	float on = mine * clamp(blink, 0.0, 1.0);
	ALBEDO = col.rgb * mix(0.25, 3.5, on);
}
"""


static func _flasher(c: Color, phase: float) -> ShaderMaterial:
	var key := "flash_%s_%s" % [c.to_html(), phase]
	if not _cache.has(key):
		var sh := Shader.new()
		sh.code = FLASH_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("col", c)
		m.set_shader_parameter("half_cycle", phase)
		_cache[key] = m
	return _cache[key]


static func _paint(c: Color, rough := 0.3, metal := 0.15) -> StandardMaterial3D:
	var key := "paint_%s_%s_%s" % [c.to_html(), rough, metal]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.albedo_color = Color.WHITE
		m.roughness = rough
		m.metallic = metal
		m.clearcoat_enabled = rough < 0.35
		m.clearcoat_roughness = 0.1
		_cache[key] = m
	return _cache[key]


# A round-cornered slab (centre, size, corner radius): eight-sided corners, for smooth-looking boxes.
static func _rbox(st: SurfaceTool, c: Vector3, s: Vector3, r: float, col: Color, bas := Basis()) -> void:
	r = minf(r, minf(s.x, s.z) * 0.5 - 0.001)
	var hx := s.x * 0.5 - r
	var hz := s.z * 0.5 - r
	var ring := []
	for q in 4:
		var cx := hx if q == 0 or q == 3 else -hx
		var cz := hz if q < 2 else -hz
		for k in 3:
			var a := PI * 0.5 * q + PI * 0.25 * k
			ring.append(Vector2(cx + cos(a) * r, cz + sin(a) * r))
	var n := ring.size()
	var y0 := -s.y * 0.5
	var y1 := s.y * 0.5
	for i in n:
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % n]
		var p00 := c + bas * Vector3(a.x, y0, a.y)
		var p01 := c + bas * Vector3(b.x, y0, b.y)
		var p10 := c + bas * Vector3(a.x, y1, a.y)
		var p11 := c + bas * Vector3(b.x, y1, b.y)
		var mid := (a + b) * 0.5
		CP._quad(st, p00, p01, p11, p10, col, bas * Vector3(mid.x, 0, mid.y))
		CP._tri(st, c + bas * Vector3(0, y1, 0), p10, p11, col, bas * Vector3.UP)
		CP._tri(st, c + bas * Vector3(0, y0, 0), p00, p01, col, bas * Vector3.DOWN)


# ================================================================ town

# A fire hydrant: a cast flange on the kerb with bolts, a fluted barrel, the bonnet dome with its pentagon
# operating nut, two hose outlets with chained caps on the sides and the big pumper outlet on the front, all in
# glossy red paint chipped at the edges, the caps silver.
static func _hydrant(root: Node3D, _id: String) -> void:
	var parts := _cached("hydrant", func() -> Array:
		var body := CP._begin()
		var red := Color(0.78, 0.1, 0.08)
		var dark := red.darkened(0.25)
		var prof := [[0.0, 0.0], [0.3, 0.0], [0.3, 0.07], [0.26, 0.1], [0.2, 0.12], [0.2, 0.62], [0.235, 0.66], [0.235, 0.72],
				[0.21, 0.74], [0.19, 0.8], [0.14, 0.88], [0.06, 0.92], [0.0, 0.925]]
		var paint_col := func(i: int, a: float) -> Color:
			var c := red if i != 3 and i != 7 else dark
			if CP._h(floor(a * 23.0) + i * 3.0) > 0.975 and i > 4:
				c = c.lerp(Color(0.5, 0.45, 0.4), 0.5)   # chipped paint
			return c
		var flutes := func(i: int, a: float) -> float:
			return 1.0 + (0.025 * cos(a * 8.0) if i == 5 else 0.0)
		CP._lathe(body, prof, 28, paint_col, Vector3.ZERO, flutes)
		# bolts round the flange
		for k in 8:
			var a := TAU * k / 8.0
			CP._lathe(body, [[0.0, 0.0], [0.022, 0.0], [0.022, 0.02], [0.0, 0.03]], 6, func(_i, _a): return dark, Vector3(cos(a) * 0.255, 0.07, sin(a) * 0.255))
		var steel := CP._begin()
		var silver := Color(0.75, 0.75, 0.72)
		# the operating nut on top
		CP._lathe(steel, [[0.0, 0.92], [0.05, 0.92], [0.05, 0.985], [0.0, 0.99]], 5, func(_i, _a): return silver)
		# outlets: two side, one big front (pointing +z)
		for o in [[Vector3(1, 0, 0), 0.075, 0.55], [Vector3(-1, 0, 0), 0.075, 0.55], [Vector3(0, 0, 1), 0.105, 0.48]]:
			var dir: Vector3 = o[0]
			var r: float = o[1]
			var y: float = o[2]
			var base := Vector3(0, y, 0) + dir * 0.17
			CP._tube(body, [base, base + dir * 0.09], [r * 1.05, r], red, 14)
			CP._tube(steel, [base + dir * 0.09, base + dir * 0.13, base + dir * 0.135], [r * 1.12, r * 1.12, r * 0.6], silver, 6)
			# the chain hanging down from the cap
			for k in 4:
				var p := base + dir * 0.11 + Vector3.DOWN * (0.04 + k * 0.035) + dir.cross(Vector3.UP) * 0.03 * sin(k)
				CP._ring(steel, p, 0.013, 0.004, silver.darkened(0.2), 8, 4)
		return [CP._end(body, false), CP._end(steel, false)])
	_put(root, parts[0], _paint(Color.WHITE, 0.35, 0.2))
	_put(root, parts[1], _paint(Color.WHITE, 0.25, 0.85), false)


# A street light: a fluted cast base with bolts on a little plinth, a tapering steel pole, and a swan-neck arm
# curving out to a cobra-head lamp with a glowing lens underneath. (The KayKit one's footprint: the pole off to
# one side, the head 1.2 m out.)
static func _streetlight(root: Node3D, _id: String) -> void:
	var parts := _cached("streetlight", func() -> Array:
		var pole := CP._begin()
		var grey := Color(0.32, 0.34, 0.36)
		var px := -0.45   # the pole's x (the arm reaches to +x)
		var base_col := func(i: int, _a: float) -> Color:
			return grey.darkened(0.15 if i < 2 else 0.0)
		var base_flute := func(i: int, a: float) -> float:
			return 1.0 + (0.08 * absf(cos(a * 6.0)) if i == 4 else 0.0)
		CP._lathe(pole, [[0.0, 0.0], [0.15, 0.0], [0.15, 0.05], [0.12, 0.08], [0.1, 0.5], [0.075, 0.6], [0.07, 0.62]], 16, base_col, Vector3(px, 0, 0), base_flute)
		CP._lathe(pole, [[0.07, 0.62], [0.055, 3.7], [0.05, 3.75], [0.0, 3.76]], 14, func(_i, _a): return grey, Vector3(px, 0, 0))
		for k in 4:
			var a := TAU * k / 4.0 + PI / 4.0
			CP._lathe(pole, [[0.0, 0.05], [0.02, 0.05], [0.02, 0.075], [0.0, 0.085]], 6, func(_i, _a): return grey.darkened(0.3),
					Vector3(px + cos(a) * 0.12, 0, sin(a) * 0.12))
		# the swan neck: up, over and out
		var arm := []
		for k in 13:
			var t := float(k) / 12.0
			var ang := t * PI * 0.62
			arm.append(Vector3(px + 0.35 * (1.0 - cos(ang)) + t * t * 0.3, 3.62 + 0.45 * sin(ang) - t * t * 0.16, 0))
		var radii := []
		for k in arm.size():
			radii.append(lerpf(0.045, 0.032, float(k) / (arm.size() - 1)))
		CP._tube(pole, arm, radii, grey, 10)
		# the cobra head: a long rounded shell, the lens underneath
		var head_at: Vector3 = arm[arm.size() - 1] + Vector3(0.06, -0.03, 0)
		var head := CP._begin()
		for k in 10:
			var t0 := float(k) / 10.0
			var t1 := float(k + 1) / 10.0
			var w0 := 0.13 * sin(PI * (0.15 + t0 * 0.85)) + 0.02
			var w1 := 0.13 * sin(PI * (0.15 + t1 * 0.85)) + 0.02
			for s in 8:
				var a0 := PI * s / 8.0
				var a1 := PI * (s + 1) / 8.0
				var x0 := head_at.x - 0.2 + t0 * 0.42
				var x1 := head_at.x - 0.2 + t1 * 0.42
				var p00 := Vector3(x0, head_at.y + sin(a0) * w0 * 0.75, cos(a0) * w0)
				var p01 := Vector3(x0, head_at.y + sin(a1) * w0 * 0.75, cos(a1) * w0)
				var p10 := Vector3(x1, head_at.y + sin(a0) * w1 * 0.75, cos(a0) * w1)
				var p11 := Vector3(x1, head_at.y + sin(a1) * w1 * 0.75, cos(a1) * w1)
				CP._quad(head, p00, p10, p11, p01, grey.lightened(0.05), Vector3(0, sin((a0 + a1) * 0.5), cos((a0 + a1) * 0.5)))
		var lens := CP._begin()
		_rbox(lens, head_at + Vector3(0.02, -0.01, 0), Vector3(0.3, 0.02, 0.18), 0.07, Color(1.0, 0.95, 0.8))
		return [CP._end(pole, false), CP._end(head, false), CP._end(lens, false)])
	_put(root, parts[0], _paint(Color.WHITE, 0.45, 0.6))
	_put(root, parts[1], _paint(Color.WHITE, 0.4, 0.5), false)
	_put(root, parts[2], _glow(Color(1.0, 0.92, 0.75), 2.5), false)


# The town dumpster, shut: a steel bin tapering a little toward the bottom, ribbed, a lip round the top, two
# black plastic lids, fork pockets on the ends, casters, and some dents and rust. (2.55 x 1.43 x 1.59)
static func _dumpster(root: Node3D, _id: String) -> void:
	var parts := _cached("dumpster", func() -> Array:
		var st := CP._begin()
		var green := Color(0.13, 0.42, 0.24)
		var w := 2.4
		var d := 1.45
		var y0 := 0.2
		var top := 1.25
		# body: front and back lean in toward the bottom
		var lo := Vector3(w * 0.5, y0, d * 0.5 - 0.1)
		var hi := Vector3(w * 0.5, top, d * 0.5)
		var corners := [Vector3(-lo.x, lo.y, -lo.z), Vector3(lo.x, lo.y, -lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(-lo.x, lo.y, lo.z),
				Vector3(-hi.x, hi.y, -hi.z), Vector3(hi.x, hi.y, -hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(-hi.x, hi.y, hi.z)]
		for f in [[0, 1, 5, 4, Vector3(0, 0, -1)], [1, 2, 6, 5, Vector3(1, 0, 0)], [2, 3, 7, 6, Vector3(0, 0, 1)], [3, 0, 4, 7, Vector3(-1, 0, 0)], [0, 3, 2, 1, Vector3.DOWN]]:
			CP._quad(st, corners[f[0]], corners[f[1]], corners[f[2]], corners[f[3]], green, f[4])
		# ribs on front and back, and the top lip
		for k in 6:
			var x := -w * 0.5 + w * (k + 0.5) / 6.0
			for sz: float in [-1.0, 1.0]:
				CP._box(st, Vector3(x, (y0 + top) * 0.5, sz * (d * 0.5 - 0.03)), Vector3(0.07, top - y0 - 0.1, 0.1), green.darkened(0.12), Basis(Vector3.RIGHT, -sz * 0.09))
		CP._box(st, Vector3(0, top + 0.02, 0), Vector3(w + 0.08, 0.06, d + 0.08), green.darkened(0.2))
		for sx: float in [-1.0, 1.0]:
			for z: float in [-0.4, 0.4]:
				CP._box(st, Vector3(sx * (w * 0.5 + 0.04), 0.62, z), Vector3(0.08, 0.14, 0.3), green.darkened(0.3))
		# rust streaks and dents (darker patches)
		for k in 6:   # rust running down from the lip
			var x := -w * 0.45 + w * 0.9 * CP._h(k * 7.1)
			CP._box(st, Vector3(x, top - 0.15 - 0.1 * CP._h(k * 3.3), d * 0.5 + 0.004), Vector3(0.03 + 0.03 * CP._h(k), 0.2 + 0.2 * CP._h(k * 1.7), 0.004), Color(0.3, 0.2, 0.1))
		var lids := CP._begin()
		var black := Color(0.08, 0.08, 0.09)
		for sx: float in [-1.0, 1.0]:
			_rbox(lids, Vector3(sx * w * 0.25, top + 0.1, 0.02), Vector3(w * 0.5 - 0.03, 0.08, d + 0.04), 0.04, black, Basis(Vector3.RIGHT, -0.08))
			for z: float in [-0.35, 0.35]:
				CP._box(lids, Vector3(sx * w * 0.25, top + 0.15, z), Vector3(w * 0.5 - 0.2, 0.03, 0.08), black.lightened(0.05), Basis(Vector3.RIGHT, -0.08))
		var wheels := CP._begin()
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var c := Vector3(sx * (w * 0.5 - 0.2), 0.0, sz * (d * 0.5 - 0.25))
				CP._box(wheels, c + Vector3(0, 0.16, 0), Vector3(0.1, 0.08, 0.1), Color(0.3, 0.3, 0.32))
				CP._tube(wheels, [c + Vector3(-0.03, 0.07, 0), c + Vector3(0.03, 0.07, 0)], [0.07, 0.07], Color(0.05, 0.05, 0.05), 10)
		return [CP._end(st, false), CP._end(lids, false), CP._end(wheels, false)])
	_put(root, parts[0], _paint(Color.WHITE, 0.55, 0.5))
	_put(root, parts[1], _paint(Color.WHITE, 0.7, 0.0))
	_put(root, parts[2], _paint(Color.WHITE, 0.6, 0.3), false)


# A park bench: five slatted boards (three on the seat, two on the back) on two cast-iron ends with scrolls,
# armrests, and bolt heads. (1.8 x 0.45 x 0.68: the KayKit bench is a low seat; ours keeps its size)
static func _park_bench(root: Node3D, _id: String) -> void:
	# (Sara, Nov 27: "refine the bench... make a higher backrest": a proper sit-down height and a back to lean on)
	var parts := _cached("park_bench2", func() -> Array:
		var wood := CP._begin()
		var iron := CP._begin()
		var w := 1.8
		var seat := 0.44
		var ic := Color(0.09, 0.1, 0.09)
		var slat := Color(0.56, 0.37, 0.2)
		for k in 4:   # the seat: four rounded slats with gaps
			var z := 0.2 - k * 0.125
			_rbox(wood, Vector3(0, seat, z), Vector3(w - 0.04, 0.04, 0.105), 0.018, slat.darkened(0.04 * float(k % 2)))
		var lean := Basis(Vector3.RIGHT, -0.24)
		for k in 3:   # the back: three slats, leaning back a little
			var y := 0.56 + k * 0.13
			var z := -0.27 - (y - 0.5) * 0.24
			_rbox(wood, Vector3(0, y, z), Vector3(w - 0.04, 0.1, 0.035), 0.016, slat.darkened(0.03 * float(k)), lean)
		# bolt heads along the slats
		for k in 4:
			for x: float in [-0.62, 0.62]:
				_rbox(iron, Vector3(x, seat + 0.022, 0.2 - k * 0.125), Vector3(0.022, 0.008, 0.022), 0.008, Color(0.35, 0.35, 0.34))
		# cast-iron ends: front leg, back leg rising into the back support, an armrest with a scroll
		for sx: float in [-1.0, 1.0]:
			var x := sx * (w * 0.5 - 0.12)
			CP._tube(iron, [Vector3(x, 0.0, 0.26), Vector3(x, 0.2, 0.25), Vector3(x, seat - 0.03, 0.22)], [0.026, 0.024, 0.022], ic, 8)
			CP._tube(iron, [Vector3(x, 0.0, -0.22), Vector3(x, 0.25, -0.24), Vector3(x, seat, -0.27), Vector3(x, 0.66, -0.31), Vector3(x, 0.86, -0.37)],
					[0.026, 0.024, 0.022, 0.022, 0.02], ic, 8)
			CP._tube(iron, [Vector3(x, seat - 0.03, 0.26), Vector3(x, seat - 0.03, -0.28)], [0.022, 0.022], ic, 8)
			CP._tube(iron, [Vector3(x, seat - 0.02, 0.24), Vector3(x, 0.6, 0.27), Vector3(x, 0.66, 0.18), Vector3(x, 0.65, -0.2), Vector3(x, 0.62, -0.31)],
					[0.02, 0.02, 0.022, 0.022, 0.02], ic, 6)
			for k in 4:   # the scroll under the arm
				CP._ring(iron, Vector3(x, 0.56 - 0.01 * k, 0.2), 0.045 - 0.009 * k, 0.008, ic, 10, 4)
			CP._tube(iron, [Vector3(x - 0.05, 0.02, 0.26), Vector3(x + 0.05, 0.02, 0.26)], [0.02, 0.02], ic, 5)   # feet
			CP._tube(iron, [Vector3(x - 0.05, 0.02, -0.22), Vector3(x + 0.05, 0.02, -0.22)], [0.02, 0.02], ic, 5)
		return [CP._end(wood, false), CP._end(iron, true)])
	_put(root, parts[0], CP._vmat("wood", 0.8))
	_put(root, parts[1], _paint(Color.WHITE, 0.5, 0.6))


# The town's potted bush: a terracotta pot with a rolled rim and a drip saucer, soil, and a round clipped bush of
# leaves (clumps covered in leaf cards, like the classic bush). (0.85 x 1.71 x 0.9)
static func _potted_bush(root: Node3D, _id: String) -> void:
	var parts := _cached("potted_bush", func() -> Array:
		var pot := CP._begin()
		var terra := Color(0.68, 0.33, 0.18)
		var pot_col := func(i: int, a: float) -> Color:
			var c := terra.darkened(0.12 if i >= 6 and i <= 7 else 0.0)
			return c.lerp(Color(0.85, 0.82, 0.75), 0.25 * smoothstep(0.6, 1.0, CP._h(floor(a * 7.0) + i)))   # lime bloom
		CP._lathe(pot, [[0.0, 0.0], [0.34, 0.0], [0.36, 0.025], [0.3, 0.03], [0.28, 0.05], [0.37, 0.5], [0.42, 0.52], [0.42, 0.6],
				[0.37, 0.61], [0.35, 0.56], [0.0, 0.56]], 28, pot_col)
		var soil := CP._begin()
		CP._lathe(soil, [[0.0, 0.58], [0.34, 0.565], [0.35, 0.56]], 20, func(_i, _a): return Color(0.18, 0.11, 0.06))
		return [CP._end(pot, false), CP._end(soil, false)])
	_put(root, parts[0], CP._vmat("plaster", 0.9))
	_put(root, parts[1], CP._vmat("stone", 1.0), false)
	var spots := []
	for k in 14:
		var y := 1.0 + 0.55 * (k / 13.0 - 0.5)
		var a := k * 2.39996
		var rr := 0.25 * sqrt(maxf(0.0, 1.0 - pow((y - 1.0) / 0.42, 2.0)))
		spots.append([Vector3(cos(a) * rr, y + 0.12, sin(a) * rr), 0.24])
	spots.append([Vector3(0, 1.45, 0), 0.2])
	spots.append([Vector3(0, 0.78, 0), 0.24])
	var cl := _cached("potted_bush_clumps", func() -> Array: return [CP._clumps(spots, Color(0.12, 0.3, 0.1), 5, 10, 5)])
	_put(root, cl[0], CP._vmat("plant", 0.9), false)
	CP._foliage(root, "potted_bush_leaves", spots, 900, 0.09, [Color(0.15, 0.38, 0.12), Color(0.2, 0.46, 0.15), Color(0.12, 0.3, 0.09)], 71)
	for c in root.get_children():
		if c is MultiMeshInstance3D:
			c.set_meta("no_collide", true)


# A wheelbarrow: a tapering wooden tray of planks with iron corner straps, two long handles running under it to
# the front, a spoked wooden wheel with an iron tyre, and two legs at the back. (1.43 x 1.13 x 3.03; it points +z)
static func _wheelbarrow(root: Node3D, _id: String) -> void:
	var parts := _cached("wheelbarrow", func() -> Array:
		var wood := CP._begin()
		var iron := CP._begin()
		var plank := Color(0.55, 0.38, 0.22)
		var ic := Color(0.2, 0.2, 0.22)
		var base_y := 0.55
		# the tray: floor and four flaring sides, plank by plank
		for k in 5:
			CP._box(wood, Vector3(-0.4 + k * 0.2, base_y, 0.2), Vector3(0.19, 0.04, 1.2), plank.darkened(0.06 * (k % 2)))
		for s: float in [-1.0, 1.0]:
			for k in 3:
				CP._box(wood, Vector3(s * (0.55 + k * 0.05), base_y + 0.12 + k * 0.14, 0.2), Vector3(0.04, 0.13, 1.25 + k * 0.08), plank.darkened(0.05 * k), Basis(Vector3.BACK, s * 0.35))
		for e in [[0.85, 0.0], [-0.5, PI]]:
			for k in 3:
				CP._box(wood, Vector3(0, base_y + 0.12 + k * 0.14, e[0] + (0.06 * k if e[0] > 0.0 else -0.05 * k)), Vector3(1.05 + k * 0.16, 0.13, 0.04), plank.darkened(0.04 * k), Basis(Vector3.RIGHT, 0.45 if e[0] > 0.0 else -0.3))
		for s: float in [-1.0, 1.0]:   # iron corner straps
			for z: float in [-0.48, 0.86]:
				CP._box(iron, Vector3(s * 0.6, base_y + 0.25, z), Vector3(0.05, 0.42, 0.05), ic)
		# handles: from the axle forks back under the tray, out past the back as grips
		for s: float in [-1.0, 1.0]:
			CP._tube(wood, [Vector3(s * 0.16, 0.42, 1.35), Vector3(s * 0.3, 0.5, 0.6), Vector3(s * 0.45, 0.62, -0.6), Vector3(s * 0.55, 0.72, -1.45)],
					[0.045, 0.045, 0.042, 0.035], plank.darkened(0.15), 8)
			CP._tube(wood, [Vector3(s * 0.4, 0.55, -0.5), Vector3(s * 0.42, 0.0, -0.45)], [0.035, 0.032], plank.darkened(0.2), 6)   # legs
		# the wheel: hub, eight spokes, felloe, iron tyre
		var wc := Vector3(0, 0.38, 1.35)
		CP._tube(wood, [wc + Vector3(-0.1, 0, 0), wc + Vector3(0.1, 0, 0)], [0.07, 0.07], plank.darkened(0.2), 12)
		for k in 8:
			var a := TAU * k / 8.0
			CP._tube(wood, [wc, wc + Vector3(0, sin(a), cos(a)) * 0.32], [0.022, 0.018], plank, 6)
		for k in 24:
			var a0 := TAU * k / 24.0
			var a1 := TAU * (k + 1) / 24.0
			CP._tube(wood, [wc + Vector3(0, sin(a0), cos(a0)) * 0.33, wc + Vector3(0, sin(a1), cos(a1)) * 0.33], [0.035, 0.035], plank.darkened(0.1), 6)
			CP._tube(iron, [wc + Vector3(0, sin(a0), cos(a0)) * 0.37, wc + Vector3(0, sin(a1), cos(a1)) * 0.37], [0.018, 0.018], ic, 5)
		CP._tube(iron, [wc + Vector3(-0.2, 0, 0), wc + Vector3(0.2, 0, 0)], [0.02, 0.02], ic, 6)   # axle
		return [CP._end(wood, false), CP._end(iron, false)])
	var holder := Node3D.new()
	holder.position.z = -0.12   # (centred on the KayKit one's footprint)
	root.add_child(holder)
	_put(holder, parts[0], CP._vmat("wood", 0.85))
	_put(holder, parts[1], _paint(Color.WHITE, 0.6, 0.6))


# A graveyard bench: one thick slab of weathered stone on two carved legs with skull-and-scroll ends, moss in the
# cracks. (1.5 x 0.38 x 0.56)
static func _grave_bench(root: Node3D, _id: String) -> void:
	var parts := _cached("grave_bench", func() -> Array:
		var st := CP._begin()
		var stone := Color(0.55, 0.55, 0.53)
		_rbox(st, Vector3(0, 0.33, 0), Vector3(1.5, 0.09, 0.56), 0.04, stone)
		_rbox(st, Vector3(0, 0.282, 0), Vector3(1.42, 0.02, 0.5), 0.03, stone.darkened(0.15))
		for sx: float in [-1.0, 1.0]:
			var x := sx * 0.55
			_rbox(st, Vector3(x, 0.14, 0), Vector3(0.18, 0.28, 0.42), 0.03, stone.darkened(0.05))
			_rbox(st, Vector3(x, 0.02, 0), Vector3(0.24, 0.04, 0.5), 0.02, stone.darkened(0.1))
			# a little skull carved on each end
			CP._lathe(st, [[0.0, -0.05], [0.04, -0.04], [0.055, 0.0], [0.045, 0.035], [0.0, 0.05]], 10, func(_i, _a): return stone.lightened(0.08),
					Vector3(x + sx * 0.09, 0.16, 0))
		# moss in the corners
		for k in 10:
			var p := Vector3(-0.72 + 1.44 * CP._h(k * 5.1), 0.376, (0.26 if k % 2 == 0 else -0.26) + 0.02 * CP._h(k * 2.7))
			CP._box(st, p, Vector3(0.05 + 0.06 * CP._h(k * 9.3), 0.006, 0.03), Color(0.25, 0.38, 0.15), Basis(Vector3.UP, CP._h(k) * 3.0))   # moss along the edges
		return [CP._end(st, false)])
	_put(root, parts[0], CP._vmat("stone", 0.95))
