# Triangle audit: a spreadsheet row for every prop, structure, walk-in building and ground block: its size,
# triangles, objects (draw calls), lights, and how finely its round primitives are cut. Cheap (a few seconds,
# headless), so it's the first thing to run when something feels heavy or a new set of models goes in:
#   godot --headless -s res://tools/audit_models.gd -- --out=C:/some/folder/audit.csv   (--plain: no rounding)
# The numbers the game is held to are in tests/test_models.gd (PROP_TRIANGLES, STRUCTURE_TRIANGLES), and the
# reasoning in scripts/model_smooth.gd's header.
extends SceneTree

const Models = preload("res://scripts/models.gd")
const PropLib = preload("res://scripts/prop_library.gd")
const HollowBuildings = preload("res://scripts/hollow_buildings.gd")
const GroundBlock = preload("res://scripts/ground_block.gd")
const Refined = preload("res://scripts/refined_models.gd")
const ExtraProps = preload("res://scripts/extra_props.gd")


func _initialize() -> void:
	_go.call_deferred()


func _walk(n: Node, acc: Dictionary) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m: Mesh = (n as MeshInstance3D).mesh
		var t: int = m.get_faces().size() / 3
		acc["tris"] += t
		acc["objs"] += 1
		acc["surfs"] += m.get_surface_count()
		var segs := -1
		var rad := 0.0
		if m is SphereMesh:
			segs = (m as SphereMesh).radial_segments
			rad = (m as SphereMesh).radius
		elif m is CylinderMesh:
			segs = (m as CylinderMesh).radial_segments
			rad = maxf((m as CylinderMesh).top_radius, (m as CylinderMesh).bottom_radius)
		elif m is CapsuleMesh:
			segs = (m as CapsuleMesh).radial_segments
			rad = (m as CapsuleMesh).radius
		elif m is TorusMesh:
			segs = (m as TorusMesh).rings
			rad = (m as TorusMesh).outer_radius
		if segs > 0:
			var sc := (n as Node3D).global_transform.basis.get_scale() if n.is_inside_tree() else Vector3.ONE
			rad *= maxf(sc.x, sc.z)
			var chord := TAU * rad / segs   # the length of one facet around it, metres
			acc["prims"] += 1
			acc["chord_max"] = maxf(acc["chord_max"], chord)
			acc["chord_min"] = minf(acc["chord_min"], chord)
			acc["seg_max"] = maxi(acc["seg_max"], segs)
			acc["seg_min"] = mini(acc["seg_min"], segs)
			if segs >= 48:
				acc["heavy_prims"] += 1
				acc["heavy_tris"] += t
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		if mm.mesh != null:
			acc["tris"] += mm.mesh.get_faces().size() / 3 * mm.instance_count
			acc["objs"] += 1
			acc["surfs"] += mm.mesh.get_surface_count()
	if n is Light3D:
		acc["lights"] += 1
	for c in n.get_children():
		_walk(c, acc)


func _measure(n: Node3D) -> Dictionary:
	root.add_child(n)
	var acc := {"tris": 0, "objs": 0, "surfs": 0, "prims": 0, "chord_max": 0.0, "chord_min": 99.0,
			"seg_max": 0, "seg_min": 9999, "heavy_prims": 0, "heavy_tris": 0, "lights": 0}
	_walk(n, acc)
	n.free()
	return acc


func _family(id: String) -> String:
	if "/" in id:
		return ("refined:" if Refined.has(id) else "kaykit:") + id.get_slice("/", 0)
	if ExtraProps.has(id):
		return "extra"
	return "classic"


func _go() -> void:
	var out := "res://tools/previews/_audit.csv"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a == "--plain":
			Models.smooth_on = false
	var lines := ["kind,family,id,sx,sy,sz,tris,objs,surfs,lights,prims,seg_min,seg_max,chord_min_mm,chord_max_mm,heavy_prims,heavy_tris,tris_per_m2"]
	var rows := []
	for t in PropLib.type_names():
		if "#" in t:
			continue
		var d: Dictionary = PropLib.TYPES[t]
		var s: Vector3 = d["size"] if d["shape"] == "box" else Vector3(d["radius"] * 2.0, d["height"], d["radius"] * 2.0)
		rows.append(["prop", _family(t), t, s, _measure(PropLib.make_visual(t))])
	for id in Models.ids("structure"):
		rows.append(["structure", _family(id), id, Models.size(id), _measure(Models.instance(id))])
	for kind in HollowBuildings.KINDS:
		rows.append(["building", "built", kind, HollowBuildings.size(kind), _measure(HollowBuildings.make(kind, 0))])
	for kind in GroundBlock.KINDS:
		var gs: Vector3 = GroundBlock.DEFAULT_SIZES.get(kind, Vector3(4, 0.3, 4))
		rows.append(["ground", "built", kind, gs, _measure(GroundBlock.make(kind, gs))])
	for r in rows:
		var s: Vector3 = r[3]
		var a: Dictionary = r[4]
		var area := maxf(2.0 * (s.x * s.y + s.y * s.z + s.x * s.z), 0.0001)
		lines.append("%s,%s,%s,%.2f,%.2f,%.2f,%d,%d,%d,%d,%d,%d,%d,%.0f,%.0f,%d,%d,%.0f" % [r[0], r[1], r[2], s.x, s.y, s.z,
				a["tris"], a["objs"], a["surfs"], a["lights"], a["prims"], a["seg_min"] if a["prims"] > 0 else 0, a["seg_max"],
				(a["chord_min"] if a["prims"] > 0 else 0.0) * 1000.0, a["chord_max"] * 1000.0, a["heavy_prims"], a["heavy_tris"],
				a["tris"] / area])
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("audit: %d rows -> %s" % [rows.size(), out])
	print("smoothing: ", load("res://scripts/model_smooth.gd").stats)
	quit()
