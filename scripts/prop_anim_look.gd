# What animated props draw (prop_animator.gd): candle flames, a lamp shade's glow, the picture frames' four
# paintings (two of heaven, two of hell), scribbles, blood and dirt, puddles and pouring streams, gas
# burner flames, bite marks, a paper towel sheet and a fuse's sparks. All shaders and simple meshes: no
# Godot particles (they'd draw from the global RNG and shift seeded test maps), no textures.
extends RefCounted

const FLAME := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
instance uniform float seed = 0.0;
instance uniform float heat = 1.0;   // 0 = out
uniform vec3 core : source_color = vec3(1.0, 0.95, 0.7);
uniform vec3 edge : source_color = vec3(1.0, 0.45, 0.08);
void vertex() {
	// always faces the camera, but stays upright
	vec3 up = MODEL_MATRIX[1].xyz;
	vec3 side = normalize(cross(up, INV_VIEW_MATRIX[2].xyz)) * length(MODEL_MATRIX[0].xyz);
	vec3 fwd = normalize(cross(side, up));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side, 0.0), vec4(up, 0.0), vec4(fwd, 0.0), MODEL_MATRIX[3]);
}
void fragment() {
	float y = 1.0 - UV.y;
	float t = TIME * 1.0 + seed * 7.0;
	float sway = (sin(t * 9.0) * 0.6 + sin(t * 15.3) * 0.4) * 0.12 * y * y;
	float x = (UV.x - 0.5) * 2.0 - sway;
	float tip = 0.82 + 0.1 * sin(t * 12.0) + 0.06 * sin(t * 21.0);
	float w = 1.15 * sqrt(max(y, 0.0)) * pow(max(1.0 - y / tip, 0.0), 0.75);
	float d = abs(x) / max(w, 0.001);
	float body = smoothstep(1.0, 0.35, d) * smoothstep(0.0, 0.07, y) * step(y, tip);
	float inner = smoothstep(0.75, 0.0, d) * smoothstep(0.75, 0.15, y / tip);
	vec3 c = mix(edge, core, inner);
	c = mix(vec3(0.25, 0.4, 1.0), c, smoothstep(0.02, 0.16, y));   // blue at the root
	ALBEDO = c * body * 2.2 * heat;
}
"""

const GLOW := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, shadows_disabled;
uniform vec3 tint : source_color = vec3(1.0, 0.78, 0.45);
void fragment() {
	float face = abs(dot(NORMAL, VIEW));
	ALBEDO = tint * (0.18 + 0.45 * face);
}
"""

