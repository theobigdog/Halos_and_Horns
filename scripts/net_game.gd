# Online play. One player hosts (runs the match AND plays); everyone else joins.
#
# The host is the referee and decides everything that matters:
#   - every hit and catch (joined players' throws are just visuals locally)
#   - movement sanity: too-fast moves and out-of-bounds positions get snapped back
#   - blessing stamina, taunt spam, round timers and team assignment
# Anti-cheat on information: each player only receives names for their OWN team.
# A disguised demon reaches an angel's computer as an anonymous entity id,
# a position and a prop type - nothing that says who it is.
extends Node

const RemotePlayer = preload("res://scripts/remote_player.gd")
const Projectile = preload("res://scripts/projectile.gd")
const Blessings = preload("res://scripts/blessings.gd")
const Taunts = preload("res://scripts/taunts.gd")
const PropLib = preload("res://scripts/prop_library.gd")
const Effects = preload("res://scripts/effects.gd")
const Skills = preload("res://scripts/skills.gd")

const PROTOCOL_VERSION := 3      # bump whenever online messages change; mismatches can't join
const DEFAULT_PORT := 7777
const MAX_PLAYERS := 16
const SEND_RATE := 30.0          # joined players report their position this many times a second
const RELAY_RATE := 20.0         # host sends everyone's positions this many times a second
const MAX_MOVE_SPEED := 14.0     # m/s; sprinting is ~10.4, the rest is slack for lag
const DEMON_HEALTH := 100
const END_SCREEN_TIME := 8.0
const THROW_COST := 7.0
const THROW_STAMINA_MAX := 100.0
const THROW_REGEN := 30.0
const SCOREBOARD_RATE := 1.0     # roster (Tab) updates per second
const GRAPPLE_MOVE_SPEED := 26.0  # allowed speed for a moment after a grapple the host approved
const HATRED_REGEN := 4.0         # must match player.gd (mirrored to catch fly hacks)
const HATRED_FLY_DRAIN := 19.0
const HATRED_MAX_MIRROR := 100.0
const FLOAT_LIMIT := 3.0          # seconds off the ground without flying before it's a cheat

var main                         # the game scene (set by main.gd)
var is_host := false
var my_eid := 0
var hide_time := 30.0
var hunt_time := 180.0

# Host-side bookkeeping, one record per connected player (peer id -> Dictionary).
var peers := {}
var phase := "lobby"             # lobby, hiding, hunting, ended
var phase_time := 0.0
var round_seed := 0
var cheat_log: Array = []        # what the host blocked (also printed)
var forced_roles := {}           # testing only: player name -> "angel"/"demon"

# Everyone: other players in the current round (entity id -> RemotePlayer).
var remotes := {}

var _relay_accum := 0.0
var _score_accum := 0.0
var _send_accum := 0.0
var _used_eids := {}


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ---------------- connecting ----------------

