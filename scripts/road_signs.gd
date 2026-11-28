# Road signs (Ted, Nov 27: "stop signs, speed limit signs, yield signs, etc, as structures"). Built in code like
# the trees and gates: map pieces of type "building" with these kinds, placed, turned and resized in Creative.
# Each is a galvanised steel post (a square tube with its row of holes) set in a little concrete footing,
# with an aluminium plate bolted on: the coloured face, a white or black border inset on it, the lettering
# (Label3D, lit like everything else), and a bare metal back. The speed limit sign's look is the speed.
# Solid: the post and the plate, so you can hide behind one (a skinny demon, anyway).
extends RefCounted

const Surfaces = preload("res://scripts/surfaces.gd")

const KINDS := {
	"sign_stop": "Stop sign",
	"sign_yield": "Yield sign",
	"sign_speed": "Speed limit sign",
	"sign_noentry": "Do Not Enter sign",
	"sign_oneway": "One Way sign",
	"sign_noparking": "No Parking sign",
	"sign_crossing": "Pedestrian crossing sign",
	"sign_deadend": "Dead End sign",
	"sign_railroad": "Railroad crossing sign",
	"sign_demons": "Demon crossing sign",
}
const SPEEDS := [10, 15, 20, 25, 35, 45, 55, 65]
const POST_H := 2.1         # the plate's bottom edge sits about this high

const RED := Color(0.72, 0.05, 0.06)
const WHITE := Color(0.95, 0.95, 0.93)
const YELLOW := Color(0.98, 0.78, 0.08)
const BLACK := Color(0.05, 0.05, 0.05)

static var _mats := {}
static var _st: SurfaceTool   # every flat piece of the sign being built goes into this one mesh


static func looks(kind: String) -> Array:
	if kind == "sign_speed":
		return SPEEDS.map(func(s): return "%d mph" % s)
	return ["Clean", "Faded", "Rusty", "Stickered"]


static func size(kind: String) -> Vector3:
	var w := 1.0 if kind == "sign_railroad" else 0.8
	return Vector3(w, POST_H + (1.3 if kind == "sign_railroad" else 0.95), 0.3)


