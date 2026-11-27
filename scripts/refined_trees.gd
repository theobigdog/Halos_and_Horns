# Trees, refined (Ted's wife, Nov 27: "all trees"). Same sizes and footprints as the KayKit ones they replace
# (refined_models.gd explains how they're used):
#   - conifers (the graveyard's golden, rust and green pines; the medieval pine and its clusters): a barked trunk
#     and tiers of drooping boughs, each bough a tapering, sagging plane with needle cards over it;
#   - broadleaf trees (the medieval round tree and its clusters): a forked trunk and a crown of leafy clumps;
#   - dead trees: gnarled, forking bare branches with lichen; the decorated one has a lantern and skulls hung on it;
#   - stumps: a cut top showing the growth rings, bark round the side, chips about (singles and clearings).
# Everything is seeded per model, so every copy (and every screen) grows the same tree. Leaf counts are kept
# moderate: these are placed in forests.
extends RefCounted

const CP = preload("res://scripts/classic_props.gd")
const RM = preload("res://scripts/refined_models.gd")

const BUILDERS := {
	"halloween/tree_dead_large": "_dead", "halloween/tree_dead_large_decorated": "_dead", "halloween/tree_dead_medium": "_dead",
	"halloween/tree_dead_small": "_dead",
	"halloween/tree_pine_orange_large": "_pine", "halloween/tree_pine_orange_medium": "_pine", "halloween/tree_pine_orange_small": "_pine",
	"halloween/tree_pine_yellow_large": "_pine", "halloween/tree_pine_yellow_medium": "_pine", "halloween/tree_pine_yellow_small": "_pine",
	"halloween/tree_pine_green_large": "_pine", "halloween/tree_pine_green_medium": "_pine", "halloween/tree_pine_green_small": "_pine",
	"medieval/tree_single_A": "_pine", "medieval/tree_single_B": "_broadleaf", "medieval/tree_single_A_cut": "_stump",
	"medieval/tree_single_B_cut": "_stump", "medieval/trees_A_large": "_grove", "medieval/trees_A_medium": "_grove",
	"medieval/trees_A_small": "_grove", "medieval/trees_B_large": "_grove", "medieval/trees_B_medium": "_grove",
	"medieval/trees_B_small": "_grove", "medieval/trees_A_cut": "_clearing", "medieval/trees_B_cut": "_clearing",
}

const NEEDLES := {
	"green": [Color(0.1, 0.28, 0.12), Color(0.14, 0.34, 0.14), Color(0.08, 0.22, 0.1)],
	"yellow": [Color(0.85, 0.6, 0.15), Color(0.95, 0.72, 0.25), Color(0.7, 0.48, 0.1)],
	"orange": [Color(0.78, 0.32, 0.08), Color(0.88, 0.45, 0.12), Color(0.6, 0.22, 0.06)],
}
const BARK := Color(0.33, 0.24, 0.17)


static func _size(id: String) -> Vector3:
	var Models = load("res://scripts/models.gd")
	return Models.size(id)


static func _palette(id: String) -> String:
	if "yellow" in id:
		return "yellow"
	if "orange" in id:
		return "orange"
	return "green"


# A bark-covered tube (furrowed: darker in the cracks).
static func _bark(st: SurfaceTool, pts: Array, radii: Array, col: Color, sides := 8) -> void:
	CP._tube(st, pts, radii, col, sides)


# ---------------------------------------------------------------- conifers

