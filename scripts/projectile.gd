# An angel's thrown blessing. Arcs slightly with gravity.
# Uses a ray each physics frame so fast shots can't pass through thin props.
# Online, only the host's copy can hurt anyone (the server decides every hit);
# everyone else's copy is visual_only, so a hacked client can't fake hits.
# Its look (Nov 24): every kind is its own thing (see "Looks" below): a spiky star of
# Holy Light, a wobbling Blessed Water drop, a spinning Halo Ring, a fluttering Feather,
# a bobbing Choir Note, the Holy Scripture book and the swirling Vacuum Orb, each with a
# hand-animated ribbon trail, a few trailing motes and its own impact flourish. No particles.
extends Node3D

const Effects = preload("res://scripts/effects.gd")
const BlessingSounds = preload("res://scripts/blessing_sounds.gd")
const Sfx = preload("res://scripts/sfx.gd")

const DAMAGE := 25
const LIFETIME := 3.0
const BOOK_RADIUS := 0.25
const PAD_BOUNCE_SPEED := 15.0   # same as a bouncy flings a player (bouncy.gd)
const MAX_PAD_BOUNCES := 3       # then it goes off wherever it lands
const PAD_KEEP_SIDEWAYS := 0.35  # how much of its sideways speed it keeps (first guess)
var color := Color(1.0, 0.9, 0.4)   # set by the thrower from its blessing type
var kind := ""                      # its blessing type (blessings.gd), or "book" / "vacuum": its look and sounds
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
	_build_look()


func _physics_process(delta: float) -> void:
	if book:
		rotate_object_local(Vector3.RIGHT, delta * 12.0)
	_life -= delta
	if _life <= 0.0:
		_leave_trail()
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
	# Bouncy pads (Nov 24): a one-use pad is used up by anything thrown at it (the throw goes off as
	# usual); a lasting pad flings every thrown thing back up into the air.
	if collider is Node and collider.is_in_group("bouncy_pad"):
		var pad: Node = (collider as Node).get_parent()
		if pad != null and pad.get("one_use") == true:
			if not visual_only and pad.has_method("shot"):
				pad.shot()   # (the host's / practice game's copy decides; it tells everyone)
		elif _pad_bounces < MAX_PAD_BOUNCES:
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
		get_tree().call_group("main_game", "demon_hit_fx", hit["position"])
		get_tree().call_group("main_game", "shove_hit", collider, velocity * (2.0 if book else 1.0))
		if is_instance_valid(shooter) and shooter.has_method("confirm_hit"):
			shooter.confirm_hit()
	if not visual_only and prop_hit.is_valid() and collider is StaticBody3D and collider.is_in_group("prop"):
		prop_hit.call(collider, velocity * (2.0 if book else 1.0), hit["position"])
	# A demon hit gets a red puff; anything else gets this kind's own flourish and sound,
	# and chips off whatever it hit.
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	_impact_look(hit["position"], normal, hit_demon)
	if hit_demon:
		Effects.puff(get_parent(), hit["position"], Color(0.9, 0.15, 0.1, 0.8), 1.0)
	else:
		if not (collider and collider.get("role") == "demon"):
			_impact_sound(hit["position"])
		Effects.debris(get_parent(), hit["position"], normal, Color(0.75, 0.68, 0.55), 6)
	_leave_trail()
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
	if pad.get_parent() and pad.get_parent().get("super_bouncy") == true:
		velocity.y *= 1.45   # (the magic pad throws it higher)
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


# It hit something that isn't a demon: this kind's impact sound where it landed (blessing_sounds.gd).
func _impact_sound(pos: Vector3) -> void:
	var parent := get_parent()
	if parent == null or kind == "":
		return
	var stream := BlessingSounds.impact(kind)
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = Sfx.BUS
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.get_tree().create_timer(stream.get_length() + 0.5).timeout.connect(p.queue_free)   # (in case "finished" never comes)
	p.play()


# =====================================================================================
# Looks. Everything below is visual only: none of it touches velocity, hits or timing.
# Meshes, shaders and materials are made once and shared by every throw (_cache).
# =====================================================================================

# Per kind: ribbon width / length (m) / shader style, its second (tail) colour, how many
# trailing motes a second (at Medium; none on Low, more on High).
const LOOKS := {
	"holy_light": {"w": 0.16, "len": 3.6, "style": 1, "tail": Color(1.0, 0.55, 0.15), "motes": 40.0},
	"blessed_water": {"w": 0.2, "len": 2.6, "style": 2, "tail": Color(0.75, 0.95, 1.0), "motes": 30.0},
	"halo_ring": {"w": 0.1, "len": 3.0, "style": 0, "tail": Color(1.0, 0.5, 0.1), "motes": 18.0},
	"feather": {"w": 0.24, "len": 2.2, "style": 4, "tail": Color(0.7, 0.82, 1.0), "motes": 14.0},
	"choir": {"w": 0.34, "len": 3.0, "style": 3, "tail": Color(0.5, 0.45, 1.0), "motes": 10.0},
	"book": {"w": 0.36, "len": 2.2, "style": 0, "tail": Color(1.0, 0.65, 0.25), "motes": 12.0},
	"vacuum": {"w": 0.42, "len": 2.6, "style": 5, "tail": Color(0.35, 0.65, 1.0), "motes": 24.0},
	"": {"w": 0.14, "len": 2.5, "style": 0, "tail": Color(1.0, 1.0, 1.0), "motes": 0.0},
}
const TRAIL_SPACING := 0.12

static var _cache := {}

var _look: Dictionary
var _body: Node3D               # the spinning / fluttering part (a child, so the node itself never turns)
var _extras: Array[Node3D] = [] # orbiting rings / motes of the Vacuum Orb
var _ribbon: MeshInstance3D
var _rmesh: ImmediateMesh
var _hist: Array[Vector3] = []  # where it has been, newest first
var _t := 0.0
var _mote_acc := 0.0
var _last_head := Vector3.INF
var _rng := RandomNumberGenerator.new()


