# Every prop a demon can possess: how it looks and how it collides.
# Visuals are built with their bottom sitting at y = 0 (the floor).
# Placeholder shapes for now; real models can replace make_visual() later.
extends RefCounted

const Surfaces = preload("res://scripts/surfaces.gd")
const Models = preload("res://scripts/models.gd")

# shape: "box" uses size, "cylinder" uses radius + height (collision only)
# hp / speed: a demon disguised as this prop. Small = fragile but quick,
# big = tanky but slow. First guesses, to be tuned in playtests.
# mass: how hard it is to shove (knock.gd). round: it rolls instead of tipping.
# lying: already on its side, so it only slides.
# The original hand-built props. Random scatter and practice bots still use just these.
const ClassicLook = preload("res://scripts/classic_look.gd")

const CLASSIC := {
	"barrel": {"shape": "cylinder", "radius": 0.45, "height": 1.0, "label": "Barrel", "hp": 120, "speed": 5.0, "mass": 2.5},
	"crate": {"shape": "box", "size": Vector3(0.9, 0.9, 0.9), "label": "Crate", "hp": 110, "speed": 5.5, "mass": 2.0},
	"lamp": {"shape": "cylinder", "radius": 0.3, "height": 1.75, "label": "Lamp", "hp": 80, "speed": 5.5, "mass": 1.2},
	"pumpkin": {"shape": "cylinder", "radius": 0.4, "height": 0.66, "label": "Pumpkin", "hp": 70, "speed": 6.5, "mass": 1.0, "round": true},
	"pot": {"shape": "cylinder", "radius": 0.35, "height": 0.6, "label": "Pot", "hp": 60, "speed": 7.0, "mass": 0.9},
	"bench": {"shape": "box", "size": Vector3(1.6, 0.5, 0.5), "label": "Bench", "hp": 120, "speed": 5.0, "mass": 2.5},
	"books": {"shape": "box", "size": Vector3(0.45, 0.35, 0.3), "label": "Stack of books", "hp": 50, "speed": 7.5, "mass": 0.6},
	"hay": {"shape": "box", "size": Vector3(1.2, 0.8, 0.8), "label": "Hay bale", "hp": 150, "speed": 4.5, "mass": 3.0},
	"apple": {"shape": "box", "size": Vector3(0.26, 0.28, 0.26), "label": "Apple", "hp": 30, "speed": 8.0, "mass": 0.3, "round": true},
	"pickle": {"shape": "box", "size": Vector3(0.5, 0.42, 1.5), "label": "Big floppy pickle", "hp": 90, "speed": 5.5, "mass": 1.4, "lying": true},
}

const DEMON_FORM_HP := 100
const DEMON_FORM_SPEED := 6.5

# Every prop: the classic ones, then every model the catalog marks as a prop (scripts/models.gd).
static var TYPES := _build_types()


# A model prop's health, speed and weight come from its size, on the same curve as the classic props
# (a crate, about 0.7 m³, is 110 hp / 5.5 speed / 2.0 mass; an apple is fragile and quick). First guesses.
static func _build_types() -> Dictionary:
	var out := CLASSIC.duplicate(true)
	for id in Models.ids("prop"):
		var s := Models.size(id)
		var k := pow(maxf(s.x * s.y * s.z, 0.001), 1.0 / 3.0)
		var d := {"shape": "box", "size": s, "label": Models.label(id), "model": id,
				"hp": int(clampf(20.0 + 100.0 * k, 30.0, 220.0)),
				"speed": snappedf(clampf(8.2 - 3.0 * k, 4.0, 8.0), 0.1),
				"mass": snappedf(clampf(2.3 * k, 0.3, 4.0), 0.1)}
		if Models.entry(id).get("round", false):
			d["round"] = true
		out[id] = d
	return out


# Props sized up or down in Creative (Sara, Nov 25: "only proportionally"): "<type>@<scale>" is the same prop
# scaled evenly, registered as its own type when a map uses it (on every screen, since everyone loads the map),
# so a demon disguised as it looks, collides and moves exactly like the real one. Heavier and tougher when bigger.
const SCALE_MIN := 0.5
const SCALE_MAX := 2.0


static func snap_scale(k: float) -> float:
	return snappedf(clampf(k, SCALE_MIN, SCALE_MAX), 0.1)


static func scaled(type_name: String, k: float) -> String:
	k = snap_scale(k)
	var base := base_type(type_name)
	if is_equal_approx(k, 1.0) or not TYPES.has(base):
		return base
	var key := "%s@%s" % [base, str(k)]
	if not TYPES.has(key):
		var d: Dictionary = TYPES[base].duplicate(true)
		if d.has("size"):
			d["size"] = d["size"] * k
		if d.has("radius"):
			d["radius"] = d["radius"] * k
			d["height"] = d["height"] * k
		d["hp"] = int(clampf(d["hp"] * pow(k, 1.2), 20.0, 400.0))
		d["speed"] = snappedf(clampf(d["speed"] - 1.5 * (k - 1.0), 3.5, 8.5), 0.1)
		d["mass"] = snappedf(clampf(d.get("mass", 1.0) * k * k * k, 0.2, 12.0), 0.1)
		d["base"] = base
		d["scale"] = k
		TYPES[key] = d
	return key


