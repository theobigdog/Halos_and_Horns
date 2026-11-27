# The graveyard set, refined (Ted's wife, Nov 27: "all graveyard props and structures"). Same sizes and
# footprints as the KayKit Halloween models they replace (see refined_models.gd for how they're used). Built
# from a few shared pieces: weathered stone (chamfered slabs, carved reliefs, moss and cracks), skulls, dripping
# candles, iron lanterns, wrought-iron railings with spear tips, rough timber, ribbed pumpkins, bones.
# Candles and lanterns mark where their flames go (meta "flame_spots", prop_animator.gd lights them).
extends RefCounted

const CP = preload("res://scripts/classic_props.gd")
const RM = preload("res://scripts/refined_models.gd")

const BUILDERS := {
	"halloween/bench_decorated": "_bench_decorated", "halloween/bone_A": "_bone", "halloween/bone_B": "_bone",
	"halloween/bone_C": "_bone", "halloween/candle": "_candle_prop", "halloween/candle_melted": "_candle_prop",
	"halloween/candle_thin": "_candle_prop", "halloween/candle_triple": "_candle_prop", "halloween/coffin": "_coffin",
	"halloween/coffin_decorated": "_coffin", "halloween/grave_A": "_grave", "halloween/grave_A_destroyed": "_grave",
	"halloween/grave_B": "_grave", "halloween/gravemarker_A": "_marker", "halloween/gravemarker_B": "_marker",
	"halloween/gravestone": "_grave", "halloween/lantern_standing": "_lantern_prop", "halloween/lantern_hanging": "_lantern_prop",
	"halloween/pumpkin_orange": "_pumpkin", "halloween/pumpkin_orange_small": "_pumpkin", "halloween/pumpkin_yellow": "_pumpkin",
	"halloween/pumpkin_yellow_small": "_pumpkin", "halloween/pumpkin_orange_jackolantern": "_pumpkin",
	"halloween/pumpkin_yellow_jackolantern": "_pumpkin", "halloween/ribcage": "_ribcage", "halloween/shrine": "_shrine",
	"halloween/shrine_candles": "_shrine", "halloween/skull": "_skull_prop", "halloween/skull_candle": "_skull_prop",
	"halloween/crypt": "_crypt", "halloween/fence": "_fence", "halloween/fence_broken": "_fence", "halloween/fence_gate": "_fence",
	"halloween/fence_pillar": "_fence_pillar", "halloween/fence_pillar_broken": "_fence_pillar", "halloween/fence_seperate": "_railing",
	"halloween/fence_seperate_broken": "_railing", "halloween/floor_dirt": "_dirt", "halloween/floor_dirt_small": "_dirt",
	"halloween/floor_dirt_grave": "_dirt", "halloween/path_A": "_path", "halloween/path_B": "_path", "halloween/path_C": "_path",
	"halloween/path_D": "_path", "halloween/pillar": "_pillar", "halloween/plaque": "_plaque", "halloween/plaque_candles": "_plaque",
	"halloween/post": "_post", "halloween/post_lantern": "_post", "halloween/post_skull": "_post",
	"halloween/arch": "_arch", "halloween/arch_gate": "_arch",
}

const STONE := Color(0.56, 0.57, 0.56)
const WAX := Color(0.93, 0.91, 0.84)
const BONE := Color(0.9, 0.85, 0.72)
const IRON := Color(0.12, 0.12, 0.13)
const TIMBER := Color(0.38, 0.27, 0.18)


static func _mat_stone() -> Material: return CP._vmat("stone", 0.92)
static func _mat_wood() -> Material: return CP._vmat("wood", 0.88)
static func _mat_iron() -> Material: return RM._paint(Color.WHITE, 0.55, 0.65)
static func _mat_soft() -> Material: return CP._vmat("plaster", 0.75)


static func _cached(key: String, make: Callable) -> Array:
	return RM._cached("g_" + key, make)


static func _flames(root: Node3D, spots: Array) -> void:
	root.set_meta("flame_spots", spots)


# ---------------------------------------------------------------- shared pieces

# A stone block with chamfered edges (centre, size), its colour mottled, a little moss on top.
static func _slab(st: SurfaceTool, c: Vector3, s: Vector3, col: Color, bev := 0.03, bas := Basis()) -> void:
	var h := s * 0.5
	var b := minf(bev, minf(h.x, minf(h.y, h.z)) * 0.6)
	# the main box, shrunk by the bevel on each axis, plus the bevel faces as three slightly bigger boxes
	CP._box(st, c, Vector3(s.x, s.y - b * 2.0, s.z - b * 2.0), col, bas)
	CP._box(st, c, Vector3(s.x - b * 2.0, s.y, s.z - b * 2.0), col.lightened(0.04), bas)
	CP._box(st, c, Vector3(s.x - b * 2.0, s.y - b * 2.0, s.z), col.darkened(0.03), bas)


# A headstone shape: a rounded (or pointed) top over a rectangle, extruded `t` thick, facing +z.
static func _headstone(st: SurfaceTool, c: Vector3, w: float, h: float, t: float, col: Color, top := "round") -> void:
	var outline := []
	var r := w * 0.5
	var shoulder := h - (r if top == "round" else r * 0.6)
	outline.append(Vector2(-r, 0.0))
	outline.append(Vector2(r, 0.0))
	if top == "round":
		for k in 11:
			var a := PI * k / 10.0
			outline.append(Vector2(cos(a) * r, shoulder + sin(a) * r))
	elif top == "peak":
		outline.append(Vector2(r, shoulder))
		outline.append(Vector2(0.0, h))
		outline.append(Vector2(-r, shoulder))
	else:   # "shoulders": a flat top with rounded corners
		outline.append(Vector2(r, h - 0.12))
		outline.append(Vector2(r - 0.12, h))
		outline.append(Vector2(-r + 0.12, h))
		outline.append(Vector2(-r, h - 0.12))
	_extrude(st, c, outline, t, col)


# A flat outline (x, y) given depth t along z, centred on c (bottom of the outline at c.y).
static func _extrude(st: SurfaceTool, c: Vector3, pts: Array, t: float, col: Color) -> void:
	var n := pts.size()
	var ctr := Vector2.ZERO
	for p in pts:
		ctr += p
	ctr /= n
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var fa := c + Vector3(a.x, a.y, t * 0.5)
		var fb := c + Vector3(b.x, b.y, t * 0.5)
		var ba := c + Vector3(a.x, a.y, -t * 0.5)
		var bb := c + Vector3(b.x, b.y, -t * 0.5)
		CP._tri(st, c + Vector3(ctr.x, ctr.y, t * 0.5), fa, fb, col, Vector3.BACK)
		CP._tri(st, c + Vector3(ctr.x, ctr.y, -t * 0.5), ba, bb, col.darkened(0.05), Vector3.FORWARD)
		var e := (b - a)
		CP._quad(st, fa, fb, bb, ba, col.darkened(0.08), Vector3(e.y, -e.x, 0.0).normalized())