const PICTURE := """
shader_type spatial;
render_mode cull_disabled;
instance uniform float pic = 1.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * n2(p); p *= 2.03; a *= 0.5; } return v; }
vec3 clouds(vec2 uv, float base, vec3 col, vec3 bg) {
	float c = fbm(vec2(uv.x * 4.0, uv.y * 7.0));
	float m = smoothstep(base, base + 0.12, c + (0.5 - uv.y) * 0.9);
	return mix(bg, col * (0.85 + 0.25 * c), m);
}
void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);   // 0,0 bottom left
	vec3 c = vec3(0.0);
	float glow = 0.0;
	if (pic < 1.5) {
		// Heaven 1: a golden sunrise over the clouds, rays fanning up
		c = mix(vec3(1.0, 0.85, 0.5), vec3(0.45, 0.7, 1.0), smoothstep(0.2, 1.0, uv.y));
		vec2 d = uv - vec2(0.5, 0.25);
		float ang = atan(d.y, d.x);
		float rays = 0.5 + 0.5 * sin(ang * 22.0);
		c += vec3(1.0, 0.9, 0.6) * rays * 0.35 * smoothstep(0.9, 0.0, length(d));
		c = mix(c, vec3(1.0, 0.97, 0.85), smoothstep(0.13, 0.08, length(d)));   // the sun
		c = clouds(uv, 0.62, vec3(1.0, 0.98, 0.94), c);
		glow = 0.25;
	} else if (pic < 2.5) {
		// Heaven 2: the pearly gates, bright light pouring through
		c = mix(vec3(0.75, 0.85, 1.0), vec3(0.35, 0.55, 0.95), uv.y);
		float gate = step(abs(uv.x - 0.5), 0.3) * step(uv.y, 0.78 - 2.2 * pow(abs(uv.x - 0.5), 2.0)) * step(0.18, uv.y);
		float light = smoothstep(0.32, 0.0, abs(uv.x - 0.5)) * gate;
		float bars = step(0.5, fract(uv.x * 14.0)) * gate * step(abs(uv.x - 0.5), 0.27);
		c = mix(c, vec3(1.0, 0.97, 0.8), light);
		c = mix(c, vec3(0.95, 0.9, 0.82), bars * 0.85);
		float pillar = step(0.26, abs(uv.x - 0.5)) * step(abs(uv.x - 0.5), 0.36) * step(0.15, uv.y) * step(uv.y, 0.8);
		c = mix(c, vec3(0.97, 0.94, 0.9) * (0.8 + 0.2 * n2(uv * 40.0)), pillar);
		c = clouds(vec2(uv.x, uv.y + 0.32), 0.62, vec3(1.0), c);
		glow = 0.25;
	} else if (pic < 3.5) {
		// Hell 1: a lava river under black crags and a red sky
		c = mix(vec3(0.95, 0.35, 0.05), vec3(0.25, 0.02, 0.02), smoothstep(0.2, 1.0, uv.y));
		float crag = 0.45 + 0.25 * fbm(vec2(uv.x * 3.0, 1.0)) + 0.1 * abs(sin(uv.x * 9.0));
		c = mix(c, vec3(0.05, 0.02, 0.02), step(uv.y, crag) * step(0.3, uv.y));
		float river = smoothstep(0.08, 0.0, abs(uv.y - 0.18 - 0.06 * sin(uv.x * 8.0)));
		float flow = fbm(vec2(uv.x * 10.0 - TIME * 0.3, uv.y * 10.0));
		c = mix(c, mix(vec3(1.0, 0.3, 0.0), vec3(1.0, 0.9, 0.3), flow), river);
		c = mix(c, vec3(0.12, 0.03, 0.02), step(uv.y, 0.1));
		glow = 0.5 * river + 0.15;
	} else {
		// Hell 2: horns and burning eyes over the flames
		c = mix(vec3(0.5, 0.05, 0.02), vec3(0.08, 0.0, 0.0), uv.y);
		float f = fbm(vec2(uv.x * 6.0, uv.y * 3.0 - TIME * 0.6));
		float flames = step(uv.y, 0.25 + 0.3 * f);
		c = mix(c, mix(vec3(1.0, 0.35, 0.0), vec3(1.0, 0.85, 0.2), f), flames);
		vec2 p = uv - vec2(0.5, 0.58);
		float head = step(length(p * vec2(1.0, 1.25)), 0.2);
		float hornL = 0.0;
		for (int i = 0; i < 2; i++) {
			float sx = (i == 0) ? -1.0 : 1.0;
			vec2 q = uv - vec2(0.5 + sx * 0.15, 0.7);
			float k = q.y / 0.22;
			float hx = q.x - sx * 0.08 * k * k;
			hornL += step(abs(hx), 0.05 * (1.0 - k)) * step(0.0, k) * step(k, 1.0);
		}
		c = mix(c, vec3(0.04, 0.0, 0.0), clamp(head + hornL, 0.0, 1.0));
		float eyes = smoothstep(0.035, 0.015, min(length(p - vec2(-0.08, 0.03)), length(p - vec2(0.08, 0.03))));
		c = mix(c, vec3(1.0, 0.85, 0.1), eyes);
		glow = 0.3 * flames + 0.9 * eyes;
	}
	float vig = smoothstep(0.75, 0.3, length(uv - 0.5));
	ALBEDO = c * (0.55 + 0.45 * vig);
	EMISSION = c * glow;
	ROUGHNESS = 0.6;
}
"""

