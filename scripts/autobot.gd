# Testing only: drives the local player automatically so whole online matches can
# be played with several copies of the game and no humans. Turned on with --autobot.
#   Demons wander off and possess a random prop, then taunt now and then.
#   Angels walk toward the nearest demon and throw at it.
# Prints "BOT: ..." lines that the multiplayer test reads.
# Options: --skills=chicken,vacuum (angel loadout). --cheat=teleport,fly tries to jump
# out of bounds once, and/or to fly forever (the host should refuse both).
extends Node

const PropLib = preload("res://scripts/prop_library.gd")

var main
var options := {}
var _wander_time := 0.0
var _wander_dir := Vector2.ZERO
var _hidden := false
var _taunt_timer := 3.0
var _last_role := ""
var _cheat_done := false
var _stuck_time := 0.0
var _last_pos := Vector3.ZERO
var _strafe_time := 0.0
var _strafe_dir := 1.0
var _reported_names := false
var _role_time := 0.0
var _rounds_started := 0
var _quitting := false
var _logged_end := false
var _misses := 0               # throws since our last confirmed hit
var _connected := false
var _loadout_sent := false
var _fly_time := 0.0
var _possess_target: Node3D = null
var _possess_tries := 0.0
var _used := {}                # skills we've already logged using


func log_line(text: String) -> void:
	print("BOT %s: %s" % [main.name_edit.text, text])


func _physics_process(delta: float) -> void:
	var p = main.player
	if not _connected:
		_connected = true
		p.hit_confirmed.connect(func(): _misses = 0)
	if main.net and not _loadout_sent:
		_loadout_sent = true
		if options.has("skills"):
			main.loadout["angel"] = Array(options["skills"].split(","))
		main.loadout["demon"] = ["possess", "fly"]
		main._apply_loadout()
	# Host: start once enough players are in (--autostart=N).
	if main.net and main.net.is_host and options.has("autostart") \
			and _rounds_started < int(options.get("rounds", "1")) \
			and main.net.can_start() and main.net.peers.size() >= int(options["autostart"]):
		_rounds_started += 1
		log_line("starting the round with %d players" % main.net.peers.size())
		main.net.start_round()
	# Quit a couple of seconds after the round ends (--quit-after-round).
	if main.state == main.State.ENDED and not _logged_end:
		_logged_end = true
		log_line("round over: " + main.center_label.text.split("\n")[0])
	if main.state != main.State.ENDED:
		_logged_end = false
	if options.has("quit-after-round") and main.state == main.State.ENDED and not _quitting:
		_quitting = true
		if main.net and main.net.is_host:
			log_line("host blocked: " + str(main.net.cheat_log))
		get_tree().create_timer(2.0).timeout.connect(func(): get_tree().quit())
	# Log every side switch, even one that happens as the round ends.
	if main.mode == "online" and main.state != main.State.LOBBY and main.role != _last_role:
		_last_role = main.role
		_hidden = false
		_reported_names = false
		_role_time = 0.0
		_fly_time = 0.0
		_possess_target = null
		_possess_tries = 0.0
		_wander_time = randf_range(1.5, 3.0)
		var a := randf() * TAU
		_wander_dir = Vector2(cos(a), sin(a))
		log_line("now playing as " + main.role)
	if not main.in_online_round():
		p.test_input = {}
		if main.state == main.State.LOBBY:
			_last_role = ""
		return
	_role_time += delta
	if not _reported_names and _role_time > 1.0:   # wait until everyone's side is known
		_reported_names = true
		var shown := []
		for eid in main.net.remotes:
			var r = main.net.remotes[eid]
			shown.append("%s=%s" % [r.team if r.team != "" else "?", r.player_name if r.player_name != "" else "<hidden>"])
		log_line("as %s, names I can see: %s" % [main.role, ", ".join(shown)])
		var roster := []
		for row in main.scoreboard_rows:
			roster.append("%s(%s,%dms,%s)" % [row[0], row[1], row[2], "+".join(row[3])])
		log_line("roster: %s | my ping %d" % [" ".join(roster), main.net.my_ping()])
	_taunt_timer -= delta
	if _taunt_timer <= 0.0:
		_taunt_timer = randf_range(6.0, 10.0)
		p._taunt_cooldown = 0.0
		p.taunt(randf() < 0.3)
	if "teleport" in options.get("cheat", "") and not _cheat_done and main.state == main.State.HIDING \
			and _role_time > 1.0:
		_cheat_done = true
		log_line("trying to teleport out of bounds")
		p.global_position = Vector3(main.MAP_HALF + 15.0, 1.0, 0.0)
		get_tree().create_timer(1.0).timeout.connect(func():
			log_line("1 s after cheat, position x = %.1f" % p.global_position.x))
	if "fly" in options.get("cheat", "") and main.role == "demon" and main.state == main.State.HIDING \
			and _role_time > 2.5:
		p.hatred = p.HATRED_MAX   # a hacked client with endless Hatred
		p.test_input = {"fly": true}
		if not _used.has("flycheat"):
			_used["flycheat"] = true
			log_line("cheating: flying forever")
		return
	if main.role == "demon":
		_play_demon(delta, p)
	else:
		_play_angel(delta, p)


