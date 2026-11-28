# The furniture set, refined (Sara, Nov 27: "refine all furniture to match the refinement level and style of the
# buildings"). Same sizes and footprints as the KayKit Furniture models they replace (refined_models.gd routes
# "furniture/..." here; Models._raw builds them). Real joinery in warm oak (plank tops, turned legs, aprons and
# stretchers), soft upholstery with tufted buttons and piping, made beds, brass knobs, terracotta pots, framed
# little paintings, braided and patterned rugs with fringes.
# Parts that the E animations move are their own named meshes (prop_animator.gd `_named_parts`): Pillow*,
# Blanket*, Seat*, LampShade, LampBulb, Picture.
extends RefCounted

const CP = preload("res://scripts/classic_props.gd")
const RM = preload("res://scripts/refined_models.gd")

const BUILDERS := {
	"furniture/armchair": "_sofa", "furniture/armchair_pillows": "_sofa", "furniture/couch": "_sofa",
	"furniture/couch_pillows": "_sofa",
	"furniture/bed_double_A": "_bed", "furniture/bed_double_B": "_bed", "furniture/bed_single_A": "_bed",
	"furniture/bed_single_B": "_bed",
	"furniture/book_set": "_books", "furniture/book_single": "_books",
	"furniture/cabinet_medium": "_cabinet", "furniture/cabinet_medium_decorated": "_cabinet",
	"furniture/cabinet_small": "_cabinet", "furniture/cabinet_small_decorated": "_cabinet",
	"furniture/cactus_medium_A": "_cactus", "furniture/cactus_medium_B": "_cactus", "furniture/cactus_small_A": "_cactus",
	"furniture/cactus_small_B": "_cactus",
	"furniture/chair_A": "_chair", "furniture/chair_A_wood": "_chair", "furniture/chair_B": "_chair",
	"furniture/chair_B_wood": "_chair", "furniture/chair_C": "_chair",
	"furniture/chair_stool": "_stool", "furniture/chair_stool_wood": "_stool",
	"furniture/lamp_standing": "_lamp", "furniture/lamp_table": "_lamp",
	"furniture/pictureframe_large_A": "_frame", "furniture/pictureframe_large_B": "_frame",
	"furniture/pictureframe_medium": "_frame", "furniture/pictureframe_small_A": "_frame",
	"furniture/pictureframe_small_B": "_frame", "furniture/pictureframe_small_C": "_frame",
	"furniture/pictureframe_standing_A": "_frame", "furniture/pictureframe_standing_B": "_frame",
	"furniture/pillow_A": "_pillow", "furniture/pillow_B": "_pillow",
	"furniture/rug_oval_A": "_rug", "furniture/rug_oval_B": "_rug", "furniture/rug_rectangle_A": "_rug",
	"furniture/rug_rectangle_B": "_rug", "furniture/rug_rectangle_stripes_A": "_rug",
	"furniture/rug_rectangle_stripes_B": "_rug",
	"furniture/shelf_A_big": "_shelf", "furniture/shelf_A_small": "_shelf", "furniture/shelf_B_large": "_shelf",
	"furniture/shelf_B_large_decorated": "_shelf", "furniture/shelf_B_small": "_shelf",
	"furniture/shelf_B_small_decorated": "_shelf",
	"furniture/table_low": "_table", "furniture/table_medium": "_table", "furniture/table_medium_long": "_table",
	"furniture/table_small": "_table",
}

const OAK := Color(0.62, 0.4, 0.24)
const OAK_D := Color(0.48, 0.3, 0.17)
const BLUE := Color("5f9bcd")
const ORANGE := Color("f89f49")
const CREAM := Color(0.95, 0.92, 0.85)
const LINEN := Color("dee4e6")
const BRASS := Color(0.86, 0.68, 0.32)
const TERRA := Color(0.78, 0.43, 0.26)
const IRON := Color(0.16, 0.16, 0.17)

static var _veh: GDScript


# ---------------------------------------------------------------- the kit

static func _sb(st: SurfaceTool, c: Vector3, s: Vector3, r: float, col: Color, bas := Basis(), n := 4) -> void:
	if _veh == null:
		_veh = load("res://scripts/vehicles.gd")
	_veh.soft_box(st, c, s, r, col, bas, n)


# One SurfaceTool per material ("wood", "cloth", ...); "cloth:Pillow0" is a part of its own, named Pillow0.
static func _s(k: Dictionary, m: String) -> SurfaceTool:
	if not k.has(m):
		k[m] = CP._begin()
	return k[m]


static func _done(k: Dictionary) -> Array:
	var out := []
	for m in k:
		out.append([m, CP._end(k[m], true)])
	return out


static func _mat(m: String) -> Material:
	match m.get_slice(":", 0):
		"wood": return CP._vmat("wood", 0.7)
		"cloth": return CP._vmat("cloth", 0.95)
		"shade": return CP._vmat("cloth", 0.9, -1.0, true)
		"rug": return CP._vmat("cloth", 0.98)
		"paint": return RM._paint(Color.WHITE, 0.4, 0.0)
		"metal": return RM._paint(Color.WHITE, 0.35, 0.75)
		"pot": return CP._vmat("plaster", 0.85)
		"plant": return CP._vmat("plant", 0.55)
		"paper": return CP._vmat("", 0.9)
	return CP._vmat("", 0.8)


static func _put_all(root: Node3D, parts: Array) -> void:
	for p in parts:
		var key: String = p[0]
		var mi := RM._put(root, p[1], _mat(key))
		if ":" in key:
			mi.name = key.get_slice(":", 1)


static func _make(root: Node3D, id: String, build: Callable) -> void:
	_put_all(root, RM._cached("f_" + id, func() -> Array:
		var k := {}
		build.call(k)
		return _done(k)))


# Another piece of the set, standing on this one (decorated cabinets and shelves).
static func _sub(root: Node3D, id: String, at: Vector3, yaw := 0.0, k := 1.0) -> void:
	var n := Node3D.new()
	root.add_child(n)
	var me: GDScript = load("res://scripts/refined_furniture.gd")
	me.call(BUILDERS[id], n, id)
	n.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * k), at)


# A turned leg standing at `at`: a foot, a long taper, a bead and a collar under the top.
static func _leg(st: SurfaceTool, at: Vector3, h: float, r: float, col: Color) -> void:
	CP._lathe(st, [[0.0, 0.0], [r * 0.75, 0.0], [r * 0.85, h * 0.04], [r * 0.7, h * 0.1], [r * 0.85, h * 0.5],
			[r * 1.05, h * 0.72], [r * 1.2, h * 0.76], [r * 0.95, h * 0.8], [r * 1.2, h * 0.84], [r * 1.25, h], [0.0, h]],
			12, func(_i, _a): return col, at)


static func _knob(st: SurfaceTool, at: Vector3, r := 0.022) -> void:
	CP._lathe(st, [[0.0, 0.0], [r * 0.45, 0.0], [r * 0.4, r * 0.7], [r, r * 1.2], [r * 0.9, r * 1.7], [0.0, r * 1.85]], 10,
			func(_i, _a): return BRASS, at, Callable())
	# (the lathe stands along y; knobs on a front face are turned to stick out along +z by the caller's basis)


# A knob sticking out of a front face (+z).
static func _front_knob(st: SurfaceTool, at: Vector3, r := 0.022) -> void:
	var tmp := CP._begin()
	_knob(tmp, Vector3.ZERO, r)
	var arr := tmp.commit_to_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var b := Basis(Vector3.RIGHT, PI * 0.5)
	for i in verts.size():
		st.set_color(cols[i])
		st.add_vertex(at + b * verts[i])


