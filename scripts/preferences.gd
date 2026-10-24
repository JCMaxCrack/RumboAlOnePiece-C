extends Node
## Preferences (autoload, see project.godot): language and controls chosen in "Options".
## Kept in user://preferencias.cfg (not in the save slots).
##
## Language: English (the texts of the game, and the default) or Spanish (assets/i18n/translations.csv,
## imported by Godot as .translation files). TranslationServer changes every text on screen at once.
##
## Controls: every action of REMAPPABLE has one key of the keyboard and one button (or stick
## direction) of the gamepad that the player can change. The defaults are the ones of
## project.godot. The arrow keys also move and the mouse also turns the camera and punches.

signal language_changed
signal bindings_changed

const FILE := "user://preferencias.cfg"
const LANGUAGES := {"en": "English", "es": "Español"}
## Actions that can be changed in Options -> Controls, with their name on screen.
const REMAPPABLE := [
	["move_forward", "Forward"], ["move_back", "Backward"], ["move_left", "Left"], ["move_right", "Right"],
	["sprint", "Run"], ["jump", "Jump / swim"], ["attack", "Punch"], ["interact", "Talk / use"],
	["use_item", "Eat / use item"], ["next_item", "Switch item"], ["skill", "Skill"],
	["next_skill", "Switch skill"], ["shop", "Skill shop"], ["map", "Map"], ["pause", "Pause"],
]

var language := "en"
## Events of every remappable action as the player chose them (any device). GameSession builds the
## real InputMap from them (one gamepad per player in co-op).
var bindings := {}
## Default events of every action (copied from project.godot before any change).
var _defaults := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for spec in REMAPPABLE:
		_defaults[spec[0]] = InputMap.action_get_events(spec[0]).duplicate()
		bindings[spec[0]] = InputMap.action_get_events(spec[0]).duplicate()
	_load()
	_write_input_map()
	TranslationServer.set_locale(language)


func _write_input_map() -> void:
	for a in bindings:
		InputMap.action_erase_events(a)
		for e in bindings[a]:
			InputMap.action_add_event(a, e)


## After a change: the InputMap is made again (GameSession splits the gamepads in co-op).
func _apply() -> void:
	_write_input_map()
	var gs := get_node_or_null("/root/GameSession")
	if gs:
		gs.call("refresh_bindings")
	_save()
	bindings_changed.emit()


# ------------------------------------------------------------------ language
func set_language(code: String) -> void:
	if not LANGUAGES.has(code):
		return
	language = code
	TranslationServer.set_locale(code)
	_save()
	language_changed.emit()


# ------------------------------------------------------------------ controls
## The key (keyboard) or the button (gamepad) of an action.
func get_event(action: String, gamepad: bool) -> InputEvent:
	for e in bindings.get(action, []):
		if gamepad and (e is InputEventJoypadButton or e is InputEventJoypadMotion):
			return e
		if not gamepad and e is InputEventKey:
			return e
	return null


## Changes the key (or the gamepad button) of an action. The same key is taken away from any other
## action that had it, so two actions never share it.
func set_event(action: String, event: InputEvent) -> void:
	var gamepad := event is InputEventJoypadButton or event is InputEventJoypadMotion
	for spec in REMAPPABLE:
		var other: String = spec[0]
		if other != action and _same(get_event(other, gamepad), event):
			_replace(other, gamepad, null)
	_replace(action, gamepad, event)
	_apply()


func reset_bindings() -> void:
	for a in _defaults:
		bindings[a] = (_defaults[a] as Array).duplicate()
	_apply()


## Text of the key or button of an action ("E", "Space", "Botón Y"...).
func event_text(action: String, gamepad: bool) -> String:
	return describe(get_event(action, gamepad))


