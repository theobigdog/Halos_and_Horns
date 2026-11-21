extends RefCounted
# Barbarian details: a heavenly warrior of the sky clans. Gold arm rings with glowing runes, a bead-and-
# feather necklace, white fur on the shoulders, a gold sun buckle, a sky-blue sash with feather charms,
# gold-banded boots. (Demons get the same shapes in rusted iron, bone and embers.)
# Coordinates are KayKit model units in the bone's space; the character faces +Z, +X is its left.


# ---------------- shared bits ----------------

static func _pal(role: String) -> Dictionary:
	if role == "demon":
		return {"gold": Color(0.42, 0.3, 0.24), "fur": Color(0.78, 0.74, 0.64), "cloth": Color(0.35, 0.08, 0.06),
			"feather": Color(0.16, 0.14, 0.14), "rune": Color(1.0, 0.38, 0.08), "bead": Color(0.85, 0.8, 0.68)}
	return {"gold": Color(1.0, 0.8, 0.32), "fur": Color(0.97, 0.96, 0.92), "cloth": Color(0.5, 0.76, 0.98),
		"feather": Color(1.0, 1.0, 0.98), "rune": Color(0.55, 0.9, 1.0), "bead": Color(0.45, 0.72, 1.0)}


static func _metal(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.75
	m.roughness = 0.32
	return m


static func _matte(c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


# A softly pulsing glow (shader TIME, no scripts).
static func _rune(c: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
uniform vec4 col : source_color = vec4(0.55, 0.9, 1.0, 1.0);
void fragment() {
	ALBEDO = col.rgb;
	EMISSION = col.rgb * (1.8 + 0.7 * sin(TIME * 2.2));
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("col", c)
	return m


static func _put(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	var r := rot_deg * (PI / 180.0)
	mi.transform = Transform3D(Basis.from_euler(r).scaled(scl), pos)
	parent.add_child(mi)
	return mi


static func _bone(sk: Skeleton3D, bone: String) -> BoneAttachment3D:
	var a := BoneAttachment3D.new()
	a.bone_name = bone
	a.name = "BarbDetail_" + bone
	sk.add_child(a)
	return a


static func _torus(inner: float, outer: float, sides := 8, rings := 16) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.ring_segments = sides
	t.rings = rings
	return t


static func _sphere(r: float, segs := 8) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = maxi(4, segs / 2)
	return s


static func _cyl(top: float, bottom: float, h: float, segs := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


# A chunky feather: a flattened leaf with a gold quill cap. Its tip points along +Y of `holder`.
static func _feather(parent: Node3D, pos: Vector3, rot_deg: Vector3, size: float, leaf: Mesh, cap: Mesh,
		fmat: Material, gmat: Material) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation = rot_deg * (PI / 180.0)
	parent.add_child(holder)
	_put(holder, leaf, fmat, Vector3(0, size * 0.5, 0), Vector3.ZERO, Vector3(size * 0.38, size, size * 0.14))
	_put(holder, cap, gmat, Vector3(0, -size * 0.02, 0), Vector3.ZERO, Vector3.ONE * size)


# A gold sun disc facing +Z of `parent` at `pos`: disc, rays, glowing core.
static func _sun(parent: Node3D, pos: Vector3, r: float, rays: int, gmat: Material, rmat: Material) -> void:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	_put(n, _cyl(r, r, r * 0.35, 12), gmat, Vector3.ZERO, Vector3(90, 0, 0))
	var ray := _cyl(0.0, r * 0.32, r * 0.6, 4)
	for i in rays:
		var a := TAU * i / rays
		var d := Vector3(cos(a), sin(a), 0)
		_put(n, ray, gmat, d * r * 1.18, Vector3(0, 0, rad_to_deg(a) - 90.0))
	_put(n, _sphere(r * 0.55, 10), rmat, Vector3(0, 0, r * 0.12), Vector3.ZERO, Vector3(1, 1, 0.55))


# ---------------- head ----------------

static func head(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var p := _pal(role)
	var gold := _metal(p["gold"])
	var rune := _rune(p["rune"])
	var fmat := _matte(p["feather"], 0.9)
	var bead := _matte(p["bead"], 0.4)
	var leaf := _sphere(0.5, 8)
	var cap := _cyl(0.05, 0.07, 0.12, 6)

	# Beard beads: two gold rings with a sky bead each, low on the beard
	var ring := _cyl(0.06, 0.06, 0.08, 8)
	var bb := _sphere(0.05, 8)
	for sx in [-1.0, 1.0]:
		_put(att, ring, gold, Vector3(0.15 * sx, -0.1, 0.43), Vector3(15, 0, 0))
		_put(att, bb, bead, Vector3(0.15 * sx, -0.17, 0.44))

	# Gold ear hoops
	var hoop := _torus(0.035, 0.06, 6, 10)
	for sx in [-1.0, 1.0]:
		_put(att, hoop, gold, Vector3(0.56 * sx, 0.2, 0.08), Vector3(0, 0, 90))

	if bare:
		# A gold circlet around the bald head with a sun gem and little feather wings at the temples
		var band := Node3D.new()
		band.position = Vector3(0, 0.72, 0.03)
		band.rotation = Vector3(deg_to_rad(-6), 0, 0)
		att.add_child(band)
		_put(band, _torus(0.49, 0.55, 6, 20), gold, Vector3.ZERO, Vector3.ZERO, Vector3(0.96, 1.0, 0.93))
		_sun(band, Vector3(0, 0.02, 0.5), 0.07, 8, gold, rune)
		for sx in [-1.0, 1.0]:
			_feather(band, Vector3(0.48 * sx, 0.04, 0.12), Vector3(-20, 0, -35 * sx), 0.26, leaf, cap, fmat, gold)
			_feather(band, Vector3(0.48 * sx, 0.0, 0.02), Vector3(-30, 0, -60 * sx), 0.2, leaf, cap, fmat, gold)
	else:
		# On the bear hood: a sun medallion on the brow, gold ear cuffs, a feather tucked by the ear
		_sun(att, Vector3(0, 0.98, 0.5), 0.08, 8, gold, rune)
		# a gold ring pierced through the bear's right ear (goofy)
		_put(att, _torus(0.06, 0.095, 6, 12), gold, Vector3(-0.5, 0.93, 0.1), Vector3(0, 90, -40))
		_put(att, _sphere(0.035, 6), rune, Vector3(-0.53, 0.86, 0.1))
		# two feathers tucked into the hood's left side
		var tuck := Node3D.new()
		tuck.position = Vector3(0.6, 0.66, -0.06)
		att.add_child(tuck)
		_put(tuck, _sphere(0.055, 8), gold, Vector3.ZERO, Vector3.ZERO, Vector3(0.6, 1.0, 1.0))
		_put(tuck, _sphere(0.03, 6), rune, Vector3(0.03, 0, 0))
		_feather(tuck, Vector3(0.02, 0.02, -0.04), Vector3(-35, 0, -20), 0.42, leaf, cap, fmat, gold)
		_feather(tuck, Vector3(0.03, 0.0, 0.0), Vector3(-15, 0, -45), 0.36, leaf, cap, fmat, gold)
		_feather(tuck, Vector3(0.03, -0.02, 0.03), Vector3(5, 0, -70), 0.28, leaf, cap, fmat, gold)


# ---------------- upper ----------------

static func upper(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var p := _pal(role)
	var gold := _metal(p["gold"])
	var rune := _rune(p["rune"])
	var fur := _matte(p["fur"], 1.0)
	var fmat := _matte(p["feather"], 0.9)
	var bead := _matte(p["bead"], 0.4)
	var leaf := _sphere(0.5, 8)
	var cap := _cyl(0.05, 0.07, 0.12, 6)

	# Necklace: a U of beads under the beard, a sun pendant and two feathers
	var neck := Node3D.new()
	neck.name = "Necklace"
	att.add_child(neck)
	var gb := _sphere(0.035, 8)
	var bl := _sphere(0.04, 8)
	var n := 9
	for i in n:
		var t := float(i) / (n - 1) * 2.0 - 1.0
		var x := t * 0.24
		var y := 0.2 - 0.13 * (1.0 - t * t)
		var z := 0.32 - 0.06 * t * t
		_put(neck, bl if i % 2 == 0 else gb, bead if i % 2 == 0 else gold, Vector3(x, y, z))
	_sun(neck, Vector3(0, 0.03, 0.34), 0.065, 8, gold, rune)
	for sx in [-1.0, 1.0]:
		_feather(neck, Vector3(0.1 * sx, 0.08, 0.33), Vector3(0, 0, 180 + 18 * sx), 0.17, leaf, cap, fmat, gold)

	# Big gold sun buckle over the belt
	_sun(att, Vector3(0, -0.42, 0.37), 0.1, 10, gold, rune)

	# Horn-shaped gold clasp on the chest strap (two curled little horns around a gem)
	var clasp := Node3D.new()
	clasp.position = Vector3(0.2, 0.08, 0.33)
	clasp.rotation = Vector3(deg_to_rad(-8), deg_to_rad(20), deg_to_rad(35))
	att.add_child(clasp)
	_put(clasp, _cyl(0.05, 0.05, 0.04, 8), gold, Vector3.ZERO, Vector3(90, 0, 0))
	_put(clasp, _sphere(0.032, 8), rune, Vector3(0, 0, 0.025))
	var horn := _cyl(0.0, 0.028, 0.1, 6)
	for sx in [-1.0, 1.0]:
		_put(clasp, horn, gold, Vector3(0.06 * sx, 0.03, 0), Vector3(0, 0, -50 * sx))

	# Arms: white fur on the shoulder, gold arm ring with runes, gold wrist band
	var furball := _sphere(0.1, 8)
	var arm_ring := _torus(0.12, 0.175, 6, 16)
	var wrist_ring := _torus(0.13, 0.185, 6, 16)
	var stud := _sphere(0.03, 6)
	for side in ["l", "r"]:
		var ua := _bone(sk, "upperarm." + side)
		# fur: a fluffy ring of puffs on the shoulder top (local +Z is up in the arm's rest pose)
		for i in 5:
			var a := deg_to_rad(-80.0 + i * 40.0)
			_put(ua, furball, fur, Vector3(sin(a) * 0.12, 0.04 + 0.02 * (i % 2), cos(a) * 0.13 + 0.02),
				Vector3.ZERO, Vector3(1.1, 0.8, 1.0))
		_put(ua, arm_ring, gold, Vector3(0, 0.15, 0))
		for i in 4:
			var a := TAU * i / 4.0 + PI / 4.0
			_put(ua, stud, rune, Vector3(cos(a) * 0.17, 0.15, sin(a) * 0.17))
		var la := _bone(sk, "lowerarm." + side)
		_put(la, wrist_ring, gold, Vector3(0, 0.21, 0))
		_put(la, stud, rune, Vector3(0, 0.21, 0.18))
		_put(la, stud, rune, Vector3(0, 0.21, -0.18))


# ---------------- lower ----------------

static func lower(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var p := _pal(role)
	var gold := _metal(p["gold"])
	var rune := _rune(p["rune"])
	var cloth := _matte(p["cloth"], 0.8)
	var fmat := _matte(p["feather"], 0.9)
	var leaf := _sphere(0.5, 8)
	var cap := _cyl(0.05, 0.07, 0.12, 6)

	# Sky-blue sash knotted on the left hip, two tails with feather charms
	var sash := Node3D.new()
	sash.name = "Sash"
	sash.position = Vector3(0.33, 0.08, 0.1)
	sash.rotation = Vector3(0, deg_to_rad(70), deg_to_rad(6))
	att.add_child(sash)
	_put(sash, _sphere(0.07, 8), cloth, Vector3.ZERO, Vector3.ZERO, Vector3(1.2, 1.0, 0.8))
	var tail := BoxMesh.new()
	tail.size = Vector3(0.12, 0.3, 0.035)
	_put(sash, tail, cloth, Vector3(-0.03, -0.16, 0.02), Vector3(0, 0, -8))
	_put(sash, tail, cloth, Vector3(0.06, -0.14, 0.0), Vector3(0, 0, 14), Vector3(1, 0.85, 1))
	_put(sash, _sphere(0.025, 6), gold, Vector3(-0.06, -0.31, 0.03))
	_put(sash, _sphere(0.025, 6), gold, Vector3(0.1, -0.27, 0.01))
	_feather(sash, Vector3(-0.06, -0.32, 0.03), Vector3(0, 0, 180), 0.13, leaf, cap, fmat, gold)
	_feather(sash, Vector3(0.1, -0.28, 0.01), Vector3(0, 0, 190), 0.11, leaf, cap, fmat, gold)

	# Boots: gold band at the top with a glowing stud, a gold knee disc, a gold toe cap
	var band := _torus(0.1, 0.15, 6, 16)
	var stud := _sphere(0.03, 6)
	var knee := _cyl(0.06, 0.06, 0.03, 8)
	var toecap := _sphere(0.06, 8)
	for side in ["l", "r"]:
		var ll := _bone(sk, "lowerleg." + side)
		# (local +Y runs down the leg; local -Z is the front)
		_put(ll, band, gold, Vector3(0, 0.11, 0))
		_put(ll, stud, rune, Vector3(0, 0.11, -0.155))
		_put(ll, knee, gold, Vector3(0, -0.02, -0.13), Vector3(90, 0, 0))
		_put(ll, stud, rune, Vector3(0, -0.02, -0.15))
		var toes := _bone(sk, "toes." + side)
		# (toes: local +Y forward, +Z up)
		_put(toes, toecap, gold, Vector3(0, 0.08, 0.07), Vector3.ZERO, Vector3(1.0, 0.6, 0.5))
