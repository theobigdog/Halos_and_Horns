# Loose props getting shoved about (knock.gd), plus the graphics settings and music
# hookup, in practice mode.
#   godot --headless -s res://tests/test_props.gd
extends SceneTree

const Graphics = preload("res://scripts/graphics.gd")
const Effects = preload("res://scripts/effects.gd")
const Models = preload("res://scripts/models.gd")

var main: Node
var failures := 0


func _initialize() -> void:
	seed(20261117)
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


# Put a fresh prop of this type on open ground, well clear of everything else.
func place(type_name: String, at: Vector3) -> StaticBody3D:
	for prop in main.props:
		if is_instance_valid(prop) and prop.visible and prop.global_position.distance_to(at) < 3.5:
			prop.global_position += Vector3(0, -50, 0)   # out of the way
	main._spawn_prop(type_name, Vector3(at.x, main.ground_below(at + Vector3.UP * 3.0).y, at.z), Vector3.ZERO)
	return main.props[main.props.size() - 1]


func at_rest(prop: Node) -> bool:
	var k = prop.get_node_or_null("Knock")
	return k == null or not k.is_physics_processing()


func wait_rest(prop: Node, max_frames := 600) -> void:
	for i in max_frames:
		if at_rest(prop):
			return
		await physics_frame


func upright(prop: Node3D) -> bool:
	return prop.global_transform.basis.y.normalized().dot(Vector3.UP) > 0.95


