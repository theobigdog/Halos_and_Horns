# The local player. Plays as either an angel (throws blessings) or a demon
# (possesses props). T toggles first/third person; each side remembers its view.
extends CharacterBody3D

signal scared          # a demon's Fear caught us
signal hit_confirmed   # one of our throws hit a demon
signal threw(kind)     # we threw a blessed projectile of this kind
signal form_changed    # we possessed a prop or returned to demon form
signal taunted(taunt_name)
signal launched(origin, velocity, kind, gravity, seq)   # a throw left our hand (multiplayer forwards it)
signal hit_taken(damage, by)              # a counted hit on us as a demon (host decides); by = who
signal skill_used(skill_id, origin, dir, point, index)   # main decides what actually happens
signal melee_used(origin, dir)
signal released_possessed                 # we left a real (possessed) prop behind
signal bumped(thing, impulse)             # we ran into a loose prop, or a disguised demon: shove it (host decides)
signal no_room                            # tried to change into something that doesn't fit here
signal animate_pressed(n)                 # E: our disguise does its thing (the n-th press since we became it)

const GameRules = preload("res://scripts/game_rules.gd")
const PropLib = preload("res://scripts/prop_library.gd")
const PropAnims = preload("res://scripts/prop_anims.gd")
const Projectile = preload("res://scripts/projectile.gd")
const Effects = preload("res://scripts/effects.gd")
const Blessings = preload("res://scripts/blessings.gd")
const Taunts = preload("res://scripts/taunts.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Bodies = preload("res://scripts/bodies.gd")
const Characters = preload("res://scripts/characters.gd")
const PowerUps = preload("res://scripts/powerups.gd")
const Skills = preload("res://scripts/skills.gd")

const ANGEL_SPEED := 6.0
const DEMON_SPEED := 6.5
const MOUSE_SENSITIVITY := 0.0025
const PROJECTILE_SPEED := 80.0
const PROJECTILE_GRAVITY := 4.0
const WEAK_THROW_BELOW := 0.25    # under 25% blessing stamina, throws get slower and droop more
const POSSESS_REACH := 6.0        # how far past the camera a demon can possess
const THIRD_PERSON_DISTANCE := 3.5
const HOLD_TO_RETURN := 0.6       # seconds to hold left click to leave a prop
const BODY_HEIGHT := Bodies.BODY_HEIGHT
const CAMERA_ABOVE_HEAD := 0.45   # third person: centered behind you, crosshair just above your head
const OUTLINE_COLOR := Color(1.0, 0.35, 0.1)
const RUN_MULTIPLIER := 1.6       # Shift
const SNEAK_MULTIPLIER := 0.45    # Ctrl

# Throwing: click as fast as you like until blessing stamina runs out; holding the button only throws slowly
# (Ted, Nov 18: "too easy to kill a demon once you get your hands on them"). Quick Blessings turns the hold
# into a machine gun. All first guesses.
const THROW_COOLDOWN := 0.1       # clicking: up to 10 throws per second
const HOLD_THROW_EVERY := 0.6     # holding the button down: one throw this often...
const QUICK_HOLD_THROW_EVERY := 0.1   # ...or a machine gun with Quick Blessings
const THROW_STAMINA_MAX := 100.0
const THROW_COST := 10.0          # 10 throws from full (was 7, then 12; Nov 26: "runs out a little too quickly")
const THROW_REGEN := 18.0         # per second, ~1.5 throws a second once empty (was 30; Quick Blessings: x6)
const THROW_REGEN_DELAY := 0.0    # pause after a throw before regen starts (0 = always regenerating)

# Sprinting: its own stamina pool, separate from throwing.
const SPRINT_MAX := 100.0
const SPRINT_DRAIN := 22.0        # per second while running (~4.5 s from full)
const SPRINT_REGEN := 18.0
const SPRINT_REGEN_DELAY := 0.8
const SPRINT_RESTART := 25.0      # once empty, need this much back before running again

# Demons' Hatred: their "mana". Fills slowly; flying and demon skills spend it.
const HATRED_MAX := 100.0
const HATRED_REGEN := 4.0
const HATRED_FLY_DRAIN := 22.0    # while flying; minus regen = ~5.5 s of flight from full

# Flying (a demon skill, any form): hold its key for upward thrust, let go to fall.
# Thrust beats gravity, so you keep speeding up toward FLY_MAX_RISE. Jumping first
# gives a head start; from standing it takes a moment to build speed.
const FLY_THRUST := 24.0          # m/s² upward (gravity pulls ~13.2 the other way)
const FLY_MAX_RISE := 11.0
const FLY_CATCH_BOOST := 2.6      # thrust multiplier while still falling (stops a fall in a fraction of a second)        # top climbing speed, m/s
const PULL_SPEED := 24.0          # being yanked by a vacuum orb (much faster than the props)

const TAUNT_COOLDOWN := 0.8

# Movement feel. Live-editable from the F1 tuning panel to compare settings.
var tuning := {
	"ground_accel": 45.0,    # m/s² to reach full speed (higher = snappier starts)
	"ground_decel": 35.0,    # m/s² to stop (lower = more slide)
	"air_accel": 12.0,       # steering in the air
	"gravity_scale": 1.35,   # >1 = less floaty
	"fall_multiplier": 1.5,  # extra gravity on the way down
	"jump_velocity": 5.6,
	"head_bob": 1.0,         # 0 = off
	"camera_kick": 1.0,      # FOV widening when you run/dash, a lean when you strafe, landing squash (0 = off)
	"coyote_time": 0.1,      # seconds after running off a ledge you can still jump
	"jump_buffer": 0.12,     # press jump this early before landing and it still counts
	# Flying Dash (see _dash_step and _update_dash_momentum)
	"dash_speed": 18.0,        # m/s during the burst
	"dash_time": 0.25,         # seconds the burst lasts (speed x time = distance)
	"dash_carry": 0.75,        # share of the burst speed you keep as momentum afterwards
	"dash_ground_drag": 9.0,   # m/s of momentum lost per second on the ground
	"dash_air_drag": 2.0,      # ...and in the air
	"dash_turn_loss": 0.15,    # share of the momentum a slow, wide 180 costs
	"dash_sharp_turn": 360.0,  # turning this fast (deg/s) or faster costs the most: a 180 kills it all
}

var role := "demon"           # "angel" or "demon"
var frozen := false           # true while angels wait out the hiding period
var possessed_type := ""      # prop type the demon currently looks like ("" = demon form)
var possessed_index := -1     # >= 0 when that's a real map prop we possessed (not a copy)
var look_target_type := ""    # prop type the demon is aiming at (for the HUD hint)
var first_person := {"angel": true, "demon": false}
var hold_fraction := 0.0      # 0-1 progress of hold-to-return (for the HUD)
var blessing := "holy_light"  # which blessed projectile an angel throws
var running := false
var sneaking := false
var throw_stamina := THROW_STAMINA_MAX
var throw_regen_multiplier := 1.0   # the future "quick regen" power-up raises this
var sprint_stamina := SPRINT_MAX
var hatred := 0.0
var hatred_regen_multiplier := 1.0  # a future power-up raises this; high enough = endless flight
var flying := false
var skill_lock := 0.0         # seconds left of a vacuum lockout (no skills, no flying)
var loadout := Skills.DEFAULTS.duplicate(true)
var skill_cd := {}            # skill id -> seconds until ready
var melee_cd := 0.0
var last_taunt := ""
var input_enabled := true      # false while a menu is open
var net_mode := ""            # "" offline/practice, "server" = host, "client" = joined someone
var test_input := {}          # automated tests only: {"dir": Vector2, "sneak", "run", "jump": bool}

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _throw_cooldown := 0.0
var _since_throw := 99.0         # seconds since our last throw (holding the button throws slowly)
var _throw_strength := 1.0
var _throw_regen_wait := 0.0
var _sprint_regen_wait := 0.0
var _sprint_exhausted := false
var _taunt_cooldown := 0.0
var _holding := false
var _hold_time := 0.0
var _form_height := BODY_HEIGHT
var _hover_prop: Node3D       # prop currently outlined under the crosshair
var _outline_mat: StandardMaterial3D
var _bob_phase := 0.0
var _bob_offset := 0.0
var _land_dip := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _dash_time := 0.0          # seconds left of the dash burst
var _dash_dir := Vector3.ZERO  # where the burst is going (any direction, up and down too)
var _momentum := Vector2.ZERO  # sideways speed left over from a dash, on top of walking
var _momentum_ref := 0.0       # how much momentum the dash gave us (turn costs are a share of this)
var _steer_local := Vector2.ZERO   # last direction steered, relative to where we face
var _pull_target := Vector3.ZERO
var _pull_time := 0.0
var minion: Node3D = null     # our decoy, if we have one out (main creates it)
var vanish_time := 0.0         # Invisibility: seconds left
var pick_minion_form: Callable # main: a random prop type that's on the map right now
var burning := 0.0            # seconds left standing in demon fire (main refreshes it)
var feared := 0.0             # seconds left panicking from a demon's Fear
var _fear_from := Vector3.ZERO
var _fear_dir := Vector3.ZERO
var _fear_turn := 0.0
var _move_dir := Vector2.ZERO # last movement keys held (Holy Leap launches that way)
var _leaping := false         # in the air from a Holy Leap jump (strong steering; the camera widens a little)
var _stomping := false
var _leap_peak := 0.0          # the highest we got since leaving the ground (a stomp from higher hurts more)
var _fear_phase := Vector2.ZERO
# Camera juice (only on your own screen; nothing here changes how you actually move)
const BASE_FOV := 75.0
var _coyote := 0.0             # seconds left to still jump after leaving the ground
var _jump_buffer := 0.0        # seconds left on an early jump press
var _shake := 0.0              # camera shake strength, dies away
var _roll := 0.0               # strafing lean
var _squash := 0.0             # landing squash of your own body / prop (third person)
var _cam_y := 0.0              # smoothed camera height in third person (steps and bumps)

var shape_node: CollisionShape3D
var visual_root: Node3D
var _flames: CPUParticles3D
var pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var voice: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("snow_walker")   # (leaves footprints in snow: snow_tracks.gd)
	floor_max_angle = deg_to_rad(50.0)   # (stairs' smooth ramps are about 45 degrees)
	# Never get carried or launched by something moving under or next to us (other
	# players' bodies jump around as positions arrive). There are no moving platforms.
	platform_floor_layers = 0
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	collision_mask = 1 | 2   # the world, plus the invisible map walls and ceiling
	shape_node = CollisionShape3D.new()
	add_child(shape_node)
	visual_root = Node3D.new()
	add_child(visual_root)
	_flames = Effects.fly_flames()   # flying: flames from under you (you see them in third person)
	add_child(_flames)
	_flames.position.y = 0.1
	pivot = Node3D.new()
	add_child(pivot)
	spring = SpringArm3D.new()
	spring.margin = 0.2
	spring.add_excluded_object(get_rid())
	pivot.add_child(spring)
	camera = Camera3D.new()
	spring.add_child(camera)
	camera.current = true
	_warm_ghost()
	voice = AudioStreamPlayer3D.new()
	voice.bus = Sfx.BUS
	voice.unit_size = 6.0
	voice.max_distance = 70.0
	voice.position.y = 1.0
	add_child(voice)
	set_role(role)


func set_role(new_role: String) -> void:
	role = new_role
	possessed_type = ""
	look_target_type = ""
	_holding = false
	hold_fraction = 0.0
	_set_hover(null)
	pivot.rotation = Vector3.ZERO
	throw_stamina = THROW_STAMINA_MAX
	sprint_stamina = SPRINT_MAX
	_sprint_exhausted = false
	hatred = HATRED_MAX           # demons start full, so they can fly to a hiding spot
	last_taunt = ""
	possessed_index = -1
	flying = false
	skill_lock = 0.0
	skill_cd.clear()
	melee_cd = 0.0
	clear_dash()
	_pull_time = 0.0
	burning = 0.0
	feared = 0.0
	vanish_time = 0.0
	powerups.clear()
	sense_alarm = false
	_mantle_time = 0.0
	_leaping = false
	_stomping = false
	_apply_form()


# The wardrobe's last slot: an angel's blessing type, a demon's flame colour.
func _apply_trail() -> void:
	var o: Dictionary = outfits.get(role, {})
	if role == "angel" and o.get("trail", "") in Blessings.names():
		blessing = o["trail"]
	elif role == "demon" and _flames:
		Effects.tint_flames(_flames, Characters.trail_color("demon", o))


func _apply_form() -> void:
	_rig = null
	anim_presses = 0
	fuse_lit = false
	for child in visual_root.get_children():
		child.queue_free()
	_ghost_on = false   # a new look: (still invisible?) the next frame makes it ghostly again
	visual_root.rotation.y = 0.0
	if possessed_type != "":
		visual_root.add_child(PropLib.make_visual(possessed_type))
		shape_node.shape = PropLib.make_shape(possessed_type)
		_form_height = PropLib.height(possessed_type)
	else:
		var body := Bodies.make(role, outfits.get(role, {}))
		_apply_trail()
		visual_root.add_child(body)
		_rig = body if body.has_method("play_action") else null
		shape_node.shape = Bodies.make_shape(role)
		_form_height = Bodies.height_for(role)
	shape_node.position.y = _form_height / 2.0
	_apply_camera()


func _apply_camera() -> void:
	if first_person[role]:
		# Eyes at the top of the body, or just above the possessed prop.
		pivot.position.y = _form_height * 0.9 if possessed_type == "" else _form_height + 0.15
		_pivot_base = pivot.position.y
		spring.position.x = 0.0
		spring.spring_length = 0.0
		visual_root.visible = false
	else:
		# Straight behind you (centered), with the crosshair a little above your head,
		# so your own body sits just under it instead of covering it.
		pivot.position.y = maxf(_form_height, 0.6) + CAMERA_ABOVE_HEAD
		_pivot_base = pivot.position.y
		spring.position.x = 0.0
		spring.spring_length = THIRD_PERSON_DISTANCE
		visual_root.visible = true


func look(mouse_move: Vector2) -> void:
	var turn: float = -mouse_move.x * MOUSE_SENSITIVITY
	if _free_looking():
		pivot.rotation.y = wrapf(pivot.rotation.y + turn, -PI, PI)   # only the camera swings round
	else:
		rotate_y(turn)                                                # you (or your prop) turn too
	pivot.rotation.x = clampf(pivot.rotation.x - mouse_move.y * MOUSE_SENSITIVITY, -1.4, 1.2)


# Looking around without turning:
# - demons do it by default (the camera orbits you); hold Shift and your body or
#   prop turns along with the view.
# - angels turn with the mouse like any shooter (so the crosshair stays true);
#   hold Alt to look around without turning.
func _free_looking() -> bool:
	if role == "demon":
		return not Input.is_action_pressed("run")
	return Input.is_action_pressed("free_look")


# Which way the movement keys push: demons move relative to the camera (so you
# can glide your view while strafing); angels relative to their body.
func move_basis() -> Basis:
	var yaw := rotation.y + (pivot.rotation.y if role == "demon" else 0.0)
	return Basis(Vector3.UP, yaw)


func toggle_view() -> void:
	first_person[role] = not first_person[role]
	_apply_camera()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_throw_cooldown = 0.3   # don't fire on the click that grabs the mouse
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		look(event.relative)
		return
	if event.is_action_pressed("toggle_view"):
		toggle_view()
		return
	if event.is_action_pressed("cycle_blessing") and role == "angel":
		cycle_blessing()
		return
	# Taunts work even during the hiding period - trash talk is half the game.
	if event.is_action_pressed("taunt_random"):
		taunt(false)
		return
	if event.is_action_pressed("taunt_signature"):
		taunt(true)
		return
	if frozen:
		return
	if event.is_action_pressed("animate"):
		try_animate()
		return
	if event.is_action_pressed("minion_jump") and role == "demon" and is_instance_valid(minion):
		minion.jump()   # (no return: the same key is the angels' free look)
	if event.is_action_pressed("skill_1"):
		use_skill(0)
		return
	if event.is_action_pressed("melee"):
		if role == "angel":
			melee()
		return
	if event.is_action_pressed("rmb"):
		use_skill(1)
		return
	if event.is_action_pressed("shoot"):
		if role == "angel":
			try_throw()   # on the click itself, not the next physics tick
		elif possessed_type == "":
			try_transform()
		else:
			# Already a prop: a quick tap switches props, a hold returns to demon form.
			_holding = true
			_hold_time = 0.0
	elif event.is_action_released("shoot") and role == "demon" and _holding:
		_holding = false
		hold_fraction = 0.0
		if _hold_time < HOLD_TO_RETURN:
			try_transform()


func _physics_process(delta: float) -> void:
	_throw_cooldown = maxf(_throw_cooldown - delta, 0.0)
	if _flames.emitting != flying:
		_flames.emitting = flying
	if _rig:
		_rig.flying = flying
		_rig.crouching = sneaking
	_since_throw += delta
	_taunt_cooldown = maxf(_taunt_cooldown - delta, 0.0)
	melee_cd = maxf(melee_cd - delta, 0.0)
	skill_lock = maxf(skill_lock - delta, 0.0)
	for id in skill_cd:
		skill_cd[id] = maxf(skill_cd[id] - delta * (3.0 if powerup_left("quick_skills") > 0.0 else 1.0), 0.0)
	_tick_powerups(delta)
	if vanish_time > 0.0:
		vanish_time -= delta
	_ghostly(vanish_time > 0.0)
	var on_floor := is_on_floor()

	var controls_active := input_enabled and not frozen and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var input_dir := Vector2.ZERO
	var want_run := false
	var want_jump := false
	var want_fly := false
	sneaking = false
	if not test_input.is_empty():
		# Automated tests drive movement here (headless mode can't capture the mouse).
		input_dir = test_input.get("dir", Vector2.ZERO)
		sneaking = test_input.get("sneak", false)
		want_run = test_input.get("run", false)
		want_jump = test_input.get("jump", false)
		want_fly = test_input.get("fly", false)
	elif controls_active:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		sneaking = Input.is_action_pressed("sneak")
		want_run = Input.is_action_pressed("run")
		want_jump = Input.is_action_just_pressed("jump")
		want_fly = _hold_key_down("fly")
	if stunned > 0.0:
		# Stunned stiff (Holy Word): no moving, jumping or flying.
		stunned -= delta
		input_dir = Vector2.ZERO
		want_run = false
		want_jump = false
		want_fly = false
	if _struck_down and on_floor:
		_struck_down = false   # back on the ground: free to fly again
	if burning > 0.0 and input_dir != Vector2.ZERO:
		# On fire: flailing about trying to cool off, you can't walk a straight line.
		var tt := Time.get_ticks_msec() / 1000.0
		var lurch := Vector2(1.3 * sin(tt * 2.1) + 0.6 * sin(tt * 7.3 + 1.3), 0.6 * sin(tt * 4.3 + 2.0))
		input_dir = (input_dir + lurch).limit_length(1.0)
	if feared > 0.0:
		# Panicking: run off in a blind scatter, roughly away from the demon.
		feared -= delta
		_fear_turn -= delta
		if _fear_turn <= 0.0 or _fear_dir == Vector3.ZERO:
			var away := Vector3(global_position.x - _fear_from.x, 0.0, global_position.z - _fear_from.z)
			if away.length() < 0.1:
				away = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
			_fear_dir = away.normalized().rotated(Vector3.UP, randf_range(-1.1, 1.1))
			_fear_turn = randf_range(0.3, 0.7)
		var local := move_basis().inverse() * _fear_dir
		input_dir = Vector2(local.x, local.z).normalized()
		want_run = true
		want_jump = is_on_wall() and randf() < 0.1
		sneaking = false
		# ...and your aim shakes all over the place.
		var tt := Time.get_ticks_msec() / 1000.0
		var shake := Skills.FEAR_SHAKE * delta
		rotation.y += shake * (sin(tt * 5.3 + _fear_phase.x) + 0.6 * sin(tt * 11.7 + _fear_phase.y))
		pivot.rotation.x = clampf(pivot.rotation.x + shake * 0.6 * (sin(tt * 6.1 + _fear_phase.y) + 0.5 * sin(tt * 13.3 + _fear_phase.x)), -1.4, 1.4)
	_move_dir = input_dir
	_steer_minion()
	_settle_view(delta, input_dir)

	# Hatred always refills; flying spends it faster than it refills (unless boosted).
	if role == "demon":
		flying = want_fly and "fly" in loadout["demon"] and not frozen and hatred > 0.5 and skill_lock <= 0.0 and not _struck_down
		hatred += HATRED_REGEN * hatred_regen_multiplier * delta
		if flying:
			hatred -= HATRED_FLY_DRAIN * delta
		hatred = clampf(hatred, 0.0, HATRED_MAX)
	else:
		flying = false

	# Walking speed is everything except the dash momentum riding on top of it.
	var current := Vector2(velocity.x, velocity.z) - _momentum
	if _mantle_time > 0.0:
		_mantle_step(delta)
		move_and_slide()
		return
	if _pull_time > 0.0:
		_pull_step(delta)
		running = false
	elif _dash_time > 0.0:
		_dash_step(delta)
		running = false
	else:
		if flying:
			# Thrust up against plain gravity; WASD steers like any other time in the air.
			var g_fly: float = gravity * tuning["gravity_scale"] * GameRules.f("gravity") * GameRules.f("gravity")
			# Already falling? Catch yourself much harder, so the fall stops quickly
			# (taking off from the ground or a jump feels the same as before).
			var thrust := FLY_THRUST * (FLY_CATCH_BOOST if velocity.y < 0.0 else 1.0)
			velocity.y = minf(velocity.y + (thrust - g_fly) * delta, FLY_MAX_RISE)
			_fall_speed = 0.0
		elif not on_floor:
			var g: float = gravity * tuning["gravity_scale"] * GameRules.f("gravity")
			if velocity.y < 0.0:
				g *= tuning["fall_multiplier"]   # fall faster than you rise: less floaty
			velocity.y -= g * delta
			_fall_speed = maxf(_fall_speed, -velocity.y)
		# A little forgiveness: jump just after running off a ledge, or press it just
		# before landing. (Same jump either way.)
		_coyote = tuning["coyote_time"] if on_floor else _coyote - delta
		_jump_buffer = tuning["jump_buffer"] if want_jump else _jump_buffer - delta
		if _jump_buffer > 0.0 and (on_floor or (_coyote > 0.0 and velocity.y <= 0.0)) and not flying:
			velocity.y = Skills.LEAPER_JUMP if _is_leaper() else tuning["jump_velocity"]
			_leaping = _is_leaper()
			_jump_buffer = 0.0
			_coyote = 0.0

		_update_sprint(delta, want_run and not sneaking and input_dir != Vector2.ZERO)

		var direction := move_basis() * Vector3(input_dir.x, 0.0, input_dir.y)
		direction.y = 0.0
		direction = direction.normalized()
		var speed := ANGEL_SPEED if role == "angel" else PropLib.speed(possessed_type)
		if burning > 0.0:
			speed *= Skills.FIRE_SLOW
		if running:
			speed *= RUN_MULTIPLIER
		elif sneaking:
			speed *= SNEAK_MULTIPLIER
		# Accelerate toward the wanted speed instead of snapping to it: gives weight.
		var target := Vector2(direction.x, direction.z) * speed
		var rate: float
		if not on_floor and input_dir == Vector2.ZERO:
			rate = 0.0                     # no keys held in the air: keep your momentum
			target = current
		elif not on_floor:
			rate = Skills.LEAP_AIR_ACCEL if _leaping else (Skills.LEAPER_AIR_ACCEL if _is_leaper() else tuning["air_accel"])
		elif target.length() < current.length():
			rate = tuning["ground_decel"]
		else:
			rate = tuning["ground_accel"]
		if on_floor and _on_ice:
			rate *= ICE_GRIP   # ice: hard to get going, harder to stop or turn
			if target.length() < current.length() or current.normalized().dot(target.normalized()) < 0.7:
				rate *= ICE_STOP   # (stopping and turning slide even further: Nov 24, "slightly slipperier")
			# Running and turning hard on ice: you slip and fall for a moment.
			if current.length() > ICE_SLIP_SPEED and target.length() > 0.5 and current.normalized().dot(target.normalized()) < -0.2 \
					and _slip_cooldown <= 0.0 and stunned <= 0.0:
				slip()
		current = current.move_toward(target, rate * delta)
		_update_dash_momentum(delta, input_dir, on_floor)
		velocity.x = current.x + _momentum.x
		velocity.z = current.y + _momentum.y
	_leap_peak = global_position.y if is_on_floor() else maxf(_leap_peak, global_position.y)
	if _stomping:
		clear_dash()
		velocity = Vector3(0.0, -Skills.STOMP_SPEED, 0.0)
	var before_slide := velocity
	var floored := is_on_floor()
	move_and_slide()
	if floored and not flying and is_on_wall() and Vector2(before_slide.x, before_slide.z).length() > 0.5:
		_try_step_up(before_slide, delta)
	# (stepping up pops us up a little: the camera and body catch up smoothly)
	if _step_lift < 0.0:
		_step_lift = minf(_step_lift + delta * 3.0, 0.0)
		visual_root.position.y = _step_lift
		pivot.position.y = _pivot_base + _step_lift
	_slip_cooldown = maxf(_slip_cooldown - delta, 0.0)
	_on_ice = false
	if is_on_floor():
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.2, global_position + Vector3.DOWN * 0.4)
		q.exclude = [get_rid()]
		var under := get_world_3d().direct_space_state.intersect_ray(q)
		_on_ice = not under.is_empty() and under["collider"] is Node and (under["collider"] as Node).is_in_group("ice")
	_check_bumps(before_slide)
	_slide_off_heads()
	if role == "angel" and not is_on_floor() and is_on_wall() and input_dir != Vector2.ZERO and not frozen:
		_try_ledge_grab()
	current = Vector2(velocity.x, velocity.z)
	if _momentum != Vector2.ZERO and is_on_wall():
		# Ran into something: keep only the momentum we're actually still moving with.
		var heading := _momentum.normalized()
		_momentum = heading * clampf(current.dot(heading), 0.0, _momentum.length())
	if is_on_floor() and (_leaping or _stomping) and velocity.y <= 0.0:
		if _stomping:
			# Cloud Stomp landed: the host / practice game decides who it hurts.
			# (point.y = the highest we got: the higher, the harder it hits)
			var top := Vector3(global_position.x, maxf(_leap_peak, global_position.y), global_position.z)
			skill_used.emit("stomp", global_position, Vector3.DOWN, top, -1)
		_leaping = false
		_stomping = false
	if burning > 0.0:
		burning -= delta
		throw_stamina = maxf(throw_stamina - Skills.FIRE_BLESSING_BURN * delta, 0.0)

	_update_head_bob(delta, current.length())
	_update_camera_juice(delta, input_dir)
	_update_throw_stamina(delta)
	_anim_cd = maxf(_anim_cd - delta, 0.0)

	if role == "angel":
		# Holding the button keeps throwing, but slowly (each click throws straight away, in _unhandled_input).
		var shoot_held: bool = test_input.get("shoot", false) if not test_input.is_empty() 				else controls_active and Input.is_action_pressed("shoot")
		if shoot_held and _since_throw >= hold_throw_every():
			try_throw()
		return

	if _holding:
		_hold_time += delta
		hold_fraction = minf(_hold_time / HOLD_TO_RETURN, 1.0)
		if _hold_time >= HOLD_TO_RETURN:
			_holding = false
			hold_fraction = 0.0
			unpossess()
	var aim := _aim_ray(spring.spring_length + POSSESS_REACH)
	var hovered: Node3D = null
	if not aim.is_empty() and aim["collider"].is_in_group("prop"):
		hovered = aim["collider"]
	_set_hover(hovered)
	look_target_type = hovered.get_meta("prop_type") if hovered else ""


