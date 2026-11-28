# A traffic light that works (Ted, Nov 20): glowing lamps laid over the model's painted red, yellow
# and green lamps (found by models.gd's lamp_spots), cycling green -> yellow -> red. Timed off the
# computer's clock, so every light on every screen changes together.
extends Node3D

const GREEN_TIME := 7.0
const YELLOW_TIME := 2.0
const RED_TIME := 9.0
const COLORS := {"red": Color(1.0, 0.12, 0.08), "yellow": Color(1.0, 0.7, 0.1), "green": Color(0.15, 1.0, 0.35)}

var heads := []          # [red spot, green spot, which way the lamp faces] in our own space
var lamp_radius := 0.09
var _lamps := {}         # "red"/"yellow"/"green" -> materials to light up
var _lights := []        # a small light per head, coloured like the lit lamp
var _shown := ""


func _ready() -> void:
	for c in COLORS:
		_lamps[c] = []
	for h in heads:
		var red: Vector3 = h[0]
		var green: Vector3 = h[1]
		var out: Vector3 = h[2]
		for c in ["red", "yellow", "green"]:
			var at: Vector3 = red if c == "red" else (green if c == "green" else (red + green) * 0.5)
			var mi := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = lamp_radius
			cyl.bottom_radius = lamp_radius
			cyl.height = 0.02
			cyl.radial_segments = 16   # (Godot's default is 64 x 4: 768 triangles for a lamp the size of a saucer;
			cyl.rings = 1              # they were 85% of a traffic light's 5,400 triangles: Nov 27 audit)
			mi.mesh = cyl
			var m := StandardMaterial3D.new()
			m.albedo_color = COLORS[c].darkened(0.7)
			m.emission_enabled = true
			m.emission = COLORS[c]
			m.emission_energy_multiplier = 0.0
			mi.material_override = m
			mi.position = at + out * 0.035
			if out.length() > 0.1:
				mi.look_at_from_position(mi.position, mi.position + out, Vector3.UP if absf(out.y) < 0.9 else Vector3.FORWARD)
				mi.rotate_object_local(Vector3.RIGHT, PI / 2)   # (a cylinder's flat face points along its y)
			add_child(mi)
			_lamps[c].append(m)
		var l := OmniLight3D.new()
		l.omni_range = 3.0
		l.light_energy = 0.8
		l.position = (red + green) * 0.5 + out * 0.4
		add_child(l)
		_lights.append(l)


func _process(_delta: float) -> void:
	var cycle := GREEN_TIME + YELLOW_TIME + RED_TIME
	var t := fposmod(Time.get_unix_time_from_system(), cycle)
	var now := "green" if t < GREEN_TIME else ("yellow" if t < GREEN_TIME + YELLOW_TIME else "red")
	if now == _shown:
		return
	_shown = now
	for c in _lamps:
		for m in _lamps[c]:
			m.emission_energy_multiplier = 4.0 if c == now else 0.0
			m.albedo_color = COLORS[c] if c == now else COLORS[c].darkened(0.7)
	for l in _lights:
		l.light_color = COLORS[now]
