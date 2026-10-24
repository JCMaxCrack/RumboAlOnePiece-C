class_name HUD
extends CanvasLayer
## In-game interface. Nodes in scenes/ui/hud.tscn.
## In co-op player 2 has his own copy of the level bar, the inventory and the skill box (made in
## code from player 1's, see set_split()); the functions that fill them take the player index.

const TOUCH_HINT := "Joystick: move (run at the edge)  ·  Drag on the right: camera"

@onready var health_bar: ProgressBar = $Root/PlayerPanel/VBox/HealthBar
@onready var health_label: Label = $Root/PlayerPanel/VBox/Row/HealthLabel
@onready var item_label: Label = $Root/ItemPanel/ItemLabel
@onready var mission_label: Label = $Root/MissionPanel/VBox/MissionText
@onready var boss_health_bar: ProgressBar = $Root/BossBox/BossHealthBar
@onready var boss_health_label: Label = $Root/BossBox/BossHealthBar/BossHealthLabel
@onready var boss_state_label: Label = $Root/BossBox/BossState
@onready var message_label: Label = $Root/Message
@onready var message_timer: Timer = $MessageTimer
@onready var dialog_panel: Control = $Root/DialogPanel
@onready var dialog_speaker: Label = $Root/DialogPanel/VBox/Speaker
@onready var dialog_text: Label = $Root/DialogPanel/VBox/Text
@onready var dialog_hint: Label = $Root/DialogPanel/VBox/Hint
@onready var controls_hint: Label = $Root/ControlsHint
@onready var fps_label: Label = $Root/FpsLabel
@onready var minimap: Minimap = $Root/Minimap
@onready var player2_panel: Control = $Root/Player2Panel
@onready var health_bar2: ProgressBar = $Root/Player2Panel/VBox/HealthBar
@onready var health_label2: Label = $Root/Player2Panel/VBox/Row/HealthLabel
@onready var inventory_slots: Array = $Root/Inventory/Slots.get_children()
@onready var inventory_hint: Label = $Root/Inventory/Hint
@onready var skill_box: Control = $Root/SkillBox
@onready var skill_hint: Label = $Root/SkillBox/VBox/Hint
@onready var interact_hint: Label = $Root/InteractHint
@onready var banner: Control = $Root/Banner
@onready var banner_title: Label = $Root/Banner/Title
@onready var banner_text: Label = $Root/Banner/Text
@onready var boss_name: Label = $Root/BossBox/BossName

var touch_mode := false
var sailing := false
## The World (set by it): the minimaps use it for the destination of the voyage.
var world: World
var compass: Compass
## Minimap of player 2 (co-op only).
var minimap2: Minimap
## Player 2's level bar, inventory and skill box (co-op only).
var _xp2: Control
var _inventory2: Control
var _skill_box2: Control
var _banner_tween: Tween


func _ready() -> void:
	Preferences.bindings_changed.connect(_refresh_hints)
	Preferences.language_changed.connect(_refresh_hints)
	banner.visible = false
	interact_hint.visible = false
	compass = Compass.new()
	compass.name = "Compass"
	compass.visible = false
	$Root.add_child(compass)
	compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	compass.offset_left = -220.0
	compass.offset_right = 220.0
	compass.offset_top = 8.0
	compass.offset_bottom = 104.0
	_refresh_hints()


