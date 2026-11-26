# Characters (Ted, Nov 20: goodbye vertical Tylenol). Built from the KayKit Adventurers and Skeletons
# packs (CC0, Kay Lousberg), which share one skeleton, so parts mix freely: any head on any upper body
# on any legs. An outfit picks each slot:
#   crown  - a halo (angels) or horns (demons), made here
#   head   - a character's head (with its hat or helmet, or "bare")
#   upper  - body and arms (with its cape or cloak, or without)
#   lower  - legs
#   skin   - skin colour (the skin-coloured parts of the texture are recoloured)
#   trail  - the colour of your blessings (angels) or flying flames (demons)
# Angels also get feathered wings and demons bat wings, so the teams always read at a glance.
extends RefCounted

const HornCrowns = preload("res://scripts/horn_crowns.gd")
const DIR := "res://assets/kaykit_characters/"
const SOURCES := {
	"Knight": "adventurers/Knight", "Barbarian": "adventurers/Barbarian", "Mage": "adventurers/Mage",
	"Rogue": "adventurers/Rogue", "Rogue_Hooded": "adventurers/Rogue_Hooded",
	"Skeleton_Warrior": "skeletons/Skeleton_Warrior", "Skeleton_Mage": "skeletons/Skeleton_Mage",
	"Skeleton_Rogue": "skeletons/Skeleton_Rogue", "Skeleton_Minion": "skeletons/Skeleton_Minion",
}
const NICE := {"Knight": "Knight", "Barbarian": "Barbarian", "Mage": "Mage", "Rogue": "Rogue",
	"Rogue_Hooded": "Hooded Rogue", "Skeleton_Warrior": "Skeleton Warrior", "Skeleton_Mage": "Skeleton Mage",
	"Skeleton_Rogue": "Skeleton Rogue", "Skeleton_Minion": "Skeleton Minion"}
const MODEL_HEIGHT := 2.35         # the KayKit characters' height, head included (their units)

const CROWNS := {
	"angel": [["halo", "Golden halo"], ["halo_double", "Double halo"], ["halo_star", "Starry halo"], ["halo_thorn", "Thorny halo"]],
	"demon": [["horns", "Devil horns"], ["horns_ram", "Ram horns"], ["horns_goat", "Goat horns"], ["horns_nubs", "Little nubs"],
			["horns_twist", "Corkscrew horns"], ["horns_four", "Four horns"]],
}
# Each team has its own wardrobe (Ted, Nov 20): angels dress from the adventurers, demons from the
# skeletons, with matching themes across the two (Knight / Skeleton Warrior, Mage / Skeleton Mage,
# Rogue / Skeleton Rogue, Barbarian / Skeleton Minion). Skin colours are split the same way.
const TEAM_CHARS := {
	"angel": ["Knight", "Barbarian", "Mage", "Rogue", "Rogue_Hooded"],
	"demon": ["Skeleton_Warrior", "Skeleton_Mage", "Skeleton_Rogue", "Skeleton_Minion"],
}
const SKINS := [
	["natural", "As drawn", ""], ["pale", "Pale", "#f2dcc8"], ["tan", "Tan", "#c98e62"], ["brown", "Brown", "#8a5a3c"],
	["dark", "Dark", "#5a3a28"], ["ghost", "Ghostly white", "#e9eef7"], ["gold", "Gold", "#e6b84a"],
	["hellred", "Hell red", "#b8281e"], ["ash", "Ash grey", "#6c6a70"], ["zombie", "Zombie green", "#7fa35a"],
	["ocean", "Ocean blue", "#4a7fc2"], ["violet", "Violet", "#8a55c0"], ["coal", "Coal black", "#2a2426"],
	["sulfur", "Sulfur yellow", "#c9b33a"], ["blood", "Blood", "#6e0f12"], ["rose", "Rose", "#e7a5a0"],
]
const TEAM_SKINS := {
	"angel": ["natural", "pale", "tan", "brown", "dark", "rose", "ghost", "gold", "ocean"],
	"demon": ["natural", "hellred", "blood", "ash", "coal", "zombie", "violet", "sulfur"],
}
const TRAILS := {
	# angels: which blessing they throw (blessings.gd: same damage, different look)
	"angel": [["holy_light", "Holy Light", "#ffe566"], ["blessed_water", "Blessed Water", "#73bfff"], ["halo_ring", "Halo Ring", "#ffcc33"],
		["feather", "Feather", "#f2f2ff"], ["choir", "Choir Note", "#d9a6ff"]],
	"demon": [["fire", "Hellfire", "#ff6a1a"], ["blue", "Blue flame", "#4aa8ff"], ["green", "Green flame", "#5aff5a"], ["purple", "Purple flame", "#c060ff"], ["smoke", "Black smoke", "#3a3038"]],
}

