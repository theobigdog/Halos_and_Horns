# Every action's key (or mouse button), rebindable, saved in the settings file.
# Esc always opens the menu and can't be rebound.
extends RefCounted

# [action, what it's called on the Controls screen, default ("key:<code>" or "mouse:<button>")]
const ACTIONS := [
	["move_forward", "Move forward", "key:%d" % KEY_W],
	["move_back", "Move back", "key:%d" % KEY_S],
	["move_left", "Move left", "key:%d" % KEY_A],
	["move_right", "Move right", "key:%d" % KEY_D],
	["jump", "Jump", "key:%d" % KEY_SPACE],
	["run", "Run (demons: also turn your prop with the view)", "key:%d" % KEY_SHIFT],
	["sneak", "Sneak", "key:%d" % KEY_CTRL],
	["shoot", "Throw / transform (hold: back to demon form)", "mouse:%d" % MOUSE_BUTTON_LEFT],
	["skill_1", "Skill 1", "key:%d" % KEY_Q],
	["rmb", "Skill 2", "mouse:%d" % MOUSE_BUTTON_RIGHT],
	["melee", "Melee (angels)", "key:%d" % KEY_F],
	["shrine", "Swap skills at the shrine", "key:%d" % KEY_G],
	["free_look", "Look around without turning (angels)", "key:%d" % KEY_ALT],
	["minion_jump", "Make your Minion jump (demons)", "key:%d" % KEY_ALT],
	["toggle_view", "First / third person", "key:%d" % KEY_T],
	["taunt_random", "Random taunt", "key:%d" % KEY_1],
	["taunt_signature", "Signature taunt", "key:%d" % KEY_2],
	["animate", "Animate your prop (demons: light a candle, pop a cork...)", "key:%d" % KEY_E],
	["chat_all", "Chat to everyone", "key:%d" % KEY_ENTER],
	["chat_team", "Chat to your team", "key:%d" % KEY_BACKSPACE],
	["scoreboard", "Roster (hold)", "key:%d" % KEY_TAB],
	["cycle_blessing", "Change blessing type (testing)", "key:%d" % KEY_B],
	["toggle_tuning", "Movement tuning panel", "key:%d" % KEY_F1],
	["switch_role", "Practice: switch side", "key:%d" % KEY_F2],
	["restart", "Practice: restart", "key:%d" % KEY_R],
	["skip_hiding", "Practice: skip the hiding wait", "key:%d" % KEY_ENTER],
]


static func code_for(action: String) -> String:
	for a in ACTIONS:
		if a[0] == action:
			return a[2]
	return ""


static func make_event(code: String) -> InputEvent:
	var parts := code.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return null
	if parts[0] == "mouse":
		var m := InputEventMouseButton.new()
		m.button_index = int(parts[1]) as MouseButton
		return m
	var k := InputEventKey.new()
	k.physical_keycode = int(parts[1]) as Key
	return k


# The code for a pressed key / mouse button (or "" if it can't be bound).
static func code_of(event: InputEvent) -> String:
	if event is InputEventKey:
		var kc: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if kc == KEY_ESCAPE or kc == KEY_NONE:
			return ""
		return "key:%d" % kc
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			return "mouse:%d" % event.button_index
		return "mouse:%d" % event.button_index
	return ""


static func bind(action: String, code: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var ev := make_event(code)
	if ev:
		InputMap.action_add_event(action, ev)


# Set up every action, using saved choices where there are any.
static func setup(saved: Dictionary) -> void:
	for a in ACTIONS:
		bind(a[0], saved.get(a[0], a[2]))


static func current(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for ev in InputMap.action_get_events(action):
		var c := code_of(ev)
		if c != "":
			return c
	return ""


# What to show for a key on screen: "Q", "Right click", "Shift"...
static func text_for(code: String) -> String:
	var parts := code.split(":")
	if parts.size() != 2:
		return "-"
	if parts[0] == "mouse":
		match int(parts[1]):
			MOUSE_BUTTON_LEFT: return "Left click"
			MOUSE_BUTTON_RIGHT: return "Right click"
			MOUSE_BUTTON_MIDDLE: return "Middle click"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel down"
			MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
		return "Mouse %s" % parts[1]
	var name := OS.get_keycode_string(int(parts[1]) as Key)
	return name if name != "" else "Key %s" % parts[1]


static func key_name(action: String) -> String:
	return text_for(current(action))
