# An angel's thrown blessing. Arcs slightly with gravity.
# Uses a ray each physics frame so fast shots can't pass through thin props.
# Online, only the host's copy can hurt anyone (the server decides every hit);
# everyone else's copy is visual_only, so a hacked client can't fake hits.
extends Node3D

const Effects = preload("res://scripts/effects.gd")

const DAMAGE := 25
const LIFETIME := 3.0
const BOOK_RADIUS := 0.25
const PAD_BOUNCE_SPEED := 15.0   # same as a bouncy flings a player (bouncy.gd)
const MAX_PAD_BOUNCES := 3       # then it goes off wherever it lands
const PAD_KEEP_SIDEWAYS := 0.35  # how much of its sideways speed it keeps (first guess)
var color := Color(1.0, 0.9, 0.4)   # set by the thrower from its blessing type
var velocity := Vector3.ZERO
var shooter: CollisionObject3D
var visual_only := false
var damage := DAMAGE
var gravity := 4.0
var size := 0.12
var book := false                # Holy Scripture: a spinning book instead of a glowing ball
var on_impact: Callable          # called with the hit position (vacuum orb); host/practice only
var on_claim: Callable           # joined player's own throw hit a demon ON THEIR SCREEN: (entity id, hit point)
var gate: Callable               # host: may this throw still hurt someone? (each throw hurts once)
var homing: Callable            # Holy Scripture, host/practice only: (where, velocity) -> a Vector3 to seek, or null
var on_steer: Callable          # ...and told where it went after each turn, to show everyone the same curve
var _steer_send := 0.0
var bounces_on_pads := false     # Vacuum Orb: a bouncy pad flings it back up instead of setting it off
var _pad_bounces := 0
# Host / practice: main's hook for a blessing hitting a loose prop (it gets shoved).
static var prop_hit: Callable
var _life := LIFETIME


func _ready() -> void:
	if book:
		_make_book()
		return
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = size
	s.height = size * 2.0
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.0
	mi.material_override = m
	add_child(mi)
	_add_trail()


# A trail of glowing motes behind it (and on High graphics, a little light).
func _add_trail() -> void:
	var trail := CPUParticles3D.new()
	trail.amount = [6, 14, 22][Effects.quality]
	trail.lifetime = 0.35
	trail.local_coords = false
	var mote := SphereMesh.new()
	mote.radius = size * 0.45
	mote.height = size * 0.9
	mote.radial_segments = 6
	mote.rings = 3
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.vertex_color_use_as_albedo = true
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote.material = mm
	trail.mesh = mote
	trail.spread = 180.0
	trail.initial_velocity_max = 0.4
	trail.gravity = Vector3.ZERO
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.r, color.g, color.b, 0.8))
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	trail.color_ramp = ramp
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.1))
	trail.scale_amount_curve = shrink
	add_child(trail)
	if Effects.quality >= 2:
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 0.8
		light.omni_range = 2.5
		add_child(light)


func _make_book() -> void:
	var cover := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.32, 0.09, 0.42)
	cover.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.12, 0.1)
	cover.material_override = m
	add_child(cover)
	var pages := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.3, 0.07, 0.4)
	pages.mesh = pb
	pages.position.x = 0.015
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(1.0, 0.95, 0.75)
	pm.emission_enabled = true
	pm.emission = Color(1.0, 0.85, 0.4)       # holy glow from the pages
	pm.emission_energy_multiplier = 1.5
	pages.material_override = pm
	add_child(pages)


