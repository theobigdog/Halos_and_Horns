# Small one-shot visual effects.
extends RefCounted

static var quality := 1    # graphics quality (graphics.gd): 0 low, 1 medium, 2 high


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
	# ...plus a burst of glowing motes flying out of it.
	burst(parent, pos, color, int(6 + 6 * size), 1.6 + size * 1.2, 0.5)


# How many particles to actually make at this graphics quality.
static func _count(n: int) -> int:
	return maxi(1, int(n * [0.4, 1.0, 1.6][quality]))


static func _particles(parent: Node, pos: Vector3, amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = _count(amount)
	p.lifetime = lifetime
	p.local_coords = false
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	# Gone once the last particle has faded.
	p.get_tree().create_timer(lifetime + 0.3).timeout.connect(p.queue_free)
	return p


static func _fading(color: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	return g


static func _shrinking() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	return c


static func _mote_mesh(radius: float, glow: bool, color := Color.WHITE) -> Mesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 6
	s.rings = 3
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if glow else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if glow:
		m.emission_enabled = true
		m.emission = Color(color.r, color.g, color.b)
		m.emission_energy_multiplier = 1.5
	s.material = m
	return s


# A flying demon's flames (Ted, Nov 18): hellfire licking down from under it and trailing behind as it goes.
# Continuous: switch it on and off with `emitting`. Add it as a child of the flier, at its feet.
static func fly_flames() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = _count(70)
	p.lifetime = 0.5
	p.local_coords = false          # flames left behind in the air as it moves: a trail
	p.emitting = false
	p.mesh = _mote_mesh(0.13, true, Color(1.0, 0.45, 0.1))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.direction = Vector3.DOWN
	p.spread = 25.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, 3.0, 0)   # flames rise as they burn out
	p.damping_min = 3.0
	p.damping_max = 5.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.9, 0.35, 1.0), Color(1.0, 0.4, 0.05, 0.9), Color(0.35, 0.02, 0.02, 0.0)])
	p.color_ramp = g
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	p.scale_amount_curve = _shrinking()
	return p


# Glowing motes bursting out from a point, drifting a little up as they fade.
static func burst(parent: Node, pos: Vector3, color: Color, amount: int, speed: float, lifetime: float) -> void:
	var p := _particles(parent, pos, amount, lifetime)
	p.mesh = _mote_mesh(0.035, true, color)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.color_ramp = _fading(Color(color.r, color.g, color.b, 1.0))
	p.scale_amount_curve = _shrinking()


# Chips and splinters knocked off a surface: little bits that fly out and fall.
static func debris(parent: Node, pos: Vector3, normal: Vector3, color: Color, amount := 8) -> void:
	var p := _particles(parent, pos + normal * 0.05, amount, 0.9)
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box.material = m
	p.mesh = box
	p.direction = normal
	p.spread = 55.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -12.0, 0)
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var c := Color(color.r, color.g, color.b, 1.0)
	p.color_ramp = _fading(c)


# A ring of dust kicked up around a point on the ground (landings, stomps, props falling over).
static func dust(parent: Node, pos: Vector3, radius: float, amount := 14) -> void:
	var p := _particles(parent, pos + Vector3.UP * 0.1, amount, 0.9)
	p.mesh = _mote_mesh(0.12, false)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.6
	p.emission_ring_height = 0.05
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.8
	p.gravity = Vector3(0, -0.5, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.75, 0.68, 0.6, 0.55))
	ramp.set_color(1, Color(0.75, 0.68, 0.6, 0.0))
	p.color_ramp = ramp
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.6))
	p.scale_amount_curve = grow


# A soft billowing smoke puff (demon things: possessing, teleporting, minions).
static func smoke(parent: Node, pos: Vector3, color: Color, size := 1.0) -> void:
	var p := _particles(parent, pos, int(10 * size), 1.1)
	p.mesh = _mote_mesh(0.18 * size, false)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3 * size
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.4 * size
	p.gravity = Vector3(0, 0.8, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.color_ramp = _fading(Color(color.r, color.g, color.b, 0.7))
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.6))
	grow.add_point(Vector2(1.0, 1.8))
	p.scale_amount_curve = grow


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
