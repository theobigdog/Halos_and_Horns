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
instance uniform int look = 0;
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
	col = mix(vec3(1.0), col, grime_amount);
	// Looks (Ted, Nov 20: cycle through options for the same piece)
	float up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	if (look == 1) {
		col = vec3(1.0);                                                       // clean
	} else if (look == 2) {
		float moss = smoothstep(0.45, 0.7, fbm(p * 0.6 + 11.0)) * (0.55 + 0.45 * max(up, 0.0));
		col *= mix(vec3(1.0), vec3(0.42, 0.66, 0.28), moss);                   // mossy, thickest on top
	} else if (look == 3) {
		float burnt = smoothstep(0.3, 0.68, fbm(p * 0.7 + 5.0));
		col *= mix(vec3(0.85, 0.8, 0.75), vec3(0.16, 0.13, 0.12), burnt);      // charred
	} else if (look == 4) {
		col *= vec3(0.86, 0.72, 0.55);                                         // aged, sepia
	} else if (look == 5) {
		col *= vec3(0.5, 0.46, 0.58);                                          // shadowy
	} else if (look == 6) {
		col *= mix(vec3(0.78, 0.9, 1.0), vec3(0.95, 0.98, 1.0), max(up, 0.0)); // icy
	} else if (look == 7) {
		float blood = smoothstep(0.66, 0.74, fbm(p * 1.2 + 77.0)) + smoothstep(0.86, 0.9, noise3(p * 9.0)) * 0.6;
		col *= mix(vec3(1.0), vec3(0.5, 0.04, 0.04), clamp(blood, 0.0, 1.0));  // bloodstained
	}
	ALBEDO = col;
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


const LOOK_NAMES := ["Weathered", "Clean", "Mossy", "Charred", "Aged", "Shadowy", "Icy", "Bloodstained"]


static func _add_grime(node: Node, look := 0) -> void:
	if not grime_on and look == 0:
		return   # (Low graphics: no grime; a chosen look still shows)
	var mat := grime_material()
	_grime_count += 1
	var s := fmod(float(_grime_count) * 0.618034, 1.0) * 10.0
	for c in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		mi.material_overlay = mat
		mi.set_instance_shader_parameter("seed", s)
		mi.set_instance_shader_parameter("look", look)


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
# The bare model, scaled to our world and stood with its bottom-centre on (0, 0, 0), nothing added.
static func _raw(id: String, extra_scale := Vector3.ONE) -> Node3D:
	var e := entry(id)
	var holder := Node3D.new()
	if e.is_empty():
		return holder
	var scene := _scene(e["path"])
	if scene == null:
		return holder
	var model: Node3D = scene.instantiate()
	var o: Array = e["offset"]
	model.scale = Vector3.ONE * float(e["scale"]) * extra_scale
	model.position = Vector3(o[0], o[1], o[2]) * extra_scale
	holder.add_child(model)
	return holder


static func instance(id: String, extra_scale := Vector3.ONE, look := 0) -> Node3D:
	var e := entry(id)
	var holder := _raw(id, extra_scale)
	if holder.get_child_count() == 0:
		return holder
	var model: Node3D = holder.get_child(0)
	_add_grime(model, look)
	_add_glow(id, holder)
	if e.get("extra", "") == "crosswalk_end":
		_add_crosswalk(holder, size(id) * extra_scale)
	if id.begins_with("city/trafficlight"):
		var heads := lamp_spots(id)
		if not heads.is_empty():
			var sig: Node3D = TrafficSignal.new()
			for h in heads:
				sig.heads.append([h[0] * extra_scale, h[1] * extra_scale, h[2]])
			sig.lamp_radius = h_radius(heads) * extra_scale.x
			holder.add_child(sig)
	return holder


# ---- traffic lights: where the painted lamps are ----
# Found from the model itself: triangles whose spot on the texture is red or green, grouped into
# small patches (big green patches are street signs). Each red lamp pairs with the nearest green.
const TrafficSignal = preload("res://scripts/traffic_signal.gd")
static var _lamp_cache := {}
static var _images := {}


static func lamp_spots(id: String) -> Array:
	if _lamp_cache.has(id):
		return _lamp_cache[id]
	var reds := []
	var greens := []
	var node := _raw(id)
	_scan_lamps(node, Transform3D.IDENTITY, reds, greens)
	node.free()
	var red_spots := _patches(reds)
	var green_spots := _patches(greens)
	var heads := []
	for r in red_spots:
		var best = null
		for g in green_spots:
			if r[0].distance_to(g[0]) < 0.9 and (best == null or r[0].distance_to(g[0]) < r[0].distance_to(best[0])):
				best = g
		if best != null:
			heads.append([r[0], best[0], ((r[1] + best[1]) * 0.5).normalized(), maxf(r[2], best[2])])
	_lamp_cache[id] = heads
	return heads


