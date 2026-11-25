# Small one-shot visual effects, shared by everything (hits, possessions, skills, blasts...).
#
# The look (Nov 24, to match fire.gd's Hellfire): no particle systems at all. Each effect is ONE mesh
# whose pieces a shader moves and shades: soft billowing lumps that swell, lift and get eaten away by
# noise (puff, smoke, dust, fireballs), streaking sparks with hot heads, chunky faceted bits that tumble,
# fall and bounce, twinkling four-point stars, flat or camera-facing shockwave rings, a glowing burn-away
# for dissolving props. A tween runs the effect's "age" from 0 to 1, then it frees itself.
# Meshes and materials are made once and shared by every effect; per-effect differences (colour, size,
# seed...) are instance uniforms, so lots of hits at once stay cheap. Variety comes from hashes of the
# position (never the shared random numbers: particle systems use those and shift seeded test maps).
# Heavenly things lean gold/white, hellish ones red/orange/black with smouldering edges.
extends RefCounted

static var quality := 1    # graphics quality (graphics.gd): 0 low, 1 medium, 2 high
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
float fbm2(vec3 p) {
	return vnoise(p) * 0.65 + vnoise(p * 2.07 + vec3(7.1, 1.3, 4.7)) * 0.35;
}
// heat -> soot, crimson, red, orange, yellow-white (HDR, so the hot part blooms)
vec3 fire_ramp(float k) {
	vec3 c = mix(vec3(0.04, 0.012, 0.02), vec3(0.32, 0.03, 0.07), smoothstep(-0.25, 0.2, k));
	c = mix(c, vec3(1.6, 0.16, 0.03), smoothstep(0.15, 0.42, k));
	c = mix(c, vec3(2.6, 0.75, 0.08), smoothstep(0.42, 0.72, k));
	c = mix(c, vec3(3.2, 2.2, 0.8), smoothstep(0.78, 1.05, k));
	return c;
}
// the heavenly version: pale cloud, gold, white-hot
vec3 holy_ramp(float k) {
	vec3 c = mix(vec3(0.75, 0.68, 0.55), vec3(1.5, 1.1, 0.45), smoothstep(-0.1, 0.35, k));
	c = mix(c, vec3(2.6, 2.1, 1.1), smoothstep(0.4, 0.75, k));
	c = mix(c, vec3(3.2, 3.1, 2.7), smoothstep(0.8, 1.05, k));
	return c;
}
"""

# Billows: a mesh of sphere lumps (each vertex knows its lump's centre (COLOR.rgb), a random number
# (COLOR.a), its radius and start delay (UV2)). The lumps swell from small, move out (spread) and up
# (rise), wobble with noise, and the fragment shader eats them away from the rim inwards as they age.
const BILLOW_HEAD := """
instance uniform float age = 0.0;
instance uniform float seed = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float spread = 0.5;
instance uniform float rise = 0.3;
instance uniform float glow = 0.0;     // billow: emission; fireball: starting heat
instance uniform float ember = 0.0;    // billow: smouldering edges; fireball: 1 = heavenly (gold)
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
varying vec3 vn;
varying float va;
varying float vs;
varying float valive;
NOISE
void vertex() {
	vec3 c = COLOR.rgb * 2.0 - 1.0;
	float s = COLOR.a;
	float delay = UV2.y;
	float a = clamp((age - delay) / max(1.0 - delay, 0.01), 0.0, 1.0);
	float e = 1.0 - (1.0 - a) * (1.0 - a) * (1.0 - a);
	vec3 n = normalize(VERTEX - c);
	float d = vnoise(n * 2.2 + vec3(s * 9.0 + seed, -TIME * 1.3 - s * 4.0, s * 3.0));
	float grow = mix(0.25, 1.0, e) * (0.78 + 0.44 * d);
	vec3 center = c * (1.0 + spread * e) + vec3(0.0, rise * e * (0.6 + 0.8 * s), 0.0);
	VERTEX = center + n * UV2.x * grow;
	NORMAL = n;
	vn = n;
	va = a;
	vs = s;
	valive = step(delay, age) * step(age, 0.999);
}
float soft_edge(vec2 suv, float dtex, vec3 vtx, mat4 ip, float dist) {
	vec4 v = ip * vec4(suv * 2.0 - 1.0, dtex, 1.0);
	return clamp((vtx.z - v.z / v.w) / dist, 0.0, 1.0);
}
"""

# Lit soft smoke / dust / magic puffs: shaded by the real lights (soft wrap), darker underneath,
# optional glow (bright colours) and smouldering ember edges (dark hellish smoke).
const BILLOW_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert_wrap, specular_disabled;
HEAD
void fragment() {
	float fres = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float n = fbm2(vn * 2.4 + vec3(vs * 7.0 + seed, -TIME * 0.9, vs * 2.0));
	float body = n * 0.55 + pow(fres, 0.8) * 0.75;
	float thr = 0.15 + va * 1.05;
	float m = smoothstep(thr, thr + 0.35, body);
	float band = smoothstep(thr - 0.02, thr + 0.03, body) * (1.0 - smoothstep(thr + 0.03, thr + 0.12, body));
	float shade = mix(0.55, 1.0, vn.y * 0.5 + 0.5) * (0.85 + 0.3 * n);
	ALBEDO = tint.rgb * shade;
	ROUGHNESS = 1.0;
	EMISSION = tint.rgb * glow * (1.0 - va) * (0.5 + 0.7 * fres)
			+ vec3(2.2, 0.45, 0.06) * ember * band * (1.0 - va) * (1.0 - va);
	ALPHA = clamp(tint.a * m * smoothstep(0.0, 0.45, fres) * valive
			* soft_edge(SCREEN_UV, texture(depth_tex, SCREEN_UV).r, VERTEX, INV_PROJECTION_MATRIX, 0.3), 0.0, 1.0);
}
"""