func _build_look() -> void:
	_look = LOOKS.get(kind if not book else "book", LOOKS[""])
	_rng.seed = 7919 + get_instance_id()   # its own generator: never touches the global one
	_t = _rng.randf() * 10.0
	_body = Node3D.new()
	add_child(_body)
	match "book" if book else kind:
		"book": _make_book()
		"holy_light": _make_holy_light()
		"blessed_water": _make_water()
		"halo_ring": _make_halo()
		"feather": _make_feather()
		"choir": _make_note()
		"vacuum": _make_vacuum()
		_: _make_plain()
	_add_trail()
	if Effects.quality >= 2:
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 0.8
		light.omni_range = 2.5
		add_child(light)


func _mesh_child(parent: Node3D, mesh: Mesh, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if mat:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _glow_sprite(parent: Node3D, c: Color, scale_m: float, alpha := 0.5, shape := 0) -> MeshInstance3D:
	var mi := _mesh_child(parent, _quad(), _sprite_mat(shape, Color(c.r, c.g, c.b, alpha), 1.4))
	mi.scale = Vector3.ONE * scale_m
	return mi


# --- Holy Light: a radiant spiky star, stretched along its flight, with a glow and a turning sparkle.
func _make_holy_light() -> void:
	_mesh_child(_body, _star_mesh(), _glow_mat("holy_core", Color(1.0, 0.97, 0.8), color, 4.0))
	_glow_sprite(self, color, 0.75, 0.55)
	_extras.append(_glow_sprite(self, Color(1.0, 1.0, 0.9), 0.9, 0.9, 1))


# --- Blessed Water: a wobbling droplet with its tail behind it (the wobble is in its shader).
func _make_water() -> void:
	var mi := _mesh_child(_body, _cached("water_mesh", func():
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 14
		s.rings = 8
		return s), _water_mat(color))
	mi.scale = Vector3.ONE * size * 1.25
	_glow_sprite(self, color, 0.6, 0.35)


# --- Halo Ring: a golden ring spinning flat like a frisbee.
func _make_halo() -> void:
	_mesh_child(_body, _halo_mesh(), _gold_mat(color))
	var inner := _glow_sprite(_body, Color(1.0, 0.95, 0.6), 0.48, 0.7, 3)
	inner.set_instance_shader_parameter("lie_flat", 1.0)
	_glow_sprite(self, color, 0.7, 0.35)


# --- Feather: a soft white feather that rocks, tumbles and flutters as it flies.
func _make_feather() -> void:
	var mi := _mesh_child(_body, _feather_mesh(), _feather_mat())
	mi.scale = Vector3.ONE * 1.45
	_glow_sprite(self, Color(0.85, 0.9, 1.0), 0.55, 0.3)


# --- Choir Note: a glowing eighth note that bobs and sways, always turned to face you.
func _make_note() -> void:
	var mi := _mesh_child(_body, _note_mesh(), _glow_mat("note", color.lightened(0.15), color, 2.2))
	mi.scale = Vector3.ONE * 1.1
	_glow_sprite(self, color, 0.75, 0.45)


# --- Holy Scripture: the red book with gold trim and glowing pages.
func _make_book() -> void:
	_mesh_child(_body, _book_mesh())
	_glow_sprite(self, Color(1.0, 0.85, 0.45), 1.0, 0.4)


# --- Vacuum Orb: a swirling banded orb with a bright core and two orbiting rings.
func _make_vacuum() -> void:
	var r := size
	var mi := _mesh_child(_body, _cached("orb_mesh", func():
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 20
		s.rings = 10
		return s), _orb_mat(color))
	mi.scale = Vector3.ONE * r
	var ring: Mesh = _cached("orb_ring", func():
		var t := TorusMesh.new()
		t.inner_radius = 1.0
		t.outer_radius = 1.12
		t.rings = 24
		t.ring_segments = 4
		return t)
	var rm := _glow_mat("orb_ring", Color(0.8, 0.6, 1.0), Color(0.7, 0.45, 1.0), 2.0)
	for i in 2:
		var holder := Node3D.new()
		add_child(holder)
		var rr := _mesh_child(holder, ring, rm)
		rr.scale = Vector3.ONE * r * (1.55 + 0.3 * i)
		_extras.append(holder)
	for i in 3:
		var m := _glow_sprite(self, Color(0.9, 0.8, 1.0), r * 0.9, 0.9, 1)
		_extras.append(m)
	_glow_sprite(self, color, r * 6.0, 0.45)


func _make_plain() -> void:
	var s := SphereMesh.new()
	s.radius = size
	s.height = size * 2.0
	s.radial_segments = 12
	s.rings = 6
	_mesh_child(_body, s, _glow_mat("plain_" + color.to_html(), color, color, 2.0))
	_glow_sprite(self, color, size * 5.0, 0.4)


# Each frame: spin / flutter / bob the body, draw the ribbon, drop trailing motes.
func _process(delta: float) -> void:
	_t += delta
	var dir := velocity.normalized() if velocity.length() > 0.01 else Vector3.FORWARD
	var aim := _aim_basis(dir)
	match "book" if book else kind:
		"holy_light":
			var pulse := 1.0 + 0.18 * sin(_t * 31.0)
			_body.basis = (aim * Basis(Vector3.FORWARD, _t * 14.0)) * Basis.from_scale(Vector3(pulse, pulse, pulse * 1.7))
			_extras[0].set_instance_shader_parameter("spin", _t * 5.0)
		"blessed_water":
			_body.basis = aim
		"halo_ring":
			var side := Vector3(dir.z, 0.0, -dir.x).normalized() if Vector2(dir.x, dir.z).length() > 0.05 else Vector3.RIGHT
			var tilt := Basis(side, 0.3 + 0.12 * sin(_t * 7.0)) * Basis(Vector3.FORWARD, 0.15 * sin(_t * 5.0))
			_body.basis = tilt * Basis(Vector3.UP, _t * 22.0)
		"feather":
			var rock := Basis(Vector3.FORWARD, sin(_t * 9.0) * 0.8) * Basis(Vector3.RIGHT, sin(_t * 5.3) * 0.45 + 0.25)
			_body.basis = aim * rock * Basis(Vector3.UP, sin(_t * 3.1) * 0.5)
			_body.position = aim * Vector3(sin(_t * 7.0) * 0.07, cos(_t * 11.0) * 0.04, 0.0)
		"choir":
			var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
			var face := Basis()
			if cam:
				var to_cam := cam.global_position - global_position
				to_cam.y = 0.0
				if to_cam.length() > 0.01:
					face = Basis.looking_at(-to_cam.normalized(), Vector3.UP)
			_body.basis = face * Basis(Vector3.FORWARD, sin(_t * 6.0) * 0.3)
			_body.position = Vector3(0.0, sin(_t * 11.0) * 0.07, 0.0)
		"vacuum":
			_body.basis = Basis(Vector3.UP, _t * 1.7) * Basis(Vector3.RIGHT, 0.4)
			_extras[0].basis = Basis(Vector3(1, 0.3, 0).normalized(), 1.1) * Basis(Vector3.UP, _t * 4.0)
			_extras[1].basis = Basis(Vector3(-0.4, 0.2, 1).normalized(), 1.3) * Basis(Vector3.UP, -_t * 3.1)
			for i in 3:
				var a := _t * (5.0 + i * 1.3) + i * TAU / 3.0
				var orbit := Basis(Vector3(cos(i * 2.0), 1.0, sin(i * 2.0)).normalized(), a) * Vector3(size * 2.1, 0, 0)
				_extras[2 + i].position = Vector3(orbit.x, orbit.y * 0.4 + orbit.z * 0.3, orbit.z)
	_update_trail()
	_emit_motes(delta)


func _aim_basis(dir: Vector3) -> Basis:
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	return Basis.looking_at(dir, up)


# --- The ribbon trail: a camera-facing strip through where it has been, rebuilt each frame.
func _add_trail() -> void:
	_rmesh = ImmediateMesh.new()
	_ribbon = MeshInstance3D.new()
	_ribbon.mesh = _rmesh
	_ribbon.top_level = true
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ribbon)
	_ribbon.global_transform = Transform3D.IDENTITY


