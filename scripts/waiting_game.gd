# "Whack-an-Imp": a silly mouse mini-game for angels stuck behind the blindfold during the
# hiding phase (Ted, Nov 25: "can we give them something fun or silly to do while they wait?").
# Imps pop out of fluffy clouds in Heaven's waiting room; bonk them with your halo (+1), golden
# imps are worth +5, and the poor cherubs must be spared (-2). It speeds up as the hunt nears.
#
# Purely local UI: its own RandomNumberGenerator (never the global one), procedural drawing
# (no image files) and its own little synthesized sounds. Nothing here touches game state.
#
# API:  start(seconds_left)  show + reset          stop()  hide, silence, emit finished_score
#       set_seconds_left(s)  optional: re-sync the countdown (e.g. the wait was skipped)
#       best                 best score this session
extends Control

signal finished_score(score: int)

var best := 0
var record := 0                   # the best going into this game: what you're trying to beat
const VOLUME_DB := -9.0           # (Ted, Nov 26: "turn down the volume a little")
var score := 0
var combo := 0

const NONE := 0
const IMP := 1
const GOLD := 2
const CHERUB := 3

const HIDDEN := 0
const RISING := 1
const UP := 2
const FALLING := 3
const BONKED := 4

const RISE_TIME := 0.16
const FALL_TIME := 0.2
const BONK_TIME := 0.6

# Holes: rows of 3, 4, 3 (staggered like a honeycomb), in 1280x720 design units around the centre.
const HOLES := [
	Vector2(-230, 0), Vector2(0, 0), Vector2(230, 0),
	Vector2(-345, 138), Vector2(-115, 138), Vector2(115, 138), Vector2(345, 138),
	Vector2(-230, 276), Vector2(0, 276), Vector2(230, 276),
]
# Puffs of one cloud (x, y, radius), for a cloud 200 units wide centred on (0, 0).
const PUFFS := [
	Vector3(-72, 10, 28), Vector3(-40, -6, 36), Vector3(2, -14, 42), Vector3(44, -6, 36),
	Vector3(78, 10, 26), Vector3(-30, 16, 34), Vector3(26, 16, 36),
]

const POP_WORDS := ["BONK!", "BOINK!", "WHAM!", "BONK!", "THWACK!", "BOP!", "DONK!"]
const CHERUB_WORDS := ["OUCH! -2", "WAAAH! -2", "NOT ME! -2", "RUDE! -2"]
const TAUNTS := ["nyah~", "too slow!", "hehehe", "missed me!", "pfffbt"]
const WHIFFS := ["whiff", "swish", "nope"]

const C_INK := Color(0.23, 0.12, 0.25)
const C_GOLD := Color(1.0, 0.8, 0.25)
const C_GOLD_DARK := Color(0.78, 0.5, 0.08)
const C_CLOUD := Color(1.0, 0.99, 1.0)
const C_CLOUD_SHADE := Color(0.8, 0.79, 0.95)
const C_CLOUD_BACK := Color(0.86, 0.85, 0.98)

var _rng := RandomNumberGenerator.new()
var _running := false
var _seconds_left := 30.0
var _total := 30.0
var _elapsed := 0.0
var _spawn_timer := 0.6
var _time := 0.0
var _last_tick := -1
var _hammer_t := 1.0    # time since the last click (halo swing animation)

var _s := 1.0           # scale: design units -> pixels
var _centre := Vector2.ZERO
var _holes: Array[Dictionary] = []
var _slot_ctrls: Array[Control] = []
var _front_ctrls: Array[Control] = []
var _overlay: Control
var _fx: Array[Dictionary] = []      # sparkles, stars, rings
var _pops: Array[Dictionary] = []    # text pop-ups
var _bg_clouds: Array[Vector4] = []  # x frac, y frac, scale, layer
var _score_bump := 0.0
var _combo_bump := 0.0
var _font: Font
var _box: StyleBoxFlat
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
static var _sounds := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_rng.seed = Time.get_ticks_usec()
	_font = ThemeDB.fallback_font
	_box = StyleBoxFlat.new()
	_box.set_corner_radius_all(14)
	_box.anti_aliasing = true
	for i in HOLES.size():
		_holes.append({"kind": NONE, "state": HIDDEN, "t": 0.0, "dur": 1.0, "variant": 0, "hit": false})
		var slot := Control.new()
		slot.clip_contents = true
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot)
		slot.draw.connect(_draw_slot.bind(i))
		_slot_ctrls.append(slot)
		var front := Control.new()
		front.set_anchors_preset(Control.PRESET_FULL_RECT)
		front.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(front)
		front.draw.connect(_draw_front.bind(i))
		_front_ctrls.append(front)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	for i in 16:
		_bg_clouds.append(Vector4(_rng.randf(), _rng.randf_range(0.12, 0.95), _rng.randf_range(0.6, 1.4), float(i % 3)))
	_make_sounds()
	var bus := "SFX" if AudioServer.get_bus_index("SFX") != -1 else "Master"
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		p.volume_db = VOLUME_DB
		add_child(p)
		_players.append(p)
	resized.connect(_layout)
	_layout()
	if not _running:
		visible = false
		set_process(false)


func start(seconds_left: float) -> void:
	_seconds_left = maxf(seconds_left, 0.0)
	_total = maxf(seconds_left, 1.0)
	_elapsed = 0.0
	_spawn_timer = 0.7
	record = best
	score = 0
	combo = 0
	_last_tick = -1
	_hammer_t = 1.0
	_fx.clear()
	_pops.clear()
	for h in _holes:
		h.kind = NONE
		h.state = HIDDEN
	_running = true
	visible = true
	set_process(true)
	_layout()