# One conifer of height h and spread w at `at`, into the trunk and bough surfaces; its needle spots go in `spots`.
static func _conifer(trunk: SurfaceTool, boughs: SurfaceTool, at: Vector3, h: float, w: float, pal: String, seed: int, spots: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var cols: Array = NEEDLES[pal]
	var base_r := w * 0.06
	_bark(trunk, [at, at + Vector3(0, h * 0.5, 0), at + Vector3(0, h * 0.97, 0)], [base_r * 1.3, base_r * 0.7, base_r * 0.15], BARK, 8)
	for k in 4:   # root flare
		var a := TAU * k / 4.0 + rng.randf()
		_bark(trunk, [at + Vector3(0, base_r * 1.5, 0), at + Vector3(cos(a), 0, sin(a)) * base_r * 2.6 + Vector3(0, -0.02, 0)], [base_r * 0.5, base_r * 0.15], BARK.darkened(0.1), 5)
	var tiers := 6 if h > 4.0 else (5 if h > 2.5 else 4)
	for t in tiers:
		var f := float(t) / tiers   # 0 bottom tier .. 1 top
		var y := at.y + h * (0.18 + 0.72 * f)
		var reach := w * 0.5 * (1.0 - f * 0.82)
		var n := 9 - int(f * 4.0)
		var spin := rng.randf() * TAU
		for b in n:
			var a := spin + TAU * b / n + rng.randf_range(-0.2, 0.2)
			var dir := Vector3(cos(a), 0, sin(a))
			var side := dir.cross(Vector3.UP)
			var root := at + Vector3(0, y - at.y, 0)
			var tip := root + dir * reach * rng.randf_range(0.85, 1.05) + Vector3.DOWN * reach * 0.45
			var mid := root.lerp(tip, 0.5) + Vector3.UP * reach * 0.08
			var wdt := reach * 0.5
			var col: Color = cols[b % cols.size()].darkened(0.15 * (1.0 - f))
			# a sagging, tapering bough: two strips (root-mid, mid-tip), a little ridge along the middle
			var quads := [[root, mid, wdt * 0.25, wdt], [mid, tip, wdt, wdt * 0.15]]
			for q in quads:
				var p0: Vector3 = q[0]
				var p1: Vector3 = q[1]
				var w0: float = q[2]
				var w1: float = q[3]
				var up := Vector3.UP * 0.04 * reach
				CP._quad(boughs, p0 - side * w0, p1 - side * w1, p1 + up, p0 + up, col, Vector3.UP + side * -0.3)
				CP._quad(boughs, p0 + up, p1 + up, p1 + side * w1, p0 + side * w0, col.lightened(0.05), Vector3.UP + side * 0.3)
				CP._quad(boughs, p0 - side * w0, p0 + side * w0, p1 + side * w1, p1 - side * w1, col.darkened(0.3), Vector3.DOWN)
			spots.append([mid + Vector3.UP * 0.03, reach * 0.32])
			spots.append([root.lerp(tip, 0.85), reach * 0.22])
	# the leader at the very top
	CP._lathe(boughs, [[w * 0.06, h * 0.88], [0.0, h * 1.0]], 6, func(_i, _a): return cols[0], at)


static func _pine(root: Node3D, id: String) -> void:
	var s := _size(id)
	var pal := _palette(id) if id.begins_with("halloween") else "green"
	var parts := RM._cached("t_" + id, func() -> Array:
		var trunk := CP._begin()
		var boughs := CP._begin()
		var spots := []
		_conifer(trunk, boughs, Vector3.ZERO, s.y, minf(s.x, s.z) * 1.05, pal, hash(id) % 1000, spots)
		return [CP._end(trunk, true), CP._end(boughs, false), spots])
	RM._put(root, parts[0], CP._vmat("wood", 0.95))
	RM._put(root, parts[1], CP._vmat("plant", 0.85, -1.0, true))
	CP._foliage(root, "needles_" + id, parts[2], parts[2].size() * 14, 0.16, NEEDLES[pal], hash(id) % 997, "leaf")
	_no_collide_foliage(root)


# ---------------------------------------------------------------- broadleaf

static func _broadleaf_tree(trunk: SurfaceTool, at: Vector3, h: float, w: float, seed: int, spots: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var r := w * 0.05
	var fork := at + Vector3(rng.randf_range(-0.1, 0.1), h * 0.28, rng.randf_range(-0.1, 0.1))
	_bark(trunk, [at, at.lerp(fork, 0.5) + Vector3(0.03, 0, 0), fork], [r * 1.4, r, r * 0.85], BARK, 8)
	for k in 3:
		var a := TAU * k / 3.0 + rng.randf()
		var tip := fork + Vector3(cos(a) * w * 0.22, h * rng.randf_range(0.25, 0.35), sin(a) * w * 0.22)
		_bark(trunk, [fork, fork.lerp(tip, 0.5) + Vector3.UP * 0.1, tip], [r * 0.7, r * 0.5, r * 0.25], BARK, 6)
	var ctr := at + Vector3(0, h * 0.6, 0)
	for k in 16:
		var y := 1.0 - 2.0 * (k + 0.5) / 16.0
		var ring := sqrt(maxf(0.0, 1.0 - y * y))
		var a := k * 2.39996
		spots.append([ctr + Vector3(cos(a) * ring * w * 0.36, y * h * 0.3, sin(a) * ring * w * 0.36), w * rng.randf_range(0.19, 0.25)])


static func _broadleaf(root: Node3D, id: String) -> void:
	var s := _size(id)
	var parts := RM._cached("t_" + id, func() -> Array:
		var trunk := CP._begin()
		var spots := []
		_broadleaf_tree(trunk, Vector3.ZERO, s.y, minf(s.x, s.z), 77, spots)
		return [CP._end(trunk, true), spots, CP._clumps(spots, Color(0.13, 0.3, 0.1), 9)])
	RM._put(root, parts[0], CP._vmat("wood", 0.95))
	RM._put(root, parts[2], CP._vmat("plant", 0.9), false)
	CP._foliage(root, "leaves_" + id, parts[1], parts[1].size() * 70, 0.2, [Color(0.17, 0.38, 0.12), Color(0.22, 0.45, 0.15), Color(0.13, 0.3, 0.09)], 33)
	_no_collide_foliage(root)


# A grove: a patch of conifers (A) or round broadleaf trees (B), spaced out over the footprint, tallest in the middle.
static func _grove(root: Node3D, id: String) -> void:
	var s := _size(id)
	var conifers := id.begins_with("medieval/trees_A")
	var parts := RM._cached("t_" + id, func() -> Array:
		var trunk := CP._begin()
		var boughs := CP._begin()
		var spots := []
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(id)
		var count := int(s.x * s.z / (4.2 if conifers else 6.0))
		var placed := []
		for k in count * 4:
			if placed.size() >= count:
				break
			var p := Vector3(rng.randf_range(-0.42, 0.42) * s.x, 0, rng.randf_range(-0.42, 0.42) * s.z)
			var clear := true
			for q in placed:
				if (q as Vector3).distance_to(p) < (1.3 if conifers else 1.9):
					clear = false
			if not clear:
				continue
			placed.append(p)
			var centre := 1.0 - 0.45 * Vector2(p.x / s.x, p.z / s.z).length() * 2.0
			var h := s.y * clampf(centre, 0.55, 1.0) * rng.randf_range(0.85, 1.0)
			if conifers:
				_conifer(trunk, boughs, p, h, h * 0.42, "green", rng.randi() % 1000, spots)
			else:
				_broadleaf_tree(trunk, p, h, h * 0.55, rng.randi() % 1000, spots)
		var cl: ArrayMesh = null if conifers else CP._clumps(spots, Color(0.13, 0.3, 0.1), 9)
		return [CP._end(trunk, true), CP._end(boughs, false), spots, cl])
	RM._put(root, parts[0], CP._vmat("wood", 0.95))
	if conifers:
		RM._put(root, parts[1], CP._vmat("plant", 0.85, -1.0, true))
		CP._foliage(root, "needles_" + id, parts[2], parts[2].size() * 8, 0.18, NEEDLES["green"], hash(id) % 997, "leaf")
	else:
		RM._put(root, parts[3], CP._vmat("plant", 0.9), false)
		CP._foliage(root, "leaves_" + id, parts[2], parts[2].size() * 30, 0.24, [Color(0.17, 0.38, 0.12), Color(0.22, 0.45, 0.15), Color(0.13, 0.3, 0.09)], hash(id) % 991)
	_no_collide_foliage(root)


# ---------------------------------------------------------------- dead trees and stumps

static func _branch(st: SurfaceTool, rng: RandomNumberGenerator, base: Vector3, dir: Vector3, len: float, r: float, depth: int, tips: Array) -> void:
	var pts := [base]
	var radii := [r]
	var p := base
	var d := dir
	for k in 4:
		d = (d + Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.1, 0.25), rng.randf_range(-0.35, 0.35))).normalized()
		p += d * len / 4.0
		pts.append(p)
		radii.append(r * (1.0 - 0.2 * (k + 1)))
	_bark(st, pts, radii, Color(0.3, 0.27, 0.24), 6)
	tips.append(p)
	if depth > 0:
		for s: float in [-1.0, 1.0]:
			var side := d.cross(Vector3.UP).normalized() * s
			var at: Vector3 = pts[rng.randi_range(2, 3)]
			_branch(st, rng, at, (d + side * 0.8 + Vector3.UP * 0.2).normalized(), len * 0.6, r * 0.5, depth - 1, tips)


