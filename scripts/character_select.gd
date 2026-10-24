class_name CharacterSelect
extends Control
## Co-op: every player chooses his character (Luffy, Zoro, Usopp or Nami) at the same time.
## Player 1 uses the keyboard (A/D or arrows, Enter/Space to choose, Esc to go back) or the mouse
## (a click on a card); player 2 uses his gamepad (stick / D-pad, A to choose, B to undo). A
## character chosen by one player can not be chosen by the other. When both have chosen,
## `chosen` gives [player 1's, player 2's]. Made in code by the main menu.

signal chosen(characters: Array)
signal cancelled

const INFO := {
	"luffy": ["Luffy", "Captain. Stretchy rubber fists: he hits from far away."],
	"zoro": ["Zoro", "Swordsman. Three swords and lots of health: the toughest one."],
	"usopp": ["Usopp", "Sniper. Shoots far-away enemies with his slingshot."],
	"nami": ["Nami", "Navigator. Quick and agile, she fights with the Clima-Tact."],
}
const SCENES := {"luffy": "res://scenes/player/luffy.tscn", "zoro": "res://scenes/player/zoro.tscn",
	"usopp": "res://scenes/player/usopp.tscn", "nami": "res://scenes/player/nami.tscn"}
const COLORS := [Color(1.0, 0.82, 0.3), Color(0.45, 1.0, 0.45)]

var _cursor := [0, 1]
var _done := [false, false]
var _held := [false, false]
var _cards: Array[PanelContainer] = []
var _tags: Array[Label] = []
var _status: Label
var _finishing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.92)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	var title := Label.new()
	title.text = tr("Choose your character")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	box.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	for i in GameSession.CHARACTERS.size():
		row.add_child(_make_card(i, GameSession.CHARACTERS[i]))
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 18)
	box.add_child(_status)
	var help := Label.new()
	help.text = tr("Player 1: A/D or arrows and Enter (or click)  ·  Player 2: stick and A (B undoes)  ·  Esc: back")
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 15)
	help.modulate = Color(0.8, 0.8, 0.85)
	box.add_child(help)


func _make_card(index: int, who: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(230, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_input.bind(index))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var view := SubViewportContainer.new()
	view.custom_minimum_size = Vector2(214, 260)
	view.stretch = true
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(view)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	view.add_child(vp)
	_build_preview(vp, who)
	var name_label := Label.new()
	name_label.text = INFO[who][0]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 26)
	v.add_child(name_label)
	var desc := Label.new()
	desc.text = tr(INFO[who][1])
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(214, 60)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 14)
	desc.modulate = Color(0.85, 0.85, 0.85)
	v.add_child(desc)
	var tag := Label.new()
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 18)
	v.add_child(tag)
	_cards.append(card)
	_tags.append(tag)
	return card


## The character standing (idle animation) in a small 3D scene of its own.
func _build_preview(vp: SubViewport, who: String) -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.7)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	vp.add_child(sun)
	var p := (load(SCENES[who]) as PackedScene).instantiate() as Player
	p.control = Player.Controller.NONE
	# the card enters the tree later: the character is set up when it is ready
	p.ready.connect(_pose.bind(p))
	vp.add_child(p)
	var cam := Camera3D.new()
	cam.fov = 32.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.0, 4.4), Vector3(0, 0.9, 0))
	cam.current = true


## Only a statue that breathes: no physics and no animation logic of the Player, just "idle".
func _pose(p: Player) -> void:
	p.remove_from_group("players")
	p.set_physics_process(false)
	p.set_process(false)
	p.anim.play(p.anim_library + "/idle")
	for label in ["NameLabel", "PromptLabel"]:
		var l := p.get_node_or_null(label) as Node3D
		if l:
			l.visible = false
	p.model.rotation.y = p.model_yaw + 0.5


func open() -> void:
	visible = true
	_cursor = [0, 1]
	_done = [false, false]
	_finishing = false
	_refresh()


# ------------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if not visible or _finishing:
		return
	var who := 1 if _is_p2(event) else 0
	if event is InputEventJoypadMotion:
		_stick(who, event as InputEventJoypadMotion)
		return
	if _pressed(event, ["ui_left", "move_left", "p2_move_left"]):
		_move(who, -1)
	elif _pressed(event, ["ui_right", "move_right", "p2_move_right"]):
		_move(who, 1)
	elif _pressed(event, ["ui_accept", "jump", "p2_jump"]):
		_choose(who)
	elif event.is_action_pressed("ui_cancel"):
		if _done[who]:
			_done[who] = false
			_refresh()
		elif who == 0:
			visible = false
			cancelled.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func _pressed(event: InputEvent, actions: Array) -> bool:
	for a in actions:
		if InputMap.has_action(a) and event.is_action_pressed(a):
			return true
	return false


## Events of player 2's gamepad (everything else belongs to player 1).
func _is_p2(event: InputEvent) -> bool:
	return (event is InputEventJoypadButton or event is InputEventJoypadMotion) and event.device == GameSession.p2_device


## A stick moves the cursor once each time it is pushed to a side.
func _stick(who: int, m: InputEventJoypadMotion) -> void:
	if m.axis != JOY_AXIS_LEFT_X:
		return
	if absf(m.axis_value) < 0.3:
		_held[who] = false
	elif absf(m.axis_value) > 0.6 and not _held[who]:
		_held[who] = true
		_move(who, 1 if m.axis_value > 0.0 else -1)
	get_viewport().set_input_as_handled()


func _on_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if not _done[0]:
			_cursor[0] = index
			_choose(0)


func _move(who: int, dir: int) -> void:
	if _done[who]:
		return
	_cursor[who] = posmod(_cursor[who] + dir, GameSession.CHARACTERS.size())
	_refresh()


func _choose(who: int) -> void:
	if _done[who]:
		return
	var other := 1 - who
	if _done[other] and _cursor[other] == _cursor[who]:
		_status.text = tr("The other player already chose %s") % INFO[GameSession.CHARACTERS[_cursor[who]]][0]
		return
	_done[who] = true
	_refresh()
	if _done[0] and _done[1]:
		_finishing = true
		_status.text = tr("Off to adventure!")
		get_tree().create_timer(0.8).timeout.connect(func() -> void:
			visible = false
			chosen.emit([GameSession.CHARACTERS[_cursor[0]], GameSession.CHARACTERS[_cursor[1]]]))


func _refresh() -> void:
	for i in _cards.size():
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.1, 0.16, 0.95)
		style.set_corner_radius_all(10)
		style.set_content_margin_all(8)
		var tags := []
		for who in 2:
			if _cursor[who] == i:
				style.border_color = COLORS[who] if style.border_width_top == 0 else style.border_color.lerp(COLORS[who], 0.5)
				style.set_border_width_all(4 if _done[who] else 2)
				tags.append(tr("P%d ✓" if _done[who] else "P%d") % (who + 1))
		if (_done[0] and _cursor[0] == i) or (_done[1] and _cursor[1] == i):
			style.bg_color = Color(0.16, 0.14, 0.08, 0.95)
		_cards[i].add_theme_stylebox_override("panel", style)
		_tags[i].text = "  ".join(tags)
		_tags[i].modulate = COLORS[0] if _cursor[0] == i else COLORS[1]
	if not _finishing:
		var waiting := []
		for who in 2:
			if not _done[who]:
				waiting.append(tr("Player %d") % (who + 1))
		_status.text = tr("Waiting for: %s") % ", ".join(waiting) if not waiting.is_empty() else ""