const SCRIBBLE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
instance uniform float progress = 0.0;   // 0..1: how much is written
instance uniform float fade = 1.0;
uniform vec3 ink : source_color = vec3(0.55, 0.05, 0.05);
void fragment() {
	vec2 uv = vec2(UV.x, UV.y);
	float a = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float line_y = 0.14 + fi * 0.14;
		float start = fi / 6.0;
		float done = clamp((progress - start) * 6.0, 0.0, 1.0);   // each line is written in turn, left to right
		float x = uv.x;
		float wob = 0.035 * sin(x * 55.0 + fi * 3.1) * sin(x * 9.0 + fi * 1.7) + 0.012 * sin(x * 140.0 + fi);
		float d = abs(uv.y - line_y - wob);
		float gap = step(0.3, fract(x * 3.3 + fi * 0.37));   // words
		float written = step(x, 0.08 + done * 0.84) * step(0.08, x);
		a = max(a, smoothstep(0.012, 0.004, d) * gap * written);
	}
	if (a * fade < 0.05) discard;
	ALBEDO = ink;
	ALPHA = a * fade;
	ROUGHNESS = 0.4;
}
"""

# Blood (the knife) and food grime (the sink's dishes): painted over a mesh as its material_overlay.
const SMEAR := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, shadows_disabled;
instance uniform float amount = 1.0;
uniform vec3 col_a : source_color = vec3(0.45, 0.02, 0.02);
uniform vec3 col_b : source_color = vec3(0.7, 0.05, 0.04);
uniform float scale = 9.0;
uniform float cover = 0.45;
uniform float gloss = 0.15;
varying vec3 lp;
float h(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float n3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h(i), h(i + vec3(1, 0, 0)), f.x), mix(h(i + vec3(0, 1, 0)), h(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(h(i + vec3(0, 0, 1)), h(i + vec3(1, 0, 1)), f.x), mix(h(i + vec3(0, 1, 1)), h(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void vertex() { lp = VERTEX * length(MODEL_MATRIX[0].xyz); }   // in metres, turning with the prop
void fragment() {
	float n = n3(lp * scale) * 0.65 + n3(lp * scale * 3.1) * 0.35;
	float drip = n3(vec3(lp.x * scale * 2.0, lp.y * scale * 0.4, lp.z * scale * 2.0));
	float m = smoothstep(cover, cover - 0.08, 1.0 - n) + smoothstep(0.8, 0.86, drip) * 0.8;
	m = clamp(m, 0.0, 1.0) * amount;
	if (m < 0.02) discard;
	ALBEDO = mix(col_a, col_b, n3(lp * scale * 5.0));
	ALPHA = m * 0.92;
	ROUGHNESS = gloss;
}
"""

# A flat round puddle (keg beer, pickle slime), growing in and fading out.
const PUDDLE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
instance uniform float grow = 1.0;
instance uniform float fade = 1.0;
uniform vec3 col : source_color = vec3(0.7, 0.45, 0.1);
uniform vec3 col2 : source_color = vec3(0.95, 0.75, 0.3);
uniform float opacity = 0.75;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float ang = atan(q.y, q.x);
	float edge = grow * (0.75 + 0.18 * sin(ang * 3.0 + 1.0) + 0.1 * n2(vec2(ang * 3.0, 2.0)));
	float r = length(q);
	float body = smoothstep(edge, edge - 0.08, r);
	float a = body * opacity * fade;
	if (a < 0.01) discard;
	ALBEDO = mix(col, col2, n2(q * 4.0) * 0.6 + 0.4 * smoothstep(edge - 0.3, edge, r));
	ALPHA = a;
	ROUGHNESS = 0.05;
	SPECULAR = 0.8;
}
"""

# A pouring stream (the keg's tap): a thin cylinder with liquid sliding down it.
const STREAM := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
instance uniform float flow = 1.0;
uniform vec3 col : source_color = vec3(0.75, 0.48, 0.1);
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	float n = n2(vec2(UV.x * 6.0, UV.y * 8.0 - TIME * 9.0));
	float a = flow * (0.65 + 0.3 * n) * step(UV.y, flow * 1.02);
	if (a < 0.02) discard;
	ALBEDO = col * (0.8 + 0.5 * n);
	ALPHA = a;
	ROUGHNESS = 0.08;
	EMISSION = col * 0.08;
}
"""