# A tufting button: a little dimpled stud on a cushion face (normal n).
static func _button(st: SurfaceTool, at: Vector3, n: Vector3, col: Color) -> void:
	var b := Basis(Vector3.UP.cross(n).normalized(), Vector3.UP.angle_to(n)) if absf(n.dot(Vector3.UP)) < 0.99 else Basis()
	var tmp := CP._begin()
	CP._lathe(tmp, [[0.0, -0.004], [0.016, -0.004], [0.018, 0.004], [0.01, 0.009], [0.0, 0.008]], 8, func(_i, _a): return col)
	var arr := tmp.commit_to_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	for i in verts.size():
		st.set_color(cols[i])
		st.add_vertex(at + b * verts[i])


# ---------------------------------------------------------------- tables

static func _table(root: Node3D, id: String) -> void:
	_make(root, id, func(k: Dictionary) -> void:
		var w := _s(k, "wood")
		var sz: Vector3 = {"furniture/table_low": Vector3(1.8, 0.38, 1.12), "furniture/table_medium": Vector3(1.5, 0.75, 1.5),
				"furniture/table_medium_long": Vector3(2.25, 0.75, 1.5), "furniture/table_small": Vector3(0.75, 0.75, 0.75)}[id]
		var low := id == "furniture/table_low"
		var tt := 0.05 if low else 0.06
		# the top: planks with rounded edges and a moulding underneath
		_sb(w, Vector3(0, sz.y - tt * 0.5, 0), Vector3(sz.x, tt, sz.z), 0.02, OAK, Basis(), 4)
		_sb(w, Vector3(0, sz.y - tt - 0.008, 0), Vector3(sz.x - 0.05, 0.018, sz.z - 0.05), 0.008, OAK_D, Basis(), 2)
		var planks := maxi(2, int(roundf(sz.z / 0.28)))
		for i in range(1, planks):
			_sb(w, Vector3(0, sz.y + 0.0004, -sz.z * 0.5 + sz.z * i / planks), Vector3(sz.x - 0.05, 0.002, 0.006), 0.001, OAK_D.darkened(0.3), Basis(), 1)
		var lx := sz.x * 0.5 - (0.1 if low else 0.08)
		var lz := sz.z * 0.5 - (0.1 if low else 0.08)
		var lh := sz.y - tt - 0.016
		for x: float in [-lx, lx]:
			for z: float in [-lz, lz]:
				_leg(w, Vector3(x, 0, z), lh, 0.045 if low else 0.036, OAK_D)
		if low:   # a coffee table: a lower shelf on the legs
			_sb(w, Vector3(0, 0.1, 0), Vector3(lx * 2.0 + 0.04, 0.03, lz * 2.0 + 0.04), 0.01, OAK, Basis(), 2)
		else:     # the apron rails between the legs, and stretchers low down
			_sb(w, Vector3(0, lh - 0.05, lz), Vector3(lx * 2.0, 0.09, 0.025), 0.008, OAK_D, Basis(), 2)
			_sb(w, Vector3(0, lh - 0.05, -lz), Vector3(lx * 2.0, 0.09, 0.025), 0.008, OAK_D, Basis(), 2)
			_sb(w, Vector3(lx, lh - 0.05, 0), Vector3(0.025, 0.09, lz * 2.0), 0.008, OAK_D, Basis(), 2)
			_sb(w, Vector3(-lx, lh - 0.05, 0), Vector3(0.025, 0.09, lz * 2.0), 0.008, OAK_D, Basis(), 2)
			for z: float in [-lz, lz]:
				CP._tube(w, [Vector3(-lx, 0.14, z), Vector3(lx, 0.14, z)], [0.014, 0.014], OAK_D, 8)
			CP._tube(w, [Vector3(0, 0.14, -lz), Vector3(0, 0.14, lz)], [0.014, 0.014], OAK_D, 8))


# ---------------------------------------------------------------- chairs and stools

static func _chair(root: Node3D, id: String) -> void:
	_make(root, id, func(k: Dictionary) -> void:
		var w := _s(k, "wood")
		var wood_only := id.ends_with("_wood")
		var style := "C" if id == "furniture/chair_C" else ("B" if "chair_B" in id else "A")
		var D := 0.7 if style == "C" else 0.63
		var H := 0.9 if style == "C" else 0.94
		var seat := 0.44
		var fx := 0.23
		var fz := D * 0.5 - 0.05
		var bz := -D * 0.5 + 0.05
		for x: float in [-fx, fx]:
			_leg(w, Vector3(x, 0, fz), seat - 0.04, 0.026, OAK_D)
			# back posts: square, rounded, running up past the seat to the top of the back
			_sb(w, Vector3(x, H * 0.5, bz), Vector3(0.045, H, 0.045), 0.012, OAK_D, Basis(), 2)
			CP._lathe(w, [[0.0, 0.0], [0.03, 0.0], [0.028, 0.02], [0.0, 0.035]], 10, func(_i, _a): return OAK_D, Vector3(x, H, bz))
		# the seat: a rail frame and a board (a padded cushion on the upholstered ones)
		_sb(w, Vector3(0, seat - 0.035, 0), Vector3(fx * 2.0 + 0.06, 0.05, D - 0.04), 0.012, OAK, Basis(), 3)
		if wood_only:
			_sb(w, Vector3(0, seat - 0.004, 0.01), Vector3(fx * 2.0 + 0.04, 0.02, D - 0.06), 0.008, OAK, Basis(), 2)
		else:
			var cl := _s(k, "cloth")
			_sb(cl, Vector3(0, seat + 0.02, 0.01), Vector3(fx * 2.0 + 0.03, 0.07, D - 0.08), 0.03, BLUE, Basis(), 5)
			_sb(cl, Vector3(0, seat - 0.012, 0.01), Vector3(fx * 2.0 + 0.04, 0.012, D - 0.07), 0.006, BLUE.darkened(0.2), Basis(), 2)
			_button(cl, Vector3(0, seat + 0.055, 0.01), Vector3.UP, BLUE.darkened(0.25))
		# stretchers between the legs
		for x: float in [-fx, fx]:
			CP._tube(w, [Vector3(x, 0.16, bz), Vector3(x, 0.16, fz)], [0.012, 0.012], OAK_D, 6)
		CP._tube(w, [Vector3(-fx, 0.22, 0.0), Vector3(fx, 0.22, 0.0)], [0.012, 0.012], OAK_D, 6)
		# the back
		var top := H - 0.06
		match style:
			"A":   # a top rail and spindles (or a padded back)
				_sb(w, Vector3(0, top, bz), Vector3(fx * 2.0, 0.1, 0.035), 0.014, OAK, Basis(), 3)
				_sb(w, Vector3(0, seat + 0.1, bz), Vector3(fx * 2.0, 0.04, 0.03), 0.01, OAK, Basis(), 2)
				if wood_only:
					for x: float in [-0.12, -0.04, 0.04, 0.12]:
						CP._tube(w, [Vector3(x, seat + 0.12, bz), Vector3(x, top - 0.05, bz)], [0.011, 0.011], OAK, 6)
				else:
					var cl := _s(k, "cloth")
					_sb(cl, Vector3(0, (seat + 0.12 + top - 0.05) * 0.5, bz + 0.012), Vector3(fx * 2.0 - 0.04, top - seat - 0.17, 0.045), 0.02, BLUE, Basis(), 4)
					_button(cl, Vector3(0, (seat + top) * 0.5 + 0.02, bz + 0.036), Vector3.BACK, BLUE.darkened(0.25))
			"B":   # three wide horizontal slats, the top one shaped (padded on the cloth one)
				for i in 3:
					var y := seat + 0.14 + i * 0.13
					var sz := Vector3(fx * 2.0, 0.07 if i < 2 else 0.11, 0.03)
					_sb(w, Vector3(0, y if i < 2 else top - 0.01, bz), sz, 0.012, OAK, Basis(), 3)
				if not wood_only:
					var cl := _s(k, "cloth")
					_sb(cl, Vector3(0, top - 0.01, bz + 0.02), Vector3(fx * 2.0 - 0.02, 0.1, 0.03), 0.014, BLUE, Basis(), 3)
			"C":   # bentwood: a hooped back with a centre splat
				var hoop := []
				var rad := []
				for i in 13:
					var a := PI * i / 12.0
					hoop.append(Vector3(-cos(a) * fx, seat + 0.08 + sin(a) * (H - seat - 0.12), bz))
					rad.append(0.018)
				CP._tube(w, hoop, rad, OAK, 8)
				_sb(w, Vector3(0, (seat + H) * 0.5, bz), Vector3(0.12, H - seat - 0.16, 0.02), 0.008, OAK, Basis(), 2)
				_sb(w, Vector3(0, seat + 0.08, bz), Vector3(fx * 2.0, 0.035, 0.03), 0.01, OAK, Basis(), 2)
		pass)


