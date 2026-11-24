# Tracks in the snow (Ted, Nov 24: "the cheap way"). A small top-down map of the arena remembers when
# each spot was last trampled; a thin layer just over the ground shows trampled snow as grey-brown
# slush, fire-melted spots as dark wet patches, and fresh snow slowly fills them back in.
# Each pixel holds a time (seconds on snow_clock): slush fades out REFILL seconds after it. A fire
# stamps a time in the future, so its melted patch stays dark while it burns and a while after.
# Who leaves prints: anyone walking on the ground who looks like a person. Never a demon disguised as
# a prop, and never anyone invisible, so the snow can't give a hidden demon away. Each screen draws
# its own tracks from what it shows (no network traffic).
extends Node3D

const REFILL := 75.0          # seconds for fresh snow to cover a track
const FIRE_HOLD := 40.0       # a fire's melted patch stays this much longer
const PRINT_RADIUS := 0.3
const TRACKS_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D trample : filter_linear;
uniform vec4 area;            // centre x, centre z, width, 0
uniform float clock;
uniform float refill = 75.0;
uniform float texel = 0.004;
varying vec3 wp;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = (wp.xz - area.xy) / area.z + 0.5;
	// soften the pixel edges: blend this spot with its neighbours, each turned into "how trampled"
	float raw = 0.0;
	float tr = 0.0;
	for (int i = 0; i < 9; i++) {
		vec2 o = vec2(float(i % 3) - 1.0, float(i / 3) - 1.0) * texel * 0.9;
		float r = 1.0 - (clock - texture(trample, uv + o).r) / refill;   // 1 = just trampled, above 1 = still melting
		float w = (i == 4) ? 0.25 : 0.09375;
		raw += r * w;
		tr += clamp(r, 0.0, 1.0) * w;
	}
	float melt = smoothstep(1.0, 1.15, raw);
	float n = n2(wp.xz * 6.0) * 0.6 + n2(wp.xz * 19.0) * 0.4;
	vec3 slush = mix(vec3(0.5, 0.48, 0.47), vec3(0.34, 0.3, 0.27), n);
	vec3 wet = vec3(0.09, 0.075, 0.07) + n * 0.05;
	ALBEDO = mix(slush, wet, melt);
	ROUGHNESS = mix(0.8, 0.2, melt);
	ALPHA = max(smoothstep(0.1, 0.45, tr * (0.8 + 0.4 * n)) * 0.8, melt * 0.95);
}
"""

var _half := 28.0
var _res := 256
var _img: Image
var _tex: ImageTexture
var _mat: ShaderMaterial
var _clock := 0.0
var _tick := 0.0
var _dirty := false
var _last := {}               # node id -> last stamped spot (only stamp when they've moved)


func setup(half: float) -> void:
	_half = half
	_res = clampi(int(half * 2.0 / 0.18), 128, 512)
	_img = Image.create(_res, _res, false, Image.FORMAT_RF)
	_img.fill(Color(-100000.0, 0, 0))
	_tex = ImageTexture.create_from_image(_img)
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(half * 2.0, half * 2.0)
	plane.mesh = pm
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = TRACKS_SHADER
	_mat.shader = sh
	_mat.set_shader_parameter("trample", _tex)
	_mat.set_shader_parameter("area", Vector4(0, 0, half * 2.0, 0))
	_mat.set_shader_parameter("refill", REFILL)
	_mat.set_shader_parameter("texel", 1.0 / _res)
	plane.material_override = _mat
	plane.position.y = 0.008
	add_child(plane)


# Mark a round spot as trampled now (plus `hold` seconds: fires).
func stamp(at: Vector3, radius: float, hold := 0.0) -> void:
	if _img == null:
		return
	var px := (at.x + _half) / (_half * 2.0) * _res
	var pz := (at.z + _half) / (_half * 2.0) * _res
	var r := radius / (_half * 2.0) * _res
	var value := _clock + hold
	for y in range(int(pz - r) - 1, int(pz + r) + 2):
		for x in range(int(px - r) - 1, int(px + r) + 2):
			if x < 0 or y < 0 or x >= _res or y >= _res:
				continue
			if Vector2(x + 0.5 - px, y + 0.5 - pz).length() > r:
				continue
			if _img.get_pixel(x, y).r < value:
				_img.set_pixel(x, y, Color(value, 0, 0))
	_dirty = true


func _process(delta: float) -> void:
	_clock += delta
	if _mat:
		_mat.set_shader_parameter("clock", _clock)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.06
	for n in get_tree().get_nodes_in_group("snow_walker"):
		var w := n as Node3D
		if w == null or not w.is_visible_in_tree():
			continue
		if str(w.get("possessed_type") if w.get("possessed_type") != null else "") != "" or str(w.get("form") if w.get("form") != null else "") != "":
			continue   # looks like a prop: no prints, ever
		if w.get("_vanished") == true or float(w.get("vanish_time") if w.get("vanish_time") != null else 0.0) > 0.0:
			continue   # invisible: no prints either
		var p := w.global_position
		if p.y > 0.7 or absf(p.x) > _half or absf(p.z) > _half:
			continue   # (only on the ground)
		var key := w.get_instance_id()
		if _last.has(key) and (_last[key] as Vector3).distance_to(p) < 0.25:
			continue
		_last[key] = p
		stamp(p, PRINT_RADIUS)
	for f in get_tree().get_nodes_in_group("hellfire"):
		if f.has_method("is_lit") and f.is_lit() and (f as Node3D).global_position.y < 0.8:
			stamp((f as Node3D).global_position, 1.8, FIRE_HOLD)   # (Skills.FIRE_RADIUS)
	if _dirty:
		_dirty = false
		_tex.update(_img)
