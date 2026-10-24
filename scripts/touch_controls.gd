class_name TouchControls
extends CanvasLayer
## Touch controls for phones and tablets (scenes/ui/touch_controls.tscn).
##   Left side: joystick to move (push it to the edge to run).
##   Right side: drag to move the camera; buttons to jump, punch and talk; pause button.
## They are only shown on devices with a touch screen (or with force_visible).

signal look_dragged(relative: Vector2)

@export var force_visible := false
@export var look_sensitivity := 1.6
## Part of the screen (from the left) where a touch starts the joystick.
@export var joystick_zone := 0.42

@onready var joystick: TouchJoystick = $Root/Joystick
@onready var interact_button: TouchButton = $Root/InteractButton
@onready var buttons: Array = [$Root/JumpButton, $Root/AttackButton, $Root/InteractButton, $Root/PauseButton]

var active := false
## game_world.gd turns it off when the game ends.
var game_running := true
var _look_index := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	active = force_visible or DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	visible = active
	interact_button.visible = false


func set_interact_visible(on: bool, text: String = "Talk") -> void:
	interact_button.visible = on
	if interact_button.text != text:
		interact_button.text = text
		interact_button.queue_redraw()


func _process(_delta: float) -> void:
	set_shown(game_running and not get_tree().paused)


## Shows or hides the controls (they hide while the game is paused or finished).
func set_shown(on: bool) -> void:
	var want := active and on
	if visible != want:
		visible = want
		if not want:
			release_all()


func release_all() -> void:
	for b in buttons:
		(b as TouchButton).release()
	if joystick.touch_index >= 0:
		joystick.release()
	_look_index = -1


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			for b in buttons:
				var btn := b as TouchButton
				if btn.touch_index == -1 and btn.hit(t.position):
					btn.touch_index = t.index
					btn.set_pressed(true)
					get_viewport().set_input_as_handled()
					return
			if joystick.touch_index == -1 and t.position.x < get_viewport().get_visible_rect().size.x * joystick_zone:
				joystick.start(t.index, t.position)
			elif _look_index == -1:
				_look_index = t.index
		else:
			for b in buttons:
				if (b as TouchButton).touch_index == t.index:
					(b as TouchButton).release()
			if joystick.touch_index == t.index:
				joystick.release()
			if _look_index == t.index:
				_look_index = -1
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if joystick.touch_index == d.index:
			joystick.drag(d.position)
		elif d.index == _look_index:
			look_dragged.emit(d.relative * look_sensitivity)
		get_viewport().set_input_as_handled()
