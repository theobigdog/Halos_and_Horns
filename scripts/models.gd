# The model catalog: every KayKit model we ship (CC0, by Kay Lousberg; see assets/kaykit/LICENSE-*.txt).
# assets/kaykit/catalog.json is made by tools/build_catalog.py and says, for each model, whether it's a
# PROP (demons can possess it; prop_library.gd adds these to its list) or a STRUCTURE (solid scenery
# placed in Creative mode), which category it's shown under, and how it's scaled and centred.
extends RefCounted

const CATALOG := "res://assets/kaykit/catalog.json"

static var _all := {}          # id -> entry
static var _order := []        # ids in catalog order
static var _scenes := {}       # path -> PackedScene (loaded on first use)
static var _faces := {}        # id -> PackedVector3Array (collision for structures, scale 1)
static var _shapes := {}       # "id@scale" -> shared collision shape


static func _load() -> void:
	if not _order.is_empty():
		return
	var f := FileAccess.open(CATALOG, FileAccess.READ)
	if f == null:
		push_error("model catalog missing: " + CATALOG)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_ARRAY:
		return
	for e in parsed:
		_all[e["id"]] = e
		_order.append(e["id"])


static func has(id: String) -> bool:
	_load()
	return _all.has(id)


static func entry(id: String) -> Dictionary:
	_load()
	return _all.get(id, {})


static func ids(kind := "") -> Array:
	_load()
	if kind == "":
		return _order.duplicate()
	return _order.filter(func(i): return _all[i]["kind"] == kind)


static func is_structure(id: String) -> bool:
	return entry(id).get("kind", "") == "structure"


static func label(id: String) -> String:
	return entry(id).get("label", id)


static func category(id: String) -> String:
	return entry(id).get("cat", "")


# Its size in metres at scale 1 (already converted to our world).
static func size(id: String) -> Vector3:
	var s: Array = entry(id).get("size", [1, 1, 1])
	return Vector3(s[0], s[1], s[2])


# The model, scaled to our world and stood with its bottom-centre on (0, 0, 0).
static func instance(id: String, extra_scale := Vector3.ONE) -> Node3D:
	var e := entry(id)
	var holder := Node3D.new()
	if e.is_empty():
		return holder
	var scene := _scene(e["path"])
	if scene == null:
		return holder
	var model: Node3D = scene.instantiate()
	var s: float = e["scale"]
	var o: Array = e["offset"]
	model.scale = Vector3.ONE * s * extra_scale
	model.position = Vector3(o[0], o[1], o[2]) * extra_scale
	holder.add_child(model)
	return holder


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene
	return _scenes[path]


# The model's real shape as triangles (so doorways, arches and stairs work), for a structure's collision.
# Scaled by extra_scale and placed like instance().
static func faces(id: String, extra_scale := Vector3.ONE) -> PackedVector3Array:
	if not _faces.has(id):
		var out := PackedVector3Array()
		var node := instance(id)
		_collect(node, Transform3D.IDENTITY, out)
		node.free()
		_faces[id] = out
	if extra_scale == Vector3.ONE:
		return _faces[id]
	var scaled := PackedVector3Array()
	scaled.resize(_faces[id].size())
	var i := 0
	for v in _faces[id]:
		scaled[i] = v * extra_scale
		i += 1
	return scaled


static func _collect(node: Node, xf: Transform3D, out: PackedVector3Array) -> void:
	if node is Node3D:
		xf = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		for v in (node as MeshInstance3D).mesh.get_faces():
			out.append(xf * v)
	for c in node.get_children():
		_collect(c, xf, out)


# A solid structure: the model plus collision matching its real shape.
static func make_structure(id: String, extra_scale := Vector3.ONE) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.add_child(instance(id, extra_scale))
	var key := "%s@%s" % [id, extra_scale]
	if not _shapes.has(key):
		var made := ConcavePolygonShape3D.new()
		made.set_faces(faces(id, extra_scale))
		made.backface_collision = true
		_shapes[key] = made
	var shape: ConcavePolygonShape3D = _shapes[key]
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	return body