# Gas burner flames: a ring of little blue tongues licking up, orange at the tips.
const BURNER := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
instance uniform float heat = 1.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	float y = 1.0 - UV.y;   // 0 at the burner, 1 at the top of the ring
	float tongue = abs(fract(UV.x * 18.0) - 0.5) * 2.0;
	float tall = 0.45 + 0.55 * n2(vec2(UV.x * 18.0, TIME * 7.0));
	float body = smoothstep(1.0, 0.4, tongue + y / tall) * step(y, tall);
	vec3 c = mix(vec3(0.15, 0.35, 1.0), vec3(1.0, 0.55, 0.15), smoothstep(0.35, 0.9, y / tall));
	ALBEDO = c * body * 3.2 * heat;
}
"""

# The inside of a bite: a hollow half-ball, only the half inside the food is drawn.
const BITE := """
shader_type spatial;
render_mode cull_disabled;
instance uniform vec3 out_dir = vec3(0.0, 1.0, 0.0);
instance uniform vec4 flesh : source_color = vec4(0.8, 0.5, 0.4, 1.0);
varying vec3 lp;
float h(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
void vertex() { lp = VERTEX; }
void fragment() {
	if (dot(lp, out_dir) > 0.0) discard;
	float grain = h(floor(lp * 90.0));
	ALBEDO = flesh.rgb * (0.85 + 0.25 * grain);
	ROUGHNESS = 0.7;
}
"""

const PAPER := """
shader_type spatial;
render_mode cull_disabled;
instance uniform float sway = 0.0;
void vertex() {
	// the loose end droops and curls toward the floor, and stirs a little
	float along = UV.x;
	VERTEX.y -= along * along * 0.28;
	VERTEX.z += along * along * 0.06 + sin(TIME * 2.5 + along * 5.0) * 0.012 * along + sway * 0.0;
}
void fragment() {
	float perf = smoothstep(0.004, 0.0, abs(fract(UV.y * 2.2) - 0.5) - 0.0) * step(0.5, fract(UV.x * 30.0));
	float quilt = 0.5 + 0.5 * sin(UV.x * 90.0) * sin(UV.y * 90.0);
	ALBEDO = vec3(0.96, 0.95, 0.92) * (0.92 + 0.08 * quilt) * (1.0 - perf * 0.25);
	ROUGHNESS = 0.95;
}
"""

const SPARK := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
float h(float x) { return fract(sin(x * 91.7) * 43758.5453); }
void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float t = floor(TIME * 24.0);
	float ang = atan(q.y, q.x);
	float rays = pow(abs(sin(ang * 4.0 + h(t) * 6.0)), 18.0) * (0.6 + 0.4 * h(t + 1.0));
	float r = length(q);
	float c = smoothstep(0.35, 0.0, r) + rays * smoothstep(1.0, 0.2, r);
	ALBEDO = vec3(1.0, 0.75, 0.3) * c * 2.5;
}
"""

static var _mats := {}


static func shader_mat(code_name: String) -> ShaderMaterial:
	if not _mats.has(code_name):
		var sh := Shader.new()
		sh.code = {"flame": FLAME, "glow": GLOW, "picture": PICTURE, "scribble": SCRIBBLE, "blood": SMEAR, "dirt": SMEAR,
				"slime": PUDDLE, "beer": PUDDLE, "stream": STREAM, "burner": BURNER, "bite": BITE, "paper": PAPER,
				"spark": SPARK}[code_name]
		var m := ShaderMaterial.new()
		m.shader = sh
		match code_name:
			"dirt":
				m.set_shader_parameter("col_a", Color(0.36, 0.25, 0.1))
				m.set_shader_parameter("col_b", Color(0.55, 0.42, 0.15))
				m.set_shader_parameter("scale", 14.0)
				m.set_shader_parameter("cover", 0.5)
				m.set_shader_parameter("gloss", 0.5)
			"slime":
				m.set_shader_parameter("col", Color(0.2, 0.42, 0.05))
				m.set_shader_parameter("col2", Color(0.45, 0.7, 0.15))
				m.set_shader_parameter("opacity", 0.6)
		_mats[code_name] = m
	return _mats[code_name]


static func flame(size: float, seed_v: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.21) * size
	q.center_offset = Vector3(0.0, 0.1 * size, 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = shader_mat("flame")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("seed", seed_v)
	return mi


static func quad(size: Vector2, mat_name: String) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = shader_mat(mat_name)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# A flat puddle lying on the ground.
static func puddle(radius: float, mat_name: String) -> MeshInstance3D:
	var p := PlaneMesh.new()
	p.size = Vector2(radius, radius) * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = p
	mi.material_override = shader_mat(mat_name)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func stream(length: float, radius: float) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius * 1.3
	c.height = length
	c.radial_segments = 8
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = shader_mat("stream")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func burner(radius: float) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius * 0.8
	c.bottom_radius = radius
	c.height = 0.2
	c.radial_segments = 24
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.position.y = 0.1
	mi.material_override = shader_mat("burner")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func bite_cap(radius: float, out_dir: Vector3, flesh: Color) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 12
	s.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = shader_mat("bite")
	mi.set_instance_shader_parameter("out_dir", out_dir)
	mi.set_instance_shader_parameter("flesh", flesh)
	return mi


static func spark() -> MeshInstance3D:
	var mi := quad(Vector2(0.16, 0.16), "spark")
	return mi