# Fireballs: the same billowing lumps, burning: white-hot where you look into them, crimson at the rim,
# cooling to soot as they age and lift (gold and white for heavenly ones).
const FIREBALL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, fog_disabled;
HEAD
void fragment() {
	float fres = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float n = fbm2(vn * 2.6 + vec3(vs * 7.0 + seed, -TIME * 2.2, vs * 2.0));
	float k = fres * 0.8 + (n - 0.5) * 0.9 + glow - va * 1.3;
	ALBEDO = mix(fire_ramp(k), holy_ramp(k), ember) * tint.rgb;
	ALPHA = clamp(smoothstep(-0.4, -0.05, k) * smoothstep(0.0, 0.35, fres + (n - 0.5) * 0.4) * tint.a * valive
			* soft_edge(SCREEN_UV, texture(depth_tex, SCREEN_UV).r, VERTEX, INV_PROJECTION_MATRIX, 0.25), 0.0, 1.0);
}
"""

# Sparks: camera-facing streaks flying out of a point (each quad's random numbers in its COLOR),
# slowed by drag, pulled by gravity, stretched along their motion, white-hot heads cooling to the tint.
const SPARK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled;
instance uniform float age = 0.0;
instance uniform float seed = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float speed = 5.0;
instance uniform float life = 0.6;
instance uniform float grav = 2.0;
instance uniform float size = 0.05;
instance uniform float up = 0.25;
varying vec2 uvv;
varying float vf;
varying float vh;
void vertex() {
	vec4 r = fract(COLOR + vec4(seed * 0.618, seed * 0.382, seed * 0.271, seed * 0.159));
	float z = r.x * 2.0 - 1.0;
	float ph = r.y * 6.2831853;
	float rz = sqrt(1.0 - z * z);
	vec3 d = normalize(vec3(rz * cos(ph), z, rz * sin(ph)) + vec3(0.0, up, 0.0));
	float sp = speed * mix(0.35, 1.0, r.z);
	float lt = clamp(age / mix(0.45, 1.0, r.w), 0.0, 1.0);
	float t = age * life;
	float k = 3.0;
	float ek = exp(-k * t);
	vec3 p = d * sp * (1.0 - ek) / k - vec3(0.0, grav, 0.0) * (t / k - (1.0 - ek) / (k * k));
	vec3 v = d * sp * ek - vec3(0.0, grav, 0.0) * (1.0 - ek) / k;
	vec3 pv = (MODELVIEW_MATRIX * vec4(p, 1.0)).xyz;
	vec3 vv = (MODELVIEW_MATRIX * vec4(v, 0.0)).xyz;
	vec2 ax = length(vv.xy) > 0.001 ? normalize(vv.xy) : vec2(0.0, 1.0);
	vec2 px = vec2(-ax.y, ax.x);
	float fade = 1.0 - lt;
	float w = size * mix(0.35, 1.0, fade);
	float len = w * 1.5 + length(vv.xy) * 0.04;
	VERTEX = pv + vec3(ax * (UV.y - 1.0) * len + px * (UV.x - 0.5) * w * 2.0, 0.0);
	uvv = UV;
	vf = fade * step(lt, 0.999);
	vh = r.w;
}
void fragment() {
	float x = abs(uvv.x - 0.5) * 2.0;
	float a = (1.0 - x * x) * smoothstep(0.0, 0.7, uvv.y);
	float flick = 0.75 + 0.25 * sin(TIME * 40.0 + vh * 60.0);
	vec3 c = mix(tint.rgb * 2.2, vec3(3.0, 2.8, 2.4), vf * vf * 0.7 * uvv.y);
	ALBEDO = c * a * vf * flick * tint.a;
}
"""

# Stars: twinkling four-point stars (with a fainter diagonal cross), spread along `span` with a bit
# of jitter, popping in one after another (ripple). One big one is a hot flash.
const STAR_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled;
instance uniform float age = 0.0;
instance uniform float seed = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform vec3 span = vec3(0.0);
instance uniform float size = 0.2;
instance uniform float ripple = 0.0;
instance uniform float jitter = 0.0;
instance uniform float power = 1.0;
instance uniform float lift = 0.0;
varying vec2 uvv;
varying float vk;
varying float vtw;
void vertex() {
	vec4 r = COLOR;
	float local = clamp((age - r.r * ripple) / max(1.0 - ripple, 0.01), 0.0, 1.0);
	float env = smoothstep(0.0, 0.12, local) * (1.0 - smoothstep(0.25, 1.0, local));
	vec3 c = span * r.r + (fract(r.gba + seed * vec3(0.31, 0.17, 0.23)) - 0.5) * 2.0 * jitter + vec3(0.0, lift * local, 0.0);
	vec4 v = MODELVIEW_MATRIX * vec4(c, 1.0);
	float sz = size * mix(0.65, 1.2, r.b) * mix(0.4, 1.0, env);
	float ang = TIME * (r.g - 0.5) * 2.0 + r.a * 3.0;
	vec2 q = (UV - 0.5) * sz;
	q = vec2(q.x * cos(ang) - q.y * sin(ang), q.x * sin(ang) + q.y * cos(ang));
	VERTEX = v.xyz + vec3(q, 0.0);
	uvv = UV;
	vk = env * step(0.0001, local) * step(local, 0.999);
	vtw = 0.55 + 0.45 * sin(TIME * 21.0 + r.g * 40.0 + seed * 7.0);
}
void fragment() {
	vec2 p = (uvv - 0.5) * 2.0;
	float ax = abs(p.x);
	float ay = abs(p.y);
	float rays = exp(-ax * 16.0) * max(1.0 - ay, 0.0) + exp(-ay * 16.0) * max(1.0 - ax, 0.0);
	vec2 pd = vec2(p.x + p.y, p.x - p.y) * 0.7071;
	float rays2 = (exp(-abs(pd.x) * 20.0) * max(1.0 - abs(pd.y) * 1.6, 0.0) + exp(-abs(pd.y) * 20.0) * max(1.0 - abs(pd.x) * 1.6, 0.0)) * 0.4;
	float core = exp(-dot(p, p) * 22.0);
	float halo = exp(-dot(p, p) * 5.0) * 0.25;
	float i = (rays + rays2 + core * 1.6 + halo) * vk * vtw * power;
	ALBEDO = mix(tint.rgb, vec3(1.0), core * 0.7) * i * 1.8;
}
"""

# A shockwave: a bright ring rushing outwards, lying flat on the ground (face 0) or facing the camera.
const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled;
instance uniform float age = 0.0;
instance uniform float seed = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float radius = 3.0;
instance uniform float face = 0.0;
instance uniform float width = 0.1;
instance uniform float power = 1.5;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
varying vec2 rp;
NOISE
void vertex() {
	vec2 q = UV * 2.0 - 1.0;
	float R = radius * 1.1;
	vec3 o = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	if (face > 0.5) {
		VERTEX = o + vec3(q * R, 0.0);
	} else {
		VERTEX = (MODELVIEW_MATRIX * vec4(q.x * R, 0.0, q.y * R, 1.0)).xyz;
	}
	rp = q * 1.1;
}
void fragment() {
	float r = length(rp);
	float e = 1.0 - pow(1.0 - age, 3.0);
	float rr = mix(0.06, 1.0, e);
	float w = width * (0.6 + age);
	float ring = exp(-pow((r - rr) / w, 2.0));
	float ang = atan(rp.y, rp.x);
	float br = 0.65 + 0.7 * vnoise(vec3(cos(ang) * 3.0, sin(ang) * 3.0, seed * 5.0 + age * 3.0));
	float fade = 1.0 - age;
	vec3 c = mix(tint.rgb, vec3(1.0), ring * fade * 0.5);
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	float soft = clamp((VERTEX.z - v.z / v.w) / 0.25, 0.0, 1.0);
	ALBEDO = c * ring * br * fade * fade * power * tint.a * mix(soft, 1.0, 1.0 - face);
}
"""