static func _dead(root: Node3D, id: String) -> void:
	var s := _size(id)
	var parts := RM._cached("t_" + id, func() -> Array:
		var st := CP._begin()
		var lichen := CP._begin()
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(id)
		var h := s.y * 0.92
		var r := 0.12 if "large" in id else (0.09 if "medium" in id else 0.07)
		var tips := []
		# the trunk leans and twists, then splits
		var lean := Vector3(rng.randf_range(-0.15, 0.15), 1.0, rng.randf_range(-0.1, 0.1)).normalized()
		var top := lean * h * 0.55
		_bark(st, [Vector3.ZERO, lean * h * 0.2 + Vector3(0.05, 0, 0), top], [r * 1.5, r * 1.1, r * 0.85], Color(0.3, 0.27, 0.24), 8)
		for k in 3:   # roots
			var a := TAU * k / 3.0 + rng.randf()
			_bark(st, [Vector3(0, r, 0), Vector3(cos(a), 0, sin(a)) * r * 3.5 + Vector3(0, -0.03, 0)], [r * 0.7, r * 0.2], Color(0.27, 0.24, 0.21), 5)
		_branch(st, rng, top, (lean + Vector3(0.5, 0.3, 0)).normalized(), h * 0.5, r * 0.75, 2, tips)
		_branch(st, rng, top, (lean + Vector3(-0.6, 0.4, 0.1)).normalized(), h * 0.45, r * 0.65, 1 if "small" in id else 2, tips)
		# lichen and fungus on the trunk
		for k in 8:
			var y := h * 0.05 + h * 0.4 * CP._h(k * 3.1)
			var a := TAU * CP._h(k * 7.7)
			CP._box(lichen, lean * y + Vector3(cos(a), 0, sin(a)) * r * 1.1, Vector3(0.06, 0.03, 0.06), Color(0.55, 0.6, 0.45) if k % 3 else Color(0.7, 0.55, 0.3), Basis(Vector3.UP, a))
		var deco := CP._begin()
		var glass := CP._begin()
		var dark := CP._begin()
		if id.ends_with("decorated"):
			var G = load("res://scripts/refined_graveyard.gd")
			var hang: Vector3 = tips[0] if not tips.is_empty() else top
			CP._tube(deco, [hang, hang + Vector3(0, -0.3, 0)], [0.008, 0.008], Color(0.12, 0.12, 0.13), 4)
			G._lantern(deco, glass, hang + Vector3(0, -0.72, 0), 0.9)
			if tips.size() > 2:
				var t2: Vector3 = tips[2]
				CP._tube(deco, [t2, t2 + Vector3(0, -0.35, 0)], [0.008, 0.008], Color(0.5, 0.42, 0.3), 4)
				G._skull(deco, dark, t2 + Vector3(0, -0.47, 0), 0.11, Color(0.9, 0.85, 0.72))
		return [CP._end(st, true), CP._end(lichen, false), CP._end(deco, false), CP._end(glass, false), CP._end(dark, false)])
	var holder := Node3D.new()
	root.add_child(holder)
	RM._put(holder, parts[0], CP._vmat("wood", 0.95))
	RM._put(holder, parts[1], CP._vmat("plant", 0.9), false)
	if id.ends_with("decorated"):
		RM._put(holder, parts[2], RM._paint(Color.WHITE, 0.6, 0.4), false)
		RM._put(holder, parts[3], RM._glow(Color(1.0, 0.82, 0.45), 0.8), false)
		RM._put(holder, parts[4], CP._vmat("plaster", 0.8), false)


