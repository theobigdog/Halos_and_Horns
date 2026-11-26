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
const Graphics = preload("res://scripts/graphics.gd")
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
# [id, label, skin colour, hair colour]. Hair (Ted, Nov 26: it took the skin colour, so you couldn't see it):
# "" keeps the character's own painted hair; the others get a colour that stands out against that skin.
const SKINS := [
	["natural", "As drawn", "", ""], ["pale", "Pale", "#f2dcc8", ""], ["tan", "Tan", "#c98e62", ""],
	["brown", "Brown", "#8a5a3c", "#2b1a10"], ["dark", "Dark", "#5a3a28", "#141010"],
	["ghost", "Ghostly white", "#e9eef7", "#8fa2c4"], ["gold", "Gold", "#e6b84a", "#6b3410"],
	["hellred", "Hell red", "#b8281e", ""], ["ash", "Ash grey", "#6c6a70", ""], ["zombie", "Zombie green", "#7fa35a", ""],
	["ocean", "Ocean blue", "#4a7fc2", "#eef5ff"], ["violet", "Violet", "#8a55c0", ""], ["coal", "Coal black", "#2a2426", ""],
	["sulfur", "Sulfur yellow", "#c9b33a", ""], ["blood", "Blood", "#6e0f12", ""], ["rose", "Rose", "#e7a5a0", ""],
]
# The KayKit textures are a palette of 8 x 4 swatches; on the adventurers' heads the hair is swatch (1, 0).
const SWATCHES := Vector2(8, 4)
const HAIR_SWATCH := Vector2(1, 0)
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
static var _skin_cell := {}        # texture path -> the palette swatch the skin is painted in


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
	var hair_col := ""
	for s in SKINS:
		if s[0] == outfit["skin"]:
			skin_col = s[2]
			hair_col = s[3]
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
		_recolor(mi, skin_col, role, p.name.ends_with("_Eyes"), hair_col if p.name.contains("_Head") else "", p.name.contains("_Head"))
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
	var hatted := head_c.begins_with("Skeleton") and not head.ends_with(":bare") and not _hat(head_c).is_empty()
	head_att.add_child(_crown(outfit["crown"], role, hatted, head_hull(head_c, hatted)))
	var wings := _wings(role, outfit["skin"])
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


# Every body part's surface (Ted, Nov 26: "the quality and resolution of the horns greatly exceeds the other
# details of the demon skins... bring the rest of the skins (both demon and angel) up to speed without
# sacrificing too much in the way of performance"). The KayKit parts are painted from a palette of flat
# swatches; one shader adds the fine detail each kind of surface has, worked out from the swatch's colour:
# steel gets a brushed sheen and scratches, gold trim shines, cloth a fine weave, leather a grain, skin a
# soft sheen, hair strands, and bone pores and hairline cracks. No extra triangles: just shading, with
# relief from screen-space bump, and it fades out with distance so nothing shimmers.
# The detail follows each part's REST pose (CUSTOM0, added by _with_rest), so it doesn't swim as limbs move.
# It also does the skin (and hair) recolouring: only the skin's own swatch, keeping each texel's shade.
static func _recolor(mi: MeshInstance3D, skin_hex: String, role: String, eyes: bool, hair_hex := "", head := false) -> void:
	if eyes:
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(1.0, 0.25, 0.1) if role == "demon" else Color(0.6, 0.85, 1.0)
		glow.emission_enabled = true
		glow.emission = glow.albedo_color
		glow.emission_energy_multiplier = 3.0
		mi.material_override = glow
		return
	var src := mi.mesh.surface_get_material(0) as StandardMaterial3D if mi.mesh else null
	if src == null or src.albedo_texture == null:
		return
	mi.mesh = _with_rest(mi.mesh)
	var tex := src.albedo_texture
	var bony := tex.resource_path.contains("skeleton")
	var hairy := head and not bony
	var key := "%s|%s|%s|%s" % [tex.resource_path, skin_hex, hair_hex, hairy]
	if _surface_mats.has(key):
		mi.material_override = _surface_mats[key]
		return
	var sm := ShaderMaterial.new()
	sm.shader = _skin_shader()
	sm.set_shader_parameter("tex", tex)
	var ref := skin_ref(tex)
	sm.set_shader_parameter("ref_v", ref.v)
	sm.set_shader_parameter("bony", bony)
	# Only the skin's own swatch (Nov 26: matching by hue also caught the hair, boots and leather straps)
	sm.set_shader_parameter("skin_cell", _skin_cell.get(tex.resource_path, Vector2(0, 0)))
	if skin_hex != "":
		var c := Color(skin_hex)
		sm.set_shader_parameter("recolor_skin", true)
		sm.set_shader_parameter("skin_new", Vector3(c.r, c.g, c.b))
	if hairy:
		sm.set_shader_parameter("hair_cell", HAIR_SWATCH)
		if hair_hex != "":
			var hc := Color(hair_hex)
			sm.set_shader_parameter("recolor_hair", true)
			sm.set_shader_parameter("hair_v", maxf(_swatch_colour(tex, HAIR_SWATCH).v, 0.05))
			sm.set_shader_parameter("hair_new", Vector3(hc.r, hc.g, hc.b))
	_surface_mats[key] = sm
	mi.material_override = sm