static var _sources := {}          # name -> an instance of that character, kept to copy parts from
static var _skin_ref := {}         # texture path -> its skin colour


static func default_outfit(role: String) -> Dictionary:
	if role == "angel":
		return {"crown": "halo", "head": "Knight", "upper": "Knight", "lower": "Knight", "skin": "natural", "trail": "holy_light"}
	# (bone-white skull by default: Ted, Nov 21, couldn't see a head when it was red on red)
	return {"crown": "horns", "head": "Skeleton_Warrior", "upper": "Skeleton_Warrior", "lower": "Skeleton_Warrior", "skin": "natural", "trail": "fire"}


# Matching sets: every character, whole.
static func matching_sets(role: String) -> Array:
	var out := []
	var d := default_outfit(role)
	for c in TEAM_CHARS[role]:
		if c == "Rogue_Hooded":
			continue
		var o := d.duplicate()
		o["head"] = c
		o["upper"] = c
		o["lower"] = c
		out.append([NICE[c], o])
	if role == "angel":
		var hooded := d.duplicate()
		hooded["head"] = "Rogue_Hooded"
		hooded["upper"] = "Rogue"
		hooded["lower"] = "Rogue"
		out.append([NICE["Rogue_Hooded"], hooded])
	return out


# Every choice for a slot: [id, label].
static func options(slot: String, role: String) -> Array:
	match slot:
		"crown":
			return CROWNS[role]
		"skin":
			return SKINS.filter(func(s): return s[0] in TEAM_SKINS[role]).map(func(s): return [s[0], s[1]])
		"trail":
			return TRAILS[role].map(func(s): return [s[0], s[1]])
	var out := []
	for c in TEAM_CHARS[role]:
		if slot != "head" and c == "Rogue_Hooded":
			continue
		out.append([c, NICE[c]])
		if slot == "head" and not _hat(c).is_empty():
			out.append([c + ":bare", NICE[c] + " (no hat)"])
		if slot == "upper" and not _cape(c).is_empty():
			out.append([c + ":bare", NICE[c] + " (no cape)"])
	return out


# Any outfit read from a file or another player is checked against these.
static func clean_outfit(o, role: String) -> Dictionary:
	var d := default_outfit(role)
	if typeof(o) != TYPE_DICTIONARY:
		return d
	var out := {}
	for slot in d:
		var v = o.get(slot)
		var ok := false
		if typeof(v) == TYPE_STRING:   # (anything else from a file or another player: the default)
			for opt in options(slot, role):
				if opt[0] == v:
					ok = true
		out[slot] = v if ok else d[slot]
	return out


static func trail_color(role: String, outfit: Dictionary) -> Color:
	for t in TRAILS[role]:
		if t[0] == outfit.get("trail", ""):
			return Color(t[2])
	return Color(TRAILS[role][0][2])


# ---------------- building one ----------------

# Free the characters kept to copy parts from. Called when the game closes: left until the engine's own
# shutdown, they're freed after the renderer is gone, which crashed the Linux build on exit (v0.6.8).
static func release() -> void:
	for n in _sources.values():
		if is_instance_valid(n):
			n.free()
	_sources.clear()


static func _source(c: String) -> Node:
	if not _sources.has(c):
		var scene := load(DIR + SOURCES[c] + ".glb") as PackedScene
		_sources[c] = scene.instantiate() if scene else null
	return _sources[c]


static func _skeleton_of(n: Node) -> Skeleton3D:
	var found := n.find_children("*", "Skeleton3D", true, false)
	return found[0] if not found.is_empty() else null


static func _parts(c: String, suffixes: Array) -> Array:
	var src := _source(c)
	var sk := _skeleton_of(src) if src else null
	if sk == null:
		return []
	var out := []
	for ch in sk.get_children():
		if ch is MeshInstance3D:
			for s in suffixes:
				if ch.name.ends_with(s):
					out.append(ch)
	return out


