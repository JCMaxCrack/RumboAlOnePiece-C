class_name EndScreen
extends CanvasLayer
## Victory / defeat screen. Nodes in scenes/ui/end_screen.tscn.
## After losing, "Back to the checkpoint" loads the last save of the slot being played.

@onready var title_label: Label = $Panel/VBox/Title
@onready var detail_label: Label = $Panel/VBox/Detail
@onready var checkpoint_button: Button = $Panel/VBox/CheckpointButton
@onready var retry_button: Button = $Panel/VBox/RetryButton


func show_result(won: bool, time_seconds: float, collected: int, total: int, boss_defeated: bool) -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var t := int(time_seconds)
	if won:
		title_label.text = tr("Adventure complete!")
		title_label.modulate = Color(1, 0.85, 0.4)
		detail_label.text = tr("Luffy, Zoro, Usopp and Nami set sail together for the Grand Line.") + "\n" + tr("Level %d  ·  Time: %d:%02d") % [GameState.hero(0).level, t / 60, t % 60]
	else:
		title_label.text = tr("You were defeated!")
		title_label.modulate = Color(1, 0.45, 0.4)
		detail_label.text = tr("Boss: %s  ·  Meat collected: %d/%d") % [tr("derrotado") if boss_defeated else tr("still standing"), collected, total] + "\n" + tr("Time: %d:%02d") % [t / 60, t % 60]
	# with a save slot, losing sends you back to the last checkpoint (starting over would erase it)
	var has_save: bool = not won and SaveManager.current_slot > 0 and SaveManager.read_slot(SaveManager.current_slot).status == SaveManager.SlotStatus.VALID
	checkpoint_button.visible = has_save
	retry_button.visible = not has_save
	if has_save:
		checkpoint_button.grab_focus()
	else:
		retry_button.grab_focus()


func _on_checkpoint_button_pressed() -> void:
	get_tree().paused = false
	if SaveManager.load_game(SaveManager.current_slot):
		get_tree().change_scene_to_file(GameState.WORLD_SCENE)


## "Play again": a new game (in the same slot, if there is one).
func _on_retry_button_pressed() -> void:
	get_tree().paused = false
	if SaveManager.current_slot > 0:
		SaveManager.start_new_game(SaveManager.current_slot)
	else:
		GameState.reset()
	get_tree().change_scene_to_file(GameState.WORLD_SCENE)


func _on_menu_button_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