# A skull (radius r, facing +z) at c: cranium, cheekbones, deep dark eye sockets, a nose hole and a jaw with teeth.
static func _skull(st: SurfaceTool, dark: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	var prof := [[0.0, -0.35], [0.55, -0.32], [0.78, -0.1], [0.92, 0.2], [0.95, 0.5], [0.85, 0.78], [0.55, 0.97], [0.0, 1.02]]
	var scaled := []
	for p in prof:
		scaled.append([p[0] * r, p[1] * r])
	var squash := func(_i: int, a: float) -> float:
		return 1.0 - 0.12 * absf(cos(a))   # narrower at the temples
	CP._lathe(st, scaled, 18, func(_i, _a): return col, c, squash)
	# the face: cheekbones and the upper jaw sticking out at the front
	CP._box(st, c + Vector3(0, -0.15 * r, 0.62 * r), Vector3(1.05 * r, 0.42 * r, 0.42 * r), col.darkened(0.04))
	CP._box(st, c + Vector3(0, -0.47 * r, 0.5 * r), Vector3(0.75 * r, 0.22 * r, 0.42 * r), col.darkened(0.06))
	# eye sockets and nose (dark insets on the front)
	for s: float in [-1.0, 1.0]:
		CP._lathe(dark, [[0.0, -0.001], [0.2 * r, 0.0], [0.17 * r, 0.06 * r], [0.0, 0.07 * r]], 10, func(_i, _a): return Color(0.05, 0.03, 0.02),
				c + Vector3(s * 0.32 * r, 0.12 * r, 0.82 * r))
	CP._tri(dark, c + Vector3(0, -0.02 * r, 0.85 * r), c + Vector3(-0.09 * r, -0.24 * r, 0.84 * r), c + Vector3(0.09 * r, -0.24 * r, 0.84 * r), Color(0.05, 0.03, 0.02), Vector3.BACK)
	# teeth
	for k in 6:
		var x := (-0.25 + k * 0.1) * r
		CP._box(st, c + Vector3(x, -0.38 * r, 0.72 * r), Vector3(0.08 * r, 0.12 * r, 0.06 * r), col.lightened(0.06))


# A candle (radius r, height h) standing at c: lumpy wax with drips down the sides and a pool at the foot, a
# blackened wick. Returns where its flame goes.
static func _candle(st: SurfaceTool, c: Vector3, r: float, h: float, col: Color, seed: float) -> Vector3:
	var prof := [[r * 1.25, 0.0], [r * 1.2, 0.02], [r * 1.02, 0.035], [r, h * 0.3], [r, h * 0.7], [r * 0.98, h * 0.96], [r * 0.75, h], [r * 0.3, h * 0.97], [0.0, h * 0.96]]
	var drips := func(i: int, a: float) -> float:
		var d := 0.0
		for k in 4:
			var da := absf(wrapf(a - (seed * 3.1 + k * 1.7), -PI, PI))
			var reach := 0.35 + 0.5 * CP._h(seed + k)
			if da < 0.25 and float(i) / 8.0 > 1.0 - reach:
				d = maxf(d, 0.09 * (1.0 - da / 0.25))
		return 1.0 + d
	CP._lathe(st, prof, 14, func(i: int, _a: float) -> Color: return col.darkened(0.04 * float(i % 2)), c, drips)
	CP._tube(st, [c + Vector3(0, h * 0.96, 0), c + Vector3(0.003, h + 0.035, 0.002)], [0.006, 0.004], Color(0.08, 0.06, 0.05), 5)
	return c + Vector3(0, h + 0.04, 0)


# An iron lantern (s: its overall size) standing at c: a stepped base, four corner posts, glass panes, a pyramid roof
# with a ring on top. Returns where its flame goes. Glass in `glass`.
static func _lantern(st: SurfaceTool, glass: SurfaceTool, c: Vector3, s: float) -> Vector3:
	var w := 0.36 * s
	var h := 0.42 * s
	CP._box(st, c + Vector3(0, 0.03 * s, 0), Vector3(w * 1.15, 0.06 * s, w * 1.15), IRON)
	CP._box(st, c + Vector3(0, 0.08 * s, 0), Vector3(w * 1.0, 0.04 * s, w * 1.0), IRON.lightened(0.05))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			CP._box(st, c + Vector3(sx * w * 0.47, 0.1 * s + h * 0.5, sz * w * 0.47), Vector3(0.035 * s, h, 0.035 * s), IRON)
	for side in 4:
		var n := Vector3(sin(side * PI * 0.5), 0, cos(side * PI * 0.5))
		var pane_c := c + Vector3(0, 0.1 * s + h * 0.5, 0) + n * w * 0.45
		CP._box(glass, pane_c, Vector3(w * 0.85 if absf(n.z) > 0.5 else 0.01, h * 0.92, w * 0.85 if absf(n.x) > 0.5 else 0.01), Color(1.0, 0.85, 0.45))
		CP._box(st, pane_c + n * 0.006 + Vector3(0, 0, 0), Vector3(w * 0.85 if absf(n.z) > 0.5 else 0.012, 0.018 * s, w * 0.85 if absf(n.x) > 0.5 else 0.012), IRON)   # a glazing bar
	var top := c + Vector3(0, 0.1 * s + h, 0)
	CP._box(st, top + Vector3(0, 0.02 * s, 0), Vector3(w * 1.2, 0.04 * s, w * 1.2), IRON)
	CP._lathe(st, [[w * 0.62, 0.0], [w * 0.15, 0.22 * s], [0.0, 0.24 * s]], 4, func(_i, _a): return IRON.lightened(0.04), top + Vector3(0, 0.04 * s, 0))
	CP._ring(st, top + Vector3(0, 0.33 * s, 0), 0.06 * s, 0.012 * s, IRON, 12, 4)
	return c + Vector3(0, 0.1 * s + h * 0.45, 0)


# Wrought-iron railing from x0 to x1 (z = 0): top and bottom rails, bars with spear tips, a twisted collar on each.
# `broken`: a few bars missing, two bent.
static func _bars(st: SurfaceTool, x0: float, x1: float, y0: float, y1: float, broken := false) -> void:
	var n := int((x1 - x0) / 0.14)
	CP._tube(st, [Vector3(x0, y0 + 0.08, 0), Vector3(x1, y0 + 0.08, 0)], [0.018, 0.018], IRON, 6)
	CP._tube(st, [Vector3(x0, y1 - 0.15, 0), Vector3(x1, y1 - 0.15, 0)], [0.018, 0.018], IRON, 6)
	for k in n:
		var x := x0 + (x1 - x0) * (k + 0.5) / n
		if broken and k % 5 == 2:
			continue
		var lean := 0.0
		if broken and k % 7 == 4:
			lean = 0.25
		var top := Vector3(x + lean * 0.4, y1, lean * 0.15)
		CP._tube(st, [Vector3(x, y0, 0), Vector3(x, y1 - 0.15, 0), top], [0.014, 0.014, 0.013], IRON, 5)
		CP._lathe(st, [[0.0, 0.0], [0.028, 0.02], [0.0, 0.1]], 4, func(_i, _a): return IRON.lightened(0.05), top)
		CP._ring(st, Vector3(x, y1 - 0.15, 0), 0.026, 0.008, IRON, 8, 4)


# A stone pillar (the fences' posts) at c: plinth, shaft with a sunken panel, cap with a pyramid top.
static func _post_pillar(st: SurfaceTool, c: Vector3, w: float, h: float, broken := false) -> void:
	_slab(st, c + Vector3(0, 0.08, 0), Vector3(w, 0.16, w), STONE.darkened(0.1))
	var sh := h - 0.45 if not broken else h - 0.2
	_slab(st, c + Vector3(0, 0.16 + sh * 0.5, 0), Vector3(w * 0.8, sh, w * 0.8), STONE)
	for s: float in [-1.0, 1.0]:
		CP._box(st, c + Vector3(0, 0.16 + sh * 0.5, s * w * 0.41), Vector3(w * 0.45, sh * 0.6, 0.01), STONE.darkened(0.18))
	if broken:
		# a jagged broken top
		for k in 5:
			CP._box(st, c + Vector3((k - 2) * w * 0.15, 0.16 + sh + 0.03 * CP._h(k * 3.0), (CP._h(k) - 0.5) * w * 0.3), Vector3(w * 0.2, 0.1, w * 0.4), STONE.darkened(0.05), Basis(Vector3.BACK, (CP._h(k * 7.0) - 0.5) * 0.8))
		return
	_slab(st, c + Vector3(0, 0.16 + sh + 0.06, 0), Vector3(w, 0.12, w), STONE.lightened(0.05))
	CP._lathe(st, [[w * 0.5, 0.0], [0.0, 0.2]], 4, func(_i, _a): return STONE.lightened(0.08), c + Vector3(0, 0.16 + sh + 0.12, 0))


# Moss and cracks: a few dark green flecks on top faces and dark lines down faces.
static func _moss(st: SurfaceTool, c: Vector3, s: Vector3, seed: float, count := 6) -> void:
	for k in count:
		var p := c + Vector3((CP._h(seed + k) - 0.5) * s.x, s.y * 0.5 + 0.004, (CP._h(seed + k * 3.7) - 0.5) * s.z)
		CP._box(st, p, Vector3(0.05 + 0.08 * CP._h(seed * 2.0 + k), 0.006, 0.04 + 0.05 * CP._h(seed + k * 1.3)), Color(0.24, 0.36, 0.14), Basis(Vector3.UP, k * 1.1))


# ---------------------------------------------------------------- props

static func _bench_decorated(root: Node3D, _id: String) -> void:
	RM._grave_bench(root, "halloween/bench")
	var parts := _cached("bench_deco", func() -> Array:
		var st := CP._begin()
		var glass := CP._begin()
		var dark := CP._begin()
		var f := _lantern(st, glass, Vector3(-0.44, 0.375, 0.0), 0.75)
		_skull(st, dark, Vector3(0.35, 0.53, 0.0), 0.17, BONE)
		var wax := CP._begin()
		var f2 := _candle(wax, Vector3(0.35, 0.68, 0.0), 0.04, 0.12, WAX, 4.0)
		return [CP._end(st, false), CP._end(glass, false), CP._end(dark, false), CP._end(wax, true), [f]])
	RM._put(root, parts[0], _mat_iron(), false)
	RM._put(root, parts[1], RM._glow(Color(1.0, 0.82, 0.45), 0.6), false)
	RM._put(root, parts[2], _mat_stone(), false)
	RM._put(root, parts[3], _mat_soft(), false)
	_flames(root, parts[4])


static func _bone(root: Node3D, id: String) -> void:
	var parts := _cached(id, func() -> Array:
		var st := CP._begin()
		var len := 0.75 if id.ends_with("C") else 0.45
		var bend := 0.06 if id.ends_with("B") else 0.0
		var pts := []
		var radii := []
		for k in 9:
			var t := float(k) / 8.0
			pts.append(Vector3(-len * 0.5 + len * t, 0.09 + bend * sin(PI * t), 0))
			radii.append(0.03 + 0.015 * pow(absf(t - 0.5) * 2.0, 3.0))
		CP._tube(st, pts, radii, BONE, 10)
		for e: float in [-1.0, 1.0]:   # the knobbly ends: two knuckles each
			for s: float in [-1.0, 1.0]:
				CP._lathe(st, [[0.0, -0.05], [0.04, -0.035], [0.05, 0.0], [0.04, 0.035], [0.0, 0.05]], 10, func(_i, _a): return BONE.lightened(0.04),
						Vector3(e * len * 0.5, 0.09, s * 0.035))
		return [CP._end(st, true)])
	RM._put(root, parts[0], _mat_soft())


static func _candle_prop(root: Node3D, id: String) -> void:
	var parts := _cached(id, func() -> Array:
		var st := CP._begin()
		var spots := []
		match id:
			"halloween/candle":
				spots.append(_candle(st, Vector3.ZERO, 0.08, 0.52, WAX, 1.0))
			"halloween/candle_melted":
				spots.append(_candle(st, Vector3.ZERO, 0.085, 0.38, WAX.darkened(0.03), 2.0))
				CP._lathe(st, [[0.0, 0.0], [0.11, 0.0], [0.115, 0.015], [0.0, 0.02]], 14, func(_i, _a): return WAX, Vector3.ZERO)
			"halloween/candle_thin":
				spots.append(_candle(st, Vector3.ZERO, 0.045, 0.53, WAX, 3.0))
			"halloween/candle_triple":
				spots.append(_candle(st, Vector3(-0.06, 0, 0.0), 0.075, 0.52, WAX, 4.0))
				spots.append(_candle(st, Vector3(0.08, 0, 0.06), 0.06, 0.36, WAX.darkened(0.02), 5.0))
				spots.append(_candle(st, Vector3(0.07, 0, -0.07), 0.05, 0.24, WAX.darkened(0.04), 6.0))
		return [CP._end(st, true), spots])
	RM._put(root, parts[0], _mat_soft())
	_flames(root, parts[1])


# Coffins: the classic six-sided shape in dark planks with a lid; "decorated": the lid off, leaning beside it, a
# skeleton inside.
static func _coffin(root: Node3D, id: String) -> void:
	var parts := _cached(id, func() -> Array:
		var st := CP._begin()
		var dark := CP._begin()
		var open := id.ends_with("decorated")
		var shape := [Vector2(-0.38, -1.05), Vector2(0.38, -1.05), Vector2(0.62, 0.45), Vector2(0.45, 1.05), Vector2(-0.45, 1.05), Vector2(-0.62, 0.45)]
		var wall := 0.05
		var h := 0.5
		var wood := TIMBER.darkened(0.1)
		# floor and walls (planks run lengthwise: drawn as darker seams)
		for i in shape.size():
			var a: Vector2 = shape[i]
			var b: Vector2 = shape[(i + 1) % shape.size()]
			var mid := (a + b) * 0.5
			var along := (b - a)
			var ang := atan2(along.x, along.y)
			CP._box(st, Vector3(mid.x, h * 0.5, mid.y), Vector3(wall, h, along.length() + 0.04), wood, Basis(Vector3.UP, ang))
			for k in 3:   # plank seams
				CP._box(dark, Vector3(mid.x, 0.12 + k * 0.14, mid.y) + Vector3(-along.y, 0, along.x).normalized() * 0.026, Vector3(0.004, 0.008, along.length() * 0.96), Color(0.1, 0.06, 0.04), Basis(Vector3.UP, ang))
		var floor_pts := []
		for p in shape:
			floor_pts.append(Vector3(p.x, 0.02, p.y))
		for i in shape.size():
			CP._tri(st, Vector3(0, 0.02, 0), floor_pts[i], floor_pts[(i + 1) % shape.size()], wood.darkened(0.2), Vector3.UP)
		# the lid: on top, or leaning against the side
		var lid := CP._begin()
		var lid_xf := Transform3D(Basis(), Vector3(0, h + 0.02, 0)) if not open else Transform3D(Basis(Vector3.BACK, 1.25), Vector3(0.95, 0.62, 0))
		var lid_pts := []
		for p in shape:
			lid_pts.append(Vector2(p.x * 1.05, p.y * 1.02))
		for i in lid_pts.size():
			var a: Vector2 = lid_pts[i]
			var b: Vector2 = lid_pts[(i + 1) % lid_pts.size()]
			var pa := lid_xf * Vector3(a.x, 0, a.y)
			var pb := lid_xf * Vector3(b.x, 0, b.y)
			var ta := lid_xf * Vector3(a.x * 0.92, 0.06, a.y * 0.96)
			var tb := lid_xf * Vector3(b.x * 0.92, 0.06, b.y * 0.96)
			var up := lid_xf.basis * Vector3.UP
			CP._quad(lid, pa, pb, tb, ta, wood.lightened(0.05), lid_xf.basis * Vector3(b.y - a.y, 0.5, a.x - b.x).normalized())
			CP._tri(lid, lid_xf * Vector3(0, 0.06, 0), ta, tb, wood.lightened(0.08), up)
			CP._tri(lid, lid_xf * Vector3(0, 0, 0), pa, pb, wood.darkened(0.2), -up)
		# a cross on the lid, and brass handles on the sides
		CP._box(lid, lid_xf * Vector3(0, 0.07, -0.05), Vector3(0.08, 0.02, 0.9), Color(0.75, 0.6, 0.25), lid_xf.basis)
		CP._box(lid, lid_xf * Vector3(0, 0.07, 0.2), Vector3(0.45, 0.02, 0.08), Color(0.75, 0.6, 0.25), lid_xf.basis)
		for s: float in [-1.0, 1.0]:
			for z: float in [-0.5, 0.0, 0.5]:
				CP._tube(dark, [Vector3(s * 0.6, 0.3, z - 0.08), Vector3(s * 0.66, 0.26, z), Vector3(s * 0.6, 0.3, z + 0.08)], [0.012, 0.012, 0.012], Color(0.7, 0.55, 0.25), 5)
		var bones := CP._begin()
		var bones_dark := CP._begin()
		if open:
			_skeleton(bones, bones_dark)
		return [CP._end(st, false), CP._end(dark, false), CP._end(lid, false), CP._end(bones, true), CP._end(bones_dark, false)])
	RM._put(root, parts[0], _mat_wood())
	RM._put(root, parts[1], RM._paint(Color.WHITE, 0.5, 0.5), false)
	RM._put(root, parts[2], _mat_wood())
	if id.ends_with("decorated"):
		RM._put(root, parts[3], _mat_soft(), false)
		RM._put(root, parts[4], _mat_soft(), false)


# Headstones: grave_A (round top, skull carved in it, on a plinth with a dirt mound in front), grave_A_destroyed
# (the same, cracked in two, the top half fallen and tilted), grave_B (shouldered top with a cross), gravestone
# (a tall round-topped stone with an inscription panel and a skull).
static func _grave(root: Node3D, id: String) -> void:
	var parts := _cached(id, func() -> Array:
		var st := CP._begin()
		var dark := CP._begin()
		var dirt := CP._begin()
		var stone := STONE.darkened(0.05 if id.ends_with("B") else 0.0)
		var big := id == "halloween/gravestone"
		var w := 0.9 if big else 0.75
		var h := 1.1 if big else 1.15
		var t := 0.2
		var plinth_y := 0.0 if big else 0.18
		if not big:
			_slab(st, Vector3(0, 0.09, -0.15), Vector3(1.4, 0.18, 0.55), stone.darkened(0.12))
			# a mound of earth in front, with a few tufts
			CP._lathe(dirt, [[0.0, 0.0], [0.6, 0.0], [0.5, 0.08], [0.25, 0.13], [0.0, 0.14]], 16, func(_i, _a): return Color(0.28, 0.2, 0.13),
					Vector3(0, 0.0, 0.18), func(_i, a): return 1.0 + 0.6 * absf(sin(a)) * 0.0)
		var top := "round" if not id.ends_with("B") else "shoulders"
		if id.ends_with("destroyed"):
			# the lower half standing, the top broken off and leaning against it
			_headstone(st, Vector3(0, plinth_y, -0.15), w, h * 0.55, t, stone, "shoulders")
			var xf := Transform3D(Basis(Vector3.RIGHT, -1.1) * Basis(Vector3.BACK, 0.25), Vector3(0.15, 0.12, 0.25))
			var pts := []
			var r := w * 0.95 * 0.5
			pts.append(Vector2(-r, 0.0))
			pts.append(Vector2(r, 0.0))
			for k in 11:
				var a := PI * k / 10.0
				pts.append(Vector2(cos(a) * r, h * 0.5 - r + sin(a) * r))
			_extrude_xf(st, xf, pts, t * 0.95, stone.lightened(0.03))
			for k in 6:   # rubble chips
				CP._box(st, Vector3((CP._h(k) - 0.5) * 1.2, 0.2, 0.1 + 0.3 * CP._h(k * 3.0)), Vector3(0.08, 0.05, 0.07), stone.darkened(0.1), Basis(Vector3.UP, k))
		else:
			_headstone(st, Vector3(0, plinth_y, -0.15), w, h, t, stone, top)
		var face_y := plinth_y + h * (0.55 if not id.ends_with("destroyed") else 0.3)
		var face_z := -0.15 + t * 0.5 + 0.004
		if id.ends_with("B"):
			CP._box(st, Vector3(0, face_y, face_z + 0.01), Vector3(0.08, 0.5, 0.025), stone.lightened(0.08))
			CP._box(st, Vector3(0, face_y + 0.1, face_z + 0.01), Vector3(0.32, 0.08, 0.025), stone.lightened(0.08))
		else:
			_skull(st, dark, Vector3(0, face_y + 0.05, face_z - 0.06), 0.13 if not big else 0.15, stone.lightened(0.1))
		if big:
			CP._box(dark, Vector3(0, plinth_y + 0.3, face_z), Vector3(0.5, 0.2, 0.004), stone.darkened(0.25))   # the inscription panel
			for k in 3:
				CP._box(dark, Vector3(-0.12 + 0.03 * k, plinth_y + 0.33 - k * 0.05, face_z + 0.002), Vector3(0.24 + 0.05 * (k % 2), 0.012, 0.002), stone.darkened(0.45))
		_moss(st, Vector3(0, plinth_y + h * 0.9, -0.15), Vector3(w * 0.6, 0.1, t), 3.0 + w)
		return [CP._end(st, false), CP._end(dark, false), CP._end(dirt, true)])
	RM._put(root, parts[0], _mat_stone())
	RM._put(root, parts[1], _mat_stone(), false)
	RM._put(root, parts[2], CP._vmat("stone", 1.0), false)


static func _extrude_xf(st: SurfaceTool, xf: Transform3D, pts: Array, t: float, col: Color) -> void:
	var tmp := CP._begin()
	_extrude(tmp, Vector3.ZERO, pts, t, col)
	var arrays := tmp.commit_to_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in verts.size():
		st.set_color(cols[i])
		st.add_vertex(xf * verts[i])


# Wooden grave markers: two rough planks crossed and nailed, leaning a little, a small mound; B has a skull hung on it.
static func _marker(root: Node3D, id: String) -> void:
	var parts := _cached(id, func() -> Array:
		var st := CP._begin()
		var dark := CP._begin()
		var lean := Basis(Vector3.BACK, 0.06) * Basis(Vector3.RIGHT, -0.05)
		CP._box(st, lean * Vector3(0, 0.45, 0), Vector3(0.1, 0.9, 0.06), TIMBER, lean)
		CP._box(st, lean * Vector3(0, 0.62, 0.035), Vector3(0.5, 0.09, 0.05), TIMBER.lightened(0.05), lean * Basis(Vector3.BACK, 0.05))
		for x: float in [-0.03, 0.03]:   # nails
			CP._box(dark, lean * Vector3(x, 0.62, 0.064), Vector3(0.015, 0.015, 0.01), Color(0.2, 0.18, 0.17), lean)
		for k in 6:   # splinters / grain lines
			CP._box(dark, lean * Vector3(-0.2 + k * 0.08, 0.62 + (CP._h(k) - 0.5) * 0.04, 0.061), Vector3(0.05, 0.004, 0.002), TIMBER.darkened(0.35), lean)
		if id.ends_with("B"):
			_skull(st, dark, lean * Vector3(0, 0.45, 0.12), 0.08, BONE)
		var mound := CP._begin()
		CP._lathe(mound, [[0.0, 0.0], [0.28, 0.0], [0.2, 0.05], [0.0, 0.07]], 12, func(_i, _a): return Color(0.27, 0.19, 0.12))
		return [CP._end(st, false), CP._end(dark, false), CP._end(mound, true)])
	RM._put(root, parts[0], _mat_wood())
	RM._put(root, parts[1], _mat_soft(), false)
	RM._put(root, parts[2], CP._vmat("stone", 1.0), false)


static func _lantern_prop(root: Node3D, id: String) -> void:
	var hanging := id.ends_with("hanging")
	var parts := _cached(id, func() -> Array:
		var st := CP._begin()
		var glass := CP._begin()
		var at := Vector3(0, 0.0, 0) if not hanging else Vector3(0, 0.38, 0)
		var f := _lantern(st, glass, at, 1.3)
		if hanging:   # a hook and a short chain above it
			for k in 5:
				CP._ring(st, at + Vector3(0, 0.62 + k * 0.08, 0), 0.025, 0.007, IRON, 8, 4)
			CP._tube(st, [at + Vector3(0, 1.0, 0), at + Vector3(0, 1.06, 0)], [0.015, 0.015], IRON, 5)
		return [CP._end(st, false), CP._end(glass, false), [f]])
	RM._put(root, parts[0], _mat_iron())
	RM._put(root, parts[1], RM._glow(Color(1.0, 0.82, 0.45), 0.7), false)
	_flames(root, parts[2])


# Pumpkins: deep ribs, a slightly squashed shape, a curly stem; jack-o'-lanterns get a carved, glowing face.
static func _pumpkin(root: Node3D, id: String) -> void:
	var parts := _cached(id, func() -> Array:
		var st := CP._begin()
		var face := CP._begin()
		var small := id.ends_with("small")
		var jack := id.ends_with("jackolantern")
		var r := 0.21 if small else (0.52 if jack else 0.36)
		var hgt := r * (0.95 if small else 0.88)
		var yellow := "yellow" in id
		var col := Color(0.92, 0.62, 0.1) if yellow else Color(0.88, 0.38, 0.05)
		var prof := []
		for k in 13:
			var t := float(k) / 12.0
			var a := -PI * 0.5 + PI * t
			prof.append([cos(a) * r * (1.0 - 0.18 * pow(absf(sin(a)), 4.0)), hgt + sin(a) * hgt * 0.95])
		prof[0][0] = 0.0
		prof[prof.size() - 1][0] = 0.0
		var ribs := func(_i: int, a: float) -> float:
			return 1.0 - 0.09 * pow(absf(sin(a * 5.0)), 0.6)
		var shade := func(_i: int, a: float) -> Color:
			return col.darkened(0.25 * pow(absf(sin(a * 5.0)), 4.0))
		CP._lathe(st, prof, 40, shade, Vector3.ZERO, ribs)
		# the stem
		var top := Vector3(0, hgt * 1.92, 0)
		CP._tube(st, [top - Vector3(0, 0.03, 0), top + Vector3(0.01, r * 0.18, 0), top + Vector3(r * 0.1, r * 0.25, 0.02)],
				[r * 0.08, r * 0.065, r * 0.04], Color(0.35, 0.28, 0.12), 6)
		if jack:
			# carved face on the front (+z): triangle eyes, a triangle nose, a jagged grin, glowing
			var fz := r * 0.93
			var at := func(x: float, y: float) -> Vector3:
				return Vector3(x * r, hgt + y * hgt, sqrt(maxf(0.0, 1.0 - x * x)) * fz + 0.004)
			var glow := Color(1.0, 0.7, 0.2)
			for s: float in [-1.0, 1.0]:
				CP._tri(face, at.call(s * 0.35, 0.42), at.call(s * 0.15, 0.12), at.call(s * 0.55, 0.12), glow, Vector3.BACK)
			CP._tri(face, at.call(0.0, 0.08), at.call(-0.08, -0.1), at.call(0.08, -0.1), glow, Vector3.BACK)
			var mouth := [[-0.6, -0.22], [-0.4, -0.38], [-0.25, -0.3], [-0.1, -0.45], [0.1, -0.33], [0.25, -0.47], [0.4, -0.35], [0.6, -0.22]]
			for k in mouth.size() - 1:
				var a: Array = mouth[k]
				var b: Array = mouth[k + 1]
				CP._quad(face, at.call(a[0], a[1]), at.call(b[0], b[1]), at.call(b[0], b[1] - 0.14), at.call(a[0], a[1] - 0.14), glow, Vector3.BACK)
		return [CP._end(st, true), CP._end(face, false)])
	RM._put(root, parts[0], CP._vmat("plant", 0.55))
	if id.ends_with("jackolantern"):
		RM._put(root, parts[1], RM._glow(Color(1.0, 0.62, 0.15), 2.2), false)


static func _ribcage(root: Node3D, _id: String) -> void:
	var parts := _cached("ribcage", func() -> Array:
		var st := CP._begin()
		# the spine: a column of vertebrae
		for k in 9:
			var y := 0.04 + k * 0.065
			CP._lathe(st, [[0.0, -0.02], [0.035, -0.02], [0.04, 0.0], [0.035, 0.02], [0.0, 0.02]], 8, func(_i, _a): return BONE, Vector3(0, y, -0.18))
			CP._box(st, Vector3(0, y, -0.23), Vector3(0.02, 0.03, 0.06), BONE.darkened(0.05))
		# ribs: curving round from the spine to the breastbone, shorter at the top and bottom
		for k in 6:
			var y := 0.12 + k * 0.08
			var span := 0.18 + 0.08 * sin(PI * (k + 0.5) / 6.0)
			for s: float in [-1.0, 1.0]:
				var pts := []
				for m in 8:
					var a := PI * m / 7.0
					pts.append(Vector3(s * sin(a) * span, y - 0.04 * sin(a), -0.18 + (1.0 - cos(a)) * 0.2))
				CP._tube(st, pts, [0.012, 0.016, 0.016, 0.015, 0.014, 0.013, 0.012, 0.01], BONE, 5)
		CP._box(st, Vector3(0, 0.33, 0.22), Vector3(0.05, 0.35, 0.025), BONE.lightened(0.04), Basis(Vector3.RIGHT, 0.15))   # breastbone
		return [CP._end(st, true)])
	RM._put(root, parts[0], _mat_soft())


# The shrine: a stepped stone obelisk with a niche and a carved skull; "candles": a lower black altar with a cluster
# of dripping candles on top.
static func _shrine(root: Node3D, id: String) -> void:
	var parts := _cached(id, func() -> Array:
		var st := CP._begin()
		var dark := CP._begin()
		var wax := CP._begin()
		var spots := []
		if id.ends_with("candles"):
			var black := Color(0.2, 0.2, 0.22)
			_slab(st, Vector3(0, 0.08, 0), Vector3(0.8, 0.16, 0.8), black.darkened(0.1))
			_slab(st, Vector3(0, 0.5, 0), Vector3(0.62, 0.7, 0.62), black)
			_slab(st, Vector3(0, 0.88, 0), Vector3(0.72, 0.08, 0.72), black.lightened(0.05))
			CP._box(dark, Vector3(0, 0.5, 0.312), Vector3(0.3, 0.4, 0.004), Color(0.08, 0.08, 0.09))
			for c in [[Vector3(-0.15, 0.92, -0.1), 0.06, 0.32], [Vector3(0.12, 0.92, -0.05), 0.05, 0.24], [Vector3(-0.02, 0.92, 0.15), 0.045, 0.18],
					[Vector3(0.18, 0.92, 0.18), 0.035, 0.12]]:
				spots.append(_candle(wax, c[0], c[1], c[2], WAX, c[0].x * 10.0))
			for k in 6:   # wax dripped down the sides
				CP._box(wax, Vector3(-0.3 + 0.12 * k, 0.86, 0.362), Vector3(0.03, 0.08 + 0.1 * CP._h(k), 0.006), WAX)
		else:
			_slab(st, Vector3(0, 0.1, 0), Vector3(0.8, 0.2, 0.8), STONE.darkened(0.1))
			_slab(st, Vector3(0, 0.26, 0), Vector3(0.66, 0.12, 0.66), STONE.darkened(0.05))
			_slab(st, Vector3(0, 0.9, 0), Vector3(0.5, 1.16, 0.5), STONE)
			_slab(st, Vector3(0, 1.52, 0), Vector3(0.58, 0.08, 0.58), STONE.lightened(0.05))
			CP._lathe(st, [[0.29, 0.0], [0.0, 0.24]], 4, func(_i, _a): return STONE.lightened(0.08), Vector3(0, 1.56, 0))
			CP._box(dark, Vector3(0, 0.95, 0.251), Vector3(0.28, 0.5, 0.004), STONE.darkened(0.35))   # niche
			_skull(st, dark, Vector3(0, 0.9, 0.18), 0.09, STONE.lightened(0.12))
			_moss(st, Vector3(0, 0.2, 0), Vector3(0.8, 0.0, 0.8), 9.0, 8)
		return [CP._end(st, false), CP._end(dark, false), CP._end(wax, true), spots])
	RM._put(root, parts[0], _mat_stone())
	RM._put(root, parts[1], _mat_stone(), false)
	RM._put(root, parts[2], _mat_soft(), false)
	if id.ends_with("candles"):
		_flames(root, parts[3])


static func _skull_prop(root: Node3D, id: String) -> void:
	var parts := _cached(id, func() -> Array:
		var st := CP._begin()
		var dark := CP._begin()
		var wax := CP._begin()
		var spots := []
		_skull(st, dark, Vector3(0, 0.12 + 0.3 * 0.35, 0), 0.3, BONE)
		# cracks across the crown
		for k in 3:
			CP._box(dark, Vector3(-0.08 + k * 0.07, 0.48, 0.1 - 0.06 * k), Vector3(0.006, 0.006, 0.12), Color(0.35, 0.3, 0.25), Basis(Vector3.UP, 0.6 * k))
		if id.ends_with("candle"):
			spots.append(_candle(wax, Vector3(-0.06, 0.38, -0.02), 0.05, 0.34, WAX, 7.0))
			spots.append(_candle(wax, Vector3(0.08, 0.36, 0.04), 0.04, 0.22, WAX.darkened(0.03), 8.0))
			for k in 5:
				CP._box(wax, Vector3(-0.1 + 0.05 * k, 0.33 - 0.05 * CP._h(k), 0.2 - 0.02 * k), Vector3(0.025, 0.08 + 0.06 * CP._h(k * 2.0), 0.02), WAX)
		return [CP._end(st, false), CP._end(dark, false), CP._end(wax, true), spots])
	RM._put(root, parts[0], _mat_soft())
	RM._put(root, parts[1], _mat_soft(), false)
	if id.ends_with("candle"):
		RM._put(root, parts[2], _mat_soft(), false)
		_flames(root, parts[3])


# ---------------------------------------------------------------- structures

# The crypt: a little stone mausoleum on a stepped base, two columns either side of an iron-studded door under a
# pediment, a slate roof, an urn on the ridge, moss along the eaves. (4.5 x 6 x 6, the door at +z)
static func _crypt(root: Node3D, _id: String) -> void:
	var parts := _cached("crypt", func() -> Array:
		var st := CP._begin()
		var dark := CP._begin()
		var roof := CP._begin()
		var w := 4.2
		var d := 5.6
		_slab(st, Vector3(0, 0.15, 0), Vector3(4.5, 0.3, 6.0), STONE.darkened(0.12))
		_slab(st, Vector3(0, 0.38, 0.1), Vector3(4.3, 0.16, 5.8), STONE.darkened(0.06))
		_slab(st, Vector3(0, 1.95, -0.2), Vector3(w - 0.4, 3.0, d - 0.8), STONE)
		# corner pilasters and the front columns
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				_slab(st, Vector3(sx * (w * 0.5 - 0.35), 1.95, -0.2 + sz * ((d - 0.8) * 0.5 - 0.15)), Vector3(0.5, 3.0, 0.5), STONE.lightened(0.04))
			CP._lathe(st, [[0.2, 0.0], [0.17, 0.08], [0.15, 0.2], [0.14, 2.6], [0.17, 2.7], [0.2, 2.78]], 14, func(_i, _a): return STONE.lightened(0.07),
					Vector3(sx * 1.25, 0.46, 2.6))
		# the entablature and pediment over the front
		_slab(st, Vector3(0, 3.38, 1.9), Vector3(w, 0.28, 1.6), STONE.lightened(0.03))
		var ped := [Vector2(-w * 0.5, 0.0), Vector2(w * 0.5, 0.0), Vector2(0.0, 1.0)]
		_extrude(st, Vector3(0, 3.52, 2.62), ped, 0.25, STONE.lightened(0.05))
		# the door: dark iron with studs and a ring
		CP._box(dark, Vector3(0, 1.45, 2.32), Vector3(1.4, 2.1, 0.08), Color(0.13, 0.13, 0.14))
		for k in 5:
			for m in 3:
				CP._box(dark, Vector3(-0.5 + 0.25 * k, 0.6 + 0.6 * m + 0.25, 2.37), Vector3(0.04, 0.04, 0.03), Color(0.3, 0.28, 0.25))
		CP._ring(dark, Vector3(0.3, 1.4, 2.4), 0.08, 0.012, Color(0.4, 0.35, 0.28), 12, 4)
		CP._box(st, Vector3(0, 2.6, 2.36), Vector3(1.8, 0.2, 0.12), STONE.lightened(0.08))   # lintel
		# the roof: two slate slopes and a ridge
		for s: float in [-1.0, 1.0]:
			for k in 9:
				var z0 := -2.95 + k * 0.66
				var ang := s * 0.48
				CP._box(roof, Vector3(s * 1.15, 4.15, z0 + 0.33), Vector3(2.55, 0.08, 0.7), Color(0.27, 0.28, 0.32).lightened(0.04 * (k % 2)), Basis(Vector3.BACK, ang))
		CP._box(roof, Vector3(0, 4.72, -0.1), Vector3(0.22, 0.18, 5.9), Color(0.22, 0.22, 0.25))
		CP._lathe(st, [[0.0, 0.0], [0.12, 0.0], [0.08, 0.08], [0.16, 0.25], [0.12, 0.4], [0.06, 0.45], [0.0, 0.46]], 12, func(_i, _a): return STONE.lightened(0.05), Vector3(0, 4.8, 1.8))
		_moss(st, Vector3(0, 0.46, 0), Vector3(4.3, 0.0, 5.8), 11.0, 14)
		return [CP._end(st, false), CP._end(dark, false), CP._end(roof, false)])
	RM._put(root, parts[0], _mat_stone())
	RM._put(root, parts[1], _mat_iron())
	RM._put(root, parts[2], CP._vmat("stone", 0.7))


# The graveyard fence: stone pillars at both ends with iron railing between; broken: bars missing and bent, one
# pillar broken off; gate: a taller pair of iron gate leaves between taller pillars.
static func _fence(root: Node3D, id: String) -> void:
	var parts := _cached(id, func() -> Array:
		var st := CP._begin()
		var iron := CP._begin()
		var gate := id.ends_with("gate")
		var broken := id.ends_with("broken")
		var ph := 2.25 if gate else 1.65
		for s: float in [-1.0, 1.0]:
			_post_pillar(st, Vector3(s * 1.31, 0, 0), 0.38, ph, broken and s > 0.0)
		_slab(st, Vector3(0, 0.1, 0), Vector3(2.3, 0.2, 0.26), STONE.darkened(0.08))   # the low wall the railing sits in
		if gate:
			for s: float in [-1.0, 1.0]:
				var x0 := s * 0.06
				var x1 := s * 1.1
				_bars(iron, minf(x0, x1), maxf(x0, x1), 0.2, 1.8)
				# an arched top rail
				var arc := []
				var radii := []
				for k in 9:
					var t := float(k) / 8.0
					arc.append(Vector3(lerpf(x0, x1, t), 1.65 + 0.2 * sin(PI * t * 0.5 + (0.0 if s > 0.0 else PI * 0.5)), 0))
					radii.append(0.016)
				CP._tube(iron, arc, radii, IRON, 5)
			CP._box(iron, Vector3(0, 1.0, 0.03), Vector3(0.08, 0.15, 0.02), IRON.lightened(0.1))   # the latch
		else:
			_bars(iron, -1.1, 1.1, 0.2, 1.35, broken)
		return [CP._end(st, false), CP._end(iron, false)])
	RM._put(root, parts[0], _mat_stone())
	RM._put(root, parts[1], _mat_iron())


static func _fence_pillar(root: Node3D, id: String) -> void:
	var parts := _cached(id, func() -> Array:
		var st := CP._begin()
		_post_pillar(st, Vector3.ZERO, 0.38, 1.65, id.ends_with("broken"))
		_moss(st, Vector3(0, 0.0, 0), Vector3(0.38, 0.32, 0.38), 5.0, 3)
		return [CP._end(st, false)])
	RM._put(root, parts[0], _mat_stone())


static func _railing(root: Node3D, id: String) -> void:
	var parts := _cached(id, func() -> Array:
		var iron := CP._begin()
		_bars(iron, -1.48, 1.48, 0.0, 1.5, id.ends_with("broken"))
		return [CP._end(iron, false)])
	RM._put(root, parts[0], _mat_iron())


# Dirt: a raw earth slab with clods, pebbles and roots in its sides and a lumpy top; "grave": an open grave dug in it,
# its walls cut, the spoil heaped to one side.
static func _dirt(root: Node3D, id: String) -> void:
	var parts := _cached(id, func() -> Array:
		var st := CP._begin()
		var bits := CP._begin()
		var size := 1.5 if id.ends_with("small") else 3.0
		var h := 1.15 if id.ends_with("grave") else 0.4
		var soil := Color(0.33, 0.23, 0.15)
		var n := 12 if size > 2.0 else 7
		var top := func(x: float, z: float) -> float:
			return h + 0.025 * sin(x * 7.0 + z * 3.0) + 0.02 * sin(z * 9.0 - x * 2.0)
		var hole := id.ends_with("grave")
		for i in n:
			for j in n:
				var x0 := -size * 0.5 + size * i / n
				var x1 := -size * 0.5 + size * (i + 1) / n
				var z0 := -size * 0.5 + size * j / n
				var z1 := -size * 0.5 + size * (j + 1) / n
				var cx := (x0 + x1) * 0.5
				var cz := (z0 + z1) * 0.5
				if hole and absf(cx) < 0.55 and absf(cz) < 1.05:
					continue
				var col := soil.lerp(Color(0.25, 0.17, 0.1), CP._h(i * 13.0 + j))
				CP._quad(st, Vector3(x0, top.call(x0, z0), z0), Vector3(x1, top.call(x1, z0), z0), Vector3(x1, top.call(x1, z1), z1), Vector3(x0, top.call(x0, z1), z1), col, Vector3.UP)
		# sides
		for s in 4:
			for k in n:
				var t0 := -size * 0.5 + size * k / n
				var t1 := -size * 0.5 + size * (k + 1) / n
				var e := size * 0.5
				var pts: Array = [[Vector3(t0, 0, e), Vector3(t1, 0, e)], [Vector3(e, 0, -t0), Vector3(e, 0, -t1)], [Vector3(-t0, 0, -e), Vector3(-t1, 0, -e)], [Vector3(-e, 0, t0), Vector3(-e, 0, t1)]][s]
				var a: Vector3 = pts[0]
				var b: Vector3 = pts[1]
				var out := Vector3(a.x + b.x, 0, a.z + b.z).normalized()
				CP._quad(st, a, b, Vector3(b.x, top.call(b.x, b.z), b.z), Vector3(a.x, top.call(a.x, a.z), a.z), soil.darkened(0.15 + 0.1 * float(k % 2)), out)
		if hole:
			var hd := 1.0   # how deep
			var hx := 0.55
			var hz := 1.05
			for f in [[Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(0, 0, 1)], [Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-1, 0, 0)],
					[Vector3(hx, 0, hz), Vector3(-hx, 0, hz), Vector3(0, 0, -1)], [Vector3(-hx, 0, hz), Vector3(-hx, 0, -hz), Vector3(1, 0, 0)]]:
				var a: Vector3 = f[0]
				var b: Vector3 = f[1]
				CP._quad(st, a + Vector3.UP * (h - hd), b + Vector3.UP * (h - hd), b + Vector3.UP * h, a + Vector3.UP * h, soil.darkened(0.3), f[2])
			CP._quad(st, Vector3(-hx, h - hd, -hz), Vector3(hx, h - hd, -hz), Vector3(hx, h - hd, hz), Vector3(-hx, h - hd, hz), soil.darkened(0.45), Vector3.UP)
			CP._lathe(bits, [[0.0, h], [0.5, h], [0.34, h + 0.2], [0.14, h + 0.3], [0.0, h + 0.32]], 14, func(_i, _a): return soil.lightened(0.05), Vector3(0.95, 0, 0.3))
		for k in int(size * size * 4.0):   # clods and pebbles on top
			var p := Vector3((CP._h(k * 1.7) - 0.5) * size * 0.92, 0.0, (CP._h(k * 2.9) - 0.5) * size * 0.92)
			if hole and absf(p.x) < 0.65 and absf(p.z) < 1.15:
				continue
			p.y = top.call(p.x, p.z) + 0.012
			var pebble := CP._h(k * 5.3) > 0.6
			CP._box(bits, p, Vector3(0.05, 0.03, 0.04) * (1.0 + CP._h(k)), Color(0.5, 0.48, 0.45) if pebble else soil.darkened(0.2), Basis(Vector3.UP, k))
		return [CP._end(st, false), CP._end(bits, false)])
	RM._put(root, parts[0], CP._vmat("stone", 1.0))
	RM._put(root, parts[1], CP._vmat("stone", 0.95), false)