static func make(kind: String, look: int) -> Node3D:
	look = clampi(look, 0, 7)
	var root := Node3D.new()
	root.name = "Sign"
	var wear := 0 if kind == "sign_speed" else look % 4
	var plate := Node3D.new()
	plate.name = "Plate"
	plate.position = Vector3(0, POST_H, 0.045)
	root.add_child(plate)
	_post(root, kind, wear)
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := 0.0   # the plate's top, above POST_H
	match kind:
		"sign_stop":
			top = _shape_plate(plate, _ngon(8, 0.38, PI / 8.0), RED, WHITE, wear, 0.38)
			_text(plate, "STOP", Vector3(0, 0.38, 0), 0.23, WHITE)   # (Sara, Nov 28: larger)
		"sign_yield":
			var tri := [Vector2(-0.45, 0.78), Vector2(0.45, 0.78), Vector2(0, 0.0)]
			top = _shape_plate(plate, tri, WHITE, RED, wear, 0.0, 0.12)
			_text(plate, "YIELD", Vector3(0, 0.55, 0), 0.085, RED)
		"sign_speed":
			top = _rect_plate(plate, 0.6, 0.76, WHITE, BLACK, wear)
			_text(plate, "SPEED", Vector3(0, 0.6, 0), 0.1, BLACK)
			_text(plate, "LIMIT", Vector3(0, 0.48, 0), 0.1, BLACK)
			_text(plate, str(SPEEDS[look]), Vector3(0, 0.24, 0), 0.26, BLACK)
		"sign_noentry":
			top = _shape_plate(plate, _ngon(32, 0.37, 0.0), RED, WHITE, wear, 0.37)
			_flat(plate, _rect(0.5, 0.11, Vector2(0, 0.37)), WHITE, 0.012)
			_text(plate, "DO NOT", Vector3(0, 0.55, 0), 0.08, WHITE)
			_text(plate, "ENTER", Vector3(0, 0.2, 0), 0.08, WHITE)
		"sign_oneway":
			top = _rect_plate(plate, 0.9, 0.3, BLACK, WHITE, wear, Vector2(0, 0.15))
			plate.position.y += 0.35
			_flat(plate, _arrow(0.78, 0.17, Vector2(0, 0.15)), WHITE, 0.012)
			_text(plate, "ONE WAY", Vector3(-0.06, 0.15, 0), 0.075, BLACK)
			top += 0.35
		"sign_noparking":
			top = _rect_plate(plate, 0.46, 0.6, WHITE, RED, wear)
			_text(plate, "P", Vector3(0, 0.3, 0), 0.28, BLACK)
			_flat(plate, _ring(0.18, 0.025, Vector2(0, 0.3)), RED, 0.016)
			_flat(plate, _rect(0.38, 0.045, Vector2(0, 0.3), -PI / 4.0), RED, 0.018)
		"sign_crossing", "sign_demons", "sign_deadend":
			var diamond := _ngon(4, 0.42, 0.0)
			top = _shape_plate(plate, diamond, YELLOW, BLACK, wear, 0.42)
			if kind == "sign_deadend":
				_text(plate, "DEAD", Vector3(0, 0.5, 0), 0.09, BLACK)
				_text(plate, "END", Vector3(0, 0.34, 0), 0.09, BLACK)
			elif kind == "sign_crossing":
				_walker(plate, Vector2(0, 0.42), false)
			else:
				_walker(plate, Vector2(0, 0.42), true)
		"sign_railroad":
			for a in [PI / 4.0, -PI / 4.0]:
				var board := _rect(1.2, 0.2, Vector2(0, 0.6), a)
				_flat(plate, board, WHITE, 0.0 if a > 0.0 else 0.022, BLACK, 0.025)
			# (RAIL and ROAD either side of where the boards cross, as on the real thing)
			for part in [["RAIL", -0.32], ["ROAD", 0.32]]:
				var along := Vector2(cos(PI / 4.0), sin(PI / 4.0)) * float(part[1])
				var t1 := _text(plate, part[0], Vector3(along.x, 0.6 + along.y, 0), 0.075, BLACK)
				t1.rotation.z = PI / 4.0
				t1.position.z = 0.03
			var t2 := _text(plate, "CROSSING", Vector3(0, 0.6, 0), 0.07, BLACK)
			t2.rotation.z = -PI / 4.0
			t2.position.z = 0.052
			top = 1.03
	var face := MeshInstance3D.new()
	face.name = "Face"
	face.mesh = _st.commit()
	face.material_override = _face_mat(wear)
	plate.add_child(face)
	_st = null
	# solid: the post, and the plate
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var post := CollisionShape3D.new()
	var pb := BoxShape3D.new()
	pb.size = Vector3(0.06, POST_H + top, 0.06)
	post.shape = pb
	post.position.y = (POST_H + top) * 0.5
	body.add_child(post)
	var ps := CollisionShape3D.new()
	var pbox := BoxShape3D.new()
	pbox.size = Vector3(0.75 if kind != "sign_oneway" else 0.9, maxf(top - (0.35 if kind == "sign_oneway" else 0.0), 0.2), 0.04)
	ps.shape = pbox
	ps.position = Vector3(0, POST_H + (0.35 if kind == "sign_oneway" else 0.0) + pbox.size.y * 0.5, 0.045)
	body.add_child(ps)
	root.add_child(body)
	return root


# ---------------------------------------------------------------- the post

