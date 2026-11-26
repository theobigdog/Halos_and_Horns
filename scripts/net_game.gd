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

const GameRules = preload("res://scripts/game_rules.gd")
const RemotePlayer = preload("res://scripts/remote_player.gd")
const Projectile = preload("res://scripts/projectile.gd")
const Blessings = preload("res://scripts/blessings.gd")
const Taunts = preload("res://scripts/taunts.gd")
const PropLib = preload("res://scripts/prop_library.gd")
const Effects = preload("res://scripts/effects.gd")
const Skills = preload("res://scripts/skills.gd")
const PowerUps = preload("res://scripts/powerups.gd")
const MapData = preload("res://scripts/map_data.gd")
const RelayPeer = preload("res://scripts/relay_peer.gd")
const Aura = preload("res://scripts/aura.gd")
const RP = preload("res://relay/relay_protocol.gd")
const Characters = preload("res://scripts/characters.gd")

const PROTOCOL_VERSION := 5      # (old) kept for reference; joining now checks main.game_build
# Only the exact same build can join. The build number comes from the release tag
# (see game_build in main.gd), and is sent where older versions sent PROTOCOL_VERSION,
# so they get a clear message too.
const DEFAULT_PORT := 7777
const MAX_PLAYERS := 16
const SEND_RATE := 30.0          # joined players report their position this many times a second
const RELAY_RATE := 20.0         # host sends everyone's positions this many times a second
const MAX_MOVE_SPEED := 14.0     # m/s; sprinting is ~10.4, the rest is slack for lag
const DEMON_HEALTH := 100
const END_SCREEN_TIME := 8.0
const THROW_COST := 12.0          # (must match player.gd)
const THROW_STAMINA_MAX := 100.0
const THROW_REGEN := 18.0
const SCOREBOARD_RATE := 1.0     # roster (Tab) updates per second
const DASH_MOVE_SPEED := 46.0     # allowed speed for a while after a dash the host approved (covers the F1 sliders' top end)
const DASH_WINDOW := 4.0          # seconds that allowance lasts: the burst, then the momentum fading out
const HATRED_REGEN := 4.0         # must match player.gd (mirrored to catch fly hacks)
const HATRED_FLY_DRAIN := 22.0
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
	peers[1]["outfits"] = _clean_outfits(main.outfits)
	_broadcast_lobby()
	return OK


func join(address: String, port: int, player_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_client_signals(player_name, "Couldn't connect. Check the address, and that the host's port is open.")
	return OK


# Hosting through the relay server: no port forwarding, friends join with a room
# code. main.online_room_code() gets the code once the relay has opened the room.
func host_relay(relay_host: String, relay_port: int, player_name: String) -> Error:
	var peer := RelayPeer.new()
	var err := peer.host(relay_host, relay_port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	peer.room_opened.connect(func(code): main.online_room_code(code))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(func(): main.online_disconnected(
			_relay_trouble(peer, "Couldn't reach the relay server. Check your internet connection.")))
	multiplayer.server_disconnected.connect(func(): main.online_disconnected(
			_relay_trouble(peer, "Lost the connection to the relay server.")))
	peers[1] = _new_record(_clean_name(player_name))
	peers[1]["outfits"] = _clean_outfits(main.outfits)
	_broadcast_lobby()
	return OK


func join_relay(relay_host: String, relay_port: int, code: String, player_name: String) -> Error:
	var peer := RelayPeer.new()
	var err := peer.join(relay_host, relay_port, code)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_client_signals(player_name, "Couldn't reach the relay server. Check your internet connection.")
	return OK


func _client_signals(player_name: String, cant_connect: String) -> void:
	multiplayer.connected_to_server.connect(func(): c_hello.rpc_id(1, player_name, main.game_build,
			main.loadout["angel"], main.loadout["demon"], main.outfits))
	multiplayer.connection_failed.connect(func(): main.online_disconnected(_relay_trouble(multiplayer.multiplayer_peer, cant_connect)))
	multiplayer.server_disconnected.connect(func(): main.online_disconnected(_relay_trouble(multiplayer.multiplayer_peer, "The host left the game.")))


# The relay's reason, when it gave one (wrong code, game full...).
static func _relay_trouble(peer, fallback: String) -> String:
	if peer is RelayPeer and peer.refusal != "":
		return peer.refusal
	return fallback


func using_relay() -> bool:
	return multiplayer.multiplayer_peer is RelayPeer


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
		"hatred": 0.0, "air_time": 0.0, "dash_until": 0.0, "locked_until": 0.0, "hp": 1.0,
	}


func _clean_name(n: String) -> String:
	n = better_name(displayable_name(n)).substr(0, 16)
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


# A couple of names get swapped for a better one. That's all.
const SWAP_NAMES := ["dickbubble", "dickbbl"]
const BETTER_NAMES := ["William", "Bubba", "Nanopenis", "Buhtlicker"]


static func better_name(n: String) -> String:
	var letters := ""
	for ch in n.to_lower():
		if ch >= "a" and ch <= "z":
			letters += ch
	for bad in SWAP_NAMES:
		if bad in letters:
			return BETTER_NAMES.pick_random()
	return n


# Names show plain keyboard characters and accented Latin letters only
# (no other alphabets or invisible characters).
static func displayable_name(n: String) -> String:
	var out := ""
	for ch in n:
		var c := ch.unicode_at(0)
		if (c >= 32 and c < 127) or (c >= 0xC0 and c <= 0x24F and c != 0xD7 and c != 0xF7) or (c >= 0x1E00 and c <= 0x1EFF):
			out += ch
	return out.strip_edges()


func _new_eid() -> int:
	# Random ids, so an id can't be matched to a player's join order.
	var e := randi_range(1000, 999999)
	while _used_eids.has(e):
		e = randi_range(1000, 999999)
	_used_eids[e] = true
	return e


@rpc("any_peer", "call_remote", "reliable")
func c_hello(player_name: String, version: int, angel_skills: Array, demon_skills: Array, outfits := {}) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if version != main.game_build:
		s_kicked.rpc_id(id, "Version mismatch: the host is running version %s. Download that version to join." % main.game_version)
		get_tree().create_timer(0.5).timeout.connect(func():
			if multiplayer.multiplayer_peer:
				multiplayer.multiplayer_peer.disconnect_peer(id))
		return
	peers[id] = _new_record(_clean_name(player_name))
	peers[id]["loadout"] = {"angel": Skills.clean_loadout("angel", angel_skills),
			"demon": Skills.clean_loadout("demon", demon_skills)}
	peers[id]["outfits"] = _clean_outfits(outfits)
	print("[host] %s joined" % peers[id]["name"])
	send_map(id)
	_broadcast_lobby()
	if (phase == "hiding" or phase == "hunting") and solo_round:
		_solo_joined(id)
	elif phase == "hiding" or phase == "hunting":
		_add_late_joiner(id)
	elif phase == "building":
		build_can[id] = true
		_build_color(id)
		_send_build_start(id)


func _on_peer_disconnected(id: int) -> void:
	if not peers.has(id):
		return
	var rec: Dictionary = peers[id]
	peers.erase(id)
	build_claims.erase(id)
	build_cams.erase(id)
	build_can.erase(id)
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


# ---------------- kicking ----------------

var idle_limit := 0.0   # seconds an ANGEL can go without moving or looking around before the host kicks them (0 = never)
# Demons are never kicked for sitting still (hiding is the whole point), but a demon
# that hasn't moved for this long during the hunt taunts, whether it likes it or not,
# and again every time this long passes. Taunting by choice resets the clock.
const STILL_TAUNT_AFTER := 20.0
const STILL_WARNING := 5.0     # (heads-up this long before)


func kick_by_name(player_name: String, reason: String) -> void:
	for id in peers:
		if id != 1 and peers[id]["name"].to_lower() == player_name.to_lower():
			kick(id, reason)
			return


func kick(id: int, reason: String) -> void:
	if not is_host or id == 1 or not peers.has(id):
		return
	print("[host] kicked %s: %s" % [peers[id]["name"], reason])
	var news := "%s was kicked." % peers[id]["name"]
	main.announce(news)
	for other in _client_ids():
		if other != id:
			s_announce.rpc_id(other, news)
	s_kicked.rpc_id(id, reason)
	get_tree().create_timer(0.5).timeout.connect(func():
		if multiplayer.multiplayer_peer and id in multiplayer.get_peers():
			multiplayer.multiplayer_peer.disconnect_peer(id))


func _mark_active(id: int) -> void:
	if peers.has(id):
		peers[id]["active_at"] = now()


func _check_idle() -> void:
	if idle_limit <= 0.0 or not (phase == "hiding" or phase == "hunting"):
		return
	var t := now()
	for id in _client_ids():
		var rec: Dictionary = peers[id]
		if rec["role"] == "demon":
			rec["active_at"] = t   # demons can sit still as long as they like (see below)
			continue
		if rec["in_round"] and t - rec.get("active_at", t) > idle_limit:
			rec["active_at"] = t
			kick(id, "You were kicked for being idle (no moving or looking around for a while).")


# Demons who haven't moved for a while taunt anyway.
func _check_still_demons() -> void:
	var t := now()
	for id in peers:
		var rec: Dictionary = peers[id]
		if phase != "hunting" or not rec["in_round"] or rec["role"] != "demon":
			rec.erase("still_pos")
			continue
		var pos: Vector3 = rec["pos"]
		if not rec.has("still_pos") or pos.distance_to(rec["still_pos"]) > 0.5:
			rec["still_pos"] = pos
			rec["still_since"] = t
			rec["still_warned"] = false
			continue
		var since: float = maxf(rec["still_since"], rec["last_taunt"])
		if t - since >= STILL_TAUNT_AFTER:
			force_taunt(id)
		elif t - since >= STILL_TAUNT_AFTER - STILL_WARNING and not rec["still_warned"]:
			rec["still_warned"] = true
			if id == 1:
				main.still_warning(STILL_WARNING)
			else:
				s_still_warning.rpc_id(id, STILL_WARNING)


func force_taunt(id: int) -> void:
	var rec: Dictionary = peers[id]
	var taunt_name: String = Taunts.pick_random(rec["role"], rec.get("forced_taunt", ""))
	rec["forced_taunt"] = taunt_name
	rec["last_taunt"] = now()
	rec["still_warned"] = false
	print("[host] %s sat still too long: forced taunt" % rec["name"])
	if id == 1:
		main.forced_taunt(taunt_name)
	else:
		s_forced_taunt.rpc_id(id, taunt_name)
		if remotes.has(rec["eid"]):
			remotes[rec["eid"]].play_taunt(taunt_name)
	for other in _client_ids():
		if other != id:
			s_taunt.rpc_id(other, rec["eid"] if id != 1 else my_eid, taunt_name)


@rpc("authority", "call_remote", "reliable")
func s_still_warning(seconds: float) -> void:
	main.still_warning(clampf(seconds, 0.0, 10.0))


@rpc("authority", "call_remote", "reliable")
func s_forced_taunt(taunt_name: String) -> void:
	if _valid_taunt("demon", taunt_name):
		print("[net] forced to taunt")
		main.forced_taunt(taunt_name)


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
	return is_host and phase == "lobby" and peers.size() >= 1   # (on your own too: Ted, Nov 26)


func start_round() -> void:
	if not can_start():
		return
	round_seed = randi()
	GameRules.current = main.active_rules()
	_used_eids.clear()
	minions.clear()
	_clear_remotes()
	var ids := peers.keys()
	ids.shuffle()
	# About one angel per three players, at least one.
	var angel_count := maxi(1, int(round(ids.size() / 3.0)))
	solo_round = ids.size() < 2
	_solo_waiting.clear()
	if solo_round:
		angel_count = 1 if solo_role == "angel" else 0   # on your own: the team you picked (Sara, Nov 25; Ted, Nov 26)
	for i in ids.size():
		var rec: Dictionary = peers[ids[i]]
		rec["role"] = "angel" if i < angel_count else "demon"
		if forced_roles.has(rec["name"]):
			rec["role"] = forced_roles[rec["name"]]
		rec["eid"] = _new_eid()
		rec["form"] = ""
		rec["aura_until"] = 0.0
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
	phase_time = 3.0 if test_round else hide_time   # (a test round from Creative skips the wait)
	for id in ids:
		_send_round_start(id)
	for id in ids:
		if id != 1:
			_ensure_host_remote(id)
	_broadcast_count()
	_send_looks()
	print("[host] round started: %d angel(s), %d demon(s)" % [angel_count, ids.size() - angel_count])
	_start_demons = ids.size() - angel_count


# The host moves a player (spawn, respawn). Updates already on their way from the
# old spot are expected for a moment, so they're quietly ignored, not flagged.
func _reset_round_mirrors(rec: Dictionary) -> void:
	rec["hp"] = 1.0
	rec["hatred"] = HATRED_MAX_MIRROR   # demons start each round with full Hatred
	rec["air_time"] = 0.0
	rec["skill_ready"] = {}
	rec["melee_ready"] = 0.0
	rec["active_at"] = now()
	rec["dash_until"] = 0.0
	rec["locked_until"] = 0.0
	for k in ["fast_hatred_until", "quick_throw_until", "quick_skills_until", "sense_until"]:
		rec[k] = 0.0
	rec["sense_near"] = false


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
# and a name ONLY for fellow angels. Demons never see any names, not even
# each other's (a demon's game could otherwise give teammates away to a cheater).
func _roster_for(viewer_id: int) -> Array:
	var viewer_role: String = peers[viewer_id]["role"]
	var roster := []
	for id in peers:
		var rec: Dictionary = peers[id]
		if id == viewer_id or not rec["in_round"]:
			continue
		var shown_name: String = rec["name"] if rec["role"] == viewer_role and viewer_role == "angel" else ""
		roster.append([rec["eid"], shown_name, rec["role"]])
	# Minions are listed just like any demon (no name), so nothing gives them away.
	for owner in minions:
		if owner != viewer_id:
			roster.append([minions[owner]["eid"], "", "demon"])
	return roster


func _send_round_start(id: int) -> void:
	var rec: Dictionary = peers[id]
	send_map(id)   # (the map goes first: same channel, so it always arrives before the round)
	if id != 1:
		s_rules.rpc_id(id, GameRules.current)   # (and the rules: the same channel, so before the round too)
	if id == 1:
		my_eid = rec["eid"]
		main.online_round_start(round_seed, rec["role"], rec["pos"], phase, phase_time)
		_apply_roster(_roster_for(1))
	else:
		s_round_start.rpc_id(id, round_seed, rec["role"], rec["pos"], phase, phase_time, rec["eid"], _roster_for(id))


# The host's game rules (gravity, stamina, damage...): every game plays by them this round.
@rpc("authority", "call_remote", "reliable")
func s_rules(d: Dictionary) -> void:
	GameRules.current = GameRules.clean(d)
	print("[net] rules: " + GameRules.summary(GameRules.current))


# ---------------- the map ----------------
# The host's map is sent to everyone as plain map data; each joiner checks and
# builds it (it can't contain anything but pieces). Sent when they join, when the
# host picks another map, and before every round, unless they already have it.

func send_map(id: int) -> void:
	if id == 1 or not peers.has(id):
		return
	var print_now: String = MapData.fingerprint(main.map_data)
	if peers[id].get("has_map", "") == print_now:
		return
	peers[id]["has_map"] = print_now
	s_map.rpc_id(id, MapData.to_text(main.map_data))


func send_map_to_all() -> void:
	for id in _client_ids():
		send_map(id)
	_broadcast_lobby()


@rpc("authority", "call_remote", "reliable")
func s_map(text: String) -> void:
	var m := MapData.from_text(text)
	if m.is_empty():
		push_warning("The host's map couldn't be read.")
		return
	if MapData.fingerprint(m) != MapData.fingerprint(main.map_data):
		main.load_map(m)
	print("[net] map: %s" % m["name"])


# ---- how everyone looks ----
# Each player's outfit for their current team, keyed by their (anonymous) entity id, and each minion
# dressed like its owner. Sent whenever who's who changes.

static func _clean_outfits(o) -> Dictionary:
	if typeof(o) != TYPE_DICTIONARY:
		o = {}
	return {"angel": Characters.clean_outfit(o.get("angel"), "angel"), "demon": Characters.clean_outfit(o.get("demon"), "demon")}


func send_outfits(o: Dictionary) -> void:
	if is_host:
		if peers.has(1):
			peers[1]["outfits"] = _clean_outfits(o)
			_send_looks()
	elif multiplayer.multiplayer_peer:
		c_outfits.rpc_id(1, o)


@rpc("any_peer", "call_remote", "reliable")
func c_outfits(o: Dictionary) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id):
		return
	var t := now()
	if t - peers[id].get("outfit_time", -10.0) < 0.5:
		return   # (no flooding)
	peers[id]["outfit_time"] = t
	peers[id]["outfits"] = _clean_outfits(o)
	_send_looks()


