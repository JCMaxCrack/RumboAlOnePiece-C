class_name SailMenu
extends CanvasLayer
## Navigation chart (scenes/ui/sail_menu.tscn): opened while steering the Going Merry. It lists the
## islands of the voyage; an open one can be chosen as the course (the compass and the light point to it).

signal sail_requested(island_id: String)
signal closed

@onready var buttons: Array = $Panel/VBox/Islands.get_children()
@onready var info_label: Label = $Panel/VBox/Info
@onready var cancel_button: Button = $Panel/VBox/CancelButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	for i in buttons.size():
		(buttons[i] as Button).pressed.connect(_on_island_pressed.bind(i))


func open(current: String) -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var focus: Button = cancel_button
	for i in buttons.size():
		var b: Button = buttons[i]
		var id: String = GameState.ISLANDS[i]
		var name: String = tr(GameState.ISLAND_NAMES[id])
		if id == current:
			b.text = tr("%s  (you are here)") % name
			b.disabled = true
		elif GameState.unlocked.has(id):
			b.text = name + ("  ✓" if GameState.completed.has(id) else "")
			b.disabled = false
			focus = b
		else:
			b.text = "???  " + tr("(complete the previous island)")
			b.disabled = true
	info_label.text = tr("Choose the Going Merry's course")
	focus.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close()


func _on_island_pressed(i: int) -> void:
	var id: String = GameState.ISLANDS[i]
	visible = false
	get_tree().paused = false
	sail_requested.emit(id)


func _on_cancel_button_pressed() -> void:
	close()
