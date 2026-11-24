# The look of the world: sky, sun, fog, glow, shadows, and the graphics quality
# setting (Low / Medium / High) that turns the costly parts on or off.
extends Node

const Surfaces = preload("res://scripts/surfaces.gd")
const Effects = preload("res://scripts/effects.gd")
const Models = preload("res://scripts/models.gd")

const QUALITY_NAMES := ["Low", "Medium", "High"]

# The sky: heavenly lavender overhead, a hellish glow at the horizon, a soft sun
# and slow drifting clouds. (A sky shader, so there are no image files.)
const SKY_SHADER := """
shader_type sky;

uniform vec3 top_color = vec3(0.32, 0.27, 0.62);
uniform vec3 mid_color = vec3(0.62, 0.5, 0.82);
uniform vec3 horizon_color = vec3(1.0, 0.58, 0.38);
uniform vec3 ground_color = vec3(0.28, 0.16, 0.14);
uniform vec3 cloud_color = vec3(1.0, 0.86, 0.9);
uniform float cloud_amount = 0.5;
uniform float stars = 0.0;
uniform float overcast = 0.0;

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	// each layer turned at an angle, so the clouds never line up on a grid
	mat2 turn = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
	for (int i = 0; i < 6; i++) {
		v += a * noise(p);
		p = turn * p + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return v;
}

void sky() {
	float y = EYEDIR.y;
	vec3 col;
	if (y > 0.0) {
		col = mix(horizon_color, mid_color, smoothstep(0.0, 0.25, y));
		col = mix(col, top_color, smoothstep(0.25, 0.9, y));
		// clouds: painted on a high flat ceiling, thinning toward the horizon
		// (they don't drift: a moving sky would cost a redraw every frame)
		vec2 uv = EYEDIR.xz / max(y, 0.05) * 0.6;
		float c = smoothstep(0.45 - cloud_amount * 0.2, 0.95, fbm(uv));
		c *= smoothstep(0.02, 0.25, y);
		col = mix(col, cloud_color * mix(0.85, 1.05, fbm(uv * 2.0)), c * 0.75);
		// stars at night, hidden behind the clouds
		vec2 cell = floor(EYEDIR.xz / max(y, 0.08) * 60.0);
		float star = step(0.9965, hash(cell)) * (0.5 + 0.5 * hash(cell + 7.0));
		col += vec3(star) * stars * smoothstep(0.08, 0.35, y) * (1.0 - c);
	} else {
		col = mix(horizon_color * 0.8, ground_color, smoothstep(0.0, -0.3, y));
	}
	// overcast: a flat grey lid of cloud
	float lum = dot(col, vec3(0.3, 0.55, 0.15));
	col = mix(col, vec3(lum) * vec3(0.92, 0.92, 1.0), overcast * smoothstep(-0.05, 0.1, y));
	// the sun: a bright disk with a warm halo around it (hidden by heavy cloud)
	float sun = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
	col += LIGHT0_COLOR * (pow(sun, 900.0) * 6.0 + pow(sun, 12.0) * 0.25) * (1.0 - overcast);
	COLOR = col;
}
"""

static var quality := 1

# Falling snow or rain: one mesh of many little quads, moved entirely in the shader (no particle
# system: those draw from the game's shared random numbers). Each drop has a fixed spot in a box
# that wraps around the camera, so it looks still in the world as you move through it.
const FALL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords;

uniform vec3 center;
uniform vec3 box = vec3(44.0, 26.0, 44.0);
uniform float speed = 2.0;
uniform float drift = 0.6;
uniform float size = 0.06;
uniform float stretch = 1.0;     // rain: long thin streaks
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.85);
uniform float round_drop = 1.0;  // snow: soft round flakes
varying vec2 uv;

void vertex() {
	vec4 seed = INSTANCE_CUSTOM;
	vec3 s = seed.xyz * box;
	float t = TIME * speed * (0.75 + seed.w * 0.5);
	vec3 moved = s + vec3(sin(TIME * 0.7 + seed.w * 20.0) * drift, -t, cos(TIME * 0.5 + seed.w * 11.0) * drift);
	vec3 corner = center - box * 0.5;
	vec3 p = corner + mod(moved - corner, box);
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 up = stretch > 1.0 ? vec3(0.0, 1.0, 0.0) : normalize(INV_VIEW_MATRIX[1].xyz);
	uv = UV;
	// (the quad's own corners, -0.5..0.5, come in as VERTEX before the model matrix: it's identity here)
	VERTEX = p + right * (UV.x - 0.5) * size + up * (UV.y - 0.5) * size * stretch;
}

