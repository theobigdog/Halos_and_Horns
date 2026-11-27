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

instance uniform float seed : instance_index(0) = 0.0;
instance uniform int look : instance_index(1) = 0;
instance uniform float own_cracks : instance_index(2) = 0.0;   // 1: the structure's own shader draws them (StructureLook)
instance uniform vec4 tint : source_color, instance_index(3) = vec4(1.0);   // Creative's Colour (Ted's wife, Nov 27)
global uniform float grime_amount;
varying vec3 lp;
varying float win;   // 1 on a city building's window glass (marked in the mesh: _mark_windows)

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
	win = CUSTOM0.x;
}

void fragment() {
	vec3 p = lp * 2.2 + vec3(seed * 13.7, seed * 7.3, seed * 3.1);
	float blotch = smoothstep(0.35, 0.8, fbm(p * 0.8));                    // big soft stains
	float mottle = fbm(p * 3.5);                                          // fine unevenness everywhere
	float spots = smoothstep(0.8, 0.92, noise3(p * 6.0)) * 0.7;          // a few soft specks
	float crack_zone = smoothstep(0.56, 0.76, fbm(p * 0.35 + 40.0));       // cracks only in the odd patch
	// (Ted, Nov 26: "looks a lot more like shading than cracks"): jagged (the cell edges wander), and each
	// crack thins out and stops somewhere instead of outlining every cell
	vec3 wp3 = p * 1.8 + vec3(fbm(p * 2.5), fbm(p * 2.5 + 7.0), fbm(p * 2.5 + 13.0)) * 0.6;
	float live = smoothstep(0.42, 0.6, fbm(p * 0.9 + 21.0));
	float crack = (1.0 - smoothstep(0.004 + 0.012 * live, 0.012 + 0.02 * live, cell_edge(wp3))) * crack_zone * live;
	// Never on windows or doors (Ted, Nov 26, again: they still ran across the glass): no cracks at all on
	// window glass, and city buildings draw theirs on their plain wall faces only (StructureLook).
	float wall_cracks = step(0.4, fract(sin(seed * 91.37) * 4375.85));
	crack *= wall_cracks * (1.0 - step(0.5, win)) * (1.0 - own_cracks);
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
	ALBEDO = col * tint.rgb;
}
"""
static var _grime: ShaderMaterial
static var _grime_count := 0


static func grime_material() -> ShaderMaterial:
	if _grime == null:
		RenderingServer.global_shader_parameter_add("grime_amount", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0 if grime_on else 0.0)
		RenderingServer.global_shader_parameter_add("snow_cover", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
		var sh := Shader.new()
		sh.code = GRIME_SHADER
		_grime = ShaderMaterial.new()
		_grime.shader = sh
	return _grime


# Snow lying on the tops of things (trees, lamp posts, cars, roofs): a second pass over every model
# while it's snowing, whitening upward-facing surfaces more as snow_cover grows (graphics.gd).
const SNOW_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;
global uniform float snow_cover;
varying float up;
varying vec3 wp;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float n = n2(wp.xz * 2.5) * 0.6 + n2(wp.xz * 9.0) * 0.4;
	float lying = smoothstep(0.35, 0.75, up + (n - 0.5) * 0.35 - (1.0 - snow_cover) * 0.4);
	ALBEDO = vec3(0.93, 0.95, 1.0);
	ROUGHNESS = 0.85;
	ALPHA = lying * clamp(snow_cover * 1.4, 0.0, 1.0);
}
"""
static var _snow_pass: ShaderMaterial
static var festive := false       # snowy maps: Christmas lights on trees and buildings (set by graphics.gd)


static func set_snow(cover: float) -> void:
	var g := grime_material()
	RenderingServer.global_shader_parameter_set("snow_cover", cover)
	if cover > 0.0 and g.next_pass == null:
		if _snow_pass == null:
			var sh := Shader.new()
			sh.code = SNOW_SHADER
			_snow_pass = ShaderMaterial.new()
			_snow_pass.shader = sh
			_snow_pass.render_priority = 2   # (always after the grime: their order used to flip as you moved)
		g.next_pass = _snow_pass
	elif cover <= 0.0 and g.next_pass != null:
		g.next_pass = null


# Graphics quality: grime on Medium and High, off on Low.
static func set_grime(on: bool) -> void:
	grime_material()
	RenderingServer.global_shader_parameter_set("grime_amount", 1.0 if on else 0.0)
	grime_on = on


static var grime_on := true


const LOOK_NAMES := ["Weathered", "Clean", "Mossy", "Charred", "Aged", "Shadowy", "Icy", "Bloodstained"]


# City buildings: a copy of the mesh with each window pane marked (CUSTOM0), so the grime shader can crack
# windows and walls separately. Panes are the faces set back behind the wall and facing out.
static var _marked := {}