static func _stool(root: Node3D, id: String) -> void:
	_make(root, id, func(k: Dictionary) -> void:
		var w := _s(k, "wood")
		var h := 0.38
		CP._lathe(w, [[0.0, h - 0.045], [0.25, h - 0.045], [0.27, h - 0.035], [0.275, h - 0.015], [0.26, h], [0.0, h]], 28, func(_i, _a): return OAK)
		if not id.ends_with("_wood"):
			var cl := _s(k, "cloth")
			CP._lathe(cl, [[0.0, h - 0.005], [0.25, h - 0.005], [0.255, h + 0.01], [0.235, h + 0.035], [0.15, h + 0.048], [0.0, h + 0.05]], 28, func(_i, _a): return BLUE)
			_button(cl, Vector3(0, h + 0.048, 0), Vector3.UP, BLUE.darkened(0.25))
		for i in 4:
			var a := TAU * i / 4.0 + PI * 0.25
			var top := Vector3(cos(a) * 0.17, h - 0.045, sin(a) * 0.17)
			var foot := Vector3(cos(a) * 0.24, 0.0, sin(a) * 0.24)
			CP._tube(w, [foot, top], [0.022, 0.017], OAK_D, 8)
		# the foot ring
		CP._ring(w, Vector3(0, 0.13, 0), 0.215, 0.011, OAK_D, 24, 6))


# ---------------------------------------------------------------- armchair and couch

static func _sofa(root: Node3D, id: String) -> void:
	_make(root, id, func(k: Dictionary) -> void:
		var couch := "couch" in id
		var W := 2.25 if couch else 1.35
		var D := 1.2
		var cl := _s(k, "cloth")
		var w := _s(k, "wood")
		var body := BLUE
		# little tapered feet
		for x: float in [-W * 0.5 + 0.1, W * 0.5 - 0.1]:
			for z: float in [-D * 0.5 + 0.1, D * 0.5 - 0.1]:
				CP._lathe(w, [[0.0, 0.0], [0.025, 0.0], [0.035, 0.08], [0.0, 0.08]], 10, func(_i, _a): return OAK_D, Vector3(x, 0, z))
		# the frame: a base, rolled arms and a high back
		_sb(cl, Vector3(0, 0.08 + 0.15, 0.02), Vector3(W - 0.02, 0.3, D - 0.04), 0.07, body, Basis(), 5)
		for s: float in [-1.0, 1.0]:
			_sb(cl, Vector3(s * (W * 0.5 - 0.11), 0.08 + 0.28, 0.0), Vector3(0.22, 0.56, D), 0.08, body, Basis(), 5)
			CP._tube(cl, [Vector3(s * (W * 0.5 - 0.11), 0.62, -D * 0.5 + 0.05), Vector3(s * (W * 0.5 - 0.11), 0.62, D * 0.5 - 0.02)], [0.12, 0.12], body, 14)
			CP._lathe(cl, [[0.0, -0.005], [0.12, -0.005], [0.1, 0.02], [0.0, 0.025]], 14, func(_i, _a): return body.darkened(0.06),
					Vector3(s * (W * 0.5 - 0.11), 0.62, D * 0.5 - 0.02))
		_sb(cl, Vector3(0, 0.08 + 0.42, -D * 0.5 + 0.12), Vector3(W - 0.04, 0.84, 0.24), 0.1, body, Basis(), 5)
		# the cushions: seat cushions (named Seat*), and tufted back cushions leaning back
		var n := 2 if couch else 1
		var inner := W - 0.44
		for i in n:
			var cx := -inner * 0.5 + inner * (i + 0.5) / n
			var seat := _s(k, "cloth:Seat%d" % i)
			_sb(seat, Vector3(cx, 0.46, 0.08), Vector3(inner / n - 0.015, 0.16, D - 0.3), 0.06, body.lightened(0.04), Basis(), 5)
			_sb(seat, Vector3(cx, 0.46, 0.08), Vector3(inner / n - 0.005, 0.014, D - 0.29), 0.007, body.darkened(0.15), Basis(), 2)
			var tilt := Basis(Vector3.RIGHT, -0.16)
			var bc := Vector3(cx, 0.76, -D * 0.5 + 0.31)
			_sb(cl, bc, Vector3(inner / n - 0.015, 0.4, 0.16), 0.07, body.lightened(0.04), tilt, 5)
			for bx: float in [-0.18, 0.0, 0.18]:
				if absf(bx) < inner / n * 0.4:
					for by: float in [-0.07, 0.08]:
						_button(cl, bc + tilt * Vector3(bx + (0.09 if by > 0.0 else 0.0) * signf(bx + 0.001) * 0.0, by, 0.082), tilt * Vector3.BACK, body.darkened(0.3))
		# throw pillows in the corners
		if id.ends_with("_pillows"):
			var pc := _s(k, "cloth")
			for s: float in [-1.0, 1.0]:
				var b := Basis(Vector3.UP, -s * 0.35) * Basis(Vector3.RIGHT, -0.3) * Basis(Vector3.BACK, s * 0.12)
				var at := Vector3(s * (inner * 0.5 - 0.17), 0.7, -D * 0.5 + 0.47)
				_sb(pc, at, Vector3(0.36, 0.36, 0.12), 0.06, ORANGE, b, 5)
				_button(pc, at + b * Vector3(0, 0, 0.06), b * Vector3.BACK, ORANGE.darkened(0.25)))


# ---------------------------------------------------------------- beds

