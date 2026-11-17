# Power-ups: glowing pickups that appear around the map during the hunt.
#
# Demon power-ups are dropped by the ANGELS (where an angel is standing), every
# so often: more often with more players, and more often the more the demons are
# moving about. Demons have to sneak up close to grab them.
#
# Demon power-ups: Hatred Surge, Fire Burst, Unholy Mending (healing) and
# Invisibility (6.5 s where the angels get no trace of you at all).
#
# Angel power-ups: every redeemed demon drops one where it was caught. And so a
# new or struggling angel isn't left with nothing, if nobody has found or hit a
# demon for a while, one turns up near an angel.
#
# Only the decider (host / practice game) creates them and decides who picked one
# up. Each team only ever SEES its own team's power-ups (the other team's game
# isn't even told where they are), so nobody can camp the other side's drops.
extends Node

const Skills = preload("res://scripts/skills.gd")
const Sfx = preload("res://scripts/sfx.gd")

const ANGEL_KINDS := ["sense", "quick_throw", "quick_skills", "quick_run"]
const DEMON_KINDS := ["fast_hatred", "fire_burst", "heal", "heal", "vanish"]   # (healing turns up twice as often)
const LABELS := {
	"sense": "Cherub Sense", "quick_throw": "Quick Blessings", "quick_skills": "Quick Skills",
	"quick_run": "Endless Sprint", "fast_hatred": "Hatred Surge", "fire_burst": "Fire Burst",
	"heal": "Unholy Mending", "vanish": "Invisibility",
}
const DURATION := {"sense": 15.0, "quick_throw": 12.0, "quick_skills": 15.0, "quick_run": 15.0, "fast_hatred": 15.0}

const HEAL_AMOUNT := 0.5          # Unholy Mending: +50% of starting health...
const MAX_HEALTH := 1.5           # ...up to 150% of it
const LIFETIME := 40.0            # a pickup nobody takes disappears after this
const MAX_EACH_TEAM := 3          # at most this many lying around per team
const PICKUP_RANGE := 1.4
const DEMON_DROP_BASE := 35.0     # seconds between demon drops (2 players, demons standing still)
const DEMON_DROP_MIN := 12.0
const ANGEL_HELP_AFTER := 30.0    # no catch, hit or angel power-up for this long: help the angels
const FIRE_BURST_RADIUS := 7.0
const REST_HEIGHT := 0.45         # a dropped pickup comes to rest (bobbing) this high off the ground
const FALL_GRAVITY := 18.0

var main                          # the game (decider helpers, effects)
var items := {}                   # everyone: id -> pickup node
var _auth := {}                   # decider: id -> {kind, team, pos, until}
var _counter := 0
var _demon_timer := 20.0
var _last_angel_help := 0.0       # when an angel power-up last appeared (or a demon was hit/caught)
var _movement := 0.0              # how much the demons have been moving lately (m/s, smoothed)
var _last_demon_pos := {}
var _tick := 0.0


func reset() -> void:
	for n in items.values():
		if is_instance_valid(n):
			n.queue_free()
	items.clear()
	_auth.clear()
	_demon_timer = 20.0
	_last_angel_help = _now()
	_movement = 0.0
	_last_demon_pos.clear()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ---------------- decider ----------------

# A demon was hit or caught: the angels are doing fine for now.
func angels_made_progress() -> void:
	_last_angel_help = _now()


func demon_caught(where: Vector3) -> void:
	_drop("angel", ANGEL_KINDS.pick_random(), where)
	_last_angel_help = _now()