# Is the key for this "hold" skill (e.g. Fly) held down? Q for slot 1, right click for slot 2.
func _hold_key_down(id: String) -> bool:
	var lo: Array = loadout[role]
	return (lo[0] == id and Input.is_action_pressed("skill_1")) \
			or (lo[1] == id and Input.is_action_pressed("rmb"))


# The dash burst: a straight line at full speed, whichever way it was aimed.
# Gravity waits until it's over. What's left afterwards is momentum.
func _dash_step(delta: float) -> void:
	_dash_time -= delta
	velocity = _dash_dir * tuning["dash_speed"]
	if _dash_time > 0.0:
		return
	var carry: float = tuning["dash_carry"]
	_momentum = Vector2(velocity.x, velocity.z) * carry
	_momentum_ref = _momentum.length()
	velocity.y *= carry
	# The walking part starts from nothing: all the sideways speed is momentum now.
	velocity.x = _momentum.x
	velocity.z = _momentum.y
	var local := global_transform.basis.inverse() * Vector3(_momentum.x, 0.0, _momentum.y)
	_steer_local = Vector2(local.x, local.z).normalized()


# Dash momentum follows where you steer (the keys you hold, turned by where you
# face), and steering is what costs it. Every bit of turning takes a share of the
# momentum the dash gave you: turned slowly, a full 180 costs only dash_turn_loss
# of it; at dash_sharp_turn degrees per second or faster a 180 costs all of it.
# Swapping keys (strafing) is an instant turn, so it always costs the most.
func _update_dash_momentum(delta: float, input_dir: Vector2, on_floor: bool) -> void:
	var speed := _momentum.length()
	if speed <= 0.0:
		return
	if input_dir != Vector2.ZERO:
		_steer_local = input_dir.normalized()
	var steer3 := move_basis() * Vector3(_steer_local.x, 0.0, _steer_local.y)
	var steer := Vector2(steer3.x, steer3.z).normalized()
	var turned := absf(_momentum.angle_to(steer))
	if turned > 0.0001:
		var sharp := deg_to_rad(maxf(tuning["dash_sharp_turn"], 1.0))
		var cost := lerpf(tuning["dash_turn_loss"], 1.0, clampf(turned / delta / sharp, 0.0, 1.0))
		speed -= _momentum_ref * cost * turned / PI
	speed -= (tuning["dash_ground_drag"] if on_floor else tuning["dash_air_drag"]) * delta
	_momentum = steer * speed if speed > 0.1 else Vector2.ZERO