static func h_radius(heads: Array) -> float:
	var r := 0.0
	for h in heads:
		r = maxf(r, h[3])
	return clampf(r * 0.5, 0.05, 0.14)


static func _scan_lamps(node: Node, xf: Transform3D, reds: Array, greens: Array) -> void:
	if node is Node3D:
		xf = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is ArrayMesh:
		var mesh: ArrayMesh = (node as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			var mat := mesh.surface_get_material(si) as StandardMaterial3D
			if mat == null or mat.albedo_texture == null:
				continue
			var img := _image_of(mat.albedo_texture)
			if img == null:
				continue
			var arrays := mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var idx = arrays[Mesh.ARRAY_INDEX]
			var tri_count: int = (idx.size() if idx != null else verts.size()) / 3
			for t in tri_count:
				var a: int = idx[t * 3] if idx != null else t * 3
				var b: int = idx[t * 3 + 1] if idx != null else t * 3 + 1
				var c: int = idx[t * 3 + 2] if idx != null else t * 3 + 2
				var uv := (uvs[a] + uvs[b] + uvs[c]) / 3.0
				var px := Vector2i(clampi(int(fposmod(uv.x, 1.0) * img.get_width()), 0, img.get_width() - 1),
						clampi(int(fposmod(uv.y, 1.0) * img.get_height()), 0, img.get_height() - 1))
				var col := img.get_pixelv(px)
				var is_red := col.r > 0.6 and col.g < 0.3 and col.b < 0.3
				var is_green := col.g > 0.45 and col.r < 0.35 and col.b < 0.55
				if not (is_red or is_green):
					continue
				var p0: Vector3 = xf * verts[a]
				var p1: Vector3 = xf * verts[b]
				var p2: Vector3 = xf * verts[c]
				var n := (p2 - p0).cross(p1 - p0)   # (Godot's front faces wind clockwise)
				if n.length() < 0.000001:
					continue
				(reds if is_red else greens).append([(p0 + p1 + p2) / 3.0, n.normalized()])
	for ch in node.get_children():
		_scan_lamps(ch, xf, reds, greens)


static func _image_of(tex: Texture2D) -> Image:
	var key := tex.resource_path
	if not _images.has(key):
		var img := tex.get_image()
		if img != null and img.is_compressed():
			img.decompress()
		_images[key] = img
	return _images[key]


# Group points into patches (within 0.2 m of each other); keep the small ones: [centre, facing, size]
static func _patches(pts: Array) -> Array:
	var groups := []
	for p in pts:
		var placed := false
		for g in groups:
			if g[0].distance_to(p[0]) < 0.2:
				g[2].append(p)
				g[0] = (g[0] * (g[2].size() - 1) + p[0]) / g[2].size()
				placed = true
				break
		if not placed:
			groups.append([p[0], p[1], [p]])
	var out := []
	for g in groups:
		var box := AABB(g[2][0][0], Vector3.ZERO)
		var facing := Vector3.ZERO
		for p in g[2]:
			box = box.expand(p[0])
			facing += p[1]
		if box.size.length() < 0.45:
			out.append([g[0], facing.normalized() if facing.length() > 0.01 else Vector3.FORWARD, box.size.length()])
	return out


# ---- car lights (a map option per car) ----
static func is_car(id: String) -> bool:
	return id.begins_with("city/car_")


# Headlights shining ahead (+Z is a car's front) and red tail lights.
static func car_lights(id: String, extra_scale := Vector3.ONE) -> Node3D:
	var s := size(id) * extra_scale
	var n := Node3D.new()
	for side in [-1.0, 1.0]:
		for front in [true, false]:
			var mi := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(s.x * 0.16, s.y * 0.06, 0.03)
			mi.mesh = b
			var m := StandardMaterial3D.new()
			var c := Color(1.0, 0.95, 0.8) if front else Color(1.0, 0.08, 0.05)
			m.albedo_color = c
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 3.0 if front else 2.0
			mi.material_override = m
			mi.position = Vector3(side * s.x * 0.33, s.y * (0.36 if front else 0.45), (s.z * 0.5 + 0.02) * (1.0 if front else -1.0))
			n.add_child(mi)
	var beam := SpotLight3D.new()
	beam.light_color = Color(1.0, 0.95, 0.85)
	beam.light_energy = 4.0
	beam.spot_range = 22.0
	beam.spot_angle = 28.0
	beam.position = Vector3(0, s.y * 0.36, s.z * 0.5 + 0.1)
	beam.rotation = Vector3(-0.12, PI, 0)   # (lights shine along -Z: turned round to face the front)
	n.add_child(beam)
	var tail := OmniLight3D.new()
	tail.light_color = Color(1.0, 0.1, 0.05)
	tail.light_energy = 0.8
	tail.omni_range = 2.5
	tail.position = Vector3(0, s.y * 0.45, -s.z * 0.5 - 0.3)
	n.add_child(tail)
	return n


# A plain road with the crosswalk painted near one end (the city pack only has it in the middle,
# which looks odd at junctions). Turn the piece to put it at the other end.
static func _add_crosswalk(holder: Node3D, s: Vector3) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.93, 0.93, 0.9)
	m.roughness = 0.8
	var stripe := BoxMesh.new()
	stripe.size = Vector3(s.x * 0.075, 0.02, s.z * 0.28)
	for i in 6:
		var mi := MeshInstance3D.new()
		mi.mesh = stripe
		mi.material_override = m
		mi.position = Vector3((i - 2.5) * s.x * 0.147, s.y + 0.005, s.z * 0.5 - s.z * 0.2)
		holder.add_child(mi)


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
# along whichever way it's longer. Stairs instead go up: each copy starts at the top of the last one
# (Ted, Nov 20), so a staircase gets longer rather than doubling up beside itself.
static func row_step(id: String, extra_scale := Vector3.ONE) -> Vector3:
	if is_stairs(id):
		return stair_step(id) * extra_scale
	var s := size(id) * extra_scale
	return Vector3(s.x, 0, 0) if s.x >= s.z else Vector3(0, 0, s.z)