func _looks() -> Dictionary:
	var out := {}
	for id in peers:
		var rec: Dictionary = peers[id]
		if rec["in_round"] and rec["role"] != "":
			out[rec["eid"]] = rec.get("outfits", _clean_outfits({}))[rec["role"]]
	for owner in minions:
		if peers.has(owner):
			out[minions[owner]["eid"]] = peers[owner].get("outfits", _clean_outfits({}))["demon"]
	return out


func _send_looks() -> void:
	var looks := _looks()
	_apply_looks(looks)
	for id in _client_ids():
		s_looks.rpc_id(id, looks)


@rpc("authority", "call_remote", "reliable")
func s_looks(l: Dictionary) -> void:
	_apply_looks(l)
	print("[net] outfits for %d players" % l.size())


var looks := {}                  # entity id -> outfit


func _apply_looks(l: Dictionary) -> void:
	looks = l
	for eid in l:
		if remotes.has(int(eid)):
			var role: String = remotes[int(eid)].role if remotes[int(eid)].role != "" else "angel"
			remotes[int(eid)].set_outfit(Characters.clean_outfit(l[eid], role))


func _send_rosters() -> void:
	_send_looks()
	_apply_roster(_roster_for(1))
	for id in _client_ids():
		if peers[id]["in_round"]:
			s_roster.rpc_id(id, _roster_for(id))


# Someone joined while the host plays alone: the round restarts with them in a few seconds, unless the
# host clicks to keep going (main.gd's pop-up).
func _solo_joined(id: int) -> void:
	_solo_waiting.append(id)
	var names := []
	for w in _solo_waiting:
		if peers.has(w):
			names.append(peers[w]["name"])
	main.solo_join_prompt(", ".join(names), SOLO_RESTART_IN)
	print("[host] %s joined a solo round" % peers[id]["name"])


# The pop-up ran out: start over with everyone.
func solo_restart() -> void:
	if not is_host or not solo_round or _solo_waiting.is_empty():
		return
	_solo_waiting.clear()
	var was_test := test_round
	_back_to_lobby()
	test_round = was_test
	start_round()


# The host kept their round: the newcomers join it, on the other team (so there's someone to play against).
func solo_keep() -> void:
	if not is_host or not solo_round:
		return
	solo_round = false
	var other := "demon" if peers[1]["role"] == "angel" else "angel"
	for w in _solo_waiting:
		if peers.has(w) and not peers[w]["in_round"]:
			_add_late_joiner(w, other)
	_solo_waiting.clear()


func _add_late_joiner(id: int, role := "angel") -> void:
	var rec: Dictionary = peers[id]
	rec["role"] = role   # late joiners hunt (unless they're joining a solo demon's round)
	rec["redeemed"] = false
	_reset_round_mirrors(rec)
	rec["eid"] = _new_eid()
	rec["form"] = ""
	rec["in_round"] = true
	rec["stamina"] = THROW_STAMINA_MAX
	rec["stamina_time"] = now()
	_place(rec, main.spawn_point(role, randi() % 4))
	_send_round_start(id)
	var props_now: Array = main.prop_state()
	s_prop_state.rpc_id(id, props_now[0], props_now[1])
	_ensure_host_remote(id)
	_send_rosters()
	_broadcast_count()