func set_health(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "%d / %d" % [int(ceil(current)), int(maximum)]


## Names in the panels of player 1 and of the second panel (player 2, or Zoro as a companion).
func set_names(first: String, second: String) -> void:
	$Root/PlayerPanel/VBox/Row/NameLabel.text = first
	$Root/Player2Panel/VBox/Row/NameLabel.text = second


## Health of player 2 in co-op (or of Zoro, once he joins the crew in single player).
func set_health2(current: float, maximum: float) -> void:
	health_bar2.max_value = maximum
	health_bar2.value = current
	health_label2.text = "%d / %d" % [int(ceil(current)), int(maximum)]


func set_player2_visible(on: bool) -> void:
	player2_panel.visible = on


## The player that the minimap of player 1 follows.
func set_player(p: Player) -> void:
	minimap.target = p


## Co-op: the screen is split in two; each half has its panel of health and its minimap.
func set_split(on: bool, p2: Player) -> void:
	var vs := get_viewport().get_visible_rect().size
	if not on:
		return
	minimap.area = Rect2(Vector2.ZERO, Vector2(vs.x / 2.0, vs.y))
	minimap._layout()
	if minimap2 == null:
		minimap2 = Minimap.new()
		minimap2.name = "Minimap2"
		$Root.add_child(minimap2)
	minimap2.target = p2
	minimap2.area = Rect2(Vector2(vs.x / 2.0, 0.0), Vector2(vs.x / 2.0, vs.y))
	minimap2._layout()
	# player 2's panel goes to his half; the panels of the right side to the left half
	player2_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	player2_panel.position = Vector2(vs.x / 2.0 + 16.0, 16.0)
	for path in ["Root/ItemPanel", "Root/MissionPanel", "Root/SkillBox"]:
		var c := get_node(path) as Control
		var w := c.offset_right - c.offset_left
		c.anchor_left = 0.5
		c.anchor_right = 0.5
		c.offset_right = -16.0
		c.offset_left = -16.0 - w
	# player 2's own level bar, inventory (bottom left of his half) and skill box (bottom right)
	if _xp2 == null:
		_xp2 = $Root/PlayerPanel/VBox/XpRow.duplicate()
		$Root/Player2Panel/VBox.add_child(_xp2)
		_inventory2 = $Root/Inventory.duplicate()
		_inventory2.name = "Inventory2"
		$Root.add_child(_inventory2)
		_skill_box2 = skill_box.duplicate()
		_skill_box2.name = "SkillBox2"
		$Root.add_child(_skill_box2)
	_inventory2.anchor_left = 0.5
	_inventory2.anchor_right = 0.5
	_inventory2.offset_left = 16.0
	_inventory2.offset_right = 280.0
	var w := _skill_box2.offset_right - _skill_box2.offset_left
	_skill_box2.anchor_left = 1.0
	_skill_box2.anchor_right = 1.0
	_skill_box2.offset_right = -16.0
	_skill_box2.offset_left = -16.0 - w
	_skill_box2.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_refresh_hints()


## Taking the wheel of the Going Merry: the hints show the controls of the ship.
func set_sailing(on: bool) -> void:
	sailing = on
	$Root/Inventory.visible = not on
	if on:
		skill_box.visible = false
	if _inventory2:
		_inventory2.visible = not on
		if on:
			_skill_box2.visible = false
	_refresh_hints()


## The compass that points to the destination (angle from the camera, in radians).
func set_compass(on: bool, angle: float, title: String, meters: float) -> void:
	compass.visible = on and not $Root/BossBox.visible
	if compass.visible:
		compass.set_target(angle, title, meters)


func set_count(current: int, total: int) -> void:
	item_label.text = tr("Meat: %d / %d") % [current, total]


## Level, experience bar and skill points of a player.
func set_xp(level: int, xp: int, needed: int, points: int, player := 0) -> void:
	var row: Control = $Root/PlayerPanel/VBox/XpRow if player == 0 else _xp2
	if row == null:
		return
	(row.get_node("LevelLabel") as Label).text = tr("Lv. %d") % level
	var bar := row.get_node("XpBar") as ProgressBar
	bar.max_value = needed
	bar.value = xp
	var pts := row.get_node("PointsLabel") as Label
	pts.text = "★ %d" % points
	pts.modulate = Color(1, 0.85, 0.3) if points > 0 else Color(0.7, 0.7, 0.7)


## The slots of a player's inventory (HeroProgress.inventory) and the one selected.
func set_inventory(inv: Array, selected: int, player := 0) -> void:
	var slots: Array = inventory_slots if player == 0 else (_inventory2.get_node("Slots").get_children() if _inventory2 else [])
	for i in slots.size():
		var slot: ItemSlot = slots[i]
		var e: Dictionary = inv[i] if i < inv.size() else {}
		slot.set_item(str(e.get("id", "")), int(e.get("count", 0)), i == selected)


## A player's equipped skill and how much of its waiting time is left (1 = just used, 0 = ready).
func set_skill(id: String, cooldown: float, player := 0) -> void:
	var box: Control = skill_box if player == 0 else _skill_box2
	if box == null:
		return
	box.visible = id != "" and not sailing
	if id == "":
		return
	(box.get_node("VBox/SkillName") as Label).text = GameState.skill_name(id)
	var bar := box.get_node("VBox/Cooldown") as ProgressBar
	bar.value = 1.0 - clampf(cooldown, 0.0, 1.0)
	bar.modulate = Color(0.55, 1, 0.55) if cooldown <= 0.0 else Color(1, 1, 1, 0.8)


## "[E] Talk", "[E] Zarpar"... over the inventory (empty text hides it).
func set_interact_hint(text: String) -> void:
	interact_hint.visible = text != "" and not dialog_panel.visible
	if text != "":
		var key := tr("Tap “%s”") % text if touch_mode else "[%s] %s" % [Preferences.event_text("interact", false), text]
		interact_hint.text = key


## Big text in the middle of the screen ("Island complete!").
func show_banner(title: String, text: String, duration := 3.0) -> void:
	banner_title.text = title
	banner_text.text = text
	banner.visible = true
	banner.modulate.a = 0.0
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(banner, "modulate:a", 1.0, 0.3)
	_banner_tween.tween_interval(duration)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.6)
	_banner_tween.tween_callback(func(): banner.visible = false)


