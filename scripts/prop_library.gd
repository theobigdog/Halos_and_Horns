# Every prop a demon can possess: how it looks and how it collides.
# Visuals are built with their bottom sitting at y = 0 (the floor).
# Placeholder shapes for now; real models can replace make_visual() later.
extends RefCounted

# shape: "box" uses size, "cylinder" uses radius + height (collision only)
const TYPES := {
	"barrel": {"shape": "cylinder", "radius": 0.45, "height": 1.0, "label": "Barrel"},
	"crate": {"shape": "box", "size": Vector3(0.9, 0.9, 0.9), "label": "Crate"},
	"lamp": {"shape": "cylinder", "radius": 0.3, "height": 1.75, "label": "Lamp"},
	"pumpkin": {"shape": "cylinder", "radius": 0.4, "height": 0.66, "label": "Pumpkin"},
	"pot": {"shape": "cylinder", "radius": 0.35, "height": 0.6, "label": "Pot"},
	"bench": {"shape": "box", "size": Vector3(1.6, 0.5, 0.5), "label": "Bench"},
	"books": {"shape": "box", "size": Vector3(0.45, 0.35, 0.3), "label": "Stack of books"},
	"hay": {"shape": "box", "size": Vector3(1.2, 0.8, 0.8), "label": "Hay bale"},
}


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


static func mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


static func _add_mesh(root: Node3D, mesh: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color)
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
			_add_mesh(root, _cyl(0.42, 0.42, 1.0), Color(0.55, 0.33, 0.15), Vector3(0, 0.5, 0))
			_add_mesh(root, _cyl(0.45, 0.45, 0.07), Color(0.25, 0.25, 0.28), Vector3(0, 0.22, 0))
			_add_mesh(root, _cyl(0.45, 0.45, 0.07), Color(0.25, 0.25, 0.28), Vector3(0, 0.78, 0))
		"crate":
			_add_mesh(root, _box(Vector3(0.9, 0.9, 0.9)), Color(0.78, 0.6, 0.35), Vector3(0, 0.45, 0))
			_add_mesh(root, _box(Vector3(0.94, 0.12, 0.94)), Color(0.5, 0.35, 0.18), Vector3(0, 0.45, 0))
		"lamp":
			_add_mesh(root, _cyl(0.25, 0.25, 0.08), Color(0.2, 0.2, 0.22), Vector3(0, 0.04, 0))
			_add_mesh(root, _cyl(0.05, 0.05, 1.45), Color(0.2, 0.2, 0.22), Vector3(0, 0.75, 0))
			var shade := _add_mesh(root, _cyl(0.15, 0.32, 0.35), Color(1.0, 0.9, 0.6), Vector3(0, 1.55, 0))
			var glow: StandardMaterial3D = shade.material_override
			glow.emission_enabled = true
			glow.emission = Color(1.0, 0.85, 0.5)
			glow.emission_energy_multiplier = 0.6
		"pumpkin":
			var s := SphereMesh.new()
			s.radius = 0.4
			s.height = 0.62
			_add_mesh(root, s, Color(0.95, 0.5, 0.1), Vector3(0, 0.31, 0))
			_add_mesh(root, _cyl(0.04, 0.05, 0.12), Color(0.3, 0.5, 0.15), Vector3(0, 0.66, 0))
		"pot":
			_add_mesh(root, _cyl(0.35, 0.28, 0.6), Color(0.3, 0.3, 0.33), Vector3(0, 0.3, 0))
		"bench":
			_add_mesh(root, _box(Vector3(1.6, 0.1, 0.5)), Color(0.5, 0.32, 0.18), Vector3(0, 0.45, 0))
			_add_mesh(root, _box(Vector3(0.1, 0.4, 0.45)), Color(0.4, 0.25, 0.14), Vector3(-0.7, 0.2, 0))
			_add_mesh(root, _box(Vector3(0.1, 0.4, 0.45)), Color(0.4, 0.25, 0.14), Vector3(0.7, 0.2, 0))
		"books":
			_add_mesh(root, _box(Vector3(0.45, 0.12, 0.3)), Color(0.6, 0.15, 0.15), Vector3(0, 0.06, 0))
			_add_mesh(root, _box(Vector3(0.4, 0.11, 0.28)), Color(0.15, 0.3, 0.6), Vector3(0.02, 0.175, 0))
			_add_mesh(root, _box(Vector3(0.42, 0.1, 0.29)), Color(0.2, 0.5, 0.25), Vector3(-0.01, 0.28, 0))
		"hay":
			_add_mesh(root, _box(Vector3(1.2, 0.8, 0.8)), Color(0.9, 0.8, 0.35), Vector3(0, 0.4, 0))
	return root