@rpc("authority", "call_remote", "reliable")
func s_prop_state(gone: Array, moved: Array) -> void:
	main.apply_prop_state(gone, moved)
	print("[net] caught up on the props: %d gone, %d moved" % [gone.size(), moved.size()])


func _ensure_host_remote(id: int) -> void:
	var rec: Dictionary = peers[id]
	var r := _get_or_make_remote(rec["eid"])
	r.snap = true     # the host needs exact positions for hit checks
	r.net = self
	r.set_name_for_teammate(rec["name"] if rec["role"] == peers[1]["role"] and rec["role"] == "angel" else "")
	r.apply_state(rec["pos"], rec["yaw"], rec["form"], rec["role"])


var _start_demons := 0


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
	for owner in minions.keys():   # the round's over: no minions wandering about
		_minion_gone(owner, true)
	main.online_round_end(message)
	for id in _client_ids():
		s_round_end.rpc_id(id, message)


func _check_round_over() -> void:
	if phase != "hiding" and phase != "hunting":
		return
	if (test_round or solo_round) and peers.size() < 2:
		return   # alone: nothing to win, just play (Esc, "Back to Creative" ends a test)
	if _demons_left() == 0:
		_end_round("Every demon was redeemed! Angels win!")
	elif _angels_left() == 0:
		_end_round("All the angels left. Demons win!")


func _back_to_lobby() -> void:
	print("[host] back to the lobby")
	phase = "lobby"
	for id in peers:
		peers[id]["in_round"] = false
	minions.clear()
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
	if phase in ["hiding", "hunting", "ended"]:   # (not "lobby" or "building")
		phase_time -= delta
		if phase_time <= 0.0:
			if phase == "hiding":
				_set_phase("hunting", hunt_time)
			elif phase == "hunting":
				var n := _demons_left()
				_end_round("Time's up! %d demon%s survived. Demons win!" % [n, "" if n == 1 else "s"])
			elif phase == "ended":
				_back_to_lobby()
				if test_round:   # a test round from Creative: back to building
					test_round = false
					start_building()
	if phase == "building":
		_build_tick(delta)
	_check_idle()
	# Host's own player into the shared state.
	var me: Dictionary = peers[1]
	if me["in_round"]:
		me["pos"] = main.player.global_position
		me["valid_pos"] = me["pos"]
		me["yaw"] = main.player.shown_yaw()
		me["form"] = main.player.possessed_type
		_record_history(1, me["pos"])
	_check_still_demons()
	if minions.has(1) and is_instance_valid(main.player.minion):
		minions[1]["pos"] = main.player.minion.global_position
		minions[1]["yaw"] = main.player.minion.rotation.y
	for owner in minions.keys():
		if now() > minions[owner]["until"]:
			_minion_gone(owner, true)
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
			if peers[viewer]["role"] == "angel" and _is_vanished(id):
				continue   # invisible: angels get nothing about this demon
			states.append([rec["eid"], rec["pos"], rec["yaw"], rec["form"], rec["role"], _shown_aura(id), _is_flying(id), _is_sneaking(id)])
		for owner in minions:
			if owner != viewer:
				var m: Dictionary = minions[owner]
				states.append([m["eid"], m["pos"], m["yaw"], m["form"], "demon", _minion_aura(owner), false])
		s_states.rpc_id(viewer, states)
	# The host's own screen.
	for id in peers:
		var rec: Dictionary = peers[id]
		if id != 1 and rec["in_round"] and remotes.has(rec["eid"]):
			remotes[rec["eid"]].set_aura(_shown_aura(id))
			remotes[rec["eid"]].set_flying(_is_flying(id))
			remotes[rec["eid"]].set_crouch(_is_sneaking(id))
	for owner in minions:
		if owner != 1 and remotes.has(minions[owner]["eid"]):
			remotes[minions[owner]["eid"]].set_aura(_minion_aura(owner))


func _is_sneaking(id: int) -> bool:
	if peers[id]["form"] != "":
		return false   # (a disguised demon: nothing extra goes out about it)
	return peers[id].get("sneak", false) if id != 1 else main.player.sneaking


# Flying makes a racket of wing beats that everyone nearby hears, even from a demon in disguise.
func _is_flying(id: int) -> bool:
	if id == 1:
		return main.player.flying and main.player.role == "demon"
	return peers[id].get("flying", false) and peers[id]["role"] == "demon"


# The power-up aura everyone may see on this player: only in their own body,
# never while disguised as a prop or invisible (that would give them away).
func _shown_aura(id: int) -> String:
	var rec: Dictionary = peers[id]
	if now() > rec.get("aura_until", 0.0) or rec["form"] != "" or _is_vanished(id):
		return ""
	return rec.get("aura", "")


# A minion that looks like its owner's body copies the owner's aura (or it'd be
# easy to tell which is the decoy).
func _minion_aura(owner: int) -> String:
	if not peers.has(owner) or minions[owner]["form"] != "" or now() > peers[owner].get("aura_until", 0.0):
		return ""
	return peers[owner].get("aura", "")


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
		r.team = entry[2]
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
		r.set_aura(st[5] if st.size() > 5 else "")
		r.set_flying(st.size() > 6 and st[6])
		r.set_crouch(st.size() > 7 and st[7])


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
		c_state.rpc_id(1, p.global_position, p.shown_yaw(), p.possessed_type, p.flying, p.sneaking)
		if is_instance_valid(p.minion):
			c_minion_state.rpc_id(1, p.minion.global_position, p.minion.rotation.y)


# ---------------- movement checks (host) ----------------

func _in_bounds(pos: Vector3) -> bool:
	var limit: float = main.MAP_HALF + 0.4
	return absf(pos.x) <= limit and absf(pos.z) <= limit and pos.y > -3.0 and pos.y < 25.0


@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_state(pos: Vector3, yaw: float, form: String, flying: bool, sneaking := false) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id) or not peers[id]["in_round"]:
		return
	var rec: Dictionary = peers[id]
	rec["sneak"] = sneaking
	var t := now()
	# (Two updates can arrive in the same instant; count at least one update's worth of time.)
	var dt := clampf(t - rec["last_time"], 1.0 / SEND_RATE, 1.0)
	var flat := Vector2(pos.x - rec["valid_pos"].x, pos.z - rec["valid_pos"].z).length()
	var problem := ""
	if not _in_bounds(pos):
		problem = "out of bounds"
	else:
		var max_speed := DASH_MOVE_SPEED if t < rec["dash_until"] else MAX_MOVE_SPEED
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
	if flying and not "fly" in rec["loadout"]["demon"]:
		_note_cheat(id, "flying without the Fly skill")
		_drop_to_ground(id, rec, pos)
		return
	rec["flying"] = flying   # everyone hears the wings (Ted, Nov 18: flying is a giveaway, on purpose)
	if pos.distance_to(rec["pos"]) > 0.05 or absf(wrapf(yaw - rec["yaw"], -PI, PI)) > 0.02:
		_mark_active(id)
	rec["pos"] = pos
	if t < rec.get("leap_at", -100.0) + 6.0:
		rec["leap_peak"] = maxf(rec.get("leap_peak", pos.y), pos.y)
	_record_history(id, pos)
	rec["valid_pos"] = pos
	rec["yaw"] = yaw
	rec["form"] = form
	rec["last_time"] = t
	if remotes.has(rec["eid"]):
		remotes[rec["eid"]].apply_state(pos, yaw, form, rec["role"])
	_check_flight(id, rec, pos, flying, dt, t)


# Fly hacks. The host keeps its own copy of each demon's Hatred: flying longer
# than their Hatred allows gets them dropped to the ground. And anyone hanging in
# the air for a while without flying (or a dash / pull the host approved) too.
func _check_flight(id: int, rec: Dictionary, pos: Vector3, flying: bool, dt: float, t: float) -> void:
	if rec["role"] == "demon":
		var regen := HATRED_REGEN * (PowerUps.FAST_HATRED_MULT if now() < rec.get("fast_hatred_until", 0.0) else 1.0)
		rec["hatred"] = clampf(rec["hatred"] + regen * dt - (HATRED_FLY_DRAIN * dt if flying else 0.0), -50.0, 100.0)
		if flying and rec["hatred"] < -15.0:
			rec["hatred"] = 0.0
			_note_cheat(id, "flying without enough Hatred")
			_drop_to_ground(id, rec, pos)
			return
	if main.near_pad(pos):
		rec["bounce_until"] = t + 6.0   # a bounce: up to ~5 s in the air is fine
	var excused: bool = flying or t < rec["grace_until"] or t < rec["dash_until"] or t < rec.get("bounce_until", 0.0)
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
func on_local_launched(origin: Vector3, velocity: Vector3, kind: String, gravity: float, seq: int) -> void:
	if not main.in_online_round():
		return
	if is_host:
		for id in _client_ids():
			s_projectile.rpc_id(id, origin, velocity, kind, gravity)
	else:
		c_throw.rpc_id(1, origin, velocity, kind, gravity, seq)


@rpc("any_peer", "call_remote", "reliable")
func c_throw(origin: Vector3, velocity: Vector3, kind: String, gravity: float, seq: int) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id):
		return
	var rec: Dictionary = peers[id]
	if not rec["in_round"] or rec["role"] != "angel" or phase != "hunting":
		return
	if not Blessings.KINDS.has(kind) or velocity.length() > 85.0 or gravity < 3.9 or gravity > 16.1:
		return
	if not _origin_ok(rec, origin):
		_note_cheat(id, "throwing from somewhere they aren't")
		return
	# Mirror the blessing stamina so a hacked client can't throw endlessly.
	# (A little slack for network timing.)
	var t := now()
	var regen := THROW_REGEN * (6.0 if t < rec.get("quick_throw_until", 0.0) else 1.0) * GameRules.f("stamina")
	rec["stamina"] = minf(rec["stamina"] + regen * (t - rec["stamina_time"]), THROW_STAMINA_MAX)
	rec["stamina_time"] = t
	if rec["stamina"] < -THROW_COST:
		_note_cheat(id, "throwing faster than stamina allows")
		return
	rec["stamina"] -= THROW_COST
	rec["throws"] += 1
	# Remember the throw: it can hurt a demon once, either by the host's own copy
	# hitting, or by the thrower's claim that it hit on their screen (checked below).
	var throws: Dictionary = rec.get("throw_log", {})
	for old_seq in throws.keys():
		if t - throws[old_seq]["t"] > 4.0:
			throws.erase(old_seq)
	throws[seq] = {"origin": origin, "vel": velocity, "g": gravity, "t": t, "used": false}
	rec["throw_log"] = throws
	var p := Projectile.new()
	p.color = Blessings.color(kind)
	p.kind = kind
	p.shooter = remotes.get(rec["eid"])
	p.gravity = gravity
	p.gate = func(): return _use_throw(id, seq)
	main.add_child(p)
	p.global_position = origin
	p.velocity = velocity
	for other in _client_ids():
		if other != id:
			s_projectile.rpc_id(other, origin, velocity, kind, gravity)