func decider_tick(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.2
	var t := _now()
	var people: Array = main.team_entries()   # [key, node, team]
	var angels := people.filter(func(e): return e[2] == "angel")
	var demons := people.filter(func(e): return e[2] == "demon")

	# How much are the demons moving about?
	var moved := 0.0
	for e in demons:
		var p: Vector3 = e[1].global_position
		if _last_demon_pos.has(e[0]):
			moved += Vector2(p.x - _last_demon_pos[e[0]].x, p.z - _last_demon_pos[e[0]].z).length()
		_last_demon_pos[e[0]] = p
	var speed_now := moved / 0.2 / maxf(demons.size(), 1)
	_movement = lerpf(_movement, speed_now, 0.05)

	# Demon power-ups, dropped by the angels.
	if not angels.is_empty() and not demons.is_empty():
		_demon_timer -= 0.2
		if _demon_timer <= 0.0 and _count("demon") < MAX_EACH_TEAM:
			var a = angels.pick_random()[1]
			_drop("demon", DEMON_KINDS.pick_random(), a.global_position)
			var busy := clampf(_movement / 2.5, 0.0, 1.0)
			var interval := DEMON_DROP_BASE / (1.0 + 0.15 * maxf(people.size() - 2, 0)) * (1.0 - 0.4 * busy)
			_demon_timer = maxf(interval, DEMON_DROP_MIN)

	# Struggling angels get a hand.
	if not angels.is_empty() and t - _last_angel_help > ANGEL_HELP_AFTER and _count("angel") < MAX_EACH_TEAM:
		var a = angels.pick_random()[1]
		var ang := randf() * TAU
		_drop("angel", ANGEL_KINDS.pick_random(), a.global_position + Vector3(cos(ang), 0, sin(ang)) * randf_range(3.0, 5.0))
		_last_angel_help = t

	# Expired, or picked up?
	for id in _auth.keys():
		var it: Dictionary = _auth[id]
		if t > it["until"]:
			_remove(id, false)
			continue
		for e in people:
			if e[2] != it["team"]:
				continue
			var off: Vector3 = e[1].global_position - it["pos"]
			if Vector2(off.x, off.z).length() <= PICKUP_RANGE and absf(off.y) < 2.2:
				_remove(id, true)
				main.give_powerup(e[0], it["kind"], it["pos"])
				break


# Decider: the power-ups lying around for one team (to show someone who just joined it).
func lying_around(team: String) -> Array:
	var out := []
	for id in _auth:
		if _auth[id]["team"] == team:
			out.append([id, _auth[id]["kind"], _auth[id]["pos"]])
	return out


static func team_of(kind: String) -> String:
	return "angel" if kind in ANGEL_KINDS else "demon"


# Everyone: we switched sides, so stop showing the other side's power-ups.
func forget_other_team(my_team: String) -> void:
	for id in items.keys():
		var n = items[id]
		if is_instance_valid(n) and team_of(n.get_meta("kind")) != my_team:
			n.queue_free()
			items.erase(id)


func _count(team: String) -> int:
	return _auth.values().filter(func(it): return it["team"] == team).size()


# It falls from about hand height where it was dropped, down to the ground (the
# ray skips players, or it would land on the dropping angel's head and float there).
func _drop(team: String, kind: String, near: Vector3) -> void:
	_counter += 1
	var people: Array = main.team_entries().map(func(e): return e[1])
	var pos: Vector3 = main.ground_below(near + Vector3.UP * 1.5, people) + Vector3.UP * REST_HEIGHT
	var from := near + Vector3.UP * 1.0
	if from.y < pos.y:
		from = pos
	_auth[_counter] = {"kind": kind, "team": team, "pos": pos, "until": _now() + LIFETIME}
	main.team_fx(team, "powerup", [_counter, kind, pos, from])
	print("[decider] %s power-up dropped: %s" % [team, kind])


func _remove(id: int, taken: bool) -> void:
	_auth.erase(id)
	main.broadcast_fx("powerup_gone", [id, taken])


# ---------------- everyone: what the pickups look like ----------------

# `pos` is where it comes to rest; `from` is where it starts falling from.
func show_item(id: int, kind: String, pos: Vector3, from: Vector3 = pos) -> void:
	var n := Node3D.new()
	var angel := kind in ANGEL_KINDS
	var color: Color = Color(1.0, 0.88, 0.35) if angel else {"heal": Color(0.3, 0.9, 0.35), "vanish": Color(0.6, 0.35, 0.95)}.get(kind, Color(0.9, 0.15, 0.1))
	var gem := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.28
	s.height = 0.56
	s.radial_segments = 6       # chunky and gem-like
	s.rings = 3
	gem.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.0
	gem.material_override = m
	n.add_child(gem)
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 3.0
	light.light_energy = 1.2
	n.add_child(light)
	var tag := Label3D.new()
	tag.text = LABELS.get(kind, kind)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 32
	tag.outline_size = 8
	tag.pixel_size = 0.008
	tag.modulate = color.lightened(0.3)
	tag.position.y = 0.6
	n.add_child(tag)
	n.set_meta("t", randf() * 10.0)
	n.set_meta("kind", kind)
	main.fx_parent().add_child(n)
	n.global_position = Vector3(pos.x, maxf(from.y, pos.y), pos.z)
	n.set_meta("base_y", pos.y)
	n.set_meta("falling", from.y > pos.y + 0.05)
	n.set_meta("vy", 0.0)   # upward speed while falling
	items[id] = n


func hide_item(id: int, taken: bool) -> void:
	var n = items.get(id)
	items.erase(id)
	if n == null or not is_instance_valid(n):
		return
	if taken:
		main.puff_at(n.global_position, Color(1, 1, 1, 0.7), 1.0)
	n.queue_free()


func _process(delta: float) -> void:
	for n in items.values():
		if not is_instance_valid(n):
			continue
		var t: float = n.get_meta("t") + delta
		n.set_meta("t", t)
		n.rotation.y += delta * 1.6
		var base: float = n.get_meta("base_y")
		if n.get_meta("falling"):
			# Falling to the ground, with a little bounce or two, then it settles and bobs.
			var vy: float = n.get_meta("vy") - FALL_GRAVITY * delta
			n.global_position.y += vy * delta
			if n.global_position.y <= base:
				n.global_position.y = base
				vy = -vy * 0.35
				if vy < 1.0:
					n.set_meta("falling", false)
					n.set_meta("t", 0.0)
			n.set_meta("vy", vy)
			continue
		n.global_position.y = base + sin(t * 2.2) * 0.12