# Stop any dash and drop its momentum (caught, yanked, moved by the host...).
func clear_dash() -> void:
	_dash_time = 0.0
	_momentum = Vector2.ZERO


# Being yanked somewhere by the angels (vacuum orb).
func _pull_step(delta: float) -> void:
	_pull_time -= delta
	var to := _pull_target - global_position
	if to.length() < 0.8:
		_pull_time = 0.0
		velocity = Vector3.ZERO
		return
	velocity = to.normalized() * minf(PULL_SPEED, to.length() / maxf(delta, 0.001))


# Called when the host (or practice game) yanks us somewhere.
func pull_to(target: Vector3, seconds := 1.0) -> void:
	_pull_target = target
	_pull_time = seconds
	clear_dash()


# ---- Ledge grab (angels) ----
# In the air, pushing into a wall whose top edge your hands could reach: grab it
# and pull yourself up onto it.
const LEDGE_REACH := 0.55       # how far above your head your hands reach
const MANTLE_TIME := 0.35
var _mantle_time := 0.0
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO


func _try_ledge_grab() -> void:
	var wall_n := get_wall_normal()
	wall_n.y = 0.0
	if wall_n.length() < 0.5:
		return
	wall_n = wall_n.normalized()
	var push := move_basis() * Vector3(_move_dir.x, 0.0, _move_dir.y)
	if push.normalized().dot(-wall_n) < 0.4:
		return   # not pushing toward the wall
	var feet := global_position
	var h := Bodies.height_for(role)
	var space := get_world_3d().direct_space_state
	# Feel for the top of the wall, just past its face, from hand height down to the waist.
	var over := feet - wall_n * 0.45
	var q := PhysicsRayQueryParameters3D.create(over + Vector3.UP * (h + LEDGE_REACH), over + Vector3.UP * (h * 0.45), 1)
	q.exclude = [get_rid()]
	var top := space.intersect_ray(q)
	if top.is_empty() or top["normal"].y < 0.7:
		return
	var land: Vector3 = top["position"]
	if land.y - feet.y < 0.4:
		return   # that's just a step
	# Room to stand up there?
	var room := PhysicsRayQueryParameters3D.create(land + Vector3.UP * 0.05, land + Vector3.UP * (h + 0.1), 1)
	room.exclude = [get_rid()]
	if not space.intersect_ray(room).is_empty():
		return
	clear_dash()
	_mantle_from = feet
	_mantle_to = land + Vector3.UP * 0.05 - wall_n * 0.15
	_mantle_time = MANTLE_TIME
	velocity = Vector3.ZERO


