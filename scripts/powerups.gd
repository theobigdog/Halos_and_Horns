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
const GameRules = preload("res://scripts/game_rules.gd")   # (each power-up can be switched off: Ted, Nov 26)

const ANGEL_KINDS := ["sense", "quick_throw", "quick_skills", "quick_run"]
const DEMON_KINDS := ["fast_hatred", "fire_burst", "heal", "heal", "vanish"]   # (healing turns up twice as often)
const LABELS := {
	"sense": "Cherub Sense", "quick_throw": "Quick Blessings", "quick_skills": "Quick Skills",
	"quick_run": "Endless Sprint", "fast_hatred": "Hatred Surge", "fire_burst": "Fire Burst",
	"heal": "Unholy Mending", "vanish": "Invisibility",
}
# What the Custom rules change (standard: the constants here).
static func surge_mult() -> float:
	return FAST_HATRED_MULT * GameRules.f("surge_strength")


static func burst_radius() -> float:
	return FIRE_BURST_RADIUS * GameRules.f("burst_radius") * GameRules.f("blast")


static func duration(kind: String) -> float:
	return DURATION.get(kind, 0.0) * GameRules.f("pu_time")


const DURATION := {"sense": 15.0, "quick_throw": 12.0, "quick_skills": 15.0, "quick_run": 15.0, "fast_hatred": 15.0}

const FAST_HATRED_MULT := 8.0     # Hatred Surge: Hatred refills 8x as fast, 32/s, beating flying's 22/s drain (Ted, Nov 18)
const HEAL_AMOUNT := 0.5          # Unholy Mending: +50% of starting health...
const MAX_HEALTH := 1.5           # ...up to 150% of it
const LIFETIME := 40.0            # a pickup nobody takes disappears after this
const MAX_EACH_TEAM := 2          # at most this many lying around per team (was 3; Ted, Nov 18: too many)
const PICKUP_RANGE := 1.4
const DEMON_DROP_BASE := 50.0     # seconds between demon drops (2 players, demons standing still; was 35)
const DEMON_DROP_MIN := 20.0      # (was 12)
const FIRST_DEMON_DROP := 35.0    # the first one of a round (was 20)
const COUNTDOWN_FROM := 8.0       # a pickup about to disappear counts down its last seconds
const ANGEL_HELP_AFTER := 55.0    # no catch, hit or angel power-up for this long: help the angels (was 30)
const ANGEL_CATCH_DROP := 0.5     # a caught demon drops an angel power-up this often (was every time; Ted, Nov 18)
const MAX_ANGEL_PICKUPS := 2      # and at most this many angel ones lying around
const FIRE_BURST_RADIUS := 7.0
const REST_HEIGHT := 0.45         # a dropped pickup comes to rest (bobbing) this high off the ground
const FALL_GRAVITY := 18.0

var main                          # the game (decider helpers, effects)
var items := {}                   # everyone: id -> pickup node
var _auth := {}                   # decider: id -> {kind, team, pos, until}
var _counter := 0
var _demon_timer := FIRST_DEMON_DROP
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
	_demon_timer = FIRST_DEMON_DROP
	_last_angel_help = _now()
	_movement = 0.0
	_last_demon_pos.clear()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ---------------- decider ----------------

# A demon was hit or caught: the angels are doing fine for now.
func angels_made_progress() -> void:
	_last_angel_help = _now()


var catch_drop := ANGEL_CATCH_DROP   # (tests set it to 1 with --sure-drops, so the drop check isn't luck)


func demon_caught(where: Vector3) -> void:
	var kinds := GameRules.allowed(ANGEL_KINDS)
	if randf() < catch_drop and _count("angel") < MAX_ANGEL_PICKUPS and not kinds.is_empty():
		_drop("angel", kinds.pick_random(), where)
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
		_demon_timer -= 0.2 * GameRules.f("pu_rate")
		var demon_kinds := GameRules.allowed(DEMON_KINDS)
		if _demon_timer <= 0.0 and _count("demon") < MAX_EACH_TEAM and not demon_kinds.is_empty():
			var a = angels.pick_random()[1]
			_drop("demon", demon_kinds.pick_random(), a.global_position)
			var busy := clampf(_movement / 2.5, 0.0, 1.0)
			var interval := DEMON_DROP_BASE / (1.0 + 0.15 * maxf(people.size() - 2, 0)) * (1.0 - 0.4 * busy)
			_demon_timer = maxf(interval, DEMON_DROP_MIN)

	# Struggling angels get a hand.
	var angel_kinds := GameRules.allowed(ANGEL_KINDS)
	if not angels.is_empty() and t - _last_angel_help > ANGEL_HELP_AFTER / GameRules.f("pu_rate") and _count("angel") < MAX_ANGEL_PICKUPS \
			and not angel_kinds.is_empty():
		var a = angels.pick_random()[1]
		var ang := randf() * TAU
		_drop("angel", angel_kinds.pick_random(), a.global_position + Vector3(cos(ang), 0, sin(ang)) * randf_range(3.0, 5.0))
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
			var p: Vector3 = _auth[id]["pos"]
			out.append([id, _auth[id]["kind"], p, p, _auth[id]["until"] - _now()])
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
	var life := LIFETIME * GameRules.f("pu_life")
	_auth[_counter] = {"kind": kind, "team": team, "pos": pos, "until": _now() + life}
	main.team_fx(team, "powerup", [_counter, kind, pos, from, life])
	print("[decider] %s power-up dropped: %s" % [team, kind])


func _remove(id: int, taken: bool) -> void:
	_auth.erase(id)
	main.broadcast_fx("powerup_gone", [id, taken])


# ---------------- everyone: what the pickups look like ----------------

# `pos` is where it comes to rest; `from` is where it starts falling from.
func show_item(id: int, kind: String, pos: Vector3, from: Vector3 = pos, left := LIFETIME) -> void:
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
	n.set_meta("expires", _now() + clampf(left, 0.0, LIFETIME * 3.0))
	n.set_meta("tag", tag)
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
		# About to disappear: count down the last seconds, and blink for the last three.
		var left: float = n.get_meta("expires") - _now()
		if left <= COUNTDOWN_FROM:
			var tag: Label3D = n.get_meta("tag")
			tag.text = "%s  %d" % [LABELS.get(n.get_meta("kind"), ""), ceili(maxf(left, 0.0))]
			tag.modulate = Color(1.0, 0.45, 0.35) if left <= 3.0 else Color(1.0, 0.85, 0.5)
			n.get_child(0).visible = left > 3.0 or fmod(left, 0.4) > 0.15
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
