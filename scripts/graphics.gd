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
	// the sun: a bright disk with a warm halo around it
	float sun = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
	col += LIGHT0_COLOR * (pow(sun, 900.0) * 6.0 + pow(sun, 12.0) * 0.25);
	COLOR = col;
}
"""

static var quality := 1

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
var sky_mat: ShaderMaterial

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
	var t: Dictionary = TIMES.get(name, TIMES["day"])
	time_of_day = name if TIMES.has(name) else "day"
	sun.rotation = Vector3(deg_to_rad(t["sun_rot"]), deg_to_rad(30), 0)
	sun.light_color = t["sun_color"]
	sun.light_energy = t["sun_energy"]
	fill.light_energy = t["fill"]
	for k in ["top", "mid", "horizon", "ground", "cloud"]:
		var c: Color = t[k]
		sky_mat.set_shader_parameter(k + "_color", Vector3(c.r, c.g, c.b))
	sky_mat.set_shader_parameter("stars", t["stars"])
	env.ambient_light_energy = t["ambient"]
	env.fog_light_color = t["fog"]
	env.tonemap_exposure = t["exposure"]


# Low: no ambient occlusion, sharper/cheaper shadows, FXAA, fewer
# particles. Medium: soft shadows, ambient occlusion, 2x MSAA. High: adds bounce
# light, light shafts in the haze and 4x MSAA.
func apply(level: int) -> void:
	quality = clampi(level, 0, 2)
	Effects.quality = quality
	Models.set_grime(quality >= 1)
	var vp := get_viewport()
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