static func _mark_windows(id: String, holder: Node3D) -> void:
	if not id.begins_with("city/building"):
		return
	if not _cores.has(id + "@" + str(Vector3.ONE)):
		var f := PackedVector3Array()
		var bare := _raw(id)   # (not faces(): that builds an instance, which would come back here)
		_collect(bare, Transform3D.IDENTITY, f)
		bare.free()
		_cores[id + "@" + str(Vector3.ONE)] = _measure_core(f)
	var core: AABB = _cores[id + "@" + str(Vector3.ONE)]
	if core.size == Vector3.ZERO:
		return
	for c in holder.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		if not mi.mesh is ArrayMesh:
			continue
		var key := "%s:%s" % [id, mi.name]
		if not _marked.has(key):
			_marked[key] = _marked_mesh(mi.mesh, holder.global_transform.affine_inverse() * mi.global_transform
					if mi.is_inside_tree() else _to_holder(mi, holder), core)
		mi.mesh = _marked[key]


static func _to_holder(n: Node, holder: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while n != null and n != holder:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _marked_mesh(src: ArrayMesh, xf: Transform3D, core: AABB) -> ArrayMesh:
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var arrays := src.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx = arrays[Mesh.ARRAY_INDEX]
		var mark := PackedByteArray()
		mark.resize(verts.size() * 4)
		mark.fill(0)
		var tris: int = (idx.size() if idx != null else verts.size()) / 3
		for t in tris:
			var ia: int = idx[t * 3] if idx != null else t * 3
			var ib: int = idx[t * 3 + 1] if idx != null else t * 3 + 1
			var ic: int = idx[t * 3 + 2] if idx != null else t * 3 + 2
			var a := xf * verts[ia]
			var b := xf * verts[ib]
			var cc := xf * verts[ic]
			var nrm := (b - a).cross(cc - a)
			if nrm.length() < 0.000001:
				continue
			nrm = nrm.normalized()
			var mid := (a + b + cc) / 3.0
			if absf(nrm.y) > 0.3 or mid.y < 0.3 or mid.y > core.end.y:
				continue
			var ax := 0 if absf(nrm.x) > absf(nrm.z) else 2
			var wall: float = core.end[ax] if nrm[ax] > 0.0 else core.position[ax]   # (the wall it faces out of)
			var depth := absf(wall - mid[ax])
			var inside: bool = mid[ax] < core.end[ax] - 0.02 and mid[ax] > core.position[ax] + 0.02
			if inside and depth > 0.04 and depth < 0.7 and absf(nrm[ax]) > 0.9:
				for v in [ia, ib, ic]:
					mark[v * 4] = 255
		arrays[Mesh.ARRAY_CUSTOM0] = mark
		var fmt := (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
		out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(si))
	return out


# Christmas lights when it snows (Wife's notes, Nov 21): a spiral of coloured bulbs and a gold star on
# trees, a drooping string of bulbs along the front and back of city buildings. Twinkling in a shader.
const BULB_SHADER := """
shader_type spatial;
render_mode unshaded;
varying vec3 bulb;
varying float tw;
void vertex() {
	bulb = COLOR.rgb;   // (the multimesh's per-bulb colour)
	tw = 0.65 + 0.35 * sin(TIME * 2.2 + float(INSTANCE_ID) * 1.7);
}
void fragment() {
	ALBEDO = bulb * (1.2 + tw * 1.6);
}
"""
static var _bulb_mesh: SphereMesh
static var _bulb_mat: ShaderMaterial
const BULB_COLORS := [Color(1.0, 0.15, 0.1), Color(0.1, 0.9, 0.25), Color(1.0, 0.8, 0.15), Color(0.2, 0.45, 1.0)]


static func _bulbs(points: Array, holder: Node3D) -> void:
	if points.is_empty():
		return
	if _bulb_mesh == null:
		_bulb_mesh = SphereMesh.new()
		_bulb_mesh.radius = 0.08
		_bulb_mesh.height = 0.16
		_bulb_mesh.radial_segments = 6
		_bulb_mesh.rings = 3
		var sh := Shader.new()
		sh.code = BULB_SHADER
		_bulb_mat = ShaderMaterial.new()
		_bulb_mat.shader = sh
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _bulb_mesh
	mm.instance_count = points.size()
	for i in points.size():
		mm.set_instance_transform(i, Transform3D(Basis(), points[i]))
		mm.set_instance_color(i, BULB_COLORS[i % BULB_COLORS.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _bulb_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mmi)


static func _add_festive(id: String, holder: Node3D, extra_scale: Vector3) -> void:
	var name := id.get_slice("/", 1)
	var s := size(id) * extra_scale
	var pts := []
	if (name.begins_with("tree") or name.contains("_tree")) and s.y > 1.0:   # (not "streetlight")
		# a spiral round the tree, narrowing toward the top
		var turns := 4.0
		var count := int(clampf(s.y * 14.0, 20.0, 90.0))
		var r := minf(s.x, s.z) * 0.42
		for i in count:
			var k := float(i) / count
			var a := k * turns * TAU
			var y := lerpf(s.y * 0.18, s.y * 0.9, k)
			var rr := r * (1.0 - (y / s.y)) * 1.15 + 0.08
			pts.append(Vector3(cos(a) * rr, y, sin(a) * rr))
		_bulbs(pts, holder)
		var star := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.14
		sm.height = 0.28
		sm.radial_segments = 5
		sm.rings = 2
		star.mesh = sm
		var gold := StandardMaterial3D.new()
		gold.albedo_color = Color(1.0, 0.85, 0.3)
		gold.emission_enabled = true
		gold.emission = Color(1.0, 0.8, 0.3)
		gold.emission_energy_multiplier = 2.5
		star.material_override = gold
		star.position.y = s.y + 0.08
		holder.add_child(star)
	elif id.begins_with("city/building"):
		var core: AABB = _cores.get(id + "@" + str(Vector3.ONE), AABB())
		if core.size == Vector3.ZERO:
			return
		for zside in [core.end.z + 0.12, core.position.z - 0.12]:
			var x := core.position.x
			while x <= core.end.x:
				var k := fposmod(x - core.position.x, 1.2) / 1.2
				pts.append(Vector3(x, core.end.y - 0.15 - sin(k * PI) * 0.25, zside) * extra_scale)
				x += 0.4
		_bulbs(pts, holder)


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


# Any structure in a chosen colour (Ted's wife, Nov 27: "give all structure blocks the ability to change their
# look and/or color"): the grime overlay multiplies it in, per piece, so the shared materials stay shared. Rugs
# keep their own recolour (recolor(), the pattern turned to the hue). White leaves it as it comes.
static func tint(node: Node, color: Color, look := 0) -> void:
	for c in node.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = c
		if gi.material_overlay == null:
			gi.material_overlay = grime_material()   # (Low graphics has no grime: this still tints)
			gi.set_instance_shader_parameter("look", maxi(look, 1))
		gi.set_instance_shader_parameter("tint", color)


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
	if is_ground(id):
		return "Ground"
	return entry(id).get("cat", "")


# Floors, roads, paths and dirt (Creative's "Ground" list, with ice).
static func is_ground(id: String) -> bool:
	var name := id.get_slice("/", 1)
	if name == "bed_floor" or not is_structure(id):
		return false
	return name.begins_with("road_") or name.begins_with("floor_") or name.begins_with("path_") or name.begins_with("sidewalk")


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
	if Refined.has(id):   # (rebuilt in code with real detail: refined_models.gd, Ted's wife's Nov 27 list)
		var built := Refined.build(id)
		built.scale = extra_scale
		holder.add_child(built)
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


# Turns a model's yellow/orange leaves green (the green pines), leaving brown bark alone.
const GREEN_SHADER := """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * clamp(p - 1.0, 0.0, 1.0);
}
void fragment() {
	vec3 c = texture(tex, UV).rgb * tint.rgb;
	vec3 h = rgb2hsv(c);
	// leaves: yellow to orange and fairly bright/saturated; bark is darker brown
	float leaf = smoothstep(0.03, 0.07, h.x) * (1.0 - smoothstep(0.2, 0.26, h.x)) * smoothstep(0.35, 0.5, h.y) * smoothstep(0.3, 0.45, h.z);
	vec3 g = hsv2rgb(vec3(0.3 + (h.x - 0.12) * 0.3, min(h.y * 0.95, 0.85), h.z * 0.62));
	ALBEDO = mix(c, g, leaf);
	ROUGHNESS = 0.9;
}
"""
static var _green_shader: Shader


static func _make_green(model: Node3D) -> void:
	if _green_shader == null:
		_green_shader = Shader.new()
		_green_shader.code = GREEN_SHADER
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		for si in m.mesh.get_surface_count():
			var src = m.get_active_material(si)
			if src is StandardMaterial3D:
				var sm := ShaderMaterial.new()
				sm.shader = _green_shader
				sm.set_shader_parameter("tex", src.albedo_texture)
				sm.set_shader_parameter("tint", src.albedo_color)
				m.set_surface_override_material(si, sm)


static func instance(id: String, extra_scale := Vector3.ONE, look := 0) -> Node3D:
	var e := entry(id)
	var holder := _raw(id, extra_scale)
	if holder.get_child_count() == 0:
		return holder
	var model: Node3D = holder.get_child(0)
	_mark_windows(id, holder)
	_add_grime(model, look)
	if festive:
		_add_festive(id, holder, extra_scale)
	_add_glow(id, holder)
	if e.get("extra", "") == "crosswalk_end":
		_add_crosswalk(id, holder, size(id) * extra_scale, extra_scale)
	# finer materials (nature_look.gd / structure_look.gd; Nov 24)
	if Refined.has(id):
		pass   # (its own materials)
	elif NatureLook.is_nature(id):
		NatureLook.apply(id, model, e.get("extra", ""))
	else:
		StructureLook.apply(id, model)
		if e.get("extra", "") == "green":
			_make_green(model)
	if id == "city/trafficlight_C":
		_drop_blank_sign(id, holder, extra_scale)
	if id.begins_with("city/trafficlight"):
		var heads := lamp_spots(id)
		if not heads.is_empty():
			var sig: Node3D = TrafficSignal.new()
			for h in heads:
				sig.heads.append([h[0] * extra_scale, h[1] * extra_scale, h[2]])
			sig.lamp_radius = h_radius(heads) * extra_scale.x
			holder.add_child(sig)
		holder.add_child(_street_signs(id, extra_scale))
	return holder


# Two green street-name signs crossed on a traffic light's pole (Wife's notes, Nov 21).
const STREETS := ["Angel Avenue", "Devil Drive"]
# How high they sit (Sara, Nov 25: they were hidden behind the walk signal box): above the lights on the short
# poles (on a little pole extension), and above the walk signal on the long-armed one.
const SIGN_HEIGHT := {"city/trafficlight_A": 3.42, "city/trafficlight_B": 3.42, "city/trafficlight_C": 2.95}
static var _no_sign := {}


# The long-armed traffic light's own street sign is blank (Sara, Nov 25: "remove the blank green sign"):
# drop its green triangles out by the pole (the lamps are far off on the arm).
static func _drop_blank_sign(id: String, holder: Node3D, extra_scale: Vector3) -> void:
	for c in holder.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		if not mi.mesh is ArrayMesh:
			continue
		var key := "%s:%s" % [id, mi.name]
		if not _no_sign.has(key):
			var xf := _to_holder(mi, holder)
			xf = Transform3D(Basis.from_scale(Vector3.ONE / extra_scale), Vector3.ZERO) * xf
			_no_sign[key] = _without_sign(mi.mesh, xf)
		mi.mesh = _no_sign[key]


static func _without_sign(src: ArrayMesh, xf: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var arrays := src.surface_get_arrays(si)
		var mat := src.surface_get_material(si)
		var smat := mat as StandardMaterial3D
		var img: Image = _image_of(smat.albedo_texture) if smat != null and smat.albedo_texture != null else null
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var idx = arrays[Mesh.ARRAY_INDEX]
		var tris: int = (idx.size() if idx != null else verts.size()) / 3
		var keep := PackedInt32Array()
		for t in tris:
			var abc := [idx[t * 3] if idx != null else t * 3, idx[t * 3 + 1] if idx != null else t * 3 + 1,
					idx[t * 3 + 2] if idx != null else t * 3 + 2]
			var drop := false
			if img != null:
				var centre: Vector3 = xf * ((verts[abc[0]] + verts[abc[1]] + verts[abc[2]]) / 3.0)
				if centre.x > 1.3 and centre.y > 2.3 and centre.y < 2.8:
					var uv := (uvs[abc[0]] + uvs[abc[1]] + uvs[abc[2]]) / 3.0
					var col := img.get_pixelv(Vector2i(clampi(int(fposmod(uv.x, 1.0) * img.get_width()), 0, img.get_width() - 1),
							clampi(int(fposmod(uv.y, 1.0) * img.get_height()), 0, img.get_height() - 1)))
					drop = col.g > 0.3 and col.g > col.r * 1.3 and col.g > col.b * 1.1
			if not drop:
				keep.append_array(PackedInt32Array(abc))
		arrays[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(si, mat)
	return out


static func _street_signs(id: String, extra_scale: Vector3) -> Node3D:
	# the pole: the middle of everything near the ground
	var f := PackedVector3Array()
	var bare := _raw(id)
	_collect(bare, Transform3D.IDENTITY, f)
	bare.free()
	var sum := Vector3.ZERO
	var n := 0
	for v in f:
		if v.y < 0.6:
			sum += v
			n += 1
	var pole := sum / maxi(n, 1)
	var root := Node3D.new()
	root.name = "StreetSigns"
	root.set_meta("extra", true)   # (not part of the model's own shape: tests measure without it)
	var at_y: float = SIGN_HEIGHT.get(id, 1.95)
	root.position = Vector3(pole.x, at_y, pole.z) * extra_scale
	if id == "city/trafficlight_A":   # (its pole stops at the lights: a short extension carries the signs)
		var ext := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.04
		cm.bottom_radius = 0.045
		cm.height = 0.75
		cm.radial_segments = 10
		ext.mesh = cm
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.5, 0.45, 0.5)
		pm.metallic = 0.4
		pm.roughness = 0.45
		ext.material_override = pm
		ext.position = Vector3(0, 0.05, 0)
		root.add_child(ext)
		var cap := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radial_segments = 10   # (Godot's default is 64 x 32: ~4000 triangles each; Nov 26 audit)
		sm.rings = 5
		sm.radius = 0.055
		sm.height = 0.07
		cap.mesh = sm
		cap.material_override = pm
		cap.position = Vector3(0, 0.43, 0)
		root.add_child(cap)
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.05, 0.42, 0.2)
	green.roughness = 0.5
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color(0.92, 0.92, 0.9)
	for k in 2:
		var arm := Node3D.new()
		arm.position.y = 0.2 * k
		arm.rotation.y = PI / 2 * k
		root.add_child(arm)
		var off := Vector3(0.47 * (1.0 if k == 0 else -1.0), 0, 0)   # (hanging off the pole, so it doesn't hide the name)
		var plate := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.95, 0.19, 0.025)
		plate.mesh = b
		plate.material_override = green
		plate.position = off
		arm.add_child(plate)
		var rim := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(0.97, 0.21, 0.02)
		rim.mesh = rb
		rim.material_override = edge
		rim.position = off
		arm.add_child(rim)
		for side in [1.0, -1.0]:
			var t := Label3D.new()
			t.text = STREETS[k]
			t.font_size = 40
			t.pixel_size = 0.0031
			t.outline_size = 0
			t.modulate = Color(1, 1, 1)
			t.double_sided = false
			t.position = off + Vector3(0, 0, 0.0135 * side)
			t.rotation.y = 0.0 if side > 0.0 else PI
			arm.add_child(t)
	return root


# ---- traffic lights: where the painted lamps are ----
# Found from the model itself: triangles whose spot on the texture is red or green, grouped into
# small patches (big green patches are street signs). Each red lamp pairs with the nearest green.
const TrafficSignal = preload("res://scripts/traffic_signal.gd")
const Lamp = preload("res://scripts/lamp.gd")
const Refined = preload("res://scripts/refined_models.gd")
const NatureLook = preload("res://scripts/nature_look.gd")
const StructureLook = preload("res://scripts/structure_look.gd")
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
static var _road_top := {}


# Painted right on the road (Sara, Nov 25: they floated at the height of the curbs): flat quads a hair above
# the asphalt, found by looking straight down onto the model's own road surface.
static func _add_crosswalk(id: String, holder: Node3D, s: Vector3, extra_scale: Vector3) -> void:
	if not _road_top.has(id):
		var f := PackedVector3Array()
		var bare := _raw(id)
		_collect(bare, Transform3D.IDENTITY, f)
		bare.free()
		var z0 := size(id).z * 0.3
		var top := -1.0
		for t in range(0, f.size() - 2, 3):
			var hit = Geometry3D.ray_intersects_triangle(Vector3(0.0, 50.0, z0), Vector3.DOWN, f[t], f[t + 1], f[t + 2])
			if hit != null:
				top = maxf(top, (hit as Vector3).y)
		_road_top[id] = top if top >= 0.0 else size(id).y
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.9, 0.86)
	m.roughness = 0.85
	var stripe := PlaneMesh.new()
	stripe.size = Vector2(s.x * 0.075, s.z * 0.28)
	for i in 6:
		var mi := MeshInstance3D.new()
		mi.mesh = stripe
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3((i - 2.5) * s.x * 0.147, _road_top[id] * extra_scale.y + 0.006, s.z * 0.5 - s.z * 0.2)
		holder.add_child(mi)