# Paths: flagstones of different sizes and tones with grass and moss in the gaps.
static func _path(root: Node3D, id: String) -> void:
	var parts := _cached(id, func() -> Array:
		var st := CP._begin()
		var grass := CP._begin()
		var seed := float(id.unicode_at(id.length() - 1))
		var size := 1.4 if not id.ends_with("D") else 1.25
		CP._box(grass, Vector3(0, 0.015, 0), Vector3(size, 0.03, size), Color(0.25, 0.33, 0.16))
		var cells := 3
		for i in cells:
			for j in cells:
				var c := Vector3(-size * 0.5 + size * (i + 0.5) / cells, 0.04, -size * 0.5 + size * (j + 0.5) / cells)
				if CP._h(seed + i * 3.0 + j) < 0.12:
					continue   # a missing stone: grass shows
				var s := size / cells - 0.06 - 0.04 * CP._h(seed + i + j * 5.0)
				var stone := STONE.lerp(Color(0.48, 0.47, 0.43), CP._h(seed * 2.0 + i + j * 7.0)).darkened(0.05)
				_slab(st, c + Vector3((CP._h(seed + i) - 0.5) * 0.04, 0.0, (CP._h(seed + j) - 0.5) * 0.04), Vector3(s, 0.06, s * (0.85 + 0.15 * CP._h(i * 5.0 + j))), stone, 0.015,
						Basis(Vector3.UP, (CP._h(seed + i * 9.0 + j) - 0.5) * 0.3))
		return [CP._end(st, false), CP._end(grass, false)])
	RM._put(root, parts[0], _mat_stone())
	RM._put(root, parts[1], CP._vmat("plant", 1.0))


