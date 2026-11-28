# Rounder models (Ted, Nov 27: "adjust any necessary props or structures resolution, to match whatever is best
# right now"). The KayKit models that haven't been rebuilt by hand yet (kitchen, dungeon, village, city) are
# low-poly: a barrel is an octagon, a bowl a decagon. They're shaded smooth, though, and that says which parts
# are meant to be round. This gives those parts the triangles to match: every curved face is split up and bent
# out onto the curve its neighbours describe, until no facet stands more than TOLERANCE off the true curve (so
# big round things get the most, about as many sides as the hand-built props have, and flat walls, floors and
# crates get none). Hard edges stay hard, flat faces stay flat, bevels become real fillets.
#
# How: "curved point-normal triangles" (each triangle becomes a cubic patch through its own corners), with
# three changes that matter for models like these (each one fixed something that looked wrong):
#   - the bend comes from normals worked out here, from the faces next door weighted by the square of their
#     size, not the model's own shading normals: a broad flat face with a thin bevel round it stays dead flat
#     instead of puffing up like a pillow;
#   - an edge only bends where its outline carries on round (_carries_on): a square's corner is a corner;
#   - every edge is bent once and shared by the faces either side of it, so nothing cracks open where a
#     round side meets a flat lid.
# Each mesh is done once and kept (per mesh, so every copy of a model shares it): about 10 ms a model the
# first time it's used, 4 seconds for all of them. Collision still comes from the original shape
# (models.gd faces()), so nothing about how the game plays changes. Low graphics keeps the originals. No
# randomness anywhere: every screen gets the same shape. tests/test_models.gd checks every rounded mesh for
# opened seams, growth and changed area.
#
# The standard this sets (Nov 27, "keep that as the standard"): round things are round to within TOLERANCE
# at their real size, which works out at about 14 sides for something 20 cm across, 24 for a barrel, 40 for a
# bouncy pad; nothing uses more than that needs (no primitive left at Godot's default 64 sides unless it's
# over a metre across); a prop stays under 14,000 triangles and a structure under 40,000 (test_models).
extends RefCounted

const TOLERANCE := 0.0025      # metres a facet may stand off the curve before it's split again
const MAX_SPLIT := 3           # ...up to this many pieces along an edge (an octagon: 24 sides)
# Structures only bend where there's a real curve: an edge that would bow less than this stays straight. Walls,
# floors and stairs are laid by the thousand, and nearly every edge of them has a little bevel: rounding those
# shows nothing and nearly doubled the triangles of a whole town map (4,755 floor tiles, 66 triangles each,
# became 250 each). Arches, columns, sinks, barrels on a table and hills still round. Props round everything.
const STRUCTURE_MIN_BOW := 0.008
const CREASE_COS := 0.42       # faces more than about 65 degrees apart never smooth into each other
const SAME_NORMAL := 0.985     # the model's own normals this alike: the same smooth surface
const CARRY_COS := 0.47        # an outline that turns more than about 62 degrees at a point has a corner there...
const CARRY_LENGTH := 0.3      # ...and so has one whose next edge is less than this much of the edge's own length
const FLAT_COS := 0.990        # a face within about 8 degrees of flat at a corner is flat there (already fine enough)
const MAX_TRIANGLES := 9000    # a mesh that would come out bigger than this is split less (then left alone)

static var _done := {}         # "mesh instance id|min_bow" -> its rounder copy (or itself, if there was nothing to round)
static var stats := {"meshes": 0, "before": 0, "after": 0, "msec": 0}


# Every mesh of a model, swapped for its rounder copy. `holder` is the model's root (models.gd _raw()).
# `piece_scale` is how much this one copy was stretched in Creative: the rounding is worked out for the model at
# its ordinary size, once, whichever copy asks first. `min_bow`: how far an edge has to bow before it's worth
# bending at all (STRUCTURE_MIN_BOW for structures).
static func apply(holder: Node3D, piece_scale := Vector3.ONE, min_bow := TOLERANCE) -> void:
	var unstretch := Transform3D(Basis.from_scale(Vector3.ONE / piece_scale), Vector3.ZERO)
	for c in holder.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		var src := mi.mesh as ArrayMesh
		if src == null or mi.skin != null:
			continue
		var key := "%d|%s" % [src.get_instance_id(), min_bow]
		if not _done.has(key):
			_done[key] = _round_mesh(src, unstretch * _to_holder(mi, holder), min_bow)
		mi.mesh = _done[key]