static func _bed(root: Node3D, id: String) -> void:
	_make(root, id, func(k: Dictionary) -> void:
		var W := 2.33 if "double" in id else 1.2
		var L := 2.25
		var b := id.ends_with("_B")
		var w := _s(k, "wood")
		var head := -L * 0.5 + 0.05
		var foot := L * 0.5 - 0.05
		# posts, side rails, a headboard and a low footboard
		for x: float in [-W * 0.5 + 0.05, W * 0.5 - 0.05]:
			_sb(w, Vector3(x, 0.375, head), Vector3(0.1, 0.75, 0.1), 0.02, OAK_D, Basis(), 3)
			CP._lathe(w, [[0.0, 0.0], [0.045, 0.0], [0.05, 0.02], [0.03, 0.04], [0.0, 0.05]], 12, func(_i, _a): return OAK, Vector3(x, 0.75, head))
			_sb(w, Vector3(x, 0.24, foot), Vector3(0.09, 0.48, 0.09), 0.02, OAK_D, Basis(), 3)
			_sb(w, Vector3(x, 0.24, 0), Vector3(0.05, 0.16, L - 0.12), 0.012, OAK, Basis(), 2)
		var span := W - 0.12
		if b:   # a solid panel headboard with a raised inset and a capping rail
			_sb(w, Vector3(0, 0.5, head), Vector3(span, 0.4, 0.05), 0.012, OAK, Basis(), 2)
			_sb(w, Vector3(0, 0.5, head + 0.022), Vector3(span - 0.12, 0.28, 0.02), 0.01, OAK.lightened(0.05), Basis(), 2)
			_sb(w, Vector3(0, 0.72, head), Vector3(span + 0.04, 0.04, 0.08), 0.012, OAK_D, Basis(), 2)
		else:   # rails with turned spindles
			_sb(w, Vector3(0, 0.7, head), Vector3(span, 0.07, 0.06), 0.015, OAK, Basis(), 2)
			_sb(w, Vector3(0, 0.34, head), Vector3(span, 0.05, 0.05), 0.012, OAK, Basis(), 2)
			var nsp := int(span / 0.14)
			for i in nsp:
				var x := -span * 0.5 + span * (i + 0.5) / nsp
				CP._tube(w, [Vector3(x, 0.36, head), Vector3(x, 0.52, head), Vector3(x, 0.67, head)], [0.014, 0.019, 0.014], OAK, 6)
		_sb(w, Vector3(0, 0.33, foot), Vector3(span, 0.22, 0.04), 0.01, OAK, Basis(), 2)
		_sb(w, Vector3(0, 0.45, foot), Vector3(span + 0.03, 0.035, 0.06), 0.01, OAK_D, Basis(), 2)
		# the mattress
		var cl := _s(k, "cloth")
		_sb(cl, Vector3(0, 0.39, 0), Vector3(W - 0.14, 0.18, L - 0.16), 0.05, CREAM, Basis(), 5)
		# the blanket over the lower part (with a quilted pattern and sides hanging down), the sheet folded over it
		var quilt := BLUE if b else ORANGE
		var bl := _s(k, "cloth:Blanket0")
		var bz0 := -L * 0.5 + 0.62
		var bz1 := L * 0.5 - 0.07
		_sb(bl, Vector3(0, 0.495, (bz0 + bz1) * 0.5), Vector3(W - 0.1, 0.04, bz1 - bz0), 0.02, quilt, Basis(), 3)
		for s: float in [-1.0, 1.0]:
			_sb(bl, Vector3(s * (W * 0.5 - 0.05), 0.41, (bz0 + bz1) * 0.5), Vector3(0.025, 0.18, bz1 - bz0), 0.012, quilt.darkened(0.05), Basis(), 2)
		var nq := maxi(2, int((W - 0.1) / 0.3))
		for i in range(1, nq):
			_sb(bl, Vector3(-(W - 0.1) * 0.5 + (W - 0.1) * i / nq, 0.516, (bz0 + bz1) * 0.5), Vector3(0.012, 0.004, bz1 - bz0 - 0.04), 0.002, quilt.darkened(0.2), Basis(), 1)
		for i in range(1, 4):
			_sb(bl, Vector3(0, 0.516, bz0 + (bz1 - bz0) * i / 4.0), Vector3(W - 0.14, 0.004, 0.012), 0.002, quilt.darkened(0.2), Basis(), 1)
		var sh := _s(k, "cloth:Blanket1")
		_sb(sh, Vector3(0, 0.52, bz0 + 0.06), Vector3(W - 0.09, 0.05, 0.15), 0.022, LINEN, Basis(), 3)
		# pillows at the head
		var np := 2 if W > 2.0 else 1
		var pw := minf(0.7, (W - 0.3) / np)
		for i in np:
			var px := 0.0 if np == 1 else (-1.0 if i == 0 else 1.0) * (W * 0.25 - 0.02)
			var pil := _s(k, "cloth:Pillow%d" % i)
			_sb(pil, Vector3(px, 0.55, head + 0.27), Vector3(pw, 0.12, 0.34), 0.055, LINEN, Basis(Vector3.RIGHT, -0.18), 6))


# ---------------------------------------------------------------- cabinets (chests of drawers, a nightstand)

static func _cabinet(root: Node3D, id: String) -> void:
	var small := "small" in id
	_make(root, id.trim_suffix("_decorated"), func(k: Dictionary) -> void:
		var w := _s(k, "wood")
		var W := 0.75 if small else 1.5
		var D := 0.75
		var H := 0.75
		_sb(w, Vector3(0, 0.035, 0), Vector3(W - 0.06, 0.07, D - 0.08), 0.01, OAK_D, Basis(), 2)
		_sb(w, Vector3(0, (H - 0.05 + 0.07) * 0.5, -0.01), Vector3(W - 0.04, H - 0.12, D - 0.06), 0.015, OAK, Basis(), 3)
		_sb(w, Vector3(0, H - 0.025, 0), Vector3(W, 0.05, D), 0.018, OAK, Basis(), 4)
		var cols := 1 if small else 2
		var rows := 2
		var fw := (W - 0.1) / cols
		var fh := (H - 0.17) / rows
		var fz := D * 0.5 - 0.03
		var br := _s(k, "metal")
		for c in cols:
			for r in rows:
				var cx := -(W - 0.1) * 0.5 + fw * (c + 0.5)
				var cy := 0.09 + fh * (r + 0.5)
				_sb(w, Vector3(cx, cy, fz), Vector3(fw - 0.025, fh - 0.025, 0.03), 0.01, OAK.lightened(0.03), Basis(), 2)
				_sb(w, Vector3(cx, cy, fz + 0.016), Vector3(fw - 0.1, fh - 0.09, 0.008), 0.004, OAK_D, Basis(), 1)
				for kx: float in ([-fw * 0.25, fw * 0.25] if fw > 0.5 else [0.0]):
					_front_knob(br, Vector3(cx + kx, cy, fz + 0.02)))
	if id.ends_with("_decorated"):
		if small:
			_sub(root, "furniture/lamp_table", Vector3(0, 0.75, -0.05), 0.0, 0.6)
		else:
			_sub(root, "furniture/lamp_table", Vector3(-0.42, 0.75, -0.08), 0.0, 0.8)
			_sub(root, "furniture/cactus_small_B", Vector3(0.45, 0.75, 0.05))
			_sub(root, "furniture/book_set", Vector3(0.05, 0.75, -0.1), 0.15, 0.7)


# ---------------------------------------------------------------- cacti in terracotta pots