static func _post(root: Node3D, kind: String, wear: int) -> void:
	var key := "post_%d" % wear
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.62, 0.64, 0.64).lerp(Color(0.45, 0.3, 0.2), 0.45 if wear == 2 else 0.0)
		m.metallic = 0.75
		m.roughness = 0.45 if wear != 2 else 0.8
		Surfaces.apply(m, "metal")
		_mats[key] = m
		var c := StandardMaterial3D.new()
		c.albedo_color = Color(0.62, 0.61, 0.58)
		c.roughness = 0.95
		Surfaces.apply(c, "stone")
		_mats["concrete"] = c
	var h := POST_H + (1.25 if kind == "sign_railroad" else 0.85)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.055, h, 0.055)
	mi.mesh = bm
	mi.material_override = _mats[key]
	mi.position.y = h * 0.5
	root.add_child(mi)
	# its row of holes up the front (dark dots), and the footing
	var holes := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dot := QuadMesh.new()
	dot.size = Vector2(0.011, 0.011)
	mm.mesh = dot
	var n := int((h - 0.4) / 0.0508)
	mm.instance_count = n
	for i in n:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, 0.3 + i * 0.0508, 0.0282)))
	holes.multimesh = mm
	holes.material_override = _flat_mat(Color(0.08, 0.08, 0.08))
	root.add_child(holes)
	var foot := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.13
	cm.bottom_radius = 0.16
	cm.height = 0.12
	cm.radial_segments = 12
	foot.mesh = cm
	foot.material_override = _mats["concrete"]
	foot.position.y = 0.04
	root.add_child(foot)


# ---------------------------------------------------------------- plates

# A flat-shaped plate: its back (bare metal), the face colour, and a border inset `rim` in from the edge
# (a wide-angle triangle like Yield gets a wider one). Returns the plate's height above its bottom.
static func _shape_plate(plate: Node3D, outline: Array, face: Color, border: Color, wear: int, lift: float, rim := 0.035) -> float:
	var pts: Array = outline.map(func(p): return p + Vector2(0, lift))
	_flat(plate, pts, border, 0.0, _metal_back(wear), 0.006)
	_flat(plate, _inset(pts, rim), face, 0.009)
	var top := 0.0
	for p in pts:
		top = maxf(top, p.y)
	_bolts(plate, Vector2(0, lift - 0.0), top)
	return top


static func _rect_plate(plate: Node3D, w: float, h: float, face: Color, border: Color, wear: int, centre := Vector2.ZERO) -> float:
	var c := centre if centre != Vector2.ZERO else Vector2(0, h * 0.5)
	var outer := _rect(w, h, c)
	_flat(plate, outer, face, 0.0, _metal_back(wear), 0.006)
	# a thin border line just inside the edge
	_flat(plate, _ring_rect(w - 0.05, h - 0.05, 0.016, c), border, 0.011)
	_bolts(plate, Vector2(0, c.y - h * 0.5), c.y + h * 0.5)
	return c.y + h * 0.5


static func _bolts(plate: Node3D, bottom: Vector2, top: float) -> void:
	for y in [bottom.y + (top - bottom.y) * 0.2, bottom.y + (top - bottom.y) * 0.8]:
		var b := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.014
		cm.height = 0.01
		cm.radial_segments = 8
		cm.rings = 1
		b.mesh = cm
		b.material_override = _flat_mat(Color(0.7, 0.7, 0.7), 0.6)
		b.rotation.x = PI / 2.0
		b.position = Vector3(0, y, 0.02)
		plate.add_child(b)


static func _metal_back(wear: int) -> Color:
	return Color(0.66, 0.67, 0.68) if wear != 2 else Color(0.5, 0.38, 0.28)


