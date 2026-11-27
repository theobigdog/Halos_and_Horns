# A light that follows the daylight (on at dusk, off at dawn, sputtering as it comes on) and/or flickers
# all the time at a set rate. (Ted's wife's Creative notes, Nov 21.) No randomness: the sputter and the
# flicker are hashes of the time, so every screen agrees and seeded tests aren't disturbed.
extends Node3D

static var darkness := 0.0      # graphics.gd: 0 in daylight, about 0.25 at dusk, 1 at night
const DUSK := 0.2               # lights with a sensor come on from about dusk

var light: Light3D
var base := 1.0                 # its energy when on
var sensor := true              # follows the daylight (false: always on)
var flicker := 0.0              # flickers this many times a second (0: steady)
var _on := -1.0
var _since_on := 99.0
var _seed := 0.0


func setup(l: Light3D, follow_daylight: bool, flicker_hz: float) -> void:
	light = l
	base = l.light_energy
	sensor = follow_daylight
	flicker = flicker_hz
	add_child(l)


func _ready() -> void:
	_seed = fposmod(global_position.x * 12.9898 + global_position.z * 78.233 + global_position.y * 3.7, 97.0)


static func _hash(x: float) -> float:
	return fposmod(sin(x * 127.1 + 311.7) * 43758.5453, 1.0)


func _process(delta: float) -> void:
	if light == null:
		return
	var want := 1.0 if not sensor or darkness >= DUSK else 0.0
	if _on < 0.0:
		_on = want   # (already on when the map loads at night: no sputter)
	elif want > 0.5 and _on < 0.5:
		_since_on = 0.0   # just came on: sputter for a moment
	_on = want
	_since_on += delta
	var e := base * _on
	if _on > 0.5 and _since_on < 1.4:
		var t := floorf(_since_on * 10.0)
		e *= 1.0 if _hash(t + _seed) < 0.3 + _since_on * 0.5 else 0.08
	if flicker > 0.0 and _on > 0.5:
		var ft := Time.get_ticks_msec() / 1000.0 * flicker + _seed
		var a := _hash(floorf(ft))
		var b := _hash(floorf(ft) + 1.0)
		e *= 0.35 + 0.65 * lerpf(a, b, smoothstep(0.0, 1.0, ft - floorf(ft)))
		if flicker >= 2.0 and _hash(floorf(ft * 1.7) + 3.0) < 0.22:
			e *= 0.04   # a bad bulb: it cuts out now and then
	light.light_energy = e
	light.visible = e > 0.01