static func base_type(type_name: String) -> String:
	return type_name.get_slice("@", 0)


static func scale_of(type_name: String) -> float:
	return float(TYPES.get(type_name, {}).get("scale", 1.0))


static func scatter_names() -> Array:
	return CLASSIC.keys()


static func category(type_name: String) -> String:
	return Models.category(base_type(type_name)) if TYPES.get(type_name, {}).has("model") else "Classic"


# Max health for a demon in this form ("" = demon form).
static func max_hp(type_name: String) -> int:
	return TYPES[type_name]["hp"] if TYPES.has(type_name) else DEMON_FORM_HP


static func speed(type_name: String) -> float:
	return TYPES[type_name]["speed"] if TYPES.has(type_name) else DEMON_FORM_SPEED


static func type_names() -> Array:
	return TYPES.keys().filter(func(t): return not "@" in t)


static func label(type_name: String) -> String:
	return TYPES[type_name]["label"]


static func height(type_name: String) -> float:
	var d: Dictionary = TYPES[type_name]
	if d["shape"] == "box":
		return d["size"].y
	return d["height"]


static func make_shape(type_name: String) -> Shape3D:
	var d: Dictionary = TYPES[type_name]
	if d["shape"] == "box":
		var box := BoxShape3D.new()
		box.size = d["size"]
		return box
	var cyl := CylinderShape3D.new()
	cyl.radius = d["radius"]
	cyl.height = d["height"]
	return cyl


# A plain coloured material, optionally dressed as a surface (wood, metal...: see surfaces.gd).
static func mat(color: Color, surface := "") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	Surfaces.apply(m, surface)
	return m


static func mass(type_name: String) -> float:
	return TYPES[type_name].get("mass", 1.0) if TYPES.has(type_name) else 1.0


# Half its width across the narrow way (what it tips over on).
static func half_width(type_name: String) -> float:
	var d: Dictionary = TYPES[type_name]
	if d["shape"] == "box":
		return minf(d["size"].x, d["size"].z) / 2.0
	return d["radius"]


static func _add_mesh(root: Node3D, mesh: Mesh, color: Color, pos: Vector3, surface := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color, surface)
	mi.position = pos
	root.add_child(mi)
	return mi


