extends Control
## Main menu. Nodes in scenes/main_menu.tscn.
## "Play" asks how to play (ModePanel: single player or local co-op with a gamepad for
## player 2, GameSession); in co-op every player chooses his character (CharacterSelect); then
## the 4 save slots open (SaveSlots node, load mode).

@onready var menu_panel: Control = $MenuPanel
@onready var controls_panel: Control = $ControlsPanel
@onready var play_button: Button = $MenuPanel/VBox/PlayButton
@onready var back_button: Button = $ControlsPanel/VBox/BackButton
@onready var click_sound: AudioStreamPlayer = $ClickSound
@onready var save_slots: SaveSlots = $SaveSlots
@onready var mode_panel: Control = $ModePanel
@onready var solo_button: Button = $ModePanel/VBox/SoloButton
@onready var coop_button: Button = $ModePanel/VBox/CoopButton
@onready var mode_info: Label = $ModePanel/VBox/Info
@onready var options: GraphicsOptions = $GraphicsOptions

var character_select: CharacterSelect


func _ready() -> void:
	get_tree().paused = false
	get_viewport().disable_3d = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	character_select = CharacterSelect.new()
	character_select.name = "CharacterSelect"
	add_child(character_select)
	move_child(character_select, save_slots.get_index())
	character_select.chosen.connect(_on_characters_chosen)
	character_select.cancelled.connect(_on_characters_cancelled)
	play_button.grab_focus()


func _on_play_button_pressed() -> void:
	click_sound.play()
	menu_panel.visible = false
	mode_panel.visible = true
	_update_mode_info()
	solo_button.grab_focus()


func _update_mode_info() -> void:
	if GameSession.can_play_coop():
		mode_info.text = "Co-op: split screen. Player 1: keyboard and mouse. Player 2: gamepad. Each one picks a character."
	else:
		mode_info.text = "For co-op, connect a gamepad: player 2 plays with it."


func _on_solo_button_pressed() -> void:
	click_sound.play()
	GameSession.start(false)
	mode_panel.visible = false
	save_slots.open(SaveSlots.Mode.LOAD)


func _on_coop_button_pressed() -> void:
	click_sound.play()
	if not GameSession.can_play_coop():
		_update_mode_info()
		return
	GameSession.start(true)
	mode_panel.visible = false
	character_select.open()


func _on_characters_chosen(characters: Array) -> void:
	click_sound.play()
	GameSession.characters = characters
	save_slots.open(SaveSlots.Mode.LOAD)


func _on_characters_cancelled() -> void:
	click_sound.play()
	mode_panel.visible = true
	coop_button.grab_focus()


func _on_mode_back_button_pressed() -> void:
	click_sound.play()
	mode_panel.visible = false
	menu_panel.visible = true
	play_button.grab_focus()


func _on_options_button_pressed() -> void:
	click_sound.play()
	menu_panel.visible = false
	options.open()


func _on_graphics_options_closed() -> void:
	click_sound.play()
	menu_panel.visible = true
	play_button.grab_focus()


func _on_save_slots_closed() -> void:
	click_sound.play()
	mode_panel.visible = true
	solo_button.grab_focus()


func _on_controls_button_pressed() -> void:
	click_sound.play()
	menu_panel.visible = false
	controls_panel.visible = true
	back_button.grab_focus()


func _on_back_button_pressed() -> void:
	click_sound.play()
	controls_panel.visible = false
	menu_panel.visible = true
	play_button.grab_focus()


func _on_quit_button_pressed() -> void:
	get_tree().quit()
