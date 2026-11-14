# Every skill in the game, and loadouts (each player picks 2 per team).
# Keys: Q = skill 1. Angels: right-click = skill 2, F = melee.
#                    Demons: F = skill 2, right-click (hold) = fly.
# Numbers here are first guesses, meant to be tuned in playtests.
extends RefCounted

const SKILLS := {
	# ---- angels ----
	"grapple": {"team": "angel", "label": "Grappling Hook", "cooldown": 6.0,
		"desc": "Zip to walls and roofs, or snag a demon: damages it and drags it to you."},
	"chicken": {"team": "angel", "label": "Alarm Chicken", "cooldown": 20.0,
		"desc": "Drop a chicken that pulses for 9 seconds and squawks if a demon is close."},
	"vacuum": {"team": "angel", "label": "Vacuum Orb", "cooldown": 18.0,
		"desc": "Throw into a pile of props: sucks them in, yanks hidden demons hard, drains their Hatred and locks their skills for 2 seconds."},
	"leap": {"team": "angel", "label": "Holy Leap", "cooldown": 8.0,
		"desc": "A magnificent jump."},
	# ---- demons ----
	"possess": {"team": "demon", "label": "Possess", "cooldown": 1.5,
		"desc": "Become a real prop instead of a copy (Q while aiming at it). The one you leave behind slowly dissolves."},
}

const DEFAULTS := {"angel": ["grapple", "chicken"], "demon": ["possess", ""]}

# Tuning
const GRAPPLE_RANGE := 25.0
const GRAPPLE_SPEED := 20.0       # m/s while zipping toward the hook
const GRAPPLE_DAMAGE := 20
const CHICKEN_RANGE := 15.0       # how far away you can drop it
const CHICKEN_RADIUS := 6.0       # detection radius
const CHICKEN_LIFETIME := 9.0
const VACUUM_RADIUS := 6.0
const VACUUM_TIME := 2.5
const VACUUM_HATRED_DRAIN := 35.0
const VACUUM_LOCKOUT := 2.0       # seconds a vacuumed demon can't use skills or fly
const LEAP_VELOCITY := 12.0
const MELEE_RANGE := 2.6
const MELEE_DAMAGE := 34          # three hits on a full-health demon
const MELEE_COOLDOWN := 0.6


static func label(id: String) -> String:
	return SKILLS[id]["label"] if SKILLS.has(id) else "-"


static func cooldown(id: String) -> float:
	return SKILLS[id]["cooldown"] if SKILLS.has(id) else 0.0


static func for_team(team: String) -> Array:
	var ids := []
	for id in SKILLS:
		if SKILLS[id]["team"] == team:
			ids.append(id)
	return ids


# Exactly 2 slots, each a real skill of that team or "" (empty), no duplicates.
static func clean_loadout(team: String, wanted) -> Array:
	var out := ["", ""]
	if typeof(wanted) != TYPE_ARRAY:
		return DEFAULTS[team].duplicate()
	for i in mini(2, wanted.size()):
		var id = wanted[i]
		if typeof(id) == TYPE_STRING and SKILLS.has(id) and SKILLS[id]["team"] == team and not id in out:
			out[i] = id
	return out
