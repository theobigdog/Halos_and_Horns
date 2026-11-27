# Game rules (Ted, Nov 26: "a standard settings, and then custom settings, for things like gravity, stamina
# refresh rate, damage, range of effects, number of hellfire pools, and even whether those powerups can
# spawn... Each power-up should be toggleable"). Picked in the lobby by the host (or from the main menu for
# practice): Standard is the game as tuned; Custom is whatever's set in the Game rules panel (saved).
# Online, the host's rules are sent to everyone at the start of each round (s_rules), so all the games
# agree; anything from the network goes through clean() first.
#
# Nov 27 (Ted: "it will need multiple tabs... General... Demons only... Angels... every Skill as well as each
# Power-Up"): every rule lives in RULES, tagged with its tab and section, and main.gd builds the tabs from it.
# To add a rule: add a line here, then use GameRules.f("key") where the number is used (a multiplier rule is
# 1.0 as standard, so standard play never changes). Every standard value is the game as tuned; the ranges are
# first guesses.
extends RefCounted

const POWERUP_KINDS := ["sense", "quick_throw", "quick_skills", "quick_run", "fast_hatred", "fire_burst", "heal", "vanish"]

const TABS := [["general", "General"], ["demons", "Demons"], ["angels", "Angels"], ["skills", "Skills"], ["powerups", "Power-ups"]]

