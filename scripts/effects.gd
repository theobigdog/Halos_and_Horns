# Small one-shot visual effects.
extends RefCounted


# A quick expanding, fading sphere - used for hits and possessions.
static func puff(parent: Node, pos: Vector3, color: Color, size: float = 1.0) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.2 * size
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 1.3 * size, 0.35)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(mi.queue_free)


# The faint trail between two props when a demon possesses from one to the next.
# Deliberately subtle: a few tiny, dim sparkles that fade quickly.
static func sparkle_trail(parent: Node, from: Vector3, to: Vector3) -> void:
	var count := 10
	for i in count:
		var mi := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.035
		s.height = 0.07
		mi.mesh = s
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.85, 0.55, 1.0, 0.45)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		parent.add_child(mi)
		var t := float(i) / (count - 1)
		mi.global_position = from.lerp(to, t) + Vector3(randf_range(-0.1, 0.1), 0.5 + randf_range(-0.1, 0.1), randf_range(-0.1, 0.1))
		var tw := mi.create_tween()
		tw.tween_interval(t * 0.25)                     # ripple from start to end
		tw.tween_property(m, "albedo_color:a", 0.0, 0.6)
		tw.tween_callback(mi.queue_free)


# Slowly fade a node out (an abandoned possessed prop), then remove it.
static func dissolve(node: Node3D, seconds: float) -> void:
	var mats := []
	_fade_prepare(node, mats)
	var tw := node.create_tween()
	tw.set_parallel(true)
	for m in mats:
		tw.tween_property(m, "albedo_color:a", 0.0, seconds)
	tw.chain().tween_callback(node.queue_free)


static func _fade_prepare(node: Node, mats: Array) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = child.material_override.duplicate()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			child.material_override = m
			mats.append(m)
		_fade_prepare(child, mats)


# An angel's melee swing: a quick pale arc in front of them.
static func swing(parent: Node, pos: Vector3, forward: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	mi.mesh = torus
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 1.0, 0.9, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = pos + forward * 1.0
	mi.look_at(mi.global_position + forward, Vector3.UP)
	mi.rotate_object_local(Vector3.RIGHT, PI / 2)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "rotation:y", mi.rotation.y + 1.2, 0.15)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.18)
	tw.chain().tween_callback(mi.queue_free)