func host(port: int, player_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	peers[1] = _new_record(_clean_name(player_name))
	_broadcast_lobby()
	return OK


func join(address: String, port: int, player_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(func(): c_hello.rpc_id(1, player_name, PROTOCOL_VERSION,
			main.loadout["angel"], main.loadout["demon"]))
	multiplayer.connection_failed.connect(func(): main.online_disconnected("Couldn't connect. Check the address, and that the host's port is open."))
	multiplayer.server_disconnected.connect(func(): main.online_disconnected("The host left the game."))
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_clear_remotes()


func _new_record(player_name: String) -> Dictionary:
	return {
		"name": player_name, "role": "", "eid": 0, "in_round": false,
		"pos": Vector3.ZERO, "valid_pos": Vector3.ZERO, "yaw": 0.0, "form": "",
		"last_time": now(), "last_correct": 0.0, "grace_until": 0.0, "moved_from": Vector3.ZERO, "moved_until": 0.0, "health": DEMON_HEALTH,
		"stamina": THROW_STAMINA_MAX, "stamina_time": now(), "last_taunt": 0.0,
		"throws": 0, "hits": 0, "redeemed": false,
		"loadout": Skills.DEFAULTS.duplicate(true), "skill_ready": {}, "melee_ready": 0.0,
		"hatred": 0.0, "air_time": 0.0, "grapple_until": 0.0, "locked_until": 0.0, "hp": 1.0,
	}


func _clean_name(n: String) -> String:
	n = n.strip_edges().substr(0, 16)
	if n == "":
		n = "Player"
	var taken := []
	for id in peers:
		taken.append(peers[id]["name"])
	var base := n
	var i := 2
	while n in taken:
		n = "%s%d" % [base, i]
		i += 1
	return n


func _new_eid() -> int:
	# Random ids, so an id can't be matched to a player's join order.
	var e := randi_range(1000, 999999)
	while _used_eids.has(e):
		e = randi_range(1000, 999999)
	_used_eids[e] = true
	return e


@rpc("any_peer", "call_remote", "reliable")
func c_hello(player_name: String, version: int, angel_skills: Array, demon_skills: Array) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if version != PROTOCOL_VERSION:
		s_kicked.rpc_id(id, "Version mismatch: you and the host have different versions of the game.")
		get_tree().create_timer(0.5).timeout.connect(func():
			if multiplayer.multiplayer_peer:
				multiplayer.multiplayer_peer.disconnect_peer(id))
		return
	peers[id] = _new_record(_clean_name(player_name))
	peers[id]["loadout"] = {"angel": Skills.clean_loadout("angel", angel_skills),
			"demon": Skills.clean_loadout("demon", demon_skills)}
	print("[host] %s joined" % peers[id]["name"])
	_broadcast_lobby()
	if phase == "hiding" or phase == "hunting":
		_add_late_joiner(id)


func _on_peer_disconnected(id: int) -> void:
	if not peers.has(id):
		return
	var rec: Dictionary = peers[id]
	peers.erase(id)
	print("[host] %s left" % rec["name"])
	if rec["in_round"]:
		main.authority_release(id, rec["pos"], rec["yaw"])
		_remove_remote(rec["eid"])
		for other in _client_ids():
			s_remove.rpc_id(other, rec["eid"])
		_broadcast_count()
		_check_round_over()
	_broadcast_lobby()


@rpc("authority", "call_remote", "reliable")
func s_kicked(message: String) -> void:
	main.online_disconnected(message)


# ---------------- lobby ----------------

func _client_ids() -> Array:
	var ids := []
	for id in peers:
		if id != 1:
			ids.append(id)
	return ids


func _broadcast_lobby() -> void:
	var names := []
	for id in peers:
		names.append(peers[id]["name"])
	main.online_lobby(names, phase)
	for id in _client_ids():
		s_lobby.rpc_id(id, names, phase)
	_send_scoreboards()


@rpc("authority", "call_remote", "reliable")
func s_lobby(names: Array, host_phase: String) -> void:
	main.online_lobby(names, host_phase)


# ---------------- rounds (host) ----------------

func can_start() -> bool:
	return is_host and phase == "lobby" and peers.size() >= 2


func start_round() -> void:
	if not can_start():
		return
	round_seed = randi()
	_used_eids.clear()
	_clear_remotes()
	var ids := peers.keys()
	ids.shuffle()
	# About one angel per three players, at least one.
	var angel_count := maxi(1, int(round(ids.size() / 3.0)))
	for i in ids.size():
		var rec: Dictionary = peers[ids[i]]
		rec["role"] = "angel" if i < angel_count else "demon"
		if forced_roles.has(rec["name"]):
			rec["role"] = forced_roles[rec["name"]]
		rec["eid"] = _new_eid()
		rec["form"] = ""
		rec["health"] = DEMON_HEALTH
		rec["stamina"] = THROW_STAMINA_MAX
		rec["stamina_time"] = now()
		rec["in_round"] = true
		rec["redeemed"] = false
		_reset_round_mirrors(rec)
		rec["throws"] = 0
		rec["hits"] = 0
		_place(rec, main.spawn_point(rec["role"], i))
	phase = "hiding"
	phase_time = hide_time
	for id in ids:
		_send_round_start(id)
	for id in ids:
		if id != 1:
			_ensure_host_remote(id)
	_broadcast_count()
	print("[host] round started: %d angel(s), %d demon(s)" % [angel_count, ids.size() - angel_count])


# The host moves a player (spawn, respawn). Updates already on their way from the
# old spot are expected for a moment, so they're quietly ignored, not flagged.
func _reset_round_mirrors(rec: Dictionary) -> void:
	rec["hp"] = 1.0
	rec["hatred"] = HATRED_MAX_MIRROR   # demons start each round with full Hatred
	rec["air_time"] = 0.0
	rec["skill_ready"] = {}
	rec["melee_ready"] = 0.0
	rec["grapple_until"] = 0.0
	rec["locked_until"] = 0.0


func _place(rec: Dictionary, pos: Vector3) -> void:
	# Updates sent from where they WERE can keep arriving for a while (laggy players),
	# so remember that spot and quietly ignore them.
	rec["moved_from"] = rec["pos"]
	rec["moved_until"] = now() + 3.0
	rec["pos"] = pos
	rec["valid_pos"] = pos
	rec["last_time"] = now()
	rec["grace_until"] = now() + 1.0


# What one player is allowed to know about everyone else: entity id, role,
# and a name ONLY when they're on the same team.
func _roster_for(viewer_id: int) -> Array:
	var viewer_role: String = peers[viewer_id]["role"]
	var roster := []
	for id in peers:
		var rec: Dictionary = peers[id]
		if id == viewer_id or not rec["in_round"]:
			continue
		var shown_name: String = rec["name"] if rec["role"] == viewer_role else ""
		roster.append([rec["eid"], shown_name, rec["role"]])
	return roster


func _send_round_start(id: int) -> void:
	var rec: Dictionary = peers[id]
	if id == 1:
		my_eid = rec["eid"]
		main.online_round_start(round_seed, rec["role"], rec["pos"], phase, phase_time)
		_apply_roster(_roster_for(1))
	else:
		s_round_start.rpc_id(id, round_seed, rec["role"], rec["pos"], phase, phase_time, rec["eid"], _roster_for(id))


func _send_rosters() -> void:
	_apply_roster(_roster_for(1))
	for id in _client_ids():
		if peers[id]["in_round"]:
			s_roster.rpc_id(id, _roster_for(id))


func _add_late_joiner(id: int) -> void:
	var rec: Dictionary = peers[id]
	rec["role"] = "angel"   # late joiners hunt
	rec["redeemed"] = false
	_reset_round_mirrors(rec)
	rec["eid"] = _new_eid()
	rec["form"] = ""
	rec["in_round"] = true
	rec["stamina"] = THROW_STAMINA_MAX
	rec["stamina_time"] = now()
	_place(rec, main.spawn_point("angel", randi() % 4))
	_send_round_start(id)
	_ensure_host_remote(id)
	_send_rosters()
	_broadcast_count()


func _ensure_host_remote(id: int) -> void:
	var rec: Dictionary = peers[id]
	var r := _get_or_make_remote(rec["eid"])
	r.snap = true     # the host needs exact positions for hit checks
	r.net = self
	if rec["role"] == peers[1]["role"]:
		r.set_name_for_teammate(rec["name"])
	r.apply_state(rec["pos"], rec["yaw"], rec["form"], rec["role"])


func _demons_left() -> int:
	var n := 0
	for id in peers:
		if peers[id]["in_round"] and peers[id]["role"] == "demon":
			n += 1
	return n


func _angels_left() -> int:
	var n := 0
	for id in peers:
		if peers[id]["in_round"] and peers[id]["role"] == "angel":
			n += 1
	return n


func _broadcast_count() -> void:
	var n := _demons_left()
	main.online_count(n)
	for id in _client_ids():
		s_count.rpc_id(id, n)


func _set_phase(new_phase: String, seconds: float) -> void:
	phase = new_phase
	phase_time = seconds
	main.online_phase(new_phase, seconds)
	for id in _client_ids():
		s_phase.rpc_id(id, new_phase, seconds)


func _end_round(message: String) -> void:
	if phase == "ended" or phase == "lobby":
		return
	print("[host] round over: " + message)
	var stats := []
	for id in peers:
		if peers[id]["throws"] > 0:
			stats.append("%s %d throws/%d hits" % [peers[id]["name"], peers[id]["throws"], peers[id]["hits"]])
	print("[host] joined players' throws: " + ", ".join(stats))
	phase = "ended"
	phase_time = END_SCREEN_TIME
	main.online_round_end(message)
	for id in _client_ids():
		s_round_end.rpc_id(id, message)


func _check_round_over() -> void:
	if phase != "hiding" and phase != "hunting":
		return
	if _demons_left() == 0:
		_end_round("Every demon was redeemed! Angels win!")
	elif _angels_left() == 0:
		_end_round("All the angels left. Demons win!")


func _back_to_lobby() -> void:
	print("[host] back to the lobby")
	phase = "lobby"
	for id in peers:
		peers[id]["in_round"] = false
	_clear_remotes()
	_broadcast_lobby()
	for id in _client_ids():
		s_back_to_lobby.rpc_id(id)
	main.online_back_to_lobby()


func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if is_host:
		_host_tick(delta)
	else:
		_client_tick(delta)


func _host_tick(delta: float) -> void:
	_score_accum += delta
	if _score_accum >= SCOREBOARD_RATE:
		_score_accum = 0.0
		_send_scoreboards()
	if phase != "lobby":
		phase_time -= delta
		if phase_time <= 0.0:
			if phase == "hiding":
				_set_phase("hunting", hunt_time)
			elif phase == "hunting":
				var n := _demons_left()
				_end_round("Time's up! %d demon%s survived. Demons win!" % [n, "" if n == 1 else "s"])
			elif phase == "ended":
				_back_to_lobby()
	# Host's own player into the shared state.
	var me: Dictionary = peers[1]
	if me["in_round"]:
		me["pos"] = main.player.global_position
		me["valid_pos"] = me["pos"]
		me["yaw"] = main.player.rotation.y
		me["form"] = main.player.possessed_type
	_relay_accum += delta
	if _relay_accum >= 1.0 / RELAY_RATE:
		_relay_accum = 0.0
		_relay_states()


func _relay_states() -> void:
	for viewer in _client_ids():
		if not peers[viewer]["in_round"]:
			continue
		var states := []
		for id in peers:
			var rec: Dictionary = peers[id]
			if id == viewer or not rec["in_round"]:
				continue
			states.append([rec["eid"], rec["pos"], rec["yaw"], rec["form"], rec["role"]])
		s_states.rpc_id(viewer, states)


# ---------------- rounds (joined players) ----------------

@rpc("authority", "call_remote", "reliable")
func s_round_start(seed_value: int, role: String, pos: Vector3, host_phase: String,
		seconds: float, eid: int, roster: Array) -> void:
	_clear_remotes()
	my_eid = eid
	main.online_round_start(seed_value, role, pos, host_phase, seconds)
	_apply_roster(roster)


@rpc("authority", "call_remote", "reliable")
func s_roster(roster: Array) -> void:
	_apply_roster(roster)


func _apply_roster(roster: Array) -> void:
	forget_names()
	for entry in roster:
		var r := _get_or_make_remote(entry[0])
		r.set_name_for_teammate(entry[1])


@rpc("authority", "call_remote", "reliable")
func s_phase(new_phase: String, seconds: float) -> void:
	main.online_phase(new_phase, seconds)


@rpc("authority", "call_remote", "reliable")
func s_count(n: int) -> void:
	main.online_count(n)


@rpc("authority", "call_remote", "reliable")
func s_round_end(message: String) -> void:
	main.online_round_end(message)


@rpc("authority", "call_remote", "reliable")
func s_back_to_lobby() -> void:
	_clear_remotes()
	main.online_back_to_lobby()


@rpc("authority", "call_remote", "unreliable_ordered")
func s_states(states: Array) -> void:
	for st in states:
		if st[0] == my_eid:
			continue
		var r := _get_or_make_remote(st[0])
		r.apply_state(st[1], st[2], st[3], st[4])


@rpc("authority", "call_remote", "reliable")
func s_remove(eid: int) -> void:
	_remove_remote(eid)


func _client_tick(delta: float) -> void:
	if not main.in_online_round():
		return
	_send_accum += delta
	if _send_accum >= 1.0 / SEND_RATE:
		_send_accum = 0.0
		var p = main.player
		c_state.rpc_id(1, p.global_position, p.rotation.y, p.possessed_type, p.flying)


# ---------------- movement checks (host) ----------------

func _in_bounds(pos: Vector3) -> bool:
	var limit: float = main.MAP_HALF + 0.4
	return absf(pos.x) <= limit and absf(pos.z) <= limit and pos.y > -3.0 and pos.y < 25.0


@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_state(pos: Vector3, yaw: float, form: String, flying: bool) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id) or not peers[id]["in_round"]:
		return
	var rec: Dictionary = peers[id]
	var t := now()
	var dt := clampf(t - rec["last_time"], 0.0, 1.0)
	var flat := Vector2(pos.x - rec["valid_pos"].x, pos.z - rec["valid_pos"].z).length()
	var problem := ""
	if not _in_bounds(pos):
		problem = "out of bounds"
	else:
		var max_speed := GRAPPLE_MOVE_SPEED if t < rec["grapple_until"] else MAX_MOVE_SPEED
		if flat > max_speed * dt + 1.5:
			problem = "moving too fast (%.1f m in %.2f s, from %s to %s)" % [flat, dt, _short(rec["valid_pos"]), _short(pos)]
	if problem != "":
		if t < rec["grace_until"]:
			return   # just after the host moved them: stale updates are expected, not cheating
		if t < rec["moved_until"] and pos.distance_to(rec["moved_from"]) < 4.0:
			return   # a late update from before the host moved them
		if t - rec["last_correct"] > 0.3:
			rec["last_correct"] = t
			_note_cheat(id, problem)
			s_correct.rpc_id(id, rec["valid_pos"])
		return
	# Only demons can be props, and only real ones.
	if form != "" and (rec["role"] != "demon" or not PropLib.TYPES.has(form)):
		form = ""
	flying = flying and rec["role"] == "demon"
	rec["pos"] = pos
	rec["valid_pos"] = pos
	rec["yaw"] = yaw
	rec["form"] = form
	rec["last_time"] = t
	if remotes.has(rec["eid"]):
		remotes[rec["eid"]].apply_state(pos, yaw, form, rec["role"])
	_check_flight(id, rec, pos, flying, dt, t)


# Fly hacks. The host keeps its own copy of each demon's Hatred: flying longer
# than their Hatred allows gets them dropped to the ground. And anyone hanging in
# the air for a while without flying (or a grapple / pull the host approved) too.
func _check_flight(id: int, rec: Dictionary, pos: Vector3, flying: bool, dt: float, t: float) -> void:
	if rec["role"] == "demon":
		rec["hatred"] = clampf(rec["hatred"] + HATRED_REGEN * dt - (HATRED_FLY_DRAIN * dt if flying else 0.0), -50.0, 100.0)
		if flying and rec["hatred"] < -15.0:
			rec["hatred"] = 0.0
			_note_cheat(id, "flying without enough Hatred")
			_drop_to_ground(id, rec, pos)
			return
	var excused: bool = flying or t < rec["grace_until"] or t < rec["grapple_until"]
	if excused or _has_ground_below(pos, remotes.get(rec["eid"])):
		rec["air_time"] = 0.0
		return
	rec["air_time"] += dt
	if rec["air_time"] > FLOAT_LIMIT:
		rec["air_time"] = 0.0
		_note_cheat(id, "floating without flying")
		_drop_to_ground(id, rec, pos)


# Ground anywhere under the player's footprint (not just the center, so standing
# on the very edge of a roof still counts).
func _has_ground_below(pos: Vector3, body) -> bool:
	for offset in [Vector3.ZERO, Vector3(0.45, 0, 0), Vector3(-0.45, 0, 0), Vector3(0, 0, 0.45), Vector3(0, 0, -0.45)]:
		var from: Vector3 = pos + offset + Vector3.UP * 0.2
		if not main._ray(from, from + Vector3.DOWN * 2.7, [body]).is_empty():
			return true
	return false


func _drop_to_ground(id: int, rec: Dictionary, pos: Vector3) -> void:
	var ground: Vector3 = main.ground_below(pos + Vector3.DOWN * 0.5)
	_place(rec, ground + Vector3.UP * 0.1)
	s_correct.rpc_id(id, rec["pos"])


@rpc("authority", "call_remote", "reliable")
func s_correct(pos: Vector3) -> void:
	main.online_correct(pos)


func _short(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]


func _note_cheat(id: int, what: String) -> void:
	var line := "%s: %s" % [peers[id]["name"], what]
	cheat_log.append(line)
	print("[host] blocked " + line)


# ---------------- throws, hits, catches ----------------

# Our own throw just left our hand.
func on_local_launched(origin: Vector3, velocity: Vector3, kind: String) -> void:
	if not main.in_online_round():
		return
	if is_host:
		for id in _client_ids():
			s_projectile.rpc_id(id, origin, velocity, kind)
	else:
		c_throw.rpc_id(1, origin, velocity, kind)


@rpc("any_peer", "call_remote", "reliable")
func c_throw(origin: Vector3, velocity: Vector3, kind: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id):
		return
	var rec: Dictionary = peers[id]
	if not rec["in_round"] or rec["role"] != "angel" or phase != "hunting":
		return
	if not Blessings.KINDS.has(kind) or velocity.length() > 45.0:
		return
	if origin.distance_to(rec["pos"] + Vector3.UP * 1.3) > 3.0:
		_note_cheat(id, "throwing from somewhere they aren't")
		return
	# Mirror the blessing stamina so a hacked client can't throw endlessly.
	# (A little slack for network timing.)
	var t := now()
	rec["stamina"] = minf(rec["stamina"] + THROW_REGEN * (t - rec["stamina_time"]), THROW_STAMINA_MAX)
	rec["stamina_time"] = t
	if rec["stamina"] < -THROW_COST:
		_note_cheat(id, "throwing faster than stamina allows")
		return
	rec["stamina"] -= THROW_COST
	rec["throws"] += 1
	var p := Projectile.new()
	p.color = Blessings.color(kind)
	p.shooter = remotes.get(rec["eid"])
	main.add_child(p)
	p.global_position = origin
	p.velocity = velocity
	for other in _client_ids():
		if other != id:
			s_projectile.rpc_id(other, origin, velocity, kind)


@rpc("authority", "call_remote", "reliable")
func s_projectile(origin: Vector3, velocity: Vector3, kind: String) -> void:
	var p := Projectile.new()
	p.color = Blessings.color(kind)
	p.visual_only = true
	main.add_child(p)
	p.global_position = origin
	p.velocity = velocity


func _peer_for_eid(eid: int) -> int:
	for id in peers:
		if peers[id]["eid"] == eid and peers[id]["in_round"]:
			return id
	return 0


# A host projectile hit a joined player.
func on_remote_hit(remote, damage: int) -> bool:
	return damage_player(_peer_for_eid(remote.eid), damage)


func on_remote_confirm(remote) -> void:
	var id := _peer_for_eid(remote.eid)
	if id != 0:
		peers[id]["hits"] += 1
		s_hit_confirm.rpc_id(id)


@rpc("authority", "call_remote", "reliable")
func s_hit_confirm() -> void:
	main.player.confirm_hit()


func damage_player(id: int, damage: int) -> bool:
	if not is_host or not peers.has(id) or phase != "hunting":
		return false
	var rec: Dictionary = peers[id]
	if rec["role"] != "demon" or not rec["in_round"]:
		return false
	# Health is kept as a fraction, so switching forms keeps your percentage:
	# the same hit hurts a stack of books (50 hp) more than a hay bale (150 hp).
	rec["hp"] -= float(damage) / PropLib.max_hp(rec["form"])
	var percent := maxi(int(ceil(rec["hp"] * 100.0)), 0)
	if id == 1:
		main.online_you_hit(percent)
	else:
		s_you_hit.rpc_id(id, percent)
	if rec["hp"] <= 0.0:
		_catch(id)
	return true


@rpc("authority", "call_remote", "reliable")
func s_you_hit(health: int) -> void:
	main.online_you_hit(health)


# Mobification: a caught demon is redeemed and joins the angels.
func _catch(id: int) -> void:
	var rec: Dictionary = peers[id]
	var where: Vector3 = rec["pos"]
	main.authority_release(id, where, rec["yaw"])   # a possessed prop stays behind, dissolving
	_reset_round_mirrors(rec)
	rec["role"] = "angel"
	rec["redeemed"] = true
	rec["form"] = ""
	rec["health"] = DEMON_HEALTH
	rec["stamina"] = THROW_STAMINA_MAX
	rec["stamina_time"] = now()
	_place(rec, main.spawn_point("angel", randi() % 4))
	print("[host] %s was caught" % rec["name"])
	# Names first: the redeemed player must lose their old teammates' names
	# before they're told they switched sides (and angels learn theirs).
	_send_rosters()
	if id == 1:
		main.online_you_were_caught(rec["pos"])
	else:
		s_you_were_caught.rpc_id(id, rec["pos"])
		if remotes.has(rec["eid"]):
			remotes[rec["eid"]].apply_state(rec["pos"], rec["yaw"], "", "angel")
	_broadcast_count()   # count first, so "N left" messages are up to date
	main.online_caught_fx(where)
	for other in _client_ids():
		s_caught_fx.rpc_id(other, where)
	_check_round_over()


@rpc("authority", "call_remote", "reliable")
func s_you_were_caught(pos: Vector3) -> void:
	main.online_you_were_caught(pos)


@rpc("authority", "call_remote", "reliable")
func s_caught_fx(pos: Vector3) -> void:
	main.online_caught_fx(pos)


# ---------------- taunts ----------------

func on_local_taunt(taunt_name: String) -> void:
	if not main.in_online_round():
		return
	if is_host:
		for id in _client_ids():
			s_taunt.rpc_id(id, my_eid, taunt_name)
	else:
		c_taunt.rpc_id(1, taunt_name)


func _valid_taunt(role: String, taunt_name: String) -> bool:
	var parts := taunt_name.split(":")
	if parts.size() != 2 or parts[0] != role:
		return false
	return parts[1] == "signature" or Taunts.TAUNTS[role].has(parts[1])


@rpc("any_peer", "call_remote", "reliable")
func c_taunt(taunt_name: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id) or not peers[id]["in_round"]:
		return
	var rec: Dictionary = peers[id]
	var t := now()
	if t - rec["last_taunt"] < 0.5 or not _valid_taunt(rec["role"], taunt_name):
		return
	rec["last_taunt"] = t
	if remotes.has(rec["eid"]):
		remotes[rec["eid"]].play_taunt(taunt_name)
	for other in _client_ids():
		if other != id:
			s_taunt.rpc_id(other, rec["eid"], taunt_name)


@rpc("authority", "call_remote", "reliable")
func s_taunt(eid: int, taunt_name: String) -> void:
	if remotes.has(eid):
		remotes[eid].play_taunt(taunt_name)


# ---------------- skills ----------------

func send_loadout(lo: Dictionary) -> void:
	if is_host:
		peers[1]["loadout"] = {"angel": Skills.clean_loadout("angel", lo["angel"]),
				"demon": Skills.clean_loadout("demon", lo["demon"])}
	elif multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		c_loadout.rpc_id(1, lo["angel"], lo["demon"])


@rpc("any_peer", "call_remote", "reliable")
func c_loadout(angel: Array, demon: Array) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	# Between rounds only (swapping mid-round will need a swap spot on the map).
	if not peers.has(id) or peers[id]["in_round"]:
		return
	peers[id]["loadout"] = {"angel": Skills.clean_loadout("angel", angel), "demon": Skills.clean_loadout("demon", demon)}


# Skills start at the player's camera, which can sit ~4 m behind them in third person.
func _origin_ok(rec: Dictionary, origin: Vector3) -> bool:
	return origin.distance_to(rec["pos"] + Vector3.UP * 1.3) <= 5.0


# Is this player allowed to use this skill right now? (Also starts its cooldown.)
func _skill_allowed(id: int, skill: String, origin: Vector3) -> bool:
	if not peers.has(id):
		return false
	var rec: Dictionary = peers[id]
	var t := now()
	if not rec["in_round"] or not Skills.SKILLS.has(skill):
		return false
	if Skills.SKILLS[skill]["team"] != rec["role"] or not skill in rec["loadout"][rec["role"]]:
		return false
	if rec["role"] == "angel" and phase != "hunting":
		return false
	if rec["role"] == "demon" and (phase != "hiding" and phase != "hunting" or t < rec["locked_until"]):
		return false
	if t + 0.3 < rec["skill_ready"].get(skill, 0.0):   # a little slack for lag
		return false
	if not _origin_ok(rec, origin):
		_note_cheat(id, "using a skill from somewhere they aren't")
		return false
	rec["skill_ready"][skill] = t + Skills.cooldown(skill)
	return true


func on_local_skill(skill: String, origin: Vector3, dir: Vector3, point: Vector3, index: int) -> void:
	if not main.in_online_round():
		return
	if is_host:
		peers[1]["pos"] = main.player.global_position
		if _skill_allowed(1, skill, origin):
			main.authority_skill(main.player, 1, skill, origin, dir.normalized(), point, index)
	else:
		c_skill.rpc_id(1, skill, origin, dir, point, index)


@rpc("any_peer", "call_remote", "reliable")
func c_skill(skill: String, origin: Vector3, dir: Vector3, point: Vector3, index: int) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _skill_allowed(id, skill, origin):
		return
	if skill == "chicken" and point.distance_to(origin) > Skills.CHICKEN_RANGE + 2.0:
		return
	var rec: Dictionary = peers[id]
	if not remotes.has(rec["eid"]):
		return
	main.authority_skill(remotes[rec["eid"]], id, skill, origin, dir.normalized(), point, index)


func on_local_melee(origin: Vector3, dir: Vector3) -> void:
	if not main.in_online_round():
		return
	if is_host:
		if _melee_allowed(1, origin):
			main.authority_melee(main.player, 1, origin, dir.normalized())
	else:
		c_melee.rpc_id(1, origin, dir)


func _melee_allowed(id: int, origin: Vector3) -> bool:
	var rec: Dictionary = peers[id]
	var t := now()
	if not rec["in_round"] or rec["role"] != "angel" or phase != "hunting" or t + 0.15 < rec["melee_ready"]:
		return false
	if id != 1 and not _origin_ok(rec, origin):
		return false
	rec["melee_ready"] = t + Skills.MELEE_COOLDOWN
	return true


@rpc("any_peer", "call_remote", "reliable")
func c_melee(origin: Vector3, dir: Vector3) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id) or not _melee_allowed(id, origin):
		return
	var rec: Dictionary = peers[id]
	if remotes.has(rec["eid"]):
		main.authority_melee(remotes[rec["eid"]], id, origin, dir.normalized())


