# Plays one prop's animation (prop_anims.gd says which). It sits inside the prop's visual, at the holder's
# origin, so everything here is in the prop's own space: x across, y up, +z its front. Pieces that move are
# lifted out of the model's mesh into their own MeshInstances under this node (PropAnims.islands()).
# Visual only, and local: every screen runs its own copy from the presses the host passes along.
extends Node3D

const PropAnims = preload("res://scripts/prop_anims.gd")
const Look = preload("res://scripts/prop_anim_look.gd")
const Sounds = preload("res://scripts/prop_anim_sounds.gd")
const Models = preload("res://scripts/models.gd")
const Surfaces = preload("res://scripts/surfaces.gd")
const Sfx = preload("res://scripts/sfx.gd")

var id := ""
var e := {}
var holder: Node3D
var presses := 0
var _built := false
var _p := {}          # what each kind keeps between presses
var _orig := {}       # source MeshInstance path -> {mesh, mats, gone: {surface: {tri: true}}}
var _tw := {}         # running tweens by name
var _clock := 0.0
var _rng := RandomNumberGenerator.new()
var _drops: MultiMeshInstance3D
var _drop_v := []
var _drop_t := 0.0


func setup(type_id: String, entry: Dictionary, visual: Node3D) -> void:
	id = type_id
	e = entry
	holder = visual
	_rng.seed = hash(id)
	if e["kind"] in ["light", "lamp", "jack"]:
		_build()
		_set_lit(_default_on())


func press(n: int) -> void:
	if not _built:
		_build()
	presses = n
	var odd := n % 2 == 1
	match e["kind"]:
		"light", "jack":
			_set_lit(_default_on() != odd)
			_sound("lighter", -12.0)
		"lamp":
			_set_lit(_default_on() != odd)
			_sound("chain", -12.0)
		"lid": _lid()
		"fridge": _fridge()
		"oven": _oven(odd)
		"bite": _bite()
		"hop": _hop()
		"spill": _spill(odd)
		"disarray": _disarray(odd)
		"dirty": _overlay_parts("dirty", odd)
		"blood": _overlay_parts("blood", odd)
		"squirt": _squirt()
		"scribble": _scribble()
		"unroll": _unroll()
		"burners": _burners()
		"drain": _drain()
		"cork": _cork()
		"bed": _bed(odd)
		"sofabed": _sofabed(odd)
		"recline": _recline(odd)
		"picture": _picture(n)
		"ooze": _ooze()
		"rock": _rock()
		"fuse": _fuse()


func _process(delta: float) -> void:
	_clock += delta
	if _drops != null and _drops.visible:
		_step_drops(delta)


# ---------- building: find and lift the pieces each kind needs ----------

func _build() -> void:
	_built = true
	var isl := [] if id in _hand_built() else PropAnims.islands(id, holder)
	match e["kind"]:
		"light": _build_light(isl)
		"lamp": _build_lamp(isl)
		"jack":
			_p["face"] = holder.find_child("Face", true, false)
			_p["lights"] = [holder.find_child("Candle", true, false)]
		"lid":
			if e.has("node"):
				var lid: MeshInstance3D = holder.find_children("*lid*", "MeshInstance3D", true, false)[0]
				_p["pivot"] = _pivot_for([lid], Models._to_holder(lid, holder).origin)
			else:
				_build_trunk(isl)
		"fridge":
			var doors := []
			for c in holder.find_children("*door*", "MeshInstance3D", true, false):
				doors.append(_pivot_for([c], Models._to_holder(c, holder).origin))
			_p["doors"] = doors
		"oven":
			var door: MeshInstance3D = holder.find_child("oven_door", true, false)
			_p["pivot"] = _pivot_for([door], Models._to_holder(door, holder).origin)
		"bite": _build_bite(isl)
		"hop":
			var picks := []
			for d in isl:
				if not e.has("pick") or _near_any(d["col"], e["pick"]):
					picks.append(d)
			_p["parts"] = _lift_each(picks)
		"spill", "disarray":
			var picks := []
			for d in isl:
				if d["box"].position.y >= float(e.get("min_y", -1.0)) - 0.01:
					picks.append(d)
			_p["parts"] = _lift_each(picks)
			_p["boxes"] = picks.map(func(d): return d["box"])
		"dirty":
			var picks := []
			for d in isl:
				var c: Color = d["col"]
				if d["box"].position.y >= float(e["min_y"]) and c.s < 0.15 and c.v > 0.5:
					picks.append(d)
			_p["parts"] = _lift_each(picks)
		"blood":
			var h := _height(isl)
			var cut := []
			for d in isl:
				for tr in PropAnims.triangles(holder, d):
					if tr["c"].y > h * 0.36:
						cut.append([d, tr["t"]])
			_p["parts"] = [_lift_tris(cut, "blade")]
		"cork":
			var h := _height(isl)
			var body := Color(0, 0, 0, 0)
			var tris := []
			for d in isl:
				tris.append_array(PropAnims.triangles(holder, d).map(func(tr): tr["isl"] = d; return tr))
			for tr in tris:
				if tr["c"].y < h * 0.6:
					body += tr["col"]
			body /= maxf(body.a, 1.0)
			var cut := []
			for tr in tris:
				var col: Color = tr["col"]
				if tr["c"].y > h * 0.8 and absf(col.r - body.r) + absf(col.g - body.g) + absf(col.b - body.b) > 0.25:
					cut.append([tr["isl"], tr["t"]])
			_p["cork"] = _lift_tris(cut, "cork") if not cut.is_empty() else null
		"bed":
			var pil := []
			var blk := []
			for d in isl:
				if PropAnims.colour_near(d["col"], e["pillow"], 0.03):
					pil.append(d)
				elif PropAnims.colour_near(d["col"], e["blanket"], 0.03):
					blk.append(d)
			_p["pillows"] = _lift_each(pil)
			_p["blankets"] = _lift_each(blk)
			var pc := Vector3.ZERO
			for d in pil:
				pc += d["box"].get_center()
			_p["foot"] = -signf(pc.z) if pc.z != 0.0 else 1.0
		"sofabed":
			var seat := []
			for d in isl:
				if PropAnims.colour_near(d["col"], Color("f89f49")):
					seat.append(d)
			_p["seat"] = _lift_each(seat)
		"scribble", "picture", "squirt", "unroll", "burners", "drain":
			_p["isl"] = isl


