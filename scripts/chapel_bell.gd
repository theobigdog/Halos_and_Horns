# The chapel's bell (Ted, Nov 26: "spruce up the bell, ALOT, make it golden and shiny and if possible, if you
# run into it, there are applied physics that can even make the bell ring"). A real bell shape turned on a
# lathe (crown, shoulder, waist, sound bow, lip, with raised bands), polished gold, hung from a wooden
# headstock, with a clapper inside. Anyone who can be seen bumping into it pushes it: it swings like a
# pendulum, slowly dying away, and rings whenever a swing turns round high enough (louder the higher).
# Each screen swings its own copy from what it sees (nothing sent): invisible players never touch it, so it
# can't give anyone away.
extends Node3D

const Sfx = preload("res://scripts/sfx.gd")

const PIVOT_TO_MOUTH := 0.78     # m: the bell's length below its pivot
const G_OVER_L := 21.0            # pendulum stiffness (g / length): a swing takes about 1.4 s
const DAMPING := 0.22             # how fast a swing dies away (1/s)
const PUSH := 5.5                 # rad/s^2 per m/s someone is moving into it
const RING_FROM := 0.28           # rad: a swing must reach this far to ring
const MAX_SWING := 1.35           # rad

var angle := 0.0
var spin := 0.0
var rings := 0                    # (tests)
var _pivot: Node3D
var _clapper: Node3D
var _clap := 0.0
var _clap_v := 0.0
var _area: Area3D
var _was_out := 0.0
var _armed := false

static var _bell_mesh: ArrayMesh
static var _gold: StandardMaterial3D
static var _sound: AudioStreamWAV


func _ready() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.2, 0.12)
	wood.roughness = 0.85
	# the headstock: a wooden beam across, its gudgeons resting in the cote's pillars
	var hs := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.7, 0.13, 0.17)
	hs.mesh = hm
	hs.material_override = wood
	hs.position.y = -0.03
	_pivot.add_child(hs)
	var bell := MeshInstance3D.new()
	bell.mesh = bell_mesh()
	bell.material_override = gold()
	bell.position.y = -0.1
	_pivot.add_child(bell)
	# the clapper: an iron rod and ball, hanging inside, swinging a little behind the bell
	_clapper = Node3D.new()
	_clapper.position.y = -0.2
	_pivot.add_child(_clapper)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.16, 0.15, 0.15)
	iron.metallic = 0.7
	iron.roughness = 0.45
	var rod := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.018
	rm.bottom_radius = 0.018
	rm.height = 0.46
	rm.radial_segments = 8
	rm.rings = 1
	rod.mesh = rm
	rod.material_override = iron
	rod.position.y = -0.23
	_clapper.add_child(rod)
	var ball := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.06
	bm.height = 0.12
	bm.radial_segments = 12
	bm.rings = 6
	ball.mesh = bm
	ball.material_override = iron
	ball.position.y = -0.48
	_clapper.add_child(ball)
	# who's touching it
	_area = Area3D.new()
	_area.monitorable = false
	_area.collision_mask = 0xFFFFFFFF
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.62
	cs.shape = sph
	cs.position.y = -0.48
	_area.add_child(cs)
	add_child(_area)


func _physics_process(delta: float) -> void:
	# pushed by whoever is moving into it (only what can be seen: never an invisible demon)
	for body in _area.get_overlapping_bodies():
		if not (body is CharacterBody3D or body is RigidBody3D) or not (body as Node3D).is_visible_in_tree():
			continue
		var v: Vector3 = body.velocity if body is CharacterBody3D else (body as RigidBody3D).linear_velocity
		var local := global_basis.inverse() * v
		push(clampf(local.z, -9.0, 9.0) * PUSH * delta)
	var acc := -G_OVER_L * sin(angle) - DAMPING * spin
	spin += acc * delta
	angle = clampf(angle + spin * delta, -MAX_SWING, MAX_SWING)
	if absf(angle) >= MAX_SWING:
		spin *= -0.3
	_pivot.rotation.x = angle
	# the clapper lags behind; it rings the bell where a swing turns round
	var cacc := -G_OVER_L * 1.6 * sin(_clap) - 2.0 * _clap_v - acc * 0.6
	_clap_v += cacc * delta
	_clap = clampf(_clap + _clap_v * delta, -0.35, 0.35)
	_clapper.rotation.x = _clap
	# one ring each time a swing turns round, if it got far enough out
	var out := absf(angle)
	if out > _was_out:
		_armed = _armed or out >= RING_FROM
	elif _armed:
		_armed = false
		_ring(_was_out)
	_was_out = out


# Give it a shove (rad/s of swing).
func push(dspin: float) -> void:
	spin = clampf(spin + dspin, -6.0, 6.0)


