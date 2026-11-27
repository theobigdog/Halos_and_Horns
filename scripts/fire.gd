# A demon's Hellfire: a fireball flies from the demon to where it aimed, then a
# patch of fire burns there for a few seconds. Angels standing in it are slowed
# and their blessing stamina burns away (main.gd checks `is_lit()` and `radius`).
# Every computer shows the same fire; positions come from the host.
#
# The look: in flight, a flaming comet (a hot core, a licking flame shell and a short
# tail of shrinking blobs along the arc). Where it lands, a roiling ball of hellfire
# the size of the burn area (Skills.FIRE_RADIUS), centred just above the surface and
# set along the surface normal so it sinks into slopes and walls the same way; it
# swells up on ignition, tongues of flame lick off the top, embers rise, a scorched
# ring with a glowing rim is projected onto the ground (a Decal, so it follows any
# surface), and it all dies down over the last second.
# Everything moves in shaders (TIME), no particles; meshes, materials and textures
# are made once and shared by every fire (per-fire differences are instance uniforms).
extends Node3D

const Skills = preload("res://scripts/skills.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Effects = preload("res://scripts/effects.gd")


var from := Vector3.ZERO
var vel := Vector3.ZERO           # thrown from `from` with this velocity...
var to := Vector3.ZERO            # ...and lights here after `flight_time` seconds
var flight_time := 0.3
var _travel := 0.0
var _travel_time := 0.3
var radius := Skills.FIRE_RADIUS   # (Custom rules: pool size, and splash pools their own size)
var life_time := Skills.FIRE_LIFETIME
var _life := Skills.FIRE_LIFETIME
var _age := 0.0                   # seconds since it lit
var _seed := 0.0
var _ball: Node3D                 # the comet while it flies
var _trail: Array[MeshInstance3D] = []
var _dome: MeshInstance3D         # the ball of fire once lit
var _core: MeshInstance3D
var _tongues: MeshInstance3D
var _embers: MeshInstance3D
var _flash: MeshInstance3D
var _scorch: Decal
var _up := Vector3.UP             # the surface normal where it landed
var _light: OmniLight3D
var _voice: AudioStreamPlayer3D
var _lit := false

const FireSounds = preload("res://scripts/fire_sounds.gd")
var _burn_voice: AudioStreamPlayer3D
const BURN_DB := -16.0      # (Sara, Nov 25: too loud; was 0, then -5, then -10; Ted, Nov 26: "needs to drop more")
const WHOOSH_DB := -15.0    # (the throw and the landing FWOOMP; was -9)

const SQUASH := 0.85              # the ball of fire is a little lower than it is wide
const SINK := 0.12                # its centre sits this far (x radius) above the surface
const TRAIL_STEP := 0.014         # seconds between the comet's tail blobs

static var _cache := {}


# --- shaders ---------------------------------------------------------------------------------

const NOISE := """
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.03 + vec3(7.1, 1.3, 4.7)) * 0.3 + vnoise(p * 4.11 + vec3(3.3, 8.1, 2.2)) * 0.15;
}
// heat 0..1 -> smoke, violet-crimson, blood red, orange, yellow-white (HDR, so it blooms)
vec3 fire_ramp(float k) {
	vec3 c = mix(vec3(0.07, 0.015, 0.06), vec3(0.42, 0.02, 0.14), smoothstep(0.0, 0.28, k));
	c = mix(c, vec3(1.5, 0.14, 0.03), smoothstep(0.25, 0.48, k));
	c = mix(c, vec3(2.4, 0.62, 0.06), smoothstep(0.48, 0.74, k));
	c = mix(c, vec3(2.9, 1.8, 0.45), smoothstep(0.8, 1.05, k));
	return c;
}
"""

# The roiling ball: a sphere pushed about by rising noise, its top stretched up into licks;
# hot where you look straight into it, dark crimson smoke at the rim, torn by noise up top.
const DOME_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;
instance uniform float seed = 0.0;
instance uniform float fade = 0.0;     // 0 burning .. 1 gone
instance uniform float heat = 1.0;     // brightness (the ignition flash goes above 1)
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
varying vec3 obj;
NOISE
void vertex() {
	vec3 n = normalize(VERTEX);
	float t = TIME + seed * 13.0;
	float d = fbm(n * 2.6 + vec3(seed * 5.0, -t * 1.6, seed * 3.0));
	float up = max(n.y, 0.0);
	VERTEX += n * (d - 0.45) * 0.36;
	VERTEX.y += up * up * up * (d - 0.2) * 0.9 * (1.0 - fade);
	obj = VERTEX;
}
void fragment() {
	float fres = abs(dot(NORMAL, VIEW));
	float t = TIME + seed * 13.0;
	float f = fbm(obj * 2.4 + vec3(seed * 3.1, -t * 2.1, seed * 1.7));
	float f2 = vnoise(obj * 6.5 + vec3(seed, -t * 4.0, 0.0));
	float h = max(obj.y, 0.0);
	float k = pow(fres, 1.3) * 0.92 - h * 0.5 + (f - 0.5) * 1.15 + (f2 - 0.5) * 0.4 + 0.06 - fade * 0.7;
	// fade out softly where it meets the ground or a wall, instead of a hard cut
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	float soft = clamp((VERTEX.z - v.z / v.w) / 0.4, 0.0, 1.0);
	ALBEDO = fire_ramp(k) * heat;
	ALPHA = clamp(smoothstep(0.02, 0.3, k) * (0.75 + 0.25 * smoothstep(0.3, 0.6, k)), 0.0, 1.0)
			* soft * (FRONT_FACING ? 1.0 : 0.4);
}
"""

# A hot glow inside the ball (added on top, so it lights up the middle).
const CORE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_add, fog_disabled;
instance uniform float seed = 0.0;
instance uniform float power = 1.0;
varying vec3 obj;
NOISE
void vertex() {
	obj = VERTEX;
}
void fragment() {
	float fres = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float f = fbm(obj * 3.0 + vec3(seed, -(TIME + seed * 9.0) * 2.5, 0.0));
	vec3 c = mix(vec3(1.1, 0.12, 0.05), vec3(1.3, 0.55, 0.12), clamp(power * 0.5, 0.0, 1.0));
	ALBEDO = c * pow(fres, 2.0) * (0.5 + f) * power;
}
"""

# Tongues of flame licking up off the ball: quads stood on its upper surface, turned to face
# the camera around the vertical, each growing, swaying and shrinking on its own cycle.
const TONGUE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;
instance uniform float seed = 0.0;
instance uniform float fade = 0.0;
varying vec2 uvv;
varying float sd;
varying float ph;
NOISE
void vertex() {
	float s = COLOR.r;
	float ang = COLOR.g * 6.2831853;
	float el = COLOR.b * 1.5707963;
	float p = fract(TIME * (0.7 + s * 0.6) + s * 7.31 + seed);
	vec3 dir = vec3(cos(ang) * cos(el), sin(el), sin(ang) * cos(el));
	vec3 right = transpose(mat3(MODEL_MATRIX)) * INV_VIEW_MATRIX[0].xyz;
	right.y = 0.0;
	right = normalize(right + vec3(1e-4, 0.0, 0.0));
	float grow = sin(3.14159 * p);
	float hgt = (0.75 + s * 0.7) * grow * (1.0 - fade * 0.85);
	float wid = (0.5 + s * 0.3) * (0.6 + 0.4 * grow);
	float y = UV.y;
	float sway = sin(TIME * 6.0 + s * 40.0 + y * 3.0) * 0.1 * y;
	VERTEX = dir * 0.6 + right * ((UV.x - 0.5) * wid + sway) + vec3(0.0, y * hgt + p * 0.3, 0.0);
	uvv = UV;
	sd = s;
	ph = p;
}
void fragment() {
	float y = uvv.y;
	float prof = pow(1.0 - y, 1.1) * (0.55 + 0.45 * smoothstep(0.0, 0.3, y));
	float f = vnoise(vec3(uvv.x * 4.0, y * 3.0 - TIME * 4.5, sd * 17.0));
	float f2 = vnoise(vec3(uvv.x * 9.0, y * 7.0 - TIME * 7.0, sd * 5.0));
	float d = abs(uvv.x - 0.5 + (f - 0.5) * 0.25 * y) * 2.0 / max(prof, 0.001);
	float k = (1.0 - d) + (f2 - 0.5) * 0.45 - y * 0.15 - fade * 0.5;
	ALBEDO = fire_ramp(0.35 + k * 0.55 - y * 0.15 - ph * 0.15);
	ALPHA = smoothstep(0.0, 0.45, k) * (1.0 - smoothstep(0.55, 1.0, ph) * 0.6) * smoothstep(0.0, 0.3, y);
}
"""

# Embers drifting up out of the fire: tiny camera-facing dots.
const EMBER_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, skip_vertex_transform, fog_disabled;
instance uniform float seed = 0.0;
instance uniform float fade = 0.0;
varying vec2 uvv;
varying float ph;
void vertex() {
	float s = COLOR.r;
	float ang = COLOR.g * 6.2831853;
	float p = fract(TIME * (0.3 + s * 0.35) + s * 5.17 + seed);
	float r = 0.15 + COLOR.b * 0.75;
	vec3 c = vec3(cos(ang) * r, 0.3 + p * 2.6, sin(ang) * r);
	c.x += sin(TIME * 2.1 + s * 31.0) * 0.25 * p;
	c.z += cos(TIME * 1.7 + s * 23.0) * 0.25 * p;
	vec4 v = MODELVIEW_MATRIX * vec4(c, 1.0);
	float sz = 0.07 * (1.0 - p * 0.7) * (1.0 - fade);
	VERTEX = v.xyz + vec3((UV - 0.5) * sz, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	uvv = UV;
	ph = p;
}
void fragment() {
	float d = length(uvv - 0.5) * 2.0;
	float twinkle = 0.6 + 0.4 * sin(TIME * 17.0 + ph * 50.0);
	ALBEDO = mix(vec3(3.0, 1.6, 0.4), vec3(1.6, 0.1, 0.05), ph) * max(1.0 - d, 0.0) * twinkle * (1.0 - ph);
}
"""


static func _shader(key: String, code: String) -> ShaderMaterial:
	if not _cache.has(key):
		var sh := Shader.new()
		sh.code = code.replace("NOISE", NOISE)
		var m := ShaderMaterial.new()
		m.shader = sh
		m.render_priority = {"tongue": 1, "ember": 2}.get(key, 0)
		_cache[key] = m
	return _cache[key]


static func _sphere(segments: int) -> SphereMesh:
	var key := "sphere%d" % segments
	if not _cache.has(key):
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = segments
		s.rings = segments / 2
		_cache[key] = s
	return _cache[key]


# n quads whose positions the shader works out; each quad's random numbers go in its colour.
static func _quads(key: String, n: int, rng_seed: int, aabb: AABB) -> ArrayMesh:
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = rng_seed
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in n:
			var c := Color(rng.randf(), (i + rng.randf() * 0.6) / n, rng.randf_range(0.2, 0.9), 1.0)
			var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
			for uv in corners:
				st.set_color(c)
				st.set_uv(uv)
				st.add_vertex(Vector3(uv.x - 0.5, uv.y, 0.0))
		var m := st.commit()
		m.custom_aabb = aabb
		_cache[key] = m
	return _cache[key]


# Smooth value noise for the scorch texture (a fixed-seed lattice, bilinear).
static func _lattice(size: int, rng_seed: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var a := PackedFloat32Array()
	a.resize(size * size)
	for i in a.size():
		a[i] = rng.randf()
	return a


static func _sample(lat: PackedFloat32Array, size: int, x: float, y: float) -> float:
	var xi := int(floor(x))
	var yi := int(floor(y))
	var fx := x - xi
	var fy := y - yi
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := lat[posmod(yi, size) * size + posmod(xi, size)]
	var b := lat[posmod(yi, size) * size + posmod(xi + 1, size)]
	var c := lat[posmod(yi + 1, size) * size + posmod(xi, size)]
	var d := lat[posmod(yi + 1, size) * size + posmod(xi + 1, size)]
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


# The scorch mark: charred soot fading out to a sharp burnt ring at exactly the burn radius,
# and (emission) a glowing rim plus smouldering cracks inside.
static func _scorch_textures() -> Array:
	if _cache.has("scorch"):
		return _cache["scorch"]
	var n := 128
	var lat := _lattice(16, 666)
	var lat2 := _lattice(16, 1313)
	var alb := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var emi := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var edge := 1.0 - 4.0 / n      # the decal is a hair wider than the burn circle
	for y in n:
		for x in n:
			var px := (x + 0.5) / n * 2.0 - 1.0
			var py := (y + 0.5) / n * 2.0 - 1.0
			var r := sqrt(px * px + py * py) / edge
			var nz := _sample(lat, 16, x / 8.0, y / 8.0) * 0.65 + _sample(lat, 16, x / 3.0 + 5.0, y / 3.0) * 0.35
			var nz2 := _sample(lat2, 16, x / 5.0, y / 5.0)
			var soot := (1.0 - smoothstep(0.55, 1.0, r - (nz - 0.5) * 0.3)) * 0.8
			var rim := exp(-pow((r - 0.975) / 0.03, 2.0))
			var a := clampf(maxf(soot, rim * 0.95), 0.0, 1.0) * (1.0 - smoothstep(1.0, 1.02, r))
			var dark := lerpf(0.05, 0.12, nz)
			alb.set_pixel(x, y, Color(dark * 1.1, dark * 0.45, dark * 0.5, a))
			var crack := smoothstep(0.035, 0.0, absf(nz2 - 0.5)) * (1.0 - smoothstep(0.5, 0.95, r)) * 0.8
			var glow := clampf(rim + crack, 0.0, 1.0) * (1.0 - smoothstep(1.0, 1.02, r))
			emi.set_pixel(x, y, Color(1.0 * glow, 0.28 * glow * glow, 0.05 * glow, 1.0))
	alb.generate_mipmaps()
	emi.generate_mipmaps()
	_cache["scorch"] = [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(emi)]
	return _cache["scorch"]


static func _hash(v: Vector3) -> float:
	return fposmod(sin(v.dot(Vector3(12.9898, 78.233, 37.719))) * 43758.5453, 1.0)


func _mesh(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("seed", _seed)
	return mi


# --- life ------------------------------------------------------------------------------------

func _ready() -> void:
	_life = life_time
	_travel_time = maxf(flight_time, 0.05)
	global_position = from
	_seed = _hash(to + from * 0.37) * 10.0
	var q := Effects.quality
	var seg: int = [12, 16, 20][clampi(q, 0, 2)]
	# Make the burning shaders now, while it flies, so lighting up doesn't hitch.
	_shader("tongue", TONGUE_SHADER)
	_shader("ember", EMBER_SHADER)

	# The comet: a flame shell round a hot core, and a tail of shrinking blobs along its arc.
	_ball = Node3D.new()
	add_child(_ball)
	var shell := _mesh(_sphere(seg), _shader("dome", DOME_SHADER))
	shell.scale = Vector3.ONE * 0.3
	_ball.add_child(shell)
	var core := _mesh(_sphere(seg), _shader("core", CORE_SHADER))
	core.scale = Vector3.ONE * 0.24
	core.set_instance_shader_parameter("power", 2.5)
	_ball.add_child(core)
	for i in [4, 7, 9][clampi(q, 0, 2)]:
		var k := float(i + 1) / float([4, 7, 9][clampi(q, 0, 2)])
		var b := _mesh(_sphere(seg), _shader("dome", DOME_SHADER) if k < 0.6 else _shader("core", CORE_SHADER))
		b.scale = Vector3.ONE * lerpf(0.28, 0.1, k)
		b.set_instance_shader_parameter("fade", lerpf(0.0, 0.4, k))
		b.set_instance_shader_parameter("power", lerpf(2.2, 0.5, k))
		b.set_instance_shader_parameter("seed", _seed + i * 1.7)
		add_child(b)
		b.top_level = true
		_trail.append(b)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.45, 0.15)
	_light.omni_range = 5.0
	_light.light_energy = 1.5
	_light.shadow_enabled = false
	add_child(_light)

	_voice = AudioStreamPlayer3D.new()
	_voice.bus = Sfx.BUS
	_voice.unit_size = 7.0
	_voice.max_distance = 70.0
	_voice.volume_db = WHOOSH_DB
	add_child(_voice)
	_voice.stream = FireSounds.whoosh()
	_voice.play()
	_burn_voice = AudioStreamPlayer3D.new()
	_burn_voice.bus = Sfx.BUS
	_burn_voice.unit_size = 7.0
	_burn_voice.max_distance = 70.0
	add_child(_burn_voice)
	_place_comet(0.0)


func is_lit() -> bool:
	return _lit


func _arc(ft: float) -> Vector3:
	return from + vel * ft + Vector3.DOWN * 0.5 * Skills.FIRE_GRAVITY * ft * ft


func _place_comet(ft: float) -> void:
	for i in _trail.size():
		var t := ft - (i + 1) * TRAIL_STEP
		_trail[i].visible = t > 0.0
		_trail[i].global_position = _arc(maxf(t, 0.0))


# Which way the surface under the landing spot faces (up if there's nothing to find).
func _surface_normal() -> Vector3:
	if not is_inside_tree():
		return Vector3.UP
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(to + Vector3.UP * 0.6, to + Vector3.DOWN * 0.8)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return Vector3.UP
	var n: Vector3 = hit["normal"]
	return n.normalized() if n.y > 0.2 else Vector3.UP


func _light_up() -> void:
	_lit = true
	global_position = to
	_ball.queue_free()
	_ball = null
	for b in _trail:
		b.queue_free()
	_trail.clear()
	_up = _surface_normal()
	var q := Effects.quality
	var seg: int = [16, 24, 32][clampi(q, 0, 2)]
	var center := Vector3.ZERO + _up * radius * SINK

	_dome = _mesh(_sphere(seg), _shader("dome", DOME_SHADER))
	_dome.position = center
	add_child(_dome)
	_core = _mesh(_sphere(16), _shader("core", CORE_SHADER))
	_core.position = center
	add_child(_core)
	var tongues: int = [5, 8, 11][clampi(q, 0, 2)]
	_tongues = _mesh(_quads("tongues%d" % tongues, tongues, 4242, AABB(Vector3(-1.4, -0.2, -1.4), Vector3(2.8, 2.8, 2.8))),
			_shader("tongue", TONGUE_SHADER))
	_tongues.position = center
	add_child(_tongues)
	if q > 0:
		var embers: int = [0, 10, 18][clampi(q, 0, 2)]
		_embers = _mesh(_quads("embers%d" % embers, embers, 777, AABB(Vector3(-1.4, 0.0, -1.4), Vector3(2.8, 3.4, 2.8))),
				_shader("ember", EMBER_SHADER))
		_embers.position = center
		add_child(_embers)
	# A flash of heat as it bursts into flame.
	_flash = _mesh(_sphere(16), _shader("core", CORE_SHADER))
	_flash.position = center
	add_child(_flash)

	# Scorched ground with a glowing rim at exactly the burn radius, on whatever it landed on.
	var tex := _scorch_textures()
	_scorch = Decal.new()
	var r := radius
	_scorch.size = Vector3(r * 2.0 * 128.0 / 124.0, 1.6, r * 2.0 * 128.0 / 124.0)
	_scorch.texture_albedo = tex[0]
	_scorch.texture_emission = tex[1]
	_scorch.emission_energy = 2.5
	_scorch.upper_fade = 0.25
	_scorch.lower_fade = 0.25
	_scorch.normal_fade = 0.5
	add_child(_scorch)
	_scorch.basis = _basis_up(_up)

	_light.position = center + Vector3.UP * 0.9
	_light.omni_range = 6.0
	_voice.stream = FireSounds.ignite()
	_voice.play()
	_burn_voice.stream = FireSounds.burn()
	_burn_voice.volume_db = BURN_DB
	_burn_voice.play()
	_update_fire()


static func _basis_up(up: Vector3) -> Basis:
	var side := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := up.cross(side).normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z)


func _update_fire() -> void:
	var r := radius
	# Swell from small to a little too big, then settle (ease out with an overshoot).
	var g := clampf(_age / 0.4, 0.0, 1.0)
	var swell := 1.0 + 2.2 * pow(g - 1.0, 3.0) + 1.2 * pow(g - 1.0, 2.0)
	var dying := clampf(1.0 - _life, 0.0, 1.0)
	var size := r * swell * (1.0 - dying * 0.35)
	var flat := SQUASH * (1.0 - dying * 0.55)
	var heat := 1.0 + 0.5 * maxf(0.0, 1.0 - _age / 0.5)
	_dome.scale = Vector3(size, size * flat, size)
	_dome.set_instance_shader_parameter("fade", dying)
	_dome.set_instance_shader_parameter("heat", heat)
	_core.scale = Vector3(size, size * flat, size) * 0.72
	_core.set_instance_shader_parameter("power", (1.0 - dying) * heat)
	_tongues.scale = Vector3(size, size, size)
	_tongues.position = _dome.position + Vector3.UP * size * (flat - 1.0) * 0.8
	_tongues.set_instance_shader_parameter("fade", dying)
	if _embers:
		_embers.scale = Vector3(size, size, size) / r
		_embers.set_instance_shader_parameter("fade", dying)
	var ft := clampf(_age / 0.45, 0.0, 1.0)
	_flash.visible = ft < 1.0
	if _flash.visible:
		_flash.scale = Vector3.ONE * r * lerpf(0.4, 1.5, sqrt(ft))
		_flash.set_instance_shader_parameter("power", 2.5 * (1.0 - ft) * (1.0 - ft))
	_scorch.emission_energy = (2.0 + 2.0 * maxf(0.0, 1.0 - _age)) * (1.0 - dying * 0.8)
	_scorch.modulate = Color(1, 1, 1, clampf(_life / 0.4, 0.0, 1.0))
	# Flicker from a few out-of-step waves (no randomness: the same on every screen).
	var t := Time.get_ticks_msec() * 0.001 + _seed
	var flicker := sin(t * 9.0) * 0.18 + sin(t * 23.0 + 1.3) * 0.1 + sin(t * 41.0 + 4.1) * 0.06
	_light.light_energy = (1.8 + flicker) * heat * (1.0 - dying)


func _process(delta: float) -> void:
	if not _lit:
		_travel += delta
		var t := minf(_travel / _travel_time, 1.0)
		var ft := t * _travel_time
		global_position = from + vel * ft + Vector3.DOWN * 0.5 * Skills.FIRE_GRAVITY * ft * ft
		_place_comet(ft)
		if t >= 1.0:
			_light_up()
		return
	_life -= delta
	_age += delta
	if _life < 1.0:
		_burn_voice.volume_db = BURN_DB + linear_to_db(maxf(_life, 0.01))
	if _life <= 0.0:
		queue_free()
		return
	_update_fire()
