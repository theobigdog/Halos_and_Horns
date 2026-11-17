# Every prop a demon can possess: how it looks and how it collides.
# Visuals are built with their bottom sitting at y = 0 (the floor).
# Placeholder shapes for now; real models can replace make_visual() later.
extends RefCounted

const Surfaces = preload("res://scripts/surfaces.gd")

# shape: "box" uses size, "cylinder" uses radius + height (collision only)
# hp / speed: a demon disguised as this prop. Small = fragile but quick,
# big = tanky but slow. First guesses, to be tuned in playtests.
# mass: how hard it is to shove (knock.gd). round: it rolls instead of tipping.
# lying: already on its side, so it only slides.
const TYPES := {
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


# Max health for a demon in this form ("" = demon form).
static func max_hp(type_name: String) -> int:
	return TYPES[type_name]["hp"] if TYPES.has(type_name) else DEMON_FORM_HP


static func speed(type_name: String) -> float:
	return TYPES[type_name]["speed"] if TYPES.has(type_name) else DEMON_FORM_SPEED


static func type_names() -> Array:
	return TYPES.keys()


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


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func make_visual(type_name: String) -> Node3D:
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
			var s := SphereMesh.new()
			s.radius = 0.4
			s.height = 0.62
			_add_mesh(root, s, Color(0.95, 0.5, 0.1), Vector3(0, 0.31, 0), "plant")
			_add_mesh(root, _cyl(0.04, 0.05, 0.12), Color(0.3, 0.5, 0.15), Vector3(0, 0.66, 0), "plant")
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
			_add_mesh(root, _box(Vector3(1.2, 0.8, 0.8)), Color(0.9, 0.8, 0.35), Vector3(0, 0.4, 0), "hay")
		"apple":
			var a := SphereMesh.new()
			a.radius = 0.13
			a.height = 0.24
			_add_mesh(root, a, Color(0.8, 0.08, 0.1), Vector3(0, 0.12, 0), "glossy")
			_add_mesh(root, _cyl(0.008, 0.012, 0.06), Color(0.35, 0.22, 0.1), Vector3(0, 0.26, 0))
			var leaf := _add_mesh(root, _box(Vector3(0.07, 0.01, 0.035)), Color(0.25, 0.6, 0.2), Vector3(0.035, 0.265, 0))
			leaf.rotation.z = 0.4
		"pickle":
			# A big, floppy pickle lying on its side: three segments that sag in the
			# middle, with a few warty bumps.
			var green := Color(0.35, 0.5, 0.15)
			for i in 3:
				var seg := CapsuleMesh.new()
				seg.radius = 0.2
				seg.height = 0.75
				var mi := _add_mesh(root, seg, green, Vector3(0, 0.2 - (0.05 if i == 1 else 0.0), (i - 1) * 0.42), "glossy")
				mi.rotation.x = PI / 2 + (i - 1) * 0.18
			for b in [Vector3(0.17, 0.3, -0.3), Vector3(-0.16, 0.28, 0.1), Vector3(0.12, 0.33, 0.45), Vector3(-0.1, 0.34, -0.55)]:
				var bump := SphereMesh.new()
				bump.radius = 0.045
				bump.height = 0.09
				_add_mesh(root, bump, Color(0.45, 0.6, 0.2), b, "plant")
	return root
