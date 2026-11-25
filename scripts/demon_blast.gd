# A redeemed demon goes out with a bang (Ted's friend, Nov 20: "more explosive"; reworked Nov 24 to
# match the Hellfire look): a white-hot flash and a light that lights up the area, a hellfire fireball
# with a blazing core swelling up and rolling into black smoke, a shockwave ring racing across the
# ground, glowing chunks tumbling and bouncing, golden sparks (the demon, redeemed), a ring of dust and
# a scorch mark left behind. With `small` it's a hit on a demon instead: a hot flash, a shockwave ring,
# a spray of sparks and a lick of fire.
# All pieces are Effects (shader-animated shared meshes, no particles, no shared random numbers); this
# node starts them on its first frame (once it has been placed), runs the light and frees itself.
extends Node3D

const Effects = preload("res://scripts/effects.gd")

const LIFE := 2.6
const HIT_LIFE := 0.6

var small := false               # a hit, not a death: a quick burst of sparks and fire
var _t := 0.0
var _started := false
var _light: OmniLight3D
var _energy := 0.0


func _start() -> void:
	_started = true
	var pos := global_position
	var q := Effects.quality
	if small:
		var at := pos + Vector3.UP * 0.35
		Effects.flash(self, at, Color(1.0, 0.75, 0.4), 1.7, 0.16, 2.2)
		Effects.shockwave(self, at, Color(1.0, 0.5, 0.15), 0.9, 0.28, true, 1.6)
		Effects.burst(self, at, Color(1.0, 0.55, 0.12), 14, 8.0, 0.45, 9.0, 0.045)
		Effects.fireball(self, at, 0.38, 0.45, 0.55)
		if q >= 2:
			Effects.debris(self, at, Vector3.UP, Color(0.12, 0.05, 0.04), 4, 100.0, 1.0, 4.0, 0.06, 0.5)
		if q >= 1:
			_light_up(Color(1.0, 0.55, 0.25), 2.5, 3.0)
		return
	var c := pos + Vector3.UP * 0.9
	Effects.flash(self, c, Color(1.0, 0.8, 0.5), 4.2, 0.26, 2.4)
	Effects.fireball(self, c, 1.25, 1.1, 0.6)
	Effects.fireball(self, c + Vector3.UP * 0.4, 0.8, 0.8, 0.8, false, 0.06)
	Effects.smoke(self, pos + Vector3.UP * 1.0, Color(0.1, 0.06, 0.06), 2.6, 2.0, 0.35)
	Effects.shockwave(self, pos + Vector3.UP * 0.08, Color(1.0, 0.6, 0.25), 7.0, 0.6, false, 1.8)
	Effects.shockwave(self, c, Color(1.0, 0.7, 0.4), 2.2, 0.3, true, 0.8)
	Effects.burst(self, c, Color(1.0, 0.8, 0.3), 26, 14.0, 1.0, 9.0, 0.06)
	Effects.debris(self, c, Vector3.UP, Color(0.12, 0.05, 0.04), 22, 0.85, 1.0, 9.0, 0.15, 1.6)
	Effects.dust(self, pos, 1.6, 22)
	Effects.scorch(self, pos, 2.4, LIFE)
	_light_up(Color(1.0, 0.6, 0.3), 9.0, 12.0)


func _light_up(color: Color, energy: float, reach: float) -> void:
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = reach
	_light.shadow_enabled = false
	_light.position.y = 1.0
	_energy = energy
	_light.light_energy = energy
	add_child(_light)


func _process(delta: float) -> void:
	if not _started:
		_start()
		return
	_t += delta
	if _t >= (HIT_LIFE if small else LIFE):
		queue_free()
		return
	if _light:
		# Flash bright, then flicker down like a dying fire.
		var span := 0.2 if small else 0.7
		var k := maxf(0.0, 1.0 - _t / span)
		var flicker := 1.0 + 0.15 * sin(_t * 47.0) + 0.1 * sin(_t * 23.0 + 1.3)
		_light.light_energy = _energy * k * k * flicker
		_light.visible = k > 0.0