func _update_trail() -> void:
	if _rmesh == null or not is_inside_tree():
		return
	var head := global_position
	if _hist.is_empty() or head.distance_to(_hist[0]) > TRAIL_SPACING:
		_hist.push_front(head)
	# Keep only as much path as the trail is long.
	var max_len: float = _look["len"] * (0.7 if Effects.quality == 0 else 1.0)
	var pts: Array[Vector3] = [head]
	var total := 0.0
	for p in _hist:
		var d := pts[pts.size() - 1].distance_to(p)
		if d < 0.001:
			continue
		if total + d >= max_len:
			pts.append(pts[pts.size() - 1].lerp(p, (max_len - total) / d))
			total = max_len
			break
		pts.append(p)
		total += d
	while _hist.size() > 2 and _hist.size() > pts.size() + 1:
		_hist.pop_back()
	_rmesh.clear_surfaces()
	if pts.size() < 2 or total < 0.05:
		return
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else head + Vector3(0, 5, 5)
	var w: float = _look["w"]
	_rmesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _ribbon_mat())
	var along := 0.0
	for i in pts.size():
		if i > 0:
			along += pts[i].distance_to(pts[i - 1])
		var seg := (pts[maxi(i - 1, 0)] - pts[mini(i + 1, pts.size() - 1)])
		var side := seg.cross(eye - pts[i])
		side = side.normalized() if side.length() > 0.0001 else Vector3.UP
		var t := along / total
		var half := w * 0.5 * (1.0 - 0.55 * t)
		_rmesh.surface_set_uv(Vector2(t, 0.0))
		_rmesh.surface_add_vertex(pts[i] + side * half)
		_rmesh.surface_set_uv(Vector2(t, 1.0))
		_rmesh.surface_add_vertex(pts[i] - side * half)
	_rmesh.surface_end()


# It's gone: its last ribbon stays a moment and fades instead of blinking out.
func _leave_trail() -> void:
	var parent := get_parent()
	if _ribbon == null or parent == null or not is_inside_tree():
		return
	_update_trail()
	var r := _ribbon
	_ribbon = null
	_rmesh = null
	r.reparent(parent)
	var tw := r.create_tween()
	tw.tween_method(func(f: float): r.set_instance_shader_parameter("fade", f), 1.0, 0.0, 0.18)
	tw.tween_callback(r.queue_free)


# --- Trailing motes: sparkles, drips, glints, down, little notes...
func _emit_motes(delta: float) -> void:
	var head := global_position
	var prev := _last_head
	_last_head = head
	if Effects.quality == 0 or prev == Vector3.INF or get_parent() == null:
		return
	_mote_acc += delta * float(_look["motes"]) * (1.6 if Effects.quality >= 2 else 1.0)
	var n := 0
	while _mote_acc >= 1.0 and n < 4:
		_mote_acc -= 1.0
		n += 1
		_trail_mote(prev.lerp(head, _rng.randf()))
	_mote_acc = minf(_mote_acc, 1.0)


func _rand_dir() -> Vector3:
	var v := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
	return v.normalized() if v.length() > 0.01 else Vector3.UP


