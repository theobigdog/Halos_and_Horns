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


# Grime (Ted, Nov 19: the free models look too clean and low-detail): drawn over every model, darkening
# it with soft blotches, little spots and patches of hairline cracks. Worked out from the model's own
# shape, so it sticks to a prop that gets knocked about, and a per-copy seed so no two look the same.
# Turned off on Low graphics (it's an extra pass for every model).
const GRIME_SHADER := """
shader_type spatial;
render_mode blend_mul, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

instance uniform float seed = 0.0;
global uniform float grime_amount;
varying vec3 lp;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}
// distance to the nearest edge between random cells: thin lines where it's small (the cracks)
float cell_edge(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int z = -1; z <= 1; z++)
	for (int y = -1; y <= 1; y++)
	for (int x = -1; x <= 1; x++) {
		vec3 g = vec3(float(x), float(y), float(z));
		vec3 o = vec3(hash3(i + g), hash3(i + g + 19.1), hash3(i + g + 47.7));
		float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
	}
	return d2 - d1;
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 p = lp * 2.2 + vec3(seed * 13.7, seed * 7.3, seed * 3.1);
	float blotch = smoothstep(0.35, 0.8, fbm(p * 0.8));                    // big soft stains
	float mottle = fbm(p * 3.5);                                          // fine unevenness everywhere
	float spots = smoothstep(0.8, 0.92, noise3(p * 6.0)) * 0.7;          // a few soft specks
	float crack_zone = smoothstep(0.56, 0.76, fbm(p * 0.35 + 40.0));       // cracks only in the odd patch
	float crack = (1.0 - smoothstep(0.008, 0.03, cell_edge(p * 1.8))) * crack_zone;
	vec3 dirt = vec3(0.62, 0.55, 0.47);                                   // brownish grime, not just grey
	vec3 col = mix(vec3(1.0), dirt, clamp(blotch * 0.55 + (mottle - 0.5) * 0.35, 0.0, 1.0));
	col *= 1.0 - spots * 0.3;
	col *= 1.0 - crack * 0.5;
	ALBEDO = mix(vec3(1.0), col, grime_amount);
}
"""
static var _grime: ShaderMaterial
static var _grime_count := 0


static func grime_material() -> ShaderMaterial:
	if _grime == null:
		RenderingServer.global_shader_parameter_add("grime_amount", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0 if grime_on else 0.0)
		var sh := Shader.new()
		sh.code = GRIME_SHADER
		_grime = ShaderMaterial.new()
		_grime.shader = sh
	return _grime


# Graphics quality: grime on Medium and High, off on Low.
static func set_grime(on: bool) -> void:
	grime_material()
	RenderingServer.global_shader_parameter_set("grime_amount", 1.0 if on else 0.0)
	grime_on = on


static var grime_on := true


static func _add_grime(node: Node) -> void:
	if not grime_on:
		return
	var mat := grime_material()
	_grime_count += 1
	var s := fmod(float(_grime_count) * 0.618034, 1.0) * 10.0
	for c in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		mi.material_overlay = mat
		mi.set_instance_shader_parameter("seed", s)


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
	_add_grime(model)
	_add_glow(id, holder)
	return holder


# Lit things (torches, candles, lanterns, jack-o'-lanterns, street lights) give off a little light,
# which matters on dusk and night maps.
const LIT := {"torch_lit": Color(1.0, 0.6, 0.25), "candle_lit": Color(1.0, 0.75, 0.4), "candle_thin_lit": Color(1.0, 0.75, 0.4),
		"lantern_standing": Color(1.0, 0.7, 0.35), "lantern_hanging": Color(1.0, 0.7, 0.35), "post_lantern": Color(1.0, 0.7, 0.35),
		"pumpkin_orange_jackolantern": Color(1.0, 0.55, 0.15), "pumpkin_yellow_jackolantern": Color(1.0, 0.7, 0.2),
		"skull_candle": Color(1.0, 0.7, 0.35), "shrine_candles": Color(1.0, 0.75, 0.4), "plaque_candles": Color(1.0, 0.75, 0.4),
		"streetlight": Color(1.0, 0.9, 0.7), "shelf_small_candles": Color(1.0, 0.75, 0.4)}


static func _add_glow(id: String, holder: Node3D) -> void:
	var name := id.get_slice("/", 1)
	if not LIT.has(name):
		return
	var s := size(id)
	var l := OmniLight3D.new()
	l.light_color = LIT[name]
	l.light_energy = 1.6 if name == "streetlight" else 0.9
	l.omni_range = 9.0 if name == "streetlight" else 4.5
	l.position.y = s.y * 0.8
	holder.add_child(l)


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


# How far apart repeated copies of a structure sit (a wall extended by dragging): its own length,
# along whichever way it's longer.
static func row_step(id: String, extra_scale := Vector3.ONE) -> Vector3:
	var s := size(id) * extra_scale
	return Vector3(s.x, 0, 0) if s.x >= s.z else Vector3(0, 0, s.z)


# The other way across (for flat things like floors, which can be pulled out into a grid).
static func row_step2(id: String, extra_scale := Vector3.ONE) -> Vector3:
	var s := size(id) * extra_scale
	return Vector3(0, 0, s.z) if s.x >= s.z else Vector3(s.x, 0, 0)


# Flat pieces (floors, rugs, roads, paths) can be repeated both ways; walls and fences just in a row.
static func is_flat(id: String) -> bool:
	var s := size(id)
	return s.y <= 0.35 * minf(s.x, s.z)


# A structure repeated end to end (count), and for floors also side by side (count2): each copy
# exactly like the first, posts, columns and all.
static func make_row(id: String, extra_scale := Vector3.ONE, count := 1, count2 := 1) -> Node3D:
	if count <= 1 and count2 <= 1:
		return make_structure(id, extra_scale)
	var row := Node3D.new()
	var step := row_step(id, extra_scale)
	var step2 := row_step2(id, extra_scale)
	for j in maxi(count2, 1):
		for i in maxi(count, 1):
			var b := make_structure(id, extra_scale)
			b.position = step * i + step2 * j
			row.add_child(b)
	return row


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