func _play_demon(delta: float, p) -> void:
	if _hidden:
		p.test_input = {}
		return
	_fly_time += delta
	if _fly_time < 0.8:
		p.test_input = {"fly": true}   # a little flight first
		if not _used.has("fly"):
			_used["fly"] = true
			log_line("flying")
		return
	_wander_time -= delta
	if _wander_time > 0.0:
		p.rotation.y = 0.0
		p.test_input = {"dir": _wander_dir}
		return
	p.test_input = {}
	# Try to POSSESS the nearest real prop; fall back to transforming into a copy.
	if _possess_target == null:
		var best := INF
		for prop in main.props:
			if is_instance_valid(prop) and prop.is_in_group("prop"):
				var d: float = prop.global_position.distance_to(p.global_position)
				if d < best and d < 9.0:
					best = d
					_possess_target = prop
	if _possess_target and is_instance_valid(_possess_target) and _possess_tries < 1.0:
		_possess_tries += delta
		if not p.first_person["demon"]:
			p.toggle_view()   # line it up through the eyes, not over the shoulder
		_aim(p, _possess_target.global_position + Vector3.UP * 0.2)
		if p._hover_prop == _possess_target and p.use_skill(0):
			_hidden = true
			log_line("possessing a real " + _possess_target.get_meta("prop_type"))
		return
	var types := PropLib.type_names()
	p.force_possess(types[randi() % types.size()])
	_hidden = true
	log_line("hiding as a copy of a " + p.possessed_type)


func _aim(p, point: Vector3) -> void:
	var to: Vector3 = point - p.global_position
	p.rotation.y = atan2(-to.x, -to.z)
	var eye: Vector3 = p.camera.global_position
	var flat := Vector2(point.x - eye.x, point.z - eye.z).length()
	p.pivot.rotation.x = clampf(atan2(point.y - eye.y, flat), -1.4, 1.2)


func _play_angel(delta: float, p) -> void:
	if p.frozen or options.has("lazy"):
		p.test_input = {}
		return
	var target = null
	var best := INF
	for eid in main.net.remotes:
		var r = main.net.remotes[eid]
		if r.role == "demon" and r.visible:
			var d: float = r.global_position.distance_to(p.global_position)
			if d < best:
				best = d
				target = r
	if target == null:
		p.test_input = {}
		return
	var to: Vector3 = target.global_position - p.global_position
	p.rotation.y = atan2(-to.x, -to.z)   # face it (-Z is forward)
	var aim_point: Vector3 = target.global_position + Vector3.UP * 0.35
	var eye: Vector3 = p.camera.global_position
	var flat := Vector2(aim_point.x - eye.x, aim_point.z - eye.z).length()
	p.pivot.rotation.x = clampf(atan2(aim_point.y - eye.y, flat), -1.4, 1.2)
	# Close enough with a clear view: throw. Otherwise walk closer.
	var clear: bool = best < 9.0 and _line_of_sight(p, target)
	# Lots of throws and no hits: probably clipping a corner. Move somewhere else.
	if _misses > 12:
		_misses = 0
		_strafe_time = 1.2
		_strafe_dir = -_strafe_dir
	if clear and _strafe_time <= 0.0:
		p.test_input = {}
		if best < 2.2 and p.melee():
			_log_once("melee")
		for slot in 2:
			var id: String = p.loadout["angel"][slot]
			if id != "" and id != "leap" and p.use_skill(slot):
				_log_once(id)
		if p.try_throw():
			_misses += 1
		return
	# Simple unsticking: if we haven't moved, sidestep for a moment.
	if p.global_position.distance_to(_last_pos) < 0.02:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	_last_pos = p.global_position
	if _stuck_time > 0.5:
		_stuck_time = 0.0
		_strafe_time = 0.8
		_strafe_dir = -_strafe_dir
	if _strafe_time > 0.0:
		_strafe_time -= delta
		p.test_input = {"dir": Vector2(_strafe_dir, -0.3)}
	else:
		p.test_input = {"dir": Vector2(0, -1)}


func _log_once(what: String) -> void:
	if not _used.has(what):
		_used[what] = true
		log_line("used " + what)


func _line_of_sight(p, target) -> bool:
	var hit: Dictionary = p._aim_ray(15.0)
	return not hit.is_empty() and hit["collider"] == target
