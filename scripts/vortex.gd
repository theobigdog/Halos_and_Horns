# The Vacuum Orb's vortex: a heavenly whirlpool of light that sucks everything toward a glowing, spinning core
# for Skills.VACUUM_TIME seconds. Its reach starts at VACUUM_RADIUS and shrinks to VACUUM_RADIUS_END while the
# suction gets stronger (Ted, Nov 24). Lines of dust, light motes and bits of debris stream in toward the core
# (all hand-animated in shaders: no particles), light rays fan out of it, a ring on the ground shows its reach.
#
# When a demon is caught in it (decided by the host / practice game and sent as "vortex_caught" fx, see main.gd)
# it turns blazing white-gold, the rays flare, it crackles, and the caught_loop sound comes in; back when not.
#
# Props are pulled here, every frame, with pure maths of (time, centre, start position), so every screen shows
# exactly the same thing (prop_offset() below). Demons are moved by the host (main.gd _vacuum_pulse).
extends Node3D

const Skills = preload("res://scripts/skills.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Effects = preload("res://scripts/effects.gd")
const VacuumSounds = preload("res://scripts/vacuum_sounds.gd")

const CORE_H := 1.1        # the core floats this high above where the orb hit
const OUTRO := 0.4         # after VACUUM_TIME: the core collapses with a flash
const T := Skills.VACUUM_TIME

var caught := false        # set before adding to the tree (the state at the start)
var ground_y := NAN        # world height of the ground under the centre (main.gd sets it)

var _age := 0.0
var _travel := 0.0         # how far the streaks have travelled (speeds up as it tightens)
var _heat := 0.0           # 0 calm .. 1 a demon is caught (smoothed)
var _pulls: Array = []     # [prop, start position, flat offset from centre, release time, visual, visual transform]
var _mats: Array = []      # every ShaderMaterial of this vortex (they all get the same uniforms)
var _ground: Node3D
var _core: Node3D
var _shell: Node3D
var _halo_mat: ShaderMaterial
var _light: OmniLight3D
var _suck: AudioStreamPlayer3D
var _caught_snd: AudioStreamPlayer3D
var _closed := false

static var _shaders := {}
static var _meshes := {}


# ---------- the maths every screen shares ----------

# The reach at time t.
static func radius_at(t: float) -> float:
	var k := clampf(t / T, 0.0, 1.0)
	return Skills.VACUUM_RADIUS - (Skills.VACUUM_RADIUS - Skills.VACUUM_RADIUS_END) * pow(k, 1.6)


# How hard it sucks, 0 (just opened) .. 1 (the end).
static func power_at(t: float) -> float:
	return clampf(t / T, 0.0, 1.0)


# Total suction so far: a jolt when it bursts open, then stronger and stronger.
static func _suction(t: float) -> float:
	var k := clampf(t / T, 0.0, 1.0)
	return 0.25 * (1.0 - exp(-t / 0.2)) + 2.4 * pow(k, 2.5)


# Distance from the centre at time t of a prop that started rho0 away (nearer = yanked harder).
static func _rho(rho0: float, t: float) -> float:
	var grip := 0.6 + 2.0 * pow(maxf(1.0 - rho0 / Skills.VACUUM_RADIUS, 0.0), 1.5)
	var rmin := 0.9 + 0.2 * rho0   # (props settle round the middle, not on top of a caught demon)
	return rmin + (rho0 - rmin) * exp(-_suction(t) * grip)


# When the shrinking reach passes a prop that started rho0 away, it lets go (T if never).
# Found by fixed steps + bisection, so it comes out identical everywhere.
static func release_time(rho0: float) -> float:
	var prev := 0.0
	var t := 0.0
	while t < T:
		t = minf(t + 0.05, T)
		if _rho(rho0, t) >= radius_at(t):
			var lo := prev
			var hi := t
			for i in 16:
				var mid := (lo + hi) * 0.5
				if _rho(rho0, mid) >= radius_at(mid):
					hi = mid
				else:
					lo = mid
			return lo
		prev = t
	return T


# Where a prop that started at flat offset `start` (from the centre, y = 0) is at time t: spiralling in.
static func prop_offset(start: Vector3, t: float, released: float) -> Vector3:
	var rho0 := start.length()
	if rho0 < 0.01:
		return start
	var tt := clampf(t, 0.0, released)
	var rho := _rho(rho0, tt)
	var swirl := 0.9 * (rho0 - rho) / maxf(rho0, 1.0)   # the same way round as the streaks
	var a := atan2(start.z, start.x) + swirl
	return Vector3(cos(a) * rho, 0.0, sin(a) * rho)


# Is this prop (flat offset from the centre) in reach when the vortex opens?
static func in_reach(offset: Vector3) -> bool:
	var d := Vector2(offset.x, offset.z).length()
	return d < Skills.VACUUM_RADIUS and d > 0.01 and absf(offset.y) < 4.0


# ---------- setup ----------

# main.gd hands us the props in reach (same list on every screen).
func pull(props_in_reach: Array) -> void:
	for prop in props_in_reach:
		var off: Vector3 = prop.global_position - global_position
		var flat := Vector3(off.x, 0.0, off.z)
		var vis := prop.get_child(0) as Node3D if prop.get_child_count() > 0 else null
		_pulls.append([prop, prop.global_position, flat, release_time(flat.length()), vis,
			vis.transform if vis else Transform3D.IDENTITY])


# Where pull() will leave a prop at the end (for anyone joining later).
static func final_position(center: Vector3, start: Vector3) -> Vector3:
	var flat := Vector3(start.x - center.x, 0.0, start.z - center.z)
	return Vector3(center.x, start.y, center.z) + prop_offset(flat, T, release_time(flat.length()))


func _ready() -> void:
	var q: int = Effects.quality
	_heat = 1.0 if caught else 0.0

	# Ring and spiral arms on the ground: shows the reach shrinking.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * (Skills.VACUUM_RADIUS * 2.0 + 1.5)
	ground.mesh = pm
	ground.material_override = _mat("ground")
	_ground = ground
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

	# Streaks of dust and light pouring in.
	var streaks := MultiMeshInstance3D.new()
	streaks.multimesh = _multimesh("streak", [70, 150, 230][q], _streak_mesh())
	streaks.material_override = _mat("streak")
	streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	streaks.custom_aabb = AABB(Vector3(-9, -6, -9), Vector3(18, 14, 18))
	add_child(streaks)

	# Bits of debris tumbling in (opaque and lit, so they sit in the world).
	var debris := MultiMeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	debris.multimesh = _multimesh("debris", [10, 22, 34][q], box)
	debris.material_override = _mat("debris")
	debris.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	debris.custom_aabb = streaks.custom_aabb
	add_child(debris)

	# Light rays, glow and (when caught) crackling bolts, on one camera-facing quad.
	var halo := MeshInstance3D.new()
	var qm := QuadMesh.new()
	halo.mesh = qm
	_halo_mat = _mat("halo")
	halo.material_override = _halo_mat
	halo.position.y = CORE_H
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.custom_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	add_child(halo)

	# The core: a bright ball with swirling bands, and a spinning see-through shell.
	_core = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.4
	sm.height = 0.8
	sm.radial_segments = 20
	sm.rings = 10
	(_core as MeshInstance3D).mesh = sm
	(_core as MeshInstance3D).material_override = _mat("core")
	(_core as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.position.y = CORE_H
	add_child(_core)
	if q > 0:
		_shell = MeshInstance3D.new()
		var sh := SphereMesh.new()
		sh.radius = 0.62
		sh.height = 1.24
		sh.radial_segments = 20
		sh.rings = 10
		(_shell as MeshInstance3D).mesh = sh
		(_shell as MeshInstance3D).material_override = _mat("shell")
		(_shell as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shell.position.y = CORE_H
		add_child(_shell)

	_light = OmniLight3D.new()
	_light.position.y = CORE_H
	_light.omni_range = 7.0
	_light.light_color = Color(1.0, 0.92, 0.75)
	_light.shadow_enabled = false
	add_child(_light)

	for m in _mats:
		m.set_shader_parameter("core_h", CORE_H)

	# Sounds: a burst, then the suction looping (with the "caught" layer faded in and out over it).
	_sound(VacuumSounds.open(), 0.0, true)
	_suck = _sound(VacuumSounds.suck_loop(), -4.0, true)
	_caught_snd = _sound(VacuumSounds.caught_loop(), -40.0 if not caught else 0.0, true)
	_update(0.0)


func set_caught(on: bool) -> void:
	caught = on


const LOUDNESS := -7.0   # everything the vacuum plays, this much quieter (playtest, Nov 26: really loud)


func _sound(stream: AudioStream, db: float, play: bool) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = Sfx.BUS
	p.stream = stream
	p.volume_db = db + LOUDNESS
	p.unit_size = 10.0
	p.max_distance = 90.0
	add_child(p)
	if play:
		p.play()
	return p


func _process(delta: float) -> void:
	_age += delta
	_heat = move_toward(_heat, 1.0 if caught else 0.0, delta * 5.0)
	_travel += delta * (0.55 + 1.1 * power_at(_age)) * (1.0 + 0.9 * _heat)
	_update(delta)
	if _age >= T and not _closed:
		_closed = true
		_finish_props()
		_sound(VacuumSounds.close(), 0.0, true)
	if _age >= T + OUTRO + 1.2:   # (a moment longer, so the close sound plays out)
		queue_free()


func _update(delta: float) -> void:
	var t := minf(_age, T)
	var pw := power_at(t)
	var r := radius_at(t)
	# 0..1 over the outro: the core collapses, a flash, then gone.
	var out := clampf((_age - T) / OUTRO, 0.0, 1.0)
	var open := clampf(_age / 0.25, 0.0, 1.0)
	var fade := open * (1.0 - out)
	# (Where the ground is: main.gd sets ground_y and our position right after adding us.)
	var gy := 0.0 if is_nan(ground_y) else clampf(ground_y - global_position.y, -6.0, 0.0)
	_ground.position.y = gy + 0.06
	for m in _mats:
		m.set_shader_parameter("ground", gy)
		m.set_shader_parameter("age", _age)
		m.set_shader_parameter("travel", _travel)
		m.set_shader_parameter("radius", r)
		m.set_shader_parameter("power", pw)
		m.set_shader_parameter("heat", _heat)
		m.set_shader_parameter("fade", fade)
	var flash := sin(out * PI)
	_halo_mat.set_shader_parameter("size", lerpf(5.5, 6.3, _heat) * (0.6 + 0.4 * open) + flash * 6.0)
	_halo_mat.set_shader_parameter("flash", flash)
	var throb := 1.0 + 0.06 * sin(_age * (9.0 + 10.0 * _heat))
	var s := (0.4 + 0.6 * open) * (1.0 - out) * (0.85 + 0.3 * pw + 0.25 * _heat) * throb
	_core.scale = Vector3.ONE * maxf(s, 0.001)
	_core.rotation.y += delta * (3.0 + 5.0 * pw + 6.0 * _heat)
	if _shell:
		_shell.scale = Vector3.ONE * maxf(s, 0.001)
		_shell.rotation.y -= delta * (4.0 + 6.0 * pw + 8.0 * _heat)
		_shell.rotation.x = 0.35 * sin(_age * 1.3)
	var flicker := 1.0 + _heat * 0.35 * sin(_age * 41.0) * sin(_age * 23.0)
	_light.light_energy = (lerpf(1.6, 3.0, pw) + 1.4 * _heat) * flicker * fade + flash * 6.0
	_light.light_color = Color(0.85, 0.85, 1.0).lerp(Color(1.0, 0.85, 0.5), 0.4 + 0.6 * _heat)
	_light.omni_range = lerpf(7.0, 9.0, _heat)
	if _suck:
		_suck.pitch_scale = lerpf(0.85, 1.45, pw) * (1.0 + 0.1 * _heat)
		_suck.volume_db = lerpf(-6.0, 0.0, pw) - 5.0 * _heat - 30.0 * out + LOUDNESS
		_caught_snd.volume_db = linear_to_db(maxf(_heat * (1.0 - out), 0.0001)) + LOUDNESS
		if out >= 1.0:
			_suck.stop()
			_caught_snd.stop()
			_suck = null
	_move_props(t)


# ---------- props ----------

func _move_props(t: float) -> void:
	for p in _pulls:
		var prop = p[0]
		if prop == null or not is_instance_valid(prop) or not prop.is_in_group("prop"):
			p[0] = null
			continue
		var knock: Node = prop.get_node_or_null("Knock")
		if knock and knock.is_physics_processing():
			_let_go(p)    # someone knocked it: physics (knock.gd) takes over from here
			continue
		var start: Vector3 = p[1]
		var off := prop_offset(p[2], t, p[3])
		prop.global_position = Vector3(global_position.x, start.y, global_position.z) + off
		# Lean into the pull while it's moving (looks only).
		var vis: Node3D = p[4]
		if vis and is_instance_valid(vis):
			var before := prop_offset(p[2], t - 0.06, p[3])
			var v := (off - before) / 0.06
			var lean := clampf(v.length() * 0.12, 0.0, 0.35)
			var axis := Vector3.UP.cross(v)
			if axis.length() > 0.001 and lean > 0.001:
				var xf: Transform3D = p[5]
				vis.transform = Transform3D(Basis(prop.global_basis.inverse() * axis.normalized(), lean), Vector3.ZERO) * xf
			else:
				vis.transform = p[5]


func _let_go(p: Array) -> void:
	var vis: Node3D = p[4]
	if vis and is_instance_valid(vis):
		vis.transform = p[5]
	p[0] = null


func _finish_props() -> void:
	_move_props(T)
	for p in _pulls:
		if p[0] != null:
			_let_go(p)


func _exit_tree() -> void:
	if not _closed:   # (round over mid-vortex) leave the visuals straight
		for p in _pulls:
			if p[0] != null and is_instance_valid(p[0]):
				_let_go(p)


# ---------- meshes and materials (made once, shared) ----------

func _mat(name: String) -> ShaderMaterial:
	if not _shaders.has(name):
		var sh := Shader.new()
		sh.code = _code(name)
		_shaders[name] = sh
	var m := ShaderMaterial.new()
	m.shader = _shaders[name]
	_mats.append(m)
	return m


static func _streak_mesh() -> ArrayMesh:
	if not _meshes.has("streak"):
		# A quad whose corners just say (along 0..1, across -1..1); the shader places it.
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)])
		arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_meshes["streak"] = am
	return _meshes["streak"]


