# Every skill in the game, and loadouts (each player picks 2 per team).
# Keys (both teams): Q = skill 1, right click = skill 2. Angels also have F = melee.
# "Hold" skills (Fly) work while their key is held down.
# Numbers here are first guesses, meant to be tuned in playtests.
extends RefCounted

const SKILLS := {
	# ---- angels ----
	"dash": {"team": "angel", "label": "Flying Dash", "cooldown": 4.0,
		"desc": "Dash any way you like: where you're looking (up into the air too), or the way your movement keys point. You keep the speed afterwards - until you turn. Wide, slow turns cost a little; a quick 180 or a strafe kills it."},
	"cherub": {"team": "angel", "label": "Alarm Cherub", "cooldown": 10.0,
		"desc": "Throw a cherub that stays for 9 seconds. It hovers there tooting its little horn; if a demon comes close it blasts the horn and shows its detection bubble. Hit it with a blessing to send it flying off to check further away."},
	"vacuum": {"team": "angel", "label": "Vacuum Orb", "cooldown": 8.0,
		"desc": "Throw into a pile of props: a vortex that sucks for 5 seconds, dragging props in and yanking any hidden demon back to its middle again and again, draining Hatred. Caught demons can't use skills until 2 seconds after it ends."},
	"leap": {"team": "angel", "label": "Holy Leap", "cooldown": 8.0,
		"desc": "Having it picked makes all your jumps MUCH higher, and you steer hard in the air. Press its key while you're in the air to Cloud Stomp: slam straight down wherever you are and hurt every demon around where you land (most in the middle, more the higher you came from)."},
	"scripture": {"team": "angel", "label": "Holy Scripture", "cooldown": 5.0,
		"desc": "Hurl a heavy holy book that heat-seeks the nearest demon ahead of it (a Minion fools it too). Wherever it lands it SMITES: a pillar of holy light that hurts every demon within 4 m, knocks them back, locks their skills for a moment and scatters the props. Lob it into a suspicious pile! A direct hit hurts even more."},
	"word": {"team": "angel", "label": "Holy Word", "cooldown": 8.0,
		"desc": "Shout a holy word down your crosshair. Any demon it hits while flying (more than 2 m up) is struck out of the sky: it drops like a stone, can't fly again until it lands, and is stunned stiff for half a second."},
	"kick": {"team": "angel", "label": "Holy Kick", "cooldown": 4.0,
		"desc": "Boot a demon (or a demon-possessed prop) away from you, so it can't rush you up close."},
	# Not pickable: the second half of Holy Leap.
	"stomp": {"team": "angel", "label": "Cloud Stomp", "cooldown": 0.0, "part_of": "leap"},
	# ---- demons ----
	"fly": {"team": "demon", "label": "Fly", "cooldown": 0.0, "hold": true,
		"desc": "Hold the key to rise, spending Hatred (about 5-6 seconds from full). Let go and you fall. No fall damage."},
	"minion": {"team": "demon", "label": "Minion", "cooldown": 2.0, "hatred": 30.0,
		"desc": "Press to quietly make a decoy of yourself (or the prop you're disguised as) where your crosshair is. Hold the key to steer it: it walks to the ground under your crosshair. It moves like a real player and bumps into things; hits on it look and sound like hits on a demon, but it's flimsy and pops after a hit or two (or 20 seconds). One at a time."},
	"teleport": {"team": "demon", "label": "Teleport", "cooldown": 12.5, "hatred": 60.0,
		"desc": "Blink to where your crosshair points, up to 20 m away (further than that: as far as you can go that way). Very expensive."},
	"fire": {"team": "demon", "label": "Hellfire", "cooldown": 2.0, "hatred": 35.0,
		"desc": "Fling a fireball from your hands; where it lands, fire burns for 6 seconds and splashes out into a few more pools around it. Angels caught in it are slowed, stagger about, can barely see straight and their blessings burn away. Costs Hatred, and the fireball shows where it came from."},
	"fear": {"team": "demon", "label": "Fear", "cooldown": 7.5, "hatred": 55.0,
		"desc": "Let out a hellish shriek. Every angel within 10 m who can see you panics for 2 seconds: they run off in a blind scatter, away from you, and their aim shakes all over the place (they can still throw, swing and use skills, good luck hitting anything)."},
	"possess": {"team": "demon", "label": "Possess", "cooldown": 1.5,
		"desc": "Become a real prop instead of a copy (press its key while aiming at the prop). The one you leave behind slowly dissolves."},
}