static func _attached(c: String, bone: String) -> Array:
	var src := _source(c)
	var sk := _skeleton_of(src) if src else null
	if sk == null:
		return []
	var out := []
	for ch in sk.get_children():
		if ch is BoneAttachment3D and ch.bone_name == bone:
			for m in ch.get_children():
				if m is MeshInstance3D:
					out.append(m)
	return out


static func _hat(c: String) -> Array:
	return _attached(c, "head") + _parts(c, ["_Helmet", "_Hat"])


static func _cape(c: String) -> Array:
	return _attached(c, "chest") + _parts(c, ["_Cloak"])


# A character for this role and outfit, standing with its feet at y = 0, facing -Z, the right height
# for the role (Bodies scales demons down). The root has character_rig.gd, which plays its animations.
static func build(role: String, outfit: Dictionary, height: float) -> Node3D:
	outfit = clean_outfit(outfit, role)
	var rig: Node3D = load("res://scripts/character_rig.gd").new()
	var base := (load(DIR + SOURCES["Knight"] + ".glb") as PackedScene).instantiate() as Node3D
	var sk := _skeleton_of(base)
	# Strip the base down to just its skeleton and animations
	for ch in sk.get_children():
		ch.free()
	base.scale = Vector3.ONE * (height / MODEL_HEIGHT)
	base.rotation.y = PI   # (KayKit characters face +Z; ours face -Z)
	rig.add_child(base)
	var head: String = outfit["head"]
	var upper: String = outfit["upper"]
	var lower: String = outfit["lower"]
	var head_c := head.get_slice(":", 0)
	var upper_c := upper.get_slice(":", 0)
	var skin_col := ""
	for s in SKINS:
		if s[0] == outfit["skin"]:
			skin_col = s[2]
	var pieces := []
	# (the Skeleton Mage's skull is its own "_Skull" mesh: without it a bare Mage head was floating eyes and a jaw)
	pieces += _parts(head_c, ["_Head", "_Head_Hooded", "_Skull", "_Eyes", "_Jaw"])
	pieces += _parts(upper_c, ["_Body", "_ArmLeft", "_ArmRight"])
	pieces += _parts(outfit["lower"], ["_LegLeft", "_LegRight"])
	if not upper.ends_with(":bare"):
		pieces += _parts(upper_c, ["_Cloak"])
	for p in pieces:
		var mi: MeshInstance3D = p.duplicate()
		sk.add_child(mi)
		mi.skeleton = NodePath("..")
		_recolor(mi, skin_col, role, p.name.ends_with("_Eyes"))
	# Hats and capes hang off bones
	var hung := []
	if not head.ends_with(":bare"):
		for m in _hat(head_c):
			hung.append(["head", m])
	if not upper.ends_with(":bare"):
		for m in _attached(upper_c, "chest"):
			hung.append(["chest", m])
	for h in hung:
		var att := BoneAttachment3D.new()
		att.bone_name = h[0]
		sk.add_child(att)
		var mi: MeshInstance3D = h[1].duplicate()
		att.add_child(mi)
		_recolor(mi, "", role, false)
	# Each character's extra details (scripts/skin_details/<name>.gd), per piece worn
	_add_details(sk, head_c, "head", role, head.ends_with(":bare"))
	_add_details(sk, upper_c, "upper", role, upper.ends_with(":bare"))
	_add_details(sk, lower, "lower", role, false)
	# The team's marks: halo or horns, and wings
	var head_att := BoneAttachment3D.new()
	head_att.bone_name = "head"
	sk.add_child(head_att)
	head_att.add_child(_crown(outfit["crown"], role, head_c.begins_with("Skeleton") and not head.ends_with(":bare") and not _hat(head_c).is_empty()))
	var wings := _wings(role)
	base.add_child(wings)   # (model space: the back is -Z, the chest about 1.1 up)
	rig.setup(base.find_children("*", "AnimationPlayer", true, false)[0], wings, role)
	return rig


# Extra details for one piece of one character, from scripts/skin_details/<name>.gd (if it exists):
# static funcs head(), upper() and lower(), each given the skeleton, a BoneAttachment3D already on the
# matching bone (head / chest / hips), the team, and whether the hat or cape was left off ("bare").
const SLOT_BONES := {"head": "head", "upper": "chest", "lower": "hips"}