# Lit things (torches, candles, lanterns, jack-o'-lanterns, street lights) give off a little light,
# which matters on dusk and night maps.
const LIT := {"torch_lit": Color(1.0, 0.6, 0.25), "candle_lit": Color(1.0, 0.75, 0.4), "candle_thin_lit": Color(1.0, 0.75, 0.4),
		"lantern_standing": Color(1.0, 0.7, 0.35), "lantern_hanging": Color(1.0, 0.7, 0.35), "post_lantern": Color(1.0, 0.7, 0.35),
		"pumpkin_orange_jackolantern": Color(1.0, 0.55, 0.15), "pumpkin_yellow_jackolantern": Color(1.0, 0.7, 0.2),
		"skull_candle": Color(1.0, 0.7, 0.35), "shrine_candles": Color(1.0, 0.75, 0.4), "plaque_candles": Color(1.0, 0.75, 0.4),
		"streetlight": Color(1.0, 0.9, 0.7), "shelf_small_candles": Color(1.0, 0.75, 0.4)}


static func _add_glow(id: String, holder: Node3D) -> void:
	var name := id.get_slice("/", 1).trim_suffix("_flicker")
	var bad_bulb: bool = entry(id).get("extra", "") == "flicker"   # (a street light that flickers: Ted's wife, Nov 27)
	if not LIT.has(name):
		return
	var s := size(id)
	var l := OmniLight3D.new()
	l.light_color = LIT[name]
	l.light_energy = 1.6 if name == "streetlight" else 0.9
	l.omni_range = 9.0 if name == "streetlight" else 4.5
	# street lights and lantern posts have a daylight sensor (on at dusk); candles and torches are just lit
	var lamp := Lamp.new()
	lamp.position.y = s.y * 0.8
	lamp.setup(l, name in ["streetlight", "post_lantern", "lantern_standing"], 2.5 if bad_bulb else 0.0)
	holder.add_child(lamp)


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
		if id.begins_with("city/road"):
			out = _flatten_paint(out)
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