# The same seeds every time (and on every screen), from a fixed-seed generator.
static func _multimesh(kind: String, n: int, mesh: Mesh) -> MultiMesh:
	var key := "%s%d" % [kind, n]
	if not _meshes.has(key):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = n
		var rng := RandomNumberGenerator.new()
		rng.seed = 7741 + n
		for i in n:
			mm.set_instance_transform(i, Transform3D.IDENTITY)
			mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
		_meshes[key] = mm
	return _meshes[key]


const COMMON := """
uniform float age = 0.0;
uniform float travel = 0.0;
uniform float radius = 8.0;
uniform float power = 0.0;
uniform float heat = 0.0;
uniform float fade = 1.0;
uniform float ground = 0.0;
uniform float core_h = 1.1;

float hash1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

// Along a trip in toward the core: p 0 (start, out at r0) .. 1 (inside the core). Spirals the same way
// round as the props (vortex.gd prop_offset).
vec3 trip(float p, float r0, float a0, float y0) {
	float e = p * p * (1.6 - 0.6 * p);
	float rad = mix(r0, 0.15, e);
	float ang = a0 + (1.4 + 2.2 * power + 1.6 * heat) * e;
	float y = mix(y0, core_h, smoothstep(0.0, 1.0, e * e * (3.0 - 2.0 * e)));
	return vec3(cos(ang) * rad, y, sin(ang) * rad);
}
"""