const DEFAULTS := {"angel": ["dash", "cherub"], "demon": ["possess", "fly"]}
const SLOT_KEYS := ["Q", "Right click"]

# Tuning
const CHERUB_THROW_SPEED := 11.0 # thrown from the angel's hands: lands and skids ~10-14 m away
const CHERUB_THROW_UP := 3.0
const CHERUB_RADIUS := 6.0       # detection radius
const CHERUB_LIFETIME := 9.0
const CHERUB_KICK_SPEED := 16.0  # how fast a blessing sends it skidding
const CHERUB_KICK_UP := 3.5
const CHERUB_CREEP_SPEED := 0.4 # m/s it drifts toward a demon it has noticed (very slowly: ~3 m in its whole life)
const CHERUB_CREEP_STOP := 1.2  # ...and it stops this close, rather than bumping into them
const CHERUB_FRICTION := 9.0     # m/s lost per second while sliding on the ground (~14 m per kick)
const LEAP_AIR_ACCEL := 40.0      # steering while leaping (normal air steering is much weaker)
const SCRIPTURE_DAMAGE := 40       # a direct hit (a blessing does 25)...
const WORD_RANGE := 45.0           # Holy Word reaches this far down the crosshair... (first guesses, Nov 19)
const WORD_WIDTH := 1.6            # ...and catches anyone within this of the line (a shout, not a sniper shot)
const WORD_MIN_HEIGHT := 2.0       # only fliers this high off the ground get struck down
const WORD_STUN := 0.5             # seconds they're frozen stiff
const WORD_DROP_SPEED := 12.0      # they get slammed downward this fast
const SEEK_RANGE := 14.0           # Holy Scripture heat-seeks the nearest demon (or Minion!) this close to the book...
const SEEK_CONE := 1.2             # ...and within this many radians (~70 degrees) of where it's heading
const SMITE_RADIUS := 4.0          # ...and wherever it lands, a holy blast hurts every demon this close (first guesses, Nov 18)
const SMITE_DAMAGE := 30           # ...this much in the middle
const SMITE_MIN_DAMAGE := 10       # ...at least this much at the edge
const SMITE_LOCKOUT := 1.5         # ...and their skills (and flying) are locked this long
const SMITE_PUSH := 2.5            # m it shoves them outward
const SCRIPTURE_SPEED := 24.0
const SCRIPTURE_GRAVITY := 14.0
const KICK_RANGE := 2.8
const FEAR_RADIUS := 10.0
const FEAR_TIME := 2.0
const FEAR_SHAKE := 1.6           # how hard a panicking angel's aim shakes (radians/second)
const KICK_PUSH := 7.0            # how far a kicked demon flies
const KICK_DAMAGE := 20           # (melee is 34)
const STOMP_SPEED := 30.0
const STOMP_RADIUS := 6.0        # everything within this of where you land gets hurt...
const STOMP_DAMAGE := 25          # ...this much right in the middle, from an ordinary leap
const STOMP_MIN_DAMAGE := 5       # ...at least this much at the very edge
const STOMP_BASE_HEIGHT := 5.0    # an ordinary leap comes down from about this high
const STOMP_FULL_HEIGHT := 15.0   # from this high up (or more): double damage
const LEAPER_JUMP := 12.0         # every jump with Holy Leap picked (normal: 5.6; Ted, Nov 18: "MUCH higher")
const LEAPER_AIR_ACCEL := 40.0    # ...and steering in the air (normal: 12)
# Hatred for naughtiness (handed out by the host)
const NAUGHTY_FIRE_PER_SEC := 4.0   # per angel standing in your fire
const NAUGHTY_MINION_HIT := 8.0     # an angel wasted a hit on your minion
const NAUGHTY_TAUNT := 4.0          # taunting with an angel within 12 m (at most every 6 s)
const NAUGHTY_TAUNT_RANGE := 12.0
const VANISH_TIME := 6.5          # the Invisibility power-up
const TELEPORT_RANGE := 20.0
const MINION_LIFETIME := 20.0
const MINION_RANGE := 30.0        # how far away you can make one appear
const MINION_HEALTH := 0.4        # share of the copied form's health (a demon body: 2 blessings)
const FIRE_THROW_SPEED := 16.0   # flung from the demon's hands...
const FIRE_THROW_UP := 2.5
const FIRE_GRAVITY := 14.0        # ...in an arc: lands roughly 8-15 m away
const FIRE_LINGER := 2.0          # seconds you keep burning (and staggering) after stepping out
const FIRE_RADIUS := 1.8
const FIRE_LIFETIME := 6.0
const FIRE_SPLASH_MIN := 2.5      # Hellfire splashes into extra pools (how many: Settings) this far out...
const FIRE_SPLASH_MAX := 5.0
const FIRE_SPLASH_HOP := 0.5      # ...each blob takes this long to hop there
const FIRE_SLOW := 0.6            # angels in fire move at 60% speed
const FIRE_BLESSING_BURN := 45.0  # blessing stamina burned per second while standing in fire
const VACUUM_RADIUS := 8.0         # (first guess, Nov 18: was 6 and "does very little")
const VACUUM_TIME := 5.0           # the vortex keeps sucking this long (was a single tug at impact)
const VACUUM_PULSE := 0.8          # how often it yanks every demon in range back to its middle
const VACUUM_HATRED_DRAIN := 40.0  # the first time it catches a demon...
const VACUUM_PULSE_DRAIN := 10.0   # ...and every yank after that
const VACUUM_LOCKOUT := 2.0        # seconds a vacuumed demon can't use skills or fly, after the vortex lets go
const MELEE_RANGE := 2.6
const MELEE_DAMAGE := 34          # three hits on a full-health demon
const MELEE_COOLDOWN := 0.6