func set_seconds_left(seconds_left: float) -> void:
	_seconds_left = maxf(seconds_left, 0.0)


func stop() -> void:
	if not _running:
		return
	_running = false
	visible = false
	set_process(false)
	for p in _players:
		p.stop()
	best = maxi(best, score)
	finished_score.emit(score)


func _layout() -> void:
	_s = minf(size.x / 1280.0, size.y / 720.0)
	if _s <= 0.0:
		_s = 1.0
	_centre = Vector2(size.x * 0.5, (size.y + 30.0 * _s) * 0.5 - 105.0 * _s)   # field centred between title and bar
	for i in _slot_ctrls.size():
		var c := _hole_pos(i)
		var slot := _slot_ctrls[i]
		slot.position = c + Vector2(-110, -175) * _s
		slot.size = Vector2(220, 175) * _s


func _hole_pos(i: int) -> Vector2:
	return _centre + HOLES[i] * _s


# ---------------------------------------------------------------- game logic

func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_time += delta
	_hammer_t += delta
	_score_bump = maxf(_score_bump - delta * 4.0, 0.0)
	_combo_bump = maxf(_combo_bump - delta * 4.0, 0.0)
	if _running:
		_seconds_left = maxf(_seconds_left - delta, 0.0)
		_elapsed += delta
		var secs := int(ceil(_seconds_left))
		if secs != _last_tick and secs <= 3 and secs > 0:
			_play("tick", 1.0 + (3 - secs) * 0.12)
		_last_tick = secs
		if _seconds_left > 0.4:
			_spawn_timer -= delta
			if _spawn_timer <= 0.0:
				_spawn()
				var speed := clampf(_elapsed / maxf(_total * 0.85, 8.0), 0.0, 1.0)
				_spawn_timer = lerpf(0.85, 0.32, speed) * _rng.randf_range(0.7, 1.3)
	for i in _holes.size():
		_update_hole(i, delta)
	for f in _fx:
		f.t += delta
		f.vel.y += f.grav * _s * delta
		f.pos += f.vel * delta
		f.rot += f.spin * delta
	_fx = _fx.filter(func(f): return f.t < f.life)
	for p in _pops:
		p.t += delta
		p.pos.y -= 46.0 * _s * delta
	_pops = _pops.filter(func(p): return p.t < p.life)
	queue_redraw()
	for c in _slot_ctrls:
		c.queue_redraw()
	for c in _front_ctrls:
		c.queue_redraw()
	_overlay.queue_redraw()


func _spawn() -> void:
	var free: Array[int] = []
	var busy := 0
	for i in _holes.size():
		if _holes[i].state == HIDDEN:
			free.append(i)
		else:
			busy += 1
	var max_up := 2 + int(_elapsed / 6.0)
	if free.is_empty() or busy >= max_up:
		return
	var i := free[_rng.randi_range(0, free.size() - 1)]
	var h := _holes[i]
	var r := _rng.randf()
	h.kind = GOLD if r < 0.06 else (CHERUB if r < 0.22 else IMP)
	h.variant = _rng.randi_range(0, 3)
	h.state = RISING
	h.t = 0.0
	h.hit = false
	var speed := clampf(_elapsed / maxf(_total * 0.85, 8.0), 0.0, 1.0)
	h.dur = lerpf(1.35, 0.62, speed) * _rng.randf_range(0.85, 1.2)
	if h.kind == GOLD:
		h.dur *= 0.7
	elif h.kind == CHERUB:
		h.dur *= 1.25
	_play("boing" if h.kind != GOLD else "shine", _rng.randf_range(0.9, 1.2))


func _update_hole(i: int, delta: float) -> void:
	var h := _holes[i]
	if h.state == HIDDEN:
		return
	h.t += delta
	match h.state:
		RISING:
			if h.t >= RISE_TIME:
				h.state = UP
				h.t = 0.0
		UP:
			if h.t >= h.dur:
				h.state = FALLING
				h.t = 0.0
				if h.kind == IMP and _running:
					if combo >= 3:
						_pop_text("combo lost", _head_pos(i) + Vector2(0, -60) * _s, Color(0.6, 0.55, 0.75), 22)
					combo = 0
					if _rng.randf() < 0.35:
						_pop_text(TAUNTS[_rng.randi_range(0, TAUNTS.size() - 1)], _head_pos(i) + Vector2(0, -40) * _s, Color(0.85, 0.3, 0.35), 22)
		FALLING:
			if h.t >= FALL_TIME:
				h.state = HIDDEN
				h.kind = NONE
		BONKED:
			if h.t >= BONK_TIME:
				h.state = HIDDEN
				h.kind = NONE


# 0 = hidden in the cloud, 1 = fully up.
func _rise(h: Dictionary) -> float:
	match h.state:
		RISING:
			var u: float = h.t / RISE_TIME
			return 1.0 + 1.7 * pow(u - 1.0, 3.0) + 0.7 * pow(u - 1.0, 2.0)   # ease-out-back
		UP:
			return 1.0
		FALLING:
			var u: float = h.t / FALL_TIME
			return 1.0 - u * u
		BONKED:
			if h.t < 0.32:
				return 1.0
			var u: float = (h.t - 0.32) / (BONK_TIME - 0.32)
			return 1.0 - u * u
	return 0.0


# Squash & stretch (x, y) for the critter's current moment.
func _squash(h: Dictionary) -> Vector2:
	var sy := 1.0
	match h.state:
		RISING:
			sy = 1.0 + 0.28 * sin(h.t / RISE_TIME * PI)
		UP:
			sy = 1.0 + 0.12 * sin(h.t * 26.0) * exp(-h.t * 6.0) + 0.025 * sin(_time * 5.0 + h.variant)
		FALLING:
			sy = 1.0 + 0.2 * h.t / FALL_TIME
		BONKED:
			sy = 1.0 - 0.45 * exp(-h.t * 9.0) * cos(h.t * 28.0)
	return Vector2(1.0 + (1.0 - sy) * 0.8, sy)