func _mantle_step(delta: float) -> void:
	_mantle_time -= delta
	var t := 1.0 - clampf(_mantle_time / MANTLE_TIME, 0.0, 1.0)
	# Up first, then over the edge.
	var up := clampf(t / 0.65, 0.0, 1.0)
	var over := clampf((t - 0.45) / 0.55, 0.0, 1.0)
	var p := _mantle_from
	p.y = lerpf(_mantle_from.y, _mantle_to.y, up)
	p.x = lerpf(_mantle_from.x, _mantle_to.x, over)
	p.z = lerpf(_mantle_from.z, _mantle_to.z, over)
	global_position = p
	velocity = Vector3.ZERO


# A bouncy flung us upward. (Returns whether it took: frozen players don't bounce.)
func bounce(up_speed: float) -> bool:
	if frozen:
		return false
	velocity.y = up_speed
	_fall_speed = 0.0
	_leaping = false
	_stomping = false
	_mantle_time = 0.0
	clear_dash()
	bounced.emit()
	return true


signal bounced


# The decider moved us (Teleport).
func teleport_to(pos: Vector3) -> void:
	global_position = pos + Vector3.UP * 0.05
	velocity = Vector3.ZERO
	clear_dash()
	_mantle_time = 0.0


func is_mantling() -> bool:
	return _mantle_time > 0.0