static func describe(e: InputEvent) -> String:
	if e == null:
		return "—"
	if e is InputEventKey:
		var k := e as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
		var names := {KEY_SPACE: "Space", KEY_SHIFT: "Shift", KEY_ESCAPE: "Esc", KEY_TAB: "Tab", KEY_ENTER: "Enter",
			KEY_UP: "↑", KEY_DOWN: "↓", KEY_LEFT: "←", KEY_RIGHT: "→", KEY_CTRL: "Ctrl", KEY_ALT: "Alt"}
		if names.has(code):
			return TranslationServer.translate(names[code])
		return OS.get_keycode_string(code)
	if e is InputEventJoypadButton:
		var names2 := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_BACK: "Back",
			JOY_BUTTON_START: "Start", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_LEFT_SHOULDER: "LB",
			JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_DPAD_UP: "D-pad ↑", JOY_BUTTON_DPAD_DOWN: "D-pad ↓",
			JOY_BUTTON_DPAD_LEFT: "D-pad ←", JOY_BUTTON_DPAD_RIGHT: "D-pad →"}
		var b := (e as InputEventJoypadButton).button_index
		return TranslationServer.translate("Button") + " " + str(names2.get(b, b))
	if e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		var axes := {JOY_AXIS_LEFT_X: "Left stick X", JOY_AXIS_LEFT_Y: "Left stick Y", JOY_AXIS_RIGHT_X: "Right stick X",
			JOY_AXIS_RIGHT_Y: "Right stick Y", JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT"}
		return TranslationServer.translate(str(axes.get(m.axis, "Axis %d" % m.axis))) + (" +" if m.axis_value > 0.0 else " −")
	return "?"


## An event of the keyboard or the gamepad that can be used as a binding (from what the player pressed).
static func clean_event(e: InputEvent) -> InputEvent:
	if e is InputEventKey:
		var k := InputEventKey.new()
		k.physical_keycode = (e as InputEventKey).physical_keycode
		k.device = -1
		return k
	if e is InputEventJoypadButton:
		var b := InputEventJoypadButton.new()
		b.button_index = (e as InputEventJoypadButton).button_index
		b.device = -1
		return b
	if e is InputEventJoypadMotion and absf((e as InputEventJoypadMotion).axis_value) > 0.6:
		var m := InputEventJoypadMotion.new()
		m.axis = (e as InputEventJoypadMotion).axis
		m.axis_value = signf((e as InputEventJoypadMotion).axis_value)
		m.device = -1
		return m
	return null


func _same(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null or a.get_class() != b.get_class():
		return false
	if a is InputEventKey:
		return (a as InputEventKey).physical_keycode == (b as InputEventKey).physical_keycode
	if a is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	if a is InputEventJoypadMotion:
		return (a as InputEventJoypadMotion).axis == (b as InputEventJoypadMotion).axis and signf((a as InputEventJoypadMotion).axis_value) == signf((b as InputEventJoypadMotion).axis_value)
	return false


## Replaces the first keyboard (or gamepad) event of an action; the others (arrow keys) stay.
func _replace(action: String, gamepad: bool, event: InputEvent) -> void:
	var events: Array = bindings.get(action, [])
	var out := []
	var done := false
	for e in events:
		var is_pad := e is InputEventJoypadButton or e is InputEventJoypadMotion
		if is_pad == gamepad and (e is InputEventKey or is_pad) and not done:
			done = true
			if event:
				out.append(event)
			continue
		out.append(e)
	if not done and event:
		out.append(event)
	bindings[action] = out


# ------------------------------------------------------------------ file
func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(FILE) != OK:
		return
	# "language" (not the old "idioma" key, written when Spanish was the default): English unless
	# the player chose another language
	language = str(cfg.get_value("general", "language", "en"))
	if not LANGUAGES.has(language):
		language = "en"
	for spec in REMAPPABLE:
		var a: String = spec[0]
		for gamepad in [false, true]:
			var key := ("mando_" if gamepad else "teclado_") + a
			if not cfg.has_section_key("controles", key):
				continue
			var e := _from_text(str(cfg.get_value("controles", key)))
			_replace(a, gamepad, e)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("general", "language", language)
	for spec in REMAPPABLE:
		var a: String = spec[0]
		cfg.set_value("controles", "teclado_" + a, _to_text(get_event(a, false)))
		cfg.set_value("controles", "mando_" + a, _to_text(get_event(a, true)))
	cfg.save(FILE)


static func _to_text(e: InputEvent) -> String:
	if e is InputEventKey:
		return "key:%d" % (e as InputEventKey).physical_keycode
	if e is InputEventJoypadButton:
		return "button:%d" % (e as InputEventJoypadButton).button_index
	if e is InputEventJoypadMotion:
		return "axis:%d:%d" % [(e as InputEventJoypadMotion).axis, int(signf((e as InputEventJoypadMotion).axis_value))]
	return "none"


static func _from_text(t: String) -> InputEvent:
	var parts := t.split(":")
	match parts[0]:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(parts[1]) as Key
			k.device = -1
			return k
		"button":
			var b := InputEventJoypadButton.new()
			b.button_index = int(parts[1]) as JoyButton
			b.device = -1
			return b
		"axis":
			var m := InputEventJoypadMotion.new()
			m.axis = int(parts[1]) as JoyAxis
			m.axis_value = float(parts[2])
			m.device = -1
			return m
	return null