# Bottom-centre of the critter's head (its squash pivot).
func _head_base(i: int) -> Vector2:
	var k := _s * 0.92
	var c := _hole_pos(i)
	return Vector2(c.x, c.y + 100.0 * k - _rise(_holes[i]) * 150.0 * k)


func _head_pos(i: int) -> Vector2:
	return _head_base(i) + Vector2(0, -50.0 * _s * 0.92)


func _gui_input(event: InputEvent) -> void:
	if not _running:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	_click(mb.position)


func _click(at: Vector2) -> void:
	_hammer_t = 0.0
	var best_i := -1
	var best_d := INF
	for i in _holes.size():
		var h := _holes[i]
		if h.kind == NONE or h.state == BONKED or h.state == HIDDEN or _rise(h) < 0.3:
			continue
		var d := at.distance_to(_head_pos(i))
		if d < 62.0 * _s and d < best_d:
			best_d = d
			best_i = i
	if best_i < 0:
		_play("whiff", _rng.randf_range(0.9, 1.15))
		if combo >= 3:
			_pop_text("combo lost", at + Vector2(0, -20) * _s, Color(0.6, 0.55, 0.75), 22)
		elif _rng.randf() < 0.5:
			_pop_text(WHIFFS[_rng.randi_range(0, WHIFFS.size() - 1)], at + Vector2(0, -20) * _s, Color(0.55, 0.55, 0.75), 22)
		combo = 0
		_ring(at, Color(1, 1, 1, 0.6), 30.0)
		return
	var h := _holes[best_i]
	h.state = BONKED
	h.t = 0.0
	h.hit = true
	var head := _head_pos(best_i)
	_ring(head, Color(1, 0.95, 0.7, 0.9), 80.0)
	match h.kind:
		IMP:
			combo += 1
			var pts := 1
			if combo % 5 == 0:
				pts += 2
				_pop_text("COMBO x%d! +3" % combo, head + Vector2(0, -95) * _s, Color(1.0, 0.55, 0.85), 30)
				_play("combo", 1.0 + minf(combo / 5 - 1, 4) * 0.08)
			score += pts
			_score_bump = 1.0
			_combo_bump = 1.0
			_burst(head, 9, [C_GOLD, Color(1, 1, 1), Color(1, 0.6, 0.8)])
			if pts == 1:
				_pop_text(POP_WORDS[_rng.randi_range(0, POP_WORDS.size() - 1)], head + Vector2(0, -60) * _s, Color(1.0, 0.86, 0.3), 40)
			_play("bonk", _rng.randf_range(0.9, 1.15))
		GOLD:
			combo += 1
			score += 5
			_score_bump = 1.0
			_combo_bump = 1.0
			_burst(head, 18, [C_GOLD, Color(1, 0.95, 0.6), Color(1, 1, 1)])
			_pop_text("JACKPOT! +5", head + Vector2(0, -64) * _s, Color(1.0, 0.82, 0.15), 44)
			_play("bonk", 0.85)
			_play("ding", 1.0)
		CHERUB:
			combo = 0
			score = maxi(score - 2, 0)
			_score_bump = 1.0
			_burst(head, 8, [Color(0.6, 0.85, 1.0), Color(1, 1, 1)])
			_pop_text(CHERUB_WORDS[_rng.randi_range(0, CHERUB_WORDS.size() - 1)], head + Vector2(0, -64) * _s, Color(0.45, 0.75, 1.0), 36)
			_play("ouch", 1.0)


func _burst(at: Vector2, n: int, cols: Array) -> void:
	for k in n:
		var a := _rng.randf() * TAU
		var sp := _rng.randf_range(160.0, 360.0) * _s
		_fx.append({"kind": 0 if k % 3 != 2 else 1, "pos": at, "vel": Vector2(cos(a), sin(a) - 0.6) * sp,
				"grav": 700.0, "t": 0.0, "life": _rng.randf_range(0.5, 0.85), "rot": _rng.randf() * TAU,
				"spin": _rng.randf_range(-8.0, 8.0), "size": _rng.randf_range(7.0, 13.0), "col": cols[k % cols.size()]})
	if _fx.size() > 140:
		_fx = _fx.slice(_fx.size() - 140)


func _ring(at: Vector2, col: Color, radius: float) -> void:
	_fx.append({"kind": 2, "pos": at, "vel": Vector2.ZERO, "grav": 0.0, "t": 0.0, "life": 0.3,
			"rot": 0.0, "spin": 0.0, "size": radius, "col": col})