func _trail_mote(p: Vector3) -> void:
	var parent := get_parent()
	var q := _quad()
	var jit := _rand_dir() * 0.06
	match "book" if book else kind:
		"holy_light":
			_fly(parent, q, _sprite_mat(1, Color(1.0, 0.97, 0.75, 1.0), 2.0), p + jit * 2.0, {
				"vel": _rand_dir() * 0.5, "life": 0.4, "s0": _rng.randf_range(0.12, 0.24), "s1": 0.02, "spin": 6.0})
		"blessed_water":
			_fly(parent, q, _sprite_mat(4, Color(0.75, 0.9, 1.0, 0.9), 1.3), p + jit, {
				"vel": _rand_dir() * 0.6 + velocity * 0.04, "grav": 9.0, "life": 0.45, "s0": _rng.randf_range(0.06, 0.11), "s1": 0.03})
		"halo_ring":
			_fly(parent, q, _sprite_mat(1, Color(1.0, 0.85, 0.4, 1.0), 2.0), p + jit, {
				"vel": _rand_dir() * 0.3, "life": 0.3, "s0": 0.14, "s1": 0.0, "spin": -4.0})
		"feather":
			_fly(parent, q, _sprite_mat(0, Color(1.0, 1.0, 1.0, 0.8), 1.2), p + jit * 2.0, {
				"vel": _rand_dir() * 0.25, "grav": 0.6, "drag": 2.0, "life": 0.8, "s0": 0.07, "s1": 0.14, "sway": 0.08})
		"choir":
			_fly(parent, q, _sprite_mat(2, Color(color.r, color.g, color.b, 1.0), 1.6), p + jit, {
				"vel": Vector3(0, 0.9, 0) + _rand_dir() * 0.25, "life": 0.9, "s0": 0.2, "s1": 0.28, "sway": 0.12,
				"spin": _rng.randf_range(-0.6, 0.6), "spin0": _rng.randf_range(-0.35, 0.35)})
		"book":
			_fly(parent, q, _sprite_mat(1, Color(1.0, 0.85, 0.5, 1.0), 1.8), p + jit * 3.0, {
				"vel": _rand_dir() * 0.4, "life": 0.45, "s0": 0.16, "s1": 0.02, "spin": 3.0})
		"vacuum":
			var off := _rand_dir() * size * 2.0
			_fly(parent, q, _sprite_mat(0, Color(0.85, 0.7, 1.0, 0.9), 1.8), p + off, {
				"vel": -off * 2.5, "life": 0.35, "s0": 0.12, "s1": 0.03})