static func _add_details(sk: Skeleton3D, c: String, slot: String, role: String, bare: bool) -> void:
	var path := "res://scripts/skin_details/%s.gd" % c.to_lower()
	if not ResourceLoader.exists(path):
		return
	var script = load(path)
	if script == null or not script.has_method(slot):
		return
	var att := BoneAttachment3D.new()
	att.name = "Details_" + slot
	att.bone_name = SLOT_BONES[slot]
	sk.add_child(att)
	script.call(slot, sk, att, role, bare)


# The skin-coloured bits of a part's texture, recoloured; demons' eyes glow.
static func _recolor(mi: MeshInstance3D, skin_hex: String, role: String, eyes: bool) -> void:
	if eyes:
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(1.0, 0.25, 0.1) if role == "demon" else Color(0.6, 0.85, 1.0)
		glow.emission_enabled = true
		glow.emission = glow.albedo_color
		glow.emission_energy_multiplier = 3.0
		mi.material_override = glow
		return
	if skin_hex == "":
		return
	var src := mi.mesh.surface_get_material(0) as StandardMaterial3D if mi.mesh else null
	if src == null or src.albedo_texture == null:
		return
	var sm := ShaderMaterial.new()
	sm.shader = _skin_shader()
	sm.set_shader_parameter("tex", src.albedo_texture)
	# Skin is a ramp of shades in the texture: match by hue and saturation, keep each texel's shade.
	var ref := skin_ref(src.albedo_texture)
	sm.set_shader_parameter("ref_hsv", Vector3(ref.h, ref.s, ref.v))
	var c := Color(skin_hex)
	sm.set_shader_parameter("skin_new", Vector3(c.r, c.g, c.b))
	mi.material_override = sm


static var _shader: Shader


