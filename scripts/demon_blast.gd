# A redeemed demon goes out with a bang (Ted's friend, Nov 20: "more explosive"): a flash that lights up
# the area, a fireball swelling and fading, a shockwave ring across the ground, fiery chunks and golden
# sparks flying out and bouncing, then a roll of smoke. Animated by hand with its own random numbers
# (particle systems use the game's shared ones, which would shift seeded test maps). Frees itself.
extends Node3D

const LIFE := 2.2
const CHUNKS := 22
const SPARKS := 26
const GRAVITY := 14.0

var small := false               # a hit, not a death: a quick burst of sparks and fire, no flash
var _t := 0.0
var _flash: OmniLight3D
var _ball: Node3D
var _core_mat: StandardMaterial3D
var _ball_mat: StandardMaterial3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _bits := []                  # [mesh, velocity, spin, material, lifetime]
var _smoke := []                 # [mesh, material, start, drift]


static func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b)
	m.emission_energy_multiplier = e
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m   # (lit, with strong emission: bright enough to bloom)


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(global_position.x * 73.0 + global_position.z * 31.0) & 0x7fffffff
	if small:
		scale = Vector3.ONE * 0.45
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.65, 0.3)
	_flash.light_energy = 2.5 if small else 9.0
	_flash.omni_range = 12.0
	_flash.position.y = 1.0
	add_child(_flash)
	# The fireball: a white-hot core inside a lumpy cluster of glowing puffs
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	_ball_mat = _glow(Color(1.0, 0.5, 0.12, 0.92), 6.0)
	var core_mat := _glow(Color(1.0, 0.95, 0.7, 1.0), 9.0)
	var holder := Node3D.new()
	holder.position.y = 0.8
	holder.scale = Vector3.ONE * 0.2
	add_child(holder)
	for i in 6:
		var lump := MeshInstance3D.new()
		lump.mesh = sm
		lump.material_override = _ball_mat
		var a := TAU * i / 6.0 + rng.randf() * 0.5
		lump.position = Vector3(cos(a) * 0.45, rng.randf_range(-0.2, 0.45), sin(a) * 0.45)
		lump.scale = Vector3.ONE * rng.randf_range(0.55, 0.8)
		holder.add_child(lump)
	var core := MeshInstance3D.new()
	core.mesh = sm
	core.material_override = core_mat
	core.scale = Vector3.ONE * 0.55
	holder.add_child(core)
	_core_mat = core_mat
	_ball = holder
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	_ring.mesh = tm
	_ring_mat = _glow(Color(1.0, 0.85, 0.5, 0.9), 3.0)
	_ring.material_override = _ring_mat
	_ring.position.y = 0.15
	_ring.scale = Vector3(0.3, 0.15, 0.3)
	add_child(_ring)
	# Fiery chunks (heavy, tumbling) and golden sparks (light, fast): the demon, redeemed
	var chunk_mesh := BoxMesh.new()
	chunk_mesh.size = Vector3(0.16, 0.16, 0.16)
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.05
	spark_mesh.height = 0.1
	spark_mesh.radial_segments = 6
	spark_mesh.rings = 3
	var chunks := 6 if small else CHUNKS
	var sparks := 14 if small else SPARKS
	for i in chunks + sparks:
		var chunk := i < chunks
		var mi := MeshInstance3D.new()
		mi.mesh = chunk_mesh if chunk else spark_mesh
		var c := Color(1.0, rng.randf_range(0.25, 0.5), 0.08) if chunk else Color(1.0, 0.85, 0.35)
		var m := _glow(Color(c.r, c.g, c.b, 1.0), 3.0 if chunk else 5.0)
		mi.material_override = m
		mi.position = Vector3(0, 0.9, 0)
		add_child(mi)
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.3, 1.2), rng.randf_range(-1, 1)).normalized()
		var speed := rng.randf_range(5.0, 10.0) if chunk else rng.randf_range(8.0, 15.0)
		var spin := Vector3(rng.randf_range(-12, 12), rng.randf_range(-12, 12), rng.randf_range(-12, 12))
		_bits.append([mi, dir * speed, spin, m, rng.randf_range(1.0, 1.8) if chunk else rng.randf_range(0.5, 1.0)])
	# Smoke puffs that roll out and up as the fire dies
	var puff := SphereMesh.new()
	puff.radius = 0.8
	puff.height = 1.6
	for i in (3 if small else 8):
		var mi := MeshInstance3D.new()
		mi.mesh = puff
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.12, 0.08, 0.08, 0.0)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = m
		var a := TAU * i / 8.0
		mi.position = Vector3(cos(a) * 0.4, 0.8, sin(a) * 0.4)
		mi.scale = Vector3.ONE * 0.3
		add_child(mi)
		_smoke.append([mi, m, rng.randf_range(0.15, 0.35), Vector3(cos(a), rng.randf_range(0.6, 1.2), sin(a))])


func _process(delta: float) -> void:
	_t += delta
	if _t >= (1.2 if small else LIFE):
		queue_free()
		return
	# Flash: bright, gone in half a second
	_flash.light_energy = (2.5 if small else 9.0) * maxf(0.0, 1.0 - _t / 0.5)
	# Fireball: swells fast, then fades out
	var k := clampf(_t / 0.35, 0.0, 1.0)
	_ball.scale = Vector3.ONE * lerpf(0.2, 2.4, 1.0 - pow(1.0 - k, 3.0))
	_ball_mat.albedo_color.a = 0.92 * maxf(0.0, 1.0 - _t / 0.6)
	_ball_mat.albedo_color.g = lerpf(0.5, 0.15, minf(_t / 0.6, 1.0))
	_ball_mat.emission = Color(1.0, _ball_mat.albedo_color.g, 0.08)
	_core_mat.albedo_color.a = maxf(0.0, 1.0 - _t / 0.3)
	_ball.visible = _t < 0.6
	# Shockwave ring across the ground
	var r := lerpf(0.3, 7.0, minf(_t / 0.55, 1.0))
	_ring.scale = Vector3(r, 0.15, r)
	_ring_mat.albedo_color.a = 0.9 * maxf(0.0, 1.0 - _t / 0.55)
	_ring.visible = _t < 0.55
	# Chunks and sparks: fly, fall, bounce once off the ground, fade
	for b in _bits:
		var mi: MeshInstance3D = b[0]
		if not mi.visible:
			continue
		var v: Vector3 = b[1]
		v.y -= GRAVITY * delta
		mi.position += v * delta
		if mi.position.y < 0.08 and v.y < 0.0:
			mi.position.y = 0.08
			v = Vector3(v.x * 0.5, -v.y * 0.35, v.z * 0.5)
		b[1] = v
		mi.rotation += b[2] * delta
		var fade: float = clampf(1.0 - _t / b[4], 0.0, 1.0)
		(b[3] as StandardMaterial3D).albedo_color.a = fade
		mi.visible = fade > 0.0
	# Smoke: grows and drifts up after the flash, then thins away
	for s in _smoke:
		var st: float = s[2]
		var u := clampf((_t - st) / (LIFE - st), 0.0, 1.0)
		var mi: MeshInstance3D = s[0]
		mi.scale = Vector3.ONE * lerpf(0.4, 2.8, u)
		mi.position = Vector3(0, 0.8, 0) + (s[3] as Vector3) * u * 2.2
		(s[1] as StandardMaterial3D).albedo_color.a = 0.75 * sin(u * PI) if _t > st else 0.0
