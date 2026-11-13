# Testing only: drives the local player automatically so whole online matches can
# be played with several copies of the game and no humans. Turned on with --autobot.
#   Demons wander off and possess a random prop, then taunt now and then.
#   Angels walk toward the nearest demon and throw at it.
# Prints "BOT: ..." lines that the multiplayer test reads.
# With --cheat=teleport, tries to jump out of bounds once (the host should refuse).
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


func log_line(text: String) -> void:
	print("BOT %s: %s" % [main.name_edit.text, text])


func _physics_process(delta: float) -> void:
	var p = main.player
	if not _connected:
		_connected = true
		p.hit_confirmed.connect(func(): _misses = 0)
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
			shown.append("%s=%s" % [r.role if r.role != "" else "?", r.player_name if r.player_name != "" else "<hidden>"])
		log_line("as %s, names I can see: %s" % [main.role, ", ".join(shown)])
	_taunt_timer -= delta
	if _taunt_timer <= 0.0:
		_taunt_timer = randf_range(6.0, 10.0)
		p._taunt_cooldown = 0.0
		p.taunt(randf() < 0.3)
	if options.get("cheat", "") == "teleport" and not _cheat_done and main.state == main.State.HUNTING:
		_cheat_done = true
		log_line("trying to teleport out of bounds")
		p.global_position = Vector3(main.MAP_HALF + 15.0, 1.0, 0.0)
		get_tree().create_timer(1.0).timeout.connect(func():
			log_line("1 s after cheat, position x = %.1f" % p.global_position.x))
	if main.role == "demon":
		_play_demon(delta, p)
	else:
		_play_angel(delta, p)


func _play_demon(delta: float, p) -> void:
	if _hidden:
		p.test_input = {}
		return
	_wander_time -= delta
	if _wander_time > 0.0:
		p.rotation.y = 0.0
		p.test_input = {"dir": _wander_dir}
		return
	p.test_input = {}
	var types := PropLib.type_names()
	p.force_possess(types[randi() % types.size()])
	_hidden = true
	log_line("hiding as a " + p.possessed_type)


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


func _line_of_sight(p, target) -> bool:
	var hit: Dictionary = p._aim_ray(15.0)
	return not hit.is_empty() and hit["collider"] == target