static func _pillar(root: Node3D, _id: String) -> void:
	var parts := _cached("pillar", func() -> Array:
		var st := CP._begin()
		_post_pillar(st, Vector3.ZERO, 0.75, 3.15)
		_moss(st, Vector3(0, 0.0, 0), Vector3(0.75, 0.32, 0.75), 2.0, 5)
		return [CP._end(st, false)])
	RM._put(root, parts[0], _mat_stone())


# A memorial plaque: a low slab with a raised, bevelled panel carved with a cross; "candles": candles stood round it.
static func _plaque(root: Node3D, id: String) -> void:
	var parts := _cached(id, func() -> Array:
		var st := CP._begin()
		var wax := CP._begin()
		var spots := []
		_slab(st, Vector3(0, 0.08, 0), Vector3(1.5, 0.16, 1.5), STONE.darkened(0.1))
		_slab(st, Vector3(0, 0.2, 0), Vector3(1.1, 0.1, 1.1), STONE.lightened(0.03))
		CP._box(st, Vector3(0, 0.253, 0.0), Vector3(0.1, 0.01, 0.6), STONE.darkened(0.25))
		CP._box(st, Vector3(0, 0.253, -0.12), Vector3(0.4, 0.01, 0.1), STONE.darkened(0.25))
		_moss(st, Vector3(0, 0.0, 0), Vector3(1.5, 0.16, 1.5), 4.0, 10)
		if id.ends_with("candles"):
			for c in [[Vector3(-0.55, 0.16, 0.55), 0.07, 0.5], [Vector3(-0.42, 0.16, 0.6), 0.05, 0.3], [Vector3(0.55, 0.16, -0.55), 0.06, 0.42],
					[Vector3(0.6, 0.16, -0.38), 0.045, 0.22], [Vector3(0.0, 0.25, 0.35), 0.05, 0.25]]:
				spots.append(_candle(wax, c[0], c[1], c[2], WAX, c[0].x * 7.0 + c[0].z))
		return [CP._end(st, false), CP._end(wax, true), spots])
	RM._put(root, parts[0], _mat_stone())
	if id.ends_with("candles"):
		RM._put(root, parts[1], _mat_soft(), false)
		_flames(root, parts[2])