func on_local_release() -> void:
	if not main.in_online_round():
		return
	if is_host:
		main.authority_release(1, main.player.global_position, main.player.rotation.y)
	else:
		c_release.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func c_release() -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if peers.has(id) and peers[id]["in_round"]:
		main.authority_release(id, peers[id]["pos"], peers[id]["yaw"])


func grant_grapple(id: int) -> void:
	if peers.has(id):
		peers[id]["grapple_until"] = now() + 1.8


# Every demon in the round, as bodies the host can measure and hit.
func demon_nodes() -> Array:
	var out := []
	for id in peers:
		var rec: Dictionary = peers[id]
		if not rec["in_round"] or rec["role"] != "demon":
			continue
		if id == 1:
			out.append(main.player)
		elif remotes.has(rec["eid"]):
			out.append(remotes[rec["eid"]])
	return out


# Pull a demon somewhere (vacuum, grappling hook), drain Hatred, lock skills.
func affect_node(node: Node3D, target: Vector3, hatred_drain: float, lockout: float) -> void:
	var id := 1 if node == main.player else (_peer_for_eid(node.eid) if node is RemotePlayer else 0)
	if id == 0 or not peers.has(id):
		return
	var rec: Dictionary = peers[id]
	var t := now()
	rec["hatred"] = maxf(rec["hatred"] - hatred_drain, -50.0)
	rec["locked_until"] = maxf(rec["locked_until"], t + lockout)
	rec["grace_until"] = t + 1.3     # they're about to move fast: not cheating
	rec["air_time"] = 0.0
	if id == 1:
		main.online_affected(target, hatred_drain, lockout)
	else:
		s_affected.rpc_id(id, target, hatred_drain, lockout)


