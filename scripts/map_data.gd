# Maps are plain data: a list of pieces (what, where, how big, which way, what
# colour) and nothing else. No code, so a map someone sends you can't do anything
# but be a map. Everything read from a file goes through clean() first: unknown
# piece types are dropped, numbers are clamped, and the whole thing is size-capped.
#
# Format (JSON):
# {
#   "format": 1, "name": "...", "author": "...",
#   "size": 28,             # half the width of the play area (walls go around it)
#   "ceiling": 24,          # how high anyone can fly
#   "ground_color": "#598c4c", "wall_color": "#807a85",
#   "random_props": 45,     # props scattered at random each round, on top of placed ones
#   "pieces": [ {"type": "block", "pos": [x, y, z], "size": [x, y, z], "rot": [x, y, z] (degrees), "color": "#rrggbb"}, ... ]
#   (each piece may also have an "id", used when building together online)
# }
extends RefCounted

const PropLib = preload("res://scripts/prop_library.gd")
const GroundBlock = preload("res://scripts/ground_block.gd")
const HollowBuildings = preload("res://scripts/hollow_buildings.gd")
const Models = preload("res://scripts/models.gd")

const FORMAT := 1
const BUILT_IN := ["res://maps/playground.json"]
const USER_DIR := "user://maps"
const MAX_BYTES := 2 * 1024 * 1024
const MAX_PIECES := 5000
const MAX_COORD := 500.0
const MAX_REPEAT := 100
const MAX_GRID := 400            # copies in one floor, at most

# Piece types and what each one needs.
#   block / cylinder: solid shapes (size, rot, color)
#   prop: a real, possessable prop placed by hand ("prop": type, rot)
#   model: a solid structure from the model catalog ("model": id, rot, "size": scale on each axis, 1 = normal,
#          "repeat": how many copies end to end, for walls and fences dragged longer)
#   bouncy_super: a bouncy pad that throws you much higher
#   ice: a slippery sheet ("size": x and z; anyone running on it can slip and fall)
#   light: a lamp (color, "range" in metres, "energy" brightness; "spot": true + "angle" for a spotlight)
#   (map settings also include "time": "day", "dusk" or "night", "weather" (WEATHERS) and "cycle":
#   minutes for a day/night cycle, 0 = off)
#   bouncy / bouncy_once, shrine, angel_spawn, demon_spawn: special pieces (pos, rot)
#   sidewalk: a raised concrete slab ("size"); window: a picture for a window ("size" x/y, "look" 0..4)
const TYPES := ["block", "cylinder", "prop", "model", "light", "ice", "sidewalk", "window", "ground", "building", "bouncy", "bouncy_once", "bouncy_super", "shrine", "angel_spawn", "demon_spawn"]
const SHAPED := ["block", "cylinder"]


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > MAX_BYTES:
		return {}
	return from_text(f.get_as_text())


static func from_text(text: String) -> Dictionary:
	if text.length() > MAX_BYTES:
		return {}
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return clean(parsed)


static func to_text(map: Dictionary) -> String:
	return JSON.stringify(clean(map), " ")