func _hand_built() -> Array:
	return ["lamp", "pickle", "rocking_chair", "tnt_crate", "dynamite_bundle", "powder_keg",
			"jack_o_lantern_grin", "jack_o_lantern_scary", "jack_o_lantern_goofy"]


func _height(isl: Array) -> float:
	var h := 0.0
	for d in isl:
		h = maxf(h, d["box"].end.y)
	return h


func _near_any(c: Color, list: Array) -> bool:
	for x in list:
		if PropAnims.colour_near(c, x):
			return true
	return false


# The material each surface of a MeshInstance really draws with.
func _mats(mi: MeshInstance3D) -> Array:
	var out := []
	for si in mi.mesh.get_surface_count():
		var m := mi.get_surface_override_material(si)
		out.append(m if m != null else mi.mesh.surface_get_material(si))
	return out


# Lift these triangles ([island, triangle number] pairs, all from one model) out into one new MeshInstance,
# and take them out of the model's own mesh.
func _lift_tris(pairs: Array, tag: String) -> MeshInstance3D:
	var by_mi := {}
	for pr in pairs:
		var d: Dictionary = pr[0]
		var path: NodePath = d["mi"]
		if not by_mi.has(path):
			by_mi[path] = {}
		if not by_mi[path].has(d["s"]):
			by_mi[path][d["s"]] = PackedInt32Array()
		by_mi[path][d["s"]].append(pr[1])
	var part: MeshInstance3D = null
	for path in by_mi:
		var src: MeshInstance3D = holder.get_node(path)
		var o := _original(src, path)
		var mesh := PropAnims.sub_mesh(o["mesh"], by_mi[path], o["mats"], "%s|%s|%s|%d" % [id, path, tag, hash(str(by_mi[path]))])
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_overlay = src.material_overlay
		for prm in ["seed", "look"]:
			var v = src.get_instance_shader_parameter(prm)
			if v != null:
				mi.set_instance_shader_parameter(prm, v)
		mi.transform = Models._to_holder(src, holder)
		if part == null:
			part = mi
			add_child(mi)
		else:
			part.add_child(mi)
			mi.transform = part.transform.affine_inverse() * mi.transform
		for s in by_mi[path]:
			for t in by_mi[path][s]:
				o["gone"][s] = o["gone"].get(s, {})
				o["gone"][s][t] = true
		_trim(src, path)
	return part


func _lift_each(list: Array) -> Array:
	var out := []
	for d in list:
		var pairs := []
		for t in d["tris"]:
			pairs.append([d, t])
		var mi := _lift_tris(pairs, "isl%d" % hash(d["box"]))
		mi.set_meta("box", d["box"])
		mi.set_meta("col", d["col"])
		out.append(mi)
	return out


func _original(src: MeshInstance3D, path: NodePath) -> Dictionary:
	if not _orig.has(path):
		_orig[path] = {"mesh": src.mesh, "mats": _mats(src), "gone": {}}
	return _orig[path]


# The model's own mesh, without the lifted triangles.
func _trim(src: MeshInstance3D, path: NodePath) -> void:
	var o: Dictionary = _orig[path]
	var keep := {}
	var src_mesh: ArrayMesh = o["mesh"]
	for si in src_mesh.get_surface_count():
		var n := src_mesh.surface_get_array_index_len(si) / 3 if src_mesh.surface_get_array_index_len(si) > 0 else src_mesh.surface_get_array_len(si) / 3
		var k := PackedInt32Array()
		var gone: Dictionary = o["gone"].get(si, {})
		for t in n:
			if not gone.has(t):
				k.append(t)
		keep[si] = k
	var key := "%s|%s|rest|%d" % [id, path, hash(str(o["gone"]))]
	src.mesh = PropAnims.sub_mesh(src_mesh, keep, o["mats"], key)
	for si in src.mesh.get_surface_count():
		src.set_surface_override_material(si, null)


# A hinge: a Node3D here at `at`, with these pieces moved under it (so turning it swings them about `at`).
func _pivot_for(parts: Array, at: Vector3) -> Node3D:
	var pv := Node3D.new()
	pv.position = at
	add_child(pv)
	for p in parts:
		var mi := p as Node3D
		var xf: Transform3D = Models._to_holder(mi, holder) if mi.get_parent() != self else mi.transform
		mi.get_parent().remove_child(mi)
		pv.add_child(mi)
		mi.transform = pv.transform.affine_inverse() * xf
	return pv


func _tween(key: String) -> Tween:
	if _tw.has(key) and _tw[key].is_valid():
		_tw[key].kill()
	var t := create_tween()
	_tw[key] = t
	return t


func _sound(sound_name: String, db := -8.0, at := Vector3.ZERO) -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var asp := AudioStreamPlayer3D.new()
	asp.stream = Sounds.get_sound(sound_name)
	asp.bus = Sfx.BUS
	asp.volume_db = db
	asp.unit_size = 5.0
	asp.max_distance = 45.0
	asp.position = at
	add_child(asp)
	asp.finished.connect(asp.queue_free)
	asp.play()


# ---------- lights ----------

func _default_on() -> bool:
	if e.has("on"):
		return e["on"]
	return not (_p.get("natives", []) as Array).is_empty()


static func _is_flame(c: Color) -> bool:
	return c.r > 0.85 and c.g > 0.5 and c.g < 0.85 and c.b < 0.45


