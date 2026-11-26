# Game rules (Ted, Nov 26: "a standard settings, and then custom settings, for things like gravity, stamina
# refresh rate, damage, range of effects, number of hellfire pools, and even whether those powerups can
# spawn... Each power-up should be toggleable"). Picked in the lobby by the host (or from the main menu for
# practice): Standard is the game as tuned; Custom is whatever's set in the Game rules panel (saved).
# Online, the host's rules are sent to everyone at the start of each round (s_rules), so all the games
# agree; anything from the network goes through clean() first.
extends RefCounted

const POWERUP_KINDS := ["sense", "quick_throw", "quick_skills", "quick_run", "fast_hatred", "fire_burst", "heal", "vanish"]

# key -> [label, min, max, step, standard, help]
const NUMBERS := {
	"gravity": ["Gravity", 0.4, 2.0, 0.1, 1.0, "How hard everyone falls (1 = standard). Lower: floaty, high jumps."],
	"stamina": ["Stamina refill", 0.25, 4.0, 0.25, 1.0, "How fast blessing and sprint stamina refill (1 = standard)."],
	"damage": ["Damage", 0.25, 3.0, 0.25, 1.0, "How much every hit on a demon does (1 = standard)."],
	"blast": ["Blast range", 0.5, 2.5, 0.25, 1.0, "How far Hellfire splashes, Fire Burst and explosions reach (1 = standard)."],
	"splashes": ["Hellfire splash pools", 0, 8, 1, 3, "How many extra pools of fire a Hellfire splashes into around where it lands."],
}

static var current := standard()   # the rules in play right now


static func standard() -> Dictionary:
	var d := {}
	for k in NUMBERS:
		d[k] = NUMBERS[k][4]
	var p := {}
	for k in POWERUP_KINDS:
		p[k] = true
	d["powerups"] = p
	return d


static func is_standard(d: Dictionary) -> bool:
	return clean(d) == standard()


# Anything from a file or the network: every value in range, every power-up a true/false, nothing extra.
static func clean(d) -> Dictionary:
	var out := standard()
	if typeof(d) != TYPE_DICTIONARY:
		return out
	for k in NUMBERS:
		var v = d.get(k)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			var r: Array = NUMBERS[k]
			var x := clampf(float(v), r[1], r[2])
			out[k] = int(round(x)) if k == "splashes" else snappedf(x, 0.01)
	var p = d.get("powerups")
	if typeof(p) == TYPE_DICTIONARY:
		for k in POWERUP_KINDS:
			if typeof(p.get(k)) == TYPE_BOOL:
				out["powerups"][k] = p[k]
	return out


static func f(key: String) -> float:
	return float(current.get(key, NUMBERS[key][4]))


static func splashes() -> int:
	return int(current.get("splashes", 3))


static func powerup_on(kind: String) -> bool:
	return bool(current.get("powerups", {}).get(kind, true))


# Kinds from this list that are switched on (repeats kept, so weighting survives).
static func allowed(kinds: Array) -> Array:
	return kinds.filter(func(k): return powerup_on(k))


# A short line for the lobby: what's different from standard.
static func summary(d: Dictionary) -> String:
	d = clean(d)
	if d == standard():
		return "Standard rules"
	var parts := []
	for k in NUMBERS:
		if d[k] != NUMBERS[k][4]:
			parts.append("%s %s" % [NUMBERS[k][0], str(d[k]) if k == "splashes" else "x%s" % str(d[k])])
	var off := POWERUP_KINDS.filter(func(k): return not d["powerups"][k])
	if not off.is_empty():
		parts.append("%d power-up(s) off" % off.size())
	return "Custom: " + ", ".join(parts)