# The road's painted lines stand 2 cm proud of the asphalt (0.33 vs 0.31), enough for a prop or a disguised
# demon to snag on them (playtest, Nov 26). The collision gets them pressed flat into the road; you still
# see them. Their sides become slivers with no area, which are dropped.
const PAINT_LOW := 0.305
const PAINT_HIGH := 0.345
const ROAD_TOP := 0.31


static func _flatten_paint(f: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(0, f.size() - 2, 3):
		var tri := [f[i], f[i + 1], f[i + 2]]
		for k in 3:
			if tri[k].y > PAINT_LOW and tri[k].y < PAINT_HIGH:
				tri[k].y = ROAD_TOP
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]).length() > 0.00001:
			out.append_array(PackedVector3Array(tri))
	return out


static func _collect(node: Node, xf: Transform3D, out: PackedVector3Array) -> void:
	if node is Node3D:
		xf = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh and not node.has_meta("no_collide"):
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
# Rugs can be any colour (Sara, Nov 25): the rug's own pattern, hue-turned to the chosen colour (its light and
# dark parts stay light and dark, so stripes and borders still show).
const RECOLOR_SHADER := """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 base_tint : source_color = vec4(1.0);
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * clamp(p - 1.0, 0.0, 1.0);
}
void fragment() {
	vec3 src = texture(tex, UV).rgb * base_tint.rgb;
	vec3 hs = rgb2hsv(src);
	vec3 want = rgb2hsv(tint.rgb);
	// every part takes the chosen hue; how strongly coloured follows the choice; light/dark follows the rug
	float v = clamp(hs.z * (0.35 + 0.9 * want.z), 0.0, 1.0);
	float s = clamp(mix(hs.y, want.y, 0.75), 0.0, 1.0);
	ALBEDO = hsv2rgb(vec3(want.x, s, v));
	ROUGHNESS = 0.95;
}
"""
static var _recolor_shader: Shader