# A rough timber post with a bracket arm reaching out (to -z, like the KayKit one), a brace under the arm; lantern:
# a lantern hangs from the arm; skull: a skull hangs from it on a rope.
static func _post(root: Node3D, id: String) -> void:
	var parts := _cached(id, func() -> Array:
		var st := CP._begin()
		var iron := CP._begin()
		var glass := CP._begin()
		var dark := CP._begin()
		var x := 0.0
		CP._box(st, Vector3(x, 1.2, 0.0), Vector3(0.16, 2.4, 0.16), TIMBER)
		CP._box(st, Vector3(x, 2.3, -0.45), Vector3(0.12, 0.12, 1.0), TIMBER.lightened(0.04))
		CP._box(st, Vector3(x, 2.05, -0.2), Vector3(0.08, 0.08, 0.55), TIMBER.darkened(0.08), Basis(Vector3.RIGHT, -0.75))
		for k in 8:   # grain splits
			CP._box(dark, Vector3(x + 0.081, 0.3 + 0.25 * k, (CP._h(k) - 0.5) * 0.1), Vector3(0.002, 0.18, 0.006), TIMBER.darkened(0.4))
		CP._lathe(st, [[0.0, 2.4], [0.1, 2.4], [0.0, 2.48]], 4, func(_i, _a): return TIMBER.darkened(0.1))   # a little cap
		var spots := []
		var hang := Vector3(x, 2.24, -0.85)
		CP._ring(iron, hang, 0.03, 0.008, IRON, 8, 4)
		if id.ends_with("lantern"):
			spots.append(_lantern(iron, glass, hang + Vector3(0, -0.62, 0), 1.0))
			CP._tube(iron, [hang, hang + Vector3(0, -0.15, 0)], [0.008, 0.008], IRON, 4)
		elif id.ends_with("skull"):
			CP._tube(st, [hang, hang + Vector3(0.0, -0.35, 0.01)], [0.012, 0.012], Color(0.55, 0.45, 0.3), 4)
			_skull(st, dark, hang + Vector3(0, -0.5, 0), 0.13, BONE)
		return [CP._end(st, false), CP._end(iron, false), CP._end(glass, false), CP._end(dark, false), spots])
	RM._put(root, parts[0], _mat_wood())
	RM._put(root, parts[1], _mat_iron(), false)
	RM._put(root, parts[2], RM._glow(Color(1.0, 0.82, 0.45), 0.7), false)
	RM._put(root, parts[3], _mat_soft(), false)