func _use_throw(id: int, seq: int) -> bool:
	if not peers.has(id):
		return false
	var entry = peers[id].get("throw_log", {}).get(seq)
	if entry == null or entry["used"]:
		return false
	entry["used"] = true
	return true


@rpc("authority", "call_remote", "reliable")
func s_projectile(origin: Vector3, velocity: Vector3, kind: String, gravity: float) -> void:
	var p := Projectile.new()
	p.color = Blessings.color(kind)
	p.kind = kind
	p.visual_only = true
	p.gravity = gravity
	main.add_child(p)
	p.global_position = origin
	p.velocity = velocity


# ---- "My throw hit them on my screen" ----
# Everyone sees other players a moment in the past (network delay plus smoothing),
# so a throw that clearly hit on the thrower's screen can miss where the host has
# them now. The thrower says which throw hit whom and where; the host believes it
# only if all of this checks out:
#   - it's a real, recent throw of theirs that hasn't hurt anyone yet,
#   - the hit point lies on that throw's flight path, with no wall in between,
#   - the demon really was at that spot within the last moment.
func claim_hit(seq: int, eid: int, point: Vector3) -> void:
	c_hit_claim.rpc_id(1, seq, eid, point)


@rpc("any_peer", "call_remote", "reliable")
func c_hit_claim(seq: int, eid: int, point: Vector3) -> void:
	if not is_host or phase != "hunting":
		return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id):
		return
	var rec: Dictionary = peers[id]
	var entry = rec.get("throw_log", {}).get(seq)
	var target := _peer_for_eid(eid)
	var why := ""
	var t_fly := -1.0
	if entry == null:
		why = "no such throw"
	elif entry["used"]:
		why = "that throw already hit"
	elif _minion_owner(eid) != 0:
		# A minion: same path and wall checks, and it must have been near there.
		t_fly = _time_on_path(entry, point)
		var mpos: Vector3 = minions[_minion_owner(eid)]["pos"]
		if t_fly < 0.0 or not _path_clear(entry, t_fly, id, 0) or Vector2(point.x - mpos.x, point.z - mpos.z).length() > 3.0:
			why = "missed the minion"
		else:
			entry["used"] = true
			if minion_hit(_minion_owner(eid), null, Projectile.DAMAGE):
				rec["hits"] += 1
				s_hit_confirm.rpc_id(id)
			return
	elif target == 0 or target == id or peers[target]["role"] != "demon":
		why = "not a demon"
	else:
		t_fly = _time_on_path(entry, point)
	if why != "":
		pass
	elif t_fly < 0.0:
		why = "not on that throw's path"
	elif not _path_clear(entry, t_fly, id, target):
		why = "through a wall"
	elif not _was_near(target, point, entry["t"] + t_fly):
		why = "the demon wasn't there"
	if why != "":
		print("[host] refused %s's hit claim: %s" % [rec["name"], why])
		return
	entry["used"] = true
	print("[host] %s's hit claim on %s accepted" % [rec["name"], peers[target]["name"]])
	if damage_player(target, Projectile.DAMAGE, id):
		rec["hits"] += 1
		s_hit_confirm.rpc_id(id)


# When the throw passes within 0.6 m of the point (seconds after the throw), or -1.
func _time_on_path(entry: Dictionary, point: Vector3) -> float:
	var g := Vector3(0, -entry["g"], 0)
	var best := INF
	var best_t := -1.0
	var tt := 0.0
	while tt <= Projectile.LIFETIME:
		var p: Vector3 = entry["origin"] + entry["vel"] * tt + 0.5 * g * tt * tt
		var d := p.distance_to(point)
		if d < best:
			best = d
			best_t = tt
		tt += 0.005
	return best_t if best <= 0.6 else -1.0


# No wall, building or plain prop between the throw and the hit (players don't count).
func _path_clear(entry: Dictionary, t_hit: float, thrower: int, target: int) -> bool:
	var g := Vector3(0, -entry["g"], 0)
	var skip := []
	for pid in peers:
		var node = main.player if pid == 1 else remotes.get(peers[pid]["eid"])
		if node is CollisionObject3D:
			skip.append(node)
	var steps := maxi(int(t_hit / 0.02), 1)
	var prev: Vector3 = entry["origin"]
	for i in range(1, steps + 1):
		var tt := t_hit * i / steps - 0.03 * float(i == steps)
		var p: Vector3 = entry["origin"] + entry["vel"] * tt + 0.5 * g * tt * tt
		var hit: Dictionary = main._ray(prev, p, skip)
		if not hit.is_empty():
			return false
		prev = p
	return true


# Was that demon's body at this point at about that time? Generous with time
# (lag + smoothing), strict with distance.
func _was_near(id: int, point: Vector3, when: float) -> bool:
	var form: String = peers[id]["form"]
	var reach := 1.0 if form == "" else 1.4
	for h in peers[id].get("hist", []):
		if h[0] < when - 1.0 or h[0] > when + 0.3:
			continue
		var pos: Vector3 = h[1]
		var flat := Vector2(point.x - pos.x, point.z - pos.z).length()
		if flat <= reach and point.y > pos.y - 0.4 and point.y < pos.y + 2.6:
			return true
	return false


# Host: remember where everyone was over the last couple of seconds.
func _record_history(id: int, pos: Vector3) -> void:
	var t := now()
	var hist: Array = peers[id].get("hist", [])
	hist.append([t, pos])
	while not hist.is_empty() and t - hist[0][0] > 2.5:
		hist.pop_front()
	peers[id]["hist"] = hist


func _peer_for_eid(eid: int) -> int:
	for id in peers:
		if peers[id]["eid"] == eid and peers[id]["in_round"]:
			return id
	return 0


# A host projectile hit a joined player (or a minion).
func on_remote_hit(remote, damage: int, by: Node = null) -> bool:
	var owner := _minion_owner(remote.eid)
	if owner != 0:
		return minion_hit(owner, by, damage)
	return damage_player(_peer_for_eid(remote.eid), damage, peer_of(by))


# ---------------- Minions ----------------
# The demon who made it runs it and sends us where it is; we show it to everyone
# else exactly like a player (random id, no name, role demon, in the roster).

var minions := {}   # owner's peer id -> {eid, pos, yaw, form, hp, until, last_time}


func _minion_owner(eid: int) -> int:
	for owner in minions:
		if minions[owner]["eid"] == eid:
			return owner
	return 0


func minion_spawned(owner: int, point: Vector3, form_index: int) -> void:
	if not peers.has(owner):
		return
	if minions.has(owner):
		_minion_gone(owner, true)
	var rec: Dictionary = peers[owner]
	if point.distance_to(rec["pos"]) > Skills.MINION_RANGE + 5.0 or not _in_bounds(point):
		if owner != 1:
			s_minion_gone.rpc_id(owner)   # too far away: no minion
		return
	# A copy of their own body, or (disguised) a kind of prop that's really on this map.
	var types: Array = PropLib.type_names()
	var form := ""
	if form_index >= 0 and form_index < types.size() and main.map_has_prop_type(types[form_index]):
		form = types[form_index]
	var m := {"eid": _new_eid(), "pos": main.ground_below(point + Vector3.UP), "yaw": rec["yaw"],
		"form": form, "hp": PropLib.max_hp(rec["form"]) * Skills.MINION_HEALTH, "until": now() + Skills.MINION_LIFETIME, "last_time": now()}
	minions[owner] = m
	_send_looks()   # (the minion dresses like its owner)
	if owner != 1:
		var r := _get_or_make_remote(m["eid"])
		r.net = self
		r.snap = true
		r.apply_state(m["pos"], m["yaw"], m["form"], "demon")
	_send_rosters()
	print("[host] %s sent out a minion" % rec["name"])


@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_minion_state(pos: Vector3, yaw: float) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if not minions.has(id):
		return
	var m: Dictionary = minions[id]
	var t := now()
	var dt := clampf(t - m["last_time"], 1.0 / SEND_RATE, 1.0)
	var flat := Vector2(pos.x - m["pos"].x, pos.z - m["pos"].z).length()
	# Same speed limit as the form it copies (it's not allowed to be a cheat-mobile).
	if flat > PropLib.speed(m["form"]) * 1.6 * dt + 1.0 or not _in_bounds(pos):
		return
	m["last_time"] = t
	m["pos"] = pos
	m["yaw"] = yaw
	if remotes.has(m["eid"]):
		remotes[m["eid"]].apply_state(pos, yaw, m["form"], "demon")


# An angel hit a minion: same hit marker and sound as hitting a real demon, and
# it has the same health a real demon in that form would. Nobody is actually hurt.
func minion_hit(owner: int, _by: Node, damage: int) -> bool:
	if not minions.has(owner) or phase != "hunting":
		return false
	var m: Dictionary = minions[owner]
	m["hp"] -= roundi(damage * GameRules.f("damage"))
	grant_hatred(owner, Skills.NAUGHTY_MINION_HIT, "your minion fooled an angel")
	print("[host] a minion was hit")
	if m["hp"] <= 0:
		_minion_gone(owner, true)
	return true


func _minion_gone(owner: int, popped: bool) -> void:
	if not minions.has(owner):
		return
	var m: Dictionary = minions[owner]
	minions.erase(owner)
	if popped:
		main.broadcast_fx("minion_pop", [m["pos"]])
	_remove_remote(m["eid"])
	for id in _client_ids():
		s_remove.rpc_id(id, m["eid"])
	if owner == 1:
		if is_instance_valid(main.player.minion):
			main.player.minion.queue_free()
	elif peers.has(owner):
		s_minion_gone.rpc_id(owner)
	_send_rosters()
	print("[host] a minion popped")