func is_dashing() -> bool:
	return _dash_time > 0.0


# Sideways speed still left over from a dash.
func dash_momentum() -> float:
	return _momentum.length()


# Q (slot 0), and right mouse (angels) or F (demons) for slot 1.
# Only the parts that must feel instant happen here (dashing, leaping);
# everything else is decided by the host / practice game via skill_used.
func use_skill(slot: int) -> bool:
	var id: String = loadout[role][slot]
	if id == "" or frozen or stunned > 0.0 or skill_cd.get(id, 0.0) > 0.0 or Skills.SKILLS[id].get("hold", false):
		return false
	if role == "demon" and skill_lock > 0.0:
		return false
	if hatred < Skills.hatred_cost(id) and role == "demon":
		return false
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	var point := Vector3.ZERO
	var index := -1
	match id:
		"teleport":
			# Where to: the spot under the crosshair, or as far as allowed that way.
			var spot := _aim_ray(150.0)
			var aimed: Vector3 = spot["position"] - dir * 0.5 if not spot.is_empty() else origin + dir * 150.0
			var reach := Vector3(aimed.x - global_position.x, 0.0, aimed.z - global_position.z).limit_length(Skills.TELEPORT_RANGE)
			point = Vector3(global_position.x + reach.x, aimed.y if reach.length() < Skills.TELEPORT_RANGE - 0.01 else 20.0, global_position.z + reach.z)
			hatred -= Skills.hatred_cost(id)
		"minion":
			if is_instance_valid(minion):
				return false            # one at a time; holding the key steers it
			# It appears wherever you're aiming (up to 30 m away), no puff, no sound.
			var spot := _aim_ray(Skills.MINION_RANGE)
			point = spot["position"] - dir * 0.3 if not spot.is_empty() else origin + dir * Skills.MINION_RANGE
			# In our own body it's a copy of us; disguised, it's some prop from this map.
			index = -1
			if possessed_type != "" and pick_minion_form.is_valid():
				index = PropLib.type_names().find(pick_minion_form.call())
			hatred -= Skills.hatred_cost(id)
		"possess":
			if not is_instance_valid(_hover_prop) or not _hover_prop.has_meta("prop_index"):
				return false
			index = _hover_prop.get_meta("prop_index")
			point = _hover_prop.global_position
		"dash":
			if _stomping or _pull_time > 0.0:
				return false
			# Any direction: where you're looking (up and down too), or the way the
			# movement keys point relative to that - back to dash backwards, and so on.
			var aim := camera.global_transform.basis
			var want := aim * Vector3(_move_dir.x, 0.0, _move_dir.y)
			_dash_dir = want.normalized() if want.length() > 0.1 else dir
			_dash_time = tuning["dash_time"]
			_momentum = Vector2.ZERO
			_leaping = false
			_fall_speed = 0.0
			dir = _dash_dir
			point = global_position + _dash_dir * tuning["dash_speed"] * tuning["dash_time"]
		"vacuum":
			point = origin + dir
		"leap":
			# Holy Leap's key: only works in the air (its jumps are just your ordinary jump, much higher).
			# Cloud Stomp: slam straight down from right where you are; the stomp lands in _physics_process.
			if is_on_floor() or _stomping or _pull_time > 0.0:
				return false
			_stomping = true
			point = Vector3(global_position.x, _leap_peak, global_position.z)
		"kick":
			origin = pivot.global_position     # reach is measured from us, not the camera
			Effects.swing(get_parent(), origin - Vector3.UP * 0.8, dir)
		"fire", "fear":
			hatred -= Skills.hatred_cost(id)
	skill_cd[id] = Skills.cooldown(id)
	skill_used.emit(id, origin, dir, point, index)
	return true


func melee() -> bool:
	if melee_cd > 0.0 or frozen or role != "angel":
		return false
	melee_cd = Skills.MELEE_COOLDOWN
	var origin := pivot.global_position   # on the crosshair line in both views, at our own head
	var dir := -camera.global_transform.basis.z
	Effects.swing(get_parent(), origin - Vector3.UP * 0.3, dir)
	melee_used.emit(origin, dir)
	return true