# Debris: faceted chunks (each vertex relative to its chunk's centre, the chunk's random numbers in
# COLOR) thrown in a cone around `dir_n`, falling, tumbling, bouncing once off `floor_y`, shrinking away.
# `hot` makes them glowing embers that cool down (blasts).
const DEBRIS_SHADER := """
shader_type spatial;
render_mode cull_back;
instance uniform float age = 0.0;
instance uniform float seed = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform vec3 dir_n = vec3(0.0, 1.0, 0.0);
instance uniform float speed = 3.0;
instance uniform float cone = 0.9;
instance uniform float life = 1.0;
instance uniform float floor_y = -100.0;
instance uniform float size = 0.08;
instance uniform float hot = 0.0;
varying float vr;
varying float vheat;
vec3 rot(vec3 v, vec3 ax, float a) {
	return v * cos(a) + cross(ax, v) * sin(a) + ax * dot(ax, v) * (1.0 - cos(a));
}
void vertex() {
	vec4 r = fract(COLOR + vec4(seed * 0.618, seed * 0.382, seed * 0.271, seed * 0.159));
	vec3 upv = normalize(dir_n);
	vec3 side = abs(upv.y) < 0.9 ? normalize(cross(upv, vec3(0.0, 1.0, 0.0))) : normalize(cross(upv, vec3(1.0, 0.0, 0.0)));
	vec3 side2 = cross(upv, side);
	float th = cone * sqrt(r.x);
	float ph = r.y * 6.2831853;
	vec3 d = upv * cos(th) + (side * cos(ph) + side2 * sin(ph)) * sin(th);
	vec3 v0 = d * speed * mix(0.45, 1.0, r.z);
	float G = 14.0;
	float t = age * life;
	float th_hit = (v0.y + sqrt(max(v0.y * v0.y - 2.0 * G * floor_y, 0.0))) / G;
	vec3 p;
	float spin_t;
	if (t < th_hit) {
		p = v0 * t + vec3(0.0, -0.5 * G * t * t, 0.0);
		spin_t = t;
	} else {
		vec3 ph_ = v0 * th_hit + vec3(0.0, -0.5 * G * th_hit * th_hit, 0.0);
		vec3 v1 = vec3(v0.x * 0.45, -(v0.y - G * th_hit) * 0.3, v0.z * 0.45);
		float u = t - th_hit;
		p = ph_ + v1 * u + vec3(0.0, -0.5 * G * u * u, 0.0);
		p.y = max(p.y, floor_y);
		spin_t = th_hit + u * 0.3;
	}
	vec3 ax = normalize(vec3(r.w - 0.5, r.x - 0.5, r.z - 0.5) + vec3(0.001));
	float ang = spin_t * mix(6.0, 16.0, r.w) + r.y * 6.0;
	float sc = size * (1.0 - smoothstep(0.7, 1.0, age));
	VERTEX = rot(VERTEX * sc, ax, ang) + p;
	NORMAL = rot(NORMAL, ax, ang);
	vr = r.w;
	vheat = hot * clamp(1.0 - age * 1.5 + r.z * 0.3, 0.0, 1.0);
}
void fragment() {
	float facet = 0.55 + 0.45 * fract(vr * 13.7 + dot(NORMAL, vec3(3.1, 5.7, 1.3)));
	ALBEDO = tint.rgb * (0.7 + 0.5 * vr);
	ROUGHNESS = 0.85;
	EMISSION = mix(vec3(1.4, 0.18, 0.02), vec3(2.4, 0.8, 0.1), vheat * vheat * vheat) * vheat * facet * 1.3;
}
"""