func _ring(swing: float) -> void:
	rings += 1
	_clap_v += -signf(angle) * 3.0
	if DisplayServer.get_name() == "headless":
		return
	var asp := AudioStreamPlayer3D.new()
	asp.stream = sound()
	asp.bus = Sfx.BUS
	asp.unit_size = 14.0
	asp.max_distance = 120.0
	asp.volume_db = lerpf(-14.0, -3.0, clampf((swing - RING_FROM) / 0.8, 0.0, 1.0))
	asp.pitch_scale = randf_range(0.99, 1.01)
	add_child(asp)
	asp.position.y = -0.5
	asp.finished.connect(asp.queue_free)
	asp.play()


# A church bell's partials: hum, prime, minor third (that's what makes it sound like a bell), fifth, nominal.
static func sound() -> AudioStreamWAV:
	if _sound == null:
		_sound = make_sound()
	return _sound


static func make_sound() -> AudioStreamWAV:
	var f := 294.0
	return Sfx.tone([[f * 0.5, 0.7], [f, 1.0], [f * 1.2, 0.55], [f * 1.5, 0.3], [f * 2.0, 0.45], [f * 2.5, 0.12], [f * 3.0, 0.08]],
			3.2, 0.45, 0.003, 3.0, 0.02, 0.995)


static func gold() -> StandardMaterial3D:
	if _gold == null:
		_gold = StandardMaterial3D.new()
		_gold.albedo_color = Color(1.0, 0.76, 0.3)
		_gold.metallic = 1.0
		_gold.roughness = 0.16
		_gold.metallic_specular = 0.7
		_gold.clearcoat_enabled = true
		_gold.clearcoat = 0.4
		_gold.clearcoat_roughness = 0.1
	return _gold


# The bell, turned on a lathe: [radius, height below the crown] down the outside, then back up the inside.
const PROFILE := [
	[0.0, 0.0], [0.05, 0.0], [0.1, 0.012], [0.135, 0.045],          # crown and shoulder
	[0.142, 0.07], [0.15, 0.075], [0.144, 0.085],                     # a band under the shoulder
	[0.145, 0.2], [0.155, 0.33], [0.175, 0.45],                       # the waist, flaring out
	[0.205, 0.54], [0.214, 0.55], [0.212, 0.565],                     # a band above the sound bow
	[0.245, 0.62], [0.28, 0.67], [0.3, 0.7], [0.304, 0.715],          # the sound bow out to the lip
	[0.29, 0.722], [0.262, 0.712],                                    # round the lip
	[0.225, 0.66], [0.18, 0.56], [0.15, 0.4], [0.13, 0.2], [0.1, 0.07], [0.0, 0.05],   # inside, back up
]


static func bell_mesh() -> ArrayMesh:
	if _bell_mesh != null:
		return _bell_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 36
	for i in PROFILE.size() - 1:
		var a: Array = PROFILE[i]
		var b: Array = PROFILE[i + 1]
		for k in seg:
			var t0 := TAU * k / seg
			var t1 := TAU * (k + 1) / seg
			var p00 := Vector3(cos(t0) * a[0], -a[1], sin(t0) * a[0])
			var p01 := Vector3(cos(t1) * a[0], -a[1], sin(t1) * a[0])
			var p10 := Vector3(cos(t0) * b[0], -b[1], sin(t0) * b[0])
			var p11 := Vector3(cos(t1) * b[0], -b[1], sin(t1) * b[0])
			st.add_vertex(p00)
			st.add_vertex(p11)
			st.add_vertex(p10)
			st.add_vertex(p00)
			st.add_vertex(p01)
			st.add_vertex(p11)
	# the canons on top: a loop it hangs by
	for k in 10:
		var a0 := PI * k / 10.0
		var a1 := PI * (k + 1) / 10.0
		var c0 := Vector3(cos(a0) * 0.06, sin(a0) * 0.07 + 0.0, 0.0)
		var c1 := Vector3(cos(a1) * 0.06, sin(a1) * 0.07 + 0.0, 0.0)
		var r := 0.018
		for j in 6:
			var b0 := TAU * j / 6.0
			var b1 := TAU * (j + 1) / 6.0
			var n0 := Vector3(cos(a0), sin(a0), 0.0)
			var n1 := Vector3(cos(a1), sin(a1), 0.0)
			var q00 := c0 + (n0 * cos(b0) + Vector3.BACK * sin(b0)) * r
			var q01 := c0 + (n0 * cos(b1) + Vector3.BACK * sin(b1)) * r
			var q10 := c1 + (n1 * cos(b0) + Vector3.BACK * sin(b0)) * r
			var q11 := c1 + (n1 * cos(b1) + Vector3.BACK * sin(b1)) * r
			st.add_vertex(q00)
			st.add_vertex(q10)
			st.add_vertex(q11)
			st.add_vertex(q00)
			st.add_vertex(q11)
			st.add_vertex(q01)
	st.generate_normals()
	_bell_mesh = st.commit()
	return _bell_mesh