# The host / practice game approved a possession: we ARE that prop now, exactly
# where it stood. No puff: possessing is meant to be sneaky.
func become_possessed(type_name: String, pos: Vector3, yaw: float, index: int) -> void:
	possessed_index = index
	possessed_type = type_name
	var cam_from := pivot.global_position
	global_position = pos
	velocity = Vector3.ZERO
	_apply_form()
	# Keep looking where we were looking; only the prop keeps its own facing.
	visual_root.rotation.y = wrapf(yaw - rotation.y, -PI, PI)
	# And glide the camera over to the new prop instead of jumping there.
	var cam_to := pivot.position
	pivot.global_position = cam_from
	var tw := create_tween()
	tw.tween_property(pivot, "position", cam_to, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	form_changed.emit()


# ---- Power-ups we're holding ----
var powerups := {}            # kind -> seconds left
var sense_alarm := false      # Cherub Sense: the host says a demon is close to us
signal powerup_taken(kind)


func apply_powerup(kind: String) -> void:
	if kind == "vanish":
		vanish_time = Skills.VANISH_TIME
	if kind == "quick_skills":
		skill_cd.clear()   # all your skills ready right now, so none of the power-up is wasted on a cooldown
	powerups[kind] = PowerUps.DURATION.get(kind, 0.0)
	powerup_taken.emit(kind)


# Running into things shoves them (Ted, Nov 18: "everything in the game can collide"). A loose prop, or a
# demon disguised as one: both get shoved the same way, so a prop that won't budge never gives a demon away.
const BUMP_MIN := 1.5        # m/s into it before it counts (just leaning on something does nothing)
const BUMP_SHARE := 0.8      # share of that speed passed on as a shove (first guess)
var _bump_ready := {}        # thing -> time it can be bumped again


func _check_bumps(before: Vector3) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var thing := col.get_collider()
		var n := col.get_normal()
		if thing == null or absf(n.y) > 0.5:
			continue   # floors and ceilings don't count
		var is_prop: bool = thing.is_in_group("prop") and thing.has_meta("prop_index")
		var disguised: bool = str(thing.get("form")) not in ["", "<null>"] or str(thing.get("prop_type")) not in ["", "<null>"]
		if not is_prop and not disguised:
			continue
		var into := -Vector3(before.x, 0.0, before.z).dot(Vector3(n.x, 0.0, n.z).normalized())
		if into < BUMP_MIN or t < _bump_ready.get(thing, 0.0):
			continue
		_bump_ready[thing] = t + 0.35
		var push := -Vector3(n.x, 0.0, n.z).normalized() * into * BUMP_SHARE
		bumped.emit(thing, push)
	if _bump_ready.size() > 40:
		_bump_ready.clear()


# Jump as if the key was just pressed (bots).
func queue_jump() -> void:
	_jump_buffer = tuning["jump_buffer"]


# Holy Leap picked: every ordinary jump is higher and easier to steer.
func _is_leaper() -> bool:
	return role == "angel" and "leap" in loadout["angel"]


# A demon's Fear caught us: panic for a few seconds.
# Holy Word struck us out of the sky: slammed down, can't fly again until we land, frozen stiff for a moment.
var stunned := 0.0
var outfits := {}                 # "angel"/"demon" -> outfit (characters.gd), set by main from the wardrobe
var _rig: Node3D                  # our body's animation player (character_rig.gd), in body form
var _on_ice := false
var _step_lift := 0.0             # how far below its spot our body still shows after a step up (catching up)
var _pivot_base := 0.0
const STEP_HEIGHT := 0.5          # walk straight up stairs, curbs and ledges this high (structures only; first guess)
var _slip_cooldown := 0.0
const ICE_GRIP := 0.12            # ice: this much of the normal grip (first guess)
const ICE_STOP := 0.65            # ...and only this much of that for stopping or turning (Nov 24: slipperier; first guess)
const ICE_SLIP_SPEED := 6.0       # turning back on yourself faster than this on ice: you slip and fall
const ICE_FALL_TIME := 0.9        # ...and lie there this long
var _struck_down := false


# Walking into a stair, curb or low ledge (Ted, Nov 20): if it's part of the map (not a prop or a
# player) and there's room on top, step up onto it instead of stopping.
func _try_step_up(wanted: Vector3, delta: float) -> void:
	var blocker = null
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		# (anything too steep to walk up counts: bevelled edges like the city roofs' rims meet the
		# capsule's round bottom at a slant, not straight on, and used to block you for good)
		if c.get_normal().y < cos(floor_max_angle) - 0.02:
			blocker = c.get_collider()
	if blocker == null or not blocker is StaticBody3D or (blocker as Node).is_in_group("prop"):
		return   # props and players still block us
	var flat := Vector3(wanted.x, 0.0, wanted.z)
	var ahead := flat.normalized() * maxf(flat.length() * delta, 0.2)
	var xf := global_transform
	if test_move(xf, Vector3.UP * STEP_HEIGHT):
		return   # no headroom
	var up_xf := xf.translated(Vector3.UP * STEP_HEIGHT)
	if test_move(up_xf, ahead):
		return   # still blocked up there: too tall to step onto
	var over := up_xf.translated(ahead)
	var land := KinematicCollision3D.new()
	if not test_move(over, Vector3.DOWN * (STEP_HEIGHT + 0.05), land):
		return   # nothing to stand on
	if land.get_normal().y < 0.7:
		# the round bottom may have caught the edge itself: check straight down for flat ground instead
		var q := PhysicsRayQueryParameters3D.create(over.origin, over.origin + Vector3.DOWN * (STEP_HEIGHT + 1.2))
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() or (hit["normal"] as Vector3).y < 0.7:
			return   # nothing flat to stand on
	var dest := over.origin + land.get_travel()
	var rise := dest.y - global_position.y
	if rise < 0.02:
		return
	global_position = dest
	velocity.x = wanted.x
	velocity.z = wanted.z
	_step_lift = maxf(_step_lift - rise, -STEP_HEIGHT)


# Slipped on ice: down for a moment (either team), then back up.
func slip() -> void:
	stunned = maxf(stunned, ICE_FALL_TIME)
	_slip_cooldown = 3.0
	velocity.x *= 0.5
	velocity.z *= 0.5
	shake(0.25)
	slipped.emit()
	print("[player] slipped on the ice")


signal slipped


func strike_down(seconds: float) -> void:
	if role != "demon":
		return
	stunned = maxf(stunned, clampf(seconds, 0.0, 1.0))
	_struck_down = true
	flying = false
	clear_dash()
	velocity = Vector3(0.0, -Skills.WORD_DROP_SPEED, 0.0)
	shake(0.35)


func scare(from: Vector3, seconds: float) -> void:
	if role != "angel":
		return
	feared = maxf(feared, clampf(seconds, 0.0, Skills.FEAR_TIME))
	_fear_from = from
	_fear_dir = Vector3.ZERO
	_fear_phase = Vector2(randf() * TAU, randf() * TAU)
	scared.emit()


func powerup_left(kind: String) -> float:
	return powerups.get(kind, 0.0)


# While invisible we see ourselves as a faint ghost (angels see nothing at all).
var _ghost_on := false


# Invisible (to the angels): we see ourselves as a faint ghost. One shared see-through material, built
# while the game starts up (see _warm_ghost), so turning invisible doesn't stall the screen while the
# graphics card builds see-through versions of every part of the model (Ted, Nov 18: 1.5 s freeze).
static var _ghost_mat: StandardMaterial3D


static func ghost_material() -> StandardMaterial3D:
	if _ghost_mat == null:
		_ghost_mat = StandardMaterial3D.new()
		_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost_mat.albedo_color = Color(0.7, 0.55, 1.0, 0.25)
	return _ghost_mat


func _warm_ghost() -> void:
	var dot := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radial_segments = 4   # (Godot's default is 64 x 32: ~4000 triangles each; Nov 26 audit)
	s.rings = 2
	s.radius = 0.01
	s.height = 0.02
	dot.mesh = s
	dot.material_override = ghost_material()
	camera.add_child(dot)
	dot.position = Vector3(0, 0, -0.5)
	for i in 3:
		await get_tree().process_frame
	dot.queue_free()


func _ghostly(on: bool) -> void:
	if on == _ghost_on:
		return
	_ghost_on = on
	for n in visual_root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if on:
			g.set_meta("own_material", g.material_override)
			g.material_override = ghost_material()
		elif g.has_meta("own_material"):
			g.material_override = g.get_meta("own_material")
			g.remove_meta("own_material")


func _tick_powerups(delta: float) -> void:
	for k in powerups.keys():
		powerups[k] -= delta
		if powerups[k] <= 0.0:
			powerups.erase(k)
			if k == "sense":
				sense_alarm = false
	throw_regen_multiplier = 6.0 if powerup_left("quick_throw") > 0.0 else 1.0
	hatred_regen_multiplier = PowerUps.FAST_HATRED_MULT if powerup_left("fast_hatred") > 0.0 else 1.0
	if powerup_left("quick_run") > 0.0:
		sprint_stamina = SPRINT_MAX
		_sprint_exhausted = false


func _update_sprint(delta: float, wants_to_run: bool) -> void:
	if _sprint_exhausted and sprint_stamina >= SPRINT_RESTART:
		_sprint_exhausted = false
	running = wants_to_run and not _sprint_exhausted and sprint_stamina > 0.0
	if running:
		sprint_stamina = maxf(sprint_stamina - SPRINT_DRAIN * delta, 0.0)
		_sprint_regen_wait = SPRINT_REGEN_DELAY
		if sprint_stamina <= 0.0:
			_sprint_exhausted = true
	elif _sprint_regen_wait > 0.0:
		_sprint_regen_wait -= delta
	else:
		sprint_stamina = minf(sprint_stamina + SPRINT_REGEN * GameRules.f("stamina") * delta, SPRINT_MAX)


func _update_throw_stamina(delta: float) -> void:
	if _throw_regen_wait > 0.0:
		_throw_regen_wait -= delta
	elif burning <= 0.0:   # no refilling while standing in demon fire
		throw_stamina = minf(throw_stamina + THROW_REGEN * throw_regen_multiplier * GameRules.f("stamina") * delta, THROW_STAMINA_MAX)


# Subtle first-person bob while moving, plus a small dip when landing.
func _update_head_bob(delta: float, ground_speed: float) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor and _fall_speed > 2.0:
		_land_dip = -minf(_fall_speed * 0.02, 0.15)
		_squash = minf(_fall_speed * 0.025, 0.3) * tuning["camera_kick"]
	if on_floor:
		_fall_speed = 0.0
	_was_on_floor = on_floor
	_land_dip = lerpf(_land_dip, 0.0, minf(delta * 10.0, 1.0))

	var amount: float = tuning["head_bob"]
	var target := 0.0
	if on_floor and ground_speed > 0.5 and amount > 0.0:
		_bob_phase += delta * ground_speed * 1.7   # step rate follows speed
		target = sin(_bob_phase * 2.0) * 0.035 * amount * clampf(ground_speed / 6.0, 0.4, 1.6)
	_bob_offset = lerpf(_bob_offset, target, minf(delta * 12.0, 1.0))
	# Bob only in first person; in third person it just looks like a shaky camera.
	spring.position.y = (_bob_offset + _land_dip) if first_person[role] else 0.0


# Shake the camera (a stomp or a blast nearby, getting hit). Strongest wins.
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


# Feel without changing movement: the view widens a touch when you run or dash and
# leans into strafes, your own body squashes when you land, the third-person camera
# glides over steps instead of jolting, and shakes die away.
func _update_camera_juice(delta: float, input_dir: Vector2) -> void:
	var kick: float = tuning["camera_kick"]
	var fov_target := BASE_FOV
	if _dash_time > 0.0:
		fov_target += 14.0 * kick
	elif running:
		fov_target += 6.0 * kick
	if _leaping or _stomping:
		fov_target += 8.0 * kick
	camera.fov = lerpf(camera.fov, fov_target, minf(delta * 8.0, 1.0))
	var lean := -input_dir.x * deg_to_rad(1.6) * kick if first_person[role] and is_on_floor() else 0.0
	_roll = lerpf(_roll, lean, minf(delta * 6.0, 1.0))
	camera.rotation.z = _roll
	# Squash and stretch: flatten on landing, spring back with a little overshoot.
	_squash = lerpf(_squash, 0.0, minf(delta * 9.0, 1.0))
	var sq := 1.0 - _squash
	visual_root.scale = Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq))
	# Third person: the camera's height lags a little behind sudden small changes.
	if not first_person[role]:
		var y := global_position.y
		_cam_y = y if absf(_cam_y - y) > 1.5 else lerpf(_cam_y, y, minf(delta * 12.0, 1.0))
		spring.position.y = clampf(_cam_y - y, -0.5, 0.5)
	else:
		_cam_y = global_position.y
	# Shake: random jitter that fades.
	if _shake > 0.001:
		camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.15
		camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.15
		_shake = lerpf(_shake, 0.0, minf(delta * 7.0, 1.0))
	else:
		_shake = 0.0
		camera.h_offset = 0.0
		camera.v_offset = 0.0


