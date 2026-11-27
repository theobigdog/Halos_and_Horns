# Hand-built props added from Ted's notes (Nov 26): three jack-o'-lanterns carved from the classic pumpkin
# (a candle inside, E lights or snuffs it), three explosives (E lights the fuse... and the demon inside goes
# up with it), a rocking chair (E rocks it) and a weapon rack that actually holds weapons. Their animations
# live in prop_animator.gd; prop_library.gd lists them with the other props.
extends RefCounted

const ClassicLook = preload("res://scripts/classic_look.gd")
const Models = preload("res://scripts/models.gd")
const Surfaces = preload("res://scripts/surfaces.gd")

# Same fields as PropLib.CLASSIC, plus "cat" (the Creative palette section).
const TYPES := {
	"jack_o_lantern_grin": {"shape": "cylinder", "radius": 0.4, "height": 0.66, "label": "Jack-o'-lantern (grin)", "hp": 70, "speed": 6.5, "mass": 1.0, "round": true, "cat": "Graveyard"},
	"jack_o_lantern_scary": {"shape": "cylinder", "radius": 0.4, "height": 0.66, "label": "Jack-o'-lantern (scary)", "hp": 70, "speed": 6.5, "mass": 1.0, "round": true, "cat": "Graveyard"},
	"jack_o_lantern_goofy": {"shape": "cylinder", "radius": 0.4, "height": 0.66, "label": "Jack-o'-lantern (goofy)", "hp": 70, "speed": 6.5, "mass": 1.0, "round": true, "cat": "Graveyard"},
	"tnt_crate": {"shape": "box", "size": Vector3(0.8, 0.62, 0.6), "label": "TNT crate", "hp": 90, "speed": 5.5, "mass": 2.0, "cat": "Explosives"},
	"dynamite_bundle": {"shape": "box", "size": Vector3(0.34, 0.5, 0.24), "label": "Dynamite bundle", "hp": 45, "speed": 7.5, "mass": 0.5, "cat": "Explosives"},
	"powder_keg": {"shape": "cylinder", "radius": 0.36, "height": 0.82, "label": "Powder keg", "hp": 110, "speed": 5.0, "mass": 2.4, "cat": "Explosives"},
	"rocking_chair": {"shape": "box", "size": Vector3(0.68, 1.12, 0.95), "label": "Rocking chair", "hp": 100, "speed": 5.5, "mass": 1.6, "cat": "Furniture"},
	"weaponrack_armed": {"shape": "box", "size": Vector3(1.2, 1.6, 0.78), "label": "Weapon rack (armed)", "hp": 140, "speed": 4.8, "mass": 2.8, "cat": "Village & nature"},
	# (Wife's notes, Nov 26: a garbage can, bushes that aren't in pots, flowers and plants: classic_props.gd)
	"trash_can": {"shape": "cylinder", "radius": 0.3, "height": 0.86, "label": "Garbage can", "hp": 90, "speed": 5.5, "mass": 1.4, "cat": "Town"},
	"wheelie_bin": {"shape": "box", "size": Vector3(0.62, 1.03, 0.72), "label": "Wheelie bin", "hp": 120, "speed": 5.0, "mass": 2.0, "cat": "Town"},
	"bush": {"shape": "cylinder", "radius": 0.72, "height": 1.0, "label": "Bush", "hp": 110, "speed": 5.0, "mass": 1.6, "round": true, "cat": "Village & nature"},
	"bush_flowering": {"shape": "cylinder", "radius": 0.62, "height": 0.86, "label": "Flowering bush", "hp": 100, "speed": 5.2, "mass": 1.4, "round": true, "cat": "Village & nature"},
	"flowers_daisies": {"shape": "cylinder", "radius": 0.32, "height": 0.4, "label": "Daisies", "hp": 40, "speed": 7.5, "mass": 0.4, "cat": "Village & nature"},
	"flowers_tulips": {"shape": "cylinder", "radius": 0.28, "height": 0.5, "label": "Tulips", "hp": 40, "speed": 7.5, "mass": 0.4, "cat": "Village & nature"},
	"fern": {"shape": "cylinder", "radius": 0.45, "height": 0.55, "label": "Fern", "hp": 50, "speed": 7.0, "mass": 0.5, "cat": "Village & nature"},
}
const ClassicProps = preload("res://scripts/classic_props.gd")