static func is_rug(id: String) -> bool:
	return id.get_slice("/", 1).begins_with("rug_")


static func recolor(node: Node, color: Color) -> void:
	if _recolor_shader == null:
		_recolor_shader = Shader.new()
		_recolor_shader.code = RECOLOR_SHADER
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var src = m.mesh.surface_get_material(si)
			if src is StandardMaterial3D:
				var sm := ShaderMaterial.new()
				sm.shader = _recolor_shader
				sm.set_shader_parameter("tex", src.albedo_texture)
				sm.set_shader_parameter("base_tint", src.albedo_color)
				sm.set_shader_parameter("tint", color)
				m.set_surface_override_material(si, sm)


# Square floor tiles whose pattern isn't the same every quarter turn (Ted's wife, Nov 27: "you can tell if the
# piece was going the same direction as the neighboring ones or if it was rotated 90 degrees"): each tile is
# turned back by the piece's quarter turns, so its pattern always lines up with the world's. (Square: the
# collision is the same either way.)
const WORLD_ALIGNED := ["dungeon/floor_tile_small", "dungeon/floor_tile_small_broken_A", "dungeon/floor_tile_small_broken_B",
		"dungeon/floor_tile_small_decorated", "dungeon/floor_tile_small_weeds_A", "dungeon/floor_tile_small_weeds_B",
		"dungeon/floor_tile_large", "dungeon/floor_tile_large_rocks"]


