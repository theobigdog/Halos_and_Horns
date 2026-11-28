# Curbs (Sara, Nov 27: "add curbs - straight and 90 degree curves"). Map pieces of type "building" (kinds
# "curb" and "curb_corner"), placed, turned, resized and coloured in Creative like the signs. Solid: you can
# step up onto it.
# Since Nov 28 it IS the kerb the road pieces have built in (Sara: "make the curb match the built in curbs on
# the various street pieces"), measured off city/road_straight: 0.45 m wide and 0.45 m tall, flat on top for
# 0.315 m, then sloping down 0.14 m to the road's surface (0.31 m up) and straight down from there; the same
# smooth blue-grey concrete, the top a shade lighter than the faces, crisp edges. Set against the end or side
# of a road piece it carries the road's own kerb on. (It was a 0.25 x 0.18 m rounded, rough white stone.) The
# sloped side is +z for the straight one and the outside of the curve for the corner. Beside a thin asphalt or
# parking block, make it lower with T.
extends RefCounted

const Surfaces = preload("res://scripts/surfaces.gd")

const KINDS := {"curb": "Curb (straight)", "curb_corner": "Curb (90° corner)"}
const W := 0.45
const H := 0.45
const SLOPE := 0.135     # how far the sloped face runs across
const ROAD := 0.31       # the road's surface: where the slope comes down to
const LENGTH := 2.0
const RADIUS := 1.5      # the corner's middle radius

static var _cache := {}


static func size(kind: String) -> Vector3:
	if kind == "curb_corner":
		return Vector3(RADIUS + W * 0.5, H, RADIUS + W * 0.5)
	return Vector3(LENGTH, H, W)


static func make(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Curb"
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(kind)
	if not _cache.has("mat"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.9   # (smooth cast concrete, like the road's: no stone texture)
		_cache["mat"] = m
	mi.material_override = _cache["mat"]
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var path := _path(kind)
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(a.distance_to(b) + 0.02, H, W)
		cs.shape = box
		cs.transform = Transform3D(Basis(Vector3.UP, -atan2(b.z - a.z, b.x - a.x)), (a + b) * 0.5 + Vector3.UP * H * 0.5)
		body.add_child(cs)
	root.add_child(body)
	return root


# The curb's centre line: straight along x, or a quarter circle (from +x round to +z), centred on its footprint.
static func _path(kind: String) -> Array:
	var out := []
	if kind == "curb_corner":
		var n := 12
		var off := Vector3(-(RADIUS + W * 0.5) * 0.5, 0, -(RADIUS + W * 0.5) * 0.5)
		for k in n + 1:
			var a := PI * 0.5 * k / n
			out.append(Vector3(cos(a) * RADIUS, 0, sin(a) * RADIUS) + off)
		return out
	return [Vector3(-LENGTH * 0.5, 0, 0), Vector3(LENGTH * 0.5, 0, 0)]


static func _mesh(kind: String) -> ArrayMesh:
	if _cache.has(kind):
		return _cache[kind]
	var path := _path(kind)
	# the cross-section (across, up), across = + toward the road side: a chamfered top edge
	var prof := [Vector2(-W * 0.5, 0.0), Vector2(-W * 0.5, H), Vector2(W * 0.5 - SLOPE, H), Vector2(W * 0.5, ROAD), Vector2(W * 0.5, 0.0)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := Color("7d878c")    # the road kerb's top; its faces are 70797e
	var along := 0.0
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var seg := a.distance_to(b)
		var dir := (b - a).normalized()
		var across := Vector3(-dir.z, 0, dir.x) * (-1.0 if kind == "curb_corner" else 1.0)
		if kind != "curb_corner":
			across = Vector3(0, 0, 1)
		for k in prof.size() - 1:
			var p0: Vector2 = prof[k]
			var p1: Vector2 = prof[k + 1]
			var q := [a + across * p0.x + Vector3.UP * p0.y, b + across * p0.x + Vector3.UP * p0.y,
					b + across * p1.x + Vector3.UP * p1.y, a + across * p1.x + Vector3.UP * p1.y]
			var mid2 := (p0 + p1) * 0.5
			var out := across * mid2.x + Vector3.UP * (mid2.y - H * 0.5)
			var tone := base if k == 1 else Color("70797e")
			_quad(st, q, tone, out.normalized())
		along += seg
	# ends, and the joints every metre (dark lines across the top and face)
	for e in [[path[0], path[1], -1.0], [path[path.size() - 1], path[path.size() - 2], 1.0]]:
		var p: Vector3 = e[0]
		var dir: Vector3 = ((e[0] as Vector3) - (e[1] as Vector3)).normalized()
		var across := Vector3(-dir.z, 0, dir.x)
		var pts := []
		for v in prof:
			pts.append(p + across * (v as Vector2).x * (1.0 if kind == "curb_corner" else 1.0) + Vector3.UP * (v as Vector2).y)
		var c := Vector3.ZERO
		for v in pts:
			c += v
		c /= pts.size()
		for k in pts.size():
			_tri(st, c, pts[k], pts[(k + 1) % pts.size()], Color("70797e"), dir)
	st.generate_normals()   # (not indexed: flat faces and crisp edges, like the road's kerb)
	_cache[kind] = st.commit()
	return _cache[kind]


static func _quad(st: SurfaceTool, q: Array, col: Color, out: Vector3) -> void:
	_tri(st, q[0], q[1], q[2], col, out)
	_tri(st, q[0], q[2], q[3], col, out)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, out: Vector3) -> void:
	if (b - a).cross(c - a).dot(out) > 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_color(col)
		st.add_vertex(v)