# How a number shows: "x" a multiplier (x1 = standard), "s" seconds, "m" metres, "n" a plain count.
# key -> [tab, section, label, min, max, step, standard, unit, help]
# A "choice" rule's min/max/step are unused: its standard is an index into CHOICES[key].
const RULES := {
	# ---------------- General ----------------
	"gravity": ["general", "World", "Gravity", 0.4, 2.0, 0.1, 1.0, "x", "How hard everyone falls (x1 = standard). Lower: floaty, high jumps."],
	"weather": ["general", "World", "Weather", 0, 0, 0, 0, "choice", "Use each map's own weather, or force one for every map."],
	"time": ["general", "World", "Time of day", 0, 0, 0, 0, "choice", "Use each map's own time of day, or force one."],
	"cycle": ["general", "World", "Day / night cycle", 0, 0, 0, 0, "choice", "Use each map's own setting, or force the cycle off or to a length."],
	"blast": ["general", "Everyone", "Blast range", 0.5, 2.5, 0.25, 1.0, "x", "How far Hellfire splashes, Fire Burst and explosions reach."],
	"knock": ["general", "Everyone", "Prop shoves", 0.25, 3.0, 0.25, 1.0, "x", "How far bumping into props and blasts send them sliding."],
	# ---------------- Demons ----------------
	"demon_health": ["demons", "Body", "Starting health", 0.5, 3.0, 0.1, 1.0, "x", "How much a demon can take before it's caught (x2: twice the hits)."],
	"demon_size": ["demons", "Body", "Size", 0.6, 1.6, 0.05, 1.0, "x", "How big a demon is out of disguise (x1: 60% of an angel). Disguises keep the prop's size."],
	"demon_speed": ["demons", "Movement", "Speed", 0.5, 1.8, 0.05, 1.0, "x", "How fast demons move, as themselves and as props."],
	"demon_jump": ["demons", "Movement", "Jump height", 0.5, 2.0, 0.1, 1.0, "x", "How high demons jump."],
	"demon_sprint": ["demons", "Movement", "Running stamina refill", 0.25, 4.0, 0.25, 1.0, "x", "How fast a demon's running stamina comes back."],
	"hatred_regen": ["demons", "Hatred", "Hatred refill", 0.25, 4.0, 0.25, 1.0, "x", "How fast Hatred comes back (it pays for flying and skills)."],
	"fly_drain": ["demons", "Flying", "Hatred used flying", 0.25, 3.0, 0.25, 1.0, "x", "How fast flying burns Hatred (x0.5: twice as long in the air)."],
	"fly_lift": ["demons", "Flying", "Lift-off strength", 0.5, 2.0, 0.1, 1.0, "x", "How hard flying pushes up against gravity (higher: quicker lift-off, gravity matters less)."],
	"fly_rise": ["demons", "Flying", "Top climbing speed", 0.5, 2.0, 0.1, 1.0, "x", "How fast a demon can climb while flying."],
	"demon_pitch": ["demons", "Voice", "Voice pitch", 0.6, 1.6, 0.05, 1.0, "x", "Demons' taunts, higher or deeper (x0.7: a big deep voice)."],
	"still_taunt": ["demons", "Voice", "Forced taunt after sitting still", 10.0, 120.0, 5.0, 30.0, "s", "A demon that doesn't move for this long during the hunt taunts anyway, and again every time this passes."],
	# ---------------- Angels ----------------
	"damage": ["angels", "Blessings", "Blessing damage", 0.25, 3.0, 0.25, 1.0, "x", "How much every angel hit on a demon does (blessings, skills, melee)."],
	"throw_cost": ["angels", "Blessings", "Stamina per throw", 0.25, 3.0, 0.25, 1.0, "x", "How much blessing stamina each throw uses (x1: 10 throws from full)."],
	"throw_regen": ["angels", "Blessings", "Throwing stamina refill", 0.25, 4.0, 0.25, 1.0, "x", "How fast blessing stamina comes back."],
	"throw_speed": ["angels", "Blessings", "Blessing speed", 0.4, 2.0, 0.1, 1.0, "x", "How fast thrown blessings fly."],
	"throw_drop": ["angels", "Blessings", "Blessing drop", 0.0, 4.0, 0.25, 1.0, "x", "How much thrown blessings arc down (0: dead straight, higher: a lob)."],
	"angel_speed": ["angels", "Movement", "Speed", 0.5, 1.8, 0.05, 1.0, "x", "How fast angels move."],
	"angel_jump": ["angels", "Movement", "Jump height", 0.5, 2.0, 0.1, 1.0, "x", "How high angels jump (Leap of Faith jumps too)."],
	"angel_sprint": ["angels", "Movement", "Running stamina refill", 0.25, 4.0, 0.25, 1.0, "x", "How fast an angel's running stamina comes back."],
	"angel_size": ["angels", "Body", "Size", 0.7, 1.4, 0.05, 1.0, "x", "How big angels are."],
	"angel_pitch": ["angels", "Voice", "Voice pitch", 0.6, 1.6, 0.05, 1.0, "x", "Angels' taunts, higher or deeper."],
	# ---------------- Skills (angels) ----------------
	"cd_dash": ["skills", "Flying Dash", "Cooldown", 0.25, 3.0, 0.25, 1.0, "x", "Time before it can be used again."],
	"dash_speed": ["skills", "Flying Dash", "Dash speed", 0.5, 2.0, 0.1, 1.0, "x", "How fast (and so how far) the dash goes."],
	"cd_cherub": ["skills", "Alarm Cherub", "Cooldown", 0.25, 3.0, 0.25, 1.0, "x", "Time before it can be used again."],
	"cherub_radius": ["skills", "Alarm Cherub", "Detection range", 0.5, 2.5, 0.1, 1.0, "x", "How close a demon has to be to set it off (x1: 6 m)."],
	"cherub_time": ["skills", "Alarm Cherub", "Lasts", 0.5, 3.0, 0.25, 1.0, "x", "How long it stays (x1: 9 s)."],
	"cd_vacuum": ["skills", "Vacuum Orb", "Cooldown", 0.25, 3.0, 0.25, 1.0, "x", "Time before it can be used again."],
	"vacuum_radius": ["skills", "Vacuum Orb", "Reach", 0.5, 2.0, 0.1, 1.0, "x", "How far the vortex sucks from (x1: 5.5 m, shrinking to 2 m)."],
	"vacuum_drain": ["skills", "Vacuum Orb", "Hatred drained", 0.0, 3.0, 0.25, 1.0, "x", "How much Hatred it drains from a caught demon."],
	"vacuum_lock": ["skills", "Vacuum Orb", "Skill lock afterwards", 0.0, 3.0, 0.25, 1.0, "x", "How long a vacuumed demon can't use skills or fly after it lets go (x1: 2 s)."],
	"cd_leap": ["skills", "Leap of Faith", "Stomp cooldown", 0.25, 3.0, 0.25, 1.0, "x", "Time before Cloud Stomp can be used again."],
	"leap_jump": ["skills", "Leap of Faith", "Jump height", 0.5, 1.6, 0.05, 1.0, "x", "How high Leap of Faith jumps go."],
	"stomp_damage": ["skills", "Leap of Faith", "Cloud Stomp damage", 0.0, 3.0, 0.25, 1.0, "x", "How much Cloud Stomp hurts."],
	"stomp_radius": ["skills", "Leap of Faith", "Cloud Stomp reach", 0.5, 2.0, 0.1, 1.0, "x", "How far from where you land Cloud Stomp hurts (x1: 6 m)."],
	"cd_scripture": ["skills", "Holy Scripture", "Cooldown", 0.25, 3.0, 0.25, 1.0, "x", "Time before it can be used again."],
	"scripture_damage": ["skills", "Holy Scripture", "Direct hit damage", 0.0, 3.0, 0.25, 1.0, "x", "How much the book hurts a demon it hits."],
	"smite_damage": ["skills", "Holy Scripture", "Smite damage", 0.0, 3.0, 0.25, 1.0, "x", "How much the blast where it lands hurts."],
	"smite_radius": ["skills", "Holy Scripture", "Smite reach", 0.5, 2.5, 0.1, 1.0, "x", "How far the blast reaches (x1: 4 m)."],
	"cd_word": ["skills", "Holy Word", "Cooldown", 0.25, 3.0, 0.25, 1.0, "x", "Time before it can be used again."],
	"word_range": ["skills", "Holy Word", "Range", 0.5, 2.0, 0.1, 1.0, "x", "How far the shout reaches (x1: 45 m)."],
	"word_stun": ["skills", "Holy Word", "Stun", 0.0, 4.0, 0.25, 1.0, "x", "How long a struck demon is frozen (x1: half a second)."],
	"cd_kick": ["skills", "Holy Kick", "Cooldown", 0.25, 3.0, 0.25, 1.0, "x", "Time before it can be used again."],
	"kick_damage": ["skills", "Holy Kick", "Damage", 0.0, 3.0, 0.25, 1.0, "x", "How much a kick hurts."],
	"kick_push": ["skills", "Holy Kick", "Push", 0.25, 3.0, 0.25, 1.0, "x", "How far a kicked demon flies (x1: 7 m)."],
	"melee_damage": ["skills", "Melee (F)", "Damage", 0.0, 3.0, 0.25, 1.0, "x", "How much an angel's melee swing hurts (x1: three hits catch a demon)."],
	# ---------------- Skills (demons) ----------------
	"cd_minion": ["skills", "Minion", "Cooldown", 0.25, 3.0, 0.25, 1.0, "x", "Time before it can be used again."],
	"hc_minion": ["skills", "Minion", "Hatred cost", 0.0, 3.0, 0.25, 1.0, "x", "How much Hatred it costs."],
	"minion_time": ["skills", "Minion", "Lasts", 0.25, 3.0, 0.25, 1.0, "x", "How long a minion lasts (x1: 20 s)."],
	"minion_health": ["skills", "Minion", "Health", 0.25, 4.0, 0.25, 1.0, "x", "How many hits a minion takes."],
	"cd_teleport": ["skills", "Teleport", "Cooldown", 0.25, 3.0, 0.25, 1.0, "x", "Time before it can be used again."],
	"hc_teleport": ["skills", "Teleport", "Hatred cost", 0.0, 3.0, 0.25, 1.0, "x", "How much Hatred it costs."],
	"teleport_range": ["skills", "Teleport", "Range", 0.5, 2.0, 0.1, 1.0, "x", "How far you can blink (x1: 20 m)."],
	"cd_fire": ["skills", "Hellfire", "Cooldown", 0.25, 3.0, 0.25, 1.0, "x", "Time before it can be used again."],
	"hc_fire": ["skills", "Hellfire", "Hatred cost", 0.0, 3.0, 0.25, 1.0, "x", "How much Hatred it costs."],
	"fire_radius": ["skills", "Hellfire", "Pool size", 0.5, 2.0, 0.1, 1.0, "x", "How wide each pool of fire is (x1: 1.8 m from the middle to the edge)."],
	"fire_time": ["skills", "Hellfire", "Fire lasts", 0.25, 3.0, 0.25, 1.0, "x", "How long the fire burns (x1: 6 s)."],
	"splashes": ["skills", "Hellfire", "Extra splash pools", 0, 8, 1, 3, "n", "How many extra pools of fire a Hellfire splashes into around where it lands."],
	"splash_size": ["skills", "Hellfire", "Splash pool size", 0.25, 2.0, 0.25, 1.0, "x", "How big each extra splash pool is, next to the main one."],
	"splash_time": ["skills", "Hellfire", "Splash pools last", 0.25, 2.0, 0.25, 1.0, "x", "How long the extra splash pools burn, next to the main one."],
	"fire_linger": ["skills", "Hellfire", "Burning after stepping out", 0.0, 3.0, 0.25, 1.0, "x", "How long an angel keeps burning after leaving the fire (x1: 2 s)."],
	"fire_slow": ["skills", "Hellfire", "Slowing", 0.0, 2.0, 0.25, 1.0, "x", "How much fire slows angels (x1: down to 60% speed; 0: not at all)."],
	"cd_fear": ["skills", "Fear", "Cooldown", 0.25, 3.0, 0.25, 1.0, "x", "Time before it can be used again."],
	"hc_fear": ["skills", "Fear", "Hatred cost", 0.0, 3.0, 0.25, 1.0, "x", "How much Hatred it costs."],
	"fear_radius": ["skills", "Fear", "Reach", 0.5, 2.5, 0.1, 1.0, "x", "How close angels have to be to panic (x1: 10 m)."],
	"fear_time": ["skills", "Fear", "Panic lasts", 0.25, 3.0, 0.25, 1.0, "x", "How long angels panic (x1: 2 s)."],
	"cd_possess": ["skills", "Possess", "Cooldown", 0.25, 3.0, 0.25, 1.0, "x", "Time before it can be used again."],
	# ---------------- Power-ups ----------------
	"pu_rate": ["powerups", "All power-ups", "How often they turn up", 0.25, 3.0, 0.25, 1.0, "x", "x2: twice as often (demon drops and the angels' help both)."],
	"pu_life": ["powerups", "All power-ups", "Lying around for", 0.25, 3.0, 0.25, 1.0, "x", "How long a pickup nobody takes stays before it disappears (x1: 40 s)."],
	"pu_time": ["powerups", "All power-ups", "Effects last", 0.25, 3.0, 0.25, 1.0, "x", "How long every timed power-up lasts once picked up."],
	"surge_strength": ["powerups", "Hatred Surge", "Strength", 0.25, 2.0, 0.25, 1.0, "x", "How much faster Hatred refills during a surge (x1: 8 times as fast)."],
	"heal_amount": ["powerups", "Unholy Mending", "Healing", 0.25, 2.0, 0.25, 1.0, "x", "How much it heals (x1: half your starting health)."],
	"vanish_time": ["powerups", "Invisibility", "Lasts", 0.25, 3.0, 0.25, 1.0, "x", "How long a demon stays invisible (x1: 6.5 s)."],
	"burst_radius": ["powerups", "Fire Burst", "Reach", 0.5, 2.0, 0.1, 1.0, "x", "How far the burst reaches (x1: 7 m; Blast range counts too)."],
}