static func _align_turn(id: String, extra_scale: Vector3, world_yaw: float) -> float:
	if not id in WORLD_ALIGNED or not is_equal_approx(extra_scale.x, extra_scale.z):
		return 0.0
	return -roundf(world_yaw / (PI * 0.5)) * PI * 0.5


static func make_row(id: String, extra_scale := Vector3.ONE, count := 1, count2 := 1, look := 0, batched := false, world_yaw := 0.0) -> Node3D:
	var turn := _align_turn(id, extra_scale, world_yaw)
	if count <= 1 and count2 <= 1:
		var one := make_structure(id, extra_scale, look)
		if turn != 0.0:
			var holder := Node3D.new()   # (the piece keeps its own turn; only the tile inside turns back)
			one.rotation.y = turn
			holder.add_child(one)
			return holder
		return one
	if batched and count * count2 >= BATCH_FROM:
		var b := _batched_row(id, extra_scale, count, count2, look, turn)
		if b:
			return b
	var row := Node3D.new()
	var step := row_step(id, extra_scale)
	var step2 := row_step2(id, extra_scale)
	for j in maxi(count2, 1):
		for i in maxi(count, 1):
			var b := make_structure(id, extra_scale, look)
			b.position = step * i + step2 * j
			b.rotation.y = turn
			row.add_child(b)
	return row