static func is_stairs(id: String) -> bool:
	return id.get_slice("/", 1).begins_with("stairs")


static var _stair_cache := {}


# Which way a staircase climbs and how high: from the model's own shape, the walkable height at each end
# of its middle line. The next flight starts where this one's top step is.
static func stair_step(id: String) -> Vector3:
	if _stair_cache.has(id):
		return _stair_cache[id]
	var s := size(id)
	var f := faces(id)
	var ends := {
		"+z": _height_at(f, Vector2(0, s.z * 0.5 - 0.15)), "-z": _height_at(f, Vector2(0, -s.z * 0.5 + 0.15)),
		"+x": _height_at(f, Vector2(s.x * 0.5 - 0.15, 0)), "-x": _height_at(f, Vector2(-s.x * 0.5 + 0.15, 0)),
	}
	var along_z := absf(ends["+z"] - ends["-z"]) >= absf(ends["+x"] - ends["-x"])
	var step: Vector3
	if along_z:
		var up_pos: bool = ends["+z"] > ends["-z"]
		step = Vector3(0, maxf(ends["+z"], ends["-z"]), s.z * (1.0 if up_pos else -1.0))
	else:
		var up_pos: bool = ends["+x"] > ends["-x"]
		step = Vector3(s.x * (1.0 if up_pos else -1.0), maxf(ends["+x"], ends["-x"]), 0)
	_stair_cache[id] = step
	return step


# The highest surface over a spot (x, z), from a model's triangles.
static func _height_at(f: PackedVector3Array, p: Vector2) -> float:
	var best := 0.0
	for i in range(0, f.size() - 2, 3):
		var a := f[i]
		var b := f[i + 1]
		var c := f[i + 2]
		var v0 := Vector2(b.x - a.x, b.z - a.z)
		var v1 := Vector2(c.x - a.x, c.z - a.z)
		var v2 := Vector2(p.x - a.x, p.y - a.z)
		var den := v0.x * v1.y - v1.x * v0.y
		if absf(den) < 0.000001:
			continue
		var u := (v2.x * v1.y - v1.x * v2.y) / den
		var v := (v0.x * v2.y - v2.x * v0.y) / den
		if u < 0.0 or v < 0.0 or u + v > 1.0:
			continue
		best = maxf(best, a.y + u * (b.y - a.y) + v * (c.y - a.y))
	return best


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
static func make_row(id: String, extra_scale := Vector3.ONE, count := 1, count2 := 1, look := 0) -> Node3D:
	if count <= 1 and count2 <= 1:
		return make_structure(id, extra_scale, look)
	var row := Node3D.new()
	var step := row_step(id, extra_scale)
	var step2 := row_step2(id, extra_scale)
	for j in maxi(count2, 1):
		for i in maxi(count, 1):
			var b := make_structure(id, extra_scale, look)
			b.position = step * i + step2 * j
			row.add_child(b)
	return row


# A solid structure: the model plus collision matching its real shape.
static func make_structure(id: String, extra_scale := Vector3.ONE, look := 0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.add_child(instance(id, extra_scale, look))
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
