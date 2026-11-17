# The row of little icons in the top-right corner: one for every effect you're
# under right now, good (green rim) or bad (red rim), each with a ring that drains
# as it runs out and its name and seconds underneath.
#   Bad:  Hellfire (burning), Fear, Vacuumed (skills locked)
#   Good: every timed power-up (Cherub Sense, Quick Blessings, Quick Skills,
#         Endless Sprint, Hatred Surge, Invisibility)
# main.gd calls show_effects() every frame with what's active. The icons are drawn
# here with simple shapes (no image files needed).
extends HBoxContainer

const SIZE := 46.0
const GOOD_RIM := Color(0.35, 0.9, 0.4)
const BAD_RIM := Color(0.95, 0.25, 0.2)

# id -> [name, colour, good?]
const INFO := {
	"burning": ["Hellfire", Color(1.0, 0.45, 0.05), false],
	"feared": ["Fear", Color(0.65, 0.2, 0.75), false],
	"skill_lock": ["Vacuumed", Color(0.6, 0.35, 1.0), false],
	"sense": ["Cherub Sense", Color(1.0, 0.88, 0.35), true],
	"quick_throw": ["Quick Blessings", Color(1.0, 0.9, 0.45), true],
	"quick_skills": ["Quick Skills", Color(0.5, 0.85, 1.0), true],
	"quick_run": ["Endless Sprint", Color(0.45, 0.95, 0.5), true],
	"fast_hatred": ["Hatred Surge", Color(0.95, 0.15, 0.12), true],
	"vanish": ["Invisibility", Color(0.6, 0.35, 0.95), true],
}

var _icons := {}   # id -> Icon


func _init() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# effects: id -> seconds left. Anything missing (or at 0) goes away.
func show_effects(effects: Dictionary) -> void:
	for id in _icons.keys():
		if effects.get(id, 0.0) <= 0.0:
			_icons[id].queue_free()
			_icons.erase(id)
	for id in effects:
		var left: float = effects[id]
		if left <= 0.0 or not INFO.has(id):
			continue
		if not _icons.has(id):
			var icon := Icon.new()
			icon.id = id
			add_child(icon)
			_icons[id] = icon
		_icons[id].set_left(left)


func shown() -> Array:
	return _icons.keys()


class Icon extends VBoxContainer:
	var id := ""
	var left := 0.0
	var total := 0.0       # the longest it's been (refreshing it refills the ring)
	var _face: Control
	var _label: Label

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("separation", 2)
		_face = Control.new()
		_face.custom_minimum_size = Vector2(SIZE, SIZE)
		_face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_face.draw.connect(_draw_face)
		add_child(_face)
		_label = Label.new()
		_label.add_theme_font_size_override("font_size", 12)
		_label.add_theme_constant_override("outline_size", 4)
		_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)

	func set_left(seconds: float) -> void:
		if seconds > left + 0.05:
			total = maxf(total, seconds)
		left = seconds
		total = maxf(total, left)
		if _label:
			_label.text = "%s %ds" % [INFO[id][0], int(ceil(left))]
			# Blink in the last two seconds, so you see it's about to end.
			modulate.a = 0.45 + 0.55 * absf(sin(left * 6.0)) if left < 2.0 else 1.0
		if _face:
			_face.queue_redraw()

	func _draw_face() -> void:
		var c: Color = INFO[id][1]
		var good: bool = INFO[id][2]
		var mid := Vector2(SIZE, SIZE) / 2.0
		_face.draw_circle(mid, SIZE * 0.5, Color(0.05, 0.04, 0.08, 0.75))
		# The ring drains as it runs out.
		var frac := clampf(left / maxf(total, 0.01), 0.0, 1.0)
		_face.draw_arc(mid, SIZE * 0.5 - 2.0, 0.0, TAU, 40, Color(0.25, 0.25, 0.25, 0.8), 3.0, true)
		_face.draw_arc(mid, SIZE * 0.5 - 2.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 40, GOOD_RIM if good else BAD_RIM, 3.0, true)
		_glyph(mid, c)

	# The picture in the middle.
	func _glyph(m: Vector2, c: Color) -> void:
		var f := _face
		match id:
			"burning":   # a flame
				f.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -15), m + Vector2(9, -1), m + Vector2(10, 7),
						m + Vector2(4, 13), m + Vector2(-5, 13), m + Vector2(-10, 6), m + Vector2(-8, -3), m + Vector2(-3, 2)]), c)
				f.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -3), m + Vector2(5, 6), m + Vector2(2, 12),
						m + Vector2(-3, 12), m + Vector2(-5, 7)]), Color(1.0, 0.9, 0.3))
			"feared":    # a panicked face: wide eyes, open mouth
				f.draw_circle(m + Vector2(-6, -4), 4.5, Color.WHITE)
				f.draw_circle(m + Vector2(6, -4), 4.5, Color.WHITE)
				f.draw_circle(m + Vector2(-6, -3), 1.8, Color.BLACK)
				f.draw_circle(m + Vector2(6, -3), 1.8, Color.BLACK)
				f.draw_circle(m + Vector2(0, 9), 4.5, c)
				f.draw_line(m + Vector2(-13, -13), m + Vector2(-9, -10), c, 2.0)
				f.draw_line(m + Vector2(13, -13), m + Vector2(9, -10), c, 2.0)
			"skill_lock":   # a swirl
				for i in 3:
					f.draw_arc(m, 4.0 + i * 4.0, i * 1.3, i * 1.3 + PI * 1.4, 16, c, 2.5, true)
			"sense":     # a little halo with wings
				f.draw_arc(m + Vector2(0, -5), 7.0, 0.0, TAU, 20, c, 3.0, true)
				f.draw_colored_polygon(PackedVector2Array([m + Vector2(-3, 4), m + Vector2(-15, 0), m + Vector2(-12, 8)]), Color.WHITE)
				f.draw_colored_polygon(PackedVector2Array([m + Vector2(3, 4), m + Vector2(15, 0), m + Vector2(12, 8)]), Color.WHITE)
			"quick_throw":   # a glowing orb with speed lines
				f.draw_circle(m + Vector2(5, 0), 7.0, c)
				for y in [-5, 0, 5]:
					f.draw_line(m + Vector2(-14, y), m + Vector2(-5, y), c, 2.0)
			"quick_skills":  # a lightning bolt
				f.draw_colored_polygon(PackedVector2Array([m + Vector2(3, -15), m + Vector2(-8, 2), m + Vector2(-1, 2),
						m + Vector2(-4, 15), m + Vector2(8, -3), m + Vector2(1, -3)]), c)
			"quick_run":     # double chevrons
				for x in [-6, 4]:
					f.draw_polyline(PackedVector2Array([m + Vector2(x - 4, -9), m + Vector2(x + 5, 0), m + Vector2(x - 4, 9)]), c, 3.5, true)
			"fast_hatred":   # horns
				f.draw_colored_polygon(PackedVector2Array([m + Vector2(-10, 10), m + Vector2(-13, -12), m + Vector2(-3, 6)]), c)
				f.draw_colored_polygon(PackedVector2Array([m + Vector2(10, 10), m + Vector2(13, -12), m + Vector2(3, 6)]), c)
				f.draw_circle(m + Vector2(0, 8), 4.0, c)
			"vanish":        # a dotted ghost outline
				for i in 12:
					var a := TAU * i / 12.0
					f.draw_circle(m + Vector2(cos(a) * 11.0, sin(a) * 13.0), 1.6, c)
				f.draw_circle(m + Vector2(-4, -3), 2.0, c)
				f.draw_circle(m + Vector2(4, -3), 2.0, c)