@rpc("authority", "call_remote", "reliable")
func s_minion_gone() -> void:
	if is_instance_valid(main.player.minion):
		main.player.minion.queue_free()


# Which player a body belongs to (0 if none): our own player is the host (1).
func peer_of(node) -> int:
	if node == null or not is_instance_valid(node):
		return 0
	if node == main.player:
		return 1
	if node is RemotePlayer:
		return _peer_for_eid(node.eid)
	return 0


func on_remote_confirm(remote) -> void:
	var id := _peer_for_eid(remote.eid)
	if id != 0:
		peers[id]["hits"] += 1
		s_hit_confirm.rpc_id(id)


@rpc("authority", "call_remote", "reliable")
func s_hit_confirm() -> void:
	main.player.confirm_hit()


func damage_player(id: int, damage: int, by := 0) -> bool:
	if not is_host or not peers.has(id) or phase != "hunting":
		return false
	var rec: Dictionary = peers[id]
	if rec["role"] != "demon" or not rec["in_round"]:
		return false
	if by != 0:
		rec["last_hit_by"] = by
	main.powerups.angels_made_progress()
	# Health is kept as a fraction, so switching forms keeps your percentage:
	# the same hit hurts a stack of books (50 hp) more than a hay bale (150 hp).
	rec["hp"] -= float(damage) * GameRules.f("damage") / PropLib.max_hp(rec["form"])
	var left := maxf(rec["hp"], 0.0)
	if id == 1:
		main.online_you_hit(left)
	else:
		s_you_hit.rpc_id(id, left)
	if rec["hp"] <= 0.0:
		_catch(id)
	return true


@rpc("authority", "call_remote", "reliable")
func s_you_hit(health_fraction: float) -> void:
	main.online_you_hit(clampf(health_fraction, 0.0, PowerUps.MAX_HEALTH))


# Mobification: a caught demon is redeemed and joins the angels.
func _catch(id: int, how := "") -> void:
	var rec: Dictionary = peers[id]
	var where: Vector3 = rec["pos"]
	main.powerups.demon_caught(where)   # every saved soul drops an angel power-up
	_minion_gone(id, true)   # a caught demon's minion goes with them
	main.authority_release(id, where, rec["yaw"])   # a possessed prop stays behind, dissolving
	_reset_round_mirrors(rec)
	rec["role"] = "angel"
	rec["redeemed"] = true
	rec["form"] = ""
	rec["health"] = DEMON_HEALTH
	rec["stamina"] = THROW_STAMINA_MAX
	rec["stamina_time"] = now()
	_place(rec, main.spawn_point("angel", randi() % 4))
	var by: int = rec.get("last_hit_by", 0)
	var by_name: String = peers[by]["name"] if peers.has(by) else ""
	rec["last_hit_by"] = 0
	print("[host] %s was caught" % rec["name"])
	# Names first: the redeemed player must lose their old teammates' names
	# before they're told they switched sides (and angels learn theirs).
	_send_rosters()
	if id == 1:
		main.online_you_were_caught(rec["pos"], by_name)
	else:
		s_you_were_caught.rpc_id(id, rec["pos"], by_name)
	_show_team_powerups(id)   # (their old team's power-ups vanish on their side)
	# Everyone hears about it: "Ava redeemed Ben!"
	var news := ("%s redeemed %s!" % [by_name, rec["name"]]) if by_name != "" else ("%s was redeemed!" % rec["name"])
	if how != "":
		news = how
	print("[host] " + news)
	main.announce(news)
	for other in _client_ids():
		s_announce.rpc_id(other, news)
		if remotes.has(rec["eid"]):
			remotes[rec["eid"]].apply_state(rec["pos"], rec["yaw"], "", "angel")
	_broadcast_count()   # count first, so "N left" messages are up to date
	# Down to the last demon (and there were more to begin with): everyone hears who.
	if _demons_left() == 1 and _start_demons > 1:
		for pid in peers:
			if peers[pid]["in_round"] and peers[pid]["role"] == "demon":
				var last := "%s is the LAST demon standing!" % peers[pid]["name"]
				print("[host] " + last)
				main.announce(last)
				for other in _client_ids():
					s_announce.rpc_id(other, last)
	main.online_caught_fx(where)
	for other in _client_ids():
		s_caught_fx.rpc_id(other, where)
	_check_round_over()


@rpc("authority", "call_remote", "reliable")
func s_you_were_caught(pos: Vector3, by_name: String) -> void:
	main.online_you_were_caught(pos, by_name.substr(0, 16))


@rpc("authority", "call_remote", "reliable")
func s_announce(text: String) -> void:
	main.announce(text.substr(0, 80))


@rpc("authority", "call_remote", "reliable")
func s_caught_fx(pos: Vector3) -> void:
	main.online_caught_fx(pos)


# ---------------- taunts ----------------

func on_local_taunt(taunt_name: String) -> void:
	if not main.in_online_round():
		return
	if is_host:
		peers[1]["last_taunt"] = now()
		_taunt_bonus(1)
		for id in _client_ids():
			s_taunt.rpc_id(id, my_eid, taunt_name)
	else:
		c_taunt.rpc_id(1, taunt_name)


# ---- Hatred for naughtiness ----

func grant_hatred(id: int, amount: float, reason: String) -> void:
	if not peers.has(id) or peers[id]["role"] != "demon" or not peers[id]["in_round"]:
		return
	peers[id]["hatred"] = minf(peers[id]["hatred"] + amount, HATRED_MAX_MIRROR)   # keep the mirror in step
	print("[host] %s +%d Hatred: %s" % [peers[id]["name"], int(amount), reason])
	if id == 1:
		main.player.add_hatred(amount, reason)
	else:
		s_hatred_bonus.rpc_id(id, amount, reason)


@rpc("authority", "call_remote", "reliable")
func s_hatred_bonus(amount: float, reason: String) -> void:
	main.player.add_hatred(clampf(amount, 0.0, 50.0), reason.substr(0, 60))


# Taunting with an angel close by is naughty (a little Hatred, at most every 6 s).
func _taunt_bonus(id: int) -> void:
	var rec: Dictionary = peers[id]
	if rec["role"] != "demon" or phase != "hunting" or now() - rec.get("taunt_bonus_at", -100.0) < 6.0:
		return
	for other in peers:
		if peers[other]["in_round"] and peers[other]["role"] == "angel" \
				and peers[other]["pos"].distance_to(rec["pos"]) <= Skills.NAUGHTY_TAUNT_RANGE:
			rec["taunt_bonus_at"] = now()
			grant_hatred(id, Skills.NAUGHTY_TAUNT, "taunting right under an angel's nose")
			return


# ---- Power-ups ----

func team_entries() -> Array:
	var out := []
	for id in peers:
		var rec: Dictionary = peers[id]
		if not rec["in_round"]:
			continue
		if id == 1:
			out.append([1, main.player, rec["role"]])
		elif remotes.has(rec["eid"]):
			out.append([id, remotes[rec["eid"]], rec["role"]])
	return out


func give_powerup(id: int, kind: String) -> void:
	if not peers.has(id):
		return
	var rec: Dictionary = peers[id]
	var until: float = now() + PowerUps.DURATION.get(kind, 0.0) + 0.5   # (a little slack for the mirrors)
	match kind:
		"fast_hatred": rec["fast_hatred_until"] = until
		"quick_throw": rec["quick_throw_until"] = until
		"quick_skills":
			rec["quick_skills_until"] = until
			rec["skill_ready"].clear()   # every cooldown starts over at zero (Ted, Nov 18)
		"sense": rec["sense_until"] = until
	if Aura.KINDS.has(kind):
		rec["aura"] = kind
		rec["aura_until"] = until
	print("[host] %s picked up %s" % [rec["name"], kind])
	if id == 1:
		main.player.apply_powerup(kind)
	else:
		s_powerup.rpc_id(id, kind)


@rpc("authority", "call_remote", "reliable")
func s_powerup(kind: String) -> void:
	if PowerUps.LABELS.has(kind):
		main.player.apply_powerup(kind)


@rpc("any_peer", "call_remote", "reliable")
func c_bouncy_used(id: int) -> void:
	if not is_host:
		return
	var who := multiplayer.get_remote_sender_id()
	if not peers.has(who) or not main.bouncies.has(id) or not is_instance_valid(main.bouncies[id]):
		return
	# They must really be standing by it.
	if peers[who]["pos"].distance_to(main.bouncies[id].global_position) > 4.0:
		return
	main.bouncy_used(id, who)


# Unholy Mending: +50% of a demon's starting health, up to 150% (demons can be
# tougher than they started out).
func heal_player(id: int) -> void:
	if not peers.has(id) or peers[id]["role"] != "demon":
		return
	var hp: float = minf(peers[id]["hp"] + PowerUps.HEAL_AMOUNT, PowerUps.MAX_HEALTH)
	peers[id]["hp"] = hp
	print("[host] %s healed up to %d%%" % [peers[id]["name"], int(round(hp * 100.0))])
	if id == 1:
		main.online_you_hit(hp)
		main.player.powerup_taken.emit("heal")
	else:
		s_you_hit.rpc_id(id, hp)
		s_healed.rpc_id(id)


@rpc("authority", "call_remote", "reliable")
func s_healed() -> void:
	main.player.powerup_taken.emit("heal")


# Holy Word struck this flier down: they drop, can't fly till they land, and are stunned a moment.
func strike_down(id: int, seconds: float) -> void:
	if id == 1:
		main.player.strike_down(seconds)
		return
	if not peers.has(id):
		return
	var rec: Dictionary = peers[id]
	rec["grace_until"] = now() + 2.0                    # (dropping fast is fine)
	rec["locked_until"] = maxf(rec["locked_until"], now() + seconds)
	s_struck.rpc_id(id, seconds)


@rpc("authority", "call_remote", "reliable")
func s_struck(seconds: float) -> void:
	print("[net] struck down!")
	main.player.strike_down(seconds)
	main.online_struck()


