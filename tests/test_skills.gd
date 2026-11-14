# Automated test of flying, possess vs transform, and the angel tools, in practice mode.
#   godot --headless -s res://tests/test_skills.gd
extends SceneTree

const Skills = preload("res://scripts/skills.gd")
const PropLib = preload("res://scripts/prop_library.gd")

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


# Stand a few meters from target with a clear crosshair line to it.
func aim_at(player, target: Node3D, aim_height: float, dist := 3.5) -> bool:
	var aim_point := target.global_position + Vector3.UP * aim_height
	for i in 16:
		var angle := TAU * i / 16.0
		var spot := target.global_position + Vector3(cos(angle), 0, sin(angle)) * dist
		player.global_position = spot + Vector3.UP * 0.1
		player.velocity = Vector3.ZERO
		player.look_at(Vector3(aim_point.x, player.global_position.y, aim_point.z))
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
	player.hatred_regen_multiplier = 6.0   # the future fast-Hatred power-up
	player.test_input = {"fly": true}
	await frames(660)
	check(player.flying, "with fast Hatred regen you can fly endlessly (11 s and counting)")
	player.hatred_regen_multiplier = 1.0
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

	# ---- Per-form health and speed ----
	check(PropLib.max_hp("books") < PropLib.max_hp("") and PropLib.max_hp("") < PropLib.max_hp("hay"),
			"small props have less health than a demon, big ones more")
	var form_speeds := {}
	for form in ["books", "", "hay"]:
		if form == "":
			player.unpossess()
		else:
			player.force_possess(form)
		player.global_position = Vector3(-20, 0.1, 20)
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
	player.loadout["angel"] = ["chicken", "vacuum"]
	var bot = get_nodes_in_group("demon")[0]

	# Chicken: near a demon it alarms, far away it doesn't.
	main.authority_skill(player, 0, "chicken", player.global_position, Vector3.FORWARD, bot.global_position + Vector3(2, 0, 0), -1)
	main.authority_skill(player, 0, "chicken", player.global_position, Vector3.FORWARD, Vector3(0, 0, -26), -1)
	await frames(30)
	var near_c = main.chickens.get(1)
	var far_c = main.chickens.get(2)
	check(near_c != null and near_c.alarmed, "a chicken near a hidden demon squawks")
	check(far_c != null and not far_c.alarmed, "a chicken with no demon nearby stays calm")
	check(near_c != null and near_c._bubble.visible, "...and shows its detection bubble")
	check(far_c != null and not far_c._bubble.visible, "...a calm chicken shows no bubble, it's just a chicken")

	# Knock the calm chicken down the "hallway" with a blessing.
	if far_c != null:
		var c_start: Vector3 = far_c.global_position
		var shot = preload("res://scripts/projectile.gd").new()
		shot.velocity = Vector3(30, 0, 0)
		shot.shooter = player
		main.add_child(shot)
		shot.global_position = c_start + Vector3(-3, 0.4, 0)
		await frames(150)
		var moved: float = far_c.global_position.x - c_start.x
		check(moved > 6.0, "a blessing sends the chicken skidding (%.1f m)" % moved)
		check(absf(far_c.velocity.x) < 0.3, "...and it slides to a stop")
		check(main._auth_chickens.has(2) and main._auth_chickens[2]["pos"].distance_to(far_c.global_position) < 0.5,
				"...and it keeps watching from where it landed")

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
	var health_before: int = bot2.health
	player.melee_cd = 0.0
	player.melee()
	await frames(2)
	check(bot2.health == health_before - Skills.MELEE_DAMAGE, "F melee hits a demon (%d -> %d)" % [health_before, bot2.health])

	# Grappling hook: hits a demon (damage + pull) ...
	var bot3 = get_nodes_in_group("demon")[2]
	player.loadout["angel"] = ["grapple", "leap"]
	check(await aim_at(player, bot3, 0.3, 8.0), "lined up a demon 8 m away")
	var hp3: int = bot3.health
	var d3: float = bot3.global_position.distance_to(player.global_position)
	player.use_skill(0)
	await frames(60)
	check(bot3.health == hp3 - Skills.GRAPPLE_DAMAGE, "the hook damages a demon")
	check(bot3.global_position.distance_to(player.global_position) < d3 - 3.0, "...and drags it to us")

	# ... or zips us up to the roof of a building.
	player.skill_cd.clear()
	player.global_position = Vector3(8, 0.1, 18)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	await frames(5)
	var eye: Vector3 = player.camera.global_position
	var roof_edge := Vector3(8, 3.9, 11)   # the 4 m tall building at (8, 8)
	player.pivot.rotation.x = atan2(roof_edge.y - eye.y, eye.z - roof_edge.z)
	await frames(2)
	check(player.use_skill(0), "fired the hook at the building")
	await frames(120)
	check(player.global_position.y > 3.8 and player.is_on_floor(),
			"zipped up and landed on the roof (y %.1f)" % player.global_position.y)

	# Holy Leap
	player.global_position = Vector3(-20, 0.1, -20)
	player.velocity = Vector3.ZERO
	await frames(20)
	player.skill_cd.clear()
	var y0: float = player.global_position.y
	check(player.use_skill(1), "Holy Leap")
	var peak := y0
	for i in 90:
		await frames(1)
		peak = maxf(peak, player.global_position.y)
	check(peak - y0 > 3.5, "a magnificent jump (%.1f m)" % (peak - y0))
	check(not player.use_skill(1), "skills have cooldowns")

	print("\n%s: %d failure(s)" % ["ALL PASSED" if failures == 0 else "FAILED", failures])
	quit(1 if failures else 0)