const CHOICES := {
	"weather": [["", "Each map's own"], ["clear", "Clear"], ["sunny_cloudy", "Sunny, some clouds"], ["cloudy", "Cloudy"],
			["fog", "Fog"], ["rain", "Rain"], ["snow", "Snow"]],
	"time": [["", "Each map's own"], ["day", "Day"], ["dusk", "Dusk"], ["night", "Night"]],
	"cycle": [[-1, "Each map's own"], [0, "Off"], [5, "5 minutes"], [10, "10 minutes"], [20, "20 minutes"], [30, "30 minutes"]],
}

static var current := standard()   # the rules in play right now


static func standard() -> Dictionary:
	var d := {}
	for k in RULES:
		d[k] = RULES[k][6]
	var p := {}
	for k in POWERUP_KINDS:
		p[k] = true
	d["powerups"] = p
	return d


static func is_standard(d: Dictionary) -> bool:
	return clean(d) == standard()


static func is_choice(key: String) -> bool:
	return RULES[key][7] == "choice"


static func is_count(key: String) -> bool:
	return RULES[key][7] == "n"


# Anything from a file or the network: every value in range, every power-up a true/false, nothing extra.
static func clean(d) -> Dictionary:
	var out := standard()
	if typeof(d) != TYPE_DICTIONARY:
		return out
	for k in RULES:
		var v = d.get(k)
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			continue
		var r: Array = RULES[k]
		if is_choice(k):
			out[k] = clampi(int(v), 0, CHOICES[k].size() - 1)
		elif is_count(k):
			out[k] = clampi(roundi(float(v)), int(r[3]), int(r[4]))
		else:
			out[k] = snappedf(clampf(float(v), r[3], r[4]), 0.01)
	var p = d.get("powerups")
	if typeof(p) == TYPE_DICTIONARY:
		for k in POWERUP_KINDS:
			if typeof(p.get(k)) == TYPE_BOOL:
				out["powerups"][k] = p[k]
	return out


