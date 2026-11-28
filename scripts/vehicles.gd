# Vehicles in a chunky, soft, toy-like style (Sara, Nov 27, with a sheet of example vehicles: "adjust the ones that
# already exist to something with a similar style and add any vehicles that were not already part of halos and
# horns"). Everything is built from "soft boxes" (boxes rounded on every edge), so the bodies look moulded:
# rounded lower bodies with fender bulges, a rounded cabin with big windows, big round headlights in chrome rings,
# chunky grey bumpers, round tail lights and big wheels with grey hubcaps.
#   Existing (same ids, same footprints): sedan, hatchback, station wagon, taxi, police car.
#   New (catalog extras): pickup truck, motorcycle, bus, ambulance, fire truck.
# Fronts face +z, like the KayKit cars. refined_models.gd sends these ids here.
extends RefCounted

const CP = preload("res://scripts/classic_props.gd")
const RM = preload("res://scripts/refined_models.gd")

const BUILDERS := {
	"city/car_sedan": "_car", "city/car_hatchback": "_car", "city/car_stationwagon": "_car", "city/car_taxi": "_car",
	"city/car_police": "_car", "city/car_pickup": "_pickup", "city/car_motorcycle": "_motorcycle", "city/car_bus": "_bus",
	"city/car_ambulance": "_ambulance", "city/car_firetruck": "_firetruck",
}

# id: [length, wheelbase, body colour, cabin from, cabin to (0 back .. 1 front), cabin top]
const CARS := {
	"city/car_sedan": [4.2, 2.5, Color(0.78, 0.22, 0.2), 0.26, 0.66, 1.5],
	"city/car_hatchback": [3.6, 2.2, Color(0.2, 0.42, 0.85), 0.1, 0.7, 1.56],
	"city/car_stationwagon": [4.2, 2.5, Color(0.28, 0.6, 0.3), 0.08, 0.66, 1.5],
	"city/car_taxi": [4.2, 2.5, Color(0.98, 0.78, 0.18), 0.26, 0.66, 1.5],
	"city/car_police": [4.2, 2.5, Color(0.12, 0.25, 0.6), 0.26, 0.66, 1.5],
}

# Paints (Sara, Nov 28: "a preset list of different colors that appropriately color all parts"): Creative's
# Style repaints the bodywork only. Glass, tyres, chrome, bumpers, lamps and lettering stay as they are. 0 is
# the vehicle as it comes.
const PAINTS := [["Red", Color(0.78, 0.16, 0.14)], ["Blue", Color(0.16, 0.38, 0.82)], ["Green", Color(0.2, 0.55, 0.26)],
		["Yellow", Color(0.96, 0.78, 0.16)], ["Orange", Color(0.95, 0.5, 0.12)], ["Purple", Color(0.5, 0.26, 0.7)],
		["Pink", Color(0.95, 0.5, 0.68)], ["Teal", Color(0.1, 0.6, 0.62)], ["White", Color(0.94, 0.94, 0.93)],
		["Silver", Color(0.68, 0.7, 0.73)], ["Black", Color(0.1, 0.1, 0.11)], ["Brown", Color(0.42, 0.27, 0.16)]]


static func paint_names() -> Array:
	var out := ["As it comes"]
	for pt in PAINTS:
		out.append(pt[0])
	return out


# The vehicle's own colour, or the paint Creative's Style picked.
static func _paint(own: Color) -> Color:
	return own if RM.style <= 0 else PAINTS[(RM.style - 1) % PAINTS.size()][1]


static func _key(id: String) -> String:
	return "v_%s_%d" % [id, RM.style]


const GREY := Color(0.55, 0.56, 0.58)
const DARK := Color(0.12, 0.12, 0.13)
const CHROME := Color(0.82, 0.83, 0.85)


# ---------------------------------------------------------------- the soft box and friends

# A box with every edge and corner rounded (radius r), as a moulded shape: each face is a grid, its points pulled
# in to an inner box and pushed back out round the corners.
# `rake`: how far the top of its front (x) and of its back (y) lean in, in metres: a cabin with a sloping
# windscreen and rear window (Sara, Nov 28: "I don't like how the front windshields of the cars are completely
# vertical and not sloped"). The bottom stays where it is.
# `droop`: how far its top sinks toward the front end (x) and the back end (y), in metres, more and more the
# further along: a bonnet that slopes down to the nose and a boot that falls away, as on Sara's sheet of example
# vehicles (the bodies were flat-topped slabs).
static func soft_box(st: SurfaceTool, c: Vector3, s: Vector3, r: float, col: Color, bas := Basis(), n := 5, rake := Vector2.ZERO,
		droop := Vector2.ZERO) -> void:
	var h := s * 0.5
	r = minf(r, minf(h.x, minf(h.y, h.z)) - 0.001)
	var inner := h - Vector3.ONE * r
	var faces := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD], [Vector3.UP, Vector3.BACK, Vector3.RIGHT],
			[Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT], [Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]
	for f in faces:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var pts := []
		for i in n + 1:
			var row := []
			for j in n + 1:
				var p := (nrm + u * (2.0 * i / n - 1.0) + v * (2.0 * j / n - 1.0)) * h
				var q := p.clamp(-inner, inner)
				var d := p - q
				var at := q + (d.normalized() * r if d.length() > 0.0001 else Vector3.ZERO)
				if rake != Vector2.ZERO:
					var up := clampf((at.y + h.y) / (2.0 * h.y), 0.0, 1.0)
					at.z -= (rake.x if at.z > 0.0 else -rake.y) * up * absf(at.z) / h.z
				if droop != Vector2.ZERO and at.y > 0.0:
					var along := absf(at.z) / h.z
					at.y -= (droop.x if at.z > 0.0 else droop.y) * along * along * at.y / h.y
				row.append(at)
			pts.append(row)
		for i in n:
			for j in n:
				var a: Vector3 = pts[i][j]
				var b: Vector3 = pts[i + 1][j]
				var cc: Vector3 = pts[i + 1][j + 1]
				var d2: Vector3 = pts[i][j + 1]
				var out := bas * ((a + cc) * 0.5).normalized()
				CP._quad(st, c + bas * a, c + bas * b, c + bas * cc, c + bas * d2, col, out)