func scare_player(id: int, from: Vector3, seconds: float) -> void:
	if id == 1:
		main.player.scare(from, seconds)
	elif peers.has(id):
		peers[id]["grace_until"] = now() + seconds + 0.5
		s_scared.rpc_id(id, from, seconds)


@rpc("authority", "call_remote", "reliable")
func s_scared(from: Vector3, seconds: float) -> void:
	print("[net] scared!")
	main.player.scare(from, seconds)


func burn_player(id: int, seconds: float) -> void:
	if id == 1:
		main.player.burning = maxf(main.player.burning, seconds)
	elif peers.has(id):
		s_burn.rpc_id(id, seconds)


@rpc("authority", "call_remote", "reliable")
func s_burn(seconds: float) -> void:
	main.player.burning = maxf(main.player.burning, clampf(seconds, 0.0, 6.0))


# Angels with Cherub Sense: is a demon (or minion) close? Only a yes/no is sent.
func check_sense() -> void:
	var demons := demon_nodes()
	for id in peers:
		var rec: Dictionary = peers[id]
		var sensing: bool = rec["in_round"] and rec["role"] == "angel" and now() < rec.get("sense_until", 0.0)
		var near := false
		if sensing:
			for d in demons:
				if d.global_position.distance_to(rec["pos"]) <= Skills.CHERUB_RADIUS:
					near = true
					break
		if near != rec.get("sense_near", false):
			rec["sense_near"] = near
			if id == 1:
				main.player.sense_alarm = near
			else:
				s_sense.rpc_id(id, near)


@rpc("authority", "call_remote", "reliable")
func s_sense(near: bool) -> void:
	main.player.sense_alarm = near


# ---- Invisibility and Teleport ----

func set_vanished(id: int, seconds: float) -> void:
	if not peers.has(id):
		return
	var rec: Dictionary = peers[id]
	rec["vanish_until"] = now() + seconds
	# Angels stop getting this demon's position at all (no seeing through it with a
	# hacked game), and their copy of it disappears right away.
	for viewer in peers:
		if peers[viewer]["role"] != "angel":
			continue
		if viewer == 1:
			if remotes.has(rec["eid"]):
				remotes[rec["eid"]].vanish(seconds)
		else:
			s_vanish.rpc_id(viewer, rec["eid"], seconds)
	print("[host] %s vanished" % rec["name"])


func _is_vanished(id: int) -> bool:
	return peers.has(id) and now() < peers[id].get("vanish_until", 0.0)


@rpc("authority", "call_remote", "reliable")
func s_vanish(eid: int, seconds: float) -> void:
	if remotes.has(eid):
		remotes[eid].vanish(clampf(seconds, 0.0, 10.0))


func teleport_player(id: int, dest: Vector3) -> void:
	if not peers.has(id):
		return
	_place(peers[id], dest)
	if id == 1:
		main.player.teleport_to(dest)
	else:
		s_teleport.rpc_id(id, dest)


@rpc("authority", "call_remote", "reliable")
func s_teleport(dest: Vector3) -> void:
	main.player.teleport_to(dest)


func angel_nodes() -> Array:
	var out := []
	for id in peers:
		var rec: Dictionary = peers[id]
		if not rec["in_round"] or rec["role"] != "angel":
			continue
		if id == 1:
			out.append(main.player)
		elif remotes.has(rec["eid"]):
			out.append(remotes[rec["eid"]])
	return out


func _valid_taunt(role: String, taunt_name: String) -> bool:
	var parts := taunt_name.split(":")
	if parts.size() != 2 or parts[0] != role:
		return false
	return parts[1] == "signature" or Taunts.TAUNTS[role].has(parts[1])


# ---------- animated props (E) ----------

func on_local_animate(n: int) -> void:
	if not main.in_online_round():
		return
	if is_host:
		_host_animate(1, n)
	else:
		c_animate.rpc_id(1, n)


@rpc("any_peer", "call_remote", "reliable")
func c_animate(n: int) -> void:
	if is_host:
		_host_animate(multiplayer.get_remote_sender_id(), n)


# A disguised demon pressed E: show it on every other screen (by entity id, like a taunt: nothing new for an
# angel's game to learn), and if it's an explosive, light the fuse.
func _host_animate(id: int, n: int) -> void:
	if not peers.has(id) or not peers[id]["in_round"]:
		return
	var rec: Dictionary = peers[id]
	var form: String = rec.get("form", "")
	if rec["role"] != "demon" or form == "" or not PropLib.PropAnims.can_animate(form):
		return
	var t := now()
	if t - rec.get("anim_at", -100.0) < PropLib.PropAnims.COOLDOWN * 0.8 or rec.get("fuse_form", "") != "":
		return
	rec["anim_at"] = t
	n = clampi(n, 1, 100000)
	if id != 1 and remotes.has(rec["eid"]):
		remotes[rec["eid"]].play_anim(n)
	for other in _client_ids():
		if other != id:
			s_prop_anim.rpc_id(other, rec["eid"] if id != 1 else my_eid, n)
	if PropLib.PropAnims.is_explosive(form):
		rec["fuse_form"] = form
		print("[host] %s lit a fuse" % rec["name"])
		get_tree().create_timer(PropLib.PropAnims.FUSE_TIME).timeout.connect(_kaboom.bind(id))


@rpc("authority", "call_remote", "reliable")
func s_prop_anim(eid: int, n: int) -> void:
	print("[net] a prop animated")
	if remotes.has(eid):
		remotes[eid].play_anim(clampi(n, 1, 100000))


# The fuse burned down: the demon goes up with it (and is caught, with nobody to thank), and angels close by
# are dazed for a moment.
func _kaboom(id: int) -> void:
	if not peers.has(id):
		return
	var rec: Dictionary = peers[id]
	var form: String = rec.get("fuse_form", "")
	rec["fuse_form"] = ""
	if not rec["in_round"] or rec["role"] != "demon" or rec.get("form", "") != form or not main.in_online_round():
		return
	var pos: Vector3 = rec["pos"]
	print("[host] %s blew up" % rec["name"])
	main.broadcast_fx("kaboom", [pos])
	for other in peers:
		var o: Dictionary = peers[other]
		if other != id and o["in_round"] and o["role"] == "angel" and o["pos"].distance_to(pos) <= PropLib.PropAnims.KABOOM_RADIUS * GameRules.f("blast"):
			daze_player(other, PropLib.PropAnims.KABOOM_DAZE)
	rec["last_hit_by"] = 0   # (nobody got them: they did it themselves)
	_catch(id, "%s blew up!" % rec["name"])


func daze_player(id: int, seconds: float) -> void:
	if id == 1:
		main.online_dazed(seconds)
	elif peers.has(id):
		peers[id]["grace_until"] = now() + seconds + 0.5
		s_dazed.rpc_id(id, seconds)


@rpc("authority", "call_remote", "reliable")
func s_dazed(seconds: float) -> void:
	main.online_dazed(clampf(seconds, 0.0, 3.0))


@rpc("any_peer", "call_remote", "reliable")
func c_taunt(taunt_name: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id) or not peers[id]["in_round"]:
		return
	var rec: Dictionary = peers[id]
	var t := now()
	_mark_active(id)
	if t - rec["last_taunt"] < 0.5 or not _valid_taunt(rec["role"], taunt_name):
		return
	rec["last_taunt"] = t
	_taunt_bonus(id)
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


# ---------------- the shrine (mid-round skill swaps) ----------------

func shrine_open() -> void:
	if is_host:
		_shrine_open(1)
	else:
		c_shrine_open.rpc_id(1)


func shrine_swap(skills: Array) -> void:
	if is_host:
		_shrine_swap(1, skills)
	else:
		c_shrine_swap.rpc_id(1, skills)