# Dissolving props: burnt away top-first in noisy patches, with a glowing edge eating through them.
const DISSOLVE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool use_tex = true;
uniform bool use_vc = false;
uniform bool scissor = false;
uniform float rough = 0.8;
instance uniform float burn = 0.0;
instance uniform vec4 edge : source_color = vec4(1.0, 0.42, 0.1, 1.0);
instance uniform vec3 origin = vec3(0.0);
instance uniform float height = 1.0;
varying vec3 wp;
NOISE
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec4 c = tint;
	if (use_tex) {
		c *= texture(tex, UV);
	}
	if (use_vc) {
		c *= COLOR;
	}
	if (scissor && c.a < 0.5) {
		discard;
	}
	float h = clamp((wp.y - origin.y) / max(height, 0.01), 0.0, 1.0);
	float n = fbm2(wp * 3.2);
	float v = n * 0.6 + (1.0 - h) * 0.4;
	float thr = burn * 1.12 - 0.08;
	if (v < thr) {
		discard;
	}
	float g = 1.0 - smoothstep(0.0, 0.07, v - thr);
	float charred = 1.0 - smoothstep(0.0, 0.2, v - thr);
	ALBEDO = c.rgb * mix(1.0, 0.12, charred * step(0.001, burn)) * (FRONT_FACING ? 1.0 : 0.25);
	ROUGHNESS = rough;
	EMISSION = edge.rgb * g * 4.0 * step(0.001, burn);
}
"""

# An angel's swing: a crescent slash sweeping round in front of them, its outer edge white-hot gold.
const SWING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
instance uniform float age = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0);
varying vec2 uvv;
NOISE
void vertex() {
	uvv = UV;
}
void fragment() {
	float head = 1.3 * (1.0 - pow(1.0 - age, 2.0));
	float behind = head - uvv.x;
	float tail = behind >= 0.0 ? exp(-behind * 3.0) : exp(behind * 30.0);
	float radial = smoothstep(0.0, 0.5, uvv.y) * (0.2 + 0.8 * pow(uvv.y, 3.0)) * (1.0 - smoothstep(0.9, 1.0, uvv.y));
	float streak = vnoise(vec3(uvv.x * 6.0 - age * 4.0, uvv.y * 14.0, 0.0));
	float ends = smoothstep(0.0, 0.08, uvv.x) * smoothstep(1.0, 0.85, uvv.x);
	float i = tail * radial * (0.6 + 0.8 * streak) * (1.0 - age * age) * ends;
	ALBEDO = mix(tint.rgb, vec3(1.0), pow(uvv.y, 5.0)) * i * 2.6;
}
"""

# A flying demon's flames: blobs of fire left behind it...
const FLAME_BLOB_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, fog_disabled;
instance uniform float age = 0.0;
instance uniform float seed = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0, 0.45, 0.1, 1.0);
varying vec3 vn;
NOISE
void vertex() {
	vn = VERTEX;
	VERTEX *= 0.8 + 0.4 * vnoise(VERTEX * 2.5 + vec3(seed * 3.0, -TIME * 4.0, 0.0));
}
void fragment() {
	float fres = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float n = vnoise(vn * 3.0 + vec3(seed * 3.0, -TIME * 5.0, 0.0));
	float k = fres * 0.95 + (n - 0.5) * 0.8 + 0.05 - age * 1.0;
	vec3 c = mix(tint.rgb * 0.12, tint.rgb * 2.0, smoothstep(0.0, 0.45, k));
	c = mix(c, mix(tint.rgb, vec3(1.0), 0.45) * 2.8, smoothstep(0.7, 1.0, k));
	ALBEDO = c;
	ALPHA = smoothstep(0.0, 0.3, k);
}
"""

# ...and a jet of flame licking down from under it (a quad turned to the camera around the vertical).
const FLAME_JET_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
instance uniform vec4 tint : source_color = vec4(1.0, 0.45, 0.1, 1.0);
instance uniform float power = 1.0;
varying vec2 uvv;
NOISE
void vertex() {
	vec3 right = transpose(mat3(MODEL_MATRIX)) * INV_VIEW_MATRIX[0].xyz;
	right.y = 0.0;
	right = normalize(right + vec3(1e-4, 0.0, 0.0));
	float y = UV.y;
	float sway = sin(TIME * 9.0 + y * 4.0) * 0.06 * y;
	VERTEX = right * ((UV.x - 0.5) * 0.55 + sway) + vec3(0.0, 0.12 - y * 1.0 * (0.6 + 0.4 * power), 0.0);
	uvv = UV;
}
void fragment() {
	float y = uvv.y;
	float f = vnoise(vec3(uvv.x * 4.0, y * 3.0 - TIME * 6.0, 0.0));
	float prof = (1.0 - y * 0.85);
	float d = abs(uvv.x - 0.5 + (f - 0.5) * 0.3 * y) * 2.0 / max(prof, 0.05);
	float k = 1.0 - d + (vnoise(vec3(uvv.x * 9.0, y * 6.0 - TIME * 9.0, 3.0)) - 0.5) * 0.5 - y * 0.6;
	vec3 c = mix(tint.rgb * 0.2, tint.rgb * 1.9, smoothstep(0.0, 0.4, k));
	c = mix(c, mix(tint.rgb, vec3(1.0), 0.6) * 3.0, smoothstep(0.5, 0.9, k));
	ALBEDO = c;
	ALPHA = smoothstep(0.0, 0.35, k) * power * smoothstep(0.0, 0.12, y);
}
"""

const SHADERS := {
	"billow": [BILLOW_SHADER, 0], "fireball": [FIREBALL_SHADER, 1], "spark": [SPARK_SHADER, 2],
	"star": [STAR_SHADER, 3], "flash": [STAR_SHADER, 3], "ring": [RING_SHADER, 1], "debris": [DEBRIS_SHADER, 0],
	"swing": [SWING_SHADER, 2], "flame_blob": [FLAME_BLOB_SHADER, 1], "flame_jet": [FLAME_JET_SHADER, 1],
}


static func _mat(key: String) -> ShaderMaterial:
	if not _cache.has(key):
		var sh := Shader.new()
		sh.code = (SHADERS[key][0] as String).replace("HEAD", BILLOW_HEAD).replace("NOISE", NOISE)
		if key == "flash":    # a flash shines over everything, it isn't cut off by the ground
			sh.code = sh.code.replace("fog_disabled;", "fog_disabled, depth_test_disabled;")
		var m := ShaderMaterial.new()
		m.shader = sh
		m.render_priority = SHADERS[key][1]
		_cache[key] = m
	return _cache[key]


# --- shared meshes ---------------------------------------------------------------------------

static func _q() -> int:
	return clampi(quality, 0, 2)


# How many pieces to actually make at this graphics quality.
static func _count(n: int) -> int:
	return maxi(1, int(n * [0.4, 1.0, 1.6][_q()]))


# A number 0..1 from a position: the same on every screen, no shared random numbers.
static func hash01(v: Vector3) -> float:
	return fposmod(sin(v.dot(Vector3(12.9898, 78.233, 37.719))) * 43758.5453, 1.0)


static func _q8(x: float) -> float:
	return roundf(clampf(x, 0.0, 1.0) * 255.0) / 255.0