static var _shader: Shader
static var _surface_mats := {}
static var _rest_meshes := {}


# A copy of a part's mesh with each vertex's own (rest pose) position in CUSTOM0, for the detail to follow.
static func _with_rest(mesh: Mesh) -> Mesh:
	if mesh == null or not (mesh is ArrayMesh):
		return mesh
	var id := mesh.get_instance_id()
	if _rest_meshes.has(id):
		return _rest_meshes[id]
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var custom := PackedFloat32Array()
		custom.resize(verts.size() * 4)
		for i in verts.size():
			custom[i * 4] = verts[i].x
			custom[i * 4 + 1] = verts[i].y
			custom[i * 4 + 2] = verts[i].z
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		var flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		var bones = arrays[Mesh.ARRAY_BONES]
		if bones != null and verts.size() > 0 and (bones as PackedInt32Array).size() == verts.size() * 8:
			flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		out.surface_set_material(s, mesh.surface_get_material(s))
	_rest_meshes[id] = out
	return out


static func _skin_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
uniform sampler2D tex : filter_nearest;   // (raw sRGB: compared as the artist painted it)
uniform bool recolor_skin = false;
uniform float ref_v = 1.0;
uniform vec3 skin_new;
uniform vec2 skin_cell = vec2(-9.0);
uniform bool bony = false;                // a skeleton: its "skin" swatch is bone
uniform vec2 hair_cell = vec2(-9.0);
uniform bool recolor_hair = false;
uniform float hair_v = 1.0;
uniform vec3 hair_new;
varying vec3 rp;
void vertex() { rp = CUSTOM0.xyz; }
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
float h3(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
float n3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void fragment() {
	vec3 c = texture(tex, UV).rgb;
	vec3 h = rgb2hsv(c);
	// which palette swatch this texel is in
	vec2 cell = floor(fract(UV) * vec2(8.0, 4.0));
	bool is_skin = distance(cell, skin_cell) < 0.5;
	bool is_hair = distance(cell, hair_cell) < 0.5;
	if (is_skin && recolor_skin) {
		c = skin_new * clamp(h.z / max(ref_v, 0.01), 0.0, 1.3);
	} else if (is_hair && recolor_hair) {
		c = hair_new * clamp(h.z / hair_v, 0.35, 1.4);
	}
	// detail fades out where it would be smaller than a pixel or so
	float near = 1.0 - smoothstep(0.004, 0.02, length(fwidth(rp)));
	float n1 = n3(rp * 22.0);
	float n2 = n3(rp * 95.0);
	vec3 col = c;
	float height = 0.0;
	float rough = 0.78;
	float metal = 0.0;
	float spec = 0.45;
	float rim = 0.0;
	if (is_skin && bony) {
		// bone: porous, mottled, with hairline cracks
		float crack = 1.0 - smoothstep(0.0, 0.035, abs(n3(rp * vec3(16.0, 26.0, 16.0)) - 0.5));
		crack *= smoothstep(0.5, 0.65, n3(rp * 5.0 + 7.0));
		col *= (0.92 + 0.12 * n1) * (1.0 - crack * 0.32 * near) * (1.0 - 0.08 * n2 * near);
		height = (n2 * 0.004 - crack * 0.012) * near;
		rough = 0.66;
		spec = 0.45;
	} else if (is_skin) {
		col *= 0.96 + 0.06 * n1;
		height = n2 * 0.0012 * near;
		rough = 0.55;
		spec = 0.4;
		rim = 0.25;
	} else if (is_hair) {
		float strand = 0.5 + 0.5 * sin(rp.x * 320.0 + rp.z * 90.0 + n3(rp * vec3(10.0, 40.0, 10.0)) * 3.0);
		col *= mix(1.0, 0.92 + 0.12 * strand, near) * (0.95 + 0.08 * n1);
		height = strand * 0.0012 * near;
		rough = 0.5;
		spec = 0.55;
	} else if (h.y < 0.2 && h.z > 0.28 && h.z < 0.9) {
		// steel: brushed, with the odd scratch catching the light
		float brushed = n3(rp * vec3(160.0, 6.0, 160.0));
		float scratch = smoothstep(0.93, 1.0, n3(rp * vec3(70.0, 7.0, 70.0) + n1 * 2.0));
		col *= 1.05 + (0.12 * brushed + scratch * 0.3) * near;
		metal = 0.3;
		rough = 0.3 + 0.14 * n1;
		spec = 0.7;
		height = (brushed * 0.0012 - scratch * 0.002) * near;
	} else if (h.x > 0.08 && h.x < 0.17 && h.y > 0.45 && h.z > 0.6) {
		// gold trim
		col *= 0.95 + 0.08 * n2;
		metal = 0.8;
		rough = 0.26 + 0.1 * n1;
		spec = 0.8;
	} else if (h.x < 0.11 && h.y > 0.25 && h.z < 0.72 && h.z > 0.16) {
		// leather: a pebbly grain, worn lighter in places
		float g = n3(rp * 180.0);
		col *= (0.92 + 0.14 * n1) * (1.0 - 0.12 * g * near);
		height = g * 0.0025 * near;
		rough = 0.62;
		spec = 0.35;
	} else if (h.z > 0.12) {
		// cloth: a fine weave
		float wx = sin((rp.x + rp.z) * 230.0);
		float wy = sin(rp.y * 230.0);
		float weave = 0.5 + 0.25 * (wx + wy) * sign(wx * wy);
		col *= 1.0 + (weave - 0.5) * 0.16 * near;
		col *= 0.95 + 0.08 * n1;
		height = weave * 0.0012 * near;
		rough = 0.92;
		spec = 0.25;
		rim = 0.18;
	}
	ALBEDO = to_linear(col);
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = spec;
	RIM = rim;
	RIM_TINT = 0.5;
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec3 r1 = cross(dpy, NORMAL);
	vec3 r2 = cross(NORMAL, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dFdx(height) * r1 + dFdy(height) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
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
		_skin_cell[key] = Vector2(0, 0)
		for c in SOURCES:
			for p in _parts(c, ["_Head"]):
				var m := (p as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
				if m == null or m.albedo_texture == null or m.albedo_texture.resource_path != key:
					continue
				for uv in (p as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]:
					var f := Vector2(fposmod(uv.x, 1.0), fposmod(uv.y, 1.0))
					var px := Vector2i(clampi(int(f.x * img.get_width()), 0, img.get_width() - 1),
							clampi(int(f.y * img.get_height()), 0, img.get_height() - 1))
					if img.get_pixelv(px).is_equal_approx(best):
						_skin_cell[key] = (f * SWATCHES).floor()
	_skin_ref[key] = best
	return best


# The colour in the middle of one palette swatch.
static func _swatch_colour(tex: Texture2D, cell: Vector2) -> Color:
	var img := tex.get_image()
	if img == null:
		return Color(0.5, 0.4, 0.3)
	if img.is_compressed():
		img.decompress()
	var px := ((cell + Vector2(0.4, 0.45)) / SWATCHES * Vector2(img.get_width(), img.get_height())).floor()
	return img.get_pixelv(Vector2i(px))


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


# The points of a head (and its hat, if worn) in the head bone's space, so horns can grow out of its
# surface (Ted, Nov 26: they floated above the skulls, which top out at 0.92, not the 1.15 they assumed).
static var _hulls := {}


static func head_hull(c: String, hat: bool) -> PackedVector3Array:
	var key := "%s_%s" % [c, hat]
	if _hulls.has(key):
		return _hulls[key]
	var out := PackedVector3Array()
	var src := _source(c)
	var sk := _skeleton_of(src) if src else null
	if sk != null and sk.find_bone("head") >= 0:
		var to_bone := sk.get_bone_global_rest(sk.find_bone("head")).affine_inverse()
		for p in _parts(c, ["_Head", "_Head_Hooded", "_Skull"]):
			var mi := p as MeshInstance3D
			for v in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				out.append(to_bone * (mi.transform * v))
		if hat and not out.is_empty():
			# Only the part of a hat that hugs the head (a helmet's dome, a hood): a brim or a helmet's own
			# spikes reach far out, and horns rooted there stood well away from the head (Ted, Nov 26).
			var box := AABB(out[0], Vector3.ZERO)
			for v in out:
				box = box.expand(v)
			var centre := box.get_center()
			var reach := box.size.length() * 0.5 * 1.15
			for m in _hat(c):
				var mi := m as MeshInstance3D
				for v in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					var p: Vector3 = mi.transform * v
					if p.distance_to(centre) < reach:
						out.append(p)
	_hulls[key] = out
	return out


# (in the head bone's space, KayKit units: the top of the head is about 1.1 up from the bone)
static func _crown(kind: String, role: String, has_hat: bool, hull := PackedVector3Array()) -> Node3D:
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
			# swept, twisted, ridged horns like the shrine's, each kind its own shape and colouring (horn_crowns.gd),
			# their roots sunk into the skull (or helmet)
			n.add_child(HornCrowns.make(kind, top, hull))
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
static var _wing_mats := {}


static func _wings(role: String, skin := "natural") -> Node3D:
	var n := Node3D.new()
	n.name = "Wings"
	for side in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.name = "L" if side < 0 else "R"
		wing.position = Vector3(0.14 * side, 1.12, -0.36)
		n.add_child(wing)
		if role == "angel":
			_angel_wing(wing, side, skin)
		else:
			_demon_wing(wing, side)
	return n


# Angel wings (Ted, Nov 26: "the feathers are few, and they only kinda look like feathers. They should be
# thicker, more clearly feathers, maybe even multicolored depending on the angel skin"). Five layers, like a
# real wing seen from behind: long primaries fanning from the wrist, secondaries along the arm, and three
# rows of coverts (greater, lesser, and little marginal ones along the leading edge) overlapping their
# bases. Every feather of a wing is one mesh (one draw call per wing), and the feather shader draws the
# quill, the barbs, the odd split in the vane and a downy base. Each skin has its own feather colours.
# Per vertex COLOR: r = which layer (0 coverts .. 1 primaries), g = a per-feather random number.
const WING_COLOURS := {
	# skin: [main, tip, quill]
	"natural": ["#fffdf6", "#ecc66e", "#c9a45a"], "pale": ["#fffdf8", "#e6d3a8", "#c8b48c"],
	"tan": ["#fbf6ee", "#b98c5e", "#9a7550"], "brown": ["#f6efe2", "#7c5a3a", "#6a4c30"],
	"dark": ["#f4f5f8", "#4c5670", "#3c4458"], "rose": ["#fff4f5", "#e488a0", "#c76c84"],
	"ghost": ["#f0f4ff", "#93aee0", "#7f97c4"], "gold": ["#fff3cf", "#d8941a", "#b07418"],
	"ocean": ["#f3f8ff", "#3b7bd0", "#2c5ea4"],
}

const FEATHER_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 main_col : source_color;
uniform vec3 tip_col : source_color;
uniform vec3 quill_col : source_color;
varying vec3 vc;
void vertex() { vc = COLOR.rgb; }
void fragment() {
	float x = UV.x;            // -1 .. 1 across the feather
	float y = UV.y;            // 0 at the root .. 1 at the tip
	float ax = abs(x);
	float tier = vc.r;
	float seed = vc.g;
	// a few splits in the vane, where the barbs have come apart
	float gy = fract(y * 5.0 + seed * 7.3 + step(0.0, x) * 0.41);
	if (ax > 0.5 && gy < 0.05 * (ax - 0.5) * 2.0 && y > 0.25) {
		discard;
	}
	// barbs: fine lines slanting out from the quill toward the tip
	float barb = fract(y * 16.0 - ax * 2.5 + seed * 3.0);
	float b = smoothstep(0.0, 0.45, barb) * smoothstep(1.0, 0.7, barb);
	float tipw = smoothstep(0.3, 1.0, y) * mix(0.25, 1.0, tier);
	vec3 col = mix(main_col, tip_col, tipw);
	// the flight feathers get faint bars across them
	col *= 1.0 - tier * 0.07 * smoothstep(0.3, 0.7, sin(y * 22.0 + seed * 6.0));
	col *= 0.9 + 0.1 * b;
	col *= mix(1.0, 0.86, smoothstep(0.55, 1.0, ax));   // the edges a touch darker, so feathers separate
	// the quill: a line down the middle, thinning toward the tip
	float q = 1.0 - smoothstep(0.035, 0.075, ax / max(1.0 - 0.75 * y, 0.05));
	col = mix(col, quill_col, q * 0.85);
	// downy, fluffy base
	col = mix(col, main_col, smoothstep(0.14, 0.0, y) * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.78;
	SPECULAR = 0.3;
	RIM = 0.45;
	RIM_TINT = 0.4;
	BACKLIGHT = col * 0.3;
	EMISSION = main_col * 0.06;   // a faint holy glow
	// a little relief for the barbs and the quill
	float height = b * 0.0012 + q * 0.002;
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec3 r1 = cross(dpy, NORMAL);
	vec3 r2 = cross(NORMAL, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dFdx(height) * r1 + dFdy(height) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
}
"""


static func _angel_mat(skin: String) -> ShaderMaterial:
	var key := "angel_" + skin
	if not _wing_mats.has(key):
		var cols: Array = WING_COLOURS.get(skin, WING_COLOURS["natural"])
		if not _wing_mats.has("feather_shader"):
			var sh := Shader.new()
			sh.code = FEATHER_SHADER
			_wing_mats["feather_shader"] = sh
		var m := ShaderMaterial.new()
		m.shader = _wing_mats["feather_shader"]
		m.set_shader_parameter("main_col", Color(cols[0]))
		m.set_shader_parameter("tip_col", Color(cols[1]))
		m.set_shader_parameter("quill_col", Color(cols[2]))
		_wing_mats[key] = m
	return _wing_mats[key]


# One feather's triangles, in its own space: the vane reaching up +Y (0..1), -1..1 across (x), cupped and
# with a raised quill, a narrow root and a rounded tip. [position, uv] per vertex, three per triangle.
static func _feather_tris(rows: int) -> Array:
	var cols := [-1.0, -0.5, 0.0, 0.5, 1.0]
	var grid := []
	for i in rows + 1:
		var t := 1.0 - pow(1.0 - float(i) / rows, 1.3)   # (rows closer together at the tip, to round it)
		var w := 0.5 * (0.4 + 0.6 * smoothstep(0.0, 0.22, t)) * sqrt(maxf(0.0, 1.0 - pow((t - 0.5) / 0.5, 6.0) * (1.0 if t > 0.5 else 0.0)))
		var row := []
		for x: float in cols:
			var z := -0.09 * w * x * x + 0.025 * (1.0 - absf(x)) * (1.0 - t)   # cupped, the quill standing proud
			row.append([Vector3(x * w, t, z), Vector2(x, t)])
		grid.append(row)
	var out := []
	for i in rows:
		for j in cols.size() - 1:
			var a: Array = grid[i][j]
			var b: Array = grid[i][j + 1]
			var c: Array = grid[i + 1][j + 1]
			var d: Array = grid[i + 1][j]
			out.append_array([a, b, c, a, c, d])
	return out


# The whole wing as one mesh (cached: every angel shares it). Right wing reaches +X; the left is mirrored.
static func _angel_wing_mesh(side: float) -> ArrayMesh:
	var key := "angel_mesh_%d_%d" % [int(side), Graphics.quality]
	if _wing_mats.has(key):
		return _wing_mats[key]
	var tris := _feather_tris([6, 8, 10][Graphics.quality])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shoulder := Vector3.ZERO
	var elbow := Vector3(0.42, 0.3, 0)
	var wrist := Vector3(0.95, 0.38, 0)
	var feathers := []   # [at, angle, length, width, depth, layer]
	# Primaries: from the wrist, fanning from out-and-up to straight down, the outer ones longest
	for i in 10:
		var k := float(i) / 9.0
		feathers.append([wrist.lerp(elbow, k * 0.45) + Vector3(0, -0.02 * k, 0), lerpf(-1.25, -2.65, k),
				lerpf(0.86, 0.66, absf(k - 0.25) * 1.3), 0.25, -0.004 * i, 1.0])
	# Secondaries: along the arm, hanging down and a little out
	for i in 11:
		var k := float(i) / 10.0
		feathers.append([elbow.lerp(shoulder, k * 0.9), lerpf(-2.7, -3.02, k), lerpf(0.66, 0.46, k), 0.25,
				-0.045 - 0.003 * i, 0.7])
	# Coverts, overlapping the bases so no gaps show: greater, lesser, then little marginals on the edge
	for row in 3:
		var n: int = [12, 12, 9][row]
		for i in n:
			var k := float(i) / (n - 1)
			var along := shoulder.lerp(wrist, k * [1.0, 0.95, 0.9][row])
			var lift: float = [-0.02, 0.07, 0.13][row]
			feathers.append([along + Vector3(0, lift, 0), lerpf(-2.7, -2.15, k), [0.36, 0.24, 0.14][row] * lerpf(1.0, 0.85, k),
					[0.21, 0.19, 0.16][row], -0.07 - 0.012 * row - 0.002 * i, [0.35, 0.15, 0.0][row]])
	var idx := 0
	for f in feathers:
		var basis := Basis(Vector3.BACK, f[1] * side).scaled(Vector3(f[3], f[2], f[3]))
		var at: Vector3 = f[0]
		var origin := Vector3(at.x * side, at.y, at.z + f[4])
		var seed := fposmod(sin(idx * 12.9898) * 43758.5453, 1.0)
		idx += 1
		for v in tris:
			var p: Vector3 = basis * (v[0] as Vector3)
			st.set_color(Color(f[5], seed, 0.0))
			st.set_uv(v[1])
			st.add_vertex(origin + p)
	st.generate_normals()
	var mesh := st.commit()
	_wing_mats[key] = mesh
	return mesh


static func _angel_wing(wing: Node3D, side: float, skin: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Feathers"
	mi.mesh = _angel_wing_mesh(side)
	mi.material_override = _angel_mat(skin)
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