# Outline the prop under the crosshair so you know exactly what you'll become.
func _set_hover(prop: Node3D) -> void:
	if prop == _hover_prop and is_instance_valid(prop):
		return
	if is_instance_valid(_hover_prop):
		_apply_outline(_hover_prop, null)
	_hover_prop = prop
	if prop:
		if _outline_mat == null:
			_outline_mat = StandardMaterial3D.new()
			_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT   # only the "shell" shows
			_outline_mat.grow = true
			_outline_mat.grow_amount = 0.04
			_outline_mat.albedo_color = OUTLINE_COLOR
		_apply_outline(prop, _outline_mat)


func _apply_outline(node: Node, material: Material) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			child.material_overlay = material
		_apply_outline(child, material)


# Ray straight out of the camera (the crosshair), ignoring ourselves.
func _aim_ray(reach: float, also_skip: Array = []) -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * reach
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)   # world only, not the invisible map bounds
	var skip := [get_rid()]
	for n in also_skip:
		skip.append(n.get_rid())
	query.exclude = skip
	return get_world_3d().direct_space_state.intersect_ray(query)


# Left click: TRANSFORM into a copy of the prop you're aiming at (the original stays).
func try_transform() -> bool:
	var hit := _aim_ray(spring.spring_length + POSSESS_REACH)
	if hit.is_empty() or not hit["collider"].is_in_group("prop"):
		return false
	force_possess(hit["collider"].get_meta("prop_type"))
	return true


func _leave_possessed() -> void:
	if possessed_index >= 0:
		possessed_index = -1
		released_possessed.emit()


# Become a copy of this prop type (named before possess/transform were split).
func force_possess(type_name: String) -> void:
	if fuse_lit:
		return   # (the fuse is lit: you're going up with it)
	if not _make_room(PropLib.make_shape(type_name), PropLib.height(type_name), false):
		no_room.emit()
		return
	_leave_possessed()
	possessed_type = type_name
	_apply_form()
	Effects.puff(get_parent(), global_position + Vector3.UP * 0.5, Color(0.8, 0.1, 0.1, 0.8))
	form_changed.emit()


func unpossess() -> void:
	if possessed_type == "" or fuse_lit:
		return
	if not _make_room(Bodies.make_shape(role), Bodies.height_for(role)):
		no_room.emit()
		return
	_leave_possessed()
	possessed_type = ""
	_apply_form()
	Effects.puff(get_parent(), global_position + Vector3.UP * 0.8, Color(0.8, 0.1, 0.1, 0.8))
	form_changed.emit()


# Room to change shape right here? (Playtest, Nov 26: an apple under a table changed back into a demon and
# was stuck inside the table.) The new shape, standing where we are, mustn't overlap anything solid. It's
# lifted a few cm so the floor we stand on doesn't count; other players don't count, but furniture does.
const FIT_LIFT := 0.05


# props_block: false when copying a prop (we're standing right beside the one we copied, and a copy
# brushing against furniture just gets nudged aside), true when growing back into a demon.
# Room here, or a step away (up to NUDGE m, with a clear line to it so never through a wall)? Moves us there.
const NUDGE := 0.5


func _make_room(shape: Shape3D, height: float, props_block := true) -> bool:
	if _fits(shape, height, props_block, global_position):
		return true
	var space := get_world_3d().direct_space_state
	for d: float in [0.15, 0.3, NUDGE]:
		for k in 8:
			var a := TAU * k / 8.0
			var to := global_position + Vector3(cos(a), 0.0, sin(a)) * d
			if not _fits(shape, height, props_block, to):
				continue
			var mid := Vector3.UP * minf(height * 0.5, 0.5)
			var ray := PhysicsRayQueryParameters3D.create(global_position + mid, to + mid + (to - global_position).normalized() * 0.3, collision_mask, [get_rid()])
			if not space.intersect_ray(ray).is_empty():
				continue
			global_position = to
			return true
	return false


func _fits(shape: Shape3D, height: float, props_block := true, at := Vector3.ZERO) -> bool:
	if not is_inside_tree():
		return true
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(global_transform.basis, at + Vector3.UP * (height / 2.0 + FIT_LIFT))
	q.collision_mask = collision_mask
	q.exclude = [get_rid()]
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 8):
		var c: Object = hit.get("collider")
		if c is CharacterBody3D or not c is PhysicsBody3D:
			continue   # other players (and disguised demons) get pushed aside, not in the way
		if c.is_in_group("prop") and not props_block:
			continue
		if possessed_index >= 0 and c.get_meta("prop_index", -1) == possessed_index:
			continue   # the prop we're possessing (we're standing inside it on purpose)
		return false
	return true


func confirm_hit() -> void:
	hit_confirmed.emit()


# Called by a projectile that hit us. Only the host's projectiles are real, so this
# only ever runs on the host. Returns whether the hit counted (only demons get hurt).
func take_hit(damage: int, by: Node = null) -> bool:
	if role != "demon" or net_mode == "":
		return false
	hit_taken.emit(damage, by)
	return true