static func _cactus(root: Node3D, id: String) -> void:
	_make(root, id, func(k: Dictionary) -> void:
		var medium := "medium" in id
		var b := id.ends_with("_B")
		var pot := _s(k, "pot")
		var pl := _s(k, "plant")
		var R := 0.3 if medium else 0.17
		var h := 0.3 if medium else 0.2
		CP._lathe(pot, [[0.0, 0.0], [R * 0.72, 0.0], [R * 0.75, 0.012], [R * 0.88, h * 0.78], [R * 0.9, h * 0.78], [R, h * 0.8],
				[R * 1.01, h], [R * 0.93, h], [R * 0.9, h * 0.93], [0.0, h * 0.93]], 28,
				func(i, a): return Color(0.28, 0.19, 0.12) if i >= 8 else TERRA.darkened(0.06 * absf(sin(a * 3.0)) + (0.08 if i >= 5 else 0.0)))
		var green := Color(0.3, 0.6, 0.28)
		var rib := func(_i, a): return green.lerp(Color(0.5, 0.75, 0.4), maxf(0.0, cos(a * 8.0)) * 0.6)
		var ribs := func(_i, a): return 1.0 + 0.09 * maxf(0.0, cos(a * 8.0))
		# a column cactus: a rounded ribbed stem
		var column := func(at: Vector3, r: float, ch: float) -> void:
			CP._lathe(pl, [[0.0, 0.0], [r, 0.0], [r, ch - r * 0.8], [r * 0.85, ch - r * 0.35], [r * 0.5, ch - r * 0.08], [0.0, ch]], 16, rib, at, ribs)
		var arm := func(at: Vector3, side: float, r: float, out: float, up: float) -> void:
			var p0 := at
			var p1 := at + Vector3(side * out, 0.0, 0.0)
			CP._tube(pl, [p0, p0.lerp(p1, 0.6), p1 + Vector3(0, r * 0.4, 0)], [r, r, r], green, 10)
			column.call(p1 + Vector3(0, r * 0.2, 0), r, up)
		var top := h * 0.93
		if medium and not b:
			column.call(Vector3(0, top, 0), 0.085, 0.31)
			arm.call(Vector3(0, top + 0.15, 0), 1.0, 0.05, 0.11, 0.1)
			column.call(Vector3(-0.15, top, 0.06), 0.06, 0.19)
			column.call(Vector3(0.12, top, -0.12), 0.055, 0.14)
		elif medium:
			CP._lathe(pl, [[0.0, 0.0], [0.15, 0.0], [0.2, 0.08], [0.2, 0.15], [0.15, 0.25], [0.0, 0.29]], 18, rib, Vector3(0, top, 0), ribs)
			CP._lathe(pl, [[0.0, 0.0], [0.07, 0.0], [0.09, 0.05], [0.07, 0.1], [0.0, 0.12]], 14, rib, Vector3(0.19, top, 0.1), ribs)
		elif not b:
			column.call(Vector3(0, top, 0), 0.06, 0.2)
			arm.call(Vector3(0, top + 0.1, 0), -1.0, 0.035, 0.08, 0.07)
		else:
			CP._lathe(pl, [[0.0, 0.0], [0.09, 0.0], [0.12, 0.06], [0.11, 0.13], [0.06, 0.18], [0.0, 0.19]], 16, rib, Vector3(0, top, 0), ribs)
		# spines: tiny pale prickles on the ribs; flowers on the B ones
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(id)
		var spine := Color(0.95, 0.93, 0.8)
		var reach := 0.2 if medium else 0.11
		for i in (60 if medium else 30):
			var a := TAU * floorf(rng.randf() * 8.0) / 8.0
			var y := top + rng.randf_range(0.03, 0.17 if medium else 0.12)
			var r := reach * 0.5 * rng.randf_range(0.8, 1.05)
			var p := Vector3(cos(a) * r, y, sin(a) * r)
			CP._tube(pl, [p, p + Vector3(cos(a), 0.3, sin(a)) * 0.018], [0.003, 0.0008], spine, 3)
		if b:
			var pink := Color(0.95, 0.4, 0.6)
			var fy := top + (0.29 if medium else 0.19)
			for f in 3 if medium else 1:
				var fa := TAU * f / 3.0
				var fp := Vector3(cos(fa) * 0.05, fy - 0.01, sin(fa) * 0.05) if medium else Vector3(0, fy - 0.005, 0)
				for p in 6:
					var pa := TAU * p / 6.0
					var tip := fp + Vector3(cos(pa) * 0.04, 0.025, sin(pa) * 0.04)
					CP._tube(pl, [fp, tip], [0.012, 0.004], pink, 4)
				CP._lathe(pl, [[0.0, 0.0], [0.012, 0.0], [0.008, 0.015], [0.0, 0.016]], 6, func(_i, _a): return Color(1.0, 0.85, 0.3), fp))


# ---------------------------------------------------------------- lamps

static func _lamp(root: Node3D, id: String) -> void:
	_make(root, id, func(k: Dictionary) -> void:
		var standing := id == "furniture/lamp_standing"
		var m := _s(k, "metal")
		var sh := _s(k, "shade:LampShade")
		var bulb := _s(k, "paint:LampBulb")
		var shade_lo := 1.38 if standing else 0.42
		var shade_hi := 1.89 if standing else 0.77
		if standing:
			CP._lathe(m, [[0.0, 0.0], [0.2, 0.0], [0.21, 0.015], [0.18, 0.04], [0.05, 0.06], [0.0, 0.062]], 24, func(_i, _a): return BRASS.darkened(0.1))
			CP._tube(m, [Vector3(0, 0.05, 0), Vector3(0, 0.8, 0), Vector3(0, 1.5, 0)], [0.016, 0.014, 0.013], BRASS, 8)
			CP._ring(m, Vector3(0, 0.8, 0), 0.02, 0.008, BRASS.darkened(0.15), 10, 4)
		else:   # a round glazed ceramic base
			var p := _s(k, "paint")
			CP._lathe(p, [[0.0, 0.0], [0.09, 0.0], [0.11, 0.02], [0.15, 0.1], [0.16, 0.17], [0.13, 0.25], [0.06, 0.3],
					[0.04, 0.32], [0.05, 0.34], [0.0, 0.345]], 24, func(i, _a): return BLUE.darkened(0.1) if i < 2 else BLUE)
			CP._tube(m, [Vector3(0, 0.34, 0), Vector3(0, shade_lo + 0.1, 0)], [0.012, 0.012], BRASS, 8)
		# the bulb in its socket, and the shade: cloth over a wire frame, trimmed top and bottom
		var bulb_y := shade_lo + (0.14 if standing else 0.09)
		CP._lathe(m, [[0.0, 0.0], [0.022, 0.0], [0.022, 0.04], [0.0, 0.04]], 10, func(_i, _a): return BRASS.darkened(0.2), Vector3(0, bulb_y - 0.07, 0))
		CP._lathe(bulb, [[0.0, -0.03], [0.02, -0.025], [0.045, 0.01], [0.04, 0.04], [0.0, 0.055]], 12, func(_i, _a): return Color(1.0, 0.97, 0.88), Vector3(0, bulb_y, 0))
		var rlo := 0.37
		var rhi := 0.22
		var sh_col := CREAM
		CP._lathe(sh, [[rlo, shade_lo], [rhi, shade_hi]], 32, func(_i, a): return sh_col.darkened(0.04 * absf(sin(a * 12.0))))
		CP._ring(m, Vector3(0, shade_lo, 0), rlo, 0.008, BRASS, 32, 4)
		CP._ring(m, Vector3(0, shade_hi, 0), rhi, 0.007, BRASS, 28, 4)
		for i in 3:
			var a := TAU * i / 3.0
			CP._tube(m, [Vector3(0, shade_hi - 0.01, 0), Vector3(cos(a) * rhi, shade_hi, sin(a) * rhi)], [0.004, 0.004], BRASS, 4)
		CP._tube(m, [Vector3(0, bulb_y - 0.05, 0), Vector3(0, shade_hi, 0)], [0.006, 0.006], BRASS, 4))


# ---------------------------------------------------------------- picture frames and their paintings