# A wheel (radius r, width w) at c, its outside facing along +x (side = +1) or -x: a chunky tyre and a grey hubcap.
static func wheel(st: SurfaceTool, c: Vector3, r: float, w: float, side: float, hub := GREY) -> void:
	var ax := Vector3(side, 0, 0)
	var n := 20
	var prof := [[r * 0.55, -w * 0.5], [r * 0.92, -w * 0.5], [r, -w * 0.35], [r, w * 0.35], [r * 0.92, w * 0.5], [r * 0.62, w * 0.5]]
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		for m in prof.size() - 1:
			var r0: float = prof[m][0]
			var x0: float = prof[m][1]
			var r1: float = prof[m + 1][0]
			var x1: float = prof[m + 1][1]
			var q := [c + ax * x0 + Vector3(0, sin(a0), cos(a0)) * r0, c + ax * x1 + Vector3(0, sin(a0), cos(a0)) * r1,
					c + ax * x1 + Vector3(0, sin(a1), cos(a1)) * r1, c + ax * x0 + Vector3(0, sin(a1), cos(a1)) * r0]
			var am := (a0 + a1) * 0.5
			var out := Vector3(0, sin(am), cos(am)) * (r0 + r1) * 0.5 + ax * (x0 + x1) * 2.0
			var tread := DARK.lightened(0.05 * float(k % 2)) if m == 2 else DARK
			CP._quad(st, q[0], q[1], q[2], q[3], tread, out)
	# the hubcap: a shallow grey dome on the outside, a darker centre
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var rim0 := c + ax * w * 0.5 + Vector3(0, sin(a0), cos(a0)) * r * 0.62
		var rim1 := c + ax * w * 0.5 + Vector3(0, sin(a1), cos(a1)) * r * 0.62
		var mid0 := c + ax * (w * 0.5 + 0.04) + Vector3(0, sin(a0), cos(a0)) * r * 0.35
		var mid1 := c + ax * (w * 0.5 + 0.04) + Vector3(0, sin(a1), cos(a1)) * r * 0.35
		CP._quad(st, rim0, rim1, mid1, mid0, hub.lightened(0.1), ax + Vector3(0, sin(a0), cos(a0)) * 0.6)
		CP._tri(st, c + ax * (w * 0.5 + 0.06), mid0, mid1, hub.darkened(0.25), ax)


# A round lamp (radius r) on a face pointing along `n`, with a chrome ring; the lens goes in `lens`.
static func lamp(st: SurfaceTool, lens: SurfaceTool, c: Vector3, n: Vector3, r: float) -> void:
	var x := n.cross(Vector3.UP).normalized()
	if x.length() < 0.1:
		x = Vector3.RIGHT
	var y := x.cross(n).normalized()
	var k := 16
	for i in k:
		var a0 := TAU * i / k
		var a1 := TAU * (i + 1) / k
		var d0 := x * cos(a0) + y * sin(a0)
		var d1 := x * cos(a1) + y * sin(a1)
		CP._quad(st, c + d0 * r * 1.25, c + d1 * r * 1.25, c + d1 * r + n * 0.03, c + d0 * r + n * 0.03, CHROME, n + d0 * 0.5)
		CP._tri(lens, c + n * 0.05, c + d0 * r + n * 0.03, c + d1 * r + n * 0.03, Color.WHITE, n)


# Tinted blue-grey glass like the examples' (it was a pale sky blue; the town's other glass is dark and mirror-like).
static func _toy_glass() -> StandardMaterial3D:
	if not RM._cache.has("toy_glass"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.36, 0.48, 0.57)
		m.metallic = 0.3
		m.roughness = 0.08
		m.clearcoat_enabled = true
		m.rim_enabled = true
		m.rim = 0.3
		RM._cache["toy_glass"] = m
	return RM._cache["toy_glass"]


static func _glass_quad(glass: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3) -> void:
	CP._quad(glass, a, b, c, d, Color.WHITE, out)