func _pop_text(text: String, at: Vector2, col: Color, font_size: int) -> void:
	at.y = maxf(at.y, 150.0 * _s)   # stay clear of the title
	_pops.append({"text": text, "pos": at, "t": 0.0, "life": 0.9, "col": col, "size": font_size,
			"rot": _rng.randf_range(-0.18, 0.18)})
	if _pops.size() > 12:
		_pops.pop_front()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var w := size.x
	var hgt := size.y
	# Sky: lavender -> pink -> warm peach.
	var top := Color(0.5, 0.58, 0.93)
	var mid := Color(0.9, 0.78, 0.93)
	var bot := Color(1.0, 0.87, 0.7)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, hgt * 0.55), Vector2(0, hgt * 0.55)]),
			PackedColorArray([top, top, mid, mid]))
	draw_polygon(PackedVector2Array([Vector2(0, hgt * 0.55), Vector2(w, hgt * 0.55), Vector2(w, hgt), Vector2(0, hgt)]),
			PackedColorArray([mid, mid, bot, bot]))
	# Heavenly light rays from above, slowly turning.
	var src := Vector2(w * 0.5, -60.0 * _s)
	var reach := maxf(w, hgt) * 1.4
	for k in 14:
		var a := PI * 0.5 + (k - 6.5) * 0.17 + sin(_time * 0.25) * 0.05
		var d1 := Vector2(cos(a - 0.035), sin(a - 0.035)) * reach
		var d2 := Vector2(cos(a + 0.035), sin(a + 0.035)) * reach
		draw_polygon(PackedVector2Array([src, src + d1, src + d2]),
				PackedColorArray([Color(1, 1, 0.9, 0.16), Color(1, 1, 0.9, 0.0), Color(1, 1, 0.9, 0.0)]))
	draw_circle(src + Vector2(0, 40) * _s, 150.0 * _s, Color(1, 0.98, 0.85, 0.18))
	draw_circle(src + Vector2(0, 40) * _s, 90.0 * _s, Color(1, 0.98, 0.85, 0.22))
	# Drifting background clouds, three layers (far ones paler, slower).
	for layer in 3:
		for c in _bg_clouds:
			if int(c.w) != layer:
				continue
			var spd := (6.0 + layer * 7.0) / 1280.0
			var span := w + 400.0 * _s
			var x := fposmod(c.x * span + _time * spd * w, span) - 200.0 * _s
			var y := c.y * hgt
			var col := Color(1, 1, 1, 0.28 + layer * 0.14)
			_cloud(self, Vector2(x, y), c.z * (0.9 + layer * 0.35) * _s, col, Color(0.85, 0.82, 0.98, col.a * 0.8), false)
	# A soft bank of cloud along the bottom (the waiting room floor).
	var n := int(w / (120.0 * _s)) + 2
	for k in n:
		var x := k * 120.0 * _s
		var r := (70.0 + 18.0 * sin(k * 2.3)) * _s
		draw_circle(Vector2(x, hgt + 10.0 * _s), r + 6.0 * _s, Color(0.9, 0.82, 0.95, 0.7))
		draw_circle(Vector2(x, hgt + 18.0 * _s), r, Color(1, 0.97, 0.98, 0.85))
	# Back halves of the hole clouds (behind the critters).
	for i in HOLES.size():
		var c := _hole_pos(i)
		draw_circle(c + Vector2(0, 6) * _s, 60.0 * _s, Color(0.55, 0.5, 0.78, 0.18))
		_cloud(self, c + Vector2(0, -2) * _s, 0.88 * _s, C_CLOUD_BACK, Color(0.72, 0.7, 0.9), false)


# One fluffy cloud of PUFFS, `k` = scale (1 = 200 units wide at design scale... in pixels via caller).
func _cloud(ci: CanvasItem, c: Vector2, k: float, col: Color, shade: Color, highlight: bool) -> void:
	for p in PUFFS:
		ci.draw_circle(c + Vector2(p.x, p.y + 7.0) * k, p.z * k, shade)
	for p in PUFFS:
		ci.draw_circle(c + Vector2(p.x, p.y) * k, p.z * k, col)
	if highlight:
		var hi := Color(1, 1, 1, 0.9)
		for p in PUFFS:
			if p.y < 12:
				ci.draw_circle(c + Vector2(p.x - p.z * 0.25, p.y - p.z * 0.3) * k, p.z * 0.45 * k, hi)


func _draw_front(i: int) -> void:
	var ci := _front_ctrls[i]
	var c := _hole_pos(i) + Vector2(0, 30) * _s
	var bob := sin(_time * 1.6 + i * 1.3) * 2.0 * _s
	# A golden imp makes its cloud glow from behind.
	var h := _holes[i]
	if h.kind == GOLD and h.state != HIDDEN:
		for k in 3:
			ci.draw_circle(c + Vector2(0, -4) * _s, (110.0 - k * 18.0) * _s, Color(1, 0.85, 0.35, 0.1))
	_cloud(ci, c + Vector2(0, bob), 0.92 * _s, C_CLOUD, C_CLOUD_SHADE, true)


func _draw_slot(i: int) -> void:
	var h := _holes[i]
	if h.state == HIDDEN or h.kind == NONE:
		return
	var ci := _slot_ctrls[i]
	var k := _s * 0.92
	var sq := _squash(h)
	var base := _head_base(i) - ci.position
	var tilt := 0.0
	if h.state == BONKED:
		tilt = sin(h.t * 30.0) * 0.12 * exp(-h.t * 4.0)
	elif h.state == UP:
		tilt = sin(_time * 3.0 + i) * 0.06
	ci.draw_set_transform(base, tilt, sq * k)
	var look := (get_local_mouse_position() - _head_pos(i)).limit_length(200.0) / 200.0
	match h.kind:
		IMP:
			_draw_imp(ci, h, look, false)
		GOLD:
			_draw_imp(ci, h, look, true)
		CHERUB:
			_draw_cherub(ci, h, look)
	ci.draw_set_transform(Vector2.ZERO)
	if h.state == BONKED:
		# Dizzy stars orbiting the bonked head.
		var c := _head_base(i) - ci.position + Vector2(0, -102) * k * sq.y
		for s in 3:
			var a: float = h.t * 9.0 + s * TAU / 3.0
			var p := c + Vector2(cos(a) * 42.0, sin(a) * 11.0) * k
			_star(ci, p, 9.0 * k, a, Color(1, 0.9, 0.3), C_GOLD_DARK)


