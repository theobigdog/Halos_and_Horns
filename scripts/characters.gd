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
	"demon": [["horns", "Devil horns"], ["horns_ram", "Ram horns"], ["horns_goat", "Goat horns"], ["horns_nubs", "Little nubs"]],
}
const SKINS := [
	["natural", "As drawn", ""], ["pale", "Pale", "#f2dcc8"], ["tan", "Tan", "#c98e62"], ["brown", "Brown", "#8a5a3c"],
	["dark", "Dark", "#5a3a28"], ["ghost", "Ghostly white", "#e9eef7"], ["gold", "Gold", "#e6b84a"],
	["hellred", "Hell red", "#b8281e"], ["ash", "Ash grey", "#6c6a70"], ["zombie", "Zombie green", "#7fa35a"],
	["ocean", "Ocean blue", "#4a7fc2"], ["violet", "Violet", "#8a55c0"], ["coal", "Coal black", "#2a2426"],
]
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
	return {"crown": "horns", "head": "Skeleton_Warrior", "upper": "Skeleton_Warrior", "lower": "Skeleton_Warrior", "skin": "hellred", "trail": "fire"}


# Matching sets: every character, whole.
static func matching_sets(role: String) -> Array:
	var out := []
	var d := default_outfit(role)
	for c in SOURCES:
		if c == "Rogue_Hooded":
			continue
		var o := d.duplicate()
		o["head"] = c
		o["upper"] = c
		o["lower"] = c
		out.append([NICE[c], o])
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
			return SKINS.map(func(s): return [s[0], s[1]])
		"trail":
			return TRAILS[role].map(func(s): return [s[0], s[1]])
	var out := []
	for c in SOURCES:
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
	pieces += _parts(head_c, ["_Head", "_Head_Hooded", "_Eyes", "_Jaw"])
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
	# The team's marks: halo or horns, and wings
	var head_att := BoneAttachment3D.new()
	head_att.bone_name = "head"
	sk.add_child(head_att)
	head_att.add_child(_crown(outfit["crown"], role, head_c.begins_with("Skeleton") and not head.ends_with(":bare") and not _hat(head_c).is_empty()))
	var wings := _wings(role)
	base.add_child(wings)   # (model space: the back is -Z, the chest about 1.1 up)
	rig.setup(base.find_children("*", "AnimationPlayer", true, false)[0], wings, role)
	return rig


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
			var dark := _plain(Color(0.16, 0.1, 0.1), 0.4)
			for side in [-1.0, 1.0]:
				var segs := 1
				var length := 0.45
				var bend := 0.35
				var thick := 0.1
				match kind:
					"horns_ram":
						segs = 4
						bend = 0.7
						thick = 0.11
						length = 0.18
					"horns_goat":
						segs = 3
						bend = 0.25
						length = 0.28
						thick = 0.08
					"horns_nubs":
						length = 0.16
						thick = 0.09
				var at := Vector3(0.28 * side, top - 0.15, 0.05)
				var dir := Vector3(0.45 * side, 1.0, -0.15).normalized()
				for s in segs:
					var cm := CylinderMesh.new()
					cm.top_radius = thick * (1.0 - float(s + 1) / (segs + 0.5)) if s == segs - 1 else thick * (1.0 - float(s + 1) / (segs + 1.0))
					cm.bottom_radius = thick * (1.0 - float(s) / (segs + 1.0))
					cm.height = length
					var mi := MeshInstance3D.new()
					mi.mesh = cm
					mi.material_override = dark
					var mid := at + dir * length * 0.5
					mi.position = mid
					mi.basis = _align_y(dir)
					n.add_child(mi)
					at += dir * length
					dir = (dir + Vector3(0.2 * side, -bend * 0.5, 0.25)).normalized() if kind == "horns_ram" else (dir + Vector3(0.08 * side, 0, 0.12)).normalized()
	return n


static func _align_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, y, x.cross(y))


# Wings on the back (chest bone space, KayKit units; +Z is the character's front, so the back is -Z).
static func _wings(role: String) -> Node3D:
	var n := Node3D.new()
	n.name = "Wings"
	var mat := _plain(Color(0.98, 0.97, 0.93), 0.9) if role == "angel" else _plain(Color(0.35, 0.06, 0.06), 0.5)
	if role == "demon":
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.name = "L" if side < 0 else "R"
		wing.position = Vector3(0.14 * side, 1.12, -0.36)
		n.add_child(wing)
		if role == "angel":
			# layered feathers fanning out and down: longest at the top
			for f in 7:
				var mi := MeshInstance3D.new()
				var b := BoxMesh.new()
				b.size = Vector3(1.0 - f * 0.09, 0.17, 0.04)
				mi.mesh = b
				mi.material_override = mat
				mi.position = Vector3(side * (0.48 - f * 0.03), 0.22 - f * 0.13, -f * 0.012)
				mi.rotation.z = side * (0.25 + f * 0.16)
				wing.add_child(mi)
		else:
			# a bat wing: a finger bone and a stretched membrane
			var bone := MeshInstance3D.new()
			var cb := CylinderMesh.new()
			cb.top_radius = 0.015
			cb.bottom_radius = 0.03
			cb.height = 1.0
			bone.mesh = cb
			bone.material_override = _plain(Color(0.12, 0.05, 0.05))
			bone.position = Vector3(side * 0.42, 0.3, 0)
			bone.rotation.z = -side * 1.05
			wing.add_child(bone)
			var mem := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(0.95, 0.8, 0.01)
			mem.mesh = pm
			mem.material_override = mat
			mem.position = Vector3(side * 0.45, 0.0, 0)
			mem.rotation.z = PI + side * 0.25
			wing.add_child(mem)
	return n
