# The pickle's slime trail (playtest, Nov 26: "a faint slime trail behind it, that fades away after a second
# or two"). Anyone shaped like the pickle prop who is moving along the ground leaves glossy green smears
# that fade out. Only when they move: a pickle standing still (a real one, or a demon keeping still) leaves
# nothing, so it can't give a hidden demon away; a pickle sliding about is a giveaway already.
# Each screen draws its own from what it shows (no network traffic), like snow_tracks.gd. A fixed pool of
# flat quads, reused oldest-first, so it never piles up.
extends Node3D

const PropLib = preload("res://scripts/prop_library.gd")

const FADE := 2.0          # seconds a smear takes to fade away
const STEP := 0.22         # m between smears (each is longer, so they overlap into one streak)
const POOL := 48
const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
instance uniform float fade = 1.0;   // 1 = fresh, 0 = gone
varying vec2 lp;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { lp = VERTEX.xz * 4.0; }   // -1..1 across the quad
void fragment() {
	// a soft-edged, lumpy smear, wider in the middle, with a few glistening drops
	vec2 q = lp;
	float r = length(q) + (n2(lp * 9.0) - 0.5) * 0.35;
	float body = smoothstep(1.0, 0.45, r) * (0.75 + 0.25 * n2(lp * 3.0));
	float drops = smoothstep(0.78, 0.9, n2(lp * 14.0 + 7.0)) * smoothstep(1.3, 0.9, r);
	float a = max(body * 0.42, drops * 0.6) * fade;
	if (a < 0.01) discard;
	ALBEDO = mix(vec3(0.16, 0.34, 0.05), vec3(0.36, 0.6, 0.12), n2(lp * 5.0));
	ROUGHNESS = 0.06;
	SPECULAR = 0.9;
	METALLIC = 0.0;
	ALPHA = a;
}
"""

var _quads := []           # MeshInstance3D pool
var _born := []            # when each was laid (seconds), -100 = free
var _next := 0
var _clock := 0.0
var _tick := 0.0
var _last := {}            # node id -> where it last left a smear


func _ready() -> void:
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.5, 0.5)
	for i in POOL:
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_quads.append(mi)
		_born.append(-100.0)


static func is_pickle(n: Node) -> bool:
	for field in ["possessed_type", "form", "prop_type"]:
		var v = n.get(field)
		if v != null and str(v) != "" and PropLib.base_type(str(v)) == "pickle":
			return true
	return false


func _process(delta: float) -> void:
	_clock += delta
	for i in POOL:
		if _born[i] < 0.0:
			continue
		var f: float = 1.0 - (_clock - _born[i]) / FADE
		if f <= 0.0:
			_born[i] = -100.0
			_quads[i].visible = false
		else:
			_quads[i].set_instance_shader_parameter("fade", f)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.05
	var walkers := {}   # (players and remote players, plus practice bots; once each)
	for n in get_tree().get_nodes_in_group("snow_walker") + get_tree().get_nodes_in_group("demon"):
		walkers[n] = true
	for n in walkers:
		var w := n as Node3D
		if w == null or not w.is_visible_in_tree() or not is_pickle(w):
			continue
		if w.get("_vanished") == true or float(w.get("vanish_time") if w.get("vanish_time") != null else 0.0) > 0.0:
			continue   # invisible: no slime either
		var p := w.global_position
		var key := w.get_instance_id()
		if not _last.has(key):
			_last[key] = p
			continue
		var from: Vector3 = _last[key]
		if Vector2(p.x - from.x, p.z - from.z).length() < STEP:
			if absf(p.y - from.y) > 1.0:
				_last[key] = p   # (teleported, fell or flew: start again from here)
			continue
		_last[key] = p
		_lay(from, p)


# A smear between where it was and where it is now, on whatever is under it.
func _lay(from: Vector3, to: Vector3) -> void:
	var mid := (from + to) * 0.5
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(mid + Vector3.UP * 0.4, mid + Vector3.DOWN * 0.6, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.7:
		return   # in the air (or on a wall): nothing to smear on
	var mi: MeshInstance3D = _quads[_next]
	_born[_next] = _clock
	_next = (_next + 1) % POOL
	var dir := Vector3(to.x - from.x, 0.0, to.z - from.z).normalized()
	var up: Vector3 = hit["normal"]
	var side := up.cross(dir).normalized()
	var fwd := side.cross(up).normalized()
	var length := clampf(Vector2(to.x - from.x, to.z - from.z).length() * 4.5, 1.2, 2.4)
	mi.global_transform = Transform3D(Basis(side * 0.8, up, fwd * length), (hit["position"] as Vector3) + up * 0.012)
	mi.set_instance_shader_parameter("fade", 1.0)
	mi.visible = true
