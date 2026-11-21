extends RefCounted
# Skeleton Warrior details: a goofy hell-knight. Ember-cracked helmet, charred spiked pauldrons,
# a chain across the chest, a grinning skull belt buckle, rusty spiked knee guards.
# (KayKit model space: front +Z, up +Y, the character's left +X.)

const EMBER_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec4 col : source_color = vec4(1.0, 0.38, 0.06, 1.0);
uniform float speed = 2.2;
uniform float phase = 0.0;
void fragment() {
	float p = 0.75 + 0.25 * sin(TIME * speed + phase + VERTEX.y * 6.0);
	ALBEDO = col.rgb * (1.0 + 0.8 * p);
}
"""


static func _ember(phase := 0.0) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = EMBER_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("phase", phase)
	return m


static func _mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _iron() -> StandardMaterial3D:
	return _mat(Color(0.5, 0.5, 0.54), 0.5, 0.4)


static func _dark_iron() -> StandardMaterial3D:
	return _mat(Color(0.2, 0.19, 0.2), 0.55, 0.5)


static func _rust() -> StandardMaterial3D:
	return _mat(Color(0.47, 0.24, 0.13), 0.9, 0.2)


static func _char() -> StandardMaterial3D:
	return _mat(Color(0.2, 0.15, 0.14), 0.8, 0.2)


static func _bone() -> StandardMaterial3D:
	return _mat(Color(0.9, 0.85, 0.72), 0.7)


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


static func _cone(r: float, h: float, segs := 6) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func _ball(r: float, h := -1.0, segs := 8, rings := 4, hemi := false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0 if h < 0.0 else h
	s.radial_segments = segs
	s.rings = rings
	s.is_hemisphere = hemi
	return s


static func _put(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mat is ShaderMaterial else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


# A cone pointing along dir (a spike), its base at pos.
static func _spike(parent: Node3D, mesh: CylinderMesh, mat: Material, base: Vector3, dir: Vector3) -> void:
	var mi := _put(parent, mesh, mat, base + dir.normalized() * mesh.height * 0.5)
	mi.basis = _align_y(dir)


static func _align_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, y, x.cross(y))


# A node following a bone, with its axes turned back to the model's axes (front +Z, up +Y).
static func _follow(sk: Skeleton3D, bone: String) -> Node3D:
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	sk.add_child(att)
	var holder := Node3D.new()
	var i := sk.find_bone(bone)
	if i >= 0:
		holder.basis = sk.get_bone_global_rest(i).basis.orthonormalized().inverse()
	att.add_child(holder)
	return holder


# A surface to stick things on: a mesh's triangles and the transform from that mesh to our node.
# hit() casts a ray in from outside (from centre c along dir) and returns [point, normal], or a
# point on a sphere of radius r if the ray misses.
class Surf:
	var tm: TriangleMesh
	var xf: Transform3D
	var c: Vector3
	var r: float

	func _init(mesh: Mesh, to_us: Transform3D, centre: Vector3, radius: float) -> void:
		tm = mesh.generate_triangle_mesh() if mesh else null
		xf = to_us
		c = centre
		r = radius

	func hit(dir: Vector3, lift := 0.008) -> Array:
		dir = dir.normalized()
		if tm:
			var inv := xf.affine_inverse()
			var res := tm.intersect_ray(inv * (c + dir * 3.0), (inv.basis * -dir).normalized())
			if not res.is_empty():
				var n: Vector3 = (xf.basis * res["normal"]).normalized()
				if n.dot(dir) < 0.0:
					n = -n
				return [xf * res["position"] + n * lift, n]
		return [c + dir * (r + lift), dir]

	func at(yaw: float, pitch: float, lift := 0.008) -> Array:
		return hit(Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)), lift)


# A basis whose z is the surface normal n and whose y runs along t (the long way of a sliver).
static func _on_surface(n: Vector3, t: Vector3) -> Basis:
	var x := t.cross(n)
	if x.length() < 0.001:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, n.cross(x).normalized(), n)


# A zigzag crack of glowing slivers across a surface, from angles (yaw, pitch) a to b, in n jagged steps.
static func _crack(parent: Node3D, mat: Material, srf: Surf, a: Vector2, b: Vector2, n: int, jag: float, w := 0.03) -> Array:
	var pts := []
	for k in n + 1:
		var ang := a.lerp(b, float(k) / n)
		if k > 0 and k < n:
			ang.x += jag * (1.0 if k % 2 == 0 else -1.0)
		pts.append(srf.at(ang.x, ang.y))
	for k in n:
		var p0: Vector3 = pts[k][0]
		var p1: Vector3 = pts[k + 1][0]
		var nrm: Vector3 = (pts[k][1] + pts[k + 1][1]).normalized()
		var d := p1 - p0
		var mi := _put(parent, _box(Vector3(w, d.length() + w, w * 0.8)), mat, (p0 + p1) * 0.5)
		mi.basis = _on_surface(nrm, d)
	return pts


# The worn piece's mesh: a hat hung on the head bone (name ending in suffix), or a skinned part.
static func _find_mesh(sk: Skeleton3D, suffix: String) -> MeshInstance3D:
	for ch in sk.get_children():
		if ch is MeshInstance3D and ch.name.begins_with("Skeleton_Warrior") and ch.name.ends_with(suffix):
			return ch
		if ch is BoneAttachment3D and ch.bone_name == "head":
			for m in ch.get_children():
				if m is MeshInstance3D and m.name.begins_with("Skeleton_Warrior") and m.name.ends_with(suffix):
					return m
	return null


# ---------------------------------------------------------------- head
static func head(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var ember := _ember(0.0)
	var iron := _iron()
	var rust := _rust()
	if bare:
		# Bare skull: glowing cracks over the cranium, held shut with iron staples, and a big rusty
		# nail stuck in the top (it doesn't seem to mind)
		var hm := _find_mesh(sk, "_Head")
		var hb := sk.find_bone("head")
		var to_head := sk.get_bone_global_rest(hb).affine_inverse() if hb >= 0 else Transform3D()
		var srf := Surf.new(hm.mesh if hm else null, to_head, Vector3(0, 0.5, 0), 0.45)
		var c1 := _crack(att, ember, srf, Vector2(0.15, 1.1), Vector2(0.6, 0.4), 4, 0.12)
		var c2 := _crack(att, ember, srf, Vector2(-0.6, 0.95), Vector2(-1.0, 0.35), 3, 0.12)
		var staple := _box(Vector3(0.03, 0.14, 0.03))
		for pair in [[c1[1], c1[2]], [c1[3], c1[4]], [c2[1], c2[2]]]:
			var p0: Vector3 = pair[0][0]
			var p1: Vector3 = pair[1][0]
			var nrm: Vector3 = pair[0][1]
			var mi := _put(att, staple, iron, (p0 + p1) * 0.5 + nrm * 0.008)
			mi.basis = _on_surface(nrm, (p1 - p0).cross(nrm))
		var top := srf.at(-0.5, 1.15, 0.0)
		var nail := Node3D.new()
		nail.position = top[0]
		nail.basis = _align_y((top[1] + Vector3(0, 0.3, 0)).normalized())
		att.add_child(nail)
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.025
		shaft.bottom_radius = 0.025
		shaft.height = 0.24
		shaft.radial_segments = 6
		_put(nail, shaft, rust, Vector3(0, 0.08, 0))
		var cap := CylinderMesh.new()
		cap.top_radius = 0.075
		cap.bottom_radius = 0.075
		cap.height = 0.04
		cap.radial_segments = 8
		_put(nail, cap, rust, Vector3(0, 0.2, 0))
		return
	# Helmet: ember cracks across the dome, rusty spikes on the brim
	var helm := _find_mesh(sk, "_Helmet")
	var srf := Surf.new(helm.mesh if helm else null, helm.transform if helm else Transform3D(), Vector3(0, 0.55, 0), 0.55)
	_crack(att, ember, srf, Vector2(0.35, 1.05), Vector2(0.95, 0.55), 4, 0.1)
	_crack(att, ember, srf, Vector2(-0.4, 1.0), Vector2(-0.95, 0.6), 3, 0.1)
	_crack(att, ember, srf, Vector2(2.7, 1.0), Vector2(2.2, 0.5), 3, 0.1)
	var sp := _cone(0.045, 0.16)
	for x in [-0.42, 0.42]:
		_spike(att, sp, rust, Vector3(x, 0.6, 0.42), Vector3(x * 1.2, 0.5, 0.9))


# ---------------------------------------------------------------- upper
static func upper(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var ember := _ember(1.3)
	var charred := _char()
	var iron := _iron()
	var rust := _rust()
	# Spiked, charred pauldrons with glowing cracks
	var dome := _ball(0.2, 0.2, 8, 3, true)
	var rim := TorusMesh.new()
	rim.inner_radius = 0.17
	rim.outer_radius = 0.22
	rim.rings = 8
	rim.ring_segments = 4
	var sp := _cone(0.045, 0.17)
	var slit := _box(Vector3(0.09, 0.025, 0.02))
	for side in [1.0, -1.0]:
		var h := _follow(sk, "upperarm.l" if side > 0 else "upperarm.r")
		var p := Node3D.new()
		p.position = Vector3(0.15 * side, 0.08, 0)
		p.rotation = Vector3(0, 0, -0.55 * side)
		h.add_child(p)
		_put(p, dome, charred, Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 1.05))
		_put(p, rim, rust, Vector3(0, 0.01, 0), Vector3.ZERO, Vector3(1, 1, 1.05))
		_spike(p, sp, iron, Vector3(0, 0.16, 0), Vector3(0.25 * side, 1, 0))
		_spike(p, sp, iron, Vector3(0.11 * side, 0.1, 0.07), Vector3(0.8 * side, 0.7, 0.35))
		_spike(p, sp, iron, Vector3(0.11 * side, 0.1, -0.07), Vector3(0.8 * side, 0.7, -0.35))
		_put(p, slit, ember, Vector3(0.0, 0.12, 0.155), Vector3(-0.7, 0, 0.3 * side))
	# A heavy chain slung from the left shoulder across to the right hip
	var chain_mat := _dark_iron()
	var link := TorusMesh.new()
	link.inner_radius = 0.028
	link.outer_radius = 0.055
	link.rings = 6
	link.ring_segments = 4
	var a := Vector3(0.27, 0.12, 0.33)
	var b := Vector3(-0.3, -0.42, 0.37)
	var n := 9
	for k in n:
		var t := (k + 0.5) / n
		var pos := a.lerp(b, t)
		pos.z += sin(t * PI) * 0.07   # bulges over the belly
		pos.y -= sin(t * PI) * 0.04   # and sags a little
		var mi := _put(att, link, chain_mat, pos)
		var d := (b - a).normalized()
		var up := Vector3.BACK if k % 2 == 0 else d.cross(Vector3.BACK).normalized()
		mi.basis = Basis(d, up, d.cross(up).normalized()) * Basis.from_scale(Vector3(1.35, 1, 1))
	# An iron shackle where the chain hangs off the shoulder, and a glowing padlock at the hip
	_put(att, _box(Vector3(0.12, 0.09, 0.06)), rust, b + Vector3(-0.02, -0.06, 0.02))
	_put(att, _box(Vector3(0.03, 0.03, 0.02)), ember, b + Vector3(-0.02, -0.06, 0.055))


# ---------------------------------------------------------------- lower
static func lower(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var ember := _ember(2.6)
	var bone := _bone()
	var rust := _rust()
	var charred := _char()
	# Skull belt buckle with glowing eyes and a jaw
	var sk_node := Node3D.new()
	sk_node.position = Vector3(0, 0.08, 0.4)
	att.add_child(sk_node)
	_put(sk_node, _ball(0.085, 0.15, 8, 4), bone, Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1.1, 1, 0.7))
	_put(sk_node, _box(Vector3(0.11, 0.05, 0.08)), bone, Vector3(0, -0.06, -0.005))
	var eye := _ball(0.024, -1.0, 6, 3)
	_put(sk_node, eye, ember, Vector3(-0.035, 0.025, 0.055))
	_put(sk_node, eye, ember, Vector3(0.035, 0.025, 0.055))
	var tooth := _box(Vector3(0.015, 0.03, 0.01))
	for tx in [-0.03, 0.0, 0.03]:
		_put(sk_node, tooth, charred, Vector3(tx, -0.06, 0.04))
	# Tattered, charred loin flaps hanging from the belt, front and back
	var cloth := _mat(Color(0.2, 0.06, 0.05), 0.95)
	var strip := _box(Vector3(0.075, 1, 0.025))
	var tip := _box(Vector3(0.053, 0.053, 0.025))
	var lens := [0.17, 0.12, 0.19, 0.11]
	for back in [false, true]:
		var z := -0.22 if back else 0.34
		var tilt := -0.15 if back else 0.15
		for k in lens.size():
			var x := -0.12 + k * 0.08
			var l: float = lens[k] if not back else lens[lens.size() - 1 - k]
			var y := 0.0 - l * 0.5
			_put(att, strip, cloth, Vector3(x, y, z + sin(tilt) * l * 0.5), Vector3(tilt, 0, 0), Vector3(1, l, 1))
			# a ragged point at the bottom
			_put(att, tip, cloth, Vector3(x, -l, z + sin(tilt) * l), Vector3(tilt, 0, PI / 4))
	# Rusted iron knee guards with a spike
	var plate := _box(Vector3(0.2, 0.16, 0.06))
	var sp := _cone(0.04, 0.13)
	var rivet := _ball(0.018, -1.0, 6, 3)
	for side in ["l", "r"]:
		var h := _follow(sk, "lowerleg." + side)
		var g := Node3D.new()
		g.position = Vector3(0, 0.03, 0.15)
		g.rotation.x = -0.15
		h.add_child(g)
		_put(g, plate, rust, Vector3.ZERO)
		_spike(g, sp, _iron(), Vector3(0, 0.0, 0.03), Vector3(0, 0.6, 1))
		_put(g, rivet, charred, Vector3(-0.07, -0.05, 0.03))
		_put(g, rivet, charred, Vector3(0.07, -0.05, 0.03))