# A mesh of sphere lumps for the billow shaders. lumps: [centre (inside -1..1), radius, delay, random].
static func _lumps_mesh(key: String, lumps: Array) -> ArrayMesh:
	key += str(_q())
	if _cache.has(key):
		return _cache[key]
	var seg: int = [8, 10, 14][_q()]
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = seg
	sm.rings = seg / 2
	var src := sm.get_mesh_arrays()
	var sv: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var si: PackedInt32Array = src[Mesh.ARRAY_INDEX]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for l in lumps:
		var c: Vector3 = l[0]
		var cc := Color(_q8(c.x * 0.5 + 0.5), _q8(c.y * 0.5 + 0.5), _q8(c.z * 0.5 + 0.5), _q8(l[3]))
		var cq := Vector3(cc.r, cc.g, cc.b) * 2.0 - Vector3.ONE
		var base := verts.size()
		for v in sv:
			var n := v.normalized()
			verts.append(cq + n * float(l[1]))
			normals.append(n)
			colors.append(cc)
			uv2.append(Vector2(l[1], l[2]))
		for i in si:
			idx.append(base + i)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3(-3.5, -2.0, -3.5), Vector3(7.0, 7.0, 7.0))
	_cache[key] = m
	return m


# A cluster of lumps: a big one in the middle, smaller ones round it (puffs, fireballs), or a
# taller stack whose upper lumps start later (smoke).
static func _cluster(kind: String, n: int) -> ArrayMesh:
	var key := "%s%d" % [kind, n]
	if _cache.has(key + str(_q())):
		return _cache[key + str(_q())]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var lumps := []
	var tall := kind == "smoke"
	var fire := kind == "fire"
	lumps.append([Vector3(0, 0.05 if tall else 0.0, 0), 0.5 if tall else 0.55, 0.0, 0.5])
	for i in n - 1:
		var a := TAU * (i + rng.randf() * 0.6) / (n - 1)
		var k := float(i) / maxf(n - 2, 1)
		var y := rng.randf_range(-0.2, 0.3)
		var rad := rng.randf_range(0.28, 0.45)
		var delay := rng.randf_range(0.0, 0.08)
		if tall:
			y = lerpf(-0.1, 0.75, k) + rng.randf_range(-0.1, 0.1)
			rad = rng.randf_range(0.3, 0.5)
			delay = k * 0.3 + rng.randf() * 0.05
		if fire:
			rad = rng.randf_range(0.22, 0.38)
		lumps.append([Vector3(cos(a) * rad, y, sin(a) * rad), rng.randf_range(0.42, 0.56) if fire else rng.randf_range(0.36, 0.5), delay, rng.randf()])
	return _lumps_mesh(key, lumps)


# Lumps round a ring of radius 1 on the ground (dust kicked up round a point).
static func _ring_lumps(n: int) -> ArrayMesh:
	var key := "dust%d" % n
	if _cache.has(key + str(_q())):
		return _cache[key + str(_q())]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + n
	var lumps := []
	for i in n:
		var a := TAU * (i + rng.randf_range(-0.3, 0.3)) / n
		var r := rng.randf_range(0.75, 0.95)
		lumps.append([Vector3(cos(a) * r, rng.randf_range(0.0, 0.1), sin(a) * r), rng.randf_range(0.26, 0.36), rng.randf() * 0.12, rng.randf()])
	return _lumps_mesh(key, lumps)


# n quads the shaders place themselves; each quad's random numbers in its colour (r = i / (n - 1)
# when `ordered`, for things laid out along a line).
static func _quads(key: String, n: int, ordered := false) -> ArrayMesh:
	key = "%s%d" % [key, n]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var first := float(i) / maxf(n - 1, 1) if ordered else (i + rng.randf()) / n
		var c := Color(first, rng.randf(), rng.randf(), rng.randf())
		for uv in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
			st.set_color(c)
			st.set_uv(uv)
			st.add_vertex(Vector3(uv.x - 0.5, uv.y - 0.5, 0.0))
	var m := st.commit()
	m.custom_aabb = AABB(Vector3(-16, -16, -16), Vector3(32, 32, 32))
	_cache[key] = m
	return m


# n chunky faceted bits (jittered boxes, flat-shaded), all built at the origin: the shader throws them.
static func _chunks(n: int) -> ArrayMesh:
	var key := "chunks%d" % n
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4400 + n
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for i in n:
		var c := Color((i + rng.randf()) / n, rng.randf(), rng.randf(), rng.randf())
		var s := Vector3(rng.randf_range(0.7, 1.4), rng.randf_range(0.5, 1.1), rng.randf_range(0.7, 1.3))
		var corners := []
		for k in 8:
			var p := Vector3(-0.5 if k & 1 == 0 else 0.5, -0.5 if k & 2 == 0 else 0.5, -0.5 if k & 4 == 0 else 0.5)
			corners.append(p * s + Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15)))
		for q in quads:
			for tri in [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]:
				var a: Vector3 = corners[tri[0]]
				var b: Vector3 = corners[tri[1]]
				var d: Vector3 = corners[tri[2]]
				var nrm := (b - a).cross(d - a).normalized()
				var mid := (a + b + d) / 3.0
				if nrm.dot(mid) < 0.0:
					nrm = -nrm
				else:          # Godot's front faces wind clockwise
					var t := b
					b = d
					d = t
				for v in [a, b, d]:
					st.set_color(c)
					st.set_normal(nrm)
					st.add_vertex(v)
	var m := st.commit()
	m.custom_aabb = AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))
	_cache[key] = m
	return m


# --- spawning --------------------------------------------------------------------------------

