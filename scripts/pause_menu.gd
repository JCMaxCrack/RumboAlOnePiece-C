class_name PauseMenu
extends CanvasLayer
## Pause menu. Nodes in scenes/ui/pause_menu.tscn.
## "Save game" opens SaveSlots (save mode): the game is saved in a new slot or replaces one.

## Connected by world.gd (scenes/world.tscn), which collects the progress and saves it.
signal save_requested(slot: int)

@onready var panel: Control = $Panel
@onready var continue_button: Button = $Panel/VBox/ContinueButton
@onready var save_button: Button = $Panel/VBox/SaveButton
@onready var save_slots: SaveSlots = $SaveSlots
@onready var options: GraphicsOptions = $GraphicsOptions

## game_world.gd turns it off while saving is not possible (e.g. Luffy lost).
var can_save := true


func toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	save_slots.visible = false
	options.visible = false
	panel.visible = true
	if visible:
		# game_world.gd stops while paused, so the mouse is freed here to click the menu
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		save_button.disabled = not can_save
		continue_button.grab_focus()


## Esc / Start closes the pause (game_world.gd does not receive input while paused).
func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or (GameSession.coop and event.is_action_pressed("p2_pause"))):
		get_viewport().set_input_as_handled()
		if save_slots.visible:
			save_slots._on_back_button_pressed()
		elif options.visible:
			options.close()
		else:
			toggle()


func _on_continue_button_pressed() -> void:
	toggle()


func _on_save_button_pressed() -> void:
	panel.visible = false
	save_slots.open(SaveSlots.Mode.SAVE)


func _on_save_slots_save_requested(slot: int) -> void:
	save_requested.emit(slot)


## Called by game_world.gd with the result of the save.
func show_saved(slot: int, ok: bool) -> void:
	save_slots.show_saved(slot, ok)


func _on_options_button_pressed() -> void:
	panel.visible = false
	options.open()


func _on_graphics_options_closed() -> void:
	panel.visible = true
	continue_button.grab_focus()


func _on_save_slots_closed() -> void:
	panel.visible = true
	save_button.grab_focus()


func _on_menu_button_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_quit_button_pressed() -> void:
	get_tree().quit()