static func _to_holder(n: Node, holder: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while n != null and n != holder:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _round_mesh(src: ArrayMesh, xf: Transform3D, min_bow: float) -> ArrayMesh:
	var t0 := Time.get_ticks_msec()
	var scale := maxf(xf.basis.get_scale().x, maxf(xf.basis.get_scale().y, xf.basis.get_scale().z))
	var up := (xf.basis.inverse() * Vector3.UP).normalized()   # (the world's up, in the mesh's own space)
	var before := 0
	for si in src.get_surface_count():
		before += _triangle_count(src, si)
	var out: ArrayMesh = null
	for split in range(MAX_SPLIT, 0, -1):
		if split == 1:
			out = src
			break
		out = ArrayMesh.new()
		var after := 0
		var changed := false
		for si in src.get_surface_count():
			var arr := _round_surface(src, si, scale, up, split, min_bow)
			if arr.is_empty():
				arr = src.surface_get_arrays(si)   # (nothing to round, or not a kind of surface we touch)
				arr[Mesh.ARRAY_TANGENT] = null
			else:
				changed = true
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(si, src.surface_get_material(si))
			out.surface_set_name(si, src.surface_get_name(si))
			after += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if arr[Mesh.ARRAY_INDEX] != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		if not changed:
			out = src
			break
		if after <= MAX_TRIANGLES:
			break
	var now := 0
	for si in out.get_surface_count():
		now += _triangle_count(out, si)
	stats["meshes"] += 1
	stats["before"] += before
	stats["after"] += now
	stats["msec"] += Time.get_ticks_msec() - t0
	return out


# Does the outline carry on round past the end `at` of the edge that comes from `from`? A curve drawn with
# straight pieces carries on: after each piece comes another about as long, turned a little (an octagon's
# sides turn 45 degrees each). A corner doesn't: the next edge turns sharply (a square's 90 degrees), or it's
# only a stub (the little mitre where two bevels meet). Without this a bevelled box's top, four bevels in a
# ring, reads as a very rough cone, and its long edges bowed out between the corners.
static func _carries_on(at: int, from: int, gpos: PackedVector3Array, linked: Dictionary, known: Dictionary) -> bool:
	var key := at * gpos.size() + from
	var had = known.get(key)
	if had != null:
		return had
	var d := gpos[at] - gpos[from]
	var length := d.length()
	var found := false
	if length > 1e-9:
		d /= length
		for o: int in linked[at]:
			if o == from or o == at:
				continue
			var e := gpos[o] - gpos[at]
			var el := e.length()
			if el >= length * CARRY_LENGTH and e.dot(d) >= el * CARRY_COS:
				found = true
				break
	known[key] = found
	return found


static func _triangle_count(mesh: ArrayMesh, si: int) -> int:
	var n := mesh.surface_get_array_index_len(si)
	return (n if n > 0 else mesh.surface_get_array_len(si)) / 3


# One surface's new arrays, or [] if nothing on it needs rounding.
static func _round_surface(src: ArrayMesh, si: int, scale: float, up: Vector3, max_split: int, min_bow: float) -> Array:
	if src.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
		return []
	var arr := src.surface_get_arrays(si)
	if arr[Mesh.ARRAY_NORMAL] == null or arr[Mesh.ARRAY_BONES] != null:
		return []
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var has_uv: bool = arr[Mesh.ARRAY_TEX_UV] != null
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if has_uv else PackedVector2Array()
	var has_col: bool = arr[Mesh.ARRAY_COLOR] != null
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR] if has_col else PackedColorArray()
	var idx: PackedInt32Array
	if arr[Mesh.ARRAY_INDEX] != null:
		idx = arr[Mesh.ARRAY_INDEX]
	else:
		idx.resize(verts.size())
		for i in verts.size():
			idx[i] = i
	var tri_count := idx.size() / 3
	if tri_count == 0:
		return []

	# --- corners that sit on the same spot are one point
	var weld := {}
	var gid := PackedInt32Array()
	gid.resize(verts.size())
	var low := INF
	for i in verts.size():
		var key := Vector3i((verts[i] * 20000.0).round())
		var g = weld.get(key)
		if g == null:
			g = weld.size()
			weld[key] = g
		gid[i] = g
		low = minf(low, verts[i].dot(up))
	var points := weld.size()
	var gpos := PackedVector3Array()   # where each point is
	gpos.resize(points)
	for i in verts.size():
		gpos[gid[i]] = verts[i]
	var linked := {}                   # point -> the points it shares an edge with

	# --- each face: which way it faces, how big it is, and the angle it has at each of its corners
	var fn := PackedVector3Array()
	fn.resize(tri_count)
	var fa := PackedFloat32Array()
	fa.resize(tri_count)
	var fw := PackedFloat32Array()
	fw.resize(tri_count * 3)
	var around := {}   # point -> the corners (triangle * 3 + corner) that meet there
	for t in tri_count:
		var a := verts[idx[t * 3]]
		var b := verts[idx[t * 3 + 1]]
		var c := verts[idx[t * 3 + 2]]
		var n := (b - a).cross(c - a)
		var area := n.length()
		if area < 1e-12:
			fn[t] = Vector3.ZERO
			continue
		n /= area
		if n.dot(norms[idx[t * 3]] + norms[idx[t * 3 + 1]] + norms[idx[t * 3 + 2]]) < 0.0:
			n = -n   # (out of the surface, whichever way the triangle winds)
		fn[t] = n
		fa[t] = area
		var p := [a, b, c]
		for k in 3:
			var e1: Vector3 = (p[(k + 1) % 3] - p[k]).normalized()
			var e2: Vector3 = (p[(k + 2) % 3] - p[k]).normalized()
			fw[t * 3 + k] = acos(clampf(e1.dot(e2), -1.0, 1.0))
			var g := gid[idx[t * 3 + k]]
			if not around.has(g):
				around[g] = []
				linked[g] = []
			(around[g] as Array).append(t * 3 + k)
			(linked[g] as Array).append(gid[idx[t * 3 + (k + 1) % 3]])   # (listed once per face: twice over is fine)
			(linked[g] as Array).append(gid[idx[t * 3 + (k + 2) % 3]])

	# --- the normal that shapes each corner: this face and the faces right next to it round that point (across an
	# edge, on the same smooth surface by the model's own normals, and not turned too sharply away). Big faces
	# count far more than small ones (by the square of their size), and a face that comes out within a few degrees
	# of flat is simply flat. So the broad faces of a crate, a stove top or a tablecloth stay dead flat and a
	# bevel strip stays straight along its length, with the bend only where the model really turns, while a
	# barrel's equal staves share alike and make a circle. (Counting every face round the point, or weighting by
	# plain size, bowed the long edges of bevelled boxes out like pillows.)
	var shape_n := PackedVector3Array()
	shape_n.resize(tri_count * 3)
	for g in around:
		var list: Array = around[g]
		var k := list.size()
		var oa := PackedInt32Array()   # each corner's two other points
		var ob := PackedInt32Array()
		oa.resize(k)
		ob.resize(k)
		for i in k:
			var ci: int = list[i]
			var t := ci / 3
			oa[i] = gid[idx[t * 3 + (ci + 1) % 3]]
			ob[i] = gid[idx[t * 3 + (ci + 2) % 3]]
		for i in k:
			var ci: int = list[i]
			var t := ci / 3
			if norms[idx[ci]].dot(fn[t]) > 0.9999:
				shape_n[ci] = fn[t]   # (shaded flat here: most corners of most models, and the quick way out)
				continue
			# steps[j]: 0 = this face or one lying flat with it, 1 = next to that; further round doesn't count
			var steps := {i: 0}
			var todo := [i]
			while not todo.is_empty():
				var at: int = todo.pop_back()
				var ta: int = list[at] / 3
				for j in k:
					if j == at or not (oa[at] == oa[j] or oa[at] == ob[j] or ob[at] == oa[j] or ob[at] == ob[j]):
						continue
					var tj: int = list[j] / 3
					var turn := fn[ta].dot(fn[tj])
					if turn < CREASE_COS or fn[t].dot(fn[tj]) < CREASE_COS or norms[idx[list[at]]].dot(norms[idx[list[j]]]) < SAME_NORMAL:
						continue
					var far: int = steps[at] + (0 if turn > 0.9995 else 1)
					if far <= 1 and (not steps.has(j) or steps[j] > far):
						steps[j] = far
						todo.append(j)
			var biggest := 0.0
			for j in steps:
				biggest = maxf(biggest, fa[list[j] / 3])
			var sum := Vector3.ZERO
			for j in steps:
				var tj: int = list[j] / 3
				var share := fa[tj] / biggest
				sum += fn[tj] * (fw[list[j]] * share * share)
			var shaped := sum.normalized() if sum.length_squared() > 1e-20 else fn[t]
			shape_n[ci] = fn[t] if shaped.dot(fn[t]) > FLAT_COS else shaped

	# --- every edge, bent once: where its two inner control points go (from the faces that curve there)
	var carries := {}     # (what _carries_on worked out, kept)
	var edge_sum := {}    # lo * points + hi -> [sum of the control point near lo, ...near hi, how many curved faces, lo vertex, hi vertex]
	var any := false
	for t in tri_count:
		if fn[t] == Vector3.ZERO:
			continue
		for k in 3:
			var ia := idx[t * 3 + k]
			var ib := idx[t * 3 + (k + 1) % 3]
			var ga := gid[ia]
			var gb := gid[ib]
			if ga == gb:
				continue
			var pa := verts[ia]
			var pb := verts[ib]
			var d := pb - pa
			var na := shape_n[t * 3 + k]
			var nb := shape_n[t * 3 + (k + 1) % 3]
			# (an end where the outline turns a corner instead of carrying on round stays straight: see _carries_on)
			var wa := d.dot(na)
			var wb := d.dot(nb)
			var slight := 0.02 * d.length()   # (a facet angle under a degree or so isn't a curve)
			if absf(wa) >= slight and not _carries_on(ga, gb, gpos, linked, carries):
				wa = 0.0
			if absf(wb) >= slight and not _carries_on(gb, ga, gpos, linked, carries):
				wb = 0.0
			var ekey := mini(ga, gb) * points + maxi(ga, gb)
			var e = edge_sum.get(ekey)
			if e == null:
				e = [Vector3.ZERO, Vector3.ZERO, 0, (pa if ga < gb else pb), (pb if ga < gb else pa)]
				edge_sum[ekey] = e
			if maxf(absf(wa), absf(wb)) < slight:
				continue
			var ca := (pa * 2.0 + pb - na * wa) / 3.0
			var cb := (pb * 2.0 + pa + nb * wb) / 3.0
			if ga < gb:
				e[0] += ca
				e[1] += cb
			else:
				e[0] += cb
				e[1] += ca
			e[2] += 1

	# --- how many pieces each edge is split into, and the points along it (shared by both its faces)
	var edge_pts := {}    # key -> [pieces, PackedVector3Array of pieces + 1 points from lo to hi, control near lo, control near hi]
	for ekey in edge_sum:
		var e: Array = edge_sum[ekey]
		var p0: Vector3 = e[3]
		var p1: Vector3 = e[4]
		var c0 := (p0 * 2.0 + p1) / 3.0
		var c1 := (p1 * 2.0 + p0) / 3.0
		var pieces := 1
		if e[2] > 0:
			var b0: Vector3 = e[0] / float(e[2])
			var b1: Vector3 = e[1] / float(e[2])
			var off := maxf(b0.distance_to(c0), b1.distance_to(c1)) * 0.75 * scale   # about how far the middle bows out
			pieces = clampi(ceili(sqrt(off / TOLERANCE)), 1, max_split) if off >= min_bow else 1
			if pieces > 1:
				c0 = b0
				c1 = b1
				any = true
		var pts := PackedVector3Array()
		pts.resize(pieces + 1)
		pts[0] = p0
		pts[pieces] = p1
		for k in range(1, pieces):
			var s := float(k) / pieces
			var r := 1.0 - s
			pts[k] = p0 * (r * r * r) + c0 * (3.0 * r * r * s) + c1 * (3.0 * r * s * s) + p1 * (s * s * s)
		edge_pts[ekey] = [pieces, pts, c0, c1]
	if not any:
		return []

	# --- build: flat faces as they were, curved ones as a patch
	var o_v := PackedVector3Array()
	var o_n := PackedVector3Array()
	var o_uv := PackedVector2Array()
	var o_c := PackedColorArray()
	var o_i := PackedInt32Array()
	for t in tri_count:
		var i0 := idx[t * 3]
		var i1 := idx[t * 3 + 1]
		var i2 := idx[t * 3 + 2]
		var g0 := gid[i0]
		var g1 := gid[i1]
		var g2 := gid[i2]
		var whole := fn[t] == Vector3.ZERO or g0 == g1 or g1 == g2 or g2 == g0
		var e01: Array = [] if whole else edge_pts[mini(g0, g1) * points + maxi(g0, g1)]
		var e12: Array = [] if whole else edge_pts[mini(g1, g2) * points + maxi(g1, g2)]
		var e20: Array = [] if whole else edge_pts[mini(g2, g0) * points + maxi(g2, g0)]
		var n01: int = 1 if whole else e01[0]
		var n12: int = 1 if whole else e12[0]
		var n20: int = 1 if whole else e20[0]
		var split := maxi(n01, maxi(n12, n20))
		if split == 1:
			var base := o_v.size()
			for i in [i0, i1, i2]:
				o_v.append(verts[i])
				o_n.append(norms[i])
				if has_uv:
					o_uv.append(uvs[i])
				if has_col:
					o_c.append(cols[i])
			o_i.append(base)
			o_i.append(base + 1)
			o_i.append(base + 2)
			continue
		var p0 := verts[i0]
		var p1 := verts[i1]
		var p2 := verts[i2]
		# the patch's control points (b210 is the one on edge 0-1 nearest corner 0, and so on)
		var b210: Vector3 = e01[2] if g0 < g1 else e01[3]
		var b120: Vector3 = e01[3] if g0 < g1 else e01[2]
		var b021: Vector3 = e12[2] if g1 < g2 else e12[3]
		var b012: Vector3 = e12[3] if g1 < g2 else e12[2]
		var b102: Vector3 = e20[2] if g2 < g0 else e20[3]
		var b201: Vector3 = e20[3] if g2 < g0 else e20[2]
		var mid_e := (b210 + b120 + b021 + b012 + b102 + b201) / 6.0
		var b111 := mid_e + (mid_e - (p0 + p1 + p2) / 3.0) * 0.5
		var local := {}   # snapped spot on the patch -> its number in the new arrays
		var grid := PackedInt32Array()
		grid.resize((split + 1) * (split + 1))
		for i in split + 1:          # toward corner 1
			for j in split + 1 - i:  # toward corner 2
				var v := float(i) / split
				var w := float(j) / split
				var u := 1.0 - v - w
				var pos := Vector3.ZERO
				var on_edge := false
				if j == 0:           # along edge 0 -> 1
					var k := roundi(v * n01)
					v = float(k) / n01
					u = 1.0 - v
					pos = (e01[1] as PackedVector3Array)[k if g0 < g1 else n01 - k]
					on_edge = true
				elif i + j == split:  # along edge 1 -> 2
					var k := roundi(w * n12)
					w = float(k) / n12
					v = 1.0 - w
					u = 0.0
					pos = (e12[1] as PackedVector3Array)[k if g1 < g2 else n12 - k]
					on_edge = true
				elif i == 0:         # along edge 2 -> 0
					var k := roundi(u * n20)
					u = float(k) / n20
					w = 1.0 - u
					pos = (e20[1] as PackedVector3Array)[k if g2 < g0 else n20 - k]
					on_edge = true
				var spot := Vector2i(roundi(v * 5040.0), roundi(w * 5040.0))
				var at = local.get(spot)
				if at == null:
					if not on_edge:
						pos = p0 * (u * u * u) + p1 * (v * v * v) + p2 * (w * w * w) \
								+ b210 * (3.0 * u * u * v) + b120 * (3.0 * u * v * v) + b201 * (3.0 * u * u * w) \
								+ b021 * (3.0 * v * v * w) + b102 * (3.0 * u * w * w) + b012 * (3.0 * v * w * w) \
								+ b111 * (6.0 * u * v * w)
					var sink := pos.dot(up) - low
					if sink < 0.0:
						pos -= up * sink   # (never below where the model stood: it still sits on the floor)
					at = o_v.size()
					local[spot] = at
					o_v.append(pos)
					o_n.append((norms[i0] * u + norms[i1] * v + norms[i2] * w).normalized())
					if has_uv:
						o_uv.append(uvs[i0] * u + uvs[i1] * v + uvs[i2] * w)
					if has_col:
						o_c.append(cols[i0] * u + cols[i1] * v + cols[i2] * w)
				grid[i * (split + 1) + j] = at
		for i in split:
			for j in split - i:
				var a := grid[i * (split + 1) + j]
				var b := grid[(i + 1) * (split + 1) + j]
				var c := grid[i * (split + 1) + j + 1]
				if a != b and b != c and c != a:
					o_i.append(a)
					o_i.append(b)
					o_i.append(c)
				if j < split - i - 1:
					var d := grid[(i + 1) * (split + 1) + j + 1]
					if b != d and d != c and c != b:
						o_i.append(b)
						o_i.append(d)
						o_i.append(c)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = o_v
	out[Mesh.ARRAY_NORMAL] = o_n
	if has_uv:
		out[Mesh.ARRAY_TEX_UV] = o_uv
	if has_col:
		out[Mesh.ARRAY_COLOR] = o_c
	out[Mesh.ARRAY_INDEX] = o_i
	return out