static func f(key: String) -> float:
	return float(current.get(key, RULES[key][6]))


static func splashes() -> int:
	return int(current.get("splashes", 3))


# A choice rule's value ("" / -1: use the map's own).
static func choice(key: String):
	var i := clampi(int(current.get(key, 0)), 0, CHOICES[key].size() - 1)
	return CHOICES[key][i][0]


static func weather_for(map_weather: String) -> String:
	var w: String = choice("weather")
	return map_weather if w == "" else w


static func time_for(map_time: String) -> String:
	var t: String = choice("time")
	return map_time if t == "" else t


static func cycle_for(map_cycle: int) -> int:
	var c: int = choice("cycle")
	return map_cycle if c < 0 else c


# A skill's cooldown / Hatred cost multiplier, if it has one ("cd_<id>", "hc_<id>"; Cloud Stomp is Leap's).
static func cooldown_mult(skill: String) -> float:
	var key := "cd_" + ("leap" if skill == "stomp" else skill)
	return f(key) if RULES.has(key) else 1.0


static func hatred_mult(skill: String) -> float:
	var key := "hc_" + skill
	return f(key) if RULES.has(key) else 1.0


static func powerup_on(kind: String) -> bool:
	return bool(current.get("powerups", {}).get(kind, true))


# Kinds from this list that are switched on (repeats kept, so weighting survives).
static func allowed(kinds: Array) -> Array:
	return kinds.filter(func(k): return powerup_on(k))