static func save_file(map: Dictionary, path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(to_text(map))
	return true


# A shared maps folder (Ted, Nov 25): any folder on this PC, e.g. one OneDrive / Dropbox / Google Drive
# keeps in sync between friends' computers. Its maps show up next to your own, and Creative can save there.
# "" = none. (Settings & controls; main.gd keeps it in the settings file.)
static var shared_dir := ""


static func has_shared() -> bool:
	return shared_dir != "" and DirAccess.dir_exists_absolute(shared_dir)


# Is this a map file we may save over (our own folder or the shared one), not a built-in one?
static func is_saveable(path: String) -> bool:
	return path.begins_with(USER_DIR) or is_shared(path)


static func is_shared(path: String) -> bool:
	return shared_dir != "" and path != "" and path.begins_with(shared_dir)


# Every map we can play: built-in ones first, then the player's own, then the shared folder's.
static func list_maps() -> Array:
	var out := []
	for p in BUILT_IN:
		var m := load_file(p)
		if not m.is_empty():
			out.append({"path": p, "name": m["name"], "built_in": true})
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var d := DirAccess.open(USER_DIR)
	if d:
		var files := Array(d.get_files())
		files.sort()
		for fname in files:
			if fname.ends_with(".json"):
				var m := load_file(USER_DIR + "/" + fname)
				if not m.is_empty():
					out.append({"path": USER_DIR + "/" + fname, "name": m["name"], "built_in": false, "shared": false})
	if has_shared():
		var sd := DirAccess.open(shared_dir)
		if sd:
			var sfiles := Array(sd.get_files())
			sfiles.sort()
			for fname in sfiles:
				if fname.ends_with(".json"):
					var m := load_file(shared_dir.path_join(fname))
					if not m.is_empty():
						out.append({"path": shared_dir.path_join(fname), "name": m["name"], "built_in": false, "shared": true})
	return out


static func user_path_for(map_name: String, shared := false) -> String:
	var safe := ""
	for ch in map_name.to_lower():
		safe += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	safe = safe.strip_edges().substr(0, 40)
	var dir := shared_dir if shared and has_shared() else USER_DIR
	return dir.path_join("%s.json" % (safe if safe.replace("_", "") != "" else "map"))


static func empty_map(map_name := "New map") -> Dictionary:
	return clean({"name": map_name, "size": 28, "random_props": 0, "pieces": [
		{"type": "angel_spawn", "pos": [0, 0.1, -20]},
		{"type": "demon_spawn", "pos": [0, 0.1, 0]},
	]})


# ---------------- checking ----------------

static func _num(v, lo: float, hi: float, default: float) -> float:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return default
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return default
	return clampf(f, lo, hi)


static func _vec(v, lo: float, hi: float, default: Vector3) -> Vector3:
	if typeof(v) != TYPE_ARRAY or v.size() != 3:
		return default
	return Vector3(_num(v[0], lo, hi, default.x), _num(v[1], lo, hi, default.y), _num(v[2], lo, hi, default.z))


static func _color(v, default: String) -> String:
	if typeof(v) == TYPE_STRING and Color.html_is_valid(v):
		return "#" + Color.html(v).to_html(false)
	return default


static func _text(v, default: String, max_len: int) -> String:
	if typeof(v) != TYPE_STRING:
		return default
	var out := ""
	for ch in v.substr(0, max_len):
		if ch.unicode_at(0) >= 32:
			out += ch
	out = out.strip_edges()
	return out if out != "" else default


static func clean(raw: Dictionary) -> Dictionary:
	var m := {
		"format": FORMAT,
		"name": _text(raw.get("name"), "Untitled map", 40),
		"author": _text(raw.get("author"), "", 40),
		"size": _num(raw.get("size"), 10.0, 200.0, 28.0),
		"ceiling": _num(raw.get("ceiling"), 6.0, 120.0, 24.0),
		"ground_color": _color(raw.get("ground_color"), "#598c4c"),
		"wall_color": _color(raw.get("wall_color"), "#807a85"),
		"random_props": int(_num(raw.get("random_props"), 0, 300, 0)),
		"time": raw.get("time") if raw.get("time") in TIMES else "day",
		"weather": raw.get("weather") if raw.get("weather") in WEATHERS else "sunny_cloudy",
		"backdrop": raw.get("backdrop") if raw.get("backdrop") in BACKDROPS else "none",   # scenery past the walls
		"cycle": int(raw.get("cycle", 0)) if typeof(raw.get("cycle")) in [TYPE_INT, TYPE_FLOAT] and int(raw.get("cycle")) in CYCLES else 0,
		"pieces": [],
	}
	var pieces = raw.get("pieces", [])
	if typeof(pieces) != TYPE_ARRAY:
		pieces = []
	var shrines := 0
	for p in pieces.slice(0, MAX_PIECES):
		if typeof(p) != TYPE_DICTIONARY or not p.get("type") in TYPES:
			continue
		var t: String = p["type"]
		if t == "prop" and typeof(p.get("prop")) == TYPE_STRING and not PropLib.TYPES.has(p["prop"]) and Models.has(p["prop"]):
			p = p.duplicate()   # (a prop that became a structure, like the fire hydrant and dumpster: Nov 25)
			p["type"] = "model"
			p["model"] = p["prop"]
			t = "model"
		var c := {"type": t, "pos": _arr(_vec(p.get("pos"), -MAX_COORD, MAX_COORD, Vector3.ZERO))}
		var pid := _id(p.get("id"))
		if pid != "":
			c["id"] = pid
		var grp = p.get("group")
		if typeof(grp) == TYPE_STRING and grp.length() > 0 and grp.length() <= 24 and grp.is_valid_identifier():
			c["group"] = grp   # pieces grouped together in Creative (selected and changed as one)
		var rot := _vec(p.get("rot"), -360.0, 360.0, Vector3.ZERO)
		if rot != Vector3.ZERO:
			c["rot"] = _arr(rot)
		if t in SHAPED:
			c["size"] = _arr(_vec(p.get("size"), 0.05, 400.0, Vector3.ONE))
			c["color"] = _color(p.get("color"), "#a09080")
		elif t == "ground":   # (Sara, Nov 25: grass, dirt, gravel, landscaping blocks)
			c["size"] = _arr(_vec(p.get("size"), 0.1, 200.0, Vector3(4, 0.3, 4)))
			c["look"] = int(_num(p.get("look"), 0.0, float(GroundBlock.KINDS.size() - 1), 0.0))
		elif t == "building":   # (Sara, Nov 25: buildings you can walk into)
			if not p.get("kind") in HollowBuildings.KINDS:
				continue
			c["kind"] = p["kind"]
			c["look"] = int(_num(p.get("look"), 0.0, 3.0, 0.0))
		elif t == "sidewalk":
			var ssz := _vec(p.get("size"), 0.3, 100.0, Vector3(2, 0.18, 6))
			c["size"] = _arr(Vector3(ssz.x, clampf(ssz.y, 0.05, 0.6), ssz.z))
		elif t == "window":
			var wsz := _vec(p.get("size"), 0.2, 12.0, Vector3(1, 1.4, 0.02))
			c["size"] = _arr(Vector3(wsz.x, wsz.y, 0.02))
			c["look"] = int(_num(p.get("look"), 0.0, 4.0, 0.0))
		elif t == "ice":
			var isz := _vec(p.get("size"), 0.5, 100.0, Vector3(4, 0.06, 4))
			c["size"] = _arr(Vector3(isz.x, 0.06, isz.z))   # a slippery sheet: always thin
		elif t in ["bouncy", "bouncy_once", "bouncy_super"]:
			var pad_look := int(_num(p.get("look"), 0.0, 4.0, 0.0))
			if pad_look > 0:
				c["look"] = pad_look   # its colour (bouncy.gd SKINS)
		elif t == "light":
			c["color"] = _color(p.get("color"), "#ffd9a0")
			c["range"] = snappedf(_num(p.get("range"), 1.0, 40.0, 8.0), 0.1)
			c["energy"] = snappedf(_num(p.get("energy"), 0.1, 8.0, 1.5), 0.05)
			if p.get("spot", false) == true:
				c["spot"] = true   # a spotlight: shines one way (its rotation), in a cone this wide
				c["angle"] = snappedf(_num(p.get("angle"), 5.0, 85.0, 35.0), 0.5)
			if p.get("always", false) == true:
				c["always"] = true   # on all the time (otherwise it comes on at dusk and goes off at dawn)
			var fl := snappedf(_num(p.get("flicker"), 0.0, 20.0, 0.0), 0.1)
			if fl > 0.0:
				c["flicker"] = fl    # flickers this many times a second
		elif t == "model":
			if typeof(p.get("model")) != TYPE_STRING or not Models.has(p["model"]):
				continue
			c["model"] = p["model"]
			var sc := _vec(p.get("size"), 0.1, 10.0, Vector3.ONE)
			if sc != Vector3.ONE:
				c["size"] = _arr(sc)
			var rep := int(_num(p.get("repeat"), 1, MAX_REPEAT, 1))
			if rep > 1:
				c["repeat"] = rep   # copies end to end (a wall dragged longer)
			if p.get("lights", false) == true and Models.is_car(c["model"]):
				c["lights"] = true   # headlights and tail lights on
			if Models.is_rug(c["model"]) and typeof(p.get("color")) == TYPE_STRING:
				c["color"] = _color(p.get("color"), "#b03030")   # a rug in any colour (Models.recolor)
			var look := int(_num(p.get("look"), 0, LOOKS - 1, 0))
			if look > 0:
				c["look"] = look   # weathered (0), clean, mossy, charred... (models.gd LOOK_NAMES)
			var rep2 := int(_num(p.get("repeat2"), 1, MAX_REPEAT, 1))
			if rep2 > 1 and Models.is_flat(c["model"]):
				c["repeat2"] = mini(rep2, MAX_GRID / maxi(rep, 1))   # and side by side (a floor pulled out)
		elif t == "prop":
			if not PropLib.TYPES.has(p.get("prop")):
				continue
			c["prop"] = p["prop"]
			var psc := PropLib.snap_scale(_num(p.get("scale"), PropLib.SCALE_MIN, PropLib.SCALE_MAX, 1.0))
			if not is_equal_approx(psc, 1.0):
				c["scale"] = psc   # sized evenly (PropLib.scaled)
		elif t == "shrine":
			shrines += 1
			if shrines > 1:
				continue   # one shrine per map, at most
		m["pieces"].append(c)
	# Every map needs somewhere for each side to start.
	var has := func(kind): return m["pieces"].any(func(q): return q["type"] == kind)
	if not has.call("angel_spawn"):
		m["pieces"].append({"type": "angel_spawn", "pos": [0, 0.1, -m["size"] + 4.0]})
	if not has.call("demon_spawn"):
		m["pieces"].append({"type": "demon_spawn", "pos": [0, 0.1, 0]})
	return m


# One piece, checked the same way a loaded map's pieces are. {} if it isn't a valid piece.
static func clean_piece(p) -> Dictionary:
	if typeof(p) != TYPE_DICTIONARY:
		return {}
	var m := clean({"pieces": [p]})
	for q in m["pieces"]:
		if q["type"] == p.get("type") and q.get("id", "") == _id(p.get("id")):
			return q
	return {}


const SETTING_KEYS := ["name", "author", "size", "ceiling", "ground_color", "wall_color", "random_props", "time", "weather", "cycle", "backdrop"]
const TIMES := ["day", "dusk", "night"]
const WEATHERS := ["clear", "sunny_cloudy", "cloudy", "fog", "snow", "rain"]
const BACKDROPS := ["none", "hills", "ocean", "mountains", "city"]   # (backdrop.gd)
const CYCLES := [0, 5, 10, 20, 30]    # minutes for a whole day/night cycle (0: off)
const LOOKS := 8                      # a structure's look: models.gd LOOK_NAMES


# One map setting, checked. null if the key isn't a setting.
static func clean_setting(key, value):
	if not key in SETTING_KEYS:
		return null
	return clean({key: value, "pieces": []})[key]


# A piece's id (for building together online): up to 24 letters, digits, - and _. Anything else: no id.
static func _id(v) -> String:
	if typeof(v) != TYPE_STRING or v.length() == 0 or v.length() > 24:
		return ""
	for ch in v:
		if not ((ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "-" or ch == "_"):
			return ""
	return v


# Gives every piece a unique id (keeping the ones it has), so pieces can be named in edits sent online.
static func ensure_ids(map: Dictionary, prefix := "m") -> void:
	var seen := {}
	var n := 0
	for p in map["pieces"]:
		var pid: String = p.get("id", "")
		while pid == "" or seen.has(pid):
			n += 1
			pid = "%s%d" % [prefix, n]
		p["id"] = pid
		seen[pid] = true


static func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


static func vec(a) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func rot_rad(piece: Dictionary) -> Vector3:
	var r: Array = piece.get("rot", [0, 0, 0])
	return Vector3(deg_to_rad(r[0]), deg_to_rad(r[1]), deg_to_rad(r[2]))


# A fingerprint, so a joiner can tell they built exactly the host's map.
static func fingerprint(map: Dictionary) -> String:
	return to_text(map).md5_text()