@rpc("any_peer", "call_remote", "reliable")
func c_shrine_open() -> void:
	if is_host:
		_shrine_open(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func c_shrine_swap(skills: Array) -> void:
	if is_host:
		_shrine_swap(multiplayer.get_remote_sender_id(), skills)


func _shrine_open(id: int) -> void:
	if not peers.has(id) or not peers[id]["in_round"]:
		return
	var rec: Dictionary = peers[id]
	var pos: Vector3 = main.player.global_position if id == 1 else rec["pos"]
	if not main.near_shrine(pos) or (rec["form"] != "" and id != 1):
		return
	rec["shrine_at"] = now()
	main.broadcast_fx("shrine", [])
	print("[host] %s is at the shrine" % rec["name"])


func _shrine_swap(id: int, skills: Array) -> void:
	if not peers.has(id) or not peers[id]["in_round"]:
		return
	var rec: Dictionary = peers[id]
	var pos: Vector3 = main.player.global_position if id == 1 else rec["pos"]
	# Angels waiting out the hiding period swap anywhere, straight away, and their skills are ready.
	if rec["role"] == "angel" and phase == "hiding":
		rec["loadout"]["angel"] = Skills.clean_loadout("angel", skills)
		for skill in rec["loadout"]["angel"]:
			rec["skill_ready"].erase(skill)
		print("[host] %s picked skills while waiting: %s" % [rec["name"], "+".join(rec["loadout"]["angel"])])
		return
	# The full swap time has to have passed (a little slack for lag), standing at the shrine.
	if now() - rec.get("shrine_at", -100.0) < 2.7 or not main.near_shrine(pos):
		if id != 1:
			_note_cheat(id, "swapping skills without the shrine")
		return
	rec["shrine_at"] = -100.0
	rec["loadout"][rec["role"]] = Skills.clean_loadout(rec["role"], skills)
	rec["skill_ready"].clear()   # a swap refreshes every cooldown (Ted, Nov 20)
	print("[host] %s swapped skills at the shrine: %s" % [rec["name"], "+".join(rec["loadout"][rec["role"]])])


# ---------------- chat ----------------

func send_chat(text: String, team_only: bool) -> void:
	if is_host:
		_relay_chat(1, text, team_only)
	else:
		c_chat.rpc_id(1, text, team_only)


@rpc("any_peer", "call_remote", "reliable")
func c_chat(text: String, team_only: bool) -> void:
	if is_host:
		_relay_chat(multiplayer.get_remote_sender_id(), text, team_only)


func _relay_chat(id: int, text: String, team_only: bool) -> void:
	if not peers.has(id):
		return
	_mark_active(id)
	var rec: Dictionary = peers[id]
	var t := now()
	if t < rec.get("chat_ready", 0.0):
		return                         # spam limit
	rec["chat_ready"] = t + 0.6
	text = text.strip_edges().substr(0, 120)
	if text == "":
		return
	var in_round: bool = phase == "hiding" or phase == "hunting"
	var sender_role: String = rec["role"] if in_round and rec["in_round"] else ""
	for to in peers:
		if team_only and peers[to]["role"] != rec["role"]:
			continue
		if to == 1:
			main.show_chat(rec["name"], sender_role, text, team_only)
		else:
			s_chat.rpc_id(to, rec["name"], sender_role, text, team_only)


@rpc("authority", "call_remote", "reliable")
func s_chat(sender: String, sender_role: String, text: String, team_only: bool) -> void:
	main.show_chat(sender.substr(0, 16), sender_role, text.substr(0, 120), team_only)


# Skills start at the player's camera, which can sit ~4 m behind them in third person.
func _origin_ok(rec: Dictionary, origin: Vector3) -> bool:
	# Mid-dash a player covers a lot of ground between position updates.
	var slack := 9.0 if now() < rec.get("dash_until", 0.0) else 5.0
	return origin.distance_to(rec["pos"] + Vector3.UP * 1.3) <= slack


# Is this player allowed to use this skill right now? (Also starts its cooldown.)
func _skill_allowed(id: int, skill: String, origin: Vector3) -> bool:
	if not peers.has(id):
		return false
	var rec: Dictionary = peers[id]
	var t := now()
	if not rec["in_round"] or not Skills.SKILLS.has(skill):
		return false
	var picked: String = Skills.SKILLS[skill].get("part_of", skill)   # Cloud Stomp comes with Holy Leap
	if Skills.SKILLS[skill]["team"] != rec["role"] or not picked in rec["loadout"][rec["role"]]:
		return false
	if skill == "stomp":
		if t > rec.get("leap_at", -100.0) + 6.0:
			return false    # one stomp per leap, soon after it
		rec["leap_at"] = -100.0
	if rec["role"] == "angel" and phase != "hunting":
		return false
	if rec["role"] == "demon" and phase != "hiding" and phase != "hunting":
		return false
	if rec["role"] == "demon" and t < rec["locked_until"]:
		print("[host] refused %s's %s: skills locked (vacuumed or smitten)" % [rec["name"], skill])
		return false
	if t + 0.3 < rec["skill_ready"].get(skill, 0.0):   # a little slack for lag
		return false
	if not _origin_ok(rec, origin):
		_note_cheat(id, "using a skill from somewhere they aren't")
		return false
	var cost := Skills.hatred_cost(skill)
	if cost > 0.0 and id != 1:   # the host's own Hatred is counted on its own player
		if rec["hatred"] < cost - 10.0:   # the mirror lags a little behind the player's own count
			_note_cheat(id, "casting %s without enough Hatred" % skill)
			return false
		rec["hatred"] -= cost
	if skill == "leap":   # (pressed mid-air: the Cloud Stomp is on its way down; count the jump before it too)
		rec["leap_at"] = t
		var peak: float = origin.y
		for h in rec.get("hist", []):
			if t - h[0] < 2.5:
				peak = maxf(peak, h[1].y)
		rec["leap_peak"] = peak
	var cd := Skills.cooldown(skill) / (3.0 if t < rec.get("quick_skills_until", 0.0) else 1.0)
	rec["skill_ready"][skill] = t + cd
	return true


# Cloud Stomp from a joined player: how far they really came down (what the host saw, plus a little slack).
func leap_drop(id: int, landed: Vector3) -> float:
	if not peers.has(id):
		return 0.0
	return maxf(peers[id].get("leap_peak", landed.y) - landed.y + 1.0, 0.0)


func on_local_skill(skill: String, origin: Vector3, dir: Vector3, point: Vector3, index: int) -> void:
	if not main.in_online_round():
		return
	if is_host:
		peers[1]["pos"] = main.player.global_position
		if _skill_allowed(1, skill, origin):
			main.authority_skill(main.player, 1, skill, origin, dir.normalized(), point, index)
		else:
			print("[host] refused my own %s (phase %s)" % [skill, phase])
	else:
		c_skill.rpc_id(1, skill, origin, dir, point, index)


@rpc("any_peer", "call_remote", "reliable")
func c_skill(skill: String, origin: Vector3, dir: Vector3, point: Vector3, index: int) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _skill_allowed(id, skill, origin):
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
		main.authority_release(1, main.player.global_position, main.player.shown_yaw())
	else:
		c_release.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func c_release() -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if peers.has(id) and peers[id]["in_round"]:
		main.authority_release(id, peers[id]["pos"], peers[id]["yaw"])


func grant_dash(id: int) -> void:
	if peers.has(id):
		peers[id]["dash_until"] = now() + DASH_WINDOW


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
	# Minions count as demons for anything that looks for demons nearby.
	for owner in minions:
		if owner == 1 and is_instance_valid(main.player.minion):
			out.append(main.player.minion)
		elif remotes.has(minions[owner]["eid"]):
			out.append(remotes[minions[owner]["eid"]])
	return out


# Only the host keeps `phase`; everyone else goes by their own game's state (playtest, Nov 26: joined
# players' bumps were never sent, because `phase` on their computers stays "lobby" all round).
func in_round_now() -> bool:
	if is_host:
		return phase == "hiding" or phase == "hunting"
	return main.state == main.State.HIDING or main.state == main.State.HUNTING


# A player ran into a loose prop (prop >= 0) or a disguised demon (eid >= 0): the host checks they were
# really right next to it, then shoves it.
func request_bump(prop: int, eid: int, push: Vector3) -> void:
	if is_host:
		_bump(1, prop, eid, push)
	else:
		c_bump.rpc_id(1, prop, eid, push)


@rpc("any_peer", "call_remote", "unreliable")
func c_bump(prop: int, eid: int, push: Vector3) -> void:
	if is_host:
		_bump(multiplayer.get_remote_sender_id(), prop, eid, push)


func _bump(id: int, prop: int, eid: int, push: Vector3) -> void:
	if not peers.has(id) or not peers[id]["in_round"] or not in_round_now():
		return
	var rec: Dictionary = peers[id]
	var pos: Vector3 = main.player.global_position if id == 1 else rec["pos"]
	var t := now()
	var key := "p%d" % prop if prop >= 0 else "e%d" % eid
	var ready: Dictionary = rec.get("bump_ready", {})
	if t < ready.get(key, 0.0):
		return   # (rate limit: one shove of the same thing every 0.3 s)
	ready[key] = t + 0.3
	rec["bump_ready"] = ready
	var thing: Node = null
	if prop >= 0 and prop < main.props.size() and is_instance_valid(main.props[prop]):
		thing = main.props[prop]
	elif eid >= 0 and remotes.has(eid):
		thing = remotes[eid]
	elif eid == my_eid:
		thing = main.player
	if thing == null or (thing as Node3D).global_position.distance_to(pos) > 3.5:
		return   # nowhere near it
	if id != 1:
		print("[bump] player %d shoved %s" % [id, key])
	main.bump(thing, push.limit_length(10.0), main.player if id == 1 else null)


# Pull a demon somewhere (vacuum, kick), drain Hatred, lock skills.
func affect_node(node: Node3D, target: Vector3, hatred_drain: float, lockout: float, label: String) -> void:
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
		main.online_affected(target, hatred_drain, lockout, label)
	else:
		s_affected.rpc_id(id, target, hatred_drain, lockout, label)


@rpc("authority", "call_remote", "reliable")
func s_affected(target: Vector3, hatred_drain: float, lockout: float, label: String) -> void:
	main.online_affected(target, hatred_drain, lockout, label.substr(0, 20))


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


func send_fx_team(team: String, kind: String, args: Array) -> void:
	for id in _client_ids():
		if peers[id]["in_round"] and peers[id]["role"] == team:
			s_fx.rpc_id(id, kind, args)


# Someone just switched sides: show them their new team's power-ups.
func _show_team_powerups(id: int) -> void:
	var team: String = peers[id]["role"]
	for it in main.powerups.lying_around(team):
		if id == 1:
			main.fx("powerup", it)
		else:
			s_fx.rpc_id(id, "powerup", it)


@rpc("authority", "call_remote", "reliable")
func s_fx(kind: String, args: Array) -> void:
	main.fx(kind, args)


# ---------------- ping and the Tab roster ----------------

# Round-trip time in milliseconds, as measured by the network library (or by
# relay_peer.gd, through the relay).
func ping_to(id: int) -> int:
	if multiplayer.multiplayer_peer is RelayPeer:
		return multiplayer.multiplayer_peer.ping_to(id)
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
	if looks.has(eid):
		r.outfit = looks[eid]
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


# ---------------- building together (Creative, online) ----------------
# The host picks "Build together" in the lobby and everyone goes into Creative on the same map.
# The host's editor holds the real map. Builders send small edits (editor.gd's _diff_ops); the
# host checks each one (a real piece, not someone else's selected piece, one shrine, not too many
# pieces, not too fast, and only from players allowed to build), applies it, and passes it on.
# Anything it refuses, it puts right on that builder's screen. The host can make anyone view-only.

const BUILD_MAX_OPS := 400          # edits in one message
const BUILD_MSGS_PER_SEC := 30      # messages a second, at most, from one builder
const BUILD_CAM_RATE := 10.0        # where-everyone-is updates a second

var build_can := {}                 # host: peer -> allowed to build
var build_claims := {}              # host: peer -> the piece id they have selected
var build_cams := {}                # host: peer -> [position, Vector2(pitch, yaw)]
var build_colors := {}              # host: peer -> colour number
var _build_window := {}             # host: peer -> [window start, messages in it]
var _build_cam_accum := 0.0
var build_refused := 0              # host: edits refused (for tests)


func is_building() -> bool:
	return phase == "building"


# Host: everyone into Creative, on the lobby's map.
func start_building() -> void:
	if not is_host or phase != "lobby":
		return
	phase = "building"
	build_claims.clear()
	build_cams.clear()
	for id in peers:
		if not build_can.has(id):
			build_can[id] = true
		_build_color(id)
	main.begin_building_host()
	for id in _client_ids():
		_send_build_start(id)
	_broadcast_lobby()
	print("[host] building together")


func _build_color(id: int) -> int:
	if not build_colors.has(id):
		build_colors[id] = build_colors.size()
	return build_colors[id]


func _send_build_start(id: int) -> void:
	s_build_start.rpc_id(id, MapData.to_text(main.editor.map), build_can.get(id, true))


@rpc("authority", "call_remote", "reliable")
func s_build_start(text: String, allowed: bool) -> void:
	var m := MapData.from_text(text)
	if m.is_empty():
		return
	main.online_build_start(m, allowed)


# Host: done building. The map goes back to the lobby, ready to play (or save).
func build_end() -> void:
	if not is_host or phase != "building":
		return
	phase = "lobby"
	build_claims.clear()
	main.end_building_host()
	for id in _client_ids():
		send_map(id)
		s_build_end.rpc_id(id)
	_broadcast_lobby()
	print("[host] done building")


@rpc("authority", "call_remote", "reliable")
func s_build_end() -> void:
	main.online_build_end()


# Host: try the map out: back to the lobby and straight into a round.
func build_test_play() -> void:
	if not is_host or phase != "building":
		return
	build_end()
	test_round = true
	start_round()


var test_round := false   # host: this round is a test from building together (short hiding; back to building after)
# Playing on your own (Ted, Nov 26): the host can start a round alone, on the team they pick. Someone joining
# mid-round restarts it with them, unless the host keeps their round going (then they join the other team).
var solo_role := "demon"
var solo_round := false
var _solo_waiting := []    # joined during a solo round, waiting on the host's choice
const SOLO_RESTART_IN := 6.0


# Host: stop the test round early (Esc, "Back to Creative") and everyone goes back to building.
func build_test_stop() -> void:
	if not is_host or not test_round:
		return
	if phase in ["hiding", "hunting", "ended"]:
		for owner in minions.keys():
			_minion_gone(owner, true)
		_back_to_lobby()
	test_round = false
	start_building()


# Ours: send our edits (the host applies its own directly).
func build_send_ops(ops: Array) -> void:
	if ops.is_empty():
		return
	if is_host:
		_build_broadcast(1, ops)
		return
	for i in range(0, ops.size(), BUILD_MAX_OPS):
		c_build_ops.rpc_id(1, JSON.stringify(ops.slice(i, i + BUILD_MAX_OPS)))


func _build_broadcast(author: int, ops: Array) -> void:
	var text := JSON.stringify(ops)
	for id in _client_ids():
		if id != author:
			s_build_ops.rpc_id(id, text)


@rpc("any_peer", "call_remote", "reliable")
func c_build_ops(text: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id) or phase != "building" or text.length() > 200000:
		return
	var t := now()
	var w: Array = _build_window.get(id, [t, 0])
	if t - w[0] > 1.0:
		w = [t, 0]
	w[1] += 1
	_build_window[id] = w
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		return
	if w[1] > BUILD_MSGS_PER_SEC or not build_can.get(id, true) or parsed.size() > BUILD_MAX_OPS:
		_build_refuse(id, parsed, "too fast" if w[1] > BUILD_MSGS_PER_SEC else ("view-only" if not build_can.get(id, true) else "too many edits at once"))
		return
	var ok := []
	var refused := []
	for op in parsed:
		var c := _build_check(id, op)
		if c.is_empty():
			refused.append(op)
		else:
			ok.append(c)
			main.editor.apply_remote([c])   # (one at a time, so the next check sees this one)
	if not ok.is_empty():
		_build_broadcast(id, ok)
	if not refused.is_empty():
		_build_refuse(id, refused, "")


# Host: is this edit fine? Returns it, cleaned, or {} if not.
func _build_check(id: int, op) -> Dictionary:
	if typeof(op) != TYPE_DICTIONARY:
		return {}
	var ed = main.editor
	match op.get("o"):
		"set":
			var v = MapData.clean_setting(op.get("k"), op.get("v"))
			if v == null:
				return {}
			return {"o": "set", "k": op["k"], "v": v}
		"put":
			var p := MapData.clean_piece(op.get("p"))
			var pid: String = p.get("id", "")
			if p.is_empty() or pid == "" or pid != str(op.get("id", "")) or _build_claimed_by_other(id, pid):
				return {}
			var i: int = ed.index_of(pid)
			if i < 0 and ed.map["pieces"].size() >= MapData.MAX_PIECES:
				return {}
			if p["type"] in ["shrine", "angel_spawn", "demon_spawn"]:
				for q in ed.map["pieces"]:
					if q["type"] == p["type"] and q.get("id", "") != pid:
						return {}   # one of each
			if i >= 0 and ed.map["pieces"][i]["type"] != p["type"] and ed.map["pieces"][i]["type"] in ["angel_spawn", "demon_spawn"]:
				return {}   # a start can't be turned into something else
			return {"o": "put", "id": pid, "p": p}
		"del":
			var pid := str(op.get("id", ""))
			var i: int = ed.index_of(pid)
			if i < 0:
				return {"o": "del", "id": pid}   # already gone: fine
			if _build_claimed_by_other(id, pid) or ed.map["pieces"][i]["type"] in ["angel_spawn", "demon_spawn"]:
				return {}
			return {"o": "del", "id": pid}
	return {}


func _build_claimed_by_other(id: int, pid: String) -> bool:
	for other in build_claims:
		if other != id and build_claims[other] == pid:
			return true
	return false


# Host: tell a builder how things really are, for the edits we didn't accept.
func _build_refuse(id: int, ops: Array, why: String) -> void:
	build_refused += ops.size()
	var ed = main.editor
	var fix := []
	var seen := {}
	for op in ops:
		if typeof(op) != TYPE_DICTIONARY:
			continue
		if op.get("o") == "set" and op.get("k") in MapData.SETTING_KEYS:
			fix.append({"o": "set", "k": op["k"], "v": ed.map[op["k"]]})
			continue
		var pid := str(op.get("id", ""))
		if pid == "" or seen.has(pid):
			continue
		seen[pid] = true
		var i: int = ed.index_of(pid)
		fix.append({"o": "put", "id": pid, "p": ed.map["pieces"][i]} if i >= 0 else {"o": "del", "id": pid})
	if not fix.is_empty():
		s_build_ops.rpc_id(id, JSON.stringify(fix))
	print("[host] refused %d of %s's edits%s" % [ops.size(), peers[id]["name"], (" (" + why + ")") if why != "" else ""])


@rpc("authority", "call_remote", "reliable")
func s_build_ops(text: String) -> void:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) == TYPE_ARRAY and main.editor != null:
		main.editor.apply_remote(parsed)


