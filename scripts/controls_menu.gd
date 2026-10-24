class_name ControlsMenu
extends Control
## Opciones -> Controles (scenes/ui/controls_menu.tscn): one row per action with its key of the
## keyboard and its button of the gamepad. Pressing one of them waits for the new key or button
## (Esc cancels). "Restablecer" puts back the controls of the game. Saved by Preferences.

signal closed

@onready var list: GridContainer = $Panel/VBox/Scroll/List
@onready var wait_label: Label = $Panel/VBox/Wait
@onready var back_button: Button = $Panel/VBox/Buttons/BackButton

var _waiting_action := ""
var _waiting_gamepad := false


func _ready() -> void:
	visible = false
	Preferences.bindings_changed.connect(_refresh)


func open() -> void:
	visible = true
	_waiting_action = ""
	wait_label.text = tr("Choose an action to change its key or button")
	_refresh()
	back_button.grab_focus()


func close() -> void:
	visible = false
	_waiting_action = ""
	closed.emit()


func _refresh() -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	for title in ["Action", "Keyboard", "Gamepad"]:
		var h := Label.new()
		h.text = tr(title)
		h.modulate = Color(0.93, 0.78, 0.42)
		list.add_child(h)
	for spec in Preferences.REMAPPABLE:
		var a: String = spec[0]
		var l := Label.new()
		l.text = tr(spec[1])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(l)
		for gamepad in [false, true]:
			var b := Button.new()
			b.custom_minimum_size = Vector2(170, 36)
			b.text = Preferences.event_text(a, gamepad)
			if a == _waiting_action and gamepad == _waiting_gamepad:
				b.text = "..."
			b.pressed.connect(_on_binding_pressed.bind(a, gamepad))
			list.add_child(b)


func _on_binding_pressed(action: String, gamepad: bool) -> void:
	_waiting_action = action
	_waiting_gamepad = gamepad
	wait_label.text = (tr("Press the gamepad button for “%s” (Esc cancels)") if gamepad else tr("Press the key for “%s” (Esc cancels)")) % tr(_label_of(action))
	_refresh()


func _label_of(action: String) -> String:
	for spec in Preferences.REMAPPABLE:
		if spec[0] == action:
			return spec[1]
	return action


func _input(event: InputEvent) -> void:
	if not visible or _waiting_action == "":
		return
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_waiting_action = ""
		wait_label.text = tr("Cancelled")
		_refresh()
		return
	var wants_pad := _waiting_gamepad
	var ok := (event is InputEventKey and not wants_pad and (event as InputEventKey).pressed) or \
		(wants_pad and ((event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed) or event is InputEventJoypadMotion))
	if not ok:
		return
	var e := Preferences.clean_event(event)
	if e == null:
		return
	get_viewport().set_input_as_handled()
	var action := _waiting_action
	_waiting_action = ""
	Preferences.set_event(action, e)
	wait_label.text = tr("“%s” is now %s") % [tr(_label_of(action)), Preferences.describe(e)]
	_refresh()


func _on_reset_button_pressed() -> void:
	Preferences.reset_bindings()
	wait_label.text = tr("Controls reset")


func _on_back_button_pressed() -> void:
	close()