# 1 = a random taunt (never the signature), 2 = your signature taunt.
func taunt(signature: bool) -> bool:
	if _taunt_cooldown > 0.0:
		return false
	var taunt_name: String = Taunts.signature(role) if signature else Taunts.pick_random(role, last_taunt)
	if not signature:
		last_taunt = taunt_name
	voice.stream = Taunts.stream(taunt_name)
	voice.pitch_scale = randf_range(0.96, 1.04)
	voice.play()
	_taunt_cooldown = TAUNT_COOLDOWN
	taunted.emit(taunt_name)
	return true


# The host made us taunt (we sat still too long as a demon). The host tells everyone else.
func forced_taunt(taunt_name: String) -> void:
	last_taunt = taunt_name
	voice.stream = Taunts.stream(taunt_name)
	voice.pitch_scale = randf_range(0.96, 1.04)
	voice.play()
	_taunt_cooldown = TAUNT_COOLDOWN


# Throw if the cooldown is done and there's enough blessing stamina.
var throw_seq := 0               # numbers our throws so the host can match up hit claims
var on_claim: Callable           # set by the network code for joined players


func hold_throw_every() -> float:
	return QUICK_HOLD_THROW_EVERY if powerup_left("quick_throw") > 0.0 else HOLD_THROW_EVERY


# E as a disguised demon: the prop does its thing (prop_anims.gd), here straight away; main passes it on.
var anim_presses := 0
var fuse_lit := false     # (an explosive's fuse is burning: no going back)
var _anim_cd := 0.0


func try_animate() -> bool:
	if role != "demon" or possessed_type == "" or not PropAnims.can_animate(possessed_type) or _anim_cd > 0.0 or fuse_lit:
		return false
	_anim_cd = PropAnims.COOLDOWN
	anim_presses += 1
	fuse_lit = PropAnims.is_explosive(possessed_type)
	if visual_root.get_child_count() > 0:
		PropAnims.press(visual_root.get_child(visual_root.get_child_count() - 1), possessed_type, anim_presses)
	animate_pressed.emit(anim_presses)
	return true


# Caught in an explosive prop's blast: stunned stiff for a moment (either team), no throwing.
func daze(seconds: float) -> void:
	stunned = maxf(stunned, clampf(seconds, 0.0, 3.0))
	shake(0.6)
	print("[player] dazed by an explosion")


func try_throw() -> bool:
	if stunned > 0.0:
		return false
	if _throw_cooldown > 0.0 or throw_stamina < THROW_COST:
		return false
	_throw_strength = clampf(throw_stamina / (THROW_STAMINA_MAX * WEAK_THROW_BELOW), 0.0, 1.0)
	throw_stamina -= THROW_COST
	_throw_regen_wait = THROW_REGEN_DELAY
	_shoot()
	return true


func _shoot() -> void:
	var p := Projectile.new()
	p.color = Blessings.color(blessing)   # before add_child: its glow is built on entering the world
	p.kind = blessing
	p.visual_only = net_mode == "client"  # joined players only show throws; the host decides hits
	get_parent().add_child(p)
	var forward := -camera.global_transform.basis.z
	# In third person, start the throw at the angel's hand height, not back at the camera.
	# Either way, aim at whatever is under the crosshair.
	var start := camera.global_position + forward * 0.6
	var direction := forward
	if not first_person[role]:
		start = global_position + Vector3.UP * 1.4 + forward * 0.6
		var hit := _aim_ray(100.0)
		var aim_point: Vector3 = hit["position"] if not hit.is_empty() else camera.global_position + forward * 100.0
		direction = (aim_point - start).normalized()
	p.global_position = start
	# Running low on stamina: the throw gets weaker (slower, droops sooner).
	p.velocity = direction * PROJECTILE_SPEED * lerpf(0.35, 1.0, _throw_strength) + Vector3.UP * 0.6
	p.gravity = lerpf(16.0, PROJECTILE_GRAVITY, _throw_strength)
	p.shooter = self
	throw_seq += 1
	if p.visual_only and on_claim.is_valid():
		var seq := throw_seq
		p.on_claim = func(eid, point): on_claim.call(seq, eid, point)
	_throw_cooldown = THROW_COOLDOWN
	_since_throw = 0.0
	threw.emit(blessing)
	launched.emit(start, p.velocity, blessing, p.gravity, throw_seq)
	if _rig:
		_rig.play_action("Throw", 0.45)


func _settle_view(delta: float, input_dir: Vector2) -> void:
	if role == "angel":
		# Let go of Alt: the view swings back to straight ahead.
		if not Input.is_action_pressed("free_look") and pivot.rotation.y != 0.0:
			pivot.rotation.y = lerp_angle(pivot.rotation.y, 0.0, minf(12.0 * delta, 1.0))
			if absf(pivot.rotation.y) < 0.002:
				pivot.rotation.y = 0.0
	elif possessed_type == "" and input_dir != Vector2.ZERO and not frozen:
		# A demon in its own body turns to face where it's walking; the camera stays put.
		var walk := move_basis() * Vector3(input_dir.x, 0.0, input_dir.y)
		var face := atan2(-walk.x, -walk.z)
		var new_yaw := lerp_angle(rotation.y, face, minf(10.0 * delta, 1.0))
		pivot.rotation.y = wrapf(pivot.rotation.y - wrapf(new_yaw - rotation.y, -PI, PI), -PI, PI)
		rotation.y = new_yaw


# Holding the Minion key: it walks to the ground under the crosshair.
func _steer_minion() -> void:
	if not is_instance_valid(minion):
		return
	var held: bool = _hold_key_down("minion") if test_input.is_empty() else test_input.get("minion", false)
	if held and not frozen:
		var hit := _aim_ray(80.0, [minion])   # (looking right at it still steers past it)
		if not hit.is_empty():
			minion.steering = true
			minion.walk_to(hit["position"])
	elif minion.steering:
		minion.stop()


# No standing on other players' heads (angels, or demons in their own body), or on
# a cherub: you slide right off. Standing on a demon disguised as a prop is fine,
# that's just a prop.
func _slide_off_heads() -> void:
	_unpin()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other == null:
			continue
		# Someone (or a cherub) on OUR head: we don't feel them, so we can walk out
		# from under (they drop off on their own screen once we're gone).
		if col.get_normal().y < -0.5 and _is_someone(other):
			add_collision_exception_with(other)
			_pinned_by[other] = true
			continue
		if col.get_normal().y < 0.6:
			continue
		var on_body: bool = (other.get("eid") != null or other.get("life") != null) and other.get("form") == ""
		if on_body or other.get("cherub_id") != null:
			var away := Vector3(global_position.x - other.global_position.x, 0.0, global_position.z - other.global_position.z)
			if away.length() < 0.05:
				away = -global_transform.basis.z
			away = away.normalized()
			velocity.x = away.x * 4.0
			velocity.z = away.z * 4.0
			velocity.y = minf(velocity.y, -1.0)
			global_position += away * 0.06
			return


var _pinned_by := {}   # bodies we're letting pass through because they were on our head


func _is_someone(n: Object) -> bool:
	return n.get("eid") != null or n.get("life") != null or n.get("cherub_id") != null


# Once whoever was on our head is clear of us, we can bump into them again.
func _unpin() -> void:
	for n in _pinned_by.keys():
		if not is_instance_valid(n):
			_pinned_by.erase(n)
			continue
		var off: Vector3 = n.global_position - global_position
		if Vector2(off.x, off.z).length() > 1.4 or off.y > 3.0 or off.y < -1.0:
			remove_collision_exception_with(n)
			_pinned_by.erase(n)


signal hatred_bonus(amount, reason)


# The host (or practice game) says we were naughty: have some Hatred.
func add_hatred(amount: float, reason: String) -> void:
	if role != "demon":
		return
	hatred = clampf(hatred + amount, 0.0, HATRED_MAX)
	hatred_bonus.emit(amount, reason)


# Which way our body or prop faces, as everyone else should see it.
func shown_yaw() -> float:
	return rotation.y + visual_root.rotation.y


func cycle_blessing() -> void:
	var kinds := Blessings.names()
	blessing = kinds[(kinds.find(blessing) + 1) % kinds.size()]