# The graveyard arch (and arch with a gate): the same stonework and ironwork as Creative's Arched Gate, which was
# made to this arch's size (hollow_buildings.gd).
static func _arch(root: Node3D, id: String) -> void:
	var HB = load("res://scripts/hollow_buildings.gd")
	var mesh: ArrayMesh = HB.gate_mesh(id.ends_with("gate"))
	RM._put(root, mesh, null)


# A skeleton lying in the open coffin.
static func _skeleton(st: SurfaceTool, dark: SurfaceTool) -> void:
		_skull(st, dark, Vector3(0, 0.12, 0.72), 0.13, BONE)
		for k in 7:
			CP._lathe(st, [[0.0, -0.015], [0.03, -0.015], [0.035, 0.0], [0.03, 0.015], [0.0, 0.015]], 8, func(_i, _a): return BONE, Vector3(0, 0.08, 0.5 - k * 0.09))
		for k in 4:
			for s: float in [-1.0, 1.0]:
				CP._tube(st, [Vector3(0, 0.1, 0.42 - k * 0.07), Vector3(s * 0.12, 0.12, 0.4 - k * 0.07), Vector3(s * 0.15, 0.08, 0.36 - k * 0.07)], [0.01, 0.012, 0.009], BONE, 4)
		for s: float in [-1.0, 1.0]:
			CP._tube(st, [Vector3(s * 0.15, 0.08, 0.45), Vector3(s * 0.22, 0.07, 0.15), Vector3(s * 0.16, 0.07, -0.1)], [0.018, 0.016, 0.014], BONE, 6)   # arms
			CP._tube(st, [Vector3(s * 0.08, 0.08, -0.15), Vector3(s * 0.1, 0.07, -0.5), Vector3(s * 0.09, 0.07, -0.85)], [0.022, 0.02, 0.017], BONE, 6)   # legs
		CP._box(st, Vector3(0, 0.08, -0.12), Vector3(0.26, 0.06, 0.12), BONE.darkened(0.05))   # pelvis