func _build_light(isl: Array) -> void:
	var natives := []
	var wicks := []
	for d in isl:
		var b: AABB = d["box"]
		if _is_flame(d["col"]) and b.size.y < 0.4:
			natives.append(d)
		elif d["tris"].size() <= 14 and d["col"].v < 0.45 and b.size.y < 0.16 and b.size.x < 0.1:
			wicks.append(d)
	_p["natives"] = _lift_each(natives)
	var spots := []
	if natives.is_empty():
		for d in wicks:
			spots.append([d["top"], 1.0])
	for a in e.get("at", []):
		spots.append([a, float(e.get("flame", 1.0))])
	var flames := []
	var sum := Vector3.ZERO
	for s in spots:
		var f := Look.flame(s[1], float(flames.size()) * 1.7 + float(hash(id) % 100))
		f.position = s[0]
		add_child(f)
		flames.append(f)
		sum += s[0]
	for n in _p["natives"]:
		sum += (n as Node3D).position + (n.get_meta("box") as AABB).get_center()
	_p["flames"] = flames
	var lights := []
	for l in holder.find_children("*", "OmniLight3D", true, false):
		lights.append(l.get_parent() if l.get_parent() != holder else l)
	if lights.is_empty() and (spots.size() + natives.size()) > 0:
		_p["light_at"] = sum / float(spots.size() + natives.size()) + Vector3.UP * 0.1   # (made when first lit)
	_p["lights"] = lights


func _build_lamp(isl: Array) -> void:
	if e.get("classic", false):
		for c in holder.find_children("*", "MeshInstance3D", true, false):
			var m := (c as MeshInstance3D).material_override as StandardMaterial3D
			if m != null and m.emission_enabled:
				_p["shade_mat"] = m
		_p["lights"] = []   # (just the glowing shade: practice maps scatter lots of these)
		return
	var pale := []
	for d in isl:
		if d["col"].v > 0.75 and d["col"].s < 0.2:
			pale.append(d)
	pale.sort_custom(func(a, b): return a["box"].get_volume() > b["box"].get_volume())
	var parts := _lift_each(pale.slice(0, 2))
	_p["shade"] = parts[0] if parts.size() > 0 else null
	_p["bulb"] = parts[1] if parts.size() > 1 else null
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.82, 0.55)
	l.light_energy = 0.9
	l.omni_range = 5.0
	l.position = (pale[1]["box"] as AABB).get_center() if pale.size() > 1 else Vector3(0.0, _height(isl) * 0.8, 0.0)
	add_child(l)
	_p["lights"] = [l]


static var _bulb_mat: StandardMaterial3D


func _set_lit(on: bool) -> void:
	_p["on"] = on
	if on and _p.has("light_at") and (_p["lights"] as Array).is_empty():
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.72, 0.4)
		l.light_energy = 0.7
		l.omni_range = 4.0
		l.position = _p["light_at"]
		add_child(l)
		_p["lights"].append(l)
	for n in _p.get("natives", []):
		n.visible = on
	for f in _p.get("flames", []):
		f.visible = on
	for l in _p.get("lights", []):
		if l != null:
			l.visible = on
	if _p.has("shade_mat"):
		(_p["shade_mat"] as StandardMaterial3D).emission_enabled = on
	if _p.get("shade") != null:
		(_p["shade"] as MeshInstance3D).material_overlay = Look.shader_mat("glow") if on else null
	if _p.get("bulb") != null:
		if _bulb_mat == null:
			_bulb_mat = StandardMaterial3D.new()
			_bulb_mat.albedo_color = Color(1.0, 0.95, 0.8)
			_bulb_mat.emission_enabled = true
			_bulb_mat.emission = Color(1.0, 0.85, 0.55)
			_bulb_mat.emission_energy_multiplier = 2.5
		(_p["bulb"] as MeshInstance3D).material_override = _bulb_mat if on else null
	if _p.get("face") != null:
		(_p["face"] as GeometryInstance3D).set_instance_shader_parameter("lit", 1.0 if on else 0.0)


# ---------- lids and doors ----------