# A flat polygon facing +z at depth `z`; with a `back` colour it gets a back face (and edge) too, `thick` deep.
# A list of polygons does each. Everything goes into the sign's one mesh (_st).
static func _flat(parent: Node3D, pts: Array, col: Color, z: float, back := Color(0, 0, 0, 0), thick := 0.0) -> void:
	if not pts.is_empty() and pts[0] is Array:
		for q in pts:
			_flat(parent, q, col, z, back, thick)
		return
	var st := _st
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var n := pts.size()
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		st.set_normal(Vector3.BACK)
		st.set_color(col)
		for v in [c, b, a] if _ccw(pts) else [c, a, b]:
			st.set_uv(v)
			st.add_vertex(Vector3(v.x, v.y, z + thick))
	if back.a > 0.0:
		for i in n:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % n]
			st.set_normal(Vector3.FORWARD)
			st.set_color(back)
			for v in [c, a, b] if _ccw(pts) else [c, b, a]:
				st.set_uv(v)
				st.add_vertex(Vector3(v.x, v.y, z))
			# the edge
			var out := Vector3(b.y - a.y, a.x - b.x, 0).normalized() * (1.0 if _ccw(pts) else -1.0)
			st.set_normal(out)
			var q := [Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(b.x, b.y, z + thick), Vector3(a.x, a.y, z + thick)]
			for k in ([0, 2, 1, 0, 3, 2] if _ccw(pts) else [0, 1, 2, 0, 2, 3]):
				st.set_uv(Vector2(q[k].x, q[k].y))
				st.add_vertex(q[k])


static func _ccw(pts: Array) -> bool:
	var s := 0.0
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		s += a.x * b.y - b.x * a.y
	return s > 0.0


# Reflective sign paint (vertex colour); worn ones get faded, rusty or covered in stickers by the shader.
const FACE_SHADER := """
shader_type spatial;
uniform int wear = 0;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));   // (the colours are given in sRGB)
	float rough = 0.35;
	float metal = 0.0;
	if (wear == 1) {           // faded by the sun: paler, chalky
		c = mix(c, vec3(dot(c, vec3(0.33))) * 1.2 + 0.05, 0.35 + 0.2 * n2(UV * 6.0));
		rough = 0.7;
	} else if (wear == 2) {    // rust blooming from the edges and the bolt holes
		float r = smoothstep(0.55, 0.75, n2(UV * 9.0) * 0.7 + n2(UV * 31.0) * 0.4);
		c = mix(c, vec3(0.12, 0.035, 0.01) * (0.7 + 0.5 * n2(UV * 50.0)), r);
		rough = mix(0.45, 0.95, r);
	} else if (wear == 3) {    // a few stickers slapped on
		vec2 cell = floor(UV * 5.0 + vec2(0.3, 0.7));
		float k = h(cell);
		vec2 f = fract(UV * 5.0 + vec2(0.3, 0.7)) - 0.5;
		float st = step(0.82, k) * step(max(abs(f.x), abs(f.y) * 1.6), 0.3);
		vec3 sc = mix(vec3(0.02, 0.2, 0.8), vec3(0.9, 0.8, 0.04), step(0.91, k));
		c = mix(c, sc, st);
	}
	c *= 0.92 + 0.08 * n2(UV * 80.0);
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.6;
}
"""


static func _face_mat(wear: int) -> Material:
	var key := "face_%d" % wear
	if not _mats.has(key):
		if not _mats.has("face_shader"):
			var sh := Shader.new()
			sh.code = FACE_SHADER
			_mats["face_shader"] = sh
		var m := ShaderMaterial.new()
		m.shader = _mats["face_shader"]
		m.set_shader_parameter("wear", wear)
		_mats[key] = m
	return _mats[key]


static func _flat_mat(c: Color, rough := 0.8) -> StandardMaterial3D:
	var key := "flat_%s_%s" % [c.to_html(), rough]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		_mats[key] = m
	return _mats[key]