func set_boss_name(text: String) -> void:
	boss_name.text = text


## Texts with the keys (they change if the player changes the controls).
func _refresh_hints() -> void:
	var k := func(a: String) -> String: return Preferences.event_text(a, false)
	var hint := tr("%s move  ·  %s run  ·  %s jump/swim  ·  Click/%s punch  ·  %s talk  ·  %s map  ·  %s pause") % [
		k.call("move_forward") + k.call("move_left") + k.call("move_back") + k.call("move_right"), k.call("sprint"), k.call("jump"),
		k.call("attack"), k.call("interact"), k.call("map"), k.call("pause")]
	if sailing:
		hint = tr("%s/%s sail  ·  %s/%s helm  ·  %s full sail  ·  %s chart  ·  %s dock / let go") % [
			k.call("move_forward"), k.call("move_back"), k.call("move_left"), k.call("move_right"), k.call("sprint"), k.call("use_item"), k.call("interact")]
	controls_hint.text = tr(TOUCH_HINT) if touch_mode and not sailing else hint
	inventory_hint.text = tr("%s eat  ·  %s switch") % [k.call("use_item"), k.call("next_item")] if not touch_mode else ""
	skill_hint.text = tr("%s use  ·  %s switch  ·  %s shop") % [k.call("skill"), k.call("next_skill"), k.call("shop")] if not touch_mode else ""
	if _inventory2:
		# player 2 plays with a gamepad
		var g := func(a: String) -> String: return Preferences.event_text(a, true)
		(_inventory2.get_node("Hint") as Label).text = tr("%s eat  ·  %s switch") % [g.call("use_item"), g.call("next_item")]
		(_skill_box2.get_node("VBox/Hint") as Label).text = tr("%s use  ·  %s switch  ·  %s shop") % [g.call("skill"), g.call("next_skill"), g.call("shop")]


func set_mission(text: String) -> void:
	mission_label.text = text


func set_boss_health(current: float, maximum: float) -> void:
	boss_health_bar.max_value = maximum
	boss_health_bar.value = current
	boss_health_label.text = "%d / %d" % [int(ceil(current)), int(maximum)]


## Buggy's name, health and AI state (hidden until Koby gives the mission and after Buggy falls).
func set_boss_visible(on: bool) -> void:
	$Root/BossBox.visible = on


func set_boss_state(text: String) -> void:
	boss_state_label.text = tr("AI: ") + text


func set_touch_mode(on: bool) -> void:
	touch_mode = on
	_refresh_hints()


func show_message(text: String, duration: float = 2.0) -> void:
	message_label.text = text
	message_label.visible = true
	message_timer.start(duration)


func show_dialog(speaker: String, text: String, last: bool) -> void:
	dialog_panel.visible = true
	interact_hint.visible = false
	dialog_speaker.text = speaker
	dialog_text.text = text
	var key := tr("Tap “Next”") if touch_mode else tr("Press %s") % Preferences.event_text("interact", false)
	dialog_hint.text = key + (tr(" to close") if last else tr(" to continue"))


func hide_dialog() -> void:
	dialog_panel.visible = false


func is_dialog_open() -> bool:
	return dialog_panel.visible


## FPS counter (Opciones -> Mostrar FPS).
func _process(_delta: float) -> void:
	fps_label.visible = GraphicsSettings.show_fps
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func _on_message_timer_timeout() -> void:
	message_label.visible = false