static func _code(name: String) -> String:
	match name:
		"streak":
			return "shader_type spatial;\nrender_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;\n" + COMMON + """
varying vec3 col;
varying float alpha_v;
varying vec2 q;

void vertex() {
	vec4 h = INSTANCE_CUSTOM;
	float dust = step(h.w, 0.45);
	float rate = 1.0 / mix(0.9, 1.6, h.z);
	float ph = travel * rate + h.x;
	float cyc = floor(ph);
	float p = fract(ph);
	float k1 = hash1(cyc * 1.37 + h.x * 91.3);
	float k2 = hash1(cyc * 2.11 + h.y * 57.1);
	float r0 = radius * mix(0.4, 1.02, sqrt(k1));
	float a0 = (h.y + k2) * 6.2832;
	float y0 = ground + mix(mix(0.3, 2.6, k2), mix(0.03, 0.45, k1 * k2), dust);
	float len = mix(0.07, 0.16, h.z) * (1.0 + heat * 0.7);
	vec3 head = trip(p, r0, a0, y0);
	vec3 tail = trip(max(p - len, 0.0), r0, a0, y0);
	vec3 axis = head - tail;
	float al = length(axis);
	axis = al > 0.0001 ? axis / al : vec3(0.0, 1.0, 0.0);
	vec3 mid = mix(tail, head, VERTEX.x);
	vec3 cam = INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz;
	vec3 side = cross(axis, cam - mid);
	side = length(side) > 0.0001 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	float w = mix(mix(0.022, 0.045, k1), mix(0.07, 0.14, k1), dust) * (1.0 + heat * 0.6);
	w *= 1.0 - 0.6 * p;
	q = VERTEX.xy;
	VERTEX = mid + side * VERTEX.y * w;
	float e = p * p;
	// Dust: earthy, catching the light as it nears the core. Light motes: white, gold, pale blue, lavender.
	vec3 dust_c = mix(vec3(0.6, 0.52, 0.4), vec3(1.5, 1.35, 1.0), e * e);
	float pick = hash1(h.w * 17.3 + h.z);
	vec3 light_c = pick < 0.3 ? vec3(1.9, 1.9, 2.0) : (pick < 0.55 ? vec3(2.2, 1.6, 0.6) : (pick < 0.8 ? vec3(1.0, 1.5, 2.4) : vec3(1.6, 1.1, 2.3)));
	col = mix(light_c, dust_c, dust);
	vec3 blaze = pick < 0.6 ? vec3(2.8, 1.9, 0.6) : vec3(2.7, 2.6, 2.3);
	col = mix(col, blaze, heat * mix(0.7, 0.5, dust));
	alpha_v = smoothstep(0.0, 0.12, p) * (1.0 - smoothstep(0.82, 0.97, p)) * fade * mix(0.85, 0.8, dust);
}

void fragment() {
	// Bright at the head, fading back along the tail; soft edges across.
	ALBEDO = col;
	ALPHA = alpha_v * pow(clamp(q.x, 0.0, 1.0), 0.8) * pow(clamp(1.0 - abs(q.y), 0.0, 1.0), 1.5);
}
"""
		"debris":
			return "shader_type spatial;\nrender_mode cull_back;\n" + COMMON + """
varying vec3 tint;
varying float glow;

mat3 spin(vec3 ax, float a) {
	float s = sin(a); float c = cos(a); float oc = 1.0 - c;
	return mat3(vec3(oc * ax.x * ax.x + c, oc * ax.x * ax.y + ax.z * s, oc * ax.z * ax.x - ax.y * s),
		vec3(oc * ax.x * ax.y - ax.z * s, oc * ax.y * ax.y + c, oc * ax.y * ax.z + ax.x * s),
		vec3(oc * ax.z * ax.x + ax.y * s, oc * ax.y * ax.z - ax.x * s, oc * ax.z * ax.z + c));
}

void vertex() {
	vec4 h = INSTANCE_CUSTOM;
	float rate = 0.7 / mix(0.9, 1.5, h.z);
	float ph = travel * rate + h.x;
	float cyc = floor(ph);
	float p = fract(ph);
	float k1 = hash1(cyc * 1.91 + h.x * 71.3);
	float k2 = hash1(cyc * 3.07 + h.y * 37.9);
	float r0 = radius * mix(0.45, 1.0, sqrt(k1));
	float a0 = (h.y + k2) * 6.2832;
	float y0 = ground + mix(0.05, 0.4, k2);
	vec3 c = trip(p, r0, a0, y0);
	float size = mix(0.07, 0.17, h.w) * smoothstep(0.0, 0.1, p) * (1.0 - smoothstep(0.75, 0.95, p)) * fade;
	vec3 ax = normalize(vec3(h.z - 0.5, h.w - 0.4, h.y - 0.5) + vec3(0.001));
	mat3 r = spin(ax, travel * (4.0 + 6.0 * h.z) + h.x * 6.28);
	vec3 shape = vec3(1.0, mix(0.5, 1.0, h.y), mix(0.6, 1.3, h.x));
	VERTEX = c + r * (VERTEX * shape * size);
	NORMAL = r * NORMAL;
	float pick = hash1(h.w * 7.7);
	tint = pick < 0.35 ? vec3(0.45, 0.33, 0.22) : (pick < 0.7 ? vec3(0.52, 0.5, 0.47) : vec3(0.36, 0.48, 0.24));
	glow = smoothstep(0.5, 0.95, p) * (0.5 + 0.7 * heat) + heat * 0.06;
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.9;
	EMISSION = mix(vec3(1.4, 1.2, 0.8), vec3(3.0, 2.3, 1.0), heat) * glow;
}
"""
		"ground":
			return "shader_type spatial;\nrender_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;\n" + COMMON + """
varying vec2 xz;
void vertex() { xz = VERTEX.xz; }

void fragment() {
	float r = length(xz);
	float a = atan(xz.y, xz.x);
	float band = 0.18 + 0.12 * heat;
	float ring = exp(-pow((r - radius) / band, 2.0));
	ring += 0.35 * exp(-pow((r - radius - 0.35) / 0.08, 2.0)) * (0.5 + 0.5 * sin(a * 24.0 - age * 6.0));
	// Spiral arms of light sliding inward.
	float arms = pow(0.5 + 0.5 * sin(a * 4.0 + log(r + 0.2) * 7.0 + travel * 7.0), 6.0);
	arms *= smoothstep(radius + 0.2, radius * 0.4, r) * smoothstep(0.2, 1.2, r);
	float inner = exp(-r * r * 0.6);
	vec3 calm = mix(vec3(1.3, 1.1, 0.75), vec3(0.85, 1.0, 1.6), 0.5 + 0.5 * sin(a * 2.0 + travel));
	vec3 blaze = vec3(3.0, 2.2, 0.9);
	vec3 c = mix(calm, blaze, heat);
	float k = ring * (0.8 + 0.8 * heat) + arms * (0.18 + 0.3 * power + 0.4 * heat) + inner * (0.3 + 0.6 * heat);
	ALBEDO = c * k;
	ALPHA = fade;
}
"""
		"halo":
			return "shader_type spatial;\nrender_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;\n" + COMMON + """
uniform float size = 5.5;
uniform float flash = 0.0;

void vertex() {
	// Facing the camera, and drawn a little in front of the core (same size on screen) so the ground
	// doesn't slice the rays off with a hard line.
	vec3 c = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	float d = max(-c.z, 0.05);
	float nd = max(d - 3.0, d * 0.4);
	VERTEX = (c + vec3(VERTEX.xy * size, 0.0)) * (nd / d);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float a = atan(uv.y, uv.x);
	// Soft glow around the core.
	float glow = exp(-r * r * 22.0) * 1.6 + exp(-r * r * 5.0) * 0.35;
	// Light rays fanning out, slowly turning (sharper, longer and brighter when a demon is caught).
	float rays = pow(0.5 + 0.5 * sin(a * 7.0 + sin(a * 3.0 + age * 0.7) * 1.6 + age * 0.5), mix(5.0, 12.0, heat));
	rays += 0.7 * pow(0.5 + 0.5 * sin(a * 11.0 - age * 0.9 + 1.3), mix(9.0, 16.0, heat));
	rays *= smoothstep(1.0, 0.1, r) * smoothstep(0.02, 0.12, r) * (0.3 + 0.35 * power + 0.3 * heat);
	// Crackling bolts while a demon is caught: jagged, re-drawn many times a second.
	float bolts = 0.0;
	float flick = floor(age * 14.0);
	for (int k = 0; k < 5; k++) {
		float fk = float(k);
		float s = hash1(fk * 7.13 + flick * 1.71);
		float base = (fk / 5.0 + s * 0.2) * 6.2832;
		float dev = (hash1(floor(r * 9.0) + s * 31.0) - 0.5) * 0.5 + (hash1(floor(r * 23.0) + s * 13.0) - 0.5) * 0.18;
		float d = abs(mod(a - base - dev + 3.14159, 6.28318) - 3.14159) * r;
		float reach = mix(0.45, 0.95, hash1(s * 5.3 + fk));
		bolts += smoothstep(0.022, 0.0, d) * step(r, reach) * step(0.08, r) * step(0.35, hash1(s * 3.1 + flick));
	}
	bolts *= heat;
	vec3 calm = mix(vec3(1.4, 1.3, 1.15), vec3(1.0, 1.05, 1.5), 0.5 + 0.5 * sin(a * 2.0 + age));
	vec3 blaze = vec3(1.7, 1.2, 0.45);   // (toned down Nov 25: in daylight it whited out the screen)
	vec3 c = mix(calm, blaze, heat);
	vec3 outc = c * (glow * (1.0 + 0.25 * heat) + rays) + vec3(2.0, 1.8, 1.4) * bolts;
	outc += vec3(2.5, 2.3, 2.0) * flash * exp(-r * r * 4.0);
	ALBEDO = outc * max(fade, flash);
	ALPHA = 1.0;
}
"""
		"core":
			return "shader_type spatial;\nrender_mode unshaded, cull_back, shadows_disabled;\n" + COMMON + """
varying vec3 lp;
void vertex() { lp = VERTEX; }

void fragment() {
	vec3 n = normalize(lp);
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float a = atan(n.z, n.x);
	float band = 0.5 + 0.5 * sin(a * 3.0 + n.y * 5.0 - age * (4.0 + 4.0 * power + 6.0 * heat));
	float band2 = 0.5 + 0.5 * sin(a * 5.0 - n.y * 7.0 + age * 3.0);
	vec3 c = mix(vec3(1.5, 1.45, 1.4), mix(vec3(1.6, 1.1, 0.35), vec3(0.55, 0.9, 1.7), band2), band * 0.75);
	c = mix(c, vec3(1.2, 0.8, 1.9), fres * 0.6);
	vec3 blaze = mix(vec3(2.6, 1.7, 0.45), vec3(3.0, 2.8, 2.4), band);
	ALBEDO = mix(c, blaze, heat);
}
"""
		"shell":
			return "shader_type spatial;\nrender_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;\n" + COMMON + """
varying vec3 lp;
void vertex() { lp = VERTEX; }

void fragment() {
	vec3 n = normalize(lp);
	float fres = 1.0 - abs(dot(NORMAL, VIEW));
	float a = atan(n.z, n.x);
	float arms = pow(0.5 + 0.5 * sin(a * 2.0 + n.y * 6.0), 6.0);
	vec3 c = mix(vec3(0.9, 0.8, 1.4), vec3(2.4, 1.8, 0.7), heat);
	ALBEDO = c * (arms * 0.8 + fres * 0.5) * (0.5 + 0.5 * power + heat) * fade;
	ALPHA = 1.0;
}
"""
	return ""
