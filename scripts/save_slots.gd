class_name SaveSlots
extends Control
## The 4 save slots (scenes/ui/save_slots.tscn), used in two ways:
##   LOAD mode (main menu): "Load" a slot, start a "New" game in it (replacing what it had)
##                          or "Delete" it.
##   SAVE mode (pause menu): "Save here" saves the current game in a new slot or replaces one.
## Replacing or deleting a slot asks for confirmation. Slots whose file was modified are shown as
## "modificado" and can not be loaded. Every row is a node: Slots/Slot1..Slot4.

signal save_requested(slot: int)
signal closed

enum Mode { LOAD, SAVE }

@export var mode: Mode = Mode.LOAD

@onready var title_label: Label = $Panel/VBox/Title
@onready var rows: Array = [$Panel/VBox/Slots/Slot1, $Panel/VBox/Slots/Slot2, $Panel/VBox/Slots/Slot3, $Panel/VBox/Slots/Slot4]
@onready var confirm_box: Control = $Panel/VBox/Confirm
@onready var confirm_label: Label = $Panel/VBox/Confirm/Label
@onready var status_label: Label = $Panel/VBox/Status
@onready var back_button: Button = $Panel/VBox/BackButton

var _pending_action := Callable()


func _ready() -> void:
	for i in rows.size():
		var row: Node = rows[i]
		var slot := i + 1
		row.get_node("HBox/MainButton").pressed.connect(_on_main_pressed.bind(slot))
		row.get_node("HBox/NewButton").pressed.connect(_on_new_pressed.bind(slot))
		row.get_node("HBox/DeleteButton").pressed.connect(_on_delete_pressed.bind(slot))


func open(new_mode: Mode) -> void:
	mode = new_mode
	visible = true
	confirm_box.visible = false
	status_label.text = ""
	refresh()
	back_button.grab_focus()


func refresh() -> void:
	title_label.text = tr("Choose a game") if mode == Mode.LOAD else tr("Save game")
	var slots := SaveManager.list_slots()
	for i in rows.size():
		var info: Dictionary = slots[i]
		var row: Node = rows[i]
		var label: Label = row.get_node("HBox/Info")
		var main: Button = row.get_node("HBox/MainButton")
		var new_button: Button = row.get_node("HBox/NewButton")
		var delete_button: Button = row.get_node("HBox/DeleteButton")
		label.text = tr("Game %d") % (i + 1) + "  ·  " + describe(info)
		main.text = tr("Load") if mode == Mode.LOAD else tr("Save here")
		new_button.visible = mode == Mode.LOAD
		delete_button.disabled = info.status == SaveManager.SlotStatus.EMPTY
		if mode == Mode.LOAD:
			main.disabled = info.status != SaveManager.SlotStatus.VALID or bool(info.data.completed)
		else:
			main.disabled = false


## Text of a slot: what was done, play time and date.
static func describe(info: Dictionary) -> String:
	match info.status:
		SaveManager.SlotStatus.EMPTY:
			return TranslationServer.translate("Empty")
		SaveManager.SlotStatus.TAMPERED:
			return TranslationServer.translate("Save modified or damaged! It can't be loaded")
	var d: Dictionary = info.data
	var t := int(d.play_time)
	var dt := Time.get_datetime_dict_from_unix_time(int(d.saved_at) + int(Time.get_time_zone_from_system().bias) * 60)
	var date := "%02d/%02d/%d %02d:%02d" % [dt.day, dt.month, dt.year, dt.hour, dt.minute]
	if d.completed:
		return TranslationServer.translate("Adventure complete!") + "  ·  %d:%02d  ·  %s" % [t / 60, t % 60, date]
	var heroes: Array = d.heroes
	var who := []
	for h in heroes:
		who.append("%s %s" % [TranslationServer.translate(str(h.character).capitalize()), TranslationServer.translate("Lv. %d") % int(h.level)])
	if heroes.size() > 1:
		who[0] = TranslationServer.translate("Co-op") + ": " + who[0]
	var crew := ["luffy"]
	for c in d.voyage.crew + heroes.map(func(h): return h.character):
		if not crew.has(c):
			crew.append(c)
	return "%s  ·  %s  ·  %s  ·  %d:%02d  ·  %s" % [TranslationServer.translate(GameState.ISLAND_NAMES[d.island]),
		" + ".join(who), TranslationServer.translate("Crew: %d") % crew.size(), t / 60, t % 60, date]


func _ask(text: String, action: Callable) -> void:
	confirm_label.text = text
	confirm_box.visible = true
	_pending_action = action
	$Panel/VBox/Confirm/Buttons/YesButton.grab_focus()


func _on_main_pressed(slot: int) -> void:
	var info := SaveManager.read_slot(slot)
	if mode == Mode.LOAD:
		if SaveManager.load_game(slot):
			get_tree().paused = false
			get_tree().change_scene_to_file(GameState.WORLD_SCENE)
		elif info.status == SaveManager.SlotStatus.VALID and (info.data.heroes as Array).size() > 1:
			status_label.text = tr("It's a co-op game: connect a gamepad for player 2.")
		else:
			status_label.text = tr("That game can't be loaded.")
	elif info.status == SaveManager.SlotStatus.EMPTY:
		save_requested.emit(slot)
	else:
		_ask(tr("Replace Game %d with the current progress?") % slot, save_requested.emit.bind(slot))


func _on_new_pressed(slot: int) -> void:
	var start := func() -> void:
		SaveManager.start_new_game(slot)
		get_tree().paused = false
		get_tree().change_scene_to_file(GameState.WORLD_SCENE)
	if SaveManager.read_slot(slot).status == SaveManager.SlotStatus.EMPTY:
		start.call()
	else:
		_ask(tr("Start a new game in Game %d? What it had will be lost.") % slot, start)


func _on_delete_pressed(slot: int) -> void:
	_ask(tr("Delete Game %d?") % slot, func() -> void:
		SaveManager.delete_slot(slot)
		status_label.text = tr("Game %d deleted.") % slot
		refresh())


func _on_yes_button_pressed() -> void:
	confirm_box.visible = false
	var action := _pending_action
	_pending_action = Callable()
	if action.is_valid():
		action.call()


func _on_no_button_pressed() -> void:
	confirm_box.visible = false
	_pending_action = Callable()


func _on_back_button_pressed() -> void:
	visible = false
	closed.emit()


## Called by the pause menu after saving.
func show_saved(slot: int, ok: bool) -> void:
	status_label.text = (tr("Game %d saved.") % slot) if ok else tr("Could not save.")
	refresh()