void fragment() {
	vec2 d = uv - 0.5;
	float a = round_drop > 0.5 ? 1.0 - smoothstep(0.2, 0.5, length(d)) : 1.0 - smoothstep(0.25, 0.5, abs(d.x));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * a * smoothstep(1.2, 3.5, length(VERTEX));   // (no huge blobs right in your face)
}
"""

# Time of day (a map setting: Ted, Nov 19). Day is the original look.
const TIMES := {
	"day": {"sun_rot": -50.0, "sun_color": Color(1.0, 0.93, 0.82), "sun_energy": 1.15, "fill": 0.22,
		"top": Color(0.32, 0.27, 0.62), "mid": Color(0.62, 0.5, 0.82), "horizon": Color(1.0, 0.58, 0.38),
		"ground": Color(0.28, 0.16, 0.14), "cloud": Color(1.0, 0.86, 0.9), "stars": 0.0,
		"ambient": 1.0, "fog": Color(0.85, 0.62, 0.62), "exposure": 1.05},
	"dusk": {"sun_rot": -9.0, "sun_color": Color(1.0, 0.55, 0.32), "sun_energy": 0.85, "fill": 0.28,
		"top": Color(0.14, 0.1, 0.32), "mid": Color(0.45, 0.25, 0.5), "horizon": Color(1.0, 0.42, 0.2),
		"ground": Color(0.18, 0.08, 0.08), "cloud": Color(1.0, 0.55, 0.5), "stars": 0.25,
		"ambient": 0.7, "fog": Color(0.6, 0.32, 0.36), "exposure": 1.05},
	"night": {"sun_rot": -38.0, "sun_color": Color(0.55, 0.65, 1.0), "sun_energy": 0.3, "fill": 0.1,
		"top": Color(0.01, 0.01, 0.05), "mid": Color(0.03, 0.03, 0.1), "horizon": Color(0.14, 0.06, 0.14),
		"ground": Color(0.03, 0.02, 0.03), "cloud": Color(0.16, 0.16, 0.24), "stars": 1.0,
		"ambient": 0.45, "fog": Color(0.08, 0.07, 0.14), "exposure": 1.15},
}
const TIME_NAMES := ["day", "dusk", "night"]
var time_of_day := "day"
const Lamp = preload("res://scripts/lamp.gd")
var sky_mat: ShaderMaterial

# Weather (a map setting: Ted, Nov 20). Each changes the clouds, sun, haze, and maybe adds snow or rain.
const WEATHER := {
	"clear": {"clouds": 0.12, "overcast": 0.0, "sun": 1.0, "fog": 1.0, "fall": ""},
	"sunny_cloudy": {"clouds": 0.5, "overcast": 0.0, "sun": 1.0, "fog": 1.0, "fall": ""},
	"cloudy": {"clouds": 1.0, "overcast": 0.75, "sun": 0.45, "fog": 1.6, "fall": ""},
	"fog": {"clouds": 0.7, "overcast": 0.5, "sun": 0.65, "fog": 9.0, "fall": ""},
	"snow": {"clouds": 1.0, "overcast": 0.8, "sun": 0.5, "fog": 4.0, "fall": "snow"},
	"rain": {"clouds": 1.0, "overcast": 0.9, "sun": 0.35, "fog": 3.0, "fall": "rain"},
}
var weather := "sunny_cloudy"
var day_cycle := 0.0             # minutes for a whole day, night and back (0: the map's time stays put)
var _fall: MultiMeshInstance3D
var _fall_mat: ShaderMaterial

var env: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D


func _ready() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SKY_SHADER
	mat.shader = shader
	sky_mat = mat
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	# A little bloom, so halos, fire, eyes and blessings glow.
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# Hazy distance, tinted like the horizon.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.85, 0.62, 0.62)
	env.fog_density = 0.0045
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.04
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_blur = 1.5
	add_child(sun)
	# A soft lavender fill from the other side: shadowed sides aren't flat grey.
	fill = DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-25), deg_to_rad(210), 0)
	fill.light_color = Color(0.6, 0.55, 1.0)
	fill.light_energy = 0.22
	fill.shadow_enabled = false
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(fill)
	apply(quality)


func set_time_of_day(name: String) -> void:
	time_of_day = name if TIMES.has(name) else "day"
	_apply_look(TIMES[time_of_day])


func set_weather(name: String) -> void:
	weather = name if WEATHER.has(name) else "sunny_cloudy"
	_apply_look(_cycle_look() if day_cycle > 0.0 else TIMES[time_of_day])
	_make_fall(WEATHER[weather]["fall"])


# A day/night cycle (a map setting, in minutes): day, dusk, night, dawn, day... Driven by the
# computer's clock, so everyone online sees the same time of day whenever they joined.
func set_day_cycle(minutes: float) -> void:
	day_cycle = maxf(minutes, 0.0)
	_apply_look(_cycle_look() if day_cycle > 0.0 else TIMES[time_of_day])


const CYCLE_KEYS := ["day", "dusk", "night", "dusk"]   # (dawn looks like dusk)


func _cycle_look() -> Dictionary:
	var start := float(TIME_NAMES.find(time_of_day)) / 4.0
	var phase := fposmod(start + Time.get_unix_time_from_system() / (day_cycle * 60.0), 1.0) * 4.0
	var i := int(phase) % 4
	var k := smoothstep(0.55, 1.0, phase - floor(phase))   # hold each, then ease into the next
	var a: Dictionary = TIMES[CYCLE_KEYS[i]]
	var b: Dictionary = TIMES[CYCLE_KEYS[(i + 1) % 4]]
	var out := {}
	for key in a:
		out[key] = lerp(a[key], b[key], k)
	return out


func _process(_delta: float) -> void:
	if day_cycle > 0.0:
		_apply_look(_cycle_look())
	if _fall:
		var cam := get_viewport().get_camera_3d()
		if cam:
			_fall_mat.set_shader_parameter("center", cam.global_position)


func _apply_look(t: Dictionary) -> void:
	var w: Dictionary = WEATHER[weather]
	sun.rotation = Vector3(deg_to_rad(t["sun_rot"]), deg_to_rad(30), 0)
	sun.light_color = t["sun_color"]
	sun.light_energy = t["sun_energy"] * w["sun"]
	fill.light_energy = t["fill"]
	for k in ["top", "mid", "horizon", "ground", "cloud"]:
		var c: Color = t[k]
		sky_mat.set_shader_parameter(k + "_color", Vector3(c.r, c.g, c.b))
	sky_mat.set_shader_parameter("stars", t["stars"] * (1.0 - w["overcast"]))
	sky_mat.set_shader_parameter("cloud_amount", w["clouds"])
	sky_mat.set_shader_parameter("overcast", w["overcast"])
	env.ambient_light_energy = t["ambient"] * (1.0 + w["overcast"] * 0.25)
	env.fog_light_color = t["fog"]
	env.fog_density = 0.0045 * w["fog"]
	env.tonemap_exposure = t["exposure"]
	Lamp.darkness = t["stars"]   # (lamps with a daylight sensor come on from dusk)


func _make_fall(kind: String) -> void:
	if _fall:
		_fall.queue_free()
		_fall = null
	if kind == "":
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = [600, 1500, 2600][quality] * (2 if kind == "rain" else 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210   # (its own numbers, never the game's)
	for i in mm.instance_count:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	_fall = MultiMeshInstance3D.new()
	_fall.multimesh = mm
	_fall.custom_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))
	_fall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fall_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FALL_SHADER
	_fall_mat.shader = sh
	if kind == "rain":
		_fall_mat.set_shader_parameter("speed", 16.0)
		_fall_mat.set_shader_parameter("drift", 0.05)
		_fall_mat.set_shader_parameter("size", 0.025)
		_fall_mat.set_shader_parameter("stretch", 22.0)
		_fall_mat.set_shader_parameter("tint", Color(0.75, 0.8, 0.95, 0.35))
		_fall_mat.set_shader_parameter("round_drop", 0.0)
	_fall.material_override = _fall_mat
	add_child(_fall)


# Low: no ambient occlusion, sharper/cheaper shadows, FXAA, fewer
# particles. Medium: soft shadows, ambient occlusion, 2x MSAA. High: adds bounce
# light, light shafts in the haze and 4x MSAA.
func apply(level: int) -> void:
	quality = clampi(level, 0, 2)
	Effects.quality = quality
	Models.set_grime(quality >= 1)
	var vp := get_viewport()
	if _fall:
		_make_fall(WEATHER[weather]["fall"])   # (more drops on higher settings)
	env.ssao_enabled = quality >= 1
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssil_enabled = quality >= 2
	env.ssil_intensity = 0.6
	env.volumetric_fog_enabled = quality >= 2
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(1.0, 0.85, 0.85)
	env.volumetric_fog_anisotropy = 0.5
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_sky_affect = 0.0
	sun.shadow_blur = 1.0 if quality == 0 else 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if quality == 0 \
			else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	RenderingServer.directional_shadow_atlas_set_size(2048 if quality == 0 else 4096, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][quality])
	if vp:
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if quality == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
