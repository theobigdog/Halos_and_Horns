# Plays a character's animations from how it's moving (works the same for your own body, other
# players and bots: it just watches where it is each frame). Idle, walk, run, in the air, flying
# (wings spread), and one-off actions (throw, cheer, hit) on request.
extends Node3D

const LOOPING := ["Idle", "Walking_A", "Running_A", "Jump_Idle", "Unarmed_Idle"]

var anim: AnimationPlayer
var wings: Node3D
var role := "angel"
var flying := false              # set by whoever owns it (demons flying)
var crouching := false           # sneaking: knees bent, low and leaning (crouch_modifier.gd)
var _crouch: Node
var _last := Vector3.ZERO
var _speed := 0.0
var _air := 0.0
var _playing := ""
var _action_until := 0.0
var _flap := 0.0
var _ruffle := 0.0                 # seconds left of a stretch-and-flap while standing about
var _ruffle_in := 6.0
var _rng := RandomNumberGenerator.new()   # (its own: the global one lays out seeded test maps)


func setup(player: AnimationPlayer, wing_node: Node3D, team: String) -> void:
	anim = player
	wings = wing_node
	role = team
	for n in LOOPING:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	var sk = anim.get_parent().find_children("*", "Skeleton3D", true, false)
	if not sk.is_empty():
		_crouch = load("res://scripts/crouch_modifier.gd").new()
		if team == "demon":
			_crouch.head_scale = 1.25
		sk[0].add_child(_crouch)
	_play("Idle", 0.0)


func _ready() -> void:
	_last = global_position
	_rng.seed = get_instance_id()
	_ruffle_in = _rng.randf_range(3.0, 9.0)


func _play(name: String, blend := 0.2) -> void:
	if anim == null or name == _playing or not anim.has_animation(name):
		return
	_playing = name
	anim.play(name, blend)


# A one-off: "Throw", "Cheer", "Hit_A", "Spellcast_Shoot"...
func play_action(name: String, seconds := 0.7) -> void:
	if anim == null or not anim.has_animation(name):
		return
	_playing = name
	anim.play(name, 0.08)
	_action_until = Time.get_ticks_msec() / 1000.0 + seconds


func _process(delta: float) -> void:
	if anim == null or delta <= 0.0:
		return
	var pos := global_position
	var move := pos - _last
	_last = pos
	var flat := Vector2(move.x, move.z).length() / delta
	_speed = lerpf(_speed, flat, minf(1.0, delta * 10.0))
	var body := get_parent()
	while body != null and not body is CharacterBody3D:
		body = body.get_parent()
	var grounded: bool = (body as CharacterBody3D).is_on_floor() if body is CharacterBody3D else absf(move.y / delta) < 0.6
	_air = 0.0 if grounded else _air + delta
	# Wings (they ride on the chest bone, so they lean and crouch with the body): folded and breathing
	# on the ground, with a stretch and a quick flap every so often; half open and beating in a jump;
	# spread and beating hard when flying; tucked in tight when crouching (Ted, Nov 27).
	if wings:
		var in_air := _air > 0.25
		_ruffle_in -= delta
		if _ruffle_in <= 0.0 and not in_air and not flying:
			_ruffle = 1.1
			_ruffle_in = _rng.randf_range(5.0, 11.0)
		_ruffle = maxf(_ruffle - delta, 0.0)
		var spread := 0.0
		var beat := 0.0
		if flying:
			_flap += delta * 11.0
			spread = 1.0
			beat = sin(_flap)
		elif in_air:
			_flap += delta * 8.0
			spread = 0.55
			beat = sin(_flap) * 0.6
		elif _ruffle > 0.0:
			_flap += delta * 13.0
			var k := sin(PI * _ruffle / 1.1)
			spread = 0.45 * k
			beat = sin(_flap) * 0.8 * k
		else:
			_flap += delta * 1.6
			beat = sin(_flap) * 0.08   # breathing
		var tuck := 1.0 if crouching and not in_air and not flying else 0.0
		for w in wings.get_children():
			var side := -1.0 if w.name == "L" else 1.0
			# (model space: +Y turns a wing's tip forward, +Z raises the right one; folded wings lie back
			# along the body)
			var ty := side * (0.55 + 0.3 * tuck - spread * (0.75 + beat * 0.35))
			var tz := side * (spread * 0.4 * beat + beat * 0.5 * (1.0 - spread) * 0.2 - 0.3 * tuck)
			w.rotation.y = lerp_angle(w.rotation.y, ty, minf(1.0, delta * 14.0))
			w.rotation.z = lerp_angle(w.rotation.z, tz, minf(1.0, delta * 14.0))
	if _crouch:
		_crouch.amount = move_toward(_crouch.amount, 1.0 if crouching and _air < 0.2 else 0.0, delta * 5.0)
	if Time.get_ticks_msec() / 1000.0 < _action_until:
		return
	if flying or _air > 0.2:
		_play("Jump_Idle")
	elif _speed > 4.8:
		_play("Running_A")
	elif _speed > 0.4:
		_play("Walking_A")
	else:
		_play("Idle")