# One effect mesh at `pos`, its age run from 0 to 1 over `life` seconds (after `delay`), then freed.
static func _spawn(parent: Node, mesh: Mesh, mat: Material, pos: Vector3, life: float, params := {}, delay := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("seed", hash01(pos) * 10.0)
	for k in params:
		mi.set_instance_shader_parameter(k, params[k])
	parent.add_child(mi)
	mi.global_position = pos
	var tw := mi.create_tween()
	if delay > 0.0:
		mi.visible = false
		tw.tween_interval(delay)
		tw.tween_callback(mi.show)
	tw.tween_method(func(v: float) -> void: mi.set_instance_shader_parameter("age", v), 0.0, 1.0, life)
	tw.tween_callback(mi.queue_free)
	return mi


# How much a colour should glow (bright warm colours glow, dark ones don't) and smoulder (dark reds).
static func _glow_of(c: Color) -> float:
	var hi := maxf(c.r, maxf(c.g, c.b))
	var lo := minf(c.r, minf(c.g, c.b))
	return clampf((hi - 0.55) * 1.6, 0.0, 1.0) * (0.35 + 0.65 * (hi - lo))


static func _ember_of(c: Color) -> float:
	var hi := maxf(c.r, maxf(c.g, c.b))
	if c.r < c.b * 1.2 or c.r < c.g:
		return 0.0
	return 1.0 - smoothstep(0.2, 0.5, hi)


# --- the effects -----------------------------------------------------------------------------

# A quick soft billow that swells and thins away, plus a few motes: hits, possessions, skills.
static func puff(parent: Node, pos: Vector3, color: Color, size: float = 1.0) -> void:
	var mi := _spawn(parent, _cluster("puff", [4, 6, 8][_q()]), _mat("billow"), pos, 0.55 + 0.05 * size, {
		"tint": color, "spread": 0.35, "rise": 0.3, "glow": _glow_of(color), "ember": _ember_of(color)})
	mi.scale = Vector3.ONE * 0.55 * size
	mi.rotation.y = hash01(pos + Vector3(3, 1, 7)) * TAU
	if _glow_of(color) > 0.2:
		flash(parent, pos, color.lightened(0.4), 0.9 * size, 0.2, 0.8)
	var mote := color
	if maxf(color.r, maxf(color.g, color.b)) < 0.4:     # dark smoke: embers (hellish) or pale sparks
		mote = Color(1.0, 0.4, 0.1) if _ember_of(color) > 0.2 else color.lightened(0.55)
	burst(parent, pos, mote, int(4 + 4 * size), 1.4 + size * 1.2, 0.5)


# A flying demon's flames (Ted, Nov 18): hellfire licking down from under it and trailing behind as it goes.
# Continuous: switch it on and off with `emitting`. Add it as a child of the flier, at its feet.
# (It's a CPUParticles3D only so the players' code keeps working; it never draws or emits anything itself:
# it stays hidden, so it never touches the shared random numbers. The flames are a FlyFlames node it
# hands to its parent, which watches `emitting` and animates hand-made flame blobs and a flame jet.)
static func fly_flames() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 1
	p.emitting = false
	p.visible = false
	if "use_fixed_seed" in p:
		p.set("use_fixed_seed", true)
	var fx := FlyFlames.new()
	fx.src = p
	fx.jet_mat = _mat("flame_jet")
	fx.blob_mat = _mat("flame_blob")
	fx.q = _q()
	p.set_meta("fx", fx)
	p.add_child(fx)
	return p


# Flying flames in another colour (a demon's wardrobe choice).
static func tint_flames(p: CPUParticles3D, c: Color) -> void:
	if p and p.has_meta("fx"):
		var fx = p.get_meta("fx")
		if is_instance_valid(fx):
			fx.set_tint(c)


class FlyFlames extends Node3D:
	var src: CPUParticles3D
	var jet_mat: Material
	var blob_mat: Material
	var q := 1
	var tint := Color(1.0, 0.45, 0.1)
	var _blobs := []          # [MeshInstance3D, age, velocity]
	var _jet: MeshInstance3D
	var _next := 0
	var _timer := 0.0
	var _power := 0.0
	var _rng := RandomNumberGenerator.new()
	const LIFE := 0.45

	func _ready() -> void:
		_rng.seed = 7171
		_adopt.call_deferred()

	# Move out from under the hidden particles node, next to it.
	func _adopt() -> void:
		if not is_instance_valid(src):
			queue_free()
			return
		if src.get_parent() == null:
			_adopt.call_deferred()
			return
		reparent(src.get_parent(), false)
		_jet = MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.custom_aabb = AABB(Vector3(-1, -1.6, -1), Vector3(2, 2, 2))
		_jet.mesh = qm
		_jet.material_override = jet_mat
		_jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_jet)
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = [8, 10, 12][q]
		sm.rings = sm.radial_segments / 2
		for i in [6, 10, 14][q]:
			var b := MeshInstance3D.new()
			b.mesh = sm
			b.material_override = blob_mat
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			b.top_level = true
			b.visible = false
			b.set_instance_shader_parameter("seed", i * 1.37)
			add_child(b)
			_blobs.append([b, 1.0, Vector3.ZERO])
		set_tint(tint)

	func set_tint(c: Color) -> void:
		tint = c
		if _jet:
			_jet.set_instance_shader_parameter("tint", c)
		for b in _blobs:
			(b[0] as MeshInstance3D).set_instance_shader_parameter("tint", c)

	func _process(delta: float) -> void:
		if not is_instance_valid(src):
			queue_free()
			return
		if not _jet:
			return
		position = src.position
		var on := src.emitting
		_power = move_toward(_power, 1.0 if on else 0.0, delta * 6.0)
		_jet.visible = _power > 0.01
		_jet.set_instance_shader_parameter("power", _power)
		if on:
			_timer -= delta
			if _timer <= 0.0:
				_timer = LIFE / _blobs.size()
				var b: Array = _blobs[_next]
				_next = (_next + 1) % _blobs.size()
				var mi: MeshInstance3D = b[0]
				mi.global_position = global_position + Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf_range(-0.1, 0.05), _rng.randf_range(-0.2, 0.2))
				b[1] = 0.0
				b[2] = Vector3(_rng.randf_range(-0.6, 0.6), -_rng.randf_range(2.0, 3.5), _rng.randf_range(-0.6, 0.6))
				mi.visible = true
		for b in _blobs:
			var mi: MeshInstance3D = b[0]
			if not mi.visible:
				continue
			b[1] += delta / LIFE
			if b[1] >= 1.0:
				mi.visible = false
				continue
			var v: Vector3 = b[2]
			v *= exp(-4.0 * delta)
			v.y += 3.0 * delta
			b[2] = v
			mi.global_position += v * delta
			mi.scale = Vector3.ONE * lerpf(0.15, 0.04, b[1])
			mi.set_instance_shader_parameter("age", b[1])