# Cloud Stomp: how much it hurts a demon this far (sideways) from where it landed,
# after coming down from this high up.
static func stomp_damage(dist: float, drop: float) -> int:
	if dist > STOMP_RADIUS:
		return 0
	var near := 1.0 - dist / STOMP_RADIUS
	var high := 1.0 + clampf((drop - STOMP_BASE_HEIGHT) / (STOMP_FULL_HEIGHT - STOMP_BASE_HEIGHT), 0.0, 1.0)
	return maxi(STOMP_MIN_DAMAGE, roundi(STOMP_DAMAGE * near * high))


static func label(id: String) -> String:
	return SKILLS[id]["label"] if SKILLS.has(id) else "-"


static func hatred_cost(id: String) -> float:
	return SKILLS[id].get("hatred", 0.0) if SKILLS.has(id) else 0.0


static func cooldown(id: String) -> float:
	return SKILLS[id]["cooldown"] if SKILLS.has(id) else 0.0


static func for_team(team: String) -> Array:
	var ids := []
	for id in SKILLS:
		if SKILLS[id]["team"] == team and not SKILLS[id].has("part_of"):
			ids.append(id)
	return ids


# Exactly 2 slots, each a real skill of that team or "" (empty), no duplicates.
static func clean_loadout(team: String, wanted) -> Array:
	var out := ["", ""]
	if typeof(wanted) != TYPE_ARRAY:
		return DEFAULTS[team].duplicate()
	for i in mini(2, wanted.size()):
		var id = wanted[i]
		if id == "chicken":
			id = "cherub"   # renamed in 0.4
		if id == "grapple":
			id = "dash"     # the hook became the Flying Dash
		if id == "vanish":
			id = "minion"   # Invisibility became a power-up in 0.5.2
		if typeof(id) == TYPE_STRING and SKILLS.has(id) and SKILLS[id]["team"] == team \
				and not SKILLS[id].has("part_of") and not id in out:
			out[i] = id
	return out