# A cut stump: bark round the side, the top sawn flat with growth rings, an axe notch; a few chips. `h` tall.
static func _stump_at(st: SurfaceTool, top: SurfaceTool, at: Vector3, r: float, h: float, seed: float) -> void:
	_bark(st, [at, at + Vector3(0, h * 0.5, 0), at + Vector3(0, h, 0)], [r * 1.15, r, r], BARK, 12)
	for k in 4:
		var a := TAU * k / 4.0 + seed
		_bark(st, [at + Vector3(0, r * 0.8, 0), at + Vector3(cos(a), 0, sin(a)) * r * 2.0 + Vector3(0, -0.02, 0)], [r * 0.45, r * 0.15], BARK.darkened(0.1), 5)
	var rings := 6
	for k in rings:
		var r0 := r * float(k) / rings
		var r1 := r * float(k + 1) / rings
		var c := Color(0.78, 0.6, 0.4).darkened(0.12 * float(k % 2) + (0.25 if k == rings - 1 else 0.0))
		for m in 16:
			var a0 := TAU * m / 16.0
			var a1 := TAU * (m + 1) / 16.0
			var y := at.y + h + 0.003
			CP._quad(top, Vector3(at.x + cos(a0) * r0, y, at.z + sin(a0) * r0), Vector3(at.x + cos(a1) * r0, y, at.z + sin(a1) * r0),
					Vector3(at.x + cos(a1) * r1, y, at.z + sin(a1) * r1), Vector3(at.x + cos(a0) * r1, y, at.z + sin(a0) * r1), c, Vector3.UP)