static func _cyl(top_r: float, bottom_r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = h
	return c


# The pickle's shape: u runs 0..1 from end to end (along z), ang around it (0 = to the side, PI/2 = on top).
const PICKLE_LENGTH := 1.45
const PICKLE_RADIUS := 0.2


static func _pickle_center(u: float) -> Vector3:
	var v := u - 0.5
	# A banana curve to one side, and the ends droop a little (floppy).
	return Vector3(0.1 * (1.0 - 4.0 * v * v), PICKLE_RADIUS - 0.05 * 4.0 * v * v + 0.01, v * PICKLE_LENGTH)


static func _pickle_radius(u: float, ang: float) -> float:
	var r := PICKLE_RADIUS * pow(sin(PI * u), 0.42)   # rounded ends, not points
	r *= 1.0 + 0.05 * sin(u * 19.0) + 0.025 * sin(ang * 5.0 + u * 11.0)   # lumpy, like the real thing
	return r


static func _pickle_point(u: float, ang: float, out := 1.0) -> Vector3:
	return _pickle_center(u) + Vector3(cos(ang), sin(ang), 0.0) * _pickle_radius(u, ang) * out


static func _pickle_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 40
	var around := 28
	var dark := Color(0.17, 0.3, 0.07)
	var light := Color(0.36, 0.52, 0.14)
	var grid := []
	for i in rings + 1:
		var u := float(i) / rings
		var row := []
		for j in around + 1:
			var ang := TAU * j / around
			var stripe := pow(0.5 + 0.5 * cos(ang * 9.0), 3.0)            # faint dark stripes down its length
			var c := light.lerp(dark, 0.35 + 0.45 * stripe)
			c = c.lerp(Color(0.5, 0.52, 0.2), 0.35 * pow(absf(u - 0.5) * 2.0, 4.0))   # yellowish ends
			row.append([_pickle_point(u, ang), c])
		grid.append(row)
	for i in rings:
		for j in around:
			var q := [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
			for k in [0, 2, 1, 0, 3, 2]:
				st.set_color(q[k][1])
				st.add_vertex(q[k][0])
	st.generate_normals()
	return st.commit()


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func make_visual(type_name: String) -> Node3D:
	if "@" in type_name:
		var v := make_visual(base_type(type_name))
		v.scale = Vector3.ONE * scale_of(type_name)
		return v
	if TYPES.get(type_name, {}).has("model"):
		return Models.instance(TYPES[type_name]["model"])
	var root := Node3D.new()
	match type_name:
		"barrel":
			_add_mesh(root, _cyl(0.42, 0.42, 1.0), Color(0.55, 0.33, 0.15), Vector3(0, 0.5, 0), "wood")
			_add_mesh(root, _cyl(0.45, 0.45, 0.07), Color(0.25, 0.25, 0.28), Vector3(0, 0.22, 0), "metal")
			_add_mesh(root, _cyl(0.45, 0.45, 0.07), Color(0.25, 0.25, 0.28), Vector3(0, 0.78, 0), "metal")
		"crate":
			_add_mesh(root, _box(Vector3(0.9, 0.9, 0.9)), Color(0.78, 0.6, 0.35), Vector3(0, 0.45, 0), "wood")
			_add_mesh(root, _box(Vector3(0.94, 0.12, 0.94)), Color(0.5, 0.35, 0.18), Vector3(0, 0.45, 0), "wood")
		"lamp":
			_add_mesh(root, _cyl(0.25, 0.25, 0.08), Color(0.2, 0.2, 0.22), Vector3(0, 0.04, 0), "metal")
			_add_mesh(root, _cyl(0.05, 0.05, 1.45), Color(0.2, 0.2, 0.22), Vector3(0, 0.75, 0), "metal")
			var shade := _add_mesh(root, _cyl(0.15, 0.32, 0.35), Color(1.0, 0.9, 0.6), Vector3(0, 1.55, 0), "cloth")
			var glow: StandardMaterial3D = shade.material_override
			glow.emission_enabled = true
			glow.emission = Color(1.0, 0.85, 0.5)
			glow.emission_energy_multiplier = 0.6
		"pumpkin":
			ClassicLook.pumpkin(root)   # (Sara, Nov 25: "very basic"; classic_look.gd)
		"pot":
			_add_mesh(root, _cyl(0.35, 0.28, 0.6), Color(0.3, 0.3, 0.33), Vector3(0, 0.3, 0), "metal")
		"bench":
			_add_mesh(root, _box(Vector3(1.6, 0.1, 0.5)), Color(0.5, 0.32, 0.18), Vector3(0, 0.45, 0), "wood")
			_add_mesh(root, _box(Vector3(0.1, 0.4, 0.45)), Color(0.4, 0.25, 0.14), Vector3(-0.7, 0.2, 0), "wood")
			_add_mesh(root, _box(Vector3(0.1, 0.4, 0.45)), Color(0.4, 0.25, 0.14), Vector3(0.7, 0.2, 0), "wood")
		"books":
			_add_mesh(root, _box(Vector3(0.45, 0.12, 0.3)), Color(0.6, 0.15, 0.15), Vector3(0, 0.06, 0), "leather")
			_add_mesh(root, _box(Vector3(0.4, 0.11, 0.28)), Color(0.15, 0.3, 0.6), Vector3(0.02, 0.175, 0), "leather")
			_add_mesh(root, _box(Vector3(0.42, 0.1, 0.29)), Color(0.2, 0.5, 0.25), Vector3(-0.01, 0.28, 0), "leather")
		"hay":
			ClassicLook.hay(root)
		"apple":
			var a := SphereMesh.new()
			a.radius = 0.13
			a.height = 0.24
			_add_mesh(root, a, Color(0.8, 0.08, 0.1), Vector3(0, 0.12, 0), "glossy")
			_add_mesh(root, _cyl(0.008, 0.012, 0.06), Color(0.35, 0.22, 0.1), Vector3(0, 0.26, 0))
			var leaf := _add_mesh(root, _box(Vector3(0.07, 0.01, 0.035)), Color(0.25, 0.6, 0.2), Vector3(0.035, 0.265, 0))
			leaf.rotation.z = 0.4
		"pickle":
			# A big, floppy pickle lying on its side (Ted, Nov 18: the old one was three capsules and looked like
			# something else entirely): one smooth body with rounded ends, a gentle banana curve, slightly lumpy,
			# faint darker stripes down its length, and little warts all over.
			var body := _add_mesh(root, _pickle_mesh(), Color(1, 1, 1), Vector3.ZERO, "glossy")
			(body.material_override as StandardMaterial3D).vertex_color_use_as_albedo = true
			var rng := RandomNumberGenerator.new()
			rng.seed = 7   # the same warts on every screen
			for i in 22:
				var u := rng.randf_range(0.12, 0.88)
				var ang := rng.randf_range(-0.2, PI + 0.2)   # the top and sides (nobody sees its belly)
				var wart := SphereMesh.new()
				wart.radius = rng.randf_range(0.022, 0.038)
				wart.height = wart.radius * 1.6
				var at := _pickle_point(u, ang, 0.98)
				_add_mesh(root, wart, Color(0.26, 0.42, 0.1), at, "plant")
	return root