# One short-lived bit: flies from `pos` with velocity, gravity and drag, grows or shrinks,
# fades (sprites) or shrinks away (solid bits), may spin and sway. Freed when done.
# opts: vel, grav, drag, life, s0, s1, spin (rad/s), sway (m), rot (Vector3 rad/s, solid bits),
#       basis (starting turn), solid (no alpha: shrink out at the end instead).
static func _fly(parent: Node, mesh: Mesh, mat: Material, pos: Vector3, opts: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var vel: Vector3 = opts.get("vel", Vector3.ZERO)
	var grav: float = opts.get("grav", 0.0)
	var drag: float = opts.get("drag", 0.0)
	var life: float = opts.get("life", 0.5)
	var s0: float = opts.get("s0", 0.2)
	var s1: float = opts.get("s1", s0)
	var spin: float = opts.get("spin", 0.0)
	var sway: float = opts.get("sway", 0.0)
	var rot: Vector3 = opts.get("rot", Vector3.ZERO)
	var b0: Basis = opts.get("basis", Basis())
	var solid: bool = opts.get("solid", false)
	var phase := fmod(pos.x * 13.1 + pos.z * 7.7, TAU)
	var spin0: float = opts.get("spin0", phase)
	mi.global_position = pos
	mi.basis = b0.scaled(Vector3.ONE * maxf(s0, 0.001))
	var step := func(t: float) -> void:
		var tt := t * life
		var travel := vel * tt if drag <= 0.0 else vel * (1.0 - exp(-drag * tt)) / drag
		var p := pos + travel + Vector3.DOWN * (0.5 * grav * tt * tt)
		if sway > 0.0:
			p += Vector3(sin(tt * 7.0 + phase), 0.0, cos(tt * 5.0 + phase)) * sway
		var s := lerpf(s0, s1, t)
		if solid:
			s *= 1.0 - smoothstep(0.75, 1.0, t)
		else:
			mi.set_instance_shader_parameter("fade", 1.0 - t * t)
			if spin != 0.0:
				mi.set_instance_shader_parameter("spin", spin * tt + spin0)
		var b := b0
		if rot != Vector3.ZERO:
			b = Basis.from_euler(rot * tt) * b0
		mi.global_transform = Transform3D(b.scaled(Vector3.ONE * maxf(s, 0.001)), p)
	if not solid:
		mi.set_instance_shader_parameter("fade", 1.0)
	var tw := mi.create_tween()
	tw.tween_method(step, 0.0, 1.0, life)
	tw.tween_callback(mi.queue_free)
	return mi


# --- Where it lands: each kind's flourish (a demon hit gets a smaller one under the red puff).
func _impact_look(pos: Vector3, normal: Vector3, on_demon: bool) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var k := "book" if book else kind
	var q := _quad()
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var at := pos + n * 0.05
	var flat := _flat_basis(n)
	var count := (1.0 if Effects.quality == 1 else (1.6 if Effects.quality >= 2 else 0.45)) * (0.6 if on_demon else 1.0)
	match k:
		"holy_light":
			_fly(parent, q, _sprite_mat(5, Color(1.0, 0.95, 0.65, 1.0), 2.2), at, {"life": 0.35, "s0": 0.4, "s1": 2.6, "spin": 0.8})
			_fly(parent, q, _sprite_mat(0, Color(1.0, 1.0, 0.9, 1.0), 2.5), at, {"life": 0.2, "s0": 1.4, "s1": 0.3})
			for i in int(10 * count):
				_fly(parent, q, _sprite_mat(1, Color(1.0, 0.95, 0.7, 1.0), 2.0), at, {
					"vel": (_rand_dir() + n).normalized() * _rng.randf_range(2.0, 4.5), "grav": 2.0, "drag": 2.5,
					"life": _rng.randf_range(0.35, 0.6), "s0": 0.22, "s1": 0.03, "spin": 5.0})
		"blessed_water":
			_fly(parent, q, _sprite_mat(3, Color(0.7, 0.9, 1.0, 0.9), 1.4, false), at, {
				"basis": flat, "life": 0.45, "s0": 0.2, "s1": 1.8})
			_fly(parent, q, _sprite_mat(3, Color(0.85, 0.95, 1.0, 0.7), 1.4, false), at, {
				"basis": flat, "life": 0.6, "s0": 0.1, "s1": 1.1})
			for i in int(12 * count):
				var d := (_rand_dir() * 0.7 + n).normalized()
				_fly(parent, q, _sprite_mat(4, Color(0.7, 0.88, 1.0, 0.95), 1.3), at, {
					"vel": d * _rng.randf_range(2.0, 4.0), "grav": 11.0, "life": _rng.randf_range(0.4, 0.6),
					"s0": _rng.randf_range(0.08, 0.14), "s1": 0.05})
		"halo_ring":
			# The ring clatters off the surface, wobbling, then winks out; a gold ring pulse under it.
			var side := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized().rotated(n, _rng.randf() * TAU)
			_fly(parent, _halo_mesh(), _gold_mat(color), at + n * 0.1, {
				"vel": n * 2.6 + side * 1.4, "grav": 9.0, "life": 0.6, "s0": 1.0, "s1": 0.9, "solid": true,
				"rot": Vector3(_rng.randf_range(8, 14), _rng.randf_range(10, 20), _rng.randf_range(-6, 6)),
				"basis": Basis(flat.x, n, flat.x.cross(n))})
			_fly(parent, q, _sprite_mat(3, Color(1.0, 0.85, 0.35, 0.9), 1.8, false), at, {"basis": flat, "life": 0.3, "s0": 0.3, "s1": 1.3})
			for i in int(6 * count):
				_fly(parent, q, _sprite_mat(1, Color(1.0, 0.9, 0.5, 1.0), 2.0), at, {
					"vel": (_rand_dir() + n).normalized() * 2.5, "drag": 3.0, "life": 0.35, "s0": 0.2, "s1": 0.0, "spin": 4.0})
		"feather":
			_fly(parent, q, _sprite_mat(0, Color(1.0, 1.0, 1.0, 0.8), 1.2), at, {"life": 0.3, "s0": 0.3, "s1": 1.1})
			for i in int(6 * count):
				var d := (_rand_dir() + n * 0.8).normalized()
				_fly(parent, _feather_mesh(), _feather_mat(), at, {
					"vel": d * _rng.randf_range(1.5, 3.0), "grav": 1.2, "drag": 2.5, "life": _rng.randf_range(0.9, 1.3),
					"s0": 0.45, "s1": 0.35, "solid": true, "sway": 0.12,
					"rot": Vector3(_rng.randf_range(-3, 3), _rng.randf_range(-4, 4), _rng.randf_range(-3, 3)),
					"basis": Basis.from_euler(_rand_dir() * 3.0)})
			for i in int(6 * count):
				_fly(parent, q, _sprite_mat(0, Color(1.0, 1.0, 1.0, 0.8), 1.2), at, {
					"vel": _rand_dir() * 1.2, "grav": 0.4, "drag": 2.0, "life": 0.8, "s0": 0.08, "s1": 0.16, "sway": 0.06})
		"choir":
			_fly(parent, q, _sprite_mat(3, Color(color.r, color.g, color.b, 0.9), 1.8), at, {"life": 0.35, "s0": 0.3, "s1": 1.6})
			for i in int(6 * count):
				var a := (float(i) / maxf(6.0 * count, 1.0) - 0.5) * 2.2
				_fly(parent, q, _sprite_mat(2, Color(color.r, color.g, color.b, 1.0), 1.7), at, {
					"vel": Vector3(sin(a) * 1.4, 1.6 + _rng.randf() * 0.8, cos(a * 1.7) * 0.8), "drag": 1.2,
					"life": _rng.randf_range(0.8, 1.1), "s0": 0.15, "s1": 0.32, "sway": 0.1, "spin": _rng.randf_range(-0.8, 0.8),
					"spin0": _rng.randf_range(-0.4, 0.4)})
		"book":
			_fly(parent, q, _sprite_mat(5, Color(1.0, 0.85, 0.45, 1.0), 2.0), at, {"life": 0.3, "s0": 0.5, "s1": 2.0, "spin": -0.6})
			for i in int(7 * count):
				_fly(parent, _page_mesh(), _page_mat(), at, {
					"vel": (_rand_dir() + n).normalized() * _rng.randf_range(1.5, 3.2), "grav": 2.0, "drag": 1.8,
					"life": _rng.randf_range(0.8, 1.2), "s0": 1.0, "s1": 0.8, "solid": true, "sway": 0.1,
					"rot": Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6), _rng.randf_range(-6, 6))})
		"vacuum":
			_fly(parent, q, _sprite_mat(3, Color(0.8, 0.6, 1.0, 1.0), 2.2), at, {"life": 0.3, "s0": 2.4, "s1": 0.1})
			_fly(parent, q, _sprite_mat(0, Color(0.95, 0.85, 1.0, 1.0), 2.5), at, {"life": 0.3, "s0": 0.3, "s1": 1.6})
			for i in int(10 * count):
				var off := _rand_dir() * 1.4
				_fly(parent, q, _sprite_mat(1, Color(0.85, 0.7, 1.0, 1.0), 2.0), at + off, {
					"vel": -off * 3.0, "life": 0.33, "s0": 0.2, "s1": 0.05, "spin": 6.0})
		_:
			if not on_demon:
				Effects.puff(parent, pos, Color(1.0, 0.95, 0.6, 0.7), 0.6)


static func _flat_basis(n: Vector3) -> Basis:
	# A quad (in its XY plane) lying on a surface with normal n.
	var x := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var y := n.cross(x).normalized()
	return Basis(x, y, n)


# ---------------------------------- shared resources ----------------------------------

static func _cached(key: String, make: Callable):
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


static func _shader(key: String, code: String) -> Shader:
	return _cached("shader_" + key, func():
		var s := Shader.new()
		s.code = code
		return s)


static func _quad() -> Mesh:
	return _cached("quad", func():
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		return q)