static func has(type_name: String) -> bool:
	return TYPES.has(type_name)


static func make(type_name: String) -> Node3D:
	var root := Node3D.new()
	match type_name:
		"jack_o_lantern_grin": _jack(root, 0)
		"jack_o_lantern_scary": _jack(root, 1)
		"jack_o_lantern_goofy": _jack(root, 2)
		"tnt_crate": _tnt(root)
		"dynamite_bundle": _dynamite(root, Vector3.ZERO, true)
		"powder_keg": _keg(root)
		"rocking_chair": _rocking_chair(root)
		"weaponrack_armed": _weapon_rack(root)
		_: ClassicProps.make(type_name, root)
	return root


static var _cache := {}


static func _mat(color: Color, kind := "", rough := -1.0) -> StandardMaterial3D:
	var key := "%s|%s|%f" % [color.to_html(), kind, rough]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		Surfaces.apply(m, kind)
		if rough >= 0.0:
			m.roughness = rough
		_cache[key] = m
	return _cache[key]


static func _add(parent: Node3D, mesh: Mesh, m: Material, at: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi


# Point a mesh's own y axis (a cylinder's length) along d (works before it's in the scene).
static func _align_y(mi: Node3D, d: Vector3) -> void:
	var y := d.normalized()
	var ref := Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD
	var x := y.cross(ref).normalized()
	mi.basis = Basis(x, y, x.cross(y))


static func _cyl(r_top: float, r_bot: float, h: float, sides := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = sides
	c.rings = 1
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _ball(r: float, seg := 12) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = seg / 2
	return s


# ---------- jack-o'-lanterns ----------

# The carved face is drawn over the pumpkin's own skin (its material_overlay), so it follows every bulge.
# The holes glow candle-orange when lit ("lit", set by the animator) and are dark hollows when not.
const FACE := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque;
instance uniform float lit = 1.0;
uniform int face = 0;
uniform vec3 centre = vec3(0.0, 0.33, 0.0);
uniform vec2 radius = vec2(0.4, 0.33);
varying vec3 lp;
void vertex() { lp = VERTEX; }
float tri(vec2 p, vec2 a, vec2 b, vec2 c) {
	vec2 e0 = b - a; vec2 e1 = c - b; vec2 e2 = a - c;
	float d0 = (p.x - a.x) * e0.y - (p.y - a.y) * e0.x;
	float d1 = (p.x - b.x) * e1.y - (p.y - b.y) * e1.x;
	float d2 = (p.x - c.x) * e2.y - (p.y - c.y) * e2.x;
	return float((d0 <= 0.0 && d1 <= 0.0 && d2 <= 0.0) || (d0 >= 0.0 && d1 >= 0.0 && d2 >= 0.0));
}
float ell(vec2 p, vec2 c, vec2 r) { vec2 q = (p - c) / r; return step(dot(q, q), 1.0); }
float carve(vec2 p) {
	float m = 0.0;
	if (face == 0) {        // classic grin: triangle eyes and nose, a zig-zag smile
		m += tri(p, vec2(-0.42, 0.2), vec2(-0.12, 0.2), vec2(-0.27, 0.5));
		m += tri(p, vec2(0.12, 0.2), vec2(0.42, 0.2), vec2(0.27, 0.5));
		m += tri(p, vec2(-0.08, -0.02), vec2(0.08, -0.02), vec2(0.0, 0.14));
		float smile = step(abs(p.x), 0.55) * step(p.y, -0.12 + 0.35 * p.x * p.x) * step(-0.42 + 0.5 * p.x * p.x, p.y);
		float teeth = step(0.5, fract(p.x * 4.5)) * step(-0.2 + 0.35 * p.x * p.x, p.y);
		m += smile * (1.0 - teeth);
	} else if (face == 1) { // scary: slanted angry eyes, a jagged mouth with fangs
		m += tri(p, vec2(-0.5, 0.42), vec2(-0.1, 0.2), vec2(-0.42, 0.14));
		m += tri(p, vec2(0.5, 0.42), vec2(0.1, 0.2), vec2(0.42, 0.14));
		m += tri(p, vec2(-0.06, 0.06), vec2(0.06, 0.06), vec2(0.0, -0.06));
		float jaw = step(abs(p.x), 0.6) * step(p.y, -0.1 - 0.12 * abs(sin(p.x * 14.0))) * step(-0.5 + 0.25 * p.x * p.x, p.y);
		float fang = tri(p, vec2(-0.22, -0.1), vec2(-0.1, -0.1), vec2(-0.16, -0.3)) + tri(p, vec2(0.1, -0.1), vec2(0.22, -0.1), vec2(0.16, -0.3));
		m += jaw * (1.0 - clamp(fang, 0.0, 1.0));
	} else {                // goofy: one big eye, one little one, a lopsided grin with the tongue out
		m += ell(p, vec2(-0.25, 0.3), vec2(0.17, 0.2));
		m += ell(p, vec2(0.25, 0.27), vec2(0.09, 0.1));
		float grin = step(abs(p.x - 0.05), 0.5) * step(p.y, -0.08 + 0.3 * (p.x - 0.05) * (p.x - 0.05) + 0.08 * p.x) * step(-0.36 + 0.35 * (p.x - 0.05) * (p.x - 0.05), p.y);
		float tongue = ell(p, vec2(0.15, -0.3), vec2(0.12, 0.09));
		m += grin * (1.0 - tongue);
	}
	return clamp(m, 0.0, 1.0);
}
void fragment() {
	vec3 d = lp - centre;
	float ang = atan(d.x, d.z);   // 0 straight out the front
	vec2 p = vec2(ang / 1.25, d.y / radius.y);
	if (abs(ang) > 1.5 || carve(p) < 0.5) discard;
	// a thin rim of carved flesh, then the hollow (glowing when the candle is lit)
	float rim = carve(p * 1.08) < 0.5 ? 1.0 : 0.0;
	vec3 flesh = vec3(0.95, 0.75, 0.35);
	vec3 hollow = mix(vec3(0.05, 0.02, 0.01), vec3(1.0, 0.62, 0.15), lit);
	float flick = 0.85 + 0.15 * sin(TIME * 17.0) * sin(TIME * 5.3);
	ALBEDO = mix(hollow, flesh * (0.6 + 0.4 * lit), rim);
	EMISSION = mix(vec3(1.0, 0.55, 0.12) * 2.2 * flick, vec3(1.0, 0.6, 0.2) * 0.3, rim) * lit;
	ROUGHNESS = 0.8;
}
"""


static func _jack(root: Node3D, face: int) -> void:
	ClassicLook.pumpkin(root)
	var body := root.get_child(0) as MeshInstance3D
	body.name = "Face"
	var key := "face%d" % face
	if not _cache.has(key):
		var sh := Shader.new()
		sh.code = FACE
		var m := ShaderMaterial.new()
		m.shader = sh
		var box := body.mesh.get_aabb()
		m.set_shader_parameter("face", face)
		m.set_shader_parameter("centre", box.get_center())
		m.set_shader_parameter("radius", Vector2(box.size.x * 0.5, box.size.y * 0.5))
		_cache[key] = m
	body.material_overlay = _cache[key]
	var l := OmniLight3D.new()
	l.name = "Candle"
	l.light_color = Color(1.0, 0.6, 0.2)
	l.light_energy = 1.0
	l.omni_range = 4.5
	l.position = body.mesh.get_aabb().get_center() + Vector3(0.0, 0.0, 0.1)
	root.add_child(l)


# ---------- explosives ----------

const STICK_RED := Color(0.78, 0.1, 0.07)


static func _fuse_line(root: Node3D, pts: Array) -> void:
	var rope := _mat(Color(0.32, 0.24, 0.15), "cloth")
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var seg := _add(root, _cyl(0.011, 0.011, a.distance_to(b) + 0.01, 6), rope, (a + b) * 0.5)
		_align_y(seg, b - a)
	root.set_meta("fuse_tip", pts[pts.size() - 1])
	root.set_meta("fuse_base", pts[0])


# Six red sticks, taped together, with a curly fuse.
static func _dynamite(root: Node3D, at: Vector3, fuse: bool) -> void:
	var paper := _mat(STICK_RED, "cloth", 0.7)
	var cap := _mat(Color(0.85, 0.8, 0.68), "cloth")
	var tape := _mat(Color(0.3, 0.24, 0.18), "leather")
	for i in 6:
		var x := (float(i % 3) - 1.0) * 0.095
		var z := (float(i / 3) - 0.5) * 0.095
		_add(root, _cyl(0.046, 0.046, 0.4, 12), paper, at + Vector3(x, 0.2, z))
		_add(root, _cyl(0.04, 0.046, 0.012, 12), cap, at + Vector3(x, 0.406, z))
	for y in [0.1, 0.3]:
		_add(root, _box(Vector3(0.3, 0.045, 0.2)), tape, at + Vector3(0.0, y, 0.0))
	if fuse:
		var pts := []
		for k in 9:
			var u := k / 8.0
			pts.append(at + Vector3(0.02 + 0.05 * sin(u * 7.0), 0.41 + 0.09 * u, 0.04 * cos(u * 7.0)))
		_fuse_line(root, pts)


static func _tnt(root: Node3D) -> void:
	var wood := _mat(Color(0.66, 0.48, 0.28), "wood")
	var dark := _mat(Color(0.4, 0.27, 0.15), "wood")
	_add(root, _box(Vector3(0.8, 0.5, 0.6)), wood, Vector3(0.0, 0.25, 0.0))
	for y in [0.03, 0.47]:   # rails round the top and bottom
		_add(root, _box(Vector3(0.82, 0.06, 0.62)), dark, Vector3(0.0, y, 0.0))
	for x in [-0.38, 0.38]:
		for z in [-0.28, 0.28]:
			_add(root, _box(Vector3(0.06, 0.5, 0.06)), dark, Vector3(x, 0.25, z))
	# black-and-yellow warning band and the stencilled TNT on the front and sides
	_add(root, _box(Vector3(0.805, 0.08, 0.605)), _mat(Color(0.95, 0.75, 0.1), "", 0.6), Vector3(0.0, 0.12, 0.0))
	for side in [[Vector3(0.0, 0.3, 0.302), 0.0], [Vector3(0.0, 0.3, -0.302), PI], [Vector3(0.402, 0.3, 0.0), PI * 0.5], [Vector3(-0.402, 0.3, 0.0), -PI * 0.5]]:
		var lbl := Label3D.new()
		lbl.text = "TNT"
		lbl.font_size = 96
		lbl.pixel_size = 0.0022
		lbl.modulate = Color(0.62, 0.06, 0.04)
		lbl.outline_size = 0
		lbl.double_sided = false
		lbl.shaded = true
		lbl.position = side[0]
		lbl.rotation.y = side[1]
		root.add_child(lbl)
	# sticks poking out of the open top, one with the fuse
	_dynamite(root, Vector3(0.0, 0.2, 0.0), false)
	var pts := []
	for k in 9:
		var u := k / 8.0
		pts.append(Vector3(0.12 + 0.12 * u, 0.6 + 0.05 * sin(u * 6.0), 0.05 * cos(u * 6.0)))
	_fuse_line(root, pts)


static func _keg(root: Node3D) -> void:
	var wood := _mat(Color(0.28, 0.2, 0.14), "wood")
	var iron := _mat(Color(0.2, 0.2, 0.22), "metal")
	_add(root, _cyl(0.33, 0.33, 0.8, 20), wood, Vector3(0.0, 0.4, 0.0))
	_add(root, _cyl(0.36, 0.33, 0.25, 20), wood, Vector3(0.0, 0.52, 0.0))   # the belly
	_add(root, _cyl(0.33, 0.36, 0.25, 20), wood, Vector3(0.0, 0.28, 0.0))
	for y in [0.06, 0.4, 0.74]:
		_add(root, _cyl(0.355 if y == 0.4 else 0.34, 0.355 if y == 0.4 else 0.34, 0.05, 20), iron, Vector3(0.0, y, 0.0))
	_add(root, _cyl(0.32, 0.32, 0.01, 20), _mat(Color(0.18, 0.13, 0.09), "wood"), Vector3(0.0, 0.805, 0.0))
	# black powder spilling from the bung
	_add(root, _ball(0.09, 10), _mat(Color(0.08, 0.08, 0.08), "ground"), Vector3(0.08, 0.79, 0.05)).scale = Vector3(1.0, 0.3, 1.0)
	var lbl := Label3D.new()
	lbl.text = "XXX"
	lbl.font_size = 80
	lbl.pixel_size = 0.0022
	lbl.modulate = Color(0.95, 0.9, 0.75)
	lbl.double_sided = false
	lbl.shaded = true
	lbl.position = Vector3(0.0, 0.52, 0.365)
	root.add_child(lbl)
	var pts := []
	for k in 9:
		var u := k / 8.0
		pts.append(Vector3(0.08 + 0.08 * u, 0.81 + 0.14 * u - 0.05 * u * u, 0.05 + 0.04 * sin(u * 5.0)))
	_fuse_line(root, pts)


# ---------- rocking chair ----------

# The chair rocks about the centre of its rockers' arc (ROCK_R above the floor), so it rolls on them.
const ROCK_R := 1.3


static func _rocking_chair(root: Node3D) -> void:
	var rocker := Node3D.new()
	rocker.name = "Rocker"
	rocker.position.y = ROCK_R
	root.add_child(rocker)
	var chair := Node3D.new()
	chair.position.y = -ROCK_R
	rocker.add_child(chair)
	var wood := _mat(Color(0.55, 0.33, 0.18), "wood")
	var dark := _mat(Color(0.4, 0.23, 0.12), "wood")
	var cushion := _mat(Color(0.62, 0.16, 0.14), "cloth")
	# the rockers: arcs made of short pieces
	for x in [-0.28, 0.28]:
		for k in 10:
			var a := lerpf(-0.36, 0.36, (k + 0.5) / 10.0)
			var p := Vector3(x, ROCK_R - cos(a) * ROCK_R + 0.03, sin(a) * ROCK_R)
			_add(chair, _box(Vector3(0.05, 0.05, ROCK_R * 0.075)), dark, p, Vector3(-a, 0.0, 0.0))
	# legs, seat, arms, back
	for x in [-0.27, 0.27]:
		for z in [-0.25, 0.25]:
			_add(chair, _cyl(0.025, 0.025, 0.42, 8), wood, Vector3(x, 0.27, z))
	_add(chair, _box(Vector3(0.62, 0.05, 0.58)), wood, Vector3(0.0, 0.48, 0.0))
	_add(chair, _box(Vector3(0.54, 0.06, 0.5)), cushion, Vector3(0.0, 0.535, 0.02))
	for x in [-0.31, 0.31]:
		_add(chair, _box(Vector3(0.06, 0.04, 0.55)), wood, Vector3(x, 0.74, 0.04))
		_add(chair, _cyl(0.02, 0.02, 0.26, 8), wood, Vector3(x, 0.61, 0.24))
	var back := Node3D.new()
	back.position = Vector3(0.0, 0.5, -0.27)
	back.rotation.x = -0.2
	chair.add_child(back)
	for x in [-0.28, 0.28]:
		_add(back, _cyl(0.028, 0.028, 0.6, 8), wood, Vector3(x, 0.3, 0.0))
	for k in 5:
		_add(back, _cyl(0.014, 0.014, 0.46, 6), wood, Vector3(-0.18 + k * 0.09, 0.3, 0.0))
	_add(back, _box(Vector3(0.66, 0.08, 0.05)), dark, Vector3(0.0, 0.62, 0.0))
	_add(back, _box(Vector3(0.56, 0.04, 0.04)), dark, Vector3(0.0, 0.07, 0.0))


# ---------- the armed weapon rack ----------

static func _weapon_rack(root: Node3D) -> void:
	var rack := Models.instance("medieval/weaponrack")
	root.add_child(rack)
	var steel := _mat(Color(0.72, 0.74, 0.78), "metal")
	var dark_steel := _mat(Color(0.35, 0.36, 0.4), "metal")
	var wood := _mat(Color(0.45, 0.28, 0.15), "wood")
	var grip := _mat(Color(0.25, 0.14, 0.08), "leather")
	var gold := _mat(Color(0.85, 0.65, 0.25), "metal")
	# leaning back against the rack's top bar
	var lean := Vector3(-0.14, 0.0, 0.0)
	_sword(root, Vector3(-0.42, 0.0, 0.2), lean, steel, grip, gold)
	_axe(root, Vector3(-0.16, 0.0, 0.2), lean, dark_steel, wood)
	_spear(root, Vector3(0.1, 0.0, 0.2), lean, steel, wood)
	_mace(root, Vector3(0.32, 0.0, 0.2), lean, dark_steel, wood)
	_sword(root, Vector3(0.5, 0.0, 0.2), lean + Vector3(0.0, 0.0, 0.05), steel, grip, dark_steel)


static func _held(root: Node3D, at: Vector3, rot: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = at
	n.rotation = rot
	n.scale = Vector3.ONE * 1.2
	root.add_child(n)
	return n


# A blade: a flat, double-edged prism tapering to a point (diamond cross-section).
static func _blade_mesh(length: float, width: float, thick: float) -> ArrayMesh:
	var key := "blade%f%f" % [length, width]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := func(y: float, w: float) -> Array:
		return [Vector3(-w, y, 0.0), Vector3(0.0, y, thick), Vector3(w, y, 0.0), Vector3(0.0, y, -thick)]
	var base: Array = ring.call(0.0, width * 0.5)
	var mid: Array = ring.call(length * 0.82, width * 0.42)
	var tip := Vector3(0.0, length, 0.0)
	for i in 4:
		var j := (i + 1) % 4
		for tri in [[base[i], mid[i], mid[j]], [base[i], mid[j], base[j]], [mid[i], tip, mid[j]]]:
			var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
			for v in tri:
				st.set_normal(n)
				st.add_vertex(v)
	var m := st.commit()
	_cache[key] = m
	return m


static func _sword(root: Node3D, at: Vector3, rot: Vector3, steel: Material, grip: Material, trim: Material) -> void:
	var s := _held(root, at, rot)
	_add(s, _ball(0.035, 8), trim, Vector3(0.0, 0.03, 0.0))
	_add(s, _cyl(0.022, 0.022, 0.22, 8), grip, Vector3(0.0, 0.15, 0.0))
	_add(s, _box(Vector3(0.24, 0.035, 0.05)), trim, Vector3(0.0, 0.27, 0.0))
	_add(s, _blade_mesh(0.95, 0.075, 0.012), steel, Vector3(0.0, 0.28, 0.0))


static func _axe(root: Node3D, at: Vector3, rot: Vector3, steel: Material, wood: Material) -> void:
	var s := _held(root, at, rot)
	_add(s, _cyl(0.025, 0.03, 1.15, 8), wood, Vector3(0.0, 0.575, 0.0))
	# the head: a wide wedge with a curved edge (a fan of thin slices)
	for k in 7:
		var a := lerpf(-0.6, 0.6, k / 6.0)
		_add(s, _box(Vector3(0.2, 0.045, 0.02)), steel, Vector3(0.1 + 0.04 * cos(a), 1.02 + 0.13 * sin(a), 0.0), Vector3(0.0, 0.0, a * 0.5))
	_add(s, _box(Vector3(0.08, 0.14, 0.05)), steel, Vector3(0.0, 1.02, 0.0))
	_add(s, _box(Vector3(0.09, 0.06, 0.03)), steel, Vector3(-0.07, 1.02, 0.0))


static func _spear(root: Node3D, at: Vector3, rot: Vector3, steel: Material, wood: Material) -> void:
	var s := _held(root, at, rot)
	_add(s, _cyl(0.02, 0.024, 1.45, 8), wood, Vector3(0.0, 0.725, 0.0))
	_add(s, _cyl(0.026, 0.026, 0.06, 8), steel, Vector3(0.0, 1.45, 0.0))
	_add(s, _blade_mesh(0.26, 0.07, 0.014), steel, Vector3(0.0, 1.47, 0.0))


static func _mace(root: Node3D, at: Vector3, rot: Vector3, steel: Material, wood: Material) -> void:
	var s := _held(root, at, rot)
	_add(s, _cyl(0.022, 0.026, 0.8, 8), wood, Vector3(0.0, 0.4, 0.0))
	_add(s, _ball(0.08, 12), steel, Vector3(0.0, 0.86, 0.0))
	for k in 8:
		var d := Vector3(cos(k * TAU / 8.0), (0.5 if k % 2 == 0 else -0.5), sin(k * TAU / 8.0)).normalized()
		var spike := _add(s, _cyl(0.0, 0.025, 0.07, 6), steel, Vector3(0.0, 0.86, 0.0) + d * 0.09)
		_align_y(spike, d)