# Host: opened another map or started a new one: everyone gets it.
func build_reset() -> void:
	if not is_host or phase != "building":
		return
	build_claims.clear()
	var text := MapData.to_text(main.editor.map)
	for id in _client_ids():
		s_build_map.rpc_id(id, text)


@rpc("authority", "call_remote", "reliable")
func s_build_map(text: String) -> void:
	var m := MapData.from_text(text)
	if not m.is_empty() and main.editor != null:
		main.editor.load_shared(m)


# Selecting a piece claims it. The host says no if someone else has it.
func build_claim(pid: String) -> void:
	if is_host:
		_take_claim(1, pid)
	else:
		c_build_claim.rpc_id(1, pid)


@rpc("any_peer", "call_remote", "reliable")
func c_build_claim(pid: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if peers.has(id) and phase == "building" and pid.length() <= 24:
		_take_claim(id, pid)


func _take_claim(id: int, pid: String) -> void:
	if pid == "":
		build_claims.erase(id)
		return
	if _build_claimed_by_other(id, pid) or (id != 1 and not build_can.get(id, true)):
		build_claims.erase(id)
		if id == 1:
			main.editor.claim_denied(pid)
		else:
			s_build_denied.rpc_id(id, pid)
		return
	build_claims[id] = pid


@rpc("authority", "call_remote", "reliable")
func s_build_denied(pid: String) -> void:
	if main.editor != null:
		main.editor.claim_denied(pid)


# Host: let someone build, or make them view-only.
func build_set_can(id: int, allowed: bool) -> void:
	if not is_host or not peers.has(id) or id == 1:
		return
	build_can[id] = allowed
	if not allowed:
		build_claims.erase(id)
	s_build_can.rpc_id(id, allowed)
	print("[host] %s %s" % [peers[id]["name"], "can build" if allowed else "is view-only"])


@rpc("authority", "call_remote", "reliable")
func s_build_can(allowed: bool) -> void:
	if main.editor != null:
		main.editor.set_can_edit(allowed)


# Where we're looking from (so the others see our marker).
func build_send_cam(pos: Vector3, rot: Vector2) -> void:
	if is_host:
		build_cams[1] = [pos, rot]
	else:
		c_build_cam.rpc_id(1, pos, rot)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_build_cam(pos: Vector3, rot: Vector2) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id) or phase != "building" or not pos.is_finite() or not rot.is_finite():
		return
	build_cams[id] = [pos.clamp(Vector3.ONE * -1000.0, Vector3.ONE * 1000.0), rot]


func _build_tick(delta: float) -> void:
	_build_cam_accum += delta
	if _build_cam_accum < 1.0 / BUILD_CAM_RATE:
		return
	_build_cam_accum = 0.0
	var all := []
	for id in peers:
		var cam: Array = build_cams.get(id, [Vector3(0, 20, 30), Vector2.ZERO])
		all.append([id, peers[id]["name"], cam[0], cam[1], build_claims.get(id, ""), _build_color(id), build_can.get(id, true)])
	var others := func(viewer): return all.filter(func(e): return e[0] != viewer)
	if main.editor != null:
		main.editor.apply_builders(others.call(1))
	for id in _client_ids():
		s_builders.rpc_id(id, others.call(id))


@rpc("authority", "call_remote", "unreliable_ordered")
func s_builders(list: Array) -> void:
	if main.editor != null and main.editor.online:
		main.editor.apply_builders(list)
