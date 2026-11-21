extends RefCounted
# Skeleton Mage details: a necromancer from the pit.
#   head  - hat: a melting candle with an ember flame and a tiny skull with crossed bones on the brim, an
#           iron rune plate glowing with hellfire on the hat band, iron studs round the band.
#           bare: an ember crack across the skull and a candle stub melted onto the top of it.
#   upper - a bone-and-teeth necklace with a little skull pendant, a tattered sash with glowing sigils,
#           a chained grimoire with a glowing eye hanging off the belt.
#   lower - bone toe-caps with claws, tattered shin wraps with ember stitches, rusted iron anklets.
# (KayKit model space: the character faces +Z, +X is its left. Torso bones aren't rotated.)

const HEAD_Y := 1.2414
const CHEST_Y := 0.9726
const HIPS_Y := 0.4057

const BONE := Color(0.88, 0.84, 0.72)
const CHAR := Color(0.09, 0.07, 0.07)
const IRON := Color(0.33, 0.2, 0.15)
const EMBER := Color(1.0, 0.38, 0.08)
const WAX := Color(0.86, 0.8, 0.64)
const SASH := Color(0.28, 0.05, 0.07)
const LEATHER := Color(0.24, 0.11, 0.07)


# ---------------------------------------------------------------- head

static func head(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var bone := _mat(BONE, 0.7)
	var iron := _iron()
	var glow := _pulse(EMBER, 3.0)
	var wax := _mat(WAX, 0.45)
	if bare:
		# An ember crack zig-zagging from the crown down the side of the skull
		var crack := []
		var pts := [Vector3(0.06, 0.935, 0.08), Vector3(0.2, 0.9, 0.0), Vector3(0.3, 0.84, 0.1),
				Vector3(0.41, 0.74, 0.02), Vector3(0.47, 0.62, 0.1), Vector3(0.49, 0.5, 0.03)]
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var out := ((a + b) * 0.5 - Vector3(0, 0.3, 0)).normalized()
			var xf := Transform3D(_align_y(b - a), (a + b) * 0.5)
			xf.basis = Basis(out.cross(b - a).normalized() * 0.035, (b - a), out * 0.05)
			crack.append([_box(Vector3.ONE), xf])
		_add(att, _merge(crack), glow)
		# A candle stub melted onto the skull (goofy), with drips running down the bone
		_candle(att, Vector3(-0.08, 0.905, -0.1), 0.17, wax, glow, 1.15)
		return
	# Hat band: iron studs round it, and an iron plate with a glowing hellfire rune at the front
	var studs := []
	for k in 8:
		var a := TAU * (k + 0.5) / 8.0
		if abs(a - TAU) < 0.5 or a < 0.5:
			continue
		var p := Vector3(sin(a) * 0.47, 0.87, cos(a) * 0.47)
		studs.append([_cone(0.05, 0.11), Transform3D(_align_y(Vector3(sin(a), 0.15, cos(a))), p)])
	var plate_xf := Transform3D(Basis.from_euler(Vector3(-0.3, 0, 0)), Vector3(0, 0.86, 0.47))
	studs.append([_box(Vector3(0.24, 0.2, 0.04)), plate_xf])
	_add(att, _merge(studs), iron)
	# The rune: a flame-trident sigil
	var rune := []
	var r := [[Vector3(0, -0.07, 0), Vector3(0, 0.08, 0)], [Vector3(-0.06, 0.05, 0), Vector3(-0.035, -0.03, 0)],
			[Vector3(0.06, 0.05, 0), Vector3(0.035, -0.03, 0)], [Vector3(-0.035, -0.03, 0), Vector3(0.035, -0.03, 0)],
			[Vector3(-0.04, -0.07, 0), Vector3(0.04, -0.07, 0)]]
	for s in r:
		var xf := _seg_xf(s[0], s[1], 0.022)
		rune.append([_box(Vector3(1, 1, 0.02)), plate_xf * Transform3D(xf.basis, xf.origin + Vector3(0, 0, 0.025))])
	_add(att, _merge(rune), glow)
	# A melting candle on the brim (the character's left), with a wax puddle dripping off the edge
	_candle(att, Vector3(0.56, 0.72, 0.24), 0.26, wax, glow, 1.35)
	_candle(att, Vector3(0.7, 0.63, 0.04), 0.13, wax, glow, 1.0)
	# A tiny skull on the brim (the right), on a pair of crossed bones
	var bones := []
	bones.append([_bone_mesh(0.34), Transform3D(Basis.from_euler(Vector3(0, 0.6, 0.18)), Vector3(-0.6, 0.72, 0.2))])
	bones.append([_bone_mesh(0.34), Transform3D(Basis.from_euler(Vector3(0, -0.6, 0.18)), Vector3(-0.6, 0.72, 0.2))])
	_add(att, _merge(bones), bone)
	_skull(att, Transform3D(Basis.from_euler(Vector3(0.1, -0.35, -0.12)).scaled(Vector3.ONE * 1.35), Vector3(-0.56, 0.84, 0.24)), bone, glow)


# ---------------------------------------------------------------- upper

static func upper(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var bone := _mat(BONE, 0.7)
	var glow := _pulse(EMBER, 2.6)
	var off := Vector3(0, -CHEST_Y, 0)
	# Bone necklace: little bones with fangs between them, hanging in a U round the collar
	var beads := []
	var teeth := []
	var n := 11
	for i in n:
		var t := float(i) / (n - 1) * 2.0 - 1.0
		var a := t * 1.25
		var p := Vector3(sin(a) * 0.34, 1.17 - 0.15 * cos(t * PI / 2.0), cos(a) * 0.33 + 0.02) + off
		if i % 2 == 0:
			beads.append([_sphere(0.04), Transform3D(Basis(Vector3.UP, a) * Basis.from_scale(Vector3(1.7, 0.9, 0.9)), p)])
		else:
			teeth.append([_cone(0.03, 0.09), Transform3D(Basis.from_euler(Vector3(PI, 0, 0)), p + Vector3(0, -0.02, 0.01))])
	_add(att, _merge(beads + teeth), bone)
	_skull(att, Transform3D(Basis.from_euler(Vector3(-0.15, 0, 0)), Vector3(0, 0.95, 0.39) + off), bone, glow)
	# A tattered sash across the robe, from the left shoulder to the right hip, with glowing sigils
	var cloth := _mat(SASH, 0.9)
	var sash := []
	var sig := []
	var path := [Vector3(0.27, 1.16, 0.3), Vector3(0.17, 1.02, 0.34), Vector3(0.05, 0.88, 0.38),
			Vector3(-0.08, 0.76, 0.42), Vector3(-0.2, 0.64, 0.43), Vector3(-0.3, 0.54, 0.4)]
	for i in path.size() - 1:
		var xf := _seg_xf(path[i] + off, path[i + 1] + off, 0.12)
		sash.append([_box(Vector3(1.12, 1, 0.035)), xf])
		if i >= 1 and i <= 3:
			var c: Vector3 = (path[i] + path[i + 1]) * 0.5 + off + Vector3(0, 0, 0.02)
			var shapes := [[Vector3(-0.03, -0.03, 0), Vector3(0, 0.035, 0)], [Vector3(0, 0.035, 0), Vector3(0.03, -0.03, 0)],
					[Vector3(-0.035, 0.0, 0), Vector3(0.035, 0.0, 0)]] if i % 2 == 1 else \
					[[Vector3(0, -0.04, 0), Vector3(0, 0.04, 0)], [Vector3(-0.03, 0.02, 0), Vector3(0.03, 0.02, 0)],
					[Vector3(-0.03, -0.02, 0), Vector3(0, -0.04, 0)]]
			for s in shapes:
				var sx := _seg_xf(s[0], s[1], 0.016)
				sig.append([_box(Vector3(1, 1, 0.02)), Transform3D(xf.basis.orthonormalized() * sx.basis, c + xf.basis.orthonormalized() * sx.origin)])
	# The knot and tattered ends hang from the hips (so they swing with the legs, not the chest)
	var hips := _bone_att(sk, "hips")
	var hoff := Vector3(0, -HIPS_Y, 0)
	var knot := Vector3(-0.3, 0.55, 0.42) + hoff
	var tails := []
	tails.append([_sphere(0.065), Transform3D(Basis.from_scale(Vector3(1.2, 1, 0.6)), knot)])
	var ends := [[-0.04, 0.15], [0.05, 0.11], [-0.1, 0.08]]
	for e in ends:
		var top: Vector3 = knot + Vector3(e[0], -0.03, 0.0)
		var bot: Vector3 = top + Vector3(e[0] * 0.5, -e[1], 0.015)
		tails.append([_box(Vector3(0.06, 1, 0.025)), _seg_xf_y(top, bot)])
		tails.append([_cone(0.035, 0.06, 3), Transform3D(_align_y(bot - top) * Basis.from_scale(Vector3(1, 1, 0.4)), bot + (bot - top).normalized() * 0.03)])
	_add(hips, _merge(tails), cloth)
	_add(att, _merge(sash), cloth)
	_add(att, _merge(sig), glow)
	# A chained grimoire hanging off the belt (right hip), with a glowing eye on its cover
	var book_at := Vector3(-0.47, 0.5, 0.05) + hoff
	var book_xf := Transform3D(Basis.from_euler(Vector3(0.05, -PI / 2, 0.1)), book_at)
	_add(hips, _merge([[_box(Vector3(0.2, 0.25, 0.08)), book_xf]]), _mat(LEATHER, 0.8))
	_add(hips, _merge([[_box(Vector3(0.185, 0.235, 0.07)), book_xf * Transform3D(Basis(), Vector3(0.012, 0, 0))]]), _mat(Color(0.8, 0.74, 0.58), 0.9))
	var metal := []
	for cx in [-1.0, 1.0]:
		for cy in [-1.0, 1.0]:
			metal.append([_box(Vector3(0.05, 0.05, 0.09)), book_xf * Transform3D(Basis(), Vector3(cx * 0.085, cy * 0.11, 0))])
	# chain links from the belt down to the book's spine
	for k in 3:
		var lp := Vector3(-0.43, 0.76 - k * 0.07, 0.05) + hoff
		var tl := TorusMesh.new()
		tl.inner_radius = 0.018
		tl.outer_radius = 0.032
		tl.rings = 6
		tl.ring_segments = 4
		metal.append([tl, Transform3D(Basis.from_euler(Vector3(PI / 2, PI / 2 * (k % 2), 0)), lp)])
	_add(hips, _merge(metal), _iron())
	var eye := []
	eye.append([_sphere(0.045), book_xf * Transform3D(Basis.from_scale(Vector3(1.3, 0.7, 0.4)), Vector3(0, 0.01, 0.045))])
	_add(hips, _merge(eye), _pulse(Color(1.0, 0.55, 0.1), 3.0))
	var pupil := []
	pupil.append([_sphere(0.022), book_xf * Transform3D(Basis.from_scale(Vector3(0.5, 1.1, 0.5)), Vector3(0, 0.01, 0.06))])
	_add(hips, _merge(pupil), _mat(CHAR, 0.5))


# ---------------------------------------------------------------- lower

static func lower(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var bone := _mat(BONE, 0.65)
	var cloth := _mat(Color(0.2, 0.16, 0.13), 0.95)
	var iron := _iron()
	var glow := _pulse(EMBER, 2.4)
	for side in [1.0, -1.0]:
		var sfx := ".l" if side > 0 else ".r"
		var x: float = 0.17 * side
		# Bone toe-caps with three little claws
		var toes := _bone_att(sk, "toes" + sfx)
		var caps := []
		caps.append([_sphere(0.1), _to_bone(sk, "toes" + sfx, Transform3D(Basis.from_scale(Vector3(1.25, 0.75, 1.0)), Vector3(x, 0.09, 0.15)))])
		for c in 3:
			var cx: float = x + (c - 1) * 0.06
			caps.append([_cone(0.025, 0.08), _to_bone(sk, "toes" + sfx, Transform3D(_align_y(Vector3((c - 1) * 0.3, -0.25, 1)), Vector3(cx, 0.06, 0.25)))])
		_add(toes, _merge(caps), bone)
		# Tattered shin wraps with an ember stitch, and a rusted anklet with spikes
		var shin := _bone_att(sk, "lowerleg" + sfx)
		var wraps := []
		for w in 3:
			var tw := TorusMesh.new()
			tw.inner_radius = 0.085
			tw.outer_radius = 0.125
			tw.rings = 8
			tw.ring_segments = 4
			wraps.append([tw, _to_bone(sk, "lowerleg" + sfx, Transform3D(Basis.from_euler(Vector3(0.15 * (w - 1), 0, 0.12 * side * (1 - w))), Vector3(x, 0.32 - w * 0.06, 0.0)))])
		# a loose strip hanging off the outside
		wraps.append([_box(Vector3(0.05, 0.14, 0.02)), _to_bone(sk, "lowerleg" + sfx, Transform3D(Basis.from_euler(Vector3(0, 0, 0.25 * side)), Vector3(x + 0.12 * side, 0.22, -0.02)))])
		_add(shin, _merge(wraps), cloth)
		var st := []
		for k in 2:
			st.append([_box(Vector3(0.05, 0.018, 0.02)), _to_bone(sk, "lowerleg" + sfx, Transform3D(Basis.from_euler(Vector3(0, 0, 0.5 * (1 - 2 * k))), Vector3(x, 0.27, 0.12)))])
		_add(shin, _merge(st), glow)
		var foot := _bone_att(sk, "foot" + sfx)
		var ank := []
		var ta := TorusMesh.new()
		ta.inner_radius = 0.1
		ta.outer_radius = 0.135
		ta.rings = 10
		ta.ring_segments = 4
		ank.append([ta, _to_bone(sk, "foot" + sfx, Transform3D(Basis(), Vector3(x, 0.16, 0.0)))])
		for k in 3:
			var a: float = PI / 2 * side + (k - 1) * 0.9
			var d := Vector3(sin(a), 0, cos(a))
			ank.append([_cone(0.025, 0.07), _to_bone(sk, "foot" + sfx, Transform3D(_align_y(d), Vector3(x, 0.16, 0) + d * 0.14))])
		_add(foot, _merge(ank), iron)


# ---------------------------------------------------------------- pieces

# A melting candle standing at `base` (its bottom), wax drips and a puddle, a wick and a flickering flame.
static func _candle(att: Node3D, base: Vector3, h: float, wax: Material, glow: Material, s: float) -> void:
	var rad := 0.055 * s
	var parts := []
	var cyl := CylinderMesh.new()
	cyl.top_radius = rad * 0.95
	cyl.bottom_radius = rad
	cyl.height = h
	cyl.radial_segments = 8
	cyl.rings = 1
	parts.append([cyl, Transform3D(Basis(), base + Vector3(0, h * 0.5, 0))])
	# puddle at the foot and a melted rim at the top
	parts.append([_sphere(rad * 1.9), Transform3D(Basis.from_scale(Vector3(1, 0.22, 1)), base + Vector3(0, 0.005, 0))])
	parts.append([_sphere(rad * 1.05), Transform3D(Basis.from_scale(Vector3(1, 0.35, 1)), base + Vector3(0, h, 0))])
	# drips running down the sides
	for k in 3:
		var a := 0.7 + k * 2.1
		var len := h * (0.35 + 0.18 * k)
		var cap := CapsuleMesh.new()
		cap.radius = rad * 0.32
		cap.height = len
		cap.radial_segments = 6
		cap.rings = 2
		parts.append([cap, Transform3D(Basis(), base + Vector3(sin(a) * rad * 0.95, h - len * 0.5 + rad * 0.2, cos(a) * rad * 0.95))])
	_add(att, _merge(parts), wax)
	var wick := []
	wick.append([_box(Vector3(0.012, 0.035, 0.012)) , Transform3D(Basis(), base + Vector3(0, h + 0.02, 0))])
	_add(att, _merge(wick), _mat(CHAR, 0.8))
	var f := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.045 * s
	fm.height = 0.16 * s
	fm.radial_segments = 8
	fm.rings = 6
	f.mesh = fm
	f.material_override = _flame()
	f.position = base + Vector3(0, h + 0.09 * s, 0)
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	att.add_child(f)


# A little goofy skull with glowing eye dots (about 0.2 wide), placed by `xf`.
static func _skull(att: Node3D, xf: Transform3D, bone: Material, glow: Material) -> void:
	var p := []
	p.append([_sphere(0.085), xf * Transform3D(Basis.from_scale(Vector3(1.0, 0.92, 0.95)), Vector3(0, 0.02, 0))])
	p.append([_box(Vector3(0.11, 0.05, 0.08)), xf * Transform3D(Basis(), Vector3(0, -0.055, 0.03))])
	_add(att, _merge(p), bone)
	var holes := []
	for side in [-1.0, 1.0]:
		holes.append([_sphere(0.022), xf * Transform3D(Basis(), Vector3(0.033 * side, 0.01, 0.075))])
	_add(att, _merge(holes), glow)
	var teeth := []
	teeth.append([_box(Vector3(0.07, 0.012, 0.01)), xf * Transform3D(Basis(), Vector3(0, -0.055, 0.072))])
	teeth.append([_box(Vector3(0.025, 0.02, 0.01)), xf * Transform3D(Basis(), Vector3(0, -0.012, 0.08))])
	_add(att, _merge(teeth), _mat(CHAR, 0.8))


# A cartoon bone of length L along X.
static func _bone_mesh(L: float) -> Mesh:
	var p := []
	var c := CylinderMesh.new()
	c.top_radius = 0.022
	c.bottom_radius = 0.022
	c.height = L
	c.radial_segments = 6
	c.rings = 1
	p.append([c, Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3.ZERO)])
	for e in [-1.0, 1.0]:
		for k in [-1.0, 1.0]:
			p.append([_sphere(0.032), Transform3D(Basis(), Vector3(e * L * 0.5, 0, k * 0.022))])
	return _merge(p)


# ---------------------------------------------------------------- helpers

static func _bone_att(sk: Skeleton3D, bone: String) -> BoneAttachment3D:
	var a := BoneAttachment3D.new()
	a.bone_name = bone
	sk.add_child(a)
	return a


# A transform given in model space, turned into the bone's space (using the bone's rest pose).
static func _to_bone(sk: Skeleton3D, bone: String, xf: Transform3D) -> Transform3D:
	var i := sk.find_bone(bone)
	if i < 0:
		return xf
	return sk.get_bone_global_rest(i).affine_inverse() * xf


static func _add(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _merge(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	for p in parts:
		st.append_from(p[0], 0, p[1])
	return st.commit()


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 8
	s.rings = 5
	return s


static func _cone(r: float, h: float, segs := 6) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


# A box of unit length along X (scaled to reach from a to b, `w` tall), facing +Z.
static func _seg_xf(a: Vector3, b: Vector3, w: float) -> Transform3D:
	var d := b - a
	var x := d.normalized()
	var z := Vector3(0, 0, 1)
	var y := z.cross(x).normalized()
	z = x.cross(y).normalized()
	return Transform3D(Basis(x * d.length(), y * w, z), (a + b) * 0.5)


static func _seg(mesh: Mesh, a: Vector3, b: Vector3, w: float) -> Array:
	return [mesh, _seg_xf(a, b, w)]


# A box of unit height along Y, stretched to reach from a to b.
static func _seg_xf_y(a: Vector3, b: Vector3) -> Transform3D:
	var d := b - a
	var basis := _align_y(d)
	return Transform3D(Basis(basis.x, basis.y * d.length(), basis.z), (a + b) * 0.5)


static func _align_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, y, x.cross(y))


static func _mat(c: Color, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _iron() -> StandardMaterial3D:
	var m := _mat(IRON, 0.55)
	m.metallic = 0.5
	return m


# Glowing ember that breathes slowly (a shader using TIME, so no scripts).
static var _pulse_sh: Shader
static var _flame_sh: Shader


static func _pulse(c: Color, e: float) -> ShaderMaterial:
	if _pulse_sh == null:
		_pulse_sh = Shader.new()
		_pulse_sh.code = """
shader_type spatial;
uniform vec4 col : source_color;
uniform float energy = 3.0;
void fragment() {
	float p = 0.75 + 0.25 * sin(TIME * 2.3 + NODE_POSITION_WORLD.x * 3.0);
	ALBEDO = col.rgb;
	EMISSION = col.rgb * energy * p;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _pulse_sh
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("energy", e)
	return m


# A flickering candle flame: teardrop-shaped, swaying, yellow core to ember-red tip.
static func _flame() -> ShaderMaterial:
	if _flame_sh == null:
		_flame_sh = Shader.new()
		_flame_sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
varying float h;
void vertex() {
	h = clamp(VERTEX.y / 0.08 * 0.5 + 0.5, 0.0, 1.0);
	VERTEX.xz *= 1.0 - 0.75 * h * h;
	float t = TIME * 9.0 + NODE_POSITION_WORLD.x * 7.0;
	VERTEX.x += sin(t) * 0.012 * h;
	VERTEX.z += cos(t * 1.3) * 0.008 * h;
	VERTEX.y *= 1.0 + 0.12 * sin(t * 0.7);
}
void fragment() {
	vec3 core = vec3(1.0, 0.85, 0.35);
	vec3 tip = vec3(1.0, 0.25, 0.05);
	ALBEDO = mix(core, tip, h) * 2.5;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _flame_sh
	return m