static func _label(root: Node3D, text: String, at: Vector3, yaw: float, size: float, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 72
	l.outline_size = 8
	l.outline_modulate = col.darkened(0.3)
	l.modulate = col
	l.pixel_size = size / 72.0
	l.position = at
	l.rotation.y = yaw
	l.shaded = true
	l.double_sided = false
	root.add_child(l)


# ---------------------------------------------------------------- cars

static func _car(root: Node3D, id: String) -> void:
	var parts := RM._cached(_key(id), func() -> Array: return _car_meshes(id))
	RM._put(root, parts[0], RM._paint(Color.WHITE, 0.28, 0.2))
	RM._put(root, parts[1], _toy_glass(), true)
	RM._put(root, parts[2], RM._paint(Color.WHITE, 0.45, 0.55), false)
	RM._put(root, parts[3], RM._paint(Color.WHITE, 0.7, 0.05))
	RM._put(root, parts[4], RM._glow(Color(1.0, 0.97, 0.85), 0.5), false)
	RM._put(root, parts[5], RM._glow(Color(0.9, 0.12, 0.08), 0.5), false)
	if id == "city/car_police":
		RM._put(root, parts[6], RM._flasher(Color(1.0, 0.08, 0.06), 0.0), false)
		RM._put(root, parts[7], RM._flasher(Color(0.12, 0.3, 1.0), 1.0), false)
		for s: float in [-1.0, 1.0]:
			_label(root, "POLICE", Vector3(s * 0.95, 0.78, 0.25), s * PI * 0.5, 0.22, Color(0.1, 0.2, 0.55))
	if id == "city/car_taxi":
		for s: float in [-1.0, 1.0]:
			_label(root, "TAXI", Vector3(0, 1.66, s * 0.13), 0.0 if s > 0.0 else PI, 0.16, Color(0.1, 0.1, 0.1))


static func _car_meshes(id: String) -> Array:
	var spec: Array = CARS[id]
	var L: float = spec[0]
	var base: float = spec[1]
	var paint: Color = _paint(spec[2])
	var c0: float = spec[3]
	var c1: float = spec[4]
	var top: float = spec[5]
	var W := 1.86
	var body := CP._begin()
	var glass := CP._begin()
	var trim := CP._begin()
	var tyres := CP._begin()
	var heads := CP._begin()
	var tails := CP._begin()
	var red := CP._begin()
	var blue := CP._begin()
	var police := id == "city/car_police"
	var white := Color(0.95, 0.95, 0.95)
	var wr := 0.38
	# the lower body, its bonnet sloping down to the nose and its boot falling away behind (hardly, on the two
	# that are square behind), and fender bulges over the wheels
	var hatch := id == "city/car_hatchback"
	var square_back := c0 <= 0.2
	soft_box(body, Vector3(0, 0.66, 0), Vector3(W, 0.6, L), 0.24, paint, Basis(), 7, Vector2.ZERO,
			Vector2(0.26 if hatch else 0.2, 0.04 if square_back else 0.13))
	for s: float in [-1.0, 1.0]:
		for wz: float in [-base * 0.5, base * 0.5]:
			soft_box(body, Vector3(s * (W * 0.5 - 0.12), 0.72, wz), Vector3(0.34, 0.38, wr * 2.3), 0.16, paint.darkened(0.04))
	if police:   # white doors on the blue
		for s: float in [-1.0, 1.0]:
			soft_box(body, Vector3(s * (W * 0.5 - 0.02), 0.68, 0.0), Vector3(0.06, 0.46, 1.35), 0.025, white)
	# the cabin: a rounded box set back, its windows set into it
	var cz0 := -L * 0.5 + L * c0
	var cz1 := -L * 0.5 + L * c1
	var cab_c := Vector3(0, (0.9 + top) * 0.5, (cz0 + cz1) * 0.5)
	var cab_s := Vector3(W * 0.86, top - 0.9 + 0.1, cz1 - cz0)
	# (the windscreen leans back 0.42 m over the cabin's height, about 30 degrees; the rear window less, and
	# hardly at all on the hatchback and the station wagon, which are square behind)
	var rake := Vector2(0.6 if hatch else 0.42, 0.1 if square_back else 0.26)
	soft_box(body, cab_c, cab_s, 0.2, white if police else paint, Basis(), 5, rake)
	var gy0 := 1.0
	var gy1 := top - 0.1
	var gx := cab_s.x * 0.5 + 0.004
	var cab_lo := cab_c.y - cab_s.y * 0.5
	# where the cabin's front and back faces are at a height (they lean)
	var front_at := func(y: float) -> float: return cz1 - rake.x * clampf((y - cab_lo) / cab_s.y, 0.0, 1.0)
	var back_at := func(y: float) -> float: return cz0 + rake.y * clampf((y - cab_lo) / cab_s.y, 0.0, 1.0)
	var f0: float = front_at.call(gy0)
	var f1: float = front_at.call(gy1)
	var b0: float = back_at.call(gy0)
	var b1: float = back_at.call(gy1)
	for s: float in [-1.0, 1.0]:   # side windows, split by a pillar, their ends following the lean
		var zm := (cz0 + cz1) * 0.5 - (rake.x - rake.y) * 0.25
		_glass_quad(glass, Vector3(s * gx, gy0, b0 + 0.2), Vector3(s * gx, gy0, zm - 0.05), Vector3(s * gx, gy1, zm - 0.05), Vector3(s * gx, gy1, b1 + 0.2), Vector3(s, 0, 0))
		_glass_quad(glass, Vector3(s * gx, gy0, zm + 0.05), Vector3(s * gx, gy0, f0 - 0.22), Vector3(s * gx, gy1, f1 - 0.2), Vector3(s * gx, gy1, zm + 0.05), Vector3(s, 0, 0))
	var lean_f := Vector3(0, rake.x / cab_s.y, 1).normalized()
	_glass_quad(glass, Vector3(-cab_s.x * 0.42, gy0, f0) + lean_f * 0.006, Vector3(cab_s.x * 0.42, gy0, f0) + lean_f * 0.006,
			Vector3(cab_s.x * 0.4, gy1, f1) + lean_f * 0.006, Vector3(-cab_s.x * 0.4, gy1, f1) + lean_f * 0.006, lean_f)
	var lean_b := Vector3(0, rake.y / cab_s.y, -1).normalized()
	_glass_quad(glass, Vector3(-cab_s.x * 0.4, gy0, b0) + lean_b * 0.006, Vector3(cab_s.x * 0.4, gy0, b0) + lean_b * 0.006,
			Vector3(cab_s.x * 0.38, gy1, b1) + lean_b * 0.006, Vector3(-cab_s.x * 0.38, gy1, b1) + lean_b * 0.006, lean_b)
	# door lines and handles, mirrors
	for s: float in [-1.0, 1.0]:
		var zm := (cz0 + cz1) * 0.5
		for z in [zm, cz1 - 0.05]:
			CP._box(trim, Vector3(s * (W * 0.5 + 0.004), 0.68, z), Vector3(0.008, 0.4, 0.012), paint.darkened(0.45) if not police else Color(0.3, 0.3, 0.32))
		for z in [zm - 0.3, cz1 - 0.35]:
			RM._rbox(trim, Vector3(s * (W * 0.5 + 0.015), 0.84, z), Vector3(0.025, 0.035, 0.14), 0.012, CHROME)
		soft_box(trim, Vector3(s * (W * 0.5 + 0.08), 1.06, cz1 - 0.1), Vector3(0.16, 0.12, 0.08), 0.035, paint if not police else white)
	# bumpers, grille, plate
	for e: float in [-1.0, 1.0]:
		soft_box(trim, Vector3(0, 0.42, e * (L * 0.5 + 0.04)), Vector3(W + 0.06, 0.2, 0.24), 0.08, GREY)
		CP._box(trim, Vector3(0, 0.42, e * (L * 0.5 + 0.165)), Vector3(0.5, 0.12, 0.01), Color(0.95, 0.95, 0.9))
	# (the nose is lower now: grille and lamps sit a hand lower, the grille in a chrome surround)
	soft_box(trim, Vector3(0, 0.58, L * 0.5 - 0.022), Vector3(0.72, 0.27, 0.06), 0.07, CHROME)
	soft_box(trim, Vector3(0, 0.58, L * 0.5 - 0.008), Vector3(0.62, 0.19, 0.06), 0.05, DARK)
	for k in 3:
		CP._box(trim, Vector3(0, 0.53 + k * 0.05, L * 0.5 + 0.024), Vector3(0.54, 0.016, 0.01), GREY)
	# lamps: big round headlights with a little amber indicator outside each, round tail lights
	for s: float in [-1.0, 1.0]:
		lamp(trim, heads, Vector3(s * W * 0.31, 0.62, L * 0.5 - 0.005), Vector3(0, 0, 1), 0.12)
		soft_box(trim, Vector3(s * (W * 0.31 + 0.19), 0.6, L * 0.5 - 0.02), Vector3(0.09, 0.08, 0.06), 0.025, Color(1.0, 0.58, 0.1))
		lamp(trim, tails, Vector3(s * W * 0.36, 0.66, -L * 0.5 + 0.005), Vector3(0, 0, -1), 0.09)
	# wheels
	for s: float in [-1.0, 1.0]:
		for wz: float in [-base * 0.5, base * 0.5]:
			wheel(tyres, Vector3(s * (W * 0.5 - 0.1), wr, wz), wr, 0.3, s)
	# extras: taxi sign and checker band, police light bar
	if id == "city/car_taxi":
		soft_box(trim, Vector3(0, top + 0.12, 0.0), Vector3(0.62, 0.22, 0.24), 0.06, Color(0.98, 0.9, 0.55))
		for s: float in [-1.0, 1.0]:
			for k in 14:
				for row in 2:
					var on := (k + row) % 2 == 0
					CP._box(trim, Vector3(s * (W * 0.5 + 0.005), 0.56 + row * 0.07, -1.1 + k * 0.16), Vector3(0.006, 0.07, 0.16), DARK if on else white)
	if police:
		soft_box(trim, Vector3(0, top + 0.06, (cz0 + cz1) * 0.5), Vector3(1.1, 0.08, 0.26), 0.04, DARK)
		soft_box(red, Vector3(-0.27, top + 0.15, (cz0 + cz1) * 0.5), Vector3(0.5, 0.12, 0.22), 0.05, Color.WHITE)
		soft_box(blue, Vector3(0.27, top + 0.15, (cz0 + cz1) * 0.5), Vector3(0.5, 0.12, 0.22), 0.05, Color.WHITE)
	return [CP._end(body, true), CP._end(glass, false), CP._end(trim, false), CP._end(tyres, false), CP._end(heads, false),
			CP._end(tails, false), CP._end(red, false), CP._end(blue, false)]


# ---------------------------------------------------------------- new vehicles

# A cab: lower body + a rounded cab with windows, used by the pickup, ambulance and fire truck. Returns where the
# cab's back is (z).
static func _cab(body: SurfaceTool, glass: SurfaceTool, trim: SurfaceTool, heads: SurfaceTool, front_z: float, W: float,
		cab_len: float, floor_y: float, top: float, col: Color) -> float:
	var back_z := front_z - cab_len
	soft_box(body, Vector3(0, floor_y + 0.32, front_z - cab_len * 0.5), Vector3(W, 0.66, cab_len), 0.2, col, Basis(), 6, Vector2.ZERO,
			Vector2(0.1, 0.0))   # (the bonnet slopes a little to the nose)
	# (the upper cab's front leans back 0.34 m: a sloping windscreen, like the cars')
	var up_h := top - floor_y - 0.6
	var up_lo := (floor_y + 0.62 + top) * 0.5 - up_h * 0.5
	var rake := 0.34
	soft_box(body, Vector3(0, (floor_y + 0.62 + top) * 0.5, back_z + cab_len * 0.38), Vector3(W * 0.96, up_h, cab_len * 0.74), 0.18, col, Basis(), 5, Vector2(rake, 0.0))
	var gx := W * 0.48 + 0.004
	var gz0 := back_z + 0.15
	var glass_lo := floor_y + 0.72
	var glass_hi := top - 0.12
	var face_lo := back_z + cab_len * 0.75 - rake * clampf((glass_lo - up_lo) / up_h, 0.0, 1.0)
	var face_hi := back_z + cab_len * 0.75 - rake * clampf((glass_hi - up_lo) / up_h, 0.0, 1.0)
	for s: float in [-1.0, 1.0]:
		_glass_quad(glass, Vector3(s * gx, glass_lo, gz0), Vector3(s * gx, glass_lo, face_lo - 0.14), Vector3(s * gx, glass_hi, face_hi - 0.12), Vector3(s * gx, glass_hi, gz0), Vector3(s, 0, 0))
	var lean := Vector3(0, rake / up_h, 1).normalized()
	_glass_quad(glass, Vector3(-W * 0.42, glass_lo, face_lo) + lean * 0.006, Vector3(W * 0.42, glass_lo, face_lo) + lean * 0.006,
			Vector3(W * 0.4, glass_hi, face_hi) + lean * 0.006, Vector3(-W * 0.4, glass_hi, face_hi) + lean * 0.006, lean)
	var gz1 := face_lo - 0.1   # (where the mirrors go)
	soft_box(trim, Vector3(0, floor_y + 0.1, front_z + 0.05), Vector3(W + 0.06, 0.22, 0.26), 0.08, GREY)
	soft_box(trim, Vector3(0, floor_y + 0.36, front_z - 0.01), Vector3(W * 0.42, 0.26, 0.06), 0.06, DARK)
	for k in 3:
		CP._box(trim, Vector3(0, floor_y + 0.28 + k * 0.07, front_z + 0.022), Vector3(W * 0.38, 0.018, 0.01), GREY)
	for s: float in [-1.0, 1.0]:
		lamp(trim, heads, Vector3(s * W * 0.34, floor_y + 0.42, front_z - 0.005), Vector3(0, 0, 1), 0.12)
		soft_box(trim, Vector3(s * (W * 0.5 + 0.09), floor_y + 0.85, gz1 - 0.05), Vector3(0.16, 0.14, 0.08), 0.035, col)
	return back_z


static func _put_parts(root: Node3D, parts: Array) -> void:
	RM._put(root, parts[0], RM._paint(Color.WHITE, 0.3, 0.2))
	RM._put(root, parts[1], _toy_glass(), true)
	RM._put(root, parts[2], RM._paint(Color.WHITE, 0.45, 0.55), false)
	RM._put(root, parts[3], RM._paint(Color.WHITE, 0.7, 0.05))
	RM._put(root, parts[4], RM._glow(Color(1.0, 0.97, 0.85), 0.5), false)


# A pickup truck: lifted, chunky, big off-road tyres, a cab and an open bed with low sides and a tailgate. (green)
static func _pickup(root: Node3D, id: String) -> void:
	var parts := RM._cached(_key(id), func() -> Array:
		var body := CP._begin()
		var glass := CP._begin()
		var trim := CP._begin()
		var tyres := CP._begin()
		var heads := CP._begin()
		var col := _paint(Color(0.32, 0.55, 0.28))
		var W := 2.0
		var L := 4.6
		var floor_y := 0.62
		var back := _cab(body, glass, trim, heads, L * 0.5, W, 2.1, floor_y, 1.95, col)
		# the bed: a floor and three low sides
		soft_box(body, Vector3(0, floor_y + 0.06, (back - L * 0.5) * 0.5), Vector3(W, 0.12, back + L * 0.5), 0.05, col.darkened(0.15))
		for s: float in [-1.0, 1.0]:
			soft_box(body, Vector3(s * (W * 0.5 - 0.05), floor_y + 0.32, (back - L * 0.5) * 0.5), Vector3(0.1, 0.52, back + L * 0.5), 0.05, col)
		soft_box(body, Vector3(0, floor_y + 0.32, -L * 0.5 + 0.05), Vector3(W, 0.52, 0.1), 0.05, col)
		soft_box(trim, Vector3(0, floor_y + 0.1, -L * 0.5 - 0.05), Vector3(W + 0.06, 0.22, 0.24), 0.08, GREY)
		soft_box(trim, Vector3(0, floor_y - 0.12, 0.0), Vector3(W * 0.7, 0.14, L * 0.8), 0.05, DARK)   # chassis
		for s: float in [-1.0, 1.0]:
			lamp(trim, heads, Vector3(s * W * 0.38, floor_y + 0.42, -L * 0.5 - 0.005), Vector3(0, 0, -1), 0.08)
			soft_box(trim, Vector3(s * (W * 0.5 + 0.08), floor_y - 0.02, 0.0), Vector3(0.12, 0.06, 1.3), 0.025, GREY)   # running boards
			for wz: float in [-1.45, 1.45]:
				soft_box(trim, Vector3(s * (W * 0.5 - 0.05), floor_y + 0.12, wz), Vector3(0.3, 0.3, 1.05), 0.14, Color(0.2, 0.2, 0.22))   # fender flares: dark, like the example's
				wheel(tyres, Vector3(s * (W * 0.5 - 0.1), 0.48, wz), 0.48, 0.4, s)
		return [CP._end(body, true), CP._end(glass, false), CP._end(trim, false), CP._end(tyres, false), CP._end(heads, false)])
	_put_parts(root, parts)


# An ambulance: a cab in white with a tall box body behind, a red stripe and red crosses, a light bar. (white)
static func _ambulance(root: Node3D, id: String) -> void:
	var parts := RM._cached(_key(id), func() -> Array:
		var body := CP._begin()
		var glass := CP._begin()
		var trim := CP._begin()
		var tyres := CP._begin()
		var heads := CP._begin()
		var red := CP._begin()
		var blue := CP._begin()
		var white := _paint(Color(0.95, 0.95, 0.94))
		var redc := Color(0.85, 0.12, 0.12)
		var W := 2.1
		var L := 5.0
		var floor_y := 0.48
		var back := _cab(body, glass, trim, heads, L * 0.5, W, 1.5, floor_y, 1.9, white)
		var box_len := back + L * 0.5
		soft_box(body, Vector3(0, floor_y + 1.05, (back - L * 0.5) * 0.5), Vector3(W + 0.1, 2.0, box_len), 0.14, white)
		for s: float in [-1.0, 1.0]:
			CP._box(trim, Vector3(s * (W * 0.5 + 0.056), floor_y + 0.9, (back - L * 0.5) * 0.5 + 0.4), Vector3(0.006, 0.18, box_len + 0.8), redc)   # the stripe (it stops short of the sloping windscreen)
			_cross(trim, Vector3(s * (W * 0.5 + 0.058), floor_y + 1.45, (back - L * 0.5) * 0.5), Vector3(s, 0, 0), 0.5, redc)
			lamp(trim, heads, Vector3(s * W * 0.38, floor_y + 0.3, -L * 0.5 - 0.005), Vector3(0, 0, -1), 0.08)
			for wz: float in [-1.4, 1.5]:
				wheel(tyres, Vector3(s * (W * 0.5 - 0.1), 0.4, wz), 0.4, 0.32, s)
		_cross(trim, Vector3(0, floor_y + 1.3, -L * 0.5 - 0.005), Vector3(0, 0, -1), 0.6, redc)
		soft_box(trim, Vector3(0, floor_y + 0.1, -L * 0.5 - 0.05), Vector3(W + 0.06, 0.22, 0.24), 0.08, GREY)
		soft_box(red, Vector3(-0.3, floor_y + 2.1, back + 0.2), Vector3(0.5, 0.14, 0.24), 0.05, Color.WHITE)
		soft_box(blue, Vector3(0.3, floor_y + 2.1, back + 0.2), Vector3(0.5, 0.14, 0.24), 0.05, Color.WHITE)
		return [CP._end(body, true), CP._end(glass, false), CP._end(trim, false), CP._end(tyres, false), CP._end(heads, false),
				CP._end(red, false), CP._end(blue, false)])
	_put_parts(root, parts)
	RM._put(root, parts[5], RM._flasher(Color(1.0, 0.08, 0.06), 0.0), false)
	RM._put(root, parts[6], RM._flasher(Color(0.12, 0.3, 1.0), 1.0), false)


static func _cross(st: SurfaceTool, c: Vector3, n: Vector3, s: float, col: Color) -> void:
	var x := n.cross(Vector3.UP).normalized()
	CP._box(st, c, (x * s + Vector3.UP * s * 0.3 + n * 0.006).abs(), col)
	CP._box(st, c, (x * s * 0.3 + Vector3.UP * s + n * 0.006).abs(), col)


# A fire truck: a red cab, a long red body with lockers, a silver ladder on top, a hose reel, a light. (red)
static func _firetruck(root: Node3D, id: String) -> void:
	var parts := RM._cached(_key(id), func() -> Array:
		var body := CP._begin()
		var glass := CP._begin()
		var trim := CP._begin()
		var tyres := CP._begin()
		var heads := CP._begin()
		var red := CP._begin()
		var blue := CP._begin()
		var col := _paint(Color(0.82, 0.12, 0.1))
		var W := 2.3
		var L := 7.0
		var floor_y := 0.55
		var back := _cab(body, glass, trim, heads, L * 0.5, W, 1.7, floor_y, 2.15, col)
		var blen := back + L * 0.5
		var bc := (back - L * 0.5) * 0.5
		soft_box(body, Vector3(0, floor_y + 0.75, bc), Vector3(W, 1.5, blen), 0.12, col)
		for s: float in [-1.0, 1.0]:
			for k in 4:   # locker doors with handles
				var z := -L * 0.5 + 0.5 + k * (blen - 1.0) / 4.0 + (blen - 1.0) / 8.0
				CP._box(trim, Vector3(s * (W * 0.5 + 0.004), floor_y + 0.8, z), Vector3(0.008, 1.0, (blen - 1.0) / 4.0 - 0.06), col.darkened(0.25))
				RM._rbox(trim, Vector3(s * (W * 0.5 + 0.015), floor_y + 0.75, z + 0.3), Vector3(0.02, 0.04, 0.16), 0.01, CHROME)
			CP._box(trim, Vector3(s * (W * 0.5 + 0.006), floor_y + 1.35, bc), Vector3(0.006, 0.08, blen), Color(0.95, 0.85, 0.3))   # a gold line
			lamp(trim, heads, Vector3(s * W * 0.4, floor_y + 0.3, -L * 0.5 - 0.005), Vector3(0, 0, -1), 0.08)
			for wz: float in [-2.6, -1.6, 2.2]:
				wheel(tyres, Vector3(s * (W * 0.5 - 0.12), 0.45, wz), 0.45, 0.36, s)
		soft_box(trim, Vector3(0, floor_y + 0.1, -L * 0.5 - 0.05), Vector3(W + 0.06, 0.22, 0.24), 0.08, GREY)
		# the ladder: two rails and rungs, on two supports, a little raised at the front
		var ly := floor_y + 1.62
		for s: float in [-1.0, 1.0]:
			CP._box(trim, Vector3(s * 0.38, ly, bc + 0.6), Vector3(0.06, 0.08, blen + 1.6), CHROME)
		for k in 22:
			CP._box(trim, Vector3(0, ly, bc - blen * 0.5 + 0.1 + k * (blen + 1.4) / 22.0), Vector3(0.76, 0.03, 0.04), CHROME.darkened(0.1))
		for z in [bc - blen * 0.35, bc + blen * 0.35]:
			soft_box(trim, Vector3(0, floor_y + 1.55, z), Vector3(0.9, 0.12, 0.2), 0.04, GREY)
		# the hose reel on the side, and a light on the cab
		CP._tube(trim, [Vector3(W * 0.5 + 0.02, floor_y + 0.8, bc - 0.6), Vector3(W * 0.5 + 0.12, floor_y + 0.8, bc - 0.6)], [0.3, 0.3], Color(0.95, 0.85, 0.5), 18)
		soft_box(red, Vector3(-0.3, floor_y + 2.0, back + 0.4), Vector3(0.45, 0.14, 0.22), 0.05, Color.WHITE)
		soft_box(blue, Vector3(0.3, floor_y + 2.0, back + 0.4), Vector3(0.45, 0.14, 0.22), 0.05, Color.WHITE)
		return [CP._end(body, true), CP._end(glass, false), CP._end(trim, false), CP._end(tyres, false), CP._end(heads, false),
				CP._end(red, false), CP._end(blue, false)])
	_put_parts(root, parts)
	RM._put(root, parts[5], RM._flasher(Color(1.0, 0.08, 0.06), 0.0), false)
	RM._put(root, parts[6], RM._flasher(Color(0.12, 0.3, 1.0), 1.0), false)


# A bus: a long soft body, cream above and yellow below, a row of big windows, a big windscreen, doors, bumpers,
# and round lamps. (8.5 m)
static func _bus(root: Node3D, id: String) -> void:
	var parts := RM._cached(_key(id), func() -> Array:
		var body := CP._begin()
		var glass := CP._begin()
		var trim := CP._begin()
		var tyres := CP._begin()
		var heads := CP._begin()
		var cream := Color(0.95, 0.92, 0.78)
		var yellow := _paint(Color(0.92, 0.68, 0.18))
		var W := 2.5
		var L := 8.5
		var floor_y := 0.45
		soft_box(body, Vector3(0, floor_y + 0.55, 0), Vector3(W, 1.1, L), 0.2, yellow)
		soft_box(body, Vector3(0, floor_y + 1.65, 0), Vector3(W * 0.99, 1.3, L * 0.995), 0.3, cream)
		soft_box(body, Vector3(0, floor_y + 2.36, 0.0), Vector3(W * 0.7, 0.12, L * 0.8), 0.05, cream.darkened(0.08))   # roof hatch strip
		var gy0 := floor_y + 1.2
		var gy1 := floor_y + 2.05
		for s: float in [-1.0, 1.0]:
			var x := s * (W * 0.5 + 0.004)
			for k in 7:
				var z0 := -L * 0.5 + 0.5 + k * 0.95
				_glass_quad(glass, Vector3(x, gy0, z0), Vector3(x, gy0, z0 + 0.8), Vector3(x, gy1, z0 + 0.8), Vector3(x, gy1, z0), Vector3(s, 0, 0))
			lamp(trim, heads, Vector3(s * W * 0.36, floor_y + 0.5, L * 0.5 + 0.0), Vector3(0, 0, 1), 0.14)
			lamp(trim, heads, Vector3(s * W * 0.38, floor_y + 0.55, -L * 0.5 - 0.005), Vector3(0, 0, -1), 0.1)
			for wz: float in [-L * 0.5 + 1.4, L * 0.5 - 1.6]:
				wheel(tyres, Vector3(s * (W * 0.5 - 0.15), 0.48, wz), 0.48, 0.36, s)
		# the door (right side, front) and the windscreen
		CP._box(trim, Vector3(W * 0.5 + 0.006, floor_y + 1.05, L * 0.5 - 1.0), Vector3(0.006, 1.9, 0.9), DARK)
		_glass_quad(glass, Vector3(W * 0.5 + 0.009, floor_y + 0.4, L * 0.5 - 1.4), Vector3(W * 0.5 + 0.009, floor_y + 0.4, L * 0.5 - 0.6),
				Vector3(W * 0.5 + 0.009, floor_y + 1.95, L * 0.5 - 0.6), Vector3(W * 0.5 + 0.009, floor_y + 1.95, L * 0.5 - 1.4), Vector3(1, 0, 0))
		var fz := L * 0.5 + 0.004
		_glass_quad(glass, Vector3(-W * 0.44, floor_y + 1.15, fz), Vector3(W * 0.44, floor_y + 1.15, fz), Vector3(W * 0.42, floor_y + 2.15, fz - 0.05), Vector3(-W * 0.42, floor_y + 2.15, fz - 0.05), Vector3(0, 0.1, 1))
		soft_box(trim, Vector3(0, floor_y + 2.32, L * 0.5 - 0.05), Vector3(W * 0.6, 0.22, 0.08), 0.05, DARK)   # destination sign
		for e: float in [-1.0, 1.0]:
			soft_box(trim, Vector3(0, floor_y + 0.12, e * (L * 0.5 + 0.06)), Vector3(W + 0.06, 0.24, 0.24), 0.08, GREY)
		soft_box(trim, Vector3(0, floor_y + 0.6, L * 0.5 - 0.005), Vector3(W * 0.4, 0.3, 0.05), 0.06, DARK)
		return [CP._end(body, true), CP._end(glass, false), CP._end(trim, false), CP._end(tyres, false), CP._end(heads, false)])
	_put_parts(root, parts)
	_label(root, "SCHOOL", Vector3(0, 2.77, 4.255), 0.0, 0.2, Color(1.0, 0.85, 0.3))


# A motorcycle: two chunky wheels, a frame, an orange tank and side panels, a black seat, handlebars and a round
# headlight. (2.0 m long)
static func _motorcycle(root: Node3D, id: String) -> void:
	var parts := RM._cached(_key(id), func() -> Array:
		var body := CP._begin()
		var glass := CP._begin()
		var trim := CP._begin()
		var tyres := CP._begin()
		var heads := CP._begin()
		var orange := _paint(Color(0.95, 0.5, 0.12))
		var r := 0.34
		for wz: float in [-0.7, 0.72]:
			wheel(tyres, Vector3(-0.1, r, wz), r, 0.2, -1.0, orange)   # (orange rims, like the example's)
			wheel(tyres, Vector3(0.1, r, wz), r, 0.001, 1.0, orange)    # ...on both sides
			CP._tube(trim, [Vector3(-0.2, r, wz), Vector3(0.0, r, wz)], [0.03, 0.03], GREY, 6)
		# frame, forks and swing arm
		CP._tube(trim, [Vector3(0, r, -0.7), Vector3(0, 0.55, -0.15), Vector3(0, 0.62, 0.35)], [0.035, 0.035, 0.035], GREY, 6)
		CP._tube(trim, [Vector3(0, r, 0.72), Vector3(0, 0.75, 0.55), Vector3(0, 1.0, 0.45)], [0.035, 0.03, 0.03], CHROME, 6)
		soft_box(body, Vector3(0, 0.78, 0.15), Vector3(0.34, 0.26, 0.55), 0.12, orange)          # tank
		soft_box(body, Vector3(0, 0.62, -0.25), Vector3(0.3, 0.26, 0.4), 0.1, orange.darkened(0.1))   # side panel
		soft_box(trim, Vector3(0, 0.82, -0.35), Vector3(0.3, 0.1, 0.6), 0.05, DARK)                    # seat
		soft_box(body, Vector3(0, 0.55, 0.78), Vector3(0.26, 0.08, 0.5), 0.04, orange)                # front mudguard
		soft_box(body, Vector3(0, 0.66, -0.78), Vector3(0.26, 0.08, 0.4), 0.04, orange)               # rear mudguard
		soft_box(trim, Vector3(0, 0.42, 0.0), Vector3(0.28, 0.24, 0.32), 0.06, GREY.darkened(0.2))   # engine
		CP._tube(trim, [Vector3(0.12, 0.3, 0.05), Vector3(0.18, 0.3, -0.5), Vector3(0.17, 0.4, -0.85)], [0.03, 0.03, 0.035], CHROME, 6)   # exhaust
		CP._tube(trim, [Vector3(-0.3, 1.05, 0.4), Vector3(0.0, 1.0, 0.45), Vector3(0.3, 1.05, 0.4)], [0.015, 0.018, 0.015], DARK, 6)   # handlebars
		lamp(trim, heads, Vector3(0, 0.92, 0.6), Vector3(0, 0, 1), 0.09)
		return [CP._end(body, true), CP._end(glass, false), CP._end(trim, false), CP._end(tyres, false), CP._end(heads, false)])
	_put_parts(root, parts)