# Head art, local units: head is a radius-50 circle centred on (0, -50); the pivot is its bottom.
func _draw_imp(ci: CanvasItem, h: Dictionary, look: Vector2, golden: bool) -> void:
	var bonked: bool = h.state == BONKED
	var skin := Color(0.9, 0.24, 0.27) if not golden else Color(1.0, 0.78, 0.2)
	var dark := Color(0.62, 0.1, 0.18) if not golden else Color(0.8, 0.5, 0.06)
	if not golden and h.variant == 2:
		skin = Color(0.85, 0.3, 0.5)
		dark = Color(0.55, 0.12, 0.3)
	var horn := Color(0.98, 0.93, 0.82) if not golden else Color(1, 1, 0.85)
	var c := Vector2(0, -50)
	# Horns (curved, drawn before the head so they sit behind it).
	for sgn in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		var bend := 1.0 if (h.variant != 1 or sgn < 0) else -0.6
		for j in 9:
			var u := j / 8.0
			pts.append(Vector2(sgn * (26.0 + 18.0 * u + bend * 6.0 * u * u), -82.0 - 36.0 * u + 10.0 * u * u * (1.0 - bend)) + Vector2(sgn * -10.0 * (1.0 - u), 0))
		for j in range(8, -1, -1):
			var u := j / 8.0
			var wdt := 14.0 * (1.0 - u)
			pts.append(Vector2(sgn * (26.0 + 18.0 * u + bend * 6.0 * u * u) + sgn * wdt, -82.0 - 36.0 * u + 10.0 * u * u * (1.0 - bend) + wdt * 0.6))
		ci.draw_colored_polygon(pts, horn)
		ci.draw_polyline(pts + PackedVector2Array([pts[0]]), C_INK, 2.5, true)
	# Pointy ears.
	for sgn in [-1.0, 1.0]:
		var ear := PackedVector2Array([Vector2(sgn * 40, -62), Vector2(sgn * 74, -72), Vector2(sgn * 44, -38)])
		ci.draw_colored_polygon(ear, dark)
		ci.draw_polyline(ear + PackedVector2Array([ear[0]]), C_INK, 2.5, true)
	# Head with cartoon outline, shading and a shine.
	ci.draw_circle(c, 53.0, C_INK)
	ci.draw_circle(c, 50.0, dark)
	ci.draw_circle(c + Vector2(-4, -5), 45.0, skin)
	ci.draw_circle(c + Vector2(-20, -26), 11.0, Color(1, 1, 1, 0.35))
	ci.draw_circle(c + Vector2(-27, -18), 5.0, Color(1, 1, 1, 0.3))
	if golden:
		var glint := 0.5 + 0.5 * sin(_time * 8.0)
		_star(ci, c + Vector2(30, -34), 9.0 + glint * 4.0, _time * 2.0, Color(1, 1, 1, 0.9), Color(1, 1, 1, 0))
	# Cheeks.
	ci.draw_circle(c + Vector2(-28, 10), 8.0, Color(1, 0.45, 0.45, 0.45))
	ci.draw_circle(c + Vector2(28, 10), 8.0, Color(1, 0.45, 0.45, 0.45))
	# Eyes.
	if bonked:
		for sgn in [-1.0, 1.0]:
			var e := c + Vector2(sgn * 18, -8)
			ci.draw_line(e + Vector2(-8, -8), e + Vector2(8, 8), C_INK, 5.0, true)
			ci.draw_line(e + Vector2(-8, 8), e + Vector2(8, -8), C_INK, 5.0, true)
	elif golden:
		# Too cool: sunglasses.
		ci.draw_line(c + Vector2(-38, -12), c + Vector2(38, -12), C_INK, 5.0, true)
		for sgn in [-1.0, 1.0]:
			var g := PackedVector2Array([c + Vector2(sgn * 6, -14), c + Vector2(sgn * 36, -14), c + Vector2(sgn * 33, 2), c + Vector2(sgn * 22, 6), c + Vector2(sgn * 9, 0)])
			ci.draw_colored_polygon(g, Color(0.12, 0.08, 0.15))
			ci.draw_line(c + Vector2(sgn * 12 + 6, -10), c + Vector2(sgn * 12 + 12, -4), Color(1, 1, 1, 0.6), 3.0, true)
	else:
		for sgn in [-1.0, 1.0]:
			var e := c + Vector2(sgn * 18, -8)
			_ellipse(ci, e, 12.0, 14.0, Color(1, 0.95, 0.5))
			_ellipse(ci, e + look * Vector2(5, 5), 4.0, 9.0, C_INK)
			ci.draw_circle(e + look * Vector2(5, 5) + Vector2(-1.5, -4), 2.0, Color(1, 1, 1))
			# Mischievous eyebrows.
			ci.draw_line(e + Vector2(-sgn * 12, -22), e + Vector2(sgn * 12, -15), C_INK, 5.0, true)
	# Mouth.
	if bonked:
		var m := PackedVector2Array()
		for j in 9:
			m.append(c + Vector2(-14 + j * 3.5, 22 + (4.0 if j % 2 == 0 else -2.0)))
		ci.draw_polyline(m, C_INK, 4.0, true)
		_ellipse(ci, c + Vector2(10, 32), 8.0, 10.0, Color(1, 0.5, 0.6))   # tongue lolling out
		ci.draw_line(c + Vector2(10, 26), c + Vector2(10, 36), Color(0.8, 0.25, 0.4), 2.0, true)
	else:
		var grin := PackedVector2Array()
		for j in 13:
			var u := j / 12.0
			grin.append(c + Vector2(lerpf(-26, 26, u), 14 + sin(u * PI) * 16.0 - u * 4.0))
		var fill := grin.duplicate()
		fill.append(c + Vector2(0, 14))
		ci.draw_colored_polygon(fill, Color(0.35, 0.05, 0.12))
		ci.draw_polyline(grin, C_INK, 4.0, true)
		ci.draw_line(c + Vector2(-26, 14), c + Vector2(26, 10), C_INK, 4.0, true)
		# One wonky fang.
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-14, 13), c + Vector2(-6, 12), c + Vector2(-10, 22)]), Color(1, 1, 1))
		if h.variant == 3 or h.state == FALLING:
			_ellipse(ci, c + Vector2(8, 28), 8.0, 9.0, Color(1, 0.5, 0.6))   # blep