@rpc("authority", "call_remote", "reliable")
func s_affected(target: Vector3, hatred_drain: float, lockout: float) -> void:
	main.online_affected(target, hatred_drain, lockout)


func tell_possessed(id: int, type_name: String, pos: Vector3, yaw: float, index: int) -> void:
	var rec: Dictionary = peers[id]
	rec["form"] = type_name
	rec["yaw"] = yaw
	_place(rec, pos)
	if remotes.has(rec["eid"]):
		remotes[rec["eid"]].apply_state(pos, yaw, type_name, rec["role"])
	s_possessed.rpc_id(id, type_name, pos, yaw, index)


@rpc("authority", "call_remote", "reliable")
func s_possessed(type_name: String, pos: Vector3, yaw: float, index: int) -> void:
	main.player.become_possessed(type_name, pos, yaw, index)


func send_fx(kind: String, args: Array, except_id: int) -> void:
	for id in _client_ids():
		if id != except_id and peers[id]["in_round"]:
			s_fx.rpc_id(id, kind, args)


@rpc("authority", "call_remote", "reliable")
func s_fx(kind: String, args: Array) -> void:
	main.fx(kind, args)


# ---------------- ping and the Tab roster ----------------

# Round-trip time in milliseconds, as measured by the network library.
func ping_to(id: int) -> int:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return -1
	var ep := enet.get_peer(id)
	if ep == null:
		return -1
	return int(ep.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


# Our own ping to the host (the host itself has none).
func my_ping() -> int:
	return 0 if is_host else ping_to(1)


# Roster rows: name, side, ping, skills, caught-this-round, is-you, is-host.
# Deliberately NO entity ids or positions: knowing who's a demon is fine,
# knowing which prop they are is not.
func _scoreboard_for(viewer: int) -> Array:
	var rows := []
	for id in peers:
		var rec: Dictionary = peers[id]
		rows.append([rec["name"], rec["role"] if rec["in_round"] else "",
				0 if id == 1 else ping_to(id),
				rec["loadout"][rec["role"]].map(func(k): return Skills.label(k)).filter(func(l): return l != "-") \
						if rec["in_round"] else [],
				rec["redeemed"],
				id == viewer, id == 1])
	return rows


func _send_scoreboards() -> void:
	main.online_scoreboard(_scoreboard_for(1))
	for id in _client_ids():
		s_scoreboard.rpc_id(id, _scoreboard_for(id))


@rpc("authority", "call_remote", "reliable")
func s_scoreboard(rows: Array) -> void:
	main.online_scoreboard(rows)


# ---------------- other players' bodies ----------------

# Wipe every name we know (switching sides: only the new roster may fill them in).
func forget_names() -> void:
	for eid in remotes:
		remotes[eid].set_name_for_teammate("")


func _get_or_make_remote(eid: int) -> RemotePlayer:
	if remotes.has(eid):
		return remotes[eid]
	var r := RemotePlayer.new()
	r.eid = eid
	r.name = "Remote_%d" % eid
	main.add_child(r)
	remotes[eid] = r
	return r


func _remove_remote(eid: int) -> void:
	if remotes.has(eid):
		remotes[eid].queue_free()
		remotes.erase(eid)


func _clear_remotes() -> void:
	for eid in remotes:
		remotes[eid].queue_free()
	remotes.clear()
