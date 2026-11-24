# Scenery past the map's walls (Ted's wife's notes, Nov 21): a map setting, "backdrop":
#   none, hills (rolling green hills and trees), ocean (the map's an island in a sea), mountains (a ring
#   of snow-capped peaks) or city (a skyline, with roads leading off toward it).
# All of it is just to look at: no collision (nobody can get past the walls), cheap low-poly shapes
# that the distance fog softens. Laid out from the map's name, so every screen sees the same.
extends RefCounted

const KINDS := ["none", "hills", "ocean", "mountains", "city"]
const NAMES := ["None", "Rolling hills", "Ocean", "Mountains", "City skyline"]

const SEA_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 deep = vec3(0.05, 0.22, 0.35);
uniform vec3 shallow = vec3(0.15, 0.5, 0.55);
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wp.x * 0.15 + TIME * 0.8) * 0.12 + sin(wp.z * 0.21 + TIME * 0.6) * 0.1;
}
void fragment() {
	float shore = clamp(1.0 - (length(wp.xz) - SHORE) / 30.0, 0.0, 1.0);
	float glint = pow(max(sin(wp.x * 1.3 + TIME * 1.5) * sin(wp.z * 1.1 - TIME * 1.2), 0.0), 8.0);
	ALBEDO = mix(deep, shallow, shore) + glint * 0.15;
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
	METALLIC = 0.1;
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


static func _around(half: float, rng: RandomNumberGenerator, near: float, far: float) -> Vector3:
	var a := rng.randf_range(0.0, TAU)
	var d := half + rng.randf_range(near, far)
	return Vector3(cos(a) * d, 0.0, sin(a) * d)


static func _hills(n: Node3D, half: float, rng: RandomNumberGenerator) -> void:
	var grass := [_mat(Color(0.36, 0.55, 0.28)), _mat(Color(0.42, 0.6, 0.3)), _mat(Color(0.3, 0.48, 0.25))]
	# a flat green apron past the walls, then hills
	var apron := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(half * 2.0 + 500.0, half * 2.0 + 500.0)
	apron.mesh = pm
	apron.material_override = grass[0]
	apron.position.y = -0.05
	n.add_child(apron)
	var hill := SphereMesh.new()
	hill.radial_segments = 16
	hill.rings = 8
	for i in 40:
		var mi := MeshInstance3D.new()
		mi.mesh = hill
		mi.material_override = grass[i % 3]
		var at := _around(half, rng, 30.0, 110.0)
		var r := rng.randf_range(18.0, 45.0)
		mi.position = at + Vector3(0, -r * 0.25, 0)
		mi.scale = Vector3(r, r * rng.randf_range(0.45, 0.75), r)
		n.add_child(mi)
	_trees(n, half, rng, 160, 8.0, 120.0)


static func _trees(n: Node3D, half: float, rng: RandomNumberGenerator, count: int, near: float, far: float) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.6
	cone.height = 4.5
	cone.radial_segments = 7
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cone
	mm.instance_count = count
	for i in count:
		var at := _around(half, rng, near, far)
		var s := rng.randf_range(0.7, 1.6)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), at + Vector3(0, 2.0 * s, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat(Color(0.16, 0.36, 0.2))
	n.add_child(mmi)


static func _ocean(n: Node3D, half: float, rng: RandomNumberGenerator) -> void:
	# a sandy beach round the edge, then the sea out to the horizon, and a few islands
	var sand := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = half * 1.45 + 6.0
	sm.bottom_radius = half * 1.45 + 12.0
	sm.height = 1.0
	sm.radial_segments = 48
	sand.mesh = sm
	sand.material_override = _mat(Color(0.86, 0.78, 0.58))
	sand.position.y = -0.55
	n.add_child(sand)
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	pm.subdivide_width = 60
	pm.subdivide_depth = 60
	sea.mesh = pm
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SEA_SHADER.replace("SHORE", "%.1f" % (half * 1.45 + 10.0))
	m.shader = sh
	sea.material_override = m
	sea.position.y = -0.4
	n.add_child(sea)
	var isle := SphereMesh.new()
	isle.radial_segments = 14
	isle.rings = 7
	for i in 7:
		var mi := MeshInstance3D.new()
		mi.mesh = isle
		mi.material_override = _mat(Color(0.35, 0.52, 0.3))
		var at := _around(half, rng, 120.0, 260.0)
		var r := rng.randf_range(10.0, 30.0)
		mi.position = at + Vector3(0, -r * 0.6, 0)
		mi.scale = Vector3(r, r * 0.6, r)
		n.add_child(mi)


static func _mountains(n: Node3D, half: float, rng: RandomNumberGenerator) -> void:
	var rock := [_mat(Color(0.42, 0.4, 0.44)), _mat(Color(0.5, 0.45, 0.42)), _mat(Color(0.36, 0.36, 0.4))]
	var snow := _mat(Color(0.95, 0.96, 1.0), 0.7)
	var apron := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(half * 2.0 + 600.0, half * 2.0 + 600.0)
	apron.mesh = pm
	apron.material_override = _mat(Color(0.38, 0.48, 0.3))
	apron.position.y = -0.05
	n.add_child(apron)
	for i in 34:
		var h := rng.randf_range(60.0, 150.0)
		var r := h * rng.randf_range(0.55, 0.85)
		var at := _around(half, rng, 150.0 + r * 0.5, 300.0)
		var peak := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = r
		cm.height = h
		cm.radial_segments = rng.randi_range(5, 8)
		peak.mesh = cm
		peak.material_override = rock[i % 3]
		peak.position = at + Vector3(0, h / 2.0 - 2.0, 0)
		peak.rotation.y = rng.randf_range(0.0, TAU)
		n.add_child(peak)
		var cap := MeshInstance3D.new()
		var capm := CylinderMesh.new()
		capm.top_radius = 0.0
		capm.bottom_radius = r * 0.3
		capm.height = h * 0.3
		capm.radial_segments = cm.radial_segments
		cap.mesh = capm
		cap.material_override = snow
		cap.position = at + Vector3(0, h - 2.0 - h * 0.15 + 0.3, 0)
		cap.rotation.y = peak.rotation.y
		n.add_child(cap)
	_trees(n, half, rng, 120, 8.0, 80.0)


static func _city(n: Node3D, half: float, rng: RandomNumberGenerator) -> void:
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(half * 2.0 + 600.0, half * 2.0 + 600.0)
	ground.mesh = pm
	ground.material_override = _mat(Color(0.4, 0.5, 0.33))
	ground.position.y = -0.05
	n.add_child(ground)
	# roads leading off from each side of the map toward the city
	var asphalt := _mat(Color(0.2, 0.2, 0.22), 0.8)
	var paint := _mat(Color(0.95, 0.85, 0.3), 0.6)
	for k in 4:
		var dir := Vector3(cos(k * PI / 2.0), 0, sin(k * PI / 2.0))
		var road := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(7.0, 0.05, 200.0)
		road.mesh = rb
		road.material_override = asphalt
		road.position = dir * (half + 101.0)
		road.rotation.y = atan2(dir.x, dir.z)
		n.add_child(road)
		var dashes := MultiMesh.new()
		dashes.transform_format = MultiMesh.TRANSFORM_3D
		var dm := BoxMesh.new()
		dm.size = Vector3(0.25, 0.06, 2.0)
		dashes.mesh = dm
		dashes.instance_count = 50
		for i in 50:
			dashes.set_instance_transform(i, Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), dir * (half + 3.0 + i * 4.0) + Vector3(0, 0.02, 0)))
		var dmi := MultiMeshInstance3D.new()
		dmi.multimesh = dashes
		dmi.material_override = paint
		n.add_child(dmi)
	# the skyline: tall blocks in a band, with lit windows (brighter at night through the fog)
	var shades := [Color(0.55, 0.58, 0.65), Color(0.45, 0.48, 0.55), Color(0.62, 0.6, 0.58), Color(0.38, 0.4, 0.48)]
	var bm := BoxMesh.new()
	for i in 90:
		var at := _around(half, rng, 120.0, 210.0)
		# leave the roads clear
		var ang := fposmod(atan2(at.z, at.x), PI / 2.0)
		if ang < 0.06 or ang > PI / 2.0 - 0.06:
			continue
		var w := rng.randf_range(8.0, 18.0)
		var h := rng.randf_range(20.0, 85.0)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		var m := _mat(shades[i % shades.size()], 0.6)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.85, 0.5)
		m.emission_energy_multiplier = 0.08
		mi.material_override = m
		mi.position = at + Vector3(0, h / 2.0, 0)
		mi.scale = Vector3(w, h, w * rng.randf_range(0.7, 1.3))
		mi.rotation.y = atan2(at.x, at.z)
		n.add_child(mi)
