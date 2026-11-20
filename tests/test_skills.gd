# Automated test of flying, possess vs transform, and the angel tools, in practice mode.
#   godot --headless -s res://tests/test_skills.gd
extends SceneTree

const Skills = preload("res://scripts/skills.gd")
const PowerUps = preload("res://scripts/powerups.gd")
const PropLib = preload("res://scripts/prop_library.gd")

var main: Node
var failures := 0


func _initialize() -> void:
	# Same prop layout and bot spots every run, so a test never fails just
	# because a random prop happened to land in the way.
	seed(int(OS.get_environment("TEST_SEED")) if OS.get_environment("TEST_SEED") != "" else 20261114)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame


# Stand a few meters from target with a clear crosshair line to it.
func aim_at(player, target: Node3D, aim_height: float, dist := 3.5) -> bool:
	var aim_point := target.global_position + Vector3.UP * aim_height
	for i in 16:
		var angle := TAU * i / 16.0
		var spot := target.global_position + Vector3(cos(angle), 0, sin(angle)) * dist
		if main.ground_below(spot + Vector3.UP * 3.0).y > target.global_position.y + 0.3:
			continue   # that spot is inside a building or on top of something
		player.global_position = spot + Vector3.UP * 0.1
		player.velocity = Vector3.ZERO
		player.look_at(Vector3(aim_point.x, player.global_position.y, aim_point.z))
		player.pivot.rotation.y = 0.0
		await frames(2)
		for pass_num in 4:
			var eye: Vector3 = player.camera.global_position
			var flat := Vector2(aim_point.x - eye.x, aim_point.z - eye.z).length()
			player.pivot.rotation.x = clampf(atan2(aim_point.y - eye.y, flat), -1.4, 1.2)
			await frames(1)
		var hit: Dictionary = player._aim_ray(20.0)
		if not hit.is_empty() and hit["collider"] == target:
			return true
	return false


# Stand still in the open, facing -z, ready to dash.
# With up_high, floating well above the props and roofs (the test switches gravity off).
func dash_setup(player, up_high := false) -> void:
	player.test_input = {}
	player.global_position = Vector3(8, 14.0 if up_high else 0.1, 18)
	player.rotation = Vector3.ZERO
	player.pivot.rotation.x = 0.0
	player.velocity = Vector3.ZERO
	player.clear_dash()
	player.skill_cd.clear()
	await frames(5)


# A spot near `want` with open ground and no prop within 4 m (props are random each round).
func clear_spot(want: Vector3) -> Vector3:
	for r in range(0, 20, 2):
		for i in 12:
			var a := TAU * i / 12.0
			var p := want + Vector3(cos(a), 0, sin(a)) * r
			if absf(p.x) > 24 or absf(p.z) > 24 or main.ground_below(p + Vector3.UP * 4.0).y > 0.2:
				continue
			var ok := true
			for prop in main.props:
				if is_instance_valid(prop) and prop.visible and prop.global_position.distance_to(p) < 4.0:
					ok = false
			if ok:
				return Vector3(p.x, 0.1, p.z)
	return want


# A spot near `want` from which the next `length` metres in direction `dir` are open
# ground with no prop or building in the way (for testing throws).
func clear_lane(want: Vector3, dir: Vector3, length: float) -> Vector3:
	for r in range(0, 30, 2):
		for i in 12:
			var a := TAU * i / 12.0
			var start := want + Vector3(cos(a), 0, sin(a)) * r
			var ok := true
			for k in range(0, int(length) + 1):
				var p := start + dir * k
				if absf(p.x) > 26 or absf(p.z) > 26 or main.ground_below(p + Vector3.UP * 5.0).y > 0.2:
					ok = false
					break
				for prop in main.props:
					if is_instance_valid(prop) and prop.visible and Vector2(prop.global_position.x - p.x, prop.global_position.z - p.z).length() < 1.8:
						ok = false
				if not ok:
					break
			if ok:
				return Vector3(start.x, 0.1, start.z)
	return want


func visible_props() -> Array:
	var out := []
	for p in main.props:
		if is_instance_valid(p) and p.is_in_group("prop"):
			out.append(p)
	return out