# A glowing sprite: shape 0 soft dot, 1 four-point sparkle, 2 eighth note, 3 ring, 4 droplet,
# 5 burst of rays. Faces the camera unless face_cam is false (then it lies in its own XY plane).
static func _sprite_mat(shape: int, c: Color, boost: float, face_cam := true) -> ShaderMaterial:
	var key := "sprite_%d_%s_%.2f_%s" % [shape, c.to_html(), boost, face_cam]
	return _cached(key, func():
		var m := ShaderMaterial.new()
		m.shader = _shader("sprite", SPRITE_SHADER)
		m.set_shader_parameter("col", c)
		m.set_shader_parameter("boost", boost)
		m.set_shader_parameter("shape", shape)
		m.set_shader_parameter("face_cam", face_cam)
		return m)


func _ribbon_mat() -> ShaderMaterial:
	var key := "ribbon_%s_%s" % [str(_look["style"]), color.to_html()]
	var tail: Color = _look["tail"]
	var style: int = _look["style"]
	var c := color
	return _cached(key, func():
		var m := ShaderMaterial.new()
		m.shader = _shader("ribbon", RIBBON_SHADER)
		m.set_shader_parameter("col", c)
		m.set_shader_parameter("col2", tail)
		m.set_shader_parameter("style", style)
		return m)


static func _glow_mat(key: String, albedo: Color, glow: Color, energy: float) -> StandardMaterial3D:
	return _cached("glow_" + key, func():
		var m := StandardMaterial3D.new()
		m.albedo_color = albedo
		m.emission_enabled = true
		m.emission = glow
		m.emission_energy_multiplier = energy
		m.roughness = 0.4
		return m)


static func _gold_mat(c: Color) -> StandardMaterial3D:
	return _cached("gold_" + c.to_html(), func():
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = 0.85
		m.roughness = 0.22
		m.metallic_specular = 0.8
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.1
		m.rim_enabled = true
		m.rim = 0.6
		return m)


static func _water_mat(c: Color) -> ShaderMaterial:
	return _cached("water_" + c.to_html(), func():
		var m := ShaderMaterial.new()
		m.shader = _shader("water", WATER_SHADER)
		m.set_shader_parameter("col", c)
		return m)


static func _orb_mat(c: Color) -> ShaderMaterial:
	return _cached("orb_" + c.to_html(), func():
		var m := ShaderMaterial.new()
		m.shader = _shader("orb", ORB_SHADER)
		m.set_shader_parameter("col", c)
		return m)


static func _feather_mat() -> StandardMaterial3D:
	return _cached("feather_mat", func():
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color.WHITE
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.85
		m.emission_enabled = true
		m.emission = Color(0.75, 0.8, 0.95)
		m.emission_energy_multiplier = 0.18
		m.rim_enabled = true
		m.rim = 0.25
		return m)


static func _page_mat() -> StandardMaterial3D:
	return _cached("page_mat", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.96, 0.82)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.emission_enabled = true
		m.emission = Color(1.0, 0.85, 0.45)
		m.emission_energy_multiplier = 0.9
		return m)


static func _halo_mesh() -> Mesh:
	return _cached("halo_mesh", func():
		var t := TorusMesh.new()
		t.inner_radius = 0.14
		t.outer_radius = 0.2
		t.rings = 20
		t.ring_segments = 6
		return t)


static func _page_mesh() -> Mesh:
	return _cached("page_mesh", func():
		var q := QuadMesh.new()
		q.size = Vector2(0.13, 0.17)
		return q)


# A 3D star: six long spikes along the axes and eight short ones on the diagonals.
static func _star_mesh() -> Mesh:
	return _cached("star_mesh", func():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
		for sx in [-1, 1]:
			for sy in [-1, 1]:
				for sz in [-1, 1]:
					dirs.append(Vector3(sx, sy, sz).normalized() * 0.55)
		for d in dirs:
			var dn: Vector3 = (d as Vector3).normalized()
			var u := dn.cross(Vector3.UP if absf(dn.y) < 0.9 else Vector3.RIGHT).normalized()
			var w := dn.cross(u)
			var r := 0.045
			var tip: Vector3 = d * 0.26
			var base := [u * r, w * r, -u * r, -w * r]
			for i in 4:
				st.add_vertex(base[i])
				st.add_vertex(base[(i + 1) % 4])
				st.add_vertex(tip)
		st.generate_normals()
		return st.commit())


# A feather 0.5 m long along Z (tip at -Z): bare quill, then two curved vanes, one narrower.
static func _feather_mesh() -> Mesh:
	return _cached("feather_mesh", func():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var steps := 9
		var z0 := 0.16
		var z1 := -0.26
		for side in [1.0, -0.72]:
			for i in steps:
				var a := float(i) / steps
				var b := float(i + 1) / steps
				var za := lerpf(z0, z1, a)
				var zb := lerpf(z0, z1, b)
				var wa: float = 0.075 * pow(sin(PI * pow(a, 0.75)), 0.6) * side
				var wb: float = 0.075 * pow(sin(PI * pow(b, 0.75)), 0.6) * side
				var notch := 0.55 if i == 5 and side > 0.0 else 1.0   # a little split in the vane
				var ea := Vector3(wa * notch, -absf(wa) * 0.5, za + 0.035)
				var eb := Vector3(wb, -absf(wb) * 0.5, zb + 0.035)
				var ca := Vector3(0, 0, za)
				var cb := Vector3(0, 0, zb)
				var edge := Color(0.72, 0.78, 0.92)
				var mid := Color(1, 1, 1)
				st.set_color(mid); st.add_vertex(ca)
				st.set_color(edge.lerp(Color(0.7, 0.78, 0.95), a)); st.add_vertex(ea)
				st.set_color(edge.lerp(Color(0.7, 0.78, 0.95), b)); st.add_vertex(eb)
				st.set_color(mid); st.add_vertex(ca)
				st.set_color(edge.lerp(Color(0.7, 0.78, 0.95), b)); st.add_vertex(eb)
				st.set_color(mid); st.add_vertex(cb)
		# The quill: a thin raised strip down the middle.
		var qc := Color(0.95, 0.88, 0.7)
		var qa := Vector3(0.006, 0.004, 0.25)
		var qb := Vector3(-0.006, 0.004, 0.25)
		var qd := Vector3(0.003, 0.004, z1)
		var qe := Vector3(-0.003, 0.004, z1)
		st.set_color(qc)
		for v in [qa, qb, qd, qb, qe, qd]:
			st.add_vertex(v)
		st.generate_normals()
		return st.commit())