# Glowing sparks bursting out from a point, streaking, slowing and drifting a little up as they fade.
# (gravity: how hard they fall, metres/s²; negative floats them up)
static func burst(parent: Node, pos: Vector3, color: Color, amount: int, speed: float, lifetime: float, gravity := -0.6, size := 0.05) -> void:
	var n := clampi(_count(amount), 2, 96)
	n = (n + 3) / 4 * 4
	_spawn(parent, _quads("sparks", n), _mat("spark"), pos, lifetime, {
		"tint": Color(color.r, color.g, color.b, 1.0), "speed": speed, "life": lifetime, "grav": gravity, "size": size})


# Chips and splinters knocked off a surface: chunky little bits that fly out, tumble, fall and shrink away.
# (floor: where the ground is, metres below `pos`, if they should bounce on it; hot: glowing embers)
static func debris(parent: Node, pos: Vector3, normal: Vector3, color: Color, amount := 8, floor_drop := 100.0,
		hot := 0.0, speed := 4.0, size := 0.07, life := 0.9) -> void:
	var n := clampi(_count(amount), 2, 48)
	_spawn(parent, _chunks(n), _mat("debris"), pos + normal * 0.05, life, {
		"tint": color, "dir_n": normal if normal.length() > 0.01 else Vector3.UP, "speed": speed,
		"cone": 0.95, "life": life, "floor_y": -floor_drop, "size": size, "hot": hot})


# A ring of dust kicked up round a point on the ground (landings, stomps, props falling over).
static func dust(parent: Node, pos: Vector3, radius: float, amount := 14) -> void:
	var n := clampi(int(_count(amount) * 0.7), 8, 22)
	var mi := _spawn(parent, _ring_lumps(n), _mat("billow"), pos + Vector3.UP * 0.05, 1.0, {
		"tint": Color(0.66, 0.6, 0.5, 0.55), "spread": 0.55, "rise": 0.35, "glow": 0.0, "ember": 0.0})
	var r := maxf(radius, 0.35)
	mi.scale = Vector3(r, minf(r, 1.2), r)
	mi.rotation.y = hash01(pos) * TAU


# A soft billowing smoke puff (demon things: possessing, teleporting, minions), rising as it thins.
static func smoke(parent: Node, pos: Vector3, color: Color, size := 1.0, life := 1.4, delay := 0.0) -> void:
	var mi := _spawn(parent, _cluster("smoke", [5, 8, 11][_q()]), _mat("billow"), pos, life, {
		"tint": Color(color.r, color.g, color.b, 0.8), "spread": 0.55, "rise": 1.1, "glow": _glow_of(color) * 0.5,
		"ember": _ember_of(color) * 0.7}, delay)
	mi.scale = Vector3.ONE * 0.6 * size
	mi.rotation.y = hash01(pos + Vector3(5, 2, 1)) * TAU


# A ball of fire swelling up, rolling upwards and burning out into soot (heavenly: gold and white light).
static func fireball(parent: Node, pos: Vector3, size := 1.0, life := 0.9, heat := 0.45, holy := false, delay := 0.0) -> MeshInstance3D:
	var mi := _spawn(parent, _cluster("fire", [5, 7, 9][_q()]), _mat("fireball"), pos, life, {
		"tint": Color.WHITE, "spread": 0.4, "rise": 0.7, "glow": heat, "ember": 1.0 if holy else 0.0}, delay)
	mi.scale = Vector3.ONE * size
	mi.rotation.y = hash01(pos + Vector3(1, 9, 4)) * TAU
	return mi


# A hot flash: a bright four-point star that pops and fades.
static func flash(parent: Node, pos: Vector3, color: Color, size := 1.5, life := 0.2, power := 1.5) -> void:
	_spawn(parent, _quads("flash", 1, true), _mat("flash"), pos, life, {"tint": color, "size": size, "power": power})


# A shockwave ring rushing out: flat on the ground, or (facing) a ring facing the camera.
static func shockwave(parent: Node, pos: Vector3, color: Color, radius := 3.0, life := 0.4, facing := false, power := 1.5) -> void:
	_spawn(parent, _quads("ring", 1, true), _mat("ring"), pos, life, {
		"tint": color, "radius": radius, "face": 1.0 if facing else 0.0, "width": 0.08 if facing else 0.06, "power": power})


# A scorched patch on the ground, fading over `life` seconds (a Decal, so it follows any surface).
static func scorch(parent: Node, pos: Vector3, radius := 2.0, life := 2.5) -> void:
	var d := Decal.new()
	d.texture_albedo = _scorch_tex()
	d.size = Vector3(radius * 2.0, 1.2, radius * 2.0)
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.normal_fade = 0.4
	d.cull_mask = 1
	parent.add_child(d)
	d.global_position = pos
	d.rotation.y = hash01(pos) * TAU
	var tw := d.create_tween()
	tw.tween_interval(life * 0.4)
	tw.tween_property(d, "modulate:a", 0.0, life * 0.6)
	tw.tween_callback(d.queue_free)


static func _scorch_tex() -> ImageTexture:
	if _cache.has("scorch"):
		return _cache["scorch"]
	var n := 96
	var rng := RandomNumberGenerator.new()
	rng.seed = 3131
	var lat := PackedFloat32Array()
	for i in 12 * 12:
		lat.append(rng.randf())
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var px := (x + 0.5) / n * 2.0 - 1.0
			var py := (y + 0.5) / n * 2.0 - 1.0
			var ang := atan2(py, px)
			var r := sqrt(px * px + py * py)
			var gx := (x / 8.0)
			var gy := (y / 8.0)
			var xi := int(gx)
			var yi := int(gy)
			var fx := gx - xi
			var fy := gy - yi
			var nz := lerpf(lerpf(lat[(yi % 12) * 12 + xi % 12], lat[(yi % 12) * 12 + (xi + 1) % 12], fx),
					lerpf(lat[((yi + 1) % 12) * 12 + xi % 12], lat[((yi + 1) % 12) * 12 + (xi + 1) % 12], fx), fy)
			var rays := 0.5 + 0.5 * sin(ang * 9.0 + nz * 4.0)
			var edge := 0.62 + 0.25 * nz + 0.12 * rays
			var a := (1.0 - smoothstep(edge * 0.55, edge, r)) * (0.6 + 0.4 * nz)
			var dark := lerpf(0.03, 0.1, nz)
			img.set_pixel(x, y, Color(dark * 1.1, dark * 0.7, dark * 0.65, clampf(a, 0.0, 0.92)))
	img.generate_mipmaps()
	_cache["scorch"] = ImageTexture.create_from_image(img)
	return _cache["scorch"]