func _physics_process(delta: float) -> void:
	if book:
		rotate_object_local(Vector3.RIGHT, delta * 12.0)
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if _seek(delta):
		velocity.y -= gravity * 0.15 * delta   # locked on: it flies at them instead of dropping
	else:
		velocity.y -= gravity * delta
	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)   # ignore the invisible map bounds
	if shooter:
		query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() and book:
		hit = _book_sweep(from, to)   # a big book: it hits anything it brushes, not just dead center
	if hit.is_empty():
		global_position = to
		return
	var collider: Object = hit["collider"]
	if bounces_on_pads and _pad_bounces < MAX_PAD_BOUNCES and collider is Node and collider.is_in_group("bouncy_pad"):
		_bounce_off_pad(hit, collider)
		return
	var hit_demon := false
	# take_hit returns true only if the hit counted (a demon, not a fellow angel).
	if not visual_only and on_impact.is_valid():
		on_impact.call(hit["position"])
	if not visual_only and collider and collider.has_method("kick"):
		collider.kick(velocity)   # the angels' alarm cherub goes skidding
	if visual_only and on_claim.is_valid() and collider and collider.get("eid") != null and collider.get("role") == "demon":
		on_claim.call(collider.eid, hit["position"])   # the host checks it against what really happened
	var allowed: bool = not gate.is_valid() or gate.call()
	if not visual_only and allowed and damage > 0 and collider and collider.has_method("take_hit") and collider.take_hit(damage, shooter):
		hit_demon = true
		if is_instance_valid(shooter) and shooter.has_method("confirm_hit"):
			shooter.confirm_hit()
	if not visual_only and prop_hit.is_valid() and collider is StaticBody3D and collider.is_in_group("prop"):
		prop_hit.call(collider, velocity * (2.0 if book else 1.0), hit["position"])
	# A demon hit gets a red puff; anything else gets a harmless golden one, and
	# chips off whatever it hit.
	var puff_color := Color(0.9, 0.15, 0.1, 0.8) if hit_demon else Color(1.0, 0.95, 0.6, 0.7)
	Effects.puff(get_parent(), hit["position"], puff_color, 1.0 if hit_demon else 0.6)
	if not hit_demon:
		Effects.debris(get_parent(), hit["position"], hit.get("normal", Vector3.UP), Color(0.75, 0.68, 0.55), 6)
	queue_free()


# Heat-seeking (Holy Scripture): curve toward whatever `homing` picks, a little at a time.
const SEEK_TURN := 4.0            # radians a second it can turn (first guess)
const SEEK_AFTER := 0.12          # flies straight out of the hand for this long first


func _seek(delta: float) -> bool:
	if visual_only or not homing.is_valid() or LIFETIME - _life < SEEK_AFTER:
		return false
	var target = homing.call(global_position, velocity)
	if target == null:
		return false
	var cur := velocity.normalized()
	var want: Vector3 = ((target as Vector3) - global_position).normalized()
	var angle := cur.angle_to(want)
	if angle > 0.001:
		velocity = cur.slerp(want, minf(1.0, SEEK_TURN * delta / angle)) * velocity.length()
	_steer_send -= delta
	if _steer_send <= 0.0 and on_steer.is_valid():
		_steer_send = 0.08
		on_steer.call(global_position, velocity)
	return true


# Off a bouncy pad: up as high as the pad flings players, keeping some of its
# sideways speed, and with a fresh lifetime so it comes back down before it fades.
# Every screen's copy hits the same pad the same way, so they all agree.
func _bounce_off_pad(hit: Dictionary, pad: Node) -> void:
	_pad_bounces += 1
	var n: Vector3 = hit.get("normal", Vector3.UP)
	var out := velocity.bounce(n)
	velocity = Vector3(out.x, 0.0, out.z) * PAD_KEEP_SIDEWAYS   # pads fling things UP, so most of the
	velocity.y = PAD_BOUNCE_SPEED                                # sideways speed goes (else it sails off the map)
	global_position = hit["position"] + n * 0.05
	_life = LIFETIME + 1.0
	if pad.get_parent() and pad.get_parent().has_method("squish"):
		pad.get_parent().squish()
	Effects.puff(get_parent(), hit["position"], Color(0.55, 0.85, 1.0, 0.7), 0.6)


# Sweep a book-sized sphere along this frame's path; returns the same keys as a ray hit.
func _book_sweep(from: Vector3, to: Vector3) -> Dictionary:
	var sphere := SphereShape3D.new()
	sphere.radius = BOOK_RADIUS
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), from)
	params.motion = to - from
	params.collision_mask = 1
	if shooter:
		params.exclude = [shooter.get_rid()]
	var space := get_world_3d().direct_space_state
	var frac := space.cast_motion(params)
	if frac.size() < 2 or frac[1] >= 1.0:
		return {}
	params.transform = Transform3D(Basis(), from + (to - from) * frac[1])
	params.motion = Vector3.ZERO
	var info := space.get_rest_info(params)
	if info.is_empty():
		return {}
	return {"collider": instance_from_id(info["collider_id"]), "position": info["point"]}
