# Measures every model under assets/kaykit and writes their bounding boxes to
# tools/model_sizes.json, for tools/build_catalog.py. Run it after adding models:
#   godot --headless -s res://tools/measure_models.gd
extends SceneTree

const ROOT := "res://assets/kaykit"


func _init() -> void:
	var out := {}
	for pack in DirAccess.get_directories_at(ROOT):
		for f in DirAccess.get_files_at(ROOT + "/" + pack):
			if not (f.ends_with(".gltf") or f.ends_with(".glb")):
				continue
			var path := "%s/%s/%s" % [ROOT, pack, f]
			var scene := load(path) as PackedScene
			if scene == null:
				push_error("can't load " + path)
				continue
			var node := scene.instantiate()
			var box := _aabb(node, Transform3D.IDENTITY)
			node.free()
			if box.size == Vector3.ZERO:
				continue
			out[path] = {"pos": [box.position.x, box.position.y, box.position.z], "size": [box.size.x, box.size.y, box.size.z]}
	var file := FileAccess.open("res://tools/model_sizes.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(out, " ", true))
	print("measured %d models" % out.size())
	quit()


func _aabb(node: Node, xf: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	if node is Node3D:
		xf = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		box = xf * (node as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in node.get_children():
		var b := _aabb(c, xf)
		if b.size == Vector3.ZERO:
			continue
		box = b if first else box.merge(b)
		first = false
	return box