# The faint trail between two props when a demon possesses from one to the next.
# Deliberately subtle: a ripple of tiny, dim violet stars twinkling from one to the other.
static func sparkle_trail(parent: Node, from: Vector3, to: Vector3) -> void:
	var n: int = [6, 10, 14][_q()]
	_spawn(parent, _quads("trail", n, true), _mat("star"), from + Vector3.UP * 0.5, 0.85, {
		"tint": Color(0.75, 0.5, 1.0), "span": to - from, "size": 0.16, "ripple": 0.45, "jitter": 0.1,
		"power": 0.55, "lift": 0.15})


# Slowly burn a node away (an abandoned possessed prop), then remove it: it disintegrates top-first in
# noisy patches behind a glowing edge (hellish orange unless told otherwise).
static func dissolve(node: Node3D, seconds: float, glow := Color(1.0, 0.42, 0.1)) -> void:
	var geos := []
	var others := []
	_fade_prepare(node, geos, others)
	var box := AABB()
	var first := true
	for g in geos:
		var b: AABB = (g as MeshInstance3D).global_transform * (g as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	for g in geos:
		g.set_instance_shader_parameter("origin", box.position)
		g.set_instance_shader_parameter("height", maxf(box.size.y, 0.2))
		g.set_instance_shader_parameter("edge", glow)
	var tw := node.create_tween()
	tw.tween_method(func(v: float) -> void: _burn(v, geos, others), 0.0, 1.0, seconds)
	tw.tween_callback(node.queue_free)


static func _burn(v: float, geos: Array, others: Array) -> void:
	for g in geos:
		if is_instance_valid(g):
			g.set_instance_shader_parameter("burn", v)
	for o in others:
		if is_instance_valid(o):
			o.visible = v < 0.4


static func _fade_prepare(node: Node, geos: Array, others: Array) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh and child.material_override is BaseMaterial3D:
			# (Its own material stays, see-through, with its alpha down: the burning copy is its next pass.)
			var mi: MeshInstance3D = child
			var base: BaseMaterial3D = mi.material_override.duplicate()
			base.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			base.albedo_color.a = 0.0
			base.next_pass = _dissolve_mat(mi.material_override)
			mi.material_override = base
			mi.material_overlay = null
			geos.append(mi)
		elif child is MeshInstance3D and child.mesh:
			var mi: MeshInstance3D = child
			for si in mi.mesh.get_surface_count():
				mi.set_surface_override_material(si, _dissolve_mat(mi.get_active_material(si)))
			mi.material_override = null
			mi.material_overlay = null
			geos.append(mi)
		elif child is GeometryInstance3D:
			others.append(child)
		_fade_prepare(child, geos, others)


static func _dissolve_mat(src: Material) -> ShaderMaterial:
	var key = src if src else "dissolve_none"
	if _cache.has(key):
		return _cache[key]
	if not _cache.has("dissolve_shader"):
		var sh := Shader.new()
		sh.code = DISSOLVE_SHADER.replace("NOISE", NOISE)
		_cache["dissolve_shader"] = sh
	var m := ShaderMaterial.new()
	m.shader = _cache["dissolve_shader"]
	var tex: Texture2D = null
	var tint := Color(0.7, 0.7, 0.7)
	if src is BaseMaterial3D:
		var b: BaseMaterial3D = src
		tex = b.albedo_texture
		tint = b.albedo_color
		m.set_shader_parameter("use_vc", b.vertex_color_use_as_albedo)
		m.set_shader_parameter("scissor", b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
		m.set_shader_parameter("rough", b.roughness)
	elif src is ShaderMaterial:
		var t = (src as ShaderMaterial).get_shader_parameter("tex")
		if t is Texture2D:
			tex = t
			tint = Color.WHITE
		var c = (src as ShaderMaterial).get_shader_parameter("tint")
		if c is Color:
			tint = c
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("use_tex", tex != null)
	if tex:
		m.set_shader_parameter("tex", tex)
	_cache[key] = m
	return m


# An angel's melee swing: a quick golden crescent slashing round in front of them.
static func swing(parent: Node, pos: Vector3, forward: Vector3) -> void:
	var f := Vector3(forward.x, 0.0, forward.z)
	if f.length() < 0.01:
		f = Vector3.FORWARD
	var mi := _spawn(parent, _arc_mesh(), _mat("swing"), pos, 0.22, {"tint": Color(1.0, 0.85, 0.45)})
	mi.basis = Basis.looking_at(f.normalized(), Vector3.UP) * Basis(Vector3.FORWARD, -0.3)
	mi.position.y += forward.y * 0.5


static func _arc_mesh() -> ArrayMesh:
	if _cache.has("arc"):
		return _cache["arc"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 20
	var a0 := -1.25
	var a1 := 1.25
	for i in seg:
		var u0 := float(i) / seg
		var u1 := float(i + 1) / seg
		var p := []
		for u in [u0, u1]:
			var a: float = lerpf(a1, a0, u)     # sweeps from the right to the left
			var d := Vector3(sin(a), 0.0, -cos(a))
			p.append([d * 0.6 + Vector3(0, 0.05, 0), d * 1.35, u])
		for v in [[p[0][0], 0.0, p[0][2]], [p[1][0], 0.0, p[1][2]], [p[1][1], 1.0, p[1][2]],
				[p[0][0], 0.0, p[0][2]], [p[1][1], 1.0, p[1][2]], [p[0][1], 1.0, p[0][2]]]:
			st.set_uv(Vector2(v[2], v[1]))
			st.add_vertex(v[0])
	var m := st.commit()
	_cache["arc"] = m
	return m
