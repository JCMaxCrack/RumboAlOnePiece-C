class_name TouchButton
extends Control
## Round button of the touch controls. While a finger holds it, its input action is pressed
## (as if it were a key), so the game code does not need to know about the touch screen.

@export var action := "jump"
@export var text := "Jump"
@export var color := Color(0.93, 0.78, 0.42)
@export var font_size := 22

var pressed := false
var touch_index := -1


func hit(pos: Vector2) -> bool:
	if not is_visible_in_tree():
		return false
	var r := minf(size.x, size.y) / 2.0
	return pos.distance_to(get_global_rect().get_center()) <= r * 1.15


func set_pressed(on: bool) -> void:
	if on == pressed:
		return
	pressed = on
	var e := InputEventAction.new()
	e.action = action
	e.pressed = on
	e.strength = 1.0 if on else 0.0
	Input.parse_input_event(e)
	queue_redraw()


func release() -> void:
	touch_index = -1
	set_pressed(false)


func _draw() -> void:
	var r := minf(size.x, size.y) / 2.0
	var c := size / 2.0
	draw_circle(c, r, Color(0.05, 0.07, 0.12, 0.65 if pressed else 0.45))
	draw_arc(c, r - 2.0, 0.0, TAU, 48, color if pressed else Color(color, 0.8), 4.0 if pressed else 3.0, true)
	var font := get_theme_default_font()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	draw_string(font, c + Vector2(-w / 2.0, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(1, 1, 1, 0.95))