const FRAMES := {
	"furniture/pictureframe_large_A": [Vector2(0.76, 0.9), "angel"], "furniture/pictureframe_large_B": [Vector2(1.5, 0.9), "hills"],
	"furniture/pictureframe_medium": [Vector2(0.53, 0.68), "flowers"], "furniture/pictureframe_small_A": [Vector2(0.38, 0.45), "demon"],
	"furniture/pictureframe_small_B": [Vector2(0.53, 0.33), "sea"], "furniture/pictureframe_small_C": [Vector2(0.38, 0.38), "flowers"],
	"furniture/pictureframe_standing_A": [Vector2(0.36, 0.44), "angel"], "furniture/pictureframe_standing_B": [Vector2(0.53, 0.33), "hills"],
}


# The little paintings, coloured per vertex on a fine grid (u: left to right, v: bottom to top).
static func _paint_at(scene: String, u: float, v: float) -> Color:
	var sky := Color(0.55, 0.75, 0.95).lerp(Color(0.95, 0.88, 0.75), clampf(1.0 - v, 0.0, 1.0) * 0.6)
	match scene:
		"hills":
			if Vector2(u - 0.75, (v - 0.78) * 0.6).length() < 0.07:
				return Color(1.0, 0.9, 0.45)
			var far := 0.48 + 0.07 * sin(u * 6.0 + 1.0)
			var near := 0.32 + 0.09 * sin(u * 4.5 - 0.5) + 0.03 * sin(u * 13.0)
			if v < near:
				return Color(0.35, 0.6, 0.28).lerp(Color(0.25, 0.45, 0.2), (near - v) * 2.0)
			if v < far:
				return Color(0.45, 0.6, 0.55)
			return sky
		"sea":
			var sea := 0.42
			var boat := Vector2(u - 0.4, v - sea)
			if boat.y > 0.0 and boat.y < 0.28 and absf(boat.x) < 0.12 * (1.0 - boat.y / 0.28) and boat.x > -0.02:
				return Color(0.97, 0.96, 0.92)   # the sail
			if boat.y > -0.05 and boat.y <= 0.0 and absf(boat.x) < 0.12 + boat.y:
				return Color(0.55, 0.3, 0.18)   # the hull
			if v < sea:
				return Color(0.15, 0.38, 0.6).lerp(Color(0.3, 0.55, 0.75), 0.5 + 0.5 * sin(u * 40.0 + v * 30.0))
			return sky
		"flowers":
			var bg := Color(0.2, 0.24, 0.22)
			if v < 0.38 and absf(u - 0.5) < 0.14 + 0.04 * sin(v * 8.0):
				return Color(0.6, 0.35, 0.2)   # the vase
			for f in [[0.38, 0.62, Color(0.9, 0.25, 0.25)], [0.6, 0.68, Color(0.98, 0.85, 0.3)], [0.5, 0.8, Color(0.95, 0.55, 0.7)],
					[0.3, 0.78, Color(0.98, 0.95, 0.9)], [0.68, 0.5, Color(0.6, 0.4, 0.85)]]:
				if Vector2(u - f[0], (v - f[1]) * 0.8).length() < 0.09:
					return f[2]
			if v < 0.75 and v > 0.36 and absf(u - 0.5 - (v - 0.36) * 0.3 * sin(u * 20.0)) < 0.2 and fmod(u * 30.0, 1.0) < 0.12:
				return Color(0.3, 0.5, 0.25)
			return bg
		"angel", "demon":   # a little portrait: a halo or horns, wings behind
			var angel := scene == "angel"
			var bg := Color(0.45, 0.55, 0.7) if angel else Color(0.35, 0.12, 0.1)
			var head := Vector2(u - 0.5, (v - 0.6) * 0.85)
			var skin := Color(0.96, 0.82, 0.7) if angel else Color(0.75, 0.25, 0.2)
			if angel and absf(Vector2(u - 0.5, (v - 0.86) * 3.0).length() - 0.13) < 0.025:
				return Color(1.0, 0.85, 0.35)
			if not angel:
				for s: float in [-1.0, 1.0]:
					var hp := Vector2(u - 0.5 - s * 0.1, v - 0.8)
					if hp.y > 0.0 and hp.y < 0.12 and absf(hp.x - s * hp.y * 0.4) < 0.035 * (1.0 - hp.y / 0.12):
						return Color(0.95, 0.9, 0.8)
			if head.length() < 0.15:
				if Vector2(absf(u - 0.5) - 0.05, v - 0.63).length() < 0.018:
					return Color(0.1, 0.1, 0.12) if angel else Color(1.0, 0.8, 0.1)
				return skin
			if v < 0.45 and absf(u - 0.5) < 0.12 + (0.45 - v) * 0.6:
				return Color(0.96, 0.95, 0.92) if angel else Color(0.12, 0.08, 0.08)
			if v < 0.6 and v > 0.15 and absf(u - 0.5) < 0.45 and absf(u - 0.5) > 0.15 + (0.6 - v) * 0.2:
				return (Color(1.0, 1.0, 1.0) if angel else Color(0.25, 0.05, 0.05)).darkened(0.08 * float(int(v * 20.0) % 2))
			return bg
	return sky


static func _frame(root: Node3D, id: String) -> void:
	var spec: Array = FRAMES[id]
	var sz: Vector2 = spec[0]
	var standing := "standing" in id
	_make(root, id, func(k: Dictionary) -> void:
		var w := _s(k, "wood")
		var g := _s(k, "metal")
		var fw := clampf(minf(sz.x, sz.y) * 0.11, 0.035, 0.08)
		var d := 0.05 if standing else 0.1
		var tilt := Basis(Vector3.RIGHT, -0.22) if standing else Basis()
		var base := Vector3(0, sz.y * 0.5 * cos(0.22) + 0.004, 0.03) if standing else Vector3(0, sz.y * 0.5, 0)
		var at := func(p: Vector3) -> Vector3: return base + tilt * p
		# the moulding: four bars, a gilt lip inside, a backboard
		for s: float in [-1.0, 1.0]:
			_sb(w, at.call(Vector3(0, s * (sz.y - fw) * 0.5, 0)), Vector3(sz.x, fw, d), fw * 0.3, OAK_D, tilt, 3)
			_sb(w, at.call(Vector3(s * (sz.x - fw) * 0.5, 0, 0)), Vector3(fw, sz.y - fw * 1.6, d), fw * 0.3, OAK_D, tilt, 3)
			_sb(g, at.call(Vector3(0, s * (sz.y * 0.5 - fw - 0.006), d * 0.3)), Vector3(sz.x - fw * 2.0, 0.012, d * 0.2), 0.004, BRASS, tilt, 1)
			_sb(g, at.call(Vector3(s * (sz.x * 0.5 - fw - 0.006), 0, d * 0.3)), Vector3(0.012, sz.y - fw * 2.0, d * 0.2), 0.004, BRASS, tilt, 1)
		_sb(w, at.call(Vector3(0, 0, -d * 0.5 + 0.006)), Vector3(sz.x - fw, sz.y - fw, 0.012), 0.004, OAK_D.darkened(0.3), tilt, 1)
		# a cream mat round the painting
		var pp := _s(k, "paper")
		var iw := sz.x - fw * 2.0
		var ih := sz.y - fw * 2.0
		var mat := minf(iw, ih) * 0.08
		_sb(pp, at.call(Vector3(0, 0, d * 0.5 - 0.03)), Vector3(iw, ih, 0.01), 0.002, CREAM, tilt, 1)
		# the painting itself (its own mesh: the E key swaps in heaven/hell pictures over it)
		var pic := _s(k, "paper:Picture")
		var pw := iw - mat * 2.0
		var ph := ih - mat * 2.0
		var nx := 24
		var ny := 20
		for i in nx:
			for j in ny:
				var u0 := float(i) / nx
				var u1 := float(i + 1) / nx
				var v0 := float(j) / ny
				var v1 := float(j + 1) / ny
				var corners := [[u0, v0], [u1, v0], [u1, v1], [u0, v1]]
				var pts := []
				for c in corners:
					pts.append(at.call(Vector3((c[0] - 0.5) * pw, (c[1] - 0.5) * ph, d * 0.5 - 0.024)))
				for t in [[0, 2, 1], [0, 3, 2]]:   # (clockwise from the front)
					for q: int in t:
						pic.set_color(_paint_at(spec[1], corners[q][0], corners[q][1]))
						pic.add_vertex(pts[q])
		# a stand behind the standing ones
		if standing:
			var top: Vector3 = at.call(Vector3(0, sz.y * 0.2, -d * 0.5))
			var foot := Vector3(0, 0, -0.2)
			var dir := (top - foot)
			_sb(w, (top + foot) * 0.5, Vector3(0.05, dir.length(), 0.012), 0.004, OAK_D, Basis(Vector3.RIGHT, -atan2(dir.z, dir.y)), 1))


