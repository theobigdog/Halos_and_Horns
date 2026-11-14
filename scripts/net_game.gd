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

const PROTOCOL_VERSION := 2      # bump whenever online messages change; mismatches can't join
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
	multiplayer.connected_to_server.connect(func(): c_hello.rpc_id(1, player_name, PROTOCOL_VERSION))
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
		"last_time": now(), "last_correct": 0.0, "grace_until": 0.0, "health": DEMON_HEALTH,
		"stamina": THROW_STAMINA_MAX, "stamina_time": now(), "last_taunt": 0.0,
		"throws": 0, "hits": 0, "redeemed": false, "skills": [],
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
func c_hello(player_name: String, version: int) -> void:
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
func _place(rec: Dictionary, pos: Vector3) -> void:
	rec["pos"] = pos
	rec["valid_pos"] = pos
	rec["last_time"] = now()
	rec["grace_until"] = now() + 0.6


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
		c_state.rpc_id(1, p.global_position, p.rotation.y, p.possessed_type)


# ---------------- movement checks (host) ----------------

func _in_bounds(pos: Vector3) -> bool:
	var limit: float = main.MAP_HALF + 0.4
	return absf(pos.x) <= limit and absf(pos.z) <= limit and pos.y > -3.0 and pos.y < 25.0


@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_state(pos: Vector3, yaw: float, form: String) -> void:
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
	elif flat > MAX_MOVE_SPEED * dt + 1.5:
		problem = "moving too fast (%.1f m in %.2f s)" % [flat, dt]
	if problem != "":
		if t < rec["grace_until"]:
			return   # just after the host moved them: stale updates are expected, not cheating
		if t - rec["last_correct"] > 0.3:
			rec["last_correct"] = t
			_note_cheat(id, problem)
			s_correct.rpc_id(id, rec["valid_pos"])
		return
	# Only demons can be props, and only real ones.
	if form != "" and (rec["role"] != "demon" or not PropLib.TYPES.has(form)):
		form = ""
	rec["pos"] = pos
	rec["valid_pos"] = pos
	rec["yaw"] = yaw
	rec["form"] = form
	rec["last_time"] = t
	if remotes.has(rec["eid"]):
		remotes[rec["eid"]].apply_state(pos, yaw, form, rec["role"])


@rpc("authority", "call_remote", "reliable")
func s_correct(pos: Vector3) -> void:
	main.online_correct(pos)


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
	rec["health"] -= damage
	if id == 1:
		main.online_you_hit(rec["health"])
	else:
		s_you_hit.rpc_id(id, rec["health"])
	if rec["health"] <= 0:
		_catch(id)
	return true


@rpc("authority", "call_remote", "reliable")
func s_you_hit(health: int) -> void:
	main.online_you_hit(health)


# Mobification: a caught demon is redeemed and joins the angels.
func _catch(id: int) -> void:
	var rec: Dictionary = peers[id]
	var where: Vector3 = rec["pos"]
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
				0 if id == 1 else ping_to(id), rec["skills"], rec["redeemed"],
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