# A trunk is one closed box (its sides run right up to the top), so it can't just be cut in two. While it's
# open it's drawn as two copies of itself: below the seam (the box, hollow, its inside shaded) and above it
# (the lid, swinging up from the back edge). Closed again, it's the ordinary model.
const CLIP := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float cut = 0.0;
uniform float keep_above = 1.0;
varying float my;
void vertex() { my = VERTEX.y; }
void fragment() {
	if ((my - cut) * (keep_above * 2.0 - 1.0) < 0.0) discard;
	ALBEDO = texture(tex, UV).rgb * (FRONT_FACING ? 1.0 : 0.35);
	ROUGHNESS = 0.8;
}
"""
static var _clip_shader: Shader


func _clip_mat(tex: Texture2D, cut: float, above: bool) -> ShaderMaterial:
	if _clip_shader == null:
		_clip_shader = Shader.new()
		_clip_shader.code = CLIP
	var m := ShaderMaterial.new()
	m.shader = _clip_shader
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("cut", cut)
	m.set_shader_parameter("keep_above", 1.0 if above else 0.0)
	return m


func _build_trunk(isl: Array) -> void:
	var src: MeshInstance3D = holder.get_node(isl[0]["mi"])
	var xf := Models._to_holder(src, holder)
	var box: AABB = isl[0]["box"]
	for d in isl:
		box = box.merge(d["box"])
	var seam: float = box.size.y * float(e["seam"]) + box.position.y
	var local_cut: float = (xf.affine_inverse() * Vector3(0.0, seam, 0.0)).y
	var smat := src.mesh.surface_get_material(0) as StandardMaterial3D
	var tex: Texture2D = smat.albedo_texture if smat != null else null
	var lid := MeshInstance3D.new()
	lid.mesh = src.mesh
	lid.material_override = _clip_mat(tex, local_cut, true)
	lid.transform = xf
	add_child(lid)
	_p["pivot"] = _pivot_for([lid], Vector3(0.0, seam, box.position.z))
	_p["pivot"].visible = false
	_p["src"] = src
	_p["base_mat"] = _clip_mat(tex, local_cut, false)
	# the shadowy inside
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.09, 0.06, 0.04)
	_p["inside"] = _box_mesh(Vector3(box.size.x * 0.9, 0.01, box.size.z * 0.86), dark,
			Vector3(box.get_center().x, seam - box.size.y * 0.12, box.get_center().z), self)
	_p["inside"].visible = false


func _lid() -> void:
	var pv: Node3D = _p["pivot"]
	var t := _tween("lid")
	if _p.has("src"):
		_trunk_open(true)
	t.tween_property(pv, "rotation:x", -0.5, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.55)
	t.tween_property(pv, "rotation:x", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_sound("creak", -12.0)
	t.tween_callback(_sound.bind("latch", -9.0))
	if _p.has("src"):
		t.tween_callback(_trunk_open.bind(false))


func _trunk_open(open: bool) -> void:
	var src: MeshInstance3D = _p["src"]
	if open and not _p.has("own_overlay"):
		_p["own_overlay"] = src.material_overlay
	src.material_override = _p["base_mat"] if open else null
	src.material_overlay = null if open else _p.get("own_overlay")
	(_p["pivot"] as Node3D).visible = open
	(_p["inside"] as Node3D).visible = open


func _fridge() -> void:
	var t := _tween("doors")
	var doors: Array = _p["doors"]
	var swing := func(k: float):
		for pv in doors:
			pv.rotation.y = k
	t.tween_method(swing, 0.0, 1.25, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_interval(1.5)
	t.tween_method(swing, 1.25, 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_sound("creak", -16.0)
	# a little food tumbles out
	var foods := ["restaurant/food_ingredient_tomato", "restaurant/food_ingredient_carrot", "restaurant/food_ingredient_cheese",
			"restaurant/food_ingredient_onion"]
	for k in 2:
		var f := Models.instance(foods[(presses + k) % foods.size()])
		f.scale = Vector3.ONE * 0.6
		f.position = Vector3(-0.2 + 0.3 * k, 0.9 + 0.3 * k, 0.3)
		add_child(f)
		var land := Vector3(-0.35 + 0.55 * k + _rng.randf_range(-0.1, 0.1), 0.0, 0.85 + _rng.randf_range(0.0, 0.4))
		var ft := create_tween()
		ft.tween_interval(0.25 + 0.12 * k)
		ft.tween_property(f, "position", land, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		ft.parallel().tween_property(f, "rotation", Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-3, 3), 0.0), 0.45)
		ft.tween_callback(_sound.bind("thump", -14.0, land))
		ft.tween_interval(2.5)
		ft.tween_property(f, "scale", Vector3.ONE * 0.01, 0.3)
		ft.tween_callback(f.queue_free)


func _oven(open: bool) -> void:
	var pv: Node3D = _p["pivot"]
	var t := _tween("oven")
	t.tween_property(pv, "rotation:x", 1.35 if open else 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if open else Tween.EASE_IN)
	if open:
		_sound("ding", -10.0)


# ---------- food ----------

func _build_bite(isl: Array) -> void:
	var food := []
	for d in isl:
		var b: AABB = d["box"]
		var c: Color = d["col"]
		if b.position.y < float(e.get("min_y", -1.0)) or b.size.y > float(e.get("max_h", 0.7)):
			continue
		if not e.get("dull", false) and c.s < 0.3:
			continue
		food.append(d)
	var tris := []
	var per := []
	for d in food:
		per.append(PropAnims.triangles(holder, d))   # (before lifting: triangle numbers are the model's own)
	for i in food.size():
		var parts := _lift_each([food[i]])
		for tr in per[i]:
			tr["part"] = parts[0]
			tris.append(tr)
	_p["tris"] = tris
	_p["bites"] = []
	_p["caps"] = []
	var c := Vector3.ZERO
	for tr in tris:
		c += tr["c"]
	_p["centre"] = c / maxf(tris.size(), 1)


const BITE_DIRS := [Vector3(0.0, 1.0, 0.7), Vector3(-0.9, 0.8, 0.2), Vector3(0.9, 0.8, 0.2), Vector3(0.0, 0.9, -0.8),
		Vector3(0.6, 1.0, 0.6)]


func _bite() -> void:
	var tris: Array = _p["tris"]
	if tris.is_empty():
		return
	var bites: Array = _p["bites"]
	if bites.size() >= BITE_DIRS.size():
		_regrow()
		bites = _p["bites"]
	var r := float(e.get("r", 0.1))
	var dir: Vector3 = BITE_DIRS[bites.size()].normalized()
	var best := Vector3.ZERO
	var best_d := -INF
	for tr in tris:
		for v in tr["v"]:
			var far := false
			for b in bites:
				if v.distance_to(b) < r * 1.2:
					far = true
			var dd: float = (v - _p["centre"]).dot(dir)
			if not far and dd > best_d:
				best_d = dd
				best = v
	bites.append(best)
	# rebuild each bitten piece without the triangles inside the bite
	var by_part := {}
	var removed_col := Color(0, 0, 0, 0)
	for tr in tris:
		var inside := false
		for b in bites:
			if (tr["c"] as Vector3).distance_to(b) < r * 0.95:
				inside = true
		if not by_part.has(tr["part"]):
			by_part[tr["part"]] = []
		if not inside:
			by_part[tr["part"]].append(tr)
		elif (tr["c"] as Vector3).distance_to(best) < r:
			removed_col += tr["col"]
	for part in by_part:
		_rebuild_part(part, by_part[part])
	var flesh: Color = (removed_col / maxf(removed_col.a, 1.0)) if removed_col.a > 0.0 else Color(0.8, 0.5, 0.4)
	flesh = flesh.lerp(Color(0.92, 0.66, 0.52), 0.35)
	var out := (best - (_p["centre"] as Vector3)).normalized()
	var cap := Look.bite_cap(r * 0.92, out, flesh)
	cap.position = best
	add_child(cap)
	_p["caps"].append(cap)
	_sound("gag" if e.get("gag", false) else "chew", -10.0)
	var t := _tween("regrow")
	t.tween_interval(3.5)
	t.tween_callback(_regrow)


# A bitten piece keeps only these triangles (cached: the bites always land in the same places).
func _rebuild_part(part: MeshInstance3D, keep_tris: Array) -> void:
	if not part.has_meta("full"):
		part.set_meta("full", part.mesh)
	var full: ArrayMesh = part.get_meta("full")
	var k := PackedInt32Array()
	var lookup := {}
	for tr in keep_tris:
		lookup[tr["t"]] = true
	# the part's mesh holds exactly its island's triangles, in order: map island triangle numbers to its own
	var own: Array = part.get_meta("tri_list", [])
	if own.is_empty():
		for tr in _p["tris"]:
			if tr["part"] == part:
				own.append(tr["t"])
		part.set_meta("tri_list", own)
	for i in own.size():
		if lookup.has(own[i]):
			k.append(i)
	part.mesh = PropAnims.sub_mesh(full, {0: k}, [full.surface_get_material(0)], "%s|bite|%d|%d" % [id, part.get_instance_id() % 997, hash(str(k))])


func _regrow() -> void:
	for cap in _p.get("caps", []):
		if is_instance_valid(cap):
			cap.queue_free()
	_p["caps"] = []
	_p["bites"] = []
	for c in get_children():
		if c is MeshInstance3D and c.has_meta("full"):
			c.mesh = c.get_meta("full")


# ---------- dishes, coins, clutter ----------

func _hop() -> void:
	var parts: Array = _p["parts"]
	for i in parts.size():
		var mi: Node3D = parts[i]
		if not mi.has_meta("home"):
			mi.set_meta("home", mi.transform)
		var home: Transform3D = mi.get_meta("home")
		var t := _tween("hop%d" % i)
		t.tween_interval(0.05 * i)
		t.tween_property(mi, "position:y", home.origin.y + 0.07 + 0.02 * (i % 2), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(mi, "rotation:z", mi.rotation.z + _rng.randf_range(-0.08, 0.08), 0.12)
		t.tween_property(mi, "transform", home, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_sound("clatter", -11.0)


func _spill(spill: bool) -> void:
	var parts: Array = _p["parts"]
	var centre := Vector3.ZERO
	for mi in parts:
		centre += (mi.get_meta("box") as AABB).get_center()
	centre /= maxf(parts.size(), 1)
	for i in parts.size():
		var mi: Node3D = parts[i]
		if not mi.has_meta("home"):
			mi.set_meta("home", mi.transform)
		var home: Transform3D = mi.get_meta("home")
		var box: AABB = mi.get_meta("box")
		var out := Vector3(box.get_center().x - centre.x, 0.0, box.get_center().z - centre.z)
		out = out.normalized() if out.length() > 0.02 else Vector3(cos(i * 2.4), 0.0, sin(i * 2.4))
		var edge := Vector3(box.get_center().x, box.position.y, box.get_center().z) + out * minf(box.size.x, box.size.z) * 0.5
		var axis := out.cross(Vector3.UP).normalized()
		var on_table := box.position.y > 0.5   # (on a table they lean over and spill there, not off the edge)
		var ang := 0.0
		if spill:
			ang = -(0.35 + 0.25 * _rng.randf()) if on_table else -(1.35 + 0.25 * _rng.randf())
		var t := _tween("spill%d" % i)
		var from_t: Transform3D = mi.transform
		var target := Transform3D(Basis(axis, ang), Vector3.ZERO)
		target = Transform3D(Basis.IDENTITY, edge) * target * Transform3D(Basis.IDENTITY, -edge) * home
		if spill and not on_table:
			target.origin += out * 0.08 * float(i % 3)
		t.tween_interval(0.06 * i if spill else 0.0)
		t.tween_method(func(k: float): mi.transform = from_t.interpolate_with(target, k), 0.0, 1.0, 0.45 if spill else 0.35) \
				.set_trans(Tween.TRANS_BOUNCE if spill else Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# loose coins skittering out
	for c in _p.get("loose", []):
		if is_instance_valid(c):
			c.queue_free()
	_p["loose"] = []
	if spill:
		var floor_y := (parts[0].get_meta("box") as AABB).position.y if not parts.is_empty() else 0.0
		var reach := 0.3 if floor_y > 0.5 else 0.7
		var coin_mesh := CylinderMesh.new()
		coin_mesh.top_radius = 0.055
		coin_mesh.bottom_radius = 0.055
		coin_mesh.height = 0.016
		coin_mesh.radial_segments = 10
		coin_mesh.rings = 1
		var gold := StandardMaterial3D.new()
		gold.albedo_color = Color(1.0, 0.72, 0.25)
		gold.metallic = 0.9
		gold.roughness = 0.3
		for k in 7:
			var c := MeshInstance3D.new()
			c.mesh = coin_mesh
			c.material_override = gold
			c.position = centre + Vector3(0.0, 0.2, 0.0)
			add_child(c)
			_p["loose"].append(c)
			var a := k * 0.9 + _rng.randf()
			var land := Vector3(centre.x + cos(a) * reach * _rng.randf_range(0.5, 1.0), floor_y + 0.008, centre.z + sin(a) * reach * _rng.randf_range(0.5, 1.0))
			var t := create_tween()
			t.tween_property(c, "position", land, 0.4 + 0.05 * k).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			t.parallel().tween_property(c, "rotation", Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf() * TAU, _rng.randf_range(-0.2, 0.2)), 0.4)
	_sound("tinkle", -10.0)


func _disarray(messy: bool) -> void:
	var parts: Array = _p["parts"]
	for i in parts.size():
		var mi: Node3D = parts[i]
		if not mi.has_meta("home"):
			mi.set_meta("home", mi.transform)
		var home: Transform3D = mi.get_meta("home")
		var box: AABB = mi.get_meta("box")
		var base := Vector3(box.get_center().x, box.position.y, box.get_center().z)
		var target := home
		if messy:
			var topple := i % 3 == 0 and box.size.y > 0.15
			var axis := Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)).normalized()
			var ang := (1.45 if topple else _rng.randf_range(0.2, 0.55)) * (1.0 if _rng.randf() < 0.5 else -1.0)
			var lift := box.size.y * 0.35 if topple else 0.0
			target = Transform3D(Basis(axis, ang), base + Vector3(_rng.randf_range(-0.12, 0.12), -lift + minf(box.size.x, box.size.z) * 0.5 * float(topple), _rng.randf_range(-0.12, 0.12))) \
					* Transform3D(Basis.IDENTITY, -base) * home
			target = target.rotated_local(Vector3.UP, _rng.randf_range(-0.6, 0.6))
		var from_t: Transform3D = mi.transform
		var t := _tween("mess%d" % i)
		t.tween_interval(0.04 * i)
		t.tween_method(func(k: float): mi.transform = from_t.interpolate_with(target, k), 0.0, 1.0, 0.35) \
				.set_trans(Tween.TRANS_BOUNCE if messy else Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_sound("rustle", -10.0)


func _overlay_parts(look: String, on: bool) -> void:
	var mat := Look.shader_mat("dirt" if look == "dirty" else "blood")
	for mi in _p.get("parts", []):
		if mi == null:
			continue
		var g := mi as GeometryInstance3D
		if not g.has_meta("own_overlay"):
			g.set_meta("own_overlay", g.material_overlay)
		g.material_overlay = mat if on else g.get_meta("own_overlay")


# ---------- squirts, scribbles, pours ----------

func _top(isl: Array) -> Vector3:
	var best := Vector3.ZERO
	for d in isl:
		if d["top"].y > best.y:
			best = d["top"]
	return best


func _squirt() -> void:
	if _drops == null:
		var s := SphereMesh.new()
		s.radius = 0.022
		s.height = 0.044
		s.radial_segments = 8
		s.rings = 4
		var m := StandardMaterial3D.new()
		m.albedo_color = e["color"]
		m.roughness = 0.12
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = s
		mm.instance_count = 22
		_drops = MultiMeshInstance3D.new()
		_drops.multimesh = mm
		_drops.material_override = m
		_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_drops)
	_drop_v.clear()
	var tip := _top(_p["isl"]) + Vector3.UP * 0.01
	for i in 22:
		_drop_v.append([tip, Vector3(_rng.randf_range(-0.12, 0.12), 2.5 + _rng.randf_range(-0.2, 0.2), 0.45 + _rng.randf_range(-0.1, 0.1)), i * 0.015])
	_drop_t = 0.0
	_drops.visible = true
	_sound("squirt", -10.0)


func _step_drops(delta: float) -> void:
	_drop_t += delta
	var alive := false
	for i in _drop_v.size():
		var d: Array = _drop_v[i]
		var t: float = _drop_t - d[2]
		var xf := Transform3D(Basis.from_scale(Vector3.ONE * 0.001), d[0])
		if t > 0.0:
			var p: Vector3 = d[0] + d[1] * t + Vector3.DOWN * 4.9 * t * t
			if p.y > 0.0:
				xf = Transform3D(Basis.from_scale(Vector3(1.0, 1.6, 1.0)), p)
				alive = true
		elif t <= 0.0:
			alive = true
		_drops.multimesh.set_instance_transform(i, xf)
	if not alive:
		_drops.visible = false


# The flattest pale patch of the model (a menu's page, a frame's picture): [centre, normal, size].
func _page(isl: Array) -> Array:
	var c := Vector3.ZERO
	var nrm := Vector3.ZERO
	var area := 0.0
	var pts := []
	for d in isl:
		var mid: float = (d["box"] as AABB).get_center().z
		for tr in PropAnims.triangles(holder, d):
			var col: Color = tr["col"]
			if col.v < 0.78 or col.s > 0.18 or tr["c"].z < mid:
				continue   # pale, and on the front half
			var v: Array = tr["v"]
			var n: Vector3 = (v[1] - v[0]).cross(v[2] - v[0])
			if n.length() < 1e-7:
				continue
			if n.z < 0.0:
				n = -n
			if n.normalized().z < 0.3:
				continue
			nrm += n
			area += n.length()
			c += tr["c"] * n.length()
			pts.append_array(v)
	if area <= 0.0:
		return []
	c /= area
	nrm = nrm.normalized()
	if nrm.z < 0.0:
		nrm = -nrm   # (pictures face the front)
	var u := Vector3.UP.cross(nrm).normalized()
	if u.length() < 0.5:
		u = Vector3.RIGHT
	var w := nrm.cross(u).normalized()
	var su := 0.0
	var sw := 0.0
	for p in pts:
		su = maxf(su, absf((p - c).dot(u)))
		sw = maxf(sw, absf((p - c).dot(w)))
	return [c, nrm, Vector2(su * 2.0, sw * 2.0), u, w]


func _scribble() -> void:
	if not _p.has("page"):
		var pg := _page(_p["isl"])
		var q := Look.quad(pg[2] * 0.82 if not pg.is_empty() else Vector2(0.28, 0.4), "scribble")
		if pg.is_empty():
			q.position = Vector3(0.0, 0.35, 0.12)
		else:
			q.transform = Transform3D(Basis(pg[3], pg[4], pg[1]), pg[0] + pg[1] * 0.004)
		add_child(q)
		_p["page"] = q
	var q: MeshInstance3D = _p["page"]
	q.visible = true
	q.set_instance_shader_parameter("fade", 1.0)
	var t := _tween("scribble")
	t.tween_method(func(k: float): q.set_instance_shader_parameter("progress", k), 0.0, 1.0, 1.25)
	t.tween_interval(4.0)
	t.tween_method(func(k: float): q.set_instance_shader_parameter("fade", k), 1.0, 0.0, 0.6)
	_sound("scribble", -12.0)


func _picture(n: int) -> void:
	if not _p.has("pic"):
		var pg := _page(_p["isl"])
		if pg.is_empty():
			return
		var q := Look.quad(pg[2] * 0.98, "picture")
		q.transform = Transform3D(Basis(pg[3], pg[4], pg[1]), pg[0] + pg[1] * 0.003)
		add_child(q)
		_p["pic"] = q
	(_p["pic"] as MeshInstance3D).set_instance_shader_parameter("pic", float((n - 1) % 4 + 1))


func _unroll() -> void:
	if not _p.has("sheet"):
		var isl: Array = _p["isl"]
		var h := _height(isl)
		var r := 0.0
		for d in isl:
			r = maxf(r, d["box"].size.z * 0.5)
		var q := QuadMesh.new()
		q.size = Vector2(0.5, h * 0.72)
		q.center_offset = Vector3(0.25, 0.0, 0.0)
		q.subdivide_width = 10
		q.subdivide_depth = 3
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = Look.shader_mat("paper")
		mi.position = Vector3(0.0, h * 0.5, r * 0.92)
		mi.scale = Vector3(0.01, 1.0, 1.0)
		mi.rotation.y = -0.35
		add_child(mi)
		_p["sheet"] = mi
	var s: MeshInstance3D = _p["sheet"]
	var t := _tween("unroll")
	t.tween_property(s, "scale:x", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(s, "rotation:y", -0.9, 0.5)
	t.tween_interval(1.8)
	t.tween_property(s, "scale:x", 0.01, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(s, "rotation:y", -0.35, 0.45)


func _burners() -> void:
	if not _p.has("rings"):
		var rings := []
		var isl: Array = _p["isl"]
		var h := _height(isl)
		for d in isl:
			var c: Color = d["col"]
			var b: AABB = d["box"]
			if c.r > 0.5 and c.r < 0.8 and c.g < 0.25 and c.b < 0.2 and b.position.y > 0.6 and b.size.y < 0.1:   # (the stovetop)
				var ring := Look.burner(minf(b.size.x, b.size.z) * 0.32)
				ring.position += Vector3(b.get_center().x, b.end.y, b.get_center().z)
				ring.visible = false
				add_child(ring)
				rings.append(ring)
		var l := OmniLight3D.new()
		l.light_color = Color(0.5, 0.6, 1.0)
		l.light_energy = 0.0
		l.omni_range = 3.0
		l.position = Vector3(0.0, h + 0.2, 0.0)
		add_child(l)
		_p["rings"] = rings
		_p["light"] = l
	var t := _tween("burn")
	var rings: Array = _p["rings"]
	var heat := func(k: float):
		for r in rings:
			r.set_instance_shader_parameter("heat", k)
	for r in rings:
		r.visible = true
	# (a step joined "in parallel" right after a pause runs during the pause: so one method for all the rings)
	t.tween_method(heat, 0.0, 1.0, 0.2)
	t.parallel().tween_property(_p["light"], "light_energy", 0.8, 0.2)
	t.tween_interval(1.7)
	t.tween_method(heat, 1.0, 0.0, 0.3)
	t.parallel().tween_property(_p["light"], "light_energy", 0.0, 0.3)
	_sound("rush", -12.0)


func _drain() -> void:
	if not _p.has("stream"):
		var isl: Array = _p["isl"]
		var tap: AABB = AABB()
		var best := -INF
		for d in isl:
			if d["tris"].size() < 60 and d["box"].end.z > best:
				best = d["box"].end.z
				tap = d["box"]
		var spout := Vector3(tap.get_center().x, tap.position.y, tap.end.z - 0.03)
		var s := Look.stream(spout.y, 0.022)
		s.position = Vector3(spout.x, spout.y * 0.5, spout.z)
		s.visible = false
		add_child(s)
		var p := Look.puddle(0.45, "beer")
		p.position = Vector3(spout.x, 0.012, spout.z + 0.12)
		p.visible = false
		add_child(p)
		_p["stream"] = s
		_p["puddle"] = p
	var s: MeshInstance3D = _p["stream"]
	var p: MeshInstance3D = _p["puddle"]
	s.visible = true
	p.visible = true
	p.set_instance_shader_parameter("fade", 1.0)
	var t := _tween("drain")
	t.tween_method(func(k: float): s.set_instance_shader_parameter("flow", k), 0.0, 1.0, 0.25)
	t.parallel().tween_method(func(k: float): p.set_instance_shader_parameter("grow", k), 0.05, 1.0, 1.3)
	t.tween_method(func(k: float): s.set_instance_shader_parameter("flow", k), 1.0, 0.0, 0.25)
	t.tween_callback(func(): s.visible = false)
	t.tween_interval(2.5)
	t.tween_method(func(k: float): p.set_instance_shader_parameter("fade", k), 1.0, 0.0, 0.8)
	_sound("glug", -10.0)


func _cork() -> void:
	var c: MeshInstance3D = _p.get("cork")
	if c == null:
		return
	if not c.has_meta("home"):
		c.set_meta("home", c.transform)
	var home: Transform3D = c.get_meta("home")
	var side := Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.4, 0.4))
	var t := _tween("cork")
	c.transform = home
	c.visible = true
	t.tween_property(c, "position", home.origin + Vector3.UP * 1.1 + side * 0.5, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(c, "rotation", Vector3(5.0, 0.0, 3.0), 0.6)
	t.tween_property(c, "position", home.origin + Vector3.UP * 0.4 + side, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(c, "scale", Vector3.ONE * 0.01, 0.25)
	t.tween_callback(func(): c.visible = false)
	t.tween_interval(1.3)
	t.tween_callback(func(): c.transform = home.scaled_local(Vector3.ONE * 0.01); c.visible = true)
	t.tween_property(c, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sound("pop", -9.0)


# ---------- furniture ----------

func _bed(unmade: bool) -> void:
	var foot: float = _p["foot"]
	var i := 0
	for mi in _p["pillows"]:
		if not mi.has_meta("home"):
			mi.set_meta("home", mi.transform)
		var home: Transform3D = mi.get_meta("home")
		var box: AABB = mi.get_meta("box")
		var c := box.get_center()
		var target := home
		if unmade:
			var turn := Transform3D(Basis(Vector3.UP, 0.45 * (1.0 if i % 2 == 0 else -1.0)) * Basis(Vector3.RIGHT, 0.2), Vector3.ZERO)
			target = Transform3D(Basis.IDENTITY, c + Vector3(0.12 * (1.0 if c.x >= 0.0 else -1.0), 0.03, 0.1 * foot)) * turn \
					* Transform3D(Basis.IDENTITY, -c) * home
		_move(mi, target, "pillow%d" % i)
		i += 1
	i = 0
	var lump_col := Color(0.6, 0.6, 0.6)
	var bed := AABB()
	for mi in _p["blankets"]:
		if not mi.has_meta("home"):
			mi.set_meta("home", mi.transform)
		var home: Transform3D = mi.get_meta("home")
		var box: AABB = mi.get_meta("box")
		lump_col = mi.get_meta("col")
		bed = box if i == 0 else bed.merge(box)
		var target := home
		if unmade:
			# the covers twisted and shoved down toward the foot
			var c := box.get_center()
			target = Transform3D(Basis(Vector3.UP, 0.22 * foot), c + Vector3(0.05, 0.025, foot * box.size.z * 0.18)) \
					* Transform3D(Basis.IDENTITY, -c) * home
		_move(mi, target, "blanket%d" % i)
		i += 1
	# and a rumpled heap of them at the foot
	if not _p.has("lumps") and bed.size != Vector3.ZERO:
		var lumps := []
		var m := _cloth(lump_col)
		for k in 2:
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			s.radial_segments = 12
			s.rings = 6
			var mi := MeshInstance3D.new()
			mi.mesh = s
			mi.material_override = m
			mi.position = Vector3(bed.get_center().x + (k - 0.5) * bed.size.x * 0.35, bed.end.y, bed.get_center().z + foot * bed.size.z * 0.32)
			mi.set_meta("size", Vector3(bed.size.x * (0.5 - 0.12 * k), 0.14, 0.32))
			mi.scale = Vector3.ONE * 0.01
			mi.rotation.y = 0.3 - 0.6 * k
			add_child(mi)
			lumps.append(mi)
		_p["lumps"] = lumps
	for mi in _p.get("lumps", []):
		var t := _tween("lump%d" % mi.get_index())
		t.tween_property(mi, "scale", mi.get_meta("size") if unmade else Vector3.ONE * 0.01, 0.35).set_trans(Tween.TRANS_SINE)


func _move(mi: Node3D, target: Transform3D, key: String, secs := 0.35) -> void:
	var from_t: Transform3D = mi.transform
	var t := _tween(key)
	t.tween_method(func(k: float): mi.transform = from_t.interpolate_with(target, k), 0.0, 1.0, secs) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _cloth(color: Color, kind := "cloth") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	Surfaces.apply(m, kind)
	return m


func _box_mesh(size: Vector3, mat: Material, at: Vector3, parent: Node3D) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


func _sofabed(out: bool) -> void:
	if not _p.has("bed"):
		var bed := Node3D.new()
		add_child(bed)
		var sheet := _cloth(Color(0.95, 0.94, 0.9))
		_box_mesh(Vector3(1.7, 0.16, 1.5), sheet, Vector3(0.0, 0.0, 0.75), bed)
		_box_mesh(Vector3(1.66, 0.04, 0.55), _cloth(Color(0.39, 0.64, 0.82)), Vector3(0.0, 0.09, 1.15), bed)   # folded blanket
		_box_mesh(Vector3(0.55, 0.1, 0.32), _cloth(Color(0.98, 0.98, 0.98)), Vector3(-0.42, 0.12, 0.25), bed)
		_box_mesh(Vector3(0.55, 0.1, 0.32), _cloth(Color(0.98, 0.98, 0.98)), Vector3(0.42, 0.12, 0.25), bed)
		var steel := _cloth(Color(0.35, 0.36, 0.38), "metal")
		for x in [-0.8, 0.8]:
			_box_mesh(Vector3(0.04, 0.22, 0.04), steel, Vector3(x, -0.17, 1.42), bed)
		bed.position = Vector3(0.0, 0.3, -0.9)
		bed.visible = false
		_p["bed"] = bed
	var bed: Node3D = _p["bed"]
	var t := _tween("sofabed")
	if out:
		bed.visible = true
		for s in _p["seat"]:
			s.visible = false
		t.tween_property(bed, "position:z", 0.45, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		t.tween_property(bed, "position:z", -0.9, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		t.tween_callback(func():
			bed.visible = false
			for s in _p["seat"]:
				s.visible = true)
	_sound("creak", -18.0)


func _recline(up: bool) -> void:
	if not _p.has("rest"):
		var pv := Node3D.new()
		pv.position = Vector3(0.0, 0.26, 0.56)
		add_child(pv)
		_box_mesh(Vector3(0.86, 0.13, 0.5), _cloth(Color("fab152")), Vector3(0.0, 0.0, 0.25), pv)
		pv.rotation.x = PI * 0.5
		pv.visible = false
		_p["rest"] = pv
	var pv: Node3D = _p["rest"]
	var t := _tween("recline")
	if up:
		pv.visible = true
		t.tween_property(pv, "rotation:x", -0.12, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		t.tween_property(pv, "rotation:x", PI * 0.5, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		t.tween_callback(func(): pv.visible = false)
	_sound("creak", -18.0)


# ---------- the classic pickle and the new props ----------

func _ooze() -> void:
	if not _p.has("slime"):
		var p := Look.puddle(0.55, "slime")
		p.scale = Vector3(1.0, 1.0, 1.8)
		p.position.y = 0.012
		add_child(p)
		_p["slime"] = p
	var p: MeshInstance3D = _p["slime"]
	p.visible = true
	p.set_instance_shader_parameter("fade", 1.0)
	var t := _tween("ooze")
	t.tween_method(func(k: float): p.set_instance_shader_parameter("grow", k), 0.2, 1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_interval(2.0)
	t.tween_method(func(k: float): p.set_instance_shader_parameter("fade", k), 1.0, 0.0, 0.8)
	t.tween_callback(func(): p.visible = false)
	_sound("squish", -11.0)


func _rock() -> void:
	var r: Node3D = holder.find_child("Rocker", true, false)
	if r == null:
		return
	var t := _tween("rock")
	t.tween_method(func(k: float): r.rotation.x = 0.22 * exp(-k * 1.1) * sin(k * 4.4), 0.0, 3.2, 3.2)
	t.tween_callback(func(): r.rotation.x = 0.0)
	for k in 3:
		var s := create_tween()
		s.tween_interval(k * 0.72)
		s.tween_callback(_sound.bind("rock", -14.0 - 3.0 * k))


func _fuse() -> void:
	if _p.has("spark"):
		return
	var sp := Look.spark()
	sp.position = holder.get_meta("fuse_tip", Vector3(0.0, 0.6, 0.0))
	add_child(sp)
	_p["spark"] = sp
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.65, 0.3)
	l.light_energy = 0.7
	l.omni_range = 2.5
	sp.add_child(l)
	_sound("fuse", -6.0)
	# the spark eats its way down the fuse
	var down: Vector3 = holder.get_meta("fuse_base", sp.position)
	var t := _tween("fuse")
	t.tween_property(sp, "position", down, 1.5)