func _draw_cherub(ci: CanvasItem, h: Dictionary, look: Vector2) -> void:
	var bonked: bool = h.state == BONKED
	var c := Vector2(0, -50)
	var flap := sin(_time * 18.0) * 0.25
	# Little wings.
	for sgn in [-1.0, 1.0]:
		var wing := PackedVector2Array()
		for j in 10:
			var a: float = lerpf(-1.4, 1.2, j / 9.0) + flap * sgn
			wing.append(c + Vector2(sgn * 48, -4) + Vector2(sgn * cos(a) * 30.0, sin(a) * 24.0 - 10.0))
		wing.append(c + Vector2(sgn * 40, 4))
		_wing_draw(ci, wing)
	# Halo.
	var hy := -118.0 + sin(_time * 4.0) * 3.0
	_halo_ring(ci, Vector2(0, hy), 30.0, 7.0, 6.0)
	# Face.
	var skin := Color(1.0, 0.86, 0.76)
	ci.draw_circle(c, 53.0, C_INK)
	ci.draw_circle(c, 50.0, Color(0.95, 0.7, 0.62))
	ci.draw_circle(c + Vector2(-4, -5), 45.0, skin)
	# Golden curls.
	for j in 7:
		var a := lerpf(-2.6, -0.5, j / 6.0)
		var p := c + Vector2(cos(a), sin(a)) * 44.0
		ci.draw_circle(p, 15.0, C_INK)
		ci.draw_circle(p, 13.0, Color(1.0, 0.82, 0.35))
		ci.draw_circle(p + Vector2(-3, -4), 5.0, Color(1, 0.95, 0.7))
	ci.draw_circle(c + Vector2(-28, 12), 10.0, Color(1, 0.5, 0.55, 0.5))
	ci.draw_circle(c + Vector2(28, 12), 10.0, Color(1, 0.5, 0.55, 0.5))
	if bonked:
		for sgn in [-1.0, 1.0]:
			var e := c + Vector2(sgn * 18, -2)
			var arc := PackedVector2Array()
			for j in 7:
				var u := j / 6.0
				arc.append(e + Vector2(lerpf(-9, 9, u), -sin(u * PI) * 6.0 + 4.0))
			ci.draw_polyline(arc, C_INK, 4.0, true)
			_ellipse(ci, e + Vector2(sgn * 4, 14 + h.t * 30.0), 4.0, 6.0, Color(0.5, 0.8, 1.0))   # tears
		_ellipse(ci, c + Vector2(0, 24), 10.0, 12.0, Color(0.4, 0.1, 0.15))   # "waah"
	else:
		for sgn in [-1.0, 1.0]:
			var e := c + Vector2(sgn * 18, -4)
			_ellipse(ci, e, 9.0, 12.0, C_INK)
			ci.draw_circle(e + look * 3.0 + Vector2(-2, -4), 3.5, Color(1, 1, 1))
			ci.draw_circle(e + Vector2(3, 4), 1.6, Color(1, 1, 1))
		var smile := PackedVector2Array()
		for j in 9:
			var u := j / 8.0
			smile.append(c + Vector2(lerpf(-12, 12, u), 18 + sin(u * PI) * 8.0))
		ci.draw_polyline(smile, C_INK, 4.0, true)


func _wing_draw(ci: CanvasItem, pts: PackedVector2Array) -> void:
	ci.draw_colored_polygon(pts, Color(1, 1, 1))
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), C_INK, 3.0, true)


func _halo_ring(ci: CanvasItem, at: Vector2, r: float, ry: float, wdt: float) -> void:
	var pts := PackedVector2Array()
	for j in 33:
		var a := j / 32.0 * TAU
		pts.append(at + Vector2(cos(a) * r, sin(a) * ry))
	ci.draw_polyline(pts, Color(1, 0.95, 0.6, 0.35), wdt * 2.2, true)
	ci.draw_polyline(pts, C_GOLD_DARK, wdt + 2.0, true)
	ci.draw_polyline(pts, C_GOLD, wdt, true)


func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for j in 18:
		var a := j / 18.0 * TAU
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, col)


func _star(ci: CanvasItem, c: Vector2, r: float, rot: float, col: Color, edge: Color) -> void:
	var pts := PackedVector2Array()
	for j in 10:
		var a := rot + j * PI / 5.0 - PI * 0.5
		var rr := r if j % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, col)
	if edge.a > 0.0:
		ci.draw_polyline(pts + PackedVector2Array([pts[0]]), edge, 1.5, true)


func _text(ci: CanvasItem, pos: Vector2, text: String, font_size: int, col: Color, outline: int = 6,
		align := HORIZONTAL_ALIGNMENT_CENTER, outline_col := C_INK) -> void:
	var wdt := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= wdt * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= wdt
	var p := Vector2(x, pos.y)
	if outline > 0:
		ci.draw_string_outline(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, outline_col)
	ci.draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _fs(px: float) -> int:
	return maxi(int(px * _s), 15)


