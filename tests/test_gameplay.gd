# Automated playtest. Run from the project folder:
#   godot --headless -s res://tests/test_gameplay.gd
# Checks: a full angel round can be won by catching every bot demon,
# and a demon can possess a prop and turn back.
extends SceneTree

var main: Node
var failures := 0


func _initialize() -> void:
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


# Stand the player a few meters from target with a clear line of sight, aimed at it.
func aim_at(player: CharacterBody3D, target: Node3D, aim_height: float) -> bool:
	var aim_point := target.global_position + Vector3.UP * aim_height
	for i in 16:
		var angle := TAU * i / 16.0
		var spot := target.global_position + Vector3(cos(angle), 0, sin(angle)) * 3.5
		player.global_position = spot + Vector3.UP * 0.1
		player.velocity = Vector3.ZERO
		player.look_at(Vector3(aim_point.x, player.global_position.y, aim_point.z))
		await frames(2)
		# The demon camera swings on its arm when it tilts, so re-aim a few times.
		for pass_num in 4:
			var eye: Vector3 = player.camera.global_position
			var flat := Vector2(aim_point.x - eye.x, aim_point.z - eye.z).length()
			player.pivot.rotation.x = clampf(atan2(aim_point.y - eye.y, flat), -1.4, 1.2)
			await frames(1)
		# Check with the game's own crosshair ray.
		var hit: Dictionary = player._aim_ray(20.0)
		if not hit.is_empty() and hit["collider"] == target:
			return true
	return false