# ---------------------------------------------------------------- pillows, rugs

static func _pillow(root: Node3D, id: String) -> void:
	_make(root, id, func(k: Dictionary) -> void:
		var col := BLUE if id.ends_with("_A") else ORANGE
		var cl := _s(k, "cloth")
		_sb(cl, Vector3(0, 0.075, 0), Vector3(0.47, 0.15, 0.36), 0.07, col, Basis(), 6)
		_sb(cl, Vector3(0, 0.075, 0), Vector3(0.48, 0.012, 0.37), 0.006, col.darkened(0.2), Basis(), 2)   # the piping seam
		_button(cl, Vector3(0, 0.15, 0), Vector3.UP, col.darkened(0.3))
		for x: float in [-0.235, 0.235]:
			for z: float in [-0.175, 0.175]:
				CP._lathe(cl, [[0.0, -0.03], [0.012, -0.02], [0.006, 0.0], [0.0, 0.004]], 6, func(_i, _a): return col.darkened(0.15), Vector3(x, 0.06, z)))


# Rug styles (Sara, Nov 28: "several options of patterns/colors that you preset... striped red and white, striped
# light and dark blue, striped rainbow"): name, the colours its stripes (or braided rings, or field and medallion)
# run through, the border, the pale trim. Creative's Style picks one; 0 is the rug as it comes.
const RUG_STYLES := [
	["As it comes"],
	["Red and white", [Color("b3261e"), Color("f4efe6")], Color("7a1712"), Color("f4efe6")],
	["Light and dark blue", [Color("8fc1ea"), Color("1f3f7a")], Color("16294f"), Color("eef3f8")],
	["Rainbow", [Color("d83a34"), Color("f08a2c"), Color("f2cf3a"), Color("4caa52"), Color("3a7fd0"), Color("7a4db8")], Color("3a3a44"), Color("f4efe6")],
	["Green and cream", [Color("3f7f4a"), Color("efe6cf")], Color("28502f"), Color("efe6cf")],
	["Black and white", [Color("1d1d20"), Color("f2f2f0")], Color("1d1d20"), Color("f2f2f0")],
	["Pink and white", [Color("e88bb0"), Color("fbf3f5")], Color("b9577e"), Color("fbf3f5")],
	["Purple and gold", [Color("5b2f86"), Color("d9b04a")], Color("3a1c58"), Color("f0e2b0")],
	["Autumn", [Color("c4621f"), Color("6b3d1e"), Color("d9a53a")], Color("4a2a14"), Color("f0e2c2")],
	["Teal and sand", [Color("1f8a8c"), Color("e3d2a8")], Color("135557"), Color("efe6cf")],
	["Grey and charcoal", [Color("a9acb2"), Color("3b3d43")], Color("2a2b30"), Color("e6e6e8")],
]


static func rug_style_names() -> Array:
	return RUG_STYLES.map(func(st): return st[0])


static func _rug(root: Node3D, id: String) -> void:
	var style := clampi(RM.style, 0, RUG_STYLES.size() - 1)
	var with_fringe := RM.fringe
	_make(root, "%s#%d%s" % [id, style, "" if with_fringe else "-plain"], func(k: Dictionary) -> void:
		var oval := "oval" in id
		var stripes := "stripes" in id
		var a := id.ends_with("_A")
		var main := BLUE if a else ORANGE
		var deep := main.darkened(0.35)
		var light := main.lightened(0.45)
		var CREAM := Color(0.95, 0.92, 0.85)
		var run := []   # a preset style's colours, in order (none: the rug's own)
		if style > 0:
			run = RUG_STYLES[style][1]
			main = run[0]
			light = run[1]
			deep = RUG_STYLES[style][2]
			CREAM = RUG_STYLES[style][3]
		var r := _s(k, "rug")
		var t := 0.025
		if oval:   # a braided rug: rings of plaited bands round an oval
			var rx := 1.1
			var rz := 0.72
			var nr := 14
			var na := 64
			var ring_col := func(ri: int, ang: float) -> Color:
				var base: Color = [main, light, deep, main, CREAM][ri % 5]
				if not run.is_empty():
					base = run[ri % run.size()]
				return base.darkened(0.12 * (0.5 + 0.5 * sin(ang * 60.0 + ri * 1.7)))
			for ri in nr:
				var f0 := float(ri) / nr
				var f1 := float(ri + 1) / nr
				for j in na:
					var a0 := TAU * j / na
					var a1 := TAU * (j + 1) / na
					var hy := t + 0.004 * sin(PI * fmod((f0 + f1) * 0.5 * nr, 1.0))
					var p := [Vector3(cos(a0) * rx * f0, hy, sin(a0) * rz * f0), Vector3(cos(a1) * rx * f0, hy, sin(a1) * rz * f0),
							Vector3(cos(a1) * rx * f1, hy, sin(a1) * rz * f1), Vector3(cos(a0) * rx * f1, hy, sin(a0) * rz * f1)]
					CP._quad(r, p[0], p[1], p[2], p[3], ring_col.call(ri, a0), Vector3.UP)
			for j in na:   # the rounded rim
				var a0 := TAU * j / na
				var a1 := TAU * (j + 1) / na
				CP._quad(r, Vector3(cos(a0) * rx, t, sin(a0) * rz), Vector3(cos(a1) * rx, t, sin(a1) * rz),
						Vector3(cos(a1) * rx, 0.0, sin(a1) * rz), Vector3(cos(a0) * rx, 0.0, sin(a0) * rz), deep, Vector3(cos(a0), 0, sin(a0)))
			return
		# a woven rectangle: a border, a field (with a medallion, or stripes), fringes along the short ends
		var hx := 1.07
		var hz := 0.75
		var nx := 48
		var nz := 32
		var col := func(x: float, z: float) -> Color:
			var ex := hx - absf(x)
			var ez := hz - absf(z)
			var e := minf(ex, ez)
			if e < 0.1:
				return deep if e > 0.03 else main.darkened(0.15)
			if e < 0.13:
				return CREAM
			if stripes:
				var band := int(floorf((x + hx) / 0.18))
				if not run.is_empty():
					return run[band % run.size()]
				return [main, light, main, CREAM, deep][band % 5]
			var dm := absf(x) / 0.5 + absf(z) / 0.32
			if dm < 1.0:
				return deep if dm > 0.8 else (light if dm > 0.45 else CREAM)
			for cx: float in [-1.0, 1.0]:
				for cz: float in [-1.0, 1.0]:
					if absf(x - cx * (hx - 0.3)) + absf(z - cz * (hz - 0.27)) < 0.09:
						return deep
			return main
		for i in nx:
			for j in nz:
				var x0 := -hx + 2.0 * hx * i / nx
				var x1 := -hx + 2.0 * hx * (i + 1) / nx
				var z0 := -hz + 2.0 * hz * j / nz
				var z1 := -hz + 2.0 * hz * (j + 1) / nz
				var c: Color = col.call((x0 + x1) * 0.5, (z0 + z1) * 0.5)
				c = c.darkened(0.04 * float((i + j) % 2))   # the weave
				CP._quad(r, Vector3(x0, t, z0), Vector3(x1, t, z0), Vector3(x1, t, z1), Vector3(x0, t, z1), c, Vector3.UP)
		for s: float in [-1.0, 1.0]:
			CP._quad(r, Vector3(-hx, t, s * hz), Vector3(hx, t, s * hz), Vector3(hx, 0, s * hz), Vector3(-hx, 0, s * hz), deep, Vector3(0, 0, s))
			CP._quad(r, Vector3(s * hx, t, -hz), Vector3(s * hx, t, hz), Vector3(s * hx, 0, hz), Vector3(s * hx, 0, -hz), deep, Vector3(s, 0, 0))
			if not with_fringe:
				continue
			for f in 40:
				var z := -hz + 0.04 + (2.0 * hz - 0.08) * f / 39.0
				CP._box(r, Vector3(s * (hx + 0.028), 0.006, z), Vector3(0.056, 0.006, 0.012), CREAM.darkened(0.05 * float(f % 3)))
	)