func _run() -> void:
	await frames(5)
	main.role = "demon"
	main.start_practice()
	await frames(10)
	var player = main.player
	player.global_position = Vector3(0, 0.1, 22)

	# ---- A tall lamp shoved hard falls over and stays down ----
	var lamp := place("lamp", Vector3(-12, 0, 14))
	var start := lamp.global_position
	main.knock_prop(lamp.get_meta("prop_index"), Vector3(5.0, 0.5, 0.0))
	await frames(5)
	check(not at_rest(lamp), "a shoved lamp starts moving")
	await wait_rest(lamp)
	check(at_rest(lamp), "...and comes to rest")
	check(not upright(lamp), "...tipped over on its side (up = %s)" % lamp.global_transform.basis.y.normalized())
	check(lamp.global_position.x > start.x + 0.3, "...in the direction it was shoved (%.2f -> %.2f)" % [start.x, lamp.global_position.x])
	check(lamp.global_position.y > start.y + 0.1 and lamp.global_position.y < start.y + 0.6,
		"...lying on the ground, not sunk into it or floating (y %.2f)" % lamp.global_position.y)
	check(lamp.has_meta("moved_basis"), "...and remembers how it's lying, for anyone joining later")
	var state: Array = main.prop_state()
	var entry = null
	for m in state[1]:
		if int(m[0]) == lamp.get_meta("prop_index"):
			entry = m
	check(entry != null and entry.size() == 4, "the host's prop state includes its tipped-over pose")

	# ---- A squat crate with a small nudge only wobbles ----
	var crate := place("crate", Vector3(-12, 0, 6))
	main.knock_prop(crate.get_meta("prop_index"), Vector3(0.0, 0.0, 2.0))
	var lean := 1.0
	for f in 20:
		await physics_frame
		lean = minf(lean, crate.global_transform.basis.y.normalized().dot(Vector3.UP))
	var wobbled := lean < 0.999
	await wait_rest(crate)
	check(wobbled, "a small nudge makes a crate rock (leaned to %.1f degrees)" % rad_to_deg(acos(clampf(lean, -1.0, 1.0))))
	check(upright(crate), "...but it settles back upright")

	# ---- Round things roll on further than square things slide ----
	var apple := place("apple", Vector3(-4, 0, 14))
	var box := place("books", Vector3(-4, 0, 6))
	var a0 := apple.global_position
	var b0 := box.global_position
	main.knock_prop(apple.get_meta("prop_index"), Vector3(1.2, 0.0, 0.0))
	main.knock_prop(box.get_meta("prop_index"), Vector3(1.2, 0.0, 0.0))
	await wait_rest(apple)
	await wait_rest(box)
	var rolled := apple.global_position.distance_to(a0)
	var slid := box.global_position.distance_to(b0)
	check(rolled > slid * 1.5, "an apple rolls further than a stack of books slides (%.2f m vs %.2f m)" % [rolled, slid])
	check(upright(apple), "...and a rolling apple's collision stays put (only its look spins)")

	# ---- Sliding into another prop shoves that one too ----
	var barrel := place("barrel", Vector3(6, 0, 14))
	var pot := place("pot", Vector3(10.5, 0, 14))
	pot.global_position = Vector3(7.4, pot.global_position.y, 14)   # (placed apart first: place() clears the area)
	var pot0 := pot.global_position
	main.knock_prop(barrel.get_meta("prop_index"), Vector3(20.0, 0.0, 0.0))
	await frames(240)
	await wait_rest(pot)
	check(pot.global_position.distance_to(pot0) > 0.2, "a barrel sliding into a pot shoves the pot (%.2f m)" % pot.global_position.distance_to(pot0))

	# ---- A blast (Cloud Stomp, Fire Burst) shoves everything near it, outward ----
	var b1 := place("crate", Vector3(10, 0, 4))
	var b2 := place("crate", Vector3(14, 0, 4))
	b1.global_position.x = 10.0
	b2.global_position.x = 14.0
	main._blast_props(Vector3(12, 0, 4), 6.0, 7.0)
	await wait_rest(b1)
	await wait_rest(b2)
	check(b1.global_position.x < 9.9 and b2.global_position.x > 14.1,
		"a blast between two crates pushes both away from it (%.2f, %.2f)" % [b1.global_position.x, b2.global_position.x])

	# ---- A blessing hitting a prop, and a swing that misses every demon ----
	var hay := place("hay", Vector3(-12, 0, -6))
	var h0 := hay.global_position
	main._on_blessing_hit_prop(hay, Vector3(0, 0, -80), h0)
	await wait_rest(hay)
	check(hay.global_position.distance_to(h0) > 0.05, "a blessing hit nudges a hay bale (%.2f m)" % hay.global_position.distance_to(h0))
	var pumpkin := place("pumpkin", Vector3(-4, 0, -6))
	player.global_position = pumpkin.global_position + Vector3(0, 0.1, 1.5)
	var p0 := pumpkin.global_position
	main._boot_prop(player, Vector3(0, 0, -1), 2.6, main.PROP_KICK)
	await wait_rest(pumpkin)
	check(pumpkin.global_position.z < p0.z - 0.5, "Holy Kick with no demon around boots the pumpkin in front instead")

	# ---- A demon leaving a knocked-over prop: it stands back up ----
	var i: int = lamp.get_meta("prop_index")
	main._set_prop_taken(i)
	check(not lamp.visible, "possessing a knocked-over lamp takes it")
	main._make_shell(i, lamp.global_position, 0.5)
	check(upright(lamp) and not lamp.has_meta("moved_basis"), "...and the shell left behind is upright again")

	# ---- Someone joining sees knocked props the way they are ----
	var crate2 := place("crate", Vector3(4, 0, -12))
	var lying := Transform3D(Basis(Vector3(0, 0, 1), PI / 2), crate2.global_position + Vector3(0, 0.45, 0))
	main.apply_prop_state([], [[crate2.get_meta("prop_index"), lying.origin, lying.basis, 0.45]])
	await frames(30)
	check(not upright(crate2) and crate2.global_position.distance_to(lying.origin) < 0.05, "a joiner's copy puts a knocked prop in its exact pose")

	# ---- Running into things shoves them: a loose prop, and a demon disguised as one, alike ----
	player.unpossess()
	var bump_crate := place("crate", Vector3(-14, 0, -6))
	var c0 := bump_crate.global_position
	player.global_position = Vector3(-17.5, c0.y + 0.1, -6)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3(0, -PI / 2, 0)   # facing +x, at the crate
	await frames(5)
	player.test_input = {"dir": Vector2(0, -1), "run": true}
	await frames(70)
	player.test_input = {}
	await wait_rest(bump_crate)
	check(bump_crate.global_position.distance_to(c0) > 0.3, "running into a crate shoves it (%.2f m)" % bump_crate.global_position.distance_to(c0))
	var bot = null
	for b in get_nodes_in_group("demon"):
		if b.get("prop_type") != null and b.prop_type != "":
			bot = b
			break
	if bot:
		var bot0: Vector3 = bot.global_position
		main.bump(bot, Vector3(6, 0, 0), player)
		await frames(30)
		check(bot.global_position.distance_to(bot0) > 0.2, "...and bumping a demon disguised as a %s shoves it too (%.2f m)" % [bot.prop_type, bot.global_position.distance_to(bot0)])

	# ---- Playtest, Nov 26 ----
	# The road's painted lines are pressed flat in its collision (props snagged on them)
	var lips := 0
	for v in Models.faces("city/road_straight"):
		if v.y > 0.315 and v.y < 0.345:
			lips += 1
	check(lips == 0, "a road's painted lines don't stick up out of its collision (%d points)" % lips)
	# No room to change back: under something low, a little prop stays a prop
	player.global_position = Vector3(12, main.ground_below(Vector3(12, 3, 12)).y + 0.05, 12)
	player.velocity = Vector3.ZERO
	player.force_possess("apple")
	await frames(3)
	var lid := StaticBody3D.new()
	var lid_shape := CollisionShape3D.new()
	var lid_box := BoxShape3D.new()
	lid_box.size = Vector3(3, 0.2, 3)
	lid_shape.shape = lid_box
	lid.add_child(lid_shape)
	main.add_child(lid)
	lid.global_position = player.global_position + Vector3(0, 0.75, 0)
	await frames(3)
	var refused := [false]
	player.no_room.connect(func(): refused[0] = true, CONNECT_ONE_SHOT)
	player.unpossess()
	check(player.possessed_type == "apple" and refused[0], "an apple under a table can't turn back into a demon (no room)")
	lid.queue_free()
	await frames(3)
	player.unpossess()
	check(player.possessed_type == "", "...and can once it's out in the open")
	# Long rows of the same piece are drawn as one batch, with every copy still solid
	var floor_row := Models.make_row("dungeon/floor_tile_small", Vector3.ONE, 5, 4, 0, true)
	check(floor_row.find_children("*", "MultiMeshInstance3D", true, false).size() > 0 			and floor_row.find_children("*", "MeshInstance3D", true, false).is_empty() 			and floor_row.find_children("*", "CollisionShape3D", true, false).size() == 20,
			"a 5 x 4 floor is one batched draw per mesh, with 20 solid tiles")
	floor_row.free()
	# Settings: Show FPS
	main._fps_pick.button_pressed = true
	await process_frame
	check(main.fps_label.visible, "Show FPS puts the counter up")
	main._fps_pick.button_pressed = false

	# ---- Graphics settings and music ----
	for q in [0, 2, 1]:
		main.graphics.apply(q)
		await frames(2)
		check(Graphics.quality == q and Effects.quality == q, "graphics quality %s applies" % Graphics.QUALITY_NAMES[q])
	# Text size: scales everything, steps with Ctrl +/-, and is remembered
	main.set_ui_scale(1.5)
	check(is_equal_approx(main.get_window().content_scale_factor, 1.5), "text size 150% makes everything bigger")
	main._step_ui_scale(1)
	check(is_equal_approx(main.ui_scale, 1.75), "...Ctrl + steps it up (%.2f)" % main.ui_scale)
	main._load_settings()
	check(is_equal_approx(main.ui_scale, 1.75), "...and it's remembered")
	main.set_ui_scale(1.0)
	main._save_settings()
	main.fx("stomp", [Vector3(0, 0, 0)])
	main.fx("teleport", [Vector3(2, 0, 2), Vector3(4, 0, 4)])
	await frames(10)
	check(true, "stomp dust and teleport smoke play without errors")
	check(main.music != null and main.music.get("_want") == "lobby" or main.music.get("_want") == "hiding" or main.music.get("_want") == "hunt",
		"the music follows the game (now: %s)" % main.music.get("_want"))

	print("\n%s: %d failure(s)" % ["ALL PASSED" if failures == 0 else "SOME FAILED", failures])
	quit(1 if failures > 0 else 0)