static func show_value(key: String, v) -> String:
	var unit: String = RULES[key][7]
	match unit:
		"choice":
			return str(CHOICES[key][clampi(int(v), 0, CHOICES[key].size() - 1)][1])
		"x":
			return "x%s" % str(v)
		"s":
			return "%s s" % str(v)
		"m":
			return "%s m" % str(v)
	return str(v)


# A short line for the lobby: what's different from standard.
static func summary(d: Dictionary) -> String:
	d = clean(d)
	if d == standard():
		return "Standard rules"
	var parts := []
	for k in RULES:
		if d[k] != RULES[k][6]:
			var sec: String = RULES[k][1]
			var name: String = RULES[k][2] if RULES[k][0] in ["general"] or sec in ["Body", "Movement", "Hatred", "Flying", "Voice", "Blessings", "All power-ups"] else "%s %s" % [sec, RULES[k][2].to_lower()]
			if RULES[k][0] == "demons":
				name = "Demon " + name.to_lower()
			elif RULES[k][0] == "angels" and k != "damage":
				name = "Angel " + name.to_lower()
			parts.append("%s %s" % [name, show_value(k, d[k])])
	var off := POWERUP_KINDS.filter(func(k): return not d["powerups"][k])
	if not off.is_empty():
		parts.append("%d power-up(s) off" % off.size())
	if parts.size() > 6:
		return "Custom: %s and %d more" % [", ".join(parts.slice(0, 5)), parts.size() - 5]
	return "Custom: " + ", ".join(parts)