func _draw_overlay() -> void:
	var o := _overlay
	var w := size.x
	var hgt := size.y
	# Sparkles, stars and shock rings.
	for f in _fx:
		var u: float = f.t / f.life
		var col: Color = f.col
		match f.kind:
			0:
				_star(o, f.pos, f.size * _s * (1.0 - u * 0.6), f.rot, Color(col, 1.0 - u * u), Color(C_GOLD_DARK, 1.0 - u))
			1:
				o.draw_circle(f.pos, f.size * 0.5 * _s * (1.0 - u), Color(col, 1.0 - u))
			2:
				o.draw_arc(f.pos, f.size * _s * (0.4 + u), 0.0, TAU, 32, Color(col, (1.0 - u) * col.a), 6.0 * _s * (1.0 - u) + 1.0, true)
	# --- HUD: title.
	var ty := 54.0 * _s
	var wob := sin(_time * 2.2) * 0.02
	o.draw_set_transform(Vector2(w * 0.5, ty), wob, Vector2.ONE)
	_text(o, Vector2(0, 0), "WHACK-AN-IMP", _fs(50), C_GOLD, maxi(int(10 * _s), 5))
	o.draw_set_transform(Vector2.ZERO)
	_text(o, Vector2(w * 0.5, ty + 30.0 * _s), "Heaven's waiting room  ·  bonk the imps, spare the cherubs", _fs(20), Color(1, 1, 1), maxi(int(6 * _s), 4), HORIZONTAL_ALIGNMENT_CENTER, Color(0.35, 0.25, 0.5))
	# Text pop-ups: overshoot pop, drift up, fade out.
	for p in _pops:
		var t: float = p.t
		var sc := 1.0
		if t < 0.18:
			var u := t / 0.18
			sc = 0.3 + u * 1.15 - sin(u * PI) * -0.2
		elif t < 0.3:
			sc = lerpf(1.45, 1.0, (t - 0.18) / 0.12)
		var a := clampf((p.life - t) / 0.3, 0.0, 1.0)
		o.draw_set_transform(p.pos, p.rot, Vector2(sc, sc))
		var col: Color = p.col
		_text(o, Vector2(0, 0), p.text, _fs(p.size), Color(col, a), maxi(int(8 * _s), 4), HORIZONTAL_ALIGNMENT_CENTER, Color(C_INK, a))
		o.draw_set_transform(Vector2.ZERO)
	# Score plaques.
	var pw := 190.0 * _s
	var ph := 84.0 * _s
	var margin := 24.0 * _s
	_plaque(o, Rect2(margin, margin, pw, ph), "BONKS", str(score), _score_bump)
	# The record to beat (Ted, Nov 26: "so they could see how they did relative to the record"), and under
	# your score, how far off it you are, or that you've beaten it.
	_plaque(o, Rect2(w - margin - pw, margin, pw, ph), "RECORD", str(record), 0.0)
	var chase := ""
	var chase_col := Color(0.55, 0.4, 0.7)
	if score > record and record > 0:
		chase = "NEW RECORD!"
		chase_col = C_GOLD if fmod(_elapsed, 0.5) < 0.3 else Color(1.0, 0.6, 0.85)
	elif record > 0:
		chase = "%d to beat it" % (record - score + 1)
	if chase != "":
		_text(o, Vector2(w - margin - pw * 0.5, margin + ph + 30.0 * _s), chase, _fs(22), chase_col, maxi(int(6 * _s), 3))
	if combo >= 2:
		var cs := 1.0 + _combo_bump * 0.35
		o.draw_set_transform(Vector2(margin + pw * 0.5, margin + ph + 34.0 * _s), -0.06, Vector2(cs, cs))
		_text(o, Vector2.ZERO, "COMBO x%d" % combo, _fs(26), Color(1.0, 0.6, 0.85), maxi(int(7 * _s), 4))
		o.draw_set_transform(Vector2.ZERO)
	# Countdown bar to the hunt.
	var bw := minf(620.0 * _s, w - 40.0)
	var bh := 26.0 * _s
	var bx := (w - bw) * 0.5
	var by := hgt - 46.0 * _s
	var frac := clampf(_seconds_left / _total, 0.0, 1.0)
	_box.set_corner_radius_all(int(bh * 0.5))
	_box.bg_color = Color(0.25, 0.15, 0.35, 0.55)
	_box.border_color = C_INK
	_box.set_border_width_all(maxi(int(3 * _s), 2))
	o.draw_style_box(_box, Rect2(bx, by, bw, bh))
	if frac > 0.0:
		var urgent := _seconds_left <= 5.0
		_box.bg_color = Color(1.0, 0.45, 0.4) if urgent and fmod(_time, 0.5) < 0.25 else C_GOLD
		_box.set_border_width_all(0)
		var inset := 4.0 * _s
		o.draw_style_box(_box, Rect2(bx + inset, by + inset, maxf((bw - inset * 2.0) * frac, bh - inset * 2.0), bh - inset * 2.0))
		o.draw_rect(Rect2(bx + inset + bh * 0.3, by + inset + 2.0 * _s, maxf((bw - inset * 2.0) * frac - bh * 0.6, 0.0), 3.0 * _s), Color(1, 1, 1, 0.45))
	var secs := int(ceil(_seconds_left))
	var msg := "The hunt begins in %d…" % secs if secs > 0 else "HERE WE GO!"
	var ms := 1.0
	if secs <= 3:
		ms = 1.0 + 0.25 * maxf(0.0, 1.0 - (fmod(_seconds_left, 1.0) if secs > 0 else 0.0) * 4.0) * (1.0 if secs > 0 else 0.0)
	o.draw_set_transform(Vector2(w * 0.5, by - 12.0 * _s), 0.0, Vector2(ms, ms))
	_text(o, Vector2.ZERO, msg, _fs(28), Color(1, 1, 1) if secs > 3 else Color(1, 0.85, 0.3), maxi(int(8 * _s), 4))
	o.draw_set_transform(Vector2.ZERO)
	# The halo "hammer" that follows the mouse and slams down on click.
	var m := get_local_mouse_position()
	var swing := clampf(_hammer_t / 0.16, 0.0, 1.0)
	var lift := (1.0 - exp(-swing * 4.0)) if _hammer_t < 0.16 else 1.0
	var hp := m + Vector2(16, -26) * _s * lift
	var tilt := lerpf(0.0, -0.35, lift)
	o.draw_set_transform(hp, tilt, Vector2.ONE)
	var r := 22.0 * _s * (1.0 + (1.0 - lift) * 0.25)
	_halo_ring(o, Vector2.ZERO, r, r * 0.38, 5.0 * _s)
	o.draw_set_transform(Vector2.ZERO)