# A long row (or a whole floor) of the same piece, in a game (Nov 26 performance audit: the Town map's
# floor was 2,362 tiles, each its own object to cull and draw). Each mesh of the piece becomes one
# MultiMesh holding every copy, so the graphics card gets one draw per mesh instead of one per tile.
# The collision is exactly what the separate copies had. Only plain pieces (meshes, no lights, signals
# or anything with a script); stairs and city buildings keep their extra ramps and cores the usual way.
const BATCH_FROM := 4
static var _baked := {}


static func _batched_row(id: String, extra_scale: Vector3, count: int, count2: int, look: int, turn := 0.0) -> Node3D:
	if is_rug(id) or is_stairs(id) or id.begins_with("city/building"):
		return null
	var tmpl := instance(id, extra_scale, look)
	var parts := []
	if not _plain_parts(tmpl, tmpl, parts):
		tmpl.free()
		return null
	var body := StaticBody3D.new()
	var step := row_step(id, extra_scale)
	var step2 := row_step2(id, extra_scale)
	var offsets := []
	for j in maxi(count2, 1):
		for i in maxi(count, 1):
			offsets.append(step * i + step2 * j)
	for part in parts:
		var mi: MeshInstance3D = part[0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _baked_mesh(mi)
		mm.instance_count = offsets.size()
		for k in offsets.size():
			mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, turn), offsets[k]) * part[1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mi.material_override
		mmi.material_overlay = mi.material_overlay
		mmi.cast_shadow = mi.cast_shadow
		if mi.material_overlay:
			for param in ["seed", "look"]:
				var v = mi.get_instance_shader_parameter(param)
				if v != null:
					mmi.set_instance_shader_parameter(param, v)
		body.add_child(mmi)
	tmpl.free()
	var shape := _shape(id, extra_scale)
	for o in offsets:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = o
		body.add_child(cs)
	return body


# The piece's meshes and where each sits, or false if it has anything else (a light, a script...).
static func _plain_parts(n: Node, holder: Node, out: Array) -> bool:
	if n.get_script() != null or not (n.get_class() == "Node3D" or n.get_class() == "MeshInstance3D"):
		return false
	if not (n as Node3D).visible:
		return true
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append([n, _to_holder(n, holder)])
	for c in n.get_children():
		if not _plain_parts(c, holder, out):
			return false
	return true


# The mesh with any per-surface materials the looks gave it built in (a MultiMesh can't override them).
static func _baked_mesh(mi: MeshInstance3D) -> Mesh:
	var overrides := []
	var any := false
	for si in mi.mesh.get_surface_count():
		var m := mi.get_surface_override_material(si)
		overrides.append(m.get_instance_id() if m else 0)
		any = any or m != null
	if not any:
		return mi.mesh
	var key := "%d:%s" % [mi.mesh.get_instance_id(), overrides]
	if not _baked.has(key) and mi.mesh is ArrayMesh:
		var copy: ArrayMesh = mi.mesh.duplicate(false)
		for si in copy.get_surface_count():
			if mi.get_surface_override_material(si):
				copy.surface_set_material(si, mi.get_surface_override_material(si))
		_baked[key] = copy
	return _baked.get(key, mi.mesh)


static func _shape(id: String, extra_scale: Vector3) -> ConcavePolygonShape3D:
	var key := "%s@%s" % [id, extra_scale]
	if not _shapes.has(key):
		var made := ConcavePolygonShape3D.new()
		made.set_faces(faces(id, extra_scale))
		made.backface_collision = true
		_shapes[key] = made
	return _shapes[key]


# A solid structure: the model plus collision matching its real shape.
static func make_structure(id: String, extra_scale := Vector3.ONE, look := 0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.add_child(instance(id, extra_scale, look))
	var cs := CollisionShape3D.new()
	cs.shape = _shape(id, extra_scale)
	body.add_child(cs)
	if is_stairs(id):
		body.add_child(_stair_ramp(id, extra_scale))
	if id.begins_with("city/building"):
		var core := _building_core(id, extra_scale)
		if core:
			body.add_child(core)
	return body


# City buildings get a solid block inside, flush with their outer walls (Wife's notes, Nov 21: angels got
# wedged in the window recesses, and could slip through a wall into the hollow inside). The walls are
# found by casting rays in at many heights: the distance most of them stop at is the wall's face; window
# recesses (deeper) and sills (further out) are rarer. The block stops just under the lowest roof.
static var _cores := {}


static func _building_core(id: String, extra_scale: Vector3) -> CollisionShape3D:
	var key := "%s@%s" % [id, extra_scale]
	if not _cores.has(key):
		_cores[key] = _measure_core(faces(id, extra_scale))
	var box: AABB = _cores[key]
	if box.size.x < 0.5 or box.size.z < 0.5 or box.size.y < 0.5:
		return null
	var shape := BoxShape3D.new()
	shape.size = box.size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = box.get_center()
	return cs


static func _measure_core(f: PackedVector3Array) -> AABB:
	if f.is_empty():
		return AABB()
	var tm := TriangleMesh.new()
	tm.create_from_faces(f)
	var lo := f[0]
	var hi := f[0]
	for v in f:
		lo = lo.min(v)
		hi = hi.max(v)
	# the lowest roof: the lowest top surface over the middle part of the footprint
	var roof := hi.y
	for i in 5:
		for j in 5:
			var px := lerpf(lo.x, hi.x, 0.2 + 0.15 * i)
			var pz := lerpf(lo.z, hi.z, 0.2 + 0.15 * j)
			var h := _height_at(f, Vector2(px, pz))
			if h > 1.0:   # (skip gaps with nothing over them)
				roof = minf(roof, h)
	var top := roof - 0.05
	var wall := {}
	for side in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var counts := {}
		var across := Vector3(absf(side.z), 0, absf(side.x))   # the axis along this wall
		for hy in 12:
			var y := lerpf(0.4, top - 0.3, hy / 11.0)
			for k in 9:
				var t := 0.15 + 0.7 * k / 8.0
				var from := Vector3(lerpf(lo.x, hi.x, t), y, lerpf(lo.z, hi.z, t)) * across
				from += side * (absf((hi * side).x + (hi * side).z) + absf((lo * side).x + (lo * side).z) + 2.0) + Vector3(0, y, 0)
				var hit: Dictionary = tm.intersect_ray(from, -side)
				if hit.is_empty():
					continue
				var d := snappedf((hit["position"] as Vector3).dot(side), 0.02)
				counts[d] = int(counts.get(d, 0)) + 1
		var best := 0.0
		var best_n := -1
		for d in counts:
			if counts[d] > best_n:
				best_n = counts[d]
				best = d
		if best_n < 6:
			return AABB()
		wall[side] = best
	var a := Vector3(-wall[Vector3.LEFT], 0.0, -wall[Vector3.FORWARD])
	var b := Vector3(wall[Vector3.RIGHT], top, wall[Vector3.BACK])
	return AABB(a, b - a)


# Stairs get an invisible smooth ramp over the steps (Ted, Nov 20), so walking up them is a glide, not a
# climb over every riser. It runs from the bottom step's edge to the top step.
static func _stair_ramp(id: String, extra_scale: Vector3) -> CollisionShape3D:
	var step := stair_step(id) * extra_scale
	var s := size(id) * extra_scale
	var along := Vector3(step.x, 0, step.z)
	var run := along.length()
	var d := along / maxf(run, 0.001)
	var side := Vector3(-d.z, 0, d.x) * (absf(s.x * d.z) + absf(s.z * d.x)) * 0.5 * 0.9
	var low := -d * run * 0.5
	var high := d * run * 0.5
	var top := Vector3.UP * (step.y + 0.03)
	# The ramp follows the front edges of the steps (so none of them pokes through and snags you):
	# it meets the ground a step's depth in front of the stairs, rises along the step edges, and runs
	# flat across the top step.
	var first: float = _height_at(faces(id, extra_scale), Vector2(low.x + d.x * 0.05, low.z + d.z * 0.05))
	var lead_len := first * run / maxf(step.y, 0.01)
	var foot := low - d * (lead_len + 0.05)
	var knee := high - d * lead_len
	var pts := PackedVector3Array([foot + side, foot - side, high + side, high - side,
			knee + side + top, knee - side + top, high + side + top, high - side + top])
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	return cs