func _run() -> void:
	await frames(5)
	main.role = "demon"
	main.start_practice()
	await frames(5)
	var player = main.player
	player.rotation = Vector3.ZERO

	# ---- Flying (a demon skill: hold its key to rise, let go to fall) ----
	player.loadout["demon"] = ["possess", "fly"]
	player.global_position = Vector3(0, 0.1, 20)
	player.hatred = player.HATRED_MAX
	await frames(5)
	player.test_input = {"fly": true}
	await frames(60)
	check(player.flying and player.global_position.y > 3.0, "holding the Fly key rises (y %.1f)" % player.global_position.y)
	player.test_input = {"fly": true, "dir": Vector2(1, 0)}
	var x_before: float = player.global_position.x
	await frames(30)
	check(player.global_position.x > x_before + 1.5, "WASD steers while flying")
	player.test_input = {}
	var y_top: float = player.global_position.y
	await frames(150)   # coasts upward first (it was rising fast), like the top of a jump
	check(player.global_position.y < y_top - 0.3, "letting go: gravity takes you down (%.1f -> %.1f, flying %s)" % [y_top, player.global_position.y, player.flying])
	await frames(90)
	check(player.is_on_floor(), "...all the way to the ground (no fall damage either)")

	player.hatred = player.HATRED_MAX
	var seconds := 0.0
	player.test_input = {"fly": true}
	while seconds < 1.0 or (player.flying and seconds < 15.0):
		await frames(6)
		seconds += 0.1
	check(seconds > 5.0 and seconds < 8.5, "a full Hatred bar gives 5-8 s of flight (%.1f s)" % seconds)
	await frames(30)
	check(not player.flying, "out of Hatred: no more lift")
	player.test_input = {}
	await frames(240)

	player.hatred = player.HATRED_MAX
	player.apply_powerup("fast_hatred")     # the Hatred Surge power-up (4x regen for 15 s)
	player.test_input = {"fly": true}
	await frames(600)
	check(player.flying, "with a Hatred Surge you fly far longer (10 s and counting)")
	player.powerups.clear()
	player.test_input = {}
	await frames(300)

	player.hatred = player.HATRED_MAX
	player.skill_lock = 2.0
	player.test_input = {"fly": true}
	await frames(20)
	check(not player.flying, "can't fly during a vacuum lockout")
	player.skill_lock = 0.0
	player.test_input = {}
	await frames(30)

	player.loadout["demon"] = ["possess", ""]
	player.test_input = {"fly": true}
	await frames(20)
	check(not player.flying, "no Fly skill picked: no flying")
	player.loadout["demon"] = ["possess", "fly"]
	player.test_input = {}

	player.force_possess("hay")
	await frames(2)
	player.hatred = player.HATRED_MAX
	player.test_input = {"fly": true}
	await frames(40)
	check(player.flying and player.global_position.y > 1.5, "props can fly (a flying hay bale)")
	player.test_input = {}
	await frames(120)

	# Catching yourself mid-fall with Fly is quick.
	player.hatred = player.HATRED_MAX
	player.global_position = Vector3(0, 15, 20)
	player.velocity = Vector3(0, -10, 0)
	player.test_input = {"fly": true}
	await frames(18)
	check(player.velocity.y > 0.0, "Fly stops a fall in under a third of a second (%.1f m/s)" % player.velocity.y)
	player.test_input = {}
	await frames(150)

	# Nobody stands on a cherub's (or anyone's) head.
	var perch = load("res://scripts/cherub.gd").new()
	main.round_root.add_child(perch)
	var perch_at: Vector3 = clear_spot(Vector3(10, 0.1, 18))
	perch.launch(perch_at + Vector3.UP * 0.05, Vector3.ZERO)
	await frames(20)
	player.global_position = perch.global_position + Vector3.UP * 1.3
	player.velocity = Vector3.ZERO
	await frames(60)
	var off_by := Vector2(player.global_position.x - perch.global_position.x, player.global_position.z - perch.global_position.z).length()
	check(player.global_position.y < 0.5 and off_by > 0.4, "landing on a cherub, you slide off (%.1f m away, y %.1f)" % [off_by, player.global_position.y])
	perch.queue_free()

	check(PropLib.TYPES.has("apple") and PropLib.TYPES.has("pickle") and PropLib.max_hp("apple") < PropLib.max_hp("books"),
			"there's a tiny apple and a big floppy pickle to hide as")

	# ---- Per-form health and speed ----
	check(PropLib.max_hp("books") < PropLib.max_hp("") and PropLib.max_hp("") < PropLib.max_hp("hay"),
			"small props have less health than a demon, big ones more")
	var form_speeds := {}
	for form in ["books", "", "hay"]:
		if form == "":
			player.unpossess()
		else:
			player.force_possess(form)
		player.global_position = clear_spot(Vector3(-20, 0.1, 20))
		player.velocity = Vector3.ZERO
		player.rotation = Vector3.ZERO
		await frames(5)
		player.test_input = {"dir": Vector2(1, 0)}
		await frames(30)
		form_speeds[form] = Vector2(player.velocity.x, player.velocity.z).length()
		player.test_input = {}
	check(form_speeds["books"] > form_speeds[""] and form_speeds[""] > form_speeds["hay"],
			"books run faster than a demon, hay bales slower (%.1f / %.1f / %.1f)" % [form_speeds["books"], form_speeds[""], form_speeds["hay"]])
	player.unpossess()
	await frames(5)

	# ---- Transform vs possess ----
	var props_before := visible_props().size()
	var first: Node3D = null
	for p in visible_props():
		if await aim_at(player, p, 0.2):
			first = p
			break
	check(first != null, "lined up on a prop")
	player.try_transform()
	await frames(2)
	check(player.possessed_type == first.get_meta("prop_type") and player.possessed_index == -1,
			"left click transforms into a copy")
	check(visible_props().size() == props_before and first.visible, "the original stays put when transforming")
	player.unpossess()
	await frames(5)

	player.loadout["demon"] = ["possess", ""]
	check(await aim_at(player, first, 0.2), "lined up again")
	await frames(2)
	check(player.use_skill(0), "Q possesses the prop under the crosshair")
	await frames(2)
	check(player.possessed_index == first.get_meta("prop_index"), "we ARE that prop now")
	check(not first.visible and not first.is_in_group("prop"), "the original is gone (we took its place)")
	check(player.global_position.distance_to(first.global_position) < 0.05, "we moved exactly to where it stood")
	check(visible_props().size() == props_before - 1, "possessing doesn't add a duplicate prop")
	await frames(25)   # let the camera finish gliding over

	var second: Node3D = null
	var others := visible_props()
	others.sort_custom(func(a, b): return a.global_position.distance_to(first.global_position) < b.global_position.distance_to(first.global_position))
	for p in others:
		if await aim_at(player, p, 0.2, 3.0):
			second = p
			break
	check(second != null, "found a second prop to hop into")
	if second:
		player.skill_cd.clear()
		player.global_position = first.global_position
		await frames(25)
		await aim_at(player, second, 0.2, 3.0)
		await frames(2)
		var left_at: Vector3 = player.global_position
		player.use_skill(0)
		await frames(2)
		check(player.possessed_index == second.get_meta("prop_index"), "hopped into the second prop")
		check(first.visible and not first.is_in_group("prop"), "the first prop was left behind")
		check(first.global_position.distance_to(left_at) < 0.05, "...exactly where we left it")
		await frames(120)
		var mi: MeshInstance3D = first.get_child(0).get_child(0)
		check(mi.material_override.albedo_color.a < 0.9, "...and it's slowly dissolving")
		await frames(300)
		check(not is_instance_valid(first), "...until it's gone")
	player.unpossess()
	await frames(5)
	check(second == null or (is_instance_valid(second) and second.visible), "leaving a possessed prop leaves it behind too")
	var walk_from: Vector3 = player.global_position
	player.test_input = {"dir": Vector2(0, -1)}
	await frames(30)
	player.test_input = {}
	var walked := Vector2(player.global_position.x - walk_from.x, player.global_position.z - walk_from.z).length()
	check(walked > 1.0, "you can walk away right away, not stuck inside the prop you left (%.1f m)" % walked)

	# ---- Angel tools vs the test demons ----
	main.role = "angel"
	main.start_round()
	main.time_left = 0.0
	await frames(5)
	player.loadout["angel"] = ["cherub", "vacuum"]
	var bot = get_nodes_in_group("demon")[0]

	# Cherub: thrown from the angel, it flies off and lands a good way away.
	player.global_position = clear_lane(Vector3(-20, 0.1, -10), Vector3(0, 0, -1), 18.0)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	await frames(5)
	var throw_from: Vector3 = player.global_position
	main.authority_skill(player, 0, "cherub", player.camera.global_position, Vector3.FORWARD, Vector3.ZERO, -1)
	await frames(150)
	var thrown = main.cherubs.get(1)
	var flew: float = throw_from.z - thrown.global_position.z if thrown else 0.0
	check(thrown != null and flew > 6.0 and flew < 20.0, "a cherub is thrown from the angel and lands a ways off (%.1f m)" % flew)
	check(thrown != null and thrown.is_on_floor() and (thrown.velocity.length() < 0.3 or thrown.alarmed), "...and settles where it lands")
	# Near a demon it alarms, far away it doesn't (placed by hand for the test).
	main.authority_skill(player, 0, "cherub", player.camera.global_position, Vector3.FORWARD, Vector3.ZERO, -1)
	main.authority_skill(player, 0, "cherub", player.camera.global_position, Vector3.FORWARD, Vector3.ZERO, -1)
	await frames(2)
	var near_c = main.cherubs.get(2)
	var far_c = main.cherubs.get(3)
	near_c.launch(bot.global_position + Vector3(2, 0.2, 0), Vector3.ZERO)
	far_c.launch(Vector3(0, 0.2, -26), Vector3.ZERO)
	await frames(30)
	check(near_c != null and near_c.alarmed, "a cherub near a hidden demon squawks")
	check(far_c != null and not far_c.alarmed, "a cherub with no demon nearby stays calm")
	check(near_c != null and near_c._bubble.visible, "...and shows its detection bubble")
	check(far_c != null and not far_c._bubble.visible, "...a calm cherub shows no bubble, it's just a cherub")

	var creep_from: Vector3 = near_c.global_position if near_c != null else Vector3.ZERO
	var creep_gap: float = creep_from.distance_to(bot.global_position)

	# Knock the calm cherub down the "hallway" with a blessing.
	if far_c != null:
		var c_start: Vector3 = far_c.global_position
		var shot = preload("res://scripts/projectile.gd").new()
		shot.velocity = Vector3(30, 0, 0)
		shot.shooter = player
		main.add_child(shot)
		shot.global_position = c_start + Vector3(-3, 0.4, 0)
		await frames(150)
		var moved: float = far_c.global_position.x - c_start.x
		check(moved > 3.0, "a blessing sends the cherub skidding (%.1f m)" % moved)
		check(absf(far_c.velocity.x) < 0.3, "...and it slides to a stop")
		check(main._auth_cherubs.has(3) and main._auth_cherubs[3]["pos"].distance_to(far_c.global_position) < 0.5,
				"...and it keeps watching from where it landed")

	# Meanwhile the alarmed one has been creeping toward its demon, very slowly.
	if near_c != null and is_instance_valid(near_c):
		var crept: float = near_c.global_position.distance_to(creep_from)
		var gap: float = near_c.global_position.distance_to(bot.global_position)
		check(gap < creep_gap - 0.2, "an alarmed cherub creeps toward the demon (%.1f m -> %.1f m away)" % [creep_gap, gap])
		check(crept < 1.6, "...very slowly (%.2f m in 2.5 s)" % crept)
		check(far_c != null and (far_c.alarmed or far_c.creep == Vector3.ZERO), "...and a calm one stays put")

	# Vacuum: pulls nearby props in and yanks the demon.
	var center: Vector3 = bot.global_position + Vector3(3, 0, 0)
	var near_props := []
	for p in visible_props():
		var d := Vector2(p.global_position.x - center.x, p.global_position.z - center.z).length()
		if d < Skills.VACUUM_RADIUS and d > 1.5:
			near_props.append([p, d])
	var bot_dist_before: float = bot.global_position.distance_to(center)
	main._vacuum_at(center)
	await frames(90)
	check(bot.global_position.distance_to(center) < bot_dist_before - 1.0, "the vacuum yanks the demon toward its center")
	var pulled := true
	for pd in near_props:
		var d2 := Vector2(pd[0].global_position.x - center.x, pd[0].global_position.z - center.z).length()
		if d2 > pd[1] - 0.3:
			pulled = false
	check(pulled, "the vacuum drags nearby props in too (%d props)" % near_props.size())

	# Melee: three hits catch a full-health test demon.
	var bot2 = get_nodes_in_group("demon")[1]
	check(await aim_at(player, bot2, 0.3, 1.8), "standing next to a demon")
	var all_before := 0
	for b in get_nodes_in_group("demon"):
		all_before += b.health
	player.melee_cd = 0.0
	player.melee()
	await frames(2)
	var all_after := 0
	for b in get_nodes_in_group("demon"):
		all_after += b.health
	# (The vacuum just bunched demons up: it hits whichever is nearest in front.)
	check(all_before - all_after == Skills.MELEE_DAMAGE, "F melee hits a demon (%d damage)" % (all_before - all_after))

	# Flying Dash: a burst in any direction that leaves momentum behind.
	player.loadout["angel"] = ["dash", "leap"]
	# Up in the air with gravity off, so no prop or wall gets in the way.
	var saved: Dictionary = player.tuning.duplicate()
	player.tuning["gravity_scale"] = 0.0
	player.tuning["dash_air_drag"] = 9.0
	await dash_setup(player, true)
	check(player.use_skill(0), "Flying Dash")
	check(not player.use_skill(0), "...which then has a cooldown")
	await frames(20)
	var burst: float = 18.0 - player.global_position.z
	check(burst > 3.5 and absf(player.global_position.x - 8.0) < 0.3, "dashed straight ahead (%.1f m)" % burst)
	var gave: float = player.dash_momentum()
	check(gave > 10.0, "...and kept momentum afterwards (%.1f m/s)" % gave)
	var z_then: float = player.global_position.z
	await frames(20)
	check(player.global_position.z < z_then - 1.5, "the momentum carries you on with no keys held")
	check(player.dash_momentum() > 5.0, "...for a while")
	check(player.dash_momentum() < gave, "...fading as you slide (%.1f m/s)" % player.dash_momentum())
	await frames(150)
	check(player.dash_momentum() == 0.0, "...until it's gone")

	# Turning costs momentum. (No fading here, so only the turning counts.)
	player.tuning["dash_air_drag"] = 0.0
	await dash_setup(player, true)
	player.use_skill(0)
	await frames(20)
	gave = player.dash_momentum()
	player.rotate_y(PI)
	await frames(2)
	check(player.dash_momentum() == 0.0, "a quick 180 kills all the momentum")

	await dash_setup(player, true)
	player.use_skill(0)
	await frames(20)
	for i in 120:
		player.rotate_y(PI / 120.0)
		await frames(1)
	var kept: float = player.dash_momentum() / gave
	check(kept > 0.5 and kept < 0.8, "a wide, slow 180 keeps most of it (%d%%)" % roundi(kept * 100.0))
	var facing: Vector3 = -player.global_transform.basis.z
	check(player.velocity.normalized().dot(facing) > 0.95, "...and it follows you round the turn")

	await dash_setup(player, true)
	player.use_skill(0)
	await frames(20)
	for i in 30:
		player.rotate_y(PI / 30.0)
		await frames(1)
	var kept_fast: float = player.dash_momentum() / gave
	check(kept_fast < kept - 0.3, "the same turn made faster loses more (%d%%)" % roundi(kept_fast * 100.0))

	await dash_setup(player, true)
	player.use_skill(0)
	await frames(20)
	player.test_input = {"dir": Vector2(1, 0)}
	await frames(2)
	kept = player.dash_momentum() / gave
	check(kept > 0.4 and kept < 0.6, "strafing sideways costs half (%d%%)" % roundi(kept * 100.0))
	player.test_input = {"dir": Vector2(-1, 0)}
	await frames(2)
	check(player.dash_momentum() == 0.0, "...and strafing back the other way kills the rest")
	player.test_input = {}
	player.tuning = saved
	# On a roof (no props up there to bump into), with a short burst so we stay on it.
	player.tuning["dash_time"] = 0.1
	await dash_setup(player)
	player.global_position = Vector3(8, 4.1, 10.5)
	await frames(5)
	player.use_skill(0)
	await frames(8)
	gave = player.dash_momentum()
	await frames(10)
	player.tuning["dash_time"] = saved["dash_time"]
	check(gave > 8.0 and player.is_on_floor() and player.dash_momentum() < gave - 1.0, "on the ground the momentum fades faster (%.1f -> %.1f m/s)" % [gave, player.dash_momentum()])

	# Any direction: backwards with the back key held, or up into the air.
	await dash_setup(player)
	player.test_input = {"dir": Vector2(0, 1)}
	await frames(1)
	player.use_skill(0)
	await frames(15)
	player.test_input = {}
	check(player.global_position.z > 18.0 + 3.0, "holding back dashes backwards (%.1f m)" % (player.global_position.z - 18.0))
	await dash_setup(player)
	player.pivot.rotation.x = 1.0
	await frames(2)
	player.use_skill(0)
	var top := 0.0
	for i in 90:
		await frames(1)
		top = maxf(top, player.global_position.y)
	check(top > 5.0, "looking up dashes into the air (%.1f m up)" % top)
	player.pivot.rotation.x = 0.0
	# The invisible map walls still stop you.
	await dash_setup(player)
	player.global_position = Vector3(22, 0.1, 18)
	player.rotation.y = -PI / 2.0
	await frames(2)
	player.use_skill(0)
	player.test_input = {"dir": Vector2(0, -1)}
	await frames(90)
	player.test_input = {}
	check(player.global_position.x < 28.6, "the invisible map wall still stops a dash (x %.1f)" % player.global_position.x)
	check(player.dash_momentum() == 0.0, "...and running into it ends the momentum")
	check(Skills.clean_loadout("angel", ["grapple", "leap"]) == ["dash", "leap"], "a saved Grappling Hook pick becomes the Flying Dash")

	# Holy Leap: picked, every jump goes MUCH higher; its key on the ground does nothing.
	player.global_position = Vector3(-20, 0.1, -20)
	player.velocity = Vector3.ZERO
	await frames(20)
	player.skill_cd.clear()
	var y0: float = player.global_position.y
	check(not player.use_skill(1), "Holy Leap's key does nothing on the ground")
	player.test_input = {"jump": true}
	await frames(2)
	player.test_input = {}
	var peak := y0
	for i in 90:
		await frames(1)
		peak = maxf(peak, player.global_position.y)
	check(peak - y0 > 3.5, "a magnificent jump (%.1f m)" % (peak - y0))
	for i in 120:
		if player.is_on_floor():
			break
		await frames(1)

	# Steering a jump: holding a direction carries you that way.
	player.rotation = Vector3.ZERO
	await frames(5)
	var x0: float = player.global_position.x
	player.test_input = {"dir": Vector2(1, 0), "jump": true}
	await frames(2)
	player.test_input = {"dir": Vector2(1, 0)}
	await frames(50)
	check(player.global_position.x - x0 > 4.0, "a leap goes where you steer it (%.1f m sideways)" % (player.global_position.x - x0))
	player.test_input = {}
	await frames(60)

	# ---- Power-ups ----
	var pu = main.powerups
	pu.reset()
	main.state = main.State.HUNTING
	# A struggling angel (nobody found or hit for a while) gets one dropped nearby...
	player.global_position = clear_spot(Vector3(-12, 0.1, 18))
	player.velocity = Vector3.ZERO
	await frames(5)
	pu._last_angel_help -= pu.ANGEL_HELP_AFTER + 1.0
	await frames(15)
	var angel_items: Array = pu._auth.values().filter(func(it): return it["team"] == "angel")
	check(angel_items.size() == 1, "a struggling angel gets a power-up dropped nearby")
	if angel_items.size() == 1:
		var it_pos: Vector3 = angel_items[0]["pos"]
		check(Vector2(it_pos.x - player.global_position.x, it_pos.z - player.global_position.z).length() < 6.0, "...close by")
		player.global_position = Vector3(it_pos.x, 0.1, it_pos.z)
		await frames(20)
		check(not player.powerups.is_empty(), "...walk over it to pick it up (%s)" % ", ".join(player.powerups.keys()))
		check(pu.items.is_empty(), "...and it's gone for everyone")
	# Each effect.
	player.powerups.clear()
	player.apply_powerup("quick_run")
	player.sprint_stamina = 0.0
	await frames(3)
	check(player.sprint_stamina >= player.SPRINT_MAX - 0.1, "Endless Sprint: running stamina stays full")
	player.skill_cd["leap"] = 6.0
	player.apply_powerup("quick_skills")
	check(player.skill_cd.is_empty(), "Quick Skills: picking it up resets every cooldown to zero")
	player.skill_cd["leap"] = 6.0
	await frames(60)
	check(player.skill_cd["leap"] < 3.5, "Quick Skills: cooldowns run 3x faster (%.1f s left of 6 after 1 s)" % player.skill_cd["leap"])
	player.apply_powerup("quick_throw")
	await frames(2)
	check(player.throw_regen_multiplier > 5.0, "Quick Blessings: blessing stamina refills much faster")
	player.powerups.clear()
	await frames(2)
	main.give_powerup(0, "fire_burst", player.global_position)
	await frames(2)
	check(player.burning > 0.0, "a demon's Fire Burst sets nearby angels burning")
	await frames(2)
	check("burning" in main.effect_icons.shown(), "...and a Hellfire icon shows in the top-right corner")
	player.apply_powerup("quick_run")
	await frames(2)
	check("quick_run" in main.effect_icons.shown() and "burning" in main.effect_icons.shown(),
			"power-ups get an icon too, next to the bad ones (%s)" % [main.effect_icons.shown()])
	player.first_person[player.role] = false
	await frames(2)
	check(main.my_aura.kind == "quick_run", "in third person you see your own power-up aura")
	player.first_person[player.role] = true
	player.powerups.erase("quick_run")
	await frames(2)
	check(not "quick_run" in main.effect_icons.shown(), "...and the icon goes when it runs out")
	await frames(250)
	# Cherub Sense: walking near a demon sets off your own alarm.
	var sensed = null
	for b in get_nodes_in_group("demon"):
		if b.health > 0:
			sensed = b
	if sensed:
		player.apply_powerup("sense")
		player.global_position = sensed.global_position + Vector3(3.0, 0.1, 0.0)
		await frames(30)
		check(player.sense_alarm, "Cherub Sense: you go off like a cherub when a demon's close")
		player.global_position = Vector3(0, 0.1, 25)
		await frames(30)
		check(not player.sense_alarm, "...and quiet down away from them")
	player.powerups.clear()
	# About half the redeemed demons drop an angel power-up where they were caught, two at most lying around.
	var drops := 0
	for i in 40:
		pu.reset()
		pu.demon_caught(Vector3(5, 0, 20))
		drops += pu._auth.size()
	check(drops > 8 and drops < 32, "a redeemed demon drops an angel power-up about half the time (%d of 40)" % drops)
	pu.reset()
	for i in 12:
		pu.demon_caught(Vector3(5, 0, 20 + i))
	await frames(2)
	check(pu._auth.size() <= 2 and pu.items.size() == pu._auth.size(), "...and no more than 2 lie around (%d)" % pu._auth.size())
	# Demons' power-ups are dropped by the angels over time.
	pu.reset()
	pu._demon_timer = 0.1
	await frames(20)
	check(pu._auth.values().any(func(it): return it["team"] == "demon"), "angels drop demon power-ups as time goes by")
	pu.reset()

	# Power-ups only show for their own team.
	pu.reset()
	pu._drop("demon", "heal", Vector3(0, 0, 20))
	pu._drop("angel", "quick_run", Vector3(2, 0, 20))
	await frames(2)
	var shown_kinds: Array = pu.items.values().map(func(n): return n.get_meta("kind"))
	check(shown_kinds == ["quick_run"], "an angel only sees angel power-ups (sees %s)" % [shown_kinds])
	pu.reset()

	# Bouncies: step on one and you're flung high.
	player.global_position = main.BOUNCIES[0] + Vector3(0, 0.1, -2.0)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.pivot.rotation = Vector3.ZERO
	await frames(10)
	player.test_input = {"dir": Vector2(0, 1)}    # walk onto it
	var peak_b := 0.0
	for k in 90:
		await frames(1)
		peak_b = maxf(peak_b, player.global_position.y)
		if peak_b > 1.0:
			player.test_input = {}
	player.test_input = {}
	check(peak_b > 6.0, "a bouncy flings you way up (%.1f m)" % peak_b)
	await frames(60)
	player.global_position = Vector3(0, 0.1, 18)   # (out of the way)
	await frames(5)
	# A cherub dropped onto a bouncy goes flying up and off it.
	var pad: Vector3 = main.BOUNCIES[0]
	main._auth_cherubs[99] = {"pos": pad, "until": Time.get_ticks_msec() / 1000.0 + 9.0, "alarmed": false, "rested": false}
	main.fx("cherub", [99, pad + Vector3(0.2, 2.5, 0), Vector3.ZERO])
	var pc = main.cherubs.get(99)
	var pc_peak := 0.0
	for k in 150:
		await frames(1)
		if is_instance_valid(pc):
			pc_peak = maxf(pc_peak, pc.global_position.y - pad.y)
	var pc_off := 0.0
	if is_instance_valid(pc):
		pc_off = Vector2(pc.global_position.x - pad.x, pc.global_position.z - pad.z).length()
	check(pc_peak > 4.0, "a cherub that lands on a bouncy is flung up (%.1f m)" % pc_peak)
	check(pc_off > 2.0, "...and off the pad, not bouncing in place forever (%.1f m away)" % pc_off)
	if is_instance_valid(pc):
		pc.queue_free()
	main._auth_cherubs.erase(99)
	# A Vacuum Orb that hits a bouncy bounces off and goes off somewhere else.
	var orb_hits := []
	var orb_from: Vector3 = pad + Vector3(-3.0, 3.0, 0.0)
	var orb_dir: Vector3 = (pad + Vector3(0, 0.25, 0) - orb_from).normalized()
	var orb = main._spawn_orb(orb_from - orb_dir * 0.6, orb_dir, false)
	orb.on_impact = func(p): orb_hits.append(p)
	var orb_peak := 0.0
	for k in 360:
		await frames(1)
		if is_instance_valid(orb):
			orb_peak = maxf(orb_peak, orb.global_position.y - pad.y)
		if not orb_hits.is_empty():
			break
	check(orb_peak > 4.0, "a Vacuum Orb that hits a bouncy flies back up (%.1f m)" % orb_peak)
	var orb_off := -1.0
	if not orb_hits.is_empty():
		orb_off = Vector2(orb_hits[0].x - pad.x, orb_hits[0].z - pad.z).length()
	check(orb_off > 1.5, "...and the vacuum goes off where it comes down, not on the pad (%.1f m away)" % orb_off)
	# Ordinary blessings still just pop on a bouncy.
	var plain_hit := []
	var plain = preload("res://scripts/projectile.gd").new()
	plain.on_impact = func(p): plain_hit.append(p)
	main.add_child(plain)
	plain.global_position = pad + Vector3(0, 2.0, 0)
	plain.velocity = Vector3(0, -20, 0)
	await frames(30)
	check(plain_hit.size() == 1 and plain_hit[0].distance_to(pad) < 0.6, "...ordinary blessings don't bounce")
	# One-use bouncies: the first bounce uses it up for the round.
	var one: Node3D = main.bouncies.get(0)
	check(one != null, "one-use bouncies are out each round")
	if one:
		player.global_position = one.global_position + Vector3(0, 0.6, 0)
		player.velocity = Vector3.ZERO
		await frames(10)
		check(player.velocity.y > 3.0 or player.global_position.y > 2.0, "...it bounces you")
		await frames(10)
		check(not main.bouncies.has(0), "...once: then it's gone")
	player.global_position = Vector3(0, 0.1, 18)
	player.velocity = Vector3.ZERO
	await frames(120)

	# Ledge grab: in the air beside a roof edge your hands can reach, you pull yourself up.
	player.rotation = Vector3.ZERO
	player.pivot.rotation = Vector3.ZERO
	player.global_position = Vector3(8, 2.0, 11.6)    # just off the hut's wall, roof at 4 m
	player.velocity = Vector3.ZERO
	player.test_input = {"dir": Vector2(0, -1)}       # pushing into the wall
	var grabbed := false
	for k in 40:
		await frames(1)
		grabbed = grabbed or player.is_mantling()
	player.test_input = {}
	await frames(10)
	check(grabbed and player.global_position.y > 3.8 and player.is_on_floor(),
			"grab a ledge your hands can reach and pull yourself up (y %.1f)" % player.global_position.y)
	player.global_position = Vector3(8, 0.5, 11.6)    # from the ground: the roof's out of reach
	player.velocity = Vector3(0, 2, 0)
	player.test_input = {"dir": Vector2(0, -1)}
	for k in 40:
		await frames(1)
	player.test_input = {}
	check(player.global_position.y < 1.0, "...but not one that's out of reach")
	player.global_position = Vector3(0, 0.1, 18)
	player.velocity = Vector3.ZERO
	await frames(20)

	# Cloud Stomp damage: most in the middle, more from higher up (to a limit), none past the edge.
	check(Skills.stomp_damage(0.0, 5.0) == 25 and Skills.stomp_damage(0.0, 15.0) == 50 and Skills.stomp_damage(0.0, 40.0) == 50,
			"Cloud Stomp: 25 in the middle from a normal leap, double from high up, no more than that")
	check(Skills.stomp_damage(3.0, 5.0) < 25 and Skills.stomp_damage(3.0, 5.0) > Skills.stomp_damage(5.5, 5.0) and Skills.stomp_damage(5.9, 5.0) == 5 and Skills.stomp_damage(6.5, 5.0) == 0,
			"...less further out, a little at the edge, nothing past it")
	# Holy Leap picked: ordinary jumps go higher.
	var jump_peaks := []
	for lo in [["cherub", "vacuum"], ["cherub", "leap"]]:
		player.loadout["angel"] = lo
		player.global_position = clear_spot(Vector3(6, 0.1, 18))
		player.velocity = Vector3.ZERO
		await frames(15)
		var ground_y: float = player.global_position.y
		player.test_input = {"jump": true}
		await frames(2)
		player.test_input = {}
		var jpeak := ground_y
		for f in 60:
			await frames(1)
			jpeak = maxf(jpeak, player.global_position.y)
		jump_peaks.append(jpeak - ground_y)
	check(jump_peaks[1] > jump_peaks[0] * 1.6, "Holy Leap picked: ordinary jumps go much higher (%.1f m vs %.1f m)" % [jump_peaks[1], jump_peaks[0]])
	player.loadout["angel"] = ["dash", "leap"]

	# Cloud Stomp: press the leap key again mid-air, slam down, hurt demons nearby.
	var victim = null
	for b in get_nodes_in_group("demon"):
		if b.health > 0:
			victim = b
	check(victim != null, "a test demon to stomp on")
	if victim:
		player.global_position = victim.global_position + Vector3(2.0, 0.1, 0)
		for k in 8:   # a spot 2 m from it with plain ground (not inside or on top of something)
			var a := TAU * k / 8.0
			var spot: Vector3 = victim.global_position + Vector3(cos(a), 0, sin(a)) * 2.0
			if absf(main.ground_below(spot + Vector3.UP * 3.0).y - victim.global_position.y) < 0.15:
				player.global_position = spot + Vector3.UP * 0.1
				break
		player.velocity = Vector3.ZERO
		await frames(10)
		player.skill_cd.clear()
		var hp_before: int = victim.health
		var victim_at: Vector3 = victim.global_position   # (the stomp shoves it away, so remember where it was)
		player.test_input = {"jump": true}
		await frames(2)
		player.test_input = {}
		await frames(12)
		check(player.use_skill(1), "jump, then press Holy Leap's key mid-air: Cloud Stomp")
		var t_stomp := 0
		while not player.is_on_floor() and t_stomp < 60:
			await frames(1)
			t_stomp += 1
		await frames(3)
		check(t_stomp < 20, "...slams straight down (%d frames)" % t_stomp)
		var st_off: Vector3 = victim_at - player.global_position
		var st_want := Skills.stomp_damage(Vector2(st_off.x, st_off.z).length(), player._leap_peak - player.global_position.y)
		check(st_want > 0 and hp_before - victim.health == st_want, "...and hurts the demon it lands near (%d damage, %.1f m away, from %.1f m up)" % [hp_before - victim.health, Vector2(st_off.x, st_off.z).length(), player._leap_peak - player.global_position.y])
		await frames(30)
		var pushed := Vector2(victim.global_position.x - player.global_position.x, victim.global_position.z - player.global_position.z).length()
		check(pushed > Vector2(st_off.x, st_off.z).length() + 1.0, "...and the shockwave shoves it away (%.1f m -> %.1f m)" % [Vector2(st_off.x, st_off.z).length(), pushed])
		player.test_input = {"jump": true}
		await frames(2)
		player.test_input = {}
		await frames(10)
		check(not player.use_skill(1), "...and the stomp has a cooldown")
		await frames(90)

	# Holy Scripture: a heavy book that hits hard.
	var reader = null
	player.loadout["angel"] = ["scripture", "leap"]
	for b in get_nodes_in_group("demon"):
		if b.health > Skills.SCRIPTURE_DAMAGE and (await aim_at(player, b, 0.6, 5.0) or await aim_at(player, b, 0.6, 3.5)):
			reader = b
			break
	check(reader != null, "lined up a demon for a scripture")
	if reader:
		player.skill_cd.clear()
		var total_before := 0
		for b in get_nodes_in_group("demon"):
			total_before += b.health
		check(player.use_skill(0), "Holy Scripture")
		await frames(40)
		var total_after := 0
		for b in get_nodes_in_group("demon"):
			total_after += b.health
		# A random prop can sit between the hand and the target (props move each round):
		# line up again and retry a couple of times before calling it a miss.
		for retry in 2:
			if total_after != total_before:
				break
			await aim_at(player, reader, 0.6, 3.0 + retry)
			player.skill_cd.clear()
			player.use_skill(0)
			await frames(40)
			total_after = 0
			for b in get_nodes_in_group("demon"):
				total_after += b.health
		# (It may hit a different demon standing in the way; any demon counts.)
		# A direct hit, plus the smite where it lands (the demon it hit, and any others close by).
		check(total_before - total_after >= Skills.SCRIPTURE_DAMAGE + Skills.SMITE_MIN_DAMAGE,
				"...the book hits for holy damage and smites (%d)" % (total_before - total_after))
		check(not player.use_skill(0), "...then it's on cooldown")
	# Heat-seeking: the book picks the nearest demon ahead of it, never one behind it or far away.
	var seek_bot = get_nodes_in_group("demon")[0]
	var sb: Vector3 = seek_bot.global_position
	check(main._book_target(player, sb + Vector3(0, 1, 6), Vector3(0, 0, -20)) != null, "Holy Scripture heat-seeks a demon ahead of it")
	check(main._book_target(player, sb + Vector3(0, 1, 6), Vector3(0, 0, 20)) == null, "...but not one behind it")
	check(main._book_target(player, sb + Vector3(0, 1, Skills.SEEK_RANGE + 4.0), Vector3(0, 0, -20)) == null, "...or one too far away")
	# The smite on its own: lands near a demon, hurts it (most in the middle), none past 4 m.
	var smitten = null
	for b in get_nodes_in_group("demon"):
		if b.health > Skills.SMITE_DAMAGE:
			smitten = b
	if smitten:
		var hp0: int = smitten.health
		main._smite(player, smitten.global_position + Vector3(1.0, 0, 0))
		await frames(2)
		check(hp0 - smitten.health > Skills.SMITE_MIN_DAMAGE and hp0 - smitten.health < Skills.SMITE_DAMAGE,
				"Holy Scripture smites demons near where it lands (%d damage from 1 m)" % (hp0 - smitten.health))
		var hp1: int = smitten.health
		await frames(20)
		main._smite(player, smitten.global_position + Vector3(Skills.SMITE_RADIUS + 1.0, 0, 0))
		await frames(2)
		check(smitten.health == hp1, "...but not ones further than 4 m away")

	# Holy Kick: boots a demon away.
	var kicked = null
	for b in get_nodes_in_group("demon"):
		if b.health > Skills.KICK_DAMAGE:
			kicked = b
	check(kicked != null, "a test demon to kick")
	if kicked:
		player.loadout["angel"] = ["kick", "leap"]
		player.skill_cd.clear()
		# Stand on open ground right next to it, facing it.
		for k in 12:
			var a := TAU * k / 12.0
			var spot: Vector3 = kicked.global_position + Vector3(cos(a), 0, sin(a)) * 1.6
			if absf(main.ground_below(spot + Vector3.UP * 3.0).y - kicked.global_position.y) < 0.15:
				player.global_position = spot + Vector3.UP * 0.1
				break
		player.velocity = Vector3.ZERO
		await frames(5)
		player.look_at(Vector3(kicked.global_position.x, player.global_position.y, kicked.global_position.z))
		player.pivot.rotation = Vector3.ZERO
		await frames(2)
		var others_before := 0
		for b in get_nodes_in_group("demon"):
			others_before += b.health
		var kd_before: float = kicked.global_position.distance_to(player.global_position)
		check(player.use_skill(0), "Holy Kick")
		await frames(40)
		var others_after := 0
		for b in get_nodes_in_group("demon"):
			others_after += b.health
		var kd_after: float = kicked.global_position.distance_to(player.global_position)
		check(kd_after > kd_before + 4.0 or others_after < others_before, "...sends the demon flying (%.1f m -> %.1f m)" % [kd_before, kd_after])
		check(others_before - others_after == Skills.KICK_DAMAGE, "...with some damage (%d)" % (others_before - others_after))
		player.loadout["angel"] = ["dash", "leap"]

	# Hellfire (decided by the practice game here): an angel in it is slowed and burns blessings.
	player.global_position = Vector3(-20, 0.1, -20)
	player.velocity = Vector3.ZERO
	player.throw_stamina = player.THROW_STAMINA_MAX
	await frames(10)
	# A stand-in demon 9 m away flings it; then we walk into where it lands.
	var thrower := Node3D.new()
	main.add_child(thrower)
	thrower.global_position = clear_lane(player.global_position + Vector3(0, 0, 9), Vector3(0, 0, -1), 16.0)
	main.state = main.State.HIDING
	var fire_n: int = main._fire_counter + 1
	main.authority_skill(thrower, 0, "fire", thrower.global_position + Vector3.UP * 1.5, Vector3(0, 0, -1), Vector3.ZERO, -1)
	await frames(2)
	var fb = main.fires.get(fire_n)
	check(fb != null and fb.from.distance_to(thrower.global_position) < 2.0, "Hellfire is flung from the demon's hands")
	var landed: float = fb.to.distance_to(thrower.global_position) if fb else 0.0
	check(landed > 6.0 and landed < 16.0, "...and lands a good way off (%.1f m)" % landed)
	await frames(60)
	var feet: Vector3 = fb.to if fb else player.global_position
	player.global_position = feet + Vector3.UP * 0.1
	await frames(30)
	check(player.burning <= 0.0 and player.throw_stamina >= player.THROW_STAMINA_MAX - 1.0,
			"while the demons are still hiding, Hellfire doesn't hurt angels")
	main.state = main.State.HUNTING
	await frames(45)
	check(player.burning > 0.0, "standing in Hellfire sets an angel burning")
	check(main.heat_rect.visible, "...the whole view swims with heat")
	check(player.throw_stamina < player.THROW_STAMINA_MAX - 15.0, "...which burns away blessing stamina")
	# Walking straight ahead while on fire: you lurch about.
	player.rotation = Vector3.ZERO
	var walk0: Vector3 = player.global_position
	player.test_input = {"dir": Vector2(0, -1)}
	var wander := 0.0
	for k in 60:
		await frames(1)
		wander = maxf(wander, absf(player.global_position.x - walk0.x))
	player.test_input = {}
	check(wander > 0.4, "...and you can't walk a straight line (%.1f m off course)" % wander)
	player.global_position = feet + Vector3(6, 0.1, 0)
	await frames(30)
	check(player.burning > 0.0, "stepping out, you keep burning a moment")
	await frames(120)
	check(player.burning <= 0.0 and not main.heat_rect.visible, "...then it stops")
	thrower.queue_free()

	# Demons pay Hatred for Hellfire.
	player.set_role("demon")
	player.loadout["demon"] = ["fire", "fly"]
	player.hatred = 20.0
	check(not player.use_skill(0), "not enough Hatred: no Hellfire")
	player.hatred = 100.0
	var fires_before: int = main.fires.size()
	check(player.use_skill(0), "Hellfire with a full bar")
	check(player.hatred < 70.0, "...costs Hatred (%.0f left)" % player.hatred)
	await frames(5)
	check(main.fires.size() > fires_before, "...and lights a fire")

	# Camera: a demon's mouse swings the camera around it; an angel's turns the angel.
	var swing := Vector2(150, 0)
	var body_yaw: float = player.rotation.y
	var cam_yaw: float = player.pivot.rotation.y
	player.look(swing)
	check(is_equal_approx(player.rotation.y, body_yaw) and not is_equal_approx(player.pivot.rotation.y, cam_yaw),
			"demon: the mouse swings the camera around you without turning you")
	player.pivot.rotation.y = 0.0

	# Minion: press to make one, hold to steer it, it has a demon's health.
	main.round_root.get_children().filter(func(n): return n is CharacterBody3D and n.get("life") != null).map(func(n): n.queue_free())
	player.global_position = clear_lane(Vector3(0, 0.1, 15), Vector3(0, 0, -1), 10.0)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.loadout["demon"] = ["minion", "fly"]
	player.skill_cd.clear()
	player.hatred = 100.0
	await frames(5)
	player.pivot.rotation.x = -0.3                 # aiming at the ground ~5 m ahead
	await frames(2)
	var aim_spot: Dictionary = player._aim_ray(Skills.MINION_RANGE)
	check(player.use_skill(0), "Minion")
	check(is_instance_valid(player.minion), "...a decoy of you appears")
	if is_instance_valid(player.minion) and not aim_spot.is_empty():
		var off_aim := Vector2(player.minion.global_position.x - aim_spot["position"].x, player.minion.global_position.z - aim_spot["position"].z).length()
		check(off_aim < 0.8, "...right where you were aiming (%.1f m off)" % off_aim)
	check(player.hatred < 75.0, "...costs Hatred")
	player.skill_cd.clear()
	check(not player.use_skill(0), "...only one at a time")
	await frames(10)
	var m = player.minion
	if is_instance_valid(m):
		var m_start: Vector3 = m.global_position
		player.pivot.rotation.x = -0.12            # crosshair on the ground further ahead
		player.test_input = {"minion": true}
		await frames(70)
		player.test_input = {}
		var walked_m := Vector2(m.global_position.x - m_start.x, m.global_position.z - m_start.z).length()
		check(walked_m > 2.0, "...holding the key steers it to the ground under your crosshair (%.1f m)" % walked_m)
		check(m.velocity.length() < PropLib.speed("") + 0.5, "...no faster than a real demon")
		await frames(30)
		check(not m.steering, "...let go and it stops steering")
		var hatred_before_hits: float = player.hatred
		var hits_to_pop := 0
		while is_instance_valid(m) and not m.is_queued_for_deletion() and hits_to_pop < 10:
			m.take_hit(25, null)
			hits_to_pop += 1
		check(hits_to_pop == 2, "...flimsy: pops after 2 blessings (a real demon takes 4)")
		check(player.hatred > hatred_before_hits + 10.0 or player.hatred >= player.HATRED_MAX - 0.1,
				"...and each angel it fools earns you Hatred (naughty!)")
	player.pivot.rotation.x = 0.0

	# Disguised as a prop, the minion is some other prop that's on this map.
	var prop_types_on_map := []
	for pr in main.props:
		if is_instance_valid(pr) and pr.has_meta("prop_type"):
			prop_types_on_map.append(pr.get_meta("prop_type"))
	player.force_possess("crate")
	player.skill_cd.clear()
	player.hatred = 100.0
	await frames(3)
	check(player.use_skill(0), "Minion while disguised")
	await frames(2)
	check(is_instance_valid(player.minion) and player.minion.form in prop_types_on_map,
			"...is a prop that's really on this map (%s)" % (player.minion.form if is_instance_valid(player.minion) else "none"))
	if is_instance_valid(player.minion):
		player.minion.queue_free()
	player.unpossess()

	# Something standing on your head doesn't pin you: you walk out from under it.
	var sitter = load("res://scripts/cherub.gd").new()
	main.round_root.add_child(sitter)
	player.global_position = clear_spot(Vector3(12, 0.1, 18))
	player.velocity = Vector3.ZERO
	await frames(10)
	sitter.launch(player.global_position + Vector3.UP * 2.6, Vector3.ZERO)
	await frames(30)
	var pinned_at: Vector3 = player.global_position
	player.test_input = {"dir": Vector2(1, 0)}
	await frames(40)
	player.test_input = {}
	check(Vector2(player.global_position.x - pinned_at.x, player.global_position.z - pinned_at.z).length() > 1.5,
			"something on your head doesn't pin you in place")
	sitter.queue_free()

	# Invisibility is a power-up now, not a skill; and Teleport.
	check(not Skills.SKILLS.has("vanish") and "vanish" in PowerUps.DEMON_KINDS, "Invisibility is a demon power-up, not a skill")
	player.apply_powerup("vanish")
	check(player.vanish_time > 6.0, "...picking it up: you vanish for 6.5 s")
	player.loadout["demon"] = ["minion", "teleport"]
	player.skill_cd.clear()
	await frames(10)
	player.hatred = 100.0
	player.global_position = clear_lane(Vector3(0, 0.1, 22), Vector3(0, 0, -1), 22.0)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.pivot.rotation = Vector3(-0.2, 0, 0)   # crosshair on the ground ahead
	await frames(5)
	var tp_from: Vector3 = player.global_position
	var tp_aim: Dictionary = player._aim_ray(Skills.TELEPORT_RANGE)
	check(player.use_skill(1), "Teleport")
	await frames(3)
	var tp_moved := Vector2(player.global_position.x - tp_from.x, player.global_position.z - tp_from.z).length()
	if not tp_aim.is_empty():
		var tp_off := Vector2(player.global_position.x - tp_aim["position"].x, player.global_position.z - tp_aim["position"].z).length()
		check(tp_off < 1.2, "...to where you aimed (%.1f m away, %.1f m off)" % [tp_moved, tp_off])
	check(player.hatred < 45.0, "...for 60 Hatred")
	player.skill_cd.clear()
	player.hatred = 100.0
	player.pivot.rotation = Vector3(0.05, 0, 0)   # aiming off into the sky: as far as allowed
	await frames(3)
	var tp2_from: Vector3 = player.global_position
	check(player.use_skill(1), "Teleport toward the sky")
	await frames(3)
	var far := Vector2(player.global_position.x - tp2_from.x, player.global_position.z - tp2_from.z).length()
	check(far > Skills.TELEPORT_RANGE - 3.0 and far <= Skills.TELEPORT_RANGE + 0.5 and player.global_position.y < 6.0,
			"...goes as far as allowed that way, onto the ground (%.1f m)" % far)
	player.pivot.rotation = Vector3.ZERO

	# Angels: the mouse turns you (unless you hold Alt).
	player.set_role("angel")
	body_yaw = player.rotation.y
	player.look(swing)
	check(not is_equal_approx(player.rotation.y, body_yaw) and is_zero_approx(player.pivot.rotation.y),
			"angel: the mouse turns you, so the crosshair stays true")

	# Cherub Sense: a little cherub dangles over the angel's head while it lasts.
	main.role = "angel"
	player.apply_powerup("sense")
	await frames(3)
	var sc = main._sense_cherub
	check(is_instance_valid(sc) and sc.get_parent() == player and sc.position.y > 1.8, "Cherub Sense: a cherub dangles above the angel's head")
	main._sense_tick = 1.0   # (so the real check doesn't switch it straight back off)
	player.sense_alarm = true
	await frames(2)
	check(sc.alarmed, "...and goes frantic when a demon is close")
	player.sense_alarm = false
	player.powerups["sense"] = 0.01
	await frames(5)
	check(not is_instance_valid(main._sense_cherub) or main._sense_cherub == null, "...and goes away when the power-up runs out")

	# Fear: angels near a shrieking demon (who can see it) scatter, and can't attack.
	main.role = "angel"
	main.state = main.State.HUNTING
	var fear_at: Vector3 = clear_lane(Vector3(-14, 0.1, 6), Vector3(1, 0, 0), 16.0)
	var shrieker = get_nodes_in_group("demon")[0]
	shrieker.global_position = fear_at
	player.global_position = fear_at + Vector3(4, 0, 0)
	player.velocity = Vector3.ZERO
	player.throw_stamina = 100.0
	await frames(5)
	main.authority_skill(shrieker, 7, "fear", shrieker.global_position, Vector3.FORWARD, Vector3.ZERO, -1)
	check(player.feared > 1.8, "Fear: an angel nearby panics")
	check(player.try_throw(), "...but can still throw (good luck aiming)")
	var fear_d0: float = player.global_position.distance_to(shrieker.global_position)
	var fear_yaw0: float = player.rotation.y
	var fear_pitch0: float = player.pivot.rotation.x
	await frames(45)
	var fear_d1: float = player.global_position.distance_to(shrieker.global_position)
	check(fear_d1 > fear_d0 + 2.0, "...and runs off, away from the demon (%.1f m -> %.1f m)" % [fear_d0, fear_d1])
	check(absf(player.rotation.y - fear_yaw0) > 0.05 or absf(player.pivot.rotation.x - fear_pitch0) > 0.05, "...with their aim shaking all over")
	await frames(110)
	check(player.feared <= 0.0, "...and it wears off after 2 seconds")
	player.global_position = fear_at + Vector3(12, 0, 0)
	await frames(3)
	player.feared = 0.0
	main.authority_skill(shrieker, 7, "fear", shrieker.global_position, Vector3.FORWARD, Vector3.ZERO, -1)
	check(player.feared <= 0.0, "...angels further than 10 m away don't")
	player.global_position = fear_at + Vector3(6, 0, 0)
	var fear_wall: Node3D = main._add_block(fear_at + Vector3(3, 2, 0), Vector3(0.5, 4, 6), Color.GRAY)
	await frames(3)
	main.authority_skill(shrieker, 7, "fear", shrieker.global_position, Vector3.FORWARD, Vector3.ZERO, -1)
	check(player.feared <= 0.0, "...nor angels behind a wall")
	fear_wall.queue_free()

	# Holy Word: a flier high enough up, on the crosshair line, is struck out of the sky and stunned.
	main.role = "demon"
	player.set_role("demon")
	player.loadout["demon"] = ["possess", "fly"]
	player.global_position = fear_at + Vector3(8, 0.1, 0)
	player.velocity = Vector3.ZERO
	player.hatred = player.HATRED_MAX
	await frames(5)
	var word_ground: float = player.global_position.y
	player.test_input = {"fly": true}
	await frames(70)
	check(player.flying and player.global_position.y - word_ground > Skills.WORD_MIN_HEIGHT,
			"(a demon flying %.1f m up)" % (player.global_position.y - word_ground))
	var word_from: Vector3 = shrieker.global_position + Vector3.UP * 1.4
	var word_dir: Vector3 = (player.global_position + Vector3.UP * 0.6 - word_from).normalized()
	main.authority_skill(shrieker, 7, "word", word_from, word_dir, Vector3.ZERO, -1)
	check(player.stunned > 0.0 and not player.flying, "Holy Word strikes a flier out of the sky, stunned")
	await frames(10)
	check(not player.flying and player.velocity.y < 0.0, "...it drops, and can't fly while the key is still held")
	for i in 120:
		if player.is_on_floor():
			break
		await frames(1)
	player.test_input = {}
	await frames(5)
	player.test_input = {"fly": true}
	await frames(10)
	check(player.flying, "...and once it's landed it can fly again")
	player.test_input = {}
	await frames(60)
	# On the ground (not flying): Holy Word does nothing to it.
	main.authority_skill(shrieker, 7, "word", word_from, (player.global_position + Vector3.UP * 0.6 - word_from).normalized(), Vector3.ZERO, -1)
	check(player.stunned <= 0.0, "...but a demon on the ground isn't stunned")
	main.role = "angel"
	player.set_role("angel")

	# The shrine: the only place to swap skills mid-round, and it takes 3 s in total.
	main.state = main.State.HUNTING
	main.role = "demon"          # (the Hellfire check above switched only the player to demon)
	main.time_left = 999.0
	player.loadout["demon"] = ["fire", "fly"]
	main.loadout["demon"] = ["fire", "fly"]
	player.global_position = main.SHRINE_POS + Vector3(6, 0.5, 0)
	await frames(10)
	main._try_open_shrine()
	check(not main.shrine_panel.visible, "away from the shrine: no swapping")
	player.global_position = main.SHRINE_POS + Vector3(1, 0.5, 0)
	await frames(10)
	player.force_possess("crate")
	main._try_open_shrine()
	check(not main.shrine_panel.visible, "demons can't swap while hiding in a prop")
	player.unpossess()
	await frames(5)
	main._try_open_shrine()
	check(main.shrine_panel.visible, "at the shrine in demon form: G opens the swap")
	main._on_shrine_pick(0, "possess")
	main._confirm_shrine()       # picked fast...
	await frames(60)
	check(player.loadout["demon"][0] == "fire", "...but the swap still takes the full 3 s")
	await frames(140)
	check(player.loadout["demon"] == ["possess", "fly"], "...then it goes through (%s)" % "+".join(player.loadout["demon"]))
	check(not main.shrine_panel.visible, "...and the panel closes")
	main._try_open_shrine()
	await frames(220)              # dawdle past 3 s before picking
	main._on_shrine_pick(1, "fire")
	main._confirm_shrine()
	await frames(3)
	check(player.loadout["demon"] == ["possess", "fire"], "taking longer than 3 s: no extra wait after confirming")
	check(player.skill_cd.values().all(func(v): return v <= 0.0), "...and every cooldown is refreshed by the swap")
	main._close_shrine()

	# Angels waiting out the hiding period: swap anywhere, straight away, and the new skills are ready to use.
	main.state = main.State.HIDING
	main.role = "angel"
	player.role = "angel"
	player.frozen = true
	player.loadout["angel"] = ["cherub", "dash"]
	main.loadout["angel"] = ["cherub", "dash"]
	player.global_position = main.SHRINE_POS + Vector3(15, 0.5, 0)
	await frames(5)
	main._try_open_shrine()
	check(main.shrine_panel.visible, "a waiting angel can open the skill swap anywhere")
	main._on_shrine_pick(0, "vacuum")
	main._confirm_shrine()
	await frames(3)
	check(player.loadout["angel"] == ["vacuum", "dash"], "...it goes through straight away (%s)" % "+".join(player.loadout["angel"]))
	check(player.skill_cd.get("vacuum", 0.0) <= 0.0, "...and the new skill has no cooldown")
	player.frozen = false

	print("\n%s: %d failure(s)" % ["ALL PASSED" if failures == 0 else "FAILED", failures])
	quit(1 if failures else 0)
