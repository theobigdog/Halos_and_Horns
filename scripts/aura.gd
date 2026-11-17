# A power-up aura: particles around a player while a timed power-up is on them,
# a different colour and style for each one, so EVERYONE (the other team too)
# can tell what someone's powered up with:
#   Cherub Sense    gold sparkles drifting up, and a soft gold glow
#   Quick Blessings white-gold sparks zipping out from the hands
#   Quick Skills    sky-blue sparks spiralling up
#   Endless Sprint  green streaks trailing off the feet
#   Hatred Surge    red embers and dark smoke rising
# A demon disguised as a prop (or invisible) shows NO aura: the host doesn't even
# send it, or it would give the disguise away.
extends Node3D

const KINDS := {
	# kind: [colour, particles, rise speed, spread, height, size]
	"sense": [Color(1.0, 0.85, 0.3), 28, 0.8, 0.6, 1.0, 0.07],
	"quick_throw": [Color(1.0, 0.95, 0.7), 36, 2.5, 0.35, 1.2, 0.05],
	"quick_skills": [Color(0.45, 0.8, 1.0), 32, 1.6, 0.55, 0.9, 0.06],
	"quick_run": [Color(0.4, 1.0, 0.45), 40, 0.3, 0.45, 0.15, 0.06],
	"fast_hatred": [Color(1.0, 0.18, 0.08), 34, 1.3, 0.55, 0.8, 0.07],
}

var kind := ""
var _sparks: CPUParticles3D
var _smoke: CPUParticles3D
var _glow: OmniLight3D


static func shown_kind(powerups: Dictionary) -> String:
	for k in ["fast_hatred", "quick_skills", "quick_throw", "quick_run", "sense"]:
		if powerups.get(k, 0.0) > 0.0:
			return k
	return ""


func set_kind(new_kind: String) -> void:
	if not KINDS.has(new_kind):
		new_kind = ""
	if new_kind == kind:
		return
	kind = new_kind
	for c in get_children():
		c.queue_free()
	_sparks = null
	_smoke = null
	_glow = null
	if kind == "":
		return
	var k: Array = KINDS[kind]
	var color: Color = k[0]
	_sparks = _particles(color, k[1], k[5])
	_sparks.position.y = k[4]
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = k[3]
	_sparks.direction = Vector3.UP
	_sparks.spread = 25.0
	_sparks.initial_velocity_min = k[2] * 0.6
	_sparks.initial_velocity_max = k[2]
	_sparks.gravity = Vector3.ZERO
	match kind:
		"quick_throw":   # sparks shoot out sideways from about hand height
			_sparks.direction = Vector3(1, 0.3, 0)
			_sparks.spread = 180.0
			_sparks.lifetime = 0.45
		"quick_skills":  # a spiral up
			_sparks.orbit_velocity_min = 0.6
			_sparks.orbit_velocity_max = 0.9
		"quick_run":     # streaks left behind at the feet
			_sparks.local_coords = false
			_sparks.lifetime = 0.6
			_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			_sparks.emission_ring_axis = Vector3.UP
			_sparks.emission_ring_radius = 0.4
			_sparks.emission_ring_inner_radius = 0.2
			_sparks.emission_ring_height = 0.05
		"fast_hatred":   # embers, plus dark smoke
			_sparks.gravity = Vector3(0, 0.6, 0)
			_smoke = _particles(Color(0.12, 0.05, 0.05, 0.55), 14, 0.22)
			_smoke.position.y = 0.6
			_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			_smoke.emission_sphere_radius = 0.45
			_smoke.direction = Vector3.UP
			_smoke.initial_velocity_min = 0.4
			_smoke.initial_velocity_max = 0.8
			_smoke.gravity = Vector3.ZERO
			_smoke.lifetime = 1.6
			add_child(_smoke)
	add_child(_sparks)
	_glow = OmniLight3D.new()
	_glow.light_color = color
	_glow.omni_range = 2.5
	_glow.light_energy = 0.7
	_glow.position.y = 1.0
	add_child(_glow)


func _particles(color: Color, amount: int, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.0
	p.local_coords = true
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 4
	mesh.rings = 2
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA   # (so particles can fade out)
	if color.a >= 1.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 2.0
	m.vertex_color_use_as_albedo = true
	mesh.material = m
	p.mesh = mesh
	# Fade out over each particle's life.
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	return p