# An eighth note in its XY plane: tilted oval head, stem, curved flag.
static func _note_mesh() -> Mesh:
	return _cached("note_mesh", func():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var head := SphereMesh.new()
		head.radius = 1.0
		head.height = 2.0
		head.radial_segments = 10
		head.rings = 5
		st.append_from(head, 0, Transform3D(Basis(Vector3.BACK, 0.45).scaled(Vector3(0.085, 0.06, 0.05)), Vector3(-0.04, -0.12, 0)))
		var stem := BoxMesh.new()
		stem.size = Vector3(0.022, 0.28, 0.03)
		st.append_from(stem, 0, Transform3D(Basis(), Vector3(0.03, 0.02, 0)))
		var flag := BoxMesh.new()
		flag.size = Vector3(0.09, 0.03, 0.03)
		st.append_from(flag, 0, Transform3D(Basis(Vector3.BACK, -0.75), Vector3(0.065, 0.12, 0)))
		st.append_from(flag, 0, Transform3D(Basis(Vector3.BACK, -0.35), Vector3(0.095, 0.075, 0)))
		return st.commit())


# The Holy Scripture: red cover, glowing pages, gold spine band, corners and a cross on each side.
static func _book_mesh() -> Mesh:
	return _cached("book_mesh", func():
		var cover_m := StandardMaterial3D.new()
		cover_m.albedo_color = Color(0.5, 0.11, 0.1)
		cover_m.roughness = 0.55
		cover_m.rim_enabled = true
		cover_m.rim = 0.3
		var page_m := StandardMaterial3D.new()
		page_m.albedo_color = Color(1.0, 0.95, 0.75)
		page_m.emission_enabled = true
		page_m.emission = Color(1.0, 0.85, 0.4)   # holy glow from the pages
		page_m.emission_energy_multiplier = 2.0
		var gold_m := StandardMaterial3D.new()
		gold_m.albedo_color = Color(1.0, 0.78, 0.3)
		gold_m.metallic = 0.9
		gold_m.roughness = 0.25
		gold_m.emission_enabled = true
		gold_m.emission = Color(1.0, 0.7, 0.25)
		gold_m.emission_energy_multiplier = 0.6
		var parts := {
			cover_m: [[Vector3(0.32, 0.09, 0.42), Vector3.ZERO]],
			page_m: [[Vector3(0.3, 0.07, 0.4), Vector3(0.015, 0, 0)]],
			gold_m: [
				[Vector3(0.03, 0.098, 0.43), Vector3(-0.152, 0, 0)],           # spine band
				[Vector3(0.035, 0.01, 0.22), Vector3(0.0, 0.048, 0.0)],        # cross, top
				[Vector3(0.14, 0.01, 0.035), Vector3(0.0, 0.048, -0.045)],
				[Vector3(0.035, 0.01, 0.22), Vector3(0.0, -0.048, 0.0)],       # cross, bottom
				[Vector3(0.14, 0.01, 0.035), Vector3(0.0, -0.048, -0.045)],
				[Vector3(0.05, 0.096, 0.05), Vector3(0.14, 0, 0.19)],          # corners
				[Vector3(0.05, 0.096, 0.05), Vector3(0.14, 0, -0.19)],
			],
		}
		var mesh := ArrayMesh.new()
		for mat in parts:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for part in parts[mat]:
				var b := BoxMesh.new()
				b.size = part[0]
				st.append_from(b, 0, Transform3D(Basis(), part[1]))
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		return mesh)


const SPRITE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0);
uniform float boost = 1.5;
uniform int shape = 0;
uniform bool face_cam = true;
instance uniform float fade = 1.0;
instance uniform float spin = 0.0;
instance uniform float lie_flat = 0.0;

void vertex() {
	if (face_cam && lie_flat < 0.5) {
		mat4 mv = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = mv * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
				vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
				vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	} else if (lie_flat > 0.5) {
		// lying in the parent's XZ plane (a quad is XY): turn it flat
		VERTEX = vec3(VERTEX.x, 0.0, VERTEX.y);
	}
}

