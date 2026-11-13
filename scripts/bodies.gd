# Placeholder character bodies, shared by your own player and everyone else's.
# Angels: white with a golden halo. Demons: small red gremlins with horns.
# Built with their feet at y = 0. Real models replace these later.
extends RefCounted

const PropLib = preload("res://scripts/prop_library.gd")

const BODY_HEIGHT := 1.7       # angel height
const BODY_RADIUS := 0.35
const DEMON_SCALE := 0.6       # demons are 60% of angel size


static func scale_for(role: String) -> float:
	return 1.0 if role == "angel" else DEMON_SCALE


static func height_for(role: String) -> float:
	return BODY_HEIGHT * scale_for(role)


static func make_shape(role: String) -> CapsuleShape3D:
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS * scale_for(role)
	capsule.height = BODY_HEIGHT * scale_for(role)
	return capsule


static func make(role: String) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = BODY_RADIUS
	capsule.height = BODY_HEIGHT
	body.mesh = capsule
	body.position.y = BODY_HEIGHT / 2.0
	root.add_child(body)
	if role == "angel":
		body.material_override = PropLib.mat(Color(0.95, 0.95, 1.0))
		var halo := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.18
		torus.outer_radius = 0.25
		halo.mesh = torus
		var gold := PropLib.mat(Color(1.0, 0.85, 0.3))
		gold.emission_enabled = true
		gold.emission = Color(1.0, 0.85, 0.3)
		halo.material_override = gold
		halo.position.y = 1.95
		root.add_child(halo)
	else:
		body.material_override = PropLib.mat(Color(0.75, 0.12, 0.12))
		for side in [-1.0, 1.0]:
			var horn := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.08
			cone.height = 0.3
			horn.mesh = cone
			horn.material_override = PropLib.mat(Color(0.15, 0.1, 0.1))
			horn.position = Vector3(0.17 * side, 1.75, 0.0)
			horn.rotation.z = -0.35 * side
			root.add_child(horn)
			var eye := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.06
			sphere.height = 0.12
			eye.mesh = sphere
			var yellow := PropLib.mat(Color(1.0, 0.9, 0.1))
			yellow.emission_enabled = true
			yellow.emission = Color(1.0, 0.9, 0.1)
			eye.material_override = yellow
			eye.position = Vector3(0.12 * side, 1.45, -0.31)   # -Z is forward
			root.add_child(eye)
		root.scale = Vector3.ONE * DEMON_SCALE
	return root
