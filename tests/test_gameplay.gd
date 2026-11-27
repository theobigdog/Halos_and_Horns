# Automated playtest. Run from the project folder:
#   godot --headless -s res://tests/test_gameplay.gd
# Checks: a full angel round can be won by catching every bot demon,
# and a demon can possess a prop and turn back.
extends SceneTree

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


# Stand the player a few meters from target with a clear line of sight, aimed at it.
func aim_at(player: CharacterBody3D, target: Node3D, aim_height: float) -> bool:
	var aim_point := target.global_position + Vector3.UP * aim_height
	for i in 16:
		var angle := TAU * i / 16.0
		var spot := target.global_position + Vector3(cos(angle), 0, sin(angle)) * 3.5
		player.global_position = spot + Vector3.UP * 0.1
		player.velocity = Vector3.ZERO
		player.look_at(Vector3(aim_point.x, player.global_position.y, aim_point.z))
		player.pivot.rotation.y = 0.0
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
	main.start_practice()   # the game opens on the main menu
	await frames(5)
	var player = main.player

	# ---- Angel round ----
	check(main.role == "angel", "game starts on the angel side")
	check(main.bots_left == 3, "3 bot demons spawned (got %d)" % main.bots_left)
	check(get_nodes_in_group("prop").size() == 45, "45 props spawned")
	check(player.frozen, "angel is frozen during the hiding period")
	main.time_left = 0.0
	for i in 30:   # (a slow frame can delay the switch a tick or two)
		await frames(1)
		if main.state == main.State.HUNTING:
			break
	await frames(2)
	check(main.state == main.State.HUNTING, "hunting starts after the hiding period")
	check(not player.frozen, "angel can move once hunting starts")

	var hits := [0]
	player.hit_confirmed.connect(func(): hits[0] += 1)
	for bot in get_nodes_in_group("demon").duplicate():
		var lined_up: bool = await aim_at(player, bot, 0.3)
		check(lined_up, "found a clear shot at a %s demon" % bot.prop_type)
		var shots := 0
		while is_instance_valid(bot) and shots < 12:
			if shots > 0:
				await aim_at(player, bot, 0.3)   # (hits nudge a disguise, like the prop it looks like: aim again)
			if not is_instance_valid(bot):
				break
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
	var pads: Array = main.BOUNCIES + main.ONE_USE_BOUNCIES + main.SUPER_BOUNCIES
	for p in get_nodes_in_group("prop"):
		# (not one lying next to a bouncy pad: turning into a long bench there flings you into the air)
		if pads.any(func(b): return Vector2(b.x - p.global_position.x, b.z - p.global_position.z).length() < 3.0):
			continue
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
	var ok: bool = player.try_transform()
	check(ok and player.possessed_type == prop.get_meta("prop_type"),
			"demon possessed a %s" % prop.get_meta("prop_type"))
	await frames(30)
	check(player.is_on_floor(), "possessed demon lands on the floor (at %s, moving %s)" % [player.global_position, player.velocity])
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
	check(player.is_on_floor(), "demon form lands on the floor (at %s, moving %s)" % [player.global_position, player.velocity])
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

	# ---- Crouching (Ted, Nov 27): a shorter body, and you stay down under something low ----
	player.global_position = Vector3(0, 0.05, 20)
	player.velocity = Vector3.ZERO
	await frames(5)
	var stand_h: float = player.shape_node.shape.height
	player.test_input = {"sneak": true}
	await frames(3)
	var crouch_h: float = player.shape_node.shape.height
	check(player.crouched and crouch_h < stand_h * 0.7, "crouching makes your body shorter (%.2f -> %.2f m)" % [stand_h, crouch_h])
	var lid := StaticBody3D.new()
	var lid_shape := CollisionShape3D.new()
	var lid_box := BoxShape3D.new()
	lid_box.size = Vector3(3, 0.2, 3)
	lid_shape.shape = lid_box
	lid.add_child(lid_shape)
	main.world_root.add_child(lid)
	lid.global_position = Vector3(0, crouch_h + 0.2 + 0.1, 20)   # just over a crouched head, under a standing one
	await frames(3)
	player.test_input = {}
	await frames(5)
	check(player.crouched, "...and stays crouched while there's no room to stand")
	lid.queue_free()
	await frames(5)
	check(not player.crouched and absf(player.shape_node.shape.height - stand_h) < 0.01, "...then stands up once there is")
	player.test_input = {"sneak": true, "jump": true}
	await frames(2)
	player.test_input = {"sneak": true}
	await frames(10)
	check(player.crouched and player.velocity.y != 0.0, "you can crouch while jumping")
	player.test_input = {}
	await frames(60)

	# ---- Props roll, tumble, go over and right themselves (Ted, Nov 27) ----
	player.global_position = Vector3(0, 0.1, 20)
	player.force_possess("apple")
	await frames(3)
	player.test_input = {"dir": Vector2(1, 0)}
	await frames(30)
	var rolled: Basis = player.prop_pose().basis
	check(not rolled.is_equal_approx(Basis()), "a demon moving as an apple rolls along")
	player.test_input = {"dir": Vector2(1, 0), "run": true}
	await frames(40)
	check(player.prop_pose().basis.y.dot(Vector3.UP) > 0.98, "...and holding Shift rights it and keeps it upright")
	player.test_input = {}
	player.force_possess("dungeon/table_medium")
	await frames(3)
	player.test_input = {"dir": Vector2(-1, 0)}
	await frames(20)
	check(player.prop_pose().basis.is_equal_approx(Basis()), "an upright table slides instead of rolling")
	player.test_input = {}
	player.force_possess("lamp")
	await frames(3)
	player.shoved(Vector3(1.5, 0, 0))
	await frames(30)
	check(player.is_tipped(), "a disguise shoved hard enough goes over, like the real prop")
	player.test_input = {"run": true}
	await frames(40)
	check(not player.is_tipped(), "...and Shift stands it back up")
	player.test_input = {}
	player.unpossess()
	await frames(10)

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
	player.hatred = 40.0   # demons start full; spend some first
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
	# Click as fast as possible for 4 seconds (try every frame), count throws per second.
	var per_second := [0, 0, 0, 0]
	for i in 240:
		if player.try_throw():
			per_second[i / 60] += 1
		await frames(1)
	check(per_second[0] >= 7, "throws rapidly from full stamina (%d in the 1st second)" % per_second[0])
	check(per_second[3] < per_second[0] and per_second[3] >= 1 and per_second[3] <= 2,
			"stamina slows spam to a steady rate (%d/s at first, %d/s after 3 s)" % [per_second[0], per_second[3]])
	await frames(400)
	check(player.throw_stamina >= player.THROW_STAMINA_MAX - 1.0,
			"blessing stamina refills (%.0f)" % player.throw_stamina)
	player.apply_powerup("quick_throw")   # the Quick Blessings power-up
	player.throw_stamina = 0.0
	var boosted := 0
	for i in 60:
		if player.try_throw():
			boosted += 1
		await frames(1)
	check(boosted >= 8, "Quick Blessings power-up allows near-nonstop throwing (%d in 1 s from empty)" % boosted)
	player.powerups.clear()
	# Holding the button down only throws slowly; Quick Blessings makes it a machine gun.
	var held := [0]
	var count_held := func(_kind): held[0] += 1
	player.threw.connect(count_held)
	for quick in [false, true]:
		if quick:
			player.apply_powerup("quick_throw")
		player.throw_stamina = player.THROW_STAMINA_MAX
		held[0] = 0
		player.test_input = {"shoot": true}
		await frames(120)
		player.test_input = {}
		await frames(2)
		if quick:
			check(held[0] >= 12, "Quick Blessings: holding the button fires like a machine gun (%d in 2 s)" % held[0])
		else:
			check(held[0] >= 2 and held[0] <= 5, "holding the button throws slowly (%d in 2 s)" % held[0])
	player.threw.disconnect(count_held)
	player.powerups.clear()

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
	# Rebinding keys: any action to any key or mouse button, remembered next time.
	var KB = load("res://scripts/keybinds.gd")
	var melee_was: String = KB.current("melee")
	main._open_controls()
	main._start_rebind("melee")
	var press := InputEventKey.new()
	press.physical_keycode = KEY_V
	press.pressed = true
	main._input(press)
	check(KB.key_name("melee") == "V" and InputMap.action_has_event("melee", KB.make_event("key:%d" % KEY_V)), "rebind melee to V")
	main._start_rebind("jump")
	var mouse4 := InputEventMouseButton.new()
	mouse4.button_index = MOUSE_BUTTON_XBUTTON1
	mouse4.pressed = true
	main._input(mouse4)
	check(KB.key_name("jump") == "Mouse 4", "...or a mouse button (jump on Mouse 4)")
	main._start_rebind("sneak")
	main._input(press)   # V again: sneak takes it, melee gives it up
	check(KB.key_name("sneak") == "V" and KB.current("melee") == "", "...a key moves to the new action instead of doing two things")
	main._close_controls()
	KB.setup({})
	main._load_settings()
	check(KB.key_name("sneak") == "V" and KB.key_name("jump") == "Mouse 4", "...and your keys are remembered next time")
	check("Mouse 4" in main._controls_text(), "...and the on-screen help uses your keys")
	KB.setup({})
	main._save_settings()
	check(KB.current("melee") == melee_was, "reset to defaults")

	# Maps are plain data, and anything odd in a map file is cleaned out.
	var MD = load("res://scripts/map_data.gd")
	var arena: Dictionary = MD.load_file("res://tests/test_map.json")
	check(arena.get("name") == "Test Arena", "a map file loads")
	check(not arena["pieces"].any(func(p): return p["type"] == "rocket_launcher"), "...unknown pieces are dropped")
	var huge: Array = arena["pieces"].filter(func(p): return p["type"] == "block" and absf(p["pos"][0]) > 400)
	check(huge.size() == 1 and huge[0]["size"][0] >= 0.05, "...wild numbers are clamped")
	check(MD.from_text("this is not a map").is_empty() and MD.from_text("[1, 2, 3]").is_empty(), "...garbage isn't a map")
	check(MD.fingerprint(arena) == MD.fingerprint(MD.from_text(MD.to_text(arena))), "...saving and loading gives the same map")
	main.load_map(arena, "res://tests/test_map.json")
	main.start_practice()
	await frames(10)
	var placed: Array = main.props.filter(func(p): return is_instance_valid(p) and p.get_meta("prop_type") in ["barrel", "pickle"] and p.global_position.distance_to(Vector3(6, 0, -6)) < 0.1)
	check(placed.size() == 1, "...props placed by hand are there")
	check(main.props.size() == 2 + 12, "...plus the map's random props (%d)" % main.props.size())
	check(main.MAP_HALF == 16.0 and main.shrine == null and not main.near_shrine(Vector3.ZERO), "...its size, and no shrine if it has none")
	# Random props sit on top of ground blocks, not buried in them (Wife's notes, Nov 26)
	var graveled: Dictionary = arena.duplicate(true)
	graveled["pieces"].append({"type": "ground", "look": 0, "pos": [0, 0, 0], "size": [40, 0.6, 40], "rot": [0, 20, 0]})
	main.load_map(graveled, "")
	main.start_practice()
	await frames(10)
	var buried: Array = main.props.slice(main.PLACED_PROPS.size()).filter(func(p): return is_instance_valid(p) and absf(p.global_position.y - 0.6) > 0.01)
	check(buried.is_empty(), "random props stand on top of a ground block (%d not)" % buried.size())
	main.load_map(MD.load_file(MD.BUILT_IN[0]), MD.BUILT_IN[0])
	main.start_practice()
	await frames(10)
	check(main.shrine != null and main.props.size() == 45, "back to the Playground")

	# Creative mode: build a map, change it, undo, save it, open it, test it.
	main.open_editor()
	await frames(5)
	var ed = main.editor
	check(main.mode == "editor" and ed.active() and ed.map["pieces"].size() == 2, "Creative opens on an empty map (just the two starts)")
	ed.set_setting("name", "Claude Test Build")
	var bi: int = ed.place("block", Vector3(4, 0, 4))
	check(ed.map["pieces"][bi]["type"] == "block" and is_equal_approx(ed.map["pieces"][bi]["pos"][1], 1.0), "...a block sits on the ground where you click")
	var pi: int = ed.place("prop:pickle", Vector3(-3, 0, 2))
	check(ed.map["pieces"][pi]["prop"] == "pickle", "...props can be placed")
	ed.place("shrine", Vector3(0, 0, 8))
	var shrine_count := func(): return ed.map["pieces"].filter(func(q): return q["type"] == "shrine").size()
	ed.place("shrine", Vector3(0, 0, -8))
	check(shrine_count.call() == 1, "...only one shrine: placing another moves it")
	# Move along X only, with snapping: drive the drag with a ray from above.
	ed.select(bi)
	ed.begin("move")
	ed.set_axis("x")
	var cam_from := Vector3(4, 30, 4)
	ed._drag_t0 = ed._along_axis(Vector3(4, 1, 4), Vector3.RIGHT, cam_from, Vector3.DOWN)
	ed.drag_update(Vector3(7.3, 30, 9), Vector3.DOWN, Vector2.ZERO)
	ed._end_drag(true)
	var bp: Array = ed.map["pieces"][bi]["pos"]
	check(is_equal_approx(bp[0], 7.5) and is_equal_approx(bp[2], 4.0) and is_equal_approx(bp[1], 1.0), "...moving on one axis only changes that axis, snapped (%s)" % str(bp))
	ed.begin("rotate")
	ed.drag_update(Vector3.ZERO, Vector3.DOWN, ed._drag_mouse + Vector2(88, 0))
	ed._end_drag(true)
	check(is_equal_approx(ed.map["pieces"][bi]["rot"][1], 45.0), "...rotating snaps to 15 degree steps (%s)" % str(ed.map["pieces"][bi].get("rot")))
	ed.begin("scale")
	ed.set_axis("y")
	ed.drag_update(Vector3.ZERO, Vector3.DOWN, ed._drag_mouse + Vector2(167, 0))
	ed._end_drag(true)
	var bs: Array = ed.map["pieces"][bi]["size"]
	check(is_equal_approx(bs[1], 4.0) and is_equal_approx(bs[0], 4.0), "...resizing one axis (%s)" % str(bs))
	ed.begin("move")
	ed.drag_update(Vector3(20, 30, 20), Vector3.DOWN, Vector2.ZERO)
	ed._end_drag(false)
	check(is_equal_approx(ed.map["pieces"][bi]["pos"][0], 7.5), "...Esc cancels a move")
	# Grabbing with the mouse: the pickle slides over whatever's under the cursor, even up onto the block.
	ed.select(pi)
	await frames(2)   # (the physics world catches up with the resized block)
	ed.grab(Vector3(-3, 30, 2), Vector3.DOWN)
	ed.drag_update(Vector3(-1.2, 30, 6.3), Vector3.DOWN, Vector2.ZERO)
	var gp: Array = ed.map["pieces"][pi]["pos"]
	check(is_equal_approx(gp[0], -1.0) and is_equal_approx(gp[2], 6.5) and absf(gp[1]) < 0.05, "...dragging a piece with the mouse moves it across the ground (%s)" % str(gp))
	var block_top: float = ed.map["pieces"][bi]["pos"][1] + ed.map["pieces"][bi]["size"][1] / 2.0
	ed.drag_update(Vector3(7.5, 30, 4), Vector3.DOWN, Vector2.ZERO)
	gp = ed.map["pieces"][pi]["pos"]
	check(is_equal_approx(gp[1], block_top), "...and up onto a block's roof (%s, roof at %.2f)" % [str(gp), block_top])
	ed._end_drag(true)
	ed.undo()
	check(ed.map["pieces"][pi]["pos"] == [-3.0, 0.0, 2.0], "...and undo puts it back")
	var n_before: int = ed.map["pieces"].size()
	ed.select(bi)
	var di: int = ed.duplicate_selected()
	check(di == n_before and ed.map["pieces"].size() == n_before + 1, "...copy")
	ed.select(di)
	ed.delete_selected()
	check(ed.map["pieces"].size() == n_before, "...delete")
	ed.undo()
	check(ed.map["pieces"].size() == n_before + 1, "...undo brings it back")
	ed.redo()
	check(ed.map["pieces"].size() == n_before, "...redo removes it again")
	ed.select(0)
	ed.delete_selected()
	check(ed.map["pieces"].size() == n_before, "...the starts can't be deleted")
	ed.set_value(pi, "pos", Vector3(-3.25, 0, 2.5))
	check(ed.map["pieces"][pi]["pos"] == [-3.25, 0.0, 2.5], "...exact numbers from the panel")
	ed.set_setting("size", 20.0)
	check(main.MAP_HALF == 20.0, "...map size changes the walls")
	var saved_path: String = MD.user_path_for("Claude Test Build")
	DirAccess.remove_absolute(saved_path)
	check(ed.save() and FileAccess.file_exists(saved_path) and not ed.dirty, "...saves to your maps folder")
	var listed: bool = MD.list_maps().any(func(e): return e["path"] == saved_path)
	check(listed, "...and shows up in the list of maps")
	var reread: Dictionary = MD.load_file(saved_path)
	check(MD.fingerprint(reread) == MD.fingerprint(ed.map), "...what's saved is exactly what was built")
	ed.new_map()
	check(ed.map["pieces"].size() == 2, "...New starts over")
	check(ed.open(saved_path) and ed.map["name"] == "Claude Test Build" and ed.map["pieces"].size() == n_before, "...and Open brings it back")
	ed.test_play()
	await frames(10)
	check(main.mode == "practice" and not ed.active() and main.MAP_HALF == 20.0 and main.shrine != null, "...Test play runs a round on it")
	var test_pickle: bool = main.props.any(func(q): return is_instance_valid(q) and q.get_meta("prop_type") == "pickle" and q.global_position.distance_to(Vector3(-3.25, 0, 2.5)) < 0.1)
	check(test_pickle, "...with the props placed where you put them")
	main.back_to_editor()
	await frames(3)
	check(main.mode == "editor" and ed.active() and ed.map["name"] == "Claude Test Build", "...and back to building")
	main.editor._try_exit()
	main.editor._try_exit()
	await frames(3)
	check(main.mode == "menu" and not ed.active() and main.round_root == null and main.MAP_HALF == 28.0 and main.player.camera.current, "...leaving goes back to the menu and the Playground (%s %s %s)" % [main.mode, ed.active(), main.MAP_HALF])
	DirAccess.remove_absolute(saved_path)

	# A couple of names get swapped for a better one; everything else is left alone.
	var N = load("res://scripts/net_game.gd")
	var swapped := true
	for n in ["Dick Bubble", "xXDickBubbleXx", "dick bbl"]:
		swapped = swapped and N.better_name(n) in N.BETTER_NAMES
	check(swapped, "the swapped names get a better one")
	var kept := true
	for n in ["Abe", "Dickens", "Bubbles", "Big Bubble", "Benedict", "Müller", "Šárka"]:
		kept = kept and N.better_name(n) == n and N.displayable_name(n) == n
	check(kept, "...normal names are left alone")

	# ---- Game rules (Ted, Nov 26): Standard / Custom, anything from outside cleaned ----
	var GR = load("res://scripts/game_rules.gd")
	check(GR.is_standard(GR.standard()) and GR.summary(GR.standard()) == "Standard rules", "standard rules read as standard")
	var wild: Dictionary = GR.clean({"gravity": 99, "damage": "lots", "splashes": -4, "powerups": {"heal": false, "bogus": true}, "extra": 1})
	check(wild["gravity"] == 2.0 and wild["damage"] == 1.0 and wild["splashes"] == 0 and not wild.has("extra")
			and not wild["powerups"].has("bogus") and wild["powerups"]["heal"] == false, "rules from outside are clamped and cleaned")
	var keep_rules: Dictionary = GR.current
	GR.current = wild
	check(GR.allowed(["fast_hatred", "heal", "heal", "vanish"]) == ["fast_hatred", "vanish"], "a switched-off power-up never turns up")
	check(GR.summary(wild).begins_with("Custom:"), "custom rules say what's different")
	GR.current = keep_rules
	main.rules_use_custom = false
	check(GR.is_standard(main.active_rules()), "the game plays Standard unless Custom is picked")
	# Nov 27: tabs, and every rule has its control and does something
	var Skills = load("res://scripts/skills.gd")
	var odd: Dictionary = GR.clean({"weather": 99, "still_taunt": 1, "cd_fire": 2.0, "stamina": 3.0})
	check(odd["weather"] == GR.CHOICES["weather"].size() - 1 and odd["still_taunt"] == 10.0 and odd["cd_fire"] == 2.0
			and not odd.has("stamina"), "choice rules and new rules are cleaned too (the old combined stamina rule is gone)")
	main._open_rules()
	await frames(2)
	var tab_box: TabContainer = main.rules_panel.find_children("*", "TabContainer", true, false)[0]
	var missing: Array = GR.RULES.keys().filter(func(k): return not main._rules_inputs.has(k))
	check(tab_box.get_tab_count() == GR.TABS.size() and missing.is_empty(),
			"the Custom rules window has %d tabs and a control for every rule (missing: %s)" % [tab_box.get_tab_count(), missing])
	var bg = main.rules_panel.get_theme_stylebox("panel")
	check(bg is StyleBoxFlat and (bg as StyleBoxFlat).bg_color.a > 0.95, "...on a solid background")
	main._close_rules()
	GR.current = GR.clean({"cd_fire": 2.0, "hc_fear": 0.5, "teleport_range": 1.5, "fire_radius": 2.0})
	check(is_equal_approx(Skills.cooldown("fire"), Skills.SKILLS["fire"]["cooldown"] * 2.0)
			and is_equal_approx(Skills.hatred_cost("fear"), Skills.SKILLS["fear"]["hatred"] * 0.5)
			and is_equal_approx(Skills.teleport_range(), Skills.TELEPORT_RANGE * 1.5), "custom rules change skill cooldowns, costs and reach")
	GR.current = keep_rules
	main.rules_use_custom = false

	print("\n%s: %d failure(s)" % ["ALL PASSED" if failures == 0 else "FAILED", failures])
	quit(1 if failures else 0)