void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float cs = cos(spin);
	float sn = sin(spin);
	p = vec2(cs * p.x - sn * p.y, sn * p.x + cs * p.y);
	float r = length(p);
	float a = 0.0;
	if (shape == 0) {
		a = pow(max(0.0, 1.0 - r), 2.2);
	} else if (shape == 1) {
		float rays = max(0.0, 1.0 - abs(p.x) * 9.0 - abs(p.y)) + max(0.0, 1.0 - abs(p.y) * 9.0 - abs(p.x));
		a = clamp(rays * 1.2 + pow(max(0.0, 1.0 - r * 2.6), 2.0), 0.0, 1.0);
	} else if (shape == 2) {
		vec2 h = p - vec2(-0.2, -0.5);
		h = vec2(0.9 * h.x + 0.44 * h.y, -0.44 * h.x + 0.9 * h.y);
		float head = length(h * vec2(1.0, 1.5)) - 0.28;
		float stem = max(abs(p.x - 0.05) - 0.055, abs(p.y - 0.12) - 0.62);
		float fx = p.x - 0.05;
		float flag = max(abs(p.y - (0.68 - fx * 0.9 - fx * fx * 0.8)) - 0.1, max(-fx, fx - 0.42));
		float d = min(head, min(stem, flag));
		a = 1.0 - smoothstep(-0.02, 0.04, d);
		a = max(a, 0.35 * (1.0 - smoothstep(0.0, 0.3, d)));
	} else if (shape == 3) {
		a = pow(max(0.0, 1.0 - abs(r - 0.78) * 7.0), 1.5) + 0.15 * pow(max(0.0, 1.0 - r), 2.0);
	} else if (shape == 4) {
		vec2 q = vec2(p.x, p.y + 0.25);
		float body = length(q) - 0.55;
		float tip = max(abs(p.x) - (0.8 - p.y) * 0.45, -q.y);
		float d = min(body, max(tip, p.y - 0.85));
		a = 1.0 - smoothstep(-0.05, 0.05, d);
		a *= 0.75 + 0.25 * smoothstep(0.35, 0.0, length(p - vec2(-0.2, -0.05)));
	} else {
		float ang = atan(p.y, p.x);
		float rays = pow(abs(cos(ang * 4.0)), 24.0) * 0.9 + pow(abs(cos(ang * 4.0 + 0.39)), 40.0) * 0.6;
		a = rays * (1.0 - smoothstep(0.15, 1.0, r)) + pow(max(0.0, 1.0 - r * 2.2), 2.0);
	}
	vec3 c = col.rgb;
	if (shape == 1 || shape == 5) {
		c = mix(c, vec3(1.0), clamp(1.0 - r * 3.0, 0.0, 1.0));
	}
	ALBEDO = c * boost;
	ALPHA = clamp(a * col.a * fade, 0.0, 1.0);
}
"""

const RIBBON_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0);
uniform vec4 col2 : source_color = vec4(1.0);
uniform float boost = 1.6;
uniform int style = 0;
instance uniform float fade = 1.0;

float h1(float x) { return fract(sin(x * 91.7) * 43758.5453); }

void fragment() {
	float t = UV.x;
	float v = UV.y * 2.0 - 1.0;
	float a = 1.0 - v * v;
	vec3 c = mix(col.rgb, col2.rgb, t);
	if (style == 1) {
		float core = exp(-v * v * 30.0);
		c = mix(c, vec3(1.0), core * (1.0 - t));
		float cell = floor(t * 16.0);
		float lx = (fract(t * 16.0) - 0.5) * 0.35;
		float ly = v - (h1(cell * 3.1) * 1.2 - 0.6);
		float tw = step(0.55, h1(cell + floor(TIME * 15.0) * 3.7)) * exp(-(lx * lx + ly * ly) * 60.0);
		a = a * 0.45 + core * 0.6 + tw;
		c = mix(c, vec3(1.0), tw * 0.7);
	} else if (style == 2) {
		float wv = v + sin(t * 22.0 - TIME * 25.0) * 0.35 * t;
		float core = exp(-wv * wv * 25.0);
		a = max(1.0 - wv * wv, 0.0) * 0.6 + core * 0.5;
		c = mix(c, vec3(1.0), core * 0.6);
	} else if (style == 3) {
		float lines = 0.0;
		for (int i = 0; i < 5; i++) {
			float y = -0.68 + float(i) * 0.34;
			lines += exp(-pow((v - y) * 16.0, 2.0));
		}
		a = a * 0.15 + lines * 0.95;
	} else if (style == 4) {
		float s = 0.5 + 0.5 * sin(v * 9.0 + t * 6.0 + sin(t * 13.0) * 1.5);
		a = a * (0.2 + 0.4 * s);
	} else if (style == 5) {
		float b = 0.5 + 0.5 * sin(v * 3.5 + t * 16.0 - TIME * 14.0);
		a = a * (0.3 + 0.7 * b);
		c = mix(c, vec3(1.0), b * b * 0.35);
	} else {
		float core = exp(-v * v * 20.0);
		a = a * 0.55 + core * 0.45;
		c = mix(c, vec3(1.0), core * 0.4 * (1.0 - t));
	}
	float start = smoothstep(0.0, 0.05, t);
	ALBEDO = c * boost;
	ALPHA = clamp(a * pow(1.0 - t, 1.3) * start * fade, 0.0, 1.0);
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;
uniform vec4 col : source_color = vec4(0.45, 0.75, 1.0, 1.0);

void vertex() {
	vec3 v = VERTEX;
	float w = sin(TIME * 19.0 + v.y * 7.0) * 0.08 + sin(TIME * 13.0 + v.x * 9.0) * 0.07;
	float tail = max(v.z, 0.0);
	v.xy *= 1.0 + w - 0.6 * smoothstep(0.0, 1.0, tail);
	v.z += tail * tail * 1.3 - w * 0.6;
	VERTEX = v;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float f = pow(1.0 - facing, 2.5);
	ALBEDO = col.rgb * 0.45;
	ROUGHNESS = 0.04;
	SPECULAR = 1.0;
	EMISSION = col.rgb * 0.55 + vec3(0.85, 0.95, 1.0) * f * 1.6;
	ALPHA = 0.55 + f * 0.45;
}
"""

const ORB_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec4 col : source_color = vec4(0.65, 0.35, 1.0, 1.0);
varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 p = normalize(lp);
	float lon = atan(p.z, p.x);
	float sw = lon * 3.0 + p.y * 7.0 - TIME * 5.0 + sin(p.y * 4.0 + TIME * 2.0) * 1.2;
	float bands = smoothstep(0.3, 0.95, 0.5 + 0.5 * sin(sw));
	float fine = 0.5 + 0.5 * sin(lon * 9.0 - p.y * 11.0 + TIME * 8.0);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float core = pow(facing, 5.0);
	float rim = pow(1.0 - facing, 3.0);
	vec3 deep = vec3(0.12, 0.04, 0.3);
	vec3 c = mix(deep, col.rgb * 1.2 + vec3(0.05, 0.1, 0.25), bands);
	c += vec3(0.5, 0.75, 1.0) * fine * bands * 0.35;
	float hot = smoothstep(0.8, 1.0, facing);
	c = mix(c, vec3(1.0, 0.92, 1.0) * 1.6, hot * hot * 0.8);
	c += vec3(0.55, 0.8, 1.0) * rim * 1.2;
	ALBEDO = c * 0.2;
	EMISSION = c * 1.15;
	ROUGHNESS = 0.3;
}
"""