static func _skin_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
uniform sampler2D tex : filter_nearest;   // (raw sRGB: compared as the artist painted it)
uniform vec3 ref_hsv;
uniform vec3 skin_new;
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
void fragment() {
	vec3 c = texture(tex, UV).rgb;
	vec3 h = rgb2hsv(c);
	float dh = abs(h.x - ref_hsv.x);
	dh = min(dh, 1.0 - dh);
	float k = (1.0 - smoothstep(0.03, 0.05, dh)) * (1.0 - smoothstep(0.18, 0.26, abs(h.y - ref_hsv.y)))
			* smoothstep(ref_hsv.z - 0.45, ref_hsv.z - 0.3, h.z);
	vec3 painted = skin_new * clamp(h.z / max(ref_hsv.z, 0.01), 0.0, 1.3);
	ALBEDO = to_linear(mix(c, painted, k));
	ROUGHNESS = 0.8;
}
"""
	return _shader


# The skin colour in a character texture: the commonest colour on that character's head.
static func skin_ref(tex: Texture2D) -> Color:
	var key := tex.resource_path
	if _skin_ref.has(key):
		return _skin_ref[key]
	var img := tex.get_image()
	if img != null and img.is_compressed():
		img.decompress()
	var counts := {}
	var best := Color(0.9, 0.75, 0.62)
	if img != null:
		# the head of whichever character uses this texture
		for c in SOURCES:
			for p in _parts(c, ["_Head"]):
				var m := (p as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
				if m == null or m.albedo_texture == null or m.albedo_texture.resource_path != key:
					continue
				var uvs: PackedVector2Array = (p as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
				for uv in uvs:
					var px := Vector2i(clampi(int(fposmod(uv.x, 1.0) * img.get_width()), 0, img.get_width() - 1),
							clampi(int(fposmod(uv.y, 1.0) * img.get_height()), 0, img.get_height() - 1))
					var col := img.get_pixelv(px)
					var k := col.to_html(false)
					counts[k] = counts.get(k, 0) + 1
		# the commonest colour that looks like skin (or bone, for the skeletons), not hair or a hood
		var bony := key.contains("skeleton")
		var target := Color(0.88, 0.86, 0.78) if bony else Color(0.95, 0.74, 0.6)
		var top := 0
		for k in counts:
			var c := Color(k)
			var close := Vector3(c.r - target.r, c.g - target.g, c.b - target.b).length() < 0.28
			if close and counts[k] > top:
				top = counts[k]
				best = c
	_skin_ref[key] = best
	return best


# ---------------- halos, horns and wings ----------------

static func _glow(c: Color, e := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


static func _plain(c: Color, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


# (in the head bone's space, KayKit units: the top of the head is about 1.1 up from the bone)
static func _crown(kind: String, role: String, has_hat: bool) -> Node3D:
	var n := Node3D.new()
	var top := 1.25 if has_hat else 1.15
	match kind:
		"halo", "halo_double", "halo_star", "halo_thorn":
			var gold := _glow(Color(1.0, 0.85, 0.35), 2.2)
			var rings := 2 if kind == "halo_double" else 1
			for i in rings:
				var t := TorusMesh.new()
				t.rings = 32   # (Godot's default 64 x 32 is ~4000 triangles; Nov 26 audit)
				t.ring_segments = 12
				t.inner_radius = 0.36 - i * 0.1
				t.outer_radius = 0.43 - i * 0.1
				var mi := MeshInstance3D.new()
				mi.mesh = t
				mi.material_override = gold
				mi.position.y = top + 0.25 + i * 0.12
				n.add_child(mi)
			if kind == "halo_star" or kind == "halo_thorn":
				for k in 8:
					var a := TAU * k / 8.0
					var spike := MeshInstance3D.new()
					var cm := CylinderMesh.new()
					cm.top_radius = 0.0
					cm.bottom_radius = 0.04 if kind == "halo_star" else 0.025
					cm.height = 0.16 if kind == "halo_star" else 0.12
					spike.mesh = cm
					spike.material_override = gold if kind == "halo_star" else _plain(Color(0.35, 0.25, 0.12))
					spike.position = Vector3(cos(a) * 0.4, top + 0.25, sin(a) * 0.4)
					if kind == "halo_star":
						spike.position.y += 0.1
					else:
						spike.rotation = Vector3(0, -a, PI / 2)
					n.add_child(spike)
		_:
			# swept, twisted, ridged horns like the shrine's, each kind its own shape and colouring (horn_crowns.gd)
			n.add_child(HornCrowns.make(kind, top))
	return n


static func _align_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, y, x.cross(y))


# Wings on the back (model space, KayKit units; +Z is the character's front, so the back is -Z).
# Each wing lies flat in its own XY plane, reaching out along +X (right wing) or -X (left), and
# character_rig.gd swings them about Y to fold and spread. (Ted, Nov 21: angel wings were "a bunch of
# rectangles" and demon wings "triangular flags": now real feathers, and scaly dragon wings.)
static var _feather: ArrayMesh
static var _wing_mats := {}


static func _wings(role: String) -> Node3D:
	var n := Node3D.new()
	n.name = "Wings"
	for side in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.name = "L" if side < 0 else "R"
		wing.position = Vector3(0.14 * side, 1.12, -0.36)
		n.add_child(wing)
		if role == "angel":
			_angel_wing(wing, side)
		else:
			_demon_wing(wing, side)
	return n


# One feather: a long tapered vane with a rounded tip and a quill down the middle (a darker line), a
# little cupped, pointing up its +Y. Shared by every feather (scaled per feather).
static func _feather_mesh() -> ArrayMesh:
	if _feather:
		return _feather
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 10
	var pts := []
	for i in rows + 1:
		var t := float(i) / rows
		var w := 0.5 * sin(PI * pow(t, 0.75)) * (1.0 - 0.25 * t)   # widest a third of the way up, rounded tip
		var y := t
		var cup := 0.06 * w   # the edges curl back a touch
		pts.append([Vector3(-w, y, -cup), Vector3(0, y, 0.015), Vector3(w, y, -cup)])
	var edge := Color(0.93, 0.92, 0.95)
	var vane := Color(1.0, 1.0, 0.98)
	var quill := Color(0.78, 0.76, 0.72)
	for i in rows:
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		for half in 2:
			var o := half   # 0: left half (edge -> quill), 1: right half (quill -> edge)
			var p0: Vector3 = a[o]
			var p1: Vector3 = a[o + 1]
			var p2: Vector3 = b[o + 1]
			var p3: Vector3 = b[o]
			var c0 := edge if o == 0 else quill
			var c1 := quill if o == 0 else edge
			for v in [[p0, c0], [p1, c1], [p2, c1], [p0, c0], [p2, c1], [p3, c0]]:
				st.set_color(v[1].lerp(vane, 0.4) if v[1] != quill else quill)
				st.add_vertex(v[0])
	st.generate_normals()
	_feather = st.commit()
	return _feather


static func _angel_mat() -> StandardMaterial3D:
	if not _wing_mats.has("angel"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(1, 1, 1)
		m.roughness = 0.85
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.rim_enabled = true
		m.rim = 0.35
		m.emission_enabled = true
		m.emission = Color(1.0, 0.97, 0.88)
		m.emission_energy_multiplier = 0.12   # a faint holy glow
		_wing_mats["angel"] = m
	return _wing_mats["angel"]


static func _add_feather(wing: Node3D, at: Vector3, angle: float, length: float, width: float, depth: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _feather_mesh()
	mi.material_override = _angel_mat()
	mi.position = at + Vector3(0, 0, depth)
	mi.rotation.z = angle
	mi.scale = Vector3(width, length, 1.0)
	wing.add_child(mi)


# An angel wing: a bony leading edge arching up and out, long primary feathers fanning from the tip,
# secondaries hanging along the arm, and rows of small covert feathers overlapping on top.
static func _angel_wing(wing: Node3D, side: float) -> void:
	var shoulder := Vector3.ZERO
	var elbow := Vector3(0.42 * side, 0.3, 0)
	var wrist := Vector3(0.95 * side, 0.36, 0)
	# Primaries: from the wrist, fanning from out-and-up to straight down, longest in the middle
	for i in 7:
		var k := float(i) / 6.0
		var ang := side * lerpf(-1.35, -2.75, k)   # feather +Y rotated: outward then down
		var length := lerpf(0.72, 0.62, absf(k - 0.35) * 1.5)
		var at := wrist.lerp(elbow, k * 0.35)
		_add_feather(wing, at, ang, length, 0.2, -0.01 * i)
	# Secondaries: along the arm, pointing down and a little out
	for i in 6:
		var k := float(i) / 5.0
		var at := elbow.lerp(shoulder, k * 0.85)
		var ang := side * lerpf(-2.75, -2.95, k)
		_add_feather(wing, at, ang, lerpf(0.55, 0.42, k), 0.21, -0.06 - 0.008 * i)
	# Coverts: two rows of short feathers over the bases, so no gaps show
	for row in 2:
		for i in 7:
			var k := float(i) / 6.0
			var at := shoulder.lerp(wrist, k) + Vector3(0, 0.03 - 0.09 * row, 0)
			var ang := side * lerpf(-2.6, -2.2, k)
			_add_feather(wing, at, ang, 0.26 - row * 0.05, 0.17, 0.02 + 0.01 * row)
	# The leading edge: a soft rounded arm
	var arm_mat := _angel_mat()
	for seg in [[shoulder, elbow], [elbow, wrist]]:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.035
		cm.height = a.distance_to(b) + 0.07
		mi.mesh = cm
		mi.material_override = arm_mat
		mi.position = (a + b) * 0.5 + Vector3(0, 0, 0.005)   # tucked under the coverts (it read as a white pipe from the front)
		mi.basis = _align_y(b - a)
		wing.add_child(mi)


const SCALE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 base_color = vec3(0.22, 0.03, 0.05);
uniform vec3 dark_color = vec3(0.05, 0.01, 0.02);
uniform vec3 vein_color = vec3(0.9, 0.25, 0.05);
varying vec3 lp;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { lp = VERTEX; }
void fragment() {
	// overlapping scales: offset rows of rounded cells, darker at each scale's lower rim
	vec2 uv = lp.xy * vec2(5.5, 6.5);
	float row = floor(uv.y);
	uv.x += mod(row, 2.0) * 0.5;
	vec2 cell = fract(uv) - vec2(0.5, 0.0);
	float d = length(cell * vec2(1.0, 0.8));
	float rim = smoothstep(0.35, 0.55, d);
	float tint = h(floor(uv)) * 0.25;
	vec3 col = mix(base_color * (0.85 + tint), dark_color, rim);
	// faint glowing veins running out along the wing
	float vein = 1.0 - smoothstep(0.0, 0.04, abs(fract(atan(lp.y, abs(lp.x) + 0.0001) * 2.2) - 0.5));
	ALBEDO = col;
	EMISSION = vein_color * vein * 0.35;
	ROUGHNESS = 0.45;
	METALLIC = 0.15;
	SPECULAR = 0.6;
}
"""