static func _text(plate: Node3D, s: String, at: Vector3, height: float, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = s
	l.font_size = 96
	l.outline_size = 10
	l.outline_modulate = col
	l.modulate = col
	l.pixel_size = height / 96.0 * 1.15
	l.shaded = true
	l.double_sided = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.position = at + Vector3(0, 0, 0.0185)
	plate.add_child(l)
	return l


# ---------------------------------------------------------------- outlines

static func _ngon(n: int, r: float, turn: float) -> Array:
	var out := []
	for i in n:
		var a := turn + TAU * i / n
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


static func _rect(w: float, h: float, c: Vector2, turn := 0.0) -> Array:
	var out := []
	for p in [Vector2(-w, -h), Vector2(w, -h), Vector2(w, h), Vector2(-w, h)]:
		out.append(c + (p * 0.5).rotated(turn))
	return out


# Each point moved `d` toward the middle (fine for these convex shapes).
static func _inset(pts: Array, d: float) -> Array:
	var n := pts.size()
	var out := []
	for i in n:
		var p: Vector2 = pts[i]
		var a: Vector2 = (pts[(i - 1 + n) % n] - p).normalized()
		var b: Vector2 = (pts[(i + 1) % n] - p).normalized()
		var bis := (a + b).normalized()
		var s := sin(a.angle_to(b) * 0.5)
		out.append(p + bis * d / maxf(absf(s), 0.1))
	return out


# A ring (strip of quads) as one polygon list won't do: make it as a fan of thin quads, drawn by _flat calls.
static func _ring(r: float, w: float, c: Vector2) -> Array:
	# (approximated by a 24-sided polygon outline with a hole: returned as a list of quads' points, see _flat_many)
	var out := []
	for i in 24:
		var a0 := TAU * i / 24.0
		var a1 := TAU * (i + 1) / 24.0
		out.append([c + Vector2(cos(a0), sin(a0)) * (r + w * 0.5), c + Vector2(cos(a1), sin(a1)) * (r + w * 0.5),
				c + Vector2(cos(a1), sin(a1)) * (r - w * 0.5), c + Vector2(cos(a0), sin(a0)) * (r - w * 0.5)])
	return out


static func _ring_rect(w: float, h: float, t: float, c: Vector2) -> Array:
	return [_rect(w, t, c + Vector2(0, (h - t) * 0.5)), _rect(w, t, c - Vector2(0, (h - t) * 0.5)),
			_rect(t, h - t * 2.0, c + Vector2((w - t) * 0.5, 0)), _rect(t, h - t * 2.0, c - Vector2((w - t) * 0.5, 0))]


static func _arrow(len: float, h: float, c: Vector2) -> Array:
	var head := h * 1.6
	var x0 := c.x - len * 0.5
	var x1 := c.x + len * 0.5
	var xs := x1 - head
	# the shaft, then the head (two convex pieces)
	return [[Vector2(x0, c.y - h * 0.25), Vector2(xs, c.y - h * 0.25), Vector2(xs, c.y + h * 0.25), Vector2(x0, c.y + h * 0.25)],
			[Vector2(xs, c.y - h * 0.5), Vector2(x1, c.y), Vector2(xs, c.y + h * 0.5)]]


# A walking figure (a person, or a little horned demon with a pitchfork-ish tail) in black on the diamond.
static func _walker(plate: Node3D, c: Vector2, demon: bool) -> void:
	var parts := []
	parts.append(_ngon(10, 0.045, 0.0).map(func(p): return p + c + Vector2(0.02, 0.17)))          # head
	parts.append(_rect(0.07, 0.17, c + Vector2(0.0, 0.05), -0.15))                                 # body
	parts.append(_rect(0.04, 0.16, c + Vector2(-0.045, -0.1), 0.45))                               # back leg
	parts.append(_rect(0.04, 0.16, c + Vector2(0.05, -0.1), -0.4))                                  # front leg
	parts.append(_rect(0.035, 0.13, c + Vector2(-0.06, 0.07), -0.7))                               # arm back
	parts.append(_rect(0.035, 0.13, c + Vector2(0.06, 0.06), 0.8))                                  # arm forward
	if demon:
		parts.append([c + Vector2(-0.01, 0.2), c + Vector2(-0.05, 0.27), c + Vector2(-0.025, 0.2)])  # horns
		parts.append([c + Vector2(0.045, 0.2), c + Vector2(0.075, 0.27), c + Vector2(0.06, 0.19)])
		parts.append(_rect(0.025, 0.16, c + Vector2(-0.1, -0.02), 1.1))                             # tail
		parts.append([c + Vector2(-0.17, -0.08), c + Vector2(-0.13, -0.03), c + Vector2(-0.19, -0.02)])  # tail tip
	for p in parts:
		_flat(plate, p, BLACK, 0.012)