static func _stump(root: Node3D, id: String) -> void:
	var s := _size(id)
	var parts := RM._cached("t_" + id, func() -> Array:
		var st := CP._begin()
		var top := CP._begin()
		_stump_at(st, top, Vector3.ZERO, minf(s.x, s.z) * 0.42, s.y * 0.96, 0.5)
		return [CP._end(st, true), CP._end(top, false)])
	RM._put(root, parts[0], CP._vmat("wood", 0.95))
	RM._put(root, parts[1], CP._vmat("wood", 0.85))


# A clearing: stumps scattered over the footprint, with a fallen log and chips.
static func _clearing(root: Node3D, id: String) -> void:
	var s := _size(id)
	var parts := RM._cached("t_" + id, func() -> Array:
		var st := CP._begin()
		var top := CP._begin()
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(id)
		var placed := []
		for k in 30:
			if placed.size() >= int(s.x * s.z / 9.0):
				break
			var p := Vector3(rng.randf_range(-0.42, 0.42) * s.x, 0, rng.randf_range(-0.42, 0.42) * s.z)
			if placed.any(func(q): return (q as Vector3).distance_to(p) < 2.0):
				continue
			placed.append(p)
			_stump_at(st, top, p, rng.randf_range(0.22, 0.35), rng.randf_range(0.3, s.y * 0.8), rng.randf() * 6.0)
		var log_at := Vector3(s.x * 0.15, 0.25, -s.z * 0.1)
		_bark(st, [log_at + Vector3(-1.4, 0, 0), log_at + Vector3(1.4, 0.05, 0.2)], [0.26, 0.22], BARK, 10)
		return [CP._end(st, true), CP._end(top, false)])
	RM._put(root, parts[0], CP._vmat("wood", 0.95))
	RM._put(root, parts[1], CP._vmat("wood", 0.85))


static func _no_collide_foliage(root: Node3D) -> void:
	for c in root.get_children():
		if c is MultiMeshInstance3D:
			c.set_meta("no_collide", true)