static func _demon_mats() -> Array:
	if not _wing_mats.has("demon"):
		var skin := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SCALE_SHADER
		skin.shader = sh
		var bone := StandardMaterial3D.new()
		bone.albedo_color = Color(0.16, 0.06, 0.06)
		bone.roughness = 0.5
		var claw := StandardMaterial3D.new()
		claw.albedo_color = Color(0.85, 0.8, 0.7)
		claw.roughness = 0.35
		_wing_mats["demon"] = [skin, bone, claw]
	return _wing_mats["demon"]


# A demon wing, dragon-style: an arm (shoulder, elbow, wrist with a claw) and long finger bones
# spreading from the wrist, with a scaly membrane stretched between them, scalloped between the tips.
static func _demon_wing(wing: Node3D, side: float) -> void:
	var mats := _demon_mats()
	var shoulder := Vector3.ZERO
	var elbow := Vector3(0.38 * side, 0.32, 0)
	var wrist := Vector3(0.78 * side, 0.52, 0)
	var tips := [
		wrist + Vector3(0.55 * side, 0.18, 0),
		wrist + Vector3(0.62 * side, -0.22, 0),
		wrist + Vector3(0.45 * side, -0.62, 0),
		wrist + Vector3(0.16 * side, -0.85, 0),
	]
	var body := Vector3(0.06 * side, -0.42, 0)
	# The membrane: a fan from the wrist over the outline elbow -> tips (scalloped) -> body -> shoulder
	var outline := [elbow, tips[0]]
	for i in tips.size():
		var a: Vector3 = tips[i]
		var b: Vector3 = tips[i + 1] if i + 1 < tips.size() else body
		var mid := (a + b) * 0.5
		outline.append(mid.lerp(wrist, 0.28))   # the scallop: the edge sags in between the fingers
		outline.append(b)
	outline.append(shoulder)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in outline.size() - 1:
		var p1: Vector3 = outline[i]
		var p2: Vector3 = outline[i + 1]
		# subdivide each fan slice a little so it bends (a slight cup) instead of being dead flat
		var m1 := wrist.lerp(p1, 0.5) + Vector3(0, 0, -0.04)
		var m2 := wrist.lerp(p2, 0.5) + Vector3(0, 0, -0.04)
		for tri in [[wrist, m1, m2], [m1, p1, p2], [m1, p2, m2]]:
			for v in tri:
				st.add_vertex(v)
	st.generate_normals()
	var mem := MeshInstance3D.new()
	mem.mesh = st.commit()
	mem.material_override = mats[0]
	wing.add_child(mem)
	# Bones: the arm and the fingers, tapering, with a hooked claw at the wrist
	var bones := [[shoulder, elbow, 0.045], [elbow, wrist, 0.04]]
	for t in tips:
		bones.append([wrist, t, 0.025])
	for b in bones:
		var a: Vector3 = b[0]
		var c: Vector3 = b[1]
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.bottom_radius = b[2]
		cm.top_radius = b[2] * 0.45
		cm.height = a.distance_to(c)
		cm.radial_segments = 6
		mi.mesh = cm
		mi.material_override = mats[1]
		mi.position = (a + c) * 0.5 + Vector3(0, 0, 0.01)
		mi.basis = _align_y(c - a)
		wing.add_child(mi)
	for t in tips + [wrist]:   # little knuckles
		var k := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.07
		sm.radial_segments = 6
		sm.rings = 3
		k.mesh = sm
		k.material_override = mats[1]
		k.position = t
		wing.add_child(k)
	var claw := MeshInstance3D.new()
	var cc := CylinderMesh.new()
	cc.top_radius = 0.0
	cc.bottom_radius = 0.03
	cc.height = 0.16
	claw.mesh = cc
	claw.material_override = mats[2]
	claw.position = wrist + Vector3(0.02 * side, 0.09, 0.02)
	claw.rotation.z = -0.5 * side
	wing.add_child(claw)