func _plaque(o: Control, r: Rect2, label: String, value: String, bump: float) -> void:
	_box.set_corner_radius_all(int(18 * _s))
	_box.bg_color = Color(1, 1, 1, 0.82)
	_box.border_color = C_GOLD_DARK
	_box.set_border_width_all(maxi(int(4 * _s), 2))
	o.draw_style_box(_box, r)
	_text(o, Vector2(r.position.x + r.size.x * 0.5, r.position.y + 26.0 * _s), label, _fs(18), Color(0.55, 0.4, 0.7), 0)
	var sc := 1.0 + bump * 0.4
	o.draw_set_transform(Vector2(r.position.x + r.size.x * 0.5, r.position.y + 70.0 * _s), 0.0, Vector2(sc, sc))
	_text(o, Vector2.ZERO, value, _fs(42), C_GOLD, maxi(int(8 * _s), 4))
	o.draw_set_transform(Vector2.ZERO)


# ---------------------------------------------------------------- sounds

func _play(sound: String, pitch: float) -> void:
	if not _sounds.has(sound) or _players.is_empty():
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = _sounds[sound]
	p.pitch_scale = pitch
	p.play()


func _make_sounds() -> void:
	if not _sounds.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	# BONK: a hollow woody knock with a falling pitch.
	_sounds["bonk"] = _synth(0.26, func(t: float, ph: Array) -> float:
		ph[0] += TAU * (95.0 + 260.0 * exp(-t * 30.0)) / 22050.0
		ph[1] += TAU * 720.0 / 22050.0
		var knock := sin(ph[1]) * exp(-t * 60.0) * 0.5
		var noise := rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.35
		return (sin(ph[0]) * exp(-t * 14.0) + knock + noise) * 0.55)
	# BOING: a springy wobble rising up out of the cloud.
	_sounds["boing"] = _synth(0.3, func(t: float, ph: Array) -> float:
		ph[0] += TAU * (240.0 + 280.0 * t / 0.3 + 30.0 * sin(t * 70.0)) / 22050.0
		return sin(ph[0]) * minf(t / 0.01, 1.0) * exp(-t * 9.0) * 0.18)
	# Golden imp shimmer + jackpot ding.
	_sounds["shine"] = _synth(0.45, func(t: float, ph: Array) -> float:
		ph[0] += TAU * (1320.0 + 200.0 * sin(t * 40.0)) / 22050.0
		ph[1] += TAU * 1980.0 / 22050.0
		return (sin(ph[0]) * 0.6 + sin(ph[1]) * 0.3) * minf(t / 0.02, 1.0) * exp(-t * 7.0) * 0.12)
	_sounds["ding"] = _synth(0.9, func(t: float, ph: Array) -> float:
		ph[0] += TAU * 1046.5 / 22050.0
		ph[1] += TAU * 1568.0 / 22050.0
		ph[2] += TAU * 2093.0 / 22050.0
		var s := sin(ph[0]) * 0.5 + sin(ph[1]) * 0.35 * float(t > 0.08) + sin(ph[2]) * 0.25 * float(t > 0.16)
		return s * minf(t / 0.005, 1.0) * exp(-t * 4.0) * 0.3)
	# Cherub "uh-oh": two falling notes.
	_sounds["ouch"] = _synth(0.42, func(t: float, ph: Array) -> float:
		var f := 620.0 if t < 0.16 else 440.0 * (1.0 - (t - 0.16) * 0.5)
		ph[0] += TAU * f / 22050.0
		var env := minf((t if t < 0.16 else t - 0.16) / 0.01, 1.0) * exp(-t * 3.0)
		return (sin(ph[0]) + 0.3 * sin(ph[0] * 2.0)) * env * 0.2)
	# Whiff: a quick airy swish.
	_sounds["whiff"] = _synth(0.18, func(t: float, ph: Array) -> float:
		ph[0] = lerpf(ph[0], rng.randf_range(-1.0, 1.0), 0.25)
		return ph[0] * sin(t / 0.18 * PI) * 0.35)
	# Countdown tick and combo chime.
	_sounds["tick"] = _synth(0.12, func(t: float, ph: Array) -> float:
		ph[0] += TAU * 880.0 / 22050.0
		return sin(ph[0]) * exp(-t * 40.0) * 0.25)
	_sounds["combo"] = _synth(0.5, func(t: float, ph: Array) -> float:
		var note: float = [784.0, 988.0, 1175.0, 1568.0][mini(int(t / 0.07), 3)]
		ph[0] += TAU * note / 22050.0
		return sin(ph[0]) * minf(fmod(t, 0.07) / 0.004, 1.0) * exp(-t * 4.0) * 0.18)


static func _synth(seconds: float, fn: Callable) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := [0.0, 0.0, 0.0]
	for i in n:
		var t := float(i) / rate
		var fade := minf(float(n - i) / (rate * 0.02), 1.0)   # no click at the end
		var v: float = fn.call(t, ph)
		data.encode_s16(i * 2, int(clampf(v * fade, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