func _run() -> void:
	await frames(5)
	var player = main.player

	# ---- Angel round ----
	check(main.role == "angel", "game starts on the angel side")
	check(main.bots_left == 3, "3 bot demons spawned (got %d)" % main.bots_left)
	check(get_nodes_in_group("prop").size() == 45, "45 props spawned")
	check(player.frozen, "angel is frozen during the hiding period")
	main.time_left = 0.0
	await frames(3)
	check(main.state == main.State.HUNTING, "hunting starts after the hiding period")
	check(not player.frozen, "angel can move once hunting starts")

	var hits := [0]
	player.hit_confirmed.connect(func(): hits[0] += 1)
	for bot in get_nodes_in_group("demon").duplicate():
		var lined_up: bool = await aim_at(player, bot, 0.3)
		check(lined_up, "found a clear shot at a %s demon" % bot.prop_type)
		var shots := 0
		while is_instance_valid(bot) and shots < 12:
			player._shoot()
			shots += 1
			await frames(25)
		check(not is_instance_valid(bot), "demon caught after %d throws" % shots)
	await frames(2)
	check(main.bots_left == 0, "no demons left")
	check(main.state == main.State.ENDED, "round ends when every demon is caught")
	check(main.center_label.text.begins_with("All demons caught"), "win message shown")
	check(hits[0] == 12, "every catching hit confirmed back to the angel (got %d)" % hits[0])

	# ---- View toggle ----
	check(player.spring.spring_length == 0.0, "angel starts in first person")
	player.toggle_view()
	check(player.spring.spring_length > 0.0 and player.visual_root.visible, "T switches angel to third person")
	player.toggle_view()
	check(player.spring.spring_length == 0.0, "T switches back to first person")

	# ---- Blessings ----
	var first_kind: String = player.blessing
	player.cycle_blessing()
	check(player.blessing != first_kind, "B cycles to another blessing (%s)" % player.blessing)
	var thrown := [""]
	player.threw.connect(func(kind): thrown[0] = kind)
	player._shoot()
	await frames(1)
	check(thrown[0] == player.blessing, "throw reports its blessing kind for the sound")

	# ---- Demon sandbox ----
	main.role = "demon"
	main.start_round()
	await frames(3)
	check(player.role == "demon", "switched to the demon side")
	check(get_nodes_in_group("demon").is_empty(), "no bot demons in the sandbox")
	var cap: CapsuleShape3D = player.shape_node.shape
	check(cap.height < 1.2, "demon is small (%.2f m tall)" % cap.height)
	# The playtest bug: our own demon covered the crosshair. Cast the crosshair
	# ray WITHOUT ignoring ourselves, looking straight ahead and slightly down.
	for pitch in [0.0, -0.3, -0.6]:
		player.pivot.rotation.x = pitch
		await frames(2)
		var cam: Camera3D = player.camera
		var q := PhysicsRayQueryParameters3D.create(cam.global_position,
				cam.global_position - cam.global_transform.basis.z * 6.0)
		var self_hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
		check(self_hit.is_empty() or self_hit["collider"] != player,
				"own demon doesn't block the crosshair (pitch %.1f)" % pitch)
	var prop: Node3D = get_nodes_in_group("prop")[0]
	var lined: bool = false
	for p in get_nodes_in_group("prop"):
		prop = p
		lined = await aim_at(player, prop, 0.2)
		if lined:
			break
	check(lined, "lined up on a prop")
	await frames(2)
	var outlined := false
	for c in prop.get_children():
		if c is Node3D:
			for m in c.get_children():
				if m is MeshInstance3D and m.material_overlay != null:
					outlined = true
	check(outlined, "hovered prop is outlined")
	var ok: bool = player.try_possess()
	check(ok and player.possessed_type == prop.get_meta("prop_type"),
			"demon possessed a %s" % prop.get_meta("prop_type"))
	await frames(30)
	check(player.is_on_floor(), "possessed demon lands on the floor")
	# Holding the click returns to demon form. (Headless can't capture the mouse,
	# so start the hold the way a click on a possessed demon does.)
	player._holding = true
	player._hold_time = 0.0
	await frames(15)
	check(player.possessed_type != "" and player.hold_fraction > 0.0, "short hold keeps the prop, shows progress")
	await frames(40)
	check(player.possessed_type == "", "holding click returns to demon form")
	check(player.hold_fraction == 0.0, "hold progress resets")
	await frames(30)
	check(player.is_on_floor(), "demon form lands on the floor")
	player.toggle_view()
	check(player.spring.spring_length == 0.0 and not player.visual_root.visible, "T switches demon to first person")

	# ---- Movement: momentum, run, sneak ----
	# The raised platform's top is at y=2, spanning x -10..-2, z 10..14.
	# Its east edge (x=-2) is a sheer 2 m drop; its north side has the ramp.
	player.rotation = Vector3.ZERO   # facing -Z, so input x=+1 walks toward +X
	player.global_position = Vector3(-8, 2.05, 12)
	player.velocity = Vector3.ZERO
	await frames(5)
	player.test_input = {"dir": Vector2(1, 0)}
	await frames(2)
	var early: float = Vector2(player.velocity.x, player.velocity.z).length()
	await frames(20)
	var settled: float = Vector2(player.velocity.x, player.velocity.z).length()
	check(early < settled * 0.6 and settled > 6.0,
			"speeds up instead of snapping to full speed (%.1f then %.1f m/s)" % [early, settled])
	player.test_input = {}
	await frames(2)
	var stopping: float = Vector2(player.velocity.x, player.velocity.z).length()
	check(stopping > 0.5 and stopping < settled, "slows down instead of stopping dead (%.1f m/s)" % stopping)
	await frames(30)

	var speeds := {}
	for mode in ["walk", "run", "sneak"]:
		player.global_position = Vector3(-9, 2.05, 12)
		player.velocity = Vector3.ZERO
		player.sprint_stamina = player.SPRINT_MAX
		await frames(5)
		player.test_input = {"dir": Vector2(1, 0), "run": mode == "run", "sneak": mode == "sneak"}
		await frames(25)
		speeds[mode] = Vector2(player.velocity.x, player.velocity.z).length()
		player.test_input = {}
	check(speeds["run"] > speeds["walk"] and speeds["walk"] > speeds["sneak"] and speeds["sneak"] > 0.5,
			"run > walk > sneak (%.1f / %.1f / %.1f m/s)" % [speeds["run"], speeds["walk"], speeds["sneak"]])

	player.global_position = Vector3(-4, 2.05, 12)
	player.velocity = Vector3.ZERO
	await frames(5)
	player.test_input = {"dir": Vector2(1, 0), "sneak": true}
	await frames(120)
	check(player.global_position.y < 1.0, "sneaking no longer stops you at ledges (y %.2f)" % player.global_position.y)
	player.test_input = {}

	player.global_position = Vector3(-6, 0.05, 3.5)
	player.velocity = Vector3.ZERO
	await frames(5)
	player.test_input = {"dir": Vector2(0, 1)}
	await frames(85)   # long enough to reach the top, not long enough to walk off the far side
	check(player.global_position.y > 1.9, "small demon walks up the ramp onto the platform (y %.2f)" % player.global_position.y)
	player.test_input = {}

	# ---- Jumping ----
	player.global_position = Vector3(0, 0.05, 20)
	player.velocity = Vector3.ZERO
	await frames(10)
	var ground_y: float = player.global_position.y
	player.test_input = {"jump": true}
	await frames(1)
	player.test_input = {}
	var peak := ground_y
	var t_up := 0
	var t_total := 0
	while t_total < 200:
		await frames(1)
		t_total += 1
		if player.global_position.y > peak:
			peak = player.global_position.y
			t_up = t_total
		if t_total > 3 and player.is_on_floor():
			break
	var height: float = peak - ground_y
	check(height > 0.8 and height < 1.6, "jump height is reasonable (%.2f m)" % height)
	check(t_total - t_up < t_up, "falls faster than it rises: not floaty (%d frames up, %d down)" % [t_up, t_total - t_up])

	# ---- Sprint stamina ----
	player.global_position = Vector3(-20, 0.05, 20)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.sprint_stamina = player.SPRINT_MAX
	await frames(5)
	player.test_input = {"dir": Vector2(1, 0), "run": true}
	await frames(30)
	check(player.running and player.sprint_stamina < player.SPRINT_MAX, "running drains sprint stamina")
	player.sprint_stamina = 1.0
	await frames(10)
	check(not player.running and player._sprint_exhausted, "can't run once sprint stamina is empty")
	player.test_input = {}
	await frames(120)
	check(player.sprint_stamina > 10.0, "sprint stamina refills after resting (%.0f)" % player.sprint_stamina)

	# ---- Hatred ----
	var hatred_before: float = player.hatred
	await frames(60)
	check(player.hatred > hatred_before, "demon Hatred fills over time")

	# ---- Taunts ----
	var sig: String = player.Taunts.signature("demon")
	var last := ""
	var never_sig := true
	var never_repeat := true
	for i in 300:
		var pick: String = player.Taunts.pick_random("demon", last)
		if pick == sig:
			never_sig = false
		if pick == last:
			never_repeat = false
		last = pick
	check(never_sig, "random taunt (1) never picks the signature taunt")
	check(never_repeat, "random taunt never repeats twice in a row")
	var heard := [""]
	player.taunted.connect(func(n): heard[0] = n)
	player._taunt_cooldown = 0.0
	check(player.taunt(true) and heard[0] == sig, "taunt 2 plays the signature taunt")
	check(not player.taunt(false), "taunts have a short cooldown")
	player._taunt_cooldown = 0.0
	check(player.taunt(false) and heard[0] != sig, "taunt 1 plays a random one (%s)" % heard[0])
	check(player.voice.stream != null, "taunt has a sound")

	# ---- Angel: throw stamina + head bob ----
	main.role = "angel"
	main.start_round()
	main.time_left = 0.0
	await frames(3)
	# Hold the button for 4 seconds (try every frame), count throws per second.
	var per_second := [0, 0, 0, 0]
	for i in 240:
		if player.try_throw():
			per_second[i / 60] += 1
		await frames(1)
	check(per_second[0] >= 8, "throws rapidly from full stamina (%d in the 1st second)" % per_second[0])
	check(per_second[3] < per_second[0] and per_second[3] >= 3,
			"stamina slows spam to a steady rate (%d/s at first, %d/s after 3 s)" % [per_second[0], per_second[3]])
	await frames(240)
	check(player.throw_stamina >= player.THROW_STAMINA_MAX - 1.0,
			"blessing stamina refills (%.0f)" % player.throw_stamina)
	player.throw_regen_multiplier = 5.0   # the future quick-regen power-up
	player.throw_stamina = 0.0
	var boosted := 0
	for i in 60:
		if player.try_throw():
			boosted += 1
		await frames(1)
	check(boosted >= 8, "quick-regen power-up allows near-nonstop throwing (%d in 1 s from empty)" % boosted)
	player.throw_regen_multiplier = 1.0

	player.global_position = Vector3(0, 0.05, 20)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	await frames(5)
	player.test_input = {"dir": Vector2(1, 0)}
	var bob_min := 9.0
	var bob_max := -9.0
	for i in 60:
		await frames(1)
		bob_min = minf(bob_min, player.spring.position.y)
		bob_max = maxf(bob_max, player.spring.position.y)
	player.test_input = {}
	check(bob_max - bob_min > 0.02 and bob_max - bob_min < 0.2,
			"first-person head bob while walking (%.3f m)" % (bob_max - bob_min))
	print("\n%s: %d failure(s)" % ["ALL PASSED" if failures == 0 else "FAILED", failures])
	quit(1 if failures else 0)