# ---------------------------------------------------------------- shelves and books

static func _shelf(root: Node3D, id: String) -> void:
	var big := "big" in id or "large" in id
	var W := 1.5 if big else 0.75
	var a := "shelf_A" in id
	_make(root, id.trim_suffix("_decorated"), func(k: Dictionary) -> void:
		var w := _s(k, "wood")
		var D := 0.38
		if a:   # a plank on two iron brackets, for a wall
			_sb(w, Vector3(0, 0.3 - 0.0225, 0), Vector3(W, 0.045, D), 0.012, OAK, Basis(), 3)
			var m := _s(k, "metal")
			for x: float in [-W * 0.5 + 0.16, W * 0.5 - 0.16]:
				_sb(m, Vector3(x, 0.15, -D * 0.5 + 0.012), Vector3(0.03, 0.26, 0.024), 0.006, IRON, Basis(), 1)
				_sb(m, Vector3(x, 0.245, 0.0), Vector3(0.03, 0.02, D - 0.04), 0.006, IRON, Basis(), 1)
				var pts := []
				var rad := []
				for i in 9:   # a curled brace
					var ang := PI * 0.5 * i / 8.0
					pts.append(Vector3(x, 0.245 - 0.2 * sin(ang) * 0.9, -D * 0.5 + 0.02 + (D - 0.08) * (1.0 - cos(ang))))
					rad.append(0.008)
				CP._tube(m, pts, rad, IRON, 6)
				for y: float in [0.06, 0.2]:
					CP._lathe(m, [[0.0, 0.0], [0.009, 0.0], [0.007, 0.004], [0.0, 0.006]], 6, func(_i, _a): return IRON.lightened(0.2),
							Vector3(x, y, -D * 0.5 + 0.024))
		else:   # a ledge with shaped end boards
			_sb(w, Vector3(0, 0.0225, 0), Vector3(W, 0.045, D), 0.012, OAK, Basis(), 3)
			for s: float in [-1.0, 1.0]:
				_sb(w, Vector3(s * (W * 0.5 - 0.02), 0.15, 0), Vector3(0.04, 0.3, D), 0.012, OAK, Basis(), 3)
				CP._tube(w, [Vector3(s * (W * 0.5 - 0.02), 0.3, -D * 0.5 + 0.02), Vector3(s * (W * 0.5 - 0.02), 0.3, D * 0.5 - 0.02)], [0.024, 0.024], OAK_D, 8)
			_sb(w, Vector3(0, 0.08, -D * 0.5 + 0.015), Vector3(W - 0.06, 0.07, 0.03), 0.008, OAK_D, Basis(), 2))
	if id == "furniture/shelf_B_large_decorated":
		_sub(root, "furniture/book_set", Vector3(-0.38, 0.045, 0.0))
		_sub(root, "furniture/pictureframe_standing_A", Vector3(0.12, 0.045, -0.02), 0.0, 1.2)
		_sub(root, "furniture/cactus_small_A", Vector3(0.48, 0.045, 0.0))
	elif id == "furniture/shelf_B_small_decorated":
		_sub(root, "furniture/lamp_table", Vector3(-0.1, 0.045, 0.0), 0.0, 0.9)
		_sub(root, "furniture/book_single", Vector3(0.27, 0.045, 0.0), 0.0, 0.9)


# One book standing up, its spine to the front (+z): two boards, the page block set back, a spine with bands.
static func _book(k: Dictionary, at: Vector3, s: Vector3, col: Color, b := Basis()) -> void:
	var cl := _s(k, "cloth")
	var pp := _s(k, "paper")
	var ct := 0.012
	for side: float in [-1.0, 1.0]:
		_sb(cl, at + b * Vector3(side * (s.x * 0.5 - ct * 0.5), s.y * 0.5, 0), Vector3(ct, s.y, s.z), 0.004, col, b, 1)
	_sb(cl, at + b * Vector3(0, s.y * 0.5, s.z * 0.5 - ct * 0.5), Vector3(s.x, s.y, ct), 0.006, col.darkened(0.05), b, 2)
	_sb(pp, at + b * Vector3(0, s.y * 0.5, -0.004), Vector3(s.x - ct * 2.0, s.y - 0.016, s.z - ct - 0.008), 0.002, CREAM, b, 1)
	for y: float in [0.12, 0.88]:
		_sb(cl, at + b * Vector3(0, s.y * y, s.z * 0.5), Vector3(s.x * 0.92, 0.008, 0.004), 0.001, BRASS, b, 1)
	_sb(cl, at + b * Vector3(0, s.y * 0.55, s.z * 0.5), Vector3(s.x * 0.55, s.y * 0.12, 0.003), 0.001, col.lightened(0.4), b, 1)


static func _books(root: Node3D, id: String) -> void:
	_make(root, id, func(k: Dictionary) -> void:
		if id == "furniture/book_single":
			_book(k, Vector3.ZERO, Vector3(0.2, 0.38, 0.27), Color(0.95, 0.7, 0.2))
			return
		var widths := [0.1, 0.12, 0.08, 0.11, 0.09]
		var heights := [0.34, 0.38, 0.3, 0.36, 0.33]
		var cols := [Color(0.75, 0.2, 0.18), BLUE, Color(0.3, 0.55, 0.3), Color(0.95, 0.7, 0.2), Color(0.5, 0.3, 0.6)]
		var x := -0.29
		for i in 5:
			var bw: float = widths[i]
			var b := Basis()
			var at := Vector3(x + bw * 0.5, 0, 0)
			if i == 4:   # the last one leans on its neighbour
				b = Basis(Vector3.BACK, 0.22)
				at += Vector3(0.03, 0, 0)
			_book(k, at, Vector3(bw, heights[i], 0.25), cols[i], b)
			x += bw + 0.004)
