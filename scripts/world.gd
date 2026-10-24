class_name World
extends Node3D
## The voyage (scenes/world.tscn): one scene with the whole sea. There is no loading between the
## islands: the Going Merry is sailed from one to the other, like in How to Fish.
##   - The islands (IslandWorld, scenes/islands/*.tscn) are loaded at their place in the sea
##     (GameState.ISLAND_PLACES) when Luffy gets close and freed when he is far; their progress
##     stays in GameState.islands. Islands that are not open yet are hidden by a storm that turns
##     the ship back.
##   - At the helm of the Going Merry (on the stern deck) Luffy takes the wheel (Ship). Near a port
##     the ship can dock: that island becomes the current one and the game is saved.
##   - Sea fog: on open water the fog gets thick, so the next island is only seen when close. To
##     find it: the compass of the HUD (name and meters), its mark in the minimap and a column of
##     light over its port that is seen through the fog.
##   - Single player (Luffy) or local co-op (split screen, each player with his minimap and his
##     own character, inventory, level and skills: GameState.heroes). Player 1 is `player`,
##     player 2 is `player2`; Luffy, if nobody plays him, is a companion. The crew that already
##     joined follows player 1 everywhere.
##   - Dialogues, inventory, skills, experience, the skill shop, the navigation chart (to choose
##     where to go), saving and the end of the game.
## Nodes: Luffy, GoingMerry (Ship), Islands, Ocean, Sun, WorldEnvironment, HUD, TouchControls,
## PauseMenu, EndScreen, ExploreMusic, ChaseMusic, VictorySound, DefeatSound, DefeatTimer.

const CREW_SCENES := {"luffy": "res://scenes/player/luffy.tscn", "zoro": "res://scenes/player/zoro.tscn",
	"usopp": "res://scenes/player/usopp.tscn", "nami": "res://scenes/player/nami.tscn"}
const SKILL_SHOP_SCENE := "res://scenes/ui/skill_shop.tscn"
const SAIL_MENU_SCENE := "res://scenes/ui/sail_menu.tscn"
const OCEAN_SHADER := "res://assets/shaders/ocean.gdshader"
## An island is loaded when Luffy is closer than this to its shore, and freed when farther than
## the second distance.
const LOAD_DISTANCE := 520.0
const UNLOAD_DISTANCE := 760.0
## Distance to a port at which the ship can dock.
const DOCK_DISTANCE := 70.0
## Fog on the open sea (near the islands it is the one of the graphics preset).
const SEA_FOG := 0.012
## Storm around the islands that are not open yet: the ship can not get closer than this to its shore.
const STORM_MARGIN := 140.0

@onready var player: Player = $Luffy
@onready var ship: Ship = $GoingMerry
@onready var islands_root: Node3D = $Islands
@onready var ocean: MeshInstance3D = $Ocean
@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var hud: HUD = $HUD
@onready var touch_controls: TouchControls = $TouchControls
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var end_screen: EndScreen = $EndScreen
@onready var explore_music: AudioStreamPlayer = $ExploreMusic
@onready var chase_music: AudioStreamPlayer = $ChaseMusic
@onready var victory_sound: AudioStreamPlayer = $VictorySound
@onready var defeat_sound: AudioStreamPlayer = $DefeatSound
@onready var defeat_timer: Timer = $DefeatTimer

## Loaded islands: id -> IslandWorld.
var islands := {}
## The island where Luffy is (or where the ship docked last).
var current: IslandWorld
## Island the compass, the minimap and the light point to ("" = none).
var destination := ""
## Player 2 in co-op (null in single player).
var player2: Player
## Crew members in the world besides player 1 (player 2 too): "zoro" -> Player.
var crew_nodes := {}
var finished := false
var skill_shop: SkillShop
var sail_menu: SailMenu
var world_map: WorldMap
var _loading := {}  # id -> path being loaded in a thread
var _stream_timer := 0.0
var _dialog: PackedStringArray = []
var _dialog_line := 0
var _dialog_speaker := ""
var _dialog_done := Callable()
var _music_tween: Tween
var _split_viewports: Array[SubViewport] = []
var _split_follow: Array[RemoteTransform3D] = []
var _interact_target: Array = []
var _base_fog := 0.0016
var _beacon: Node3D
var _ocean_mat: ShaderMaterial


func _ready() -> void:
	get_tree().paused = false
	get_viewport().disable_3d = false
	add_to_group("world")
	_setup_heroes()
	skill_shop = (load(SKILL_SHOP_SCENE) as PackedScene).instantiate()
	add_child(skill_shop)
	skill_shop.closed.connect(_on_menu_closed)
	sail_menu = (load(SAIL_MENU_SCENE) as PackedScene).instantiate()
	add_child(sail_menu)
	sail_menu.closed.connect(_on_menu_closed)
	sail_menu.sail_requested.connect(set_destination)
	hud.set_touch_mode(touch_controls.active)
	hud.hide_dialog()
	hud.world = self
	hud.set_player(player)
	player.set_max_health(GameState.hero(0).max_health(), true)
	ship.can_sail = _can_sail
	ship.blocked.connect(_on_ship_blocked)
	world_map = WorldMap.new()
	world_map.name = "WorldMap"
	world_map.world = self
	add_child(world_map)
	_build_ocean()
	_build_beacon()
	var loaded := SaveManager.take_pending()
	var id := GameState.island
	if not GameState.unlocked.has(id):
		GameState.unlocked.append(id)
	ship.moor(GameState.dock_transform(id))
	_lower_gangway(id, false)
	current = _load_island_now(id)
	player.global_position = current.spawn_position()
	player.velocity = Vector3.ZERO
	if current.chunks:
		current.chunks.load_around(player.global_position)
	_setup_crew()
	_restore_health(player, GameState.hero(0))
	if player2:
		_restore_health(player2, GameState.hero(1))
	hud.set_health(player.health, player.max_health)
	player.health_changed.connect(hud.set_health)
	player.died.connect(_on_player_died)
	touch_controls.look_dragged.connect(player.look)
	pause_menu.save_requested.connect(_on_pause_menu_save_requested)
	defeat_timer.timeout.connect(_on_defeat_timer_timeout)
	explore_music.finished.connect(explore_music.play)
	chase_music.finished.connect(chase_music.play)
	for i in GameState.heroes.size():
		var h := GameState.hero(i)
		h.inventory_changed.connect(_on_inventory_changed.bind(i))
		h.xp_changed.connect(_on_xp_changed.bind(i))
		h.leveled_up.connect(_on_leveled_up.bind(i))
		h.skills_changed.connect(_on_skills_changed.bind(i))
	_apply_graphics()
	GraphicsSettings.changed.connect(_apply_graphics)
	destination = _default_destination()
	explore_music.stream = current.music
	explore_music.volume_db = -8.0
	explore_music.play()
	for i in GameState.heroes.size():
		_on_inventory_changed(i)
		_on_skills_changed(i)
	current.activate()
	if loaded.is_empty() and SaveManager.current_slot > 0:
		save_game(SaveManager.current_slot)
	current.arrival_message(not loaded.is_empty())


func _exit_tree() -> void:
	get_viewport().disable_3d = false
	_store_health()


# ------------------------------------------------------------------ islands
func _place(id: String) -> Dictionary:
	return GameState.ISLAND_PLACES[id]


## The big map shows what is on an island that is far: it is loaded now (and freed again when far).
func load_island(id: String) -> void:
	if GameState.unlocked.has(id) and not islands.has(id) and not _loading.has(id):
		_load_island_now(id)


func _load_island_now(id: String) -> IslandWorld:
	if islands.has(id):
		return islands[id]
	var scene := load(GameState.island_scene(id)) as PackedScene
	return _add_island(id, scene)


func _add_island(id: String, scene: PackedScene) -> IslandWorld:
	var isl := scene.instantiate() as IslandWorld
	isl.world = self
	isl.position = _place(id).offset
	islands[id] = isl
	islands_root.add_child(isl)
	return isl


## Loads (in a thread) the open islands near Luffy and frees the far ones.
func _stream_islands() -> void:
	var p := Vector2(player.global_position.x, player.global_position.z)
	for id in GameState.ISLANDS:
		var d := GameState.island_center(id).distance_to(p) - float(_place(id).radius)
		var open := GameState.unlocked.has(id)
		if open and d < LOAD_DISTANCE and not islands.has(id) and not _loading.has(id):
			var path := GameState.island_scene(id)
			ResourceLoader.load_threaded_request(path)
			_loading[id] = path
		elif islands.has(id) and d > UNLOAD_DISTANCE and islands[id] != current:
			var isl: IslandWorld = islands[id]
			GameState.islands[id] = isl.collect_island()
			islands.erase(id)
			isl.queue_free()
	for id in _loading.keys():
		var path: String = _loading[id]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_loading.erase(id)
			if not islands.has(id):
				_add_island(id, ResourceLoader.load_threaded_get(path) as PackedScene)
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_loading.erase(id)


## The island under Luffy's feet becomes the current one (walking or swimming to it also counts).
func _update_current() -> void:
	if ship.steering:
		return
	var p := player.global_position
	for id in islands:
		var isl: IslandWorld = islands[id]
		if isl != current and GameState.island_center(id).distance_to(Vector2(p.x, p.z)) < float(_place(id).radius) and isl.ground_height(p.x, p.z) > -2.0:
			arrive_at(isl)
			return


## Luffy is now in this island (he docked, walked to it or touched one of its checkpoints).
func arrive_at(isl: IslandWorld) -> void:
	if isl == current:
		return
	var first_time := not GameState.islands.has(isl.island_id) or isl.mission == IslandWorld.Mission.NOT_GIVEN
	current = isl
	GameState.island = isl.island_id
	if not GameState.unlocked.has(isl.island_id):
		GameState.unlocked.append(isl.island_id)
	isl.activate()
	if destination == isl.island_id:
		destination = _default_destination()
	if explore_music.stream != isl.music:
		explore_music.stream = isl.music
		explore_music.play()
	if first_time:
		isl.arrival_message(false)
	else:
		hud.show_message(tr(GameState.ISLAND_NAMES[isl.island_id]), 2.0)


## The island that the compass shows by default: the first open one that is not completed.
func _default_destination() -> String:
	for id in GameState.ISLANDS:
		if GameState.unlocked.has(id) and not GameState.completed.has(id) and (current == null or id != current.island_id):
			return id
	return ""


func set_destination(id: String) -> void:
	destination = id
	hud.show_banner(tr("Heading to %s") % tr(GameState.ISLAND_NAMES[id]), tr("Follow the compass and the light over its port"), 2.5)


# ------------------------------------------------------------------ crew and co-op
## Player 1's character takes the place of Luffy (who is in the scene); then Luffy sails with the
## crew: as player 2 or as a companion.
func _setup_heroes() -> void:
	var first := GameState.hero(0).character
	if first == "luffy":
		return
	var luffy := player
	player = (load(CREW_SCENES[first]) as PackedScene).instantiate() as Player
	player.name = first.capitalize()
	player.control = Player.Controller.PLAYER_ONE
	add_child(player)
	player.global_transform = luffy.global_transform
	for label in ["NameLabel", "PromptLabel"]:
		var l := player.get_node_or_null(label) as Node3D
		if l:
			l.visible = false
	luffy.control = Player.Controller.AI
	luffy.remove_from_group("player")
	var ai := CompanionAI.new()
	ai.name = "CompanionAI"
	luffy.add_child(ai)
	crew_nodes["luffy"] = luffy


## The character of player 2 ("" in single player).
func _p2_character() -> String:
	return GameState.hero(1).character if GameState.heroes.size() > 1 else ""


## The characters on screen: player 1, then player 2 (if there is one).
func hero_node(i: int) -> Player:
	return player if i == 0 else player2


func _restore_health(p: Player, h: HeroProgress) -> void:
	p.set_max_health(h.max_health(), true)
	if h.health > 0.0:
		p.health = minf(h.health, p.max_health)
		p.health_changed.emit(p.health, p.max_health)


## The health of the players is kept in their HeroProgress (it is saved and goes between scenes).
func _store_health() -> void:
	for i in GameState.heroes.size():
		var p := hero_node(i)
		GameState.hero(i).health = p.health if is_instance_valid(p) and not p.dead else 0.0


func _setup_crew() -> void:
	if crew_nodes.has("luffy") and crew_nodes.luffy.get_parent() == self:
		var luffy: Player = crew_nodes.luffy
		crew_nodes.erase("luffy")
		luffy.global_position = current.on_ground(player.global_position - player.facing * 2.0)
		_add_crew_node("luffy", luffy)
	for member in GameState.CREW:
		var wanted: bool = GameState.has_crew(member) or member == _p2_character()
		if not wanted or crew_nodes.has(member):
			continue
		var node := (load(CREW_SCENES[member]) as PackedScene).instantiate() as Player
		node.name = member.capitalize()
		add_child(node)
		node.global_position = current.on_ground(player.global_position - player.facing * (2.0 + crew_nodes.size()) + Vector3(1.2 * crew_nodes.size(), 0.3, 0))
		_add_crew_node(member, node)
	player2 = crew_nodes.get(_p2_character()) as Player
	if player2:
		player2.global_position = player.global_position + Vector3(1.6, 0.3, 0.8)
		touch_controls.active = false
		_setup_split_screen()
	_update_crew()


func _add_crew_node(member: String, node: Player) -> void:
	crew_nodes[member] = node
	var ai := node.get_node_or_null("CompanionAI") as CompanionAI
	if ai:
		ai.leader = player
		ai.slot = crew_nodes.size() - 1
	if not node.died.is_connected(_on_crew_died):
		node.died.connect(_on_crew_died.bind(node))


## The crew member of an island joined: he leaves the island (so he is not freed with it).
func adopt_crew(member: String, node: Player) -> void:
	if node.get_parent() != self:
		node.reparent(self)
	_add_crew_node(member, node)
	_update_crew()


## Who follows player 1 and who is player 2.
func _update_crew() -> void:
	for member in crew_nodes:
		var p: Player = crew_nodes[member]
		if member == _p2_character():
			p.control = Player.Controller.PLAYER_TWO
		else:
			p.control = Player.Controller.AI
		var label := p.get_node_or_null("NameLabel") as Label3D
		if label:
			label.visible = false
		var prompt := p.get_node_or_null("PromptLabel") as Label3D
		if prompt:
			prompt.visible = false
		if p.global_position.distance_to(player.global_position) > 25.0 and not ship.steering:
			p.global_position = current.on_ground(player.global_position - player.facing * 2.5)
	# the second panel: player 2, or Zoro when he is a companion
	var second := player2 if player2 else crew_nodes.get("zoro") as Player
	for p in [player] + crew_nodes.values():
		var pl := p as Player
		if pl != second and pl.health_changed.is_connected(hud.set_health2):
			pl.health_changed.disconnect(hud.set_health2)
	hud.set_player2_visible(second != null)
	hud.set_names(player.display_name, second.display_name if second else "")
	if second:
		if not second.health_changed.is_connected(hud.set_health2):
			second.health_changed.connect(hud.set_health2)
		second.health_changed.emit(second.health, second.max_health)


## Co-op: two views side by side, each one following the camera of its player.
func _setup_split_screen() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SplitScreen"
	layer.layer = -1
	add_child(layer)
	var box := HBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(box)
	for p in [player, player2]:
		var container := SubViewportContainer.new()
		container.stretch = true
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(container)
		var vp := SubViewport.new()
		vp.world_3d = get_viewport().find_world_3d()
		vp.audio_listener_enable_3d = p == player
		container.add_child(vp)
		_split_viewports.append(vp)
		var cam := Camera3D.new()
		vp.add_child(cam)
		cam.current = true
		var follow := RemoteTransform3D.new()
		follow.name = "SplitScreenCamera"
		_split_follow.append(follow)
		_follow_camera(follow, (p as Player).camera, cam)
	get_viewport().disable_3d = true
	hud.set_split(true, player2)


## Moves the RemoteTransform of a split view under another camera (the player's or the ship's).
func _follow_camera(follow: RemoteTransform3D, source: Camera3D, view_cam: Camera3D = null) -> void:
	var cam := view_cam if view_cam else follow.get_node(follow.remote_path) as Camera3D
	if follow.get_parent():
		follow.get_parent().remove_child(follow)
	source.add_child(follow)
	follow.remote_path = follow.get_path_to(cam)
	cam.fov = source.fov
	cam.far = source.far


## The camera that player 1 is looking through.
func view_camera() -> Camera3D:
	if ship.steering:
		return ship.camera
	return player.camera


## A crew member fell (player 2 or companion): he comes back next to Luffy after a moment.
func _on_crew_died(p: Player) -> void:
	if finished:
		return
	hud.show_message(tr("%s fell! Back in a moment") % p.display_name, 1.5)
	await get_tree().create_timer(3.0).timeout
	if is_inside_tree() and not finished and is_instance_valid(p):
		p.revive(current.on_ground(player.global_position - player.facing * 2.0))


# ------------------------------------------------------------------ frame and input
func _process(delta: float) -> void:
	if not finished and not get_tree().paused:
		GameState.play_time += delta
	_stream_timer -= delta
	if _stream_timer <= 0.0:
		_stream_timer = 0.5
		_stream_islands()
		_update_current()
	_keep_above_ground()
	_update_interact_target()
	_update_sea(delta)
	for i in GameState.heroes.size():
		var eq := GameState.hero(i).equipped
		var spec := GameState.skill_spec(eq)
		hud.set_skill(eq, hero_node(i).skill_cooldown(eq) / maxf(0.01, float(spec.get("cooldown", 1.0))), i)
	if DisplayServer.get_name() == "headless" or touch_controls.active:
		return
	var free_mouse := get_tree().paused or finished
	var want := Input.MOUSE_MODE_VISIBLE if free_mouse else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != want:
		Input.mouse_mode = want


## Things that can be used with "interact" right now: those of the island and the helm.
func _interactables() -> Array:
	var out: Array = current._interactables() if current else []
	if not ship.steering and not ship.is_docking() and not player.dead:
		out.append([ship.get_node("Helm"), 2.8, "Take the helm", take_helm])
	return out


func _update_interact_target() -> void:
	var best: Array = []
	var label := ""
	if ship.steering:
		var port := _port_near()
		label = tr("Dock at %s") % tr(GameState.ISLAND_NAMES[port]) if port != "" else tr("Let go of the helm")
		if ship.is_docking():
			label = ""
	elif not hud.is_dialog_open() and not finished and not player.dead:
		best = _interactable_near(player)
		label = tr(best[2]) if not best.is_empty() else ""
	_interact_target = best
	hud.set_interact_hint(label)
	touch_controls.set_interact_visible(hud.is_dialog_open() or label != "", tr("Next") if hud.is_dialog_open() else (label if label != "" else tr("Talk")))


## The closest thing that this player can use with "interact" ([] = none).
func _interactable_near(p: Player) -> Array:
	var best: Array = []
	var best_d := INF
	for it in _interactables():
		var n := it[0] as Node3D
		if n == null or not is_instance_valid(n) or not n.is_visible_in_tree():
			continue
		var d := n.global_position.distance_to(p.global_position)
		if d < float(it[1]) and d < best_d:
			best = it
			best_d = d
	return best


func _unhandled_input(event: InputEvent) -> void:
	if finished:
		return
	var p2 := player2 != null
	if event.is_action_pressed("pause") or (p2 and event.is_action_pressed("p2_pause")):
		pause_menu.can_save = not player.dead
		pause_menu.toggle()
		return
	if event.is_action_pressed("map") or (p2 and event.is_action_pressed("p2_map")):
		world_map.open()
		return
	if ship.steering:
		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			ship.look((event as InputEventMouseMotion).relative)
		elif event.is_action_pressed("interact") and not ship.is_docking():
			_ship_interact()
		elif event.is_action_pressed("use_item") and not ship.is_docking():
			sail_menu.open(current.island_id if current else "")
		return
	if event.is_action_pressed("interact") or (p2 and event.is_action_pressed("p2_interact")):
		if hud.is_dialog_open():
			_next_dialog_line()
			return
		var target := _interact_target if event.is_action_pressed("interact") else _interactable_near(player2)
		if not target.is_empty() and not (target[0] == ship.get_node("Helm") and not event.is_action_pressed("interact")):
			(target[3] as Callable).call()
		return
	if hud.is_dialog_open():
		return
	for i in GameState.heroes.size():
		var pre := "p2_" if i == 1 else ""
		if event.is_action_pressed(pre + "use_item"):
			_use_selected_item(i)
		elif event.is_action_pressed(pre + "next_item"):
			GameState.hero(i).select_next()
		elif event.is_action_pressed(pre + "skill"):
			_use_skill(i)
		elif event.is_action_pressed(pre + "next_skill"):
			var h := GameState.hero(i)
			h.equip_next()
			if h.equipped != "":
				hud.show_message(GameState.skill_name(h.equipped), 1.0)
		elif event.is_action_pressed(pre + "shop"):
			open_skill_shop(i)
		else:
			continue
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_4:
			GameState.hero(0).select_slot(k - KEY_1)


## Eats the food of the selected slot of player i's inventory.
func _use_selected_item(i := 0) -> void:
	var h := GameState.hero(i)
	var p := hero_node(i)
	var id := h.selected_item()
	if id == "":
		hud.show_message(tr("You have nothing in that slot"), 1.2)
		return
	var heal: float = GameState.ITEMS[id].heal
	if heal <= 0.0:
		hud.show_message(tr("%s: it's used somewhere else") % GameState.item_name(id), 1.5)
		return
	if p.health >= p.max_health:
		hud.show_message(tr("Your health is already full"), 1.2)
		return
	if p.eat(id, heal):
		h.remove_item(id)


func _use_skill(i := 0) -> void:
	var h := GameState.hero(i)
	var p := hero_node(i)
	if h.equipped == "":
		hud.show_message(tr("Learn attacks in the skill shop (%s)") % Preferences.event_text("shop", i == 1), 1.8)
		return
	if not p.use_skill(h.equipped, h.level):
		var cd := p.skill_cooldown(h.equipped)
		if cd > 0.0:
			hud.show_message(tr("%s: wait %.1f s") % [GameState.skill_name(h.equipped), cd], 0.9)


func open_skill_shop(i := 0) -> void:
	if finished or hero_node(i).dead or get_tree().paused:
		return
	skill_shop.open(GameState.hero(i))


func _on_menu_closed() -> void:
	if not skill_shop.visible and not sail_menu.visible and not pause_menu.visible:
		get_tree().paused = false


# ------------------------------------------------------------------ dialogues
## Shows lines in the HUD; on_done is called after the last one.
func open_dialog(speaker: String, lines: Array, on_done := Callable()) -> void:
	_dialog = PackedStringArray(lines.map(func(l): return tr(l)))
	_dialog_speaker = speaker
	_dialog_done = on_done
	_dialog_line = 0
	for p in [player] + crew_nodes.values():
		(p as Player).controls_enabled = false
	hud.show_dialog(speaker, _dialog[0], _dialog.size() == 1)


func _next_dialog_line() -> void:
	_dialog_line += 1
	if _dialog_line < _dialog.size():
		hud.show_dialog(_dialog_speaker, _dialog[_dialog_line], _dialog_line == _dialog.size() - 1)
		return
	hud.hide_dialog()
	for p in [player] + crew_nodes.values():
		(p as Player).controls_enabled = true
	if _dialog_done.is_valid():
		var done := _dialog_done
		_dialog_done = Callable()
		done.call()


# ------------------------------------------------------------------ sailing
## Luffy takes the wheel of the Going Merry: the crew sails with him.
func take_helm() -> void:
	if ship.steering or player.dead or finished:
		return
	ship.take_helm(player, crew_nodes.values())
	ship.set_gangway(false, 1.0, 0.0)
	if _split_follow.is_empty():
		ship.camera.current = true
	else:
		_follow_camera(_split_follow[0], ship.camera)
	ship.camera.far = player.camera.far
	hud.set_sailing(true)
	var where := tr(GameState.ISLAND_NAMES[destination]) if destination != "" else tr("open sea")
	hud.show_banner(tr("Set sail!"), tr("Heading to %s  ·  %s navigation chart") % [where, Preferences.event_text("use_item", false)], 3.0)


func _leave_helm() -> void:
	ship.leave_helm()
	_restore_camera()


func _restore_camera() -> void:
	if _split_follow.is_empty():
		player.camera.current = true
	else:
		_follow_camera(_split_follow[0], player.camera)
	hud.set_sailing(false)


func _ship_interact() -> void:
	var port := _port_near()
	if port == "":
		_leave_helm()
		hud.show_message(tr("You let go of the helm: the Going Merry is anchored"), 1.8)
		return
	if not islands.has(port):
		_load_island_now(port)
	hud.show_message(tr("Docking at %s...") % tr(GameState.ISLAND_NAMES[port]), 2.0)
	ship.dock(GameState.dock_transform(port), _on_docked.bind(port))


func _lower_gangway(id: String, animate := true) -> void:
	var place := _place(id)
	ship.set_gangway(true, float(place.gangway_side), float(place.gangway_drop), animate)


func _on_docked(id: String) -> void:
	_lower_gangway(id)
	_restore_camera()
	var isl := _load_island_now(id)
	var was := current
	arrive_at(isl)
	if was == isl:
		hud.show_message(tr("Back in %s") % tr(GameState.ISLAND_NAMES[id]), 2.0)
	if SaveManager.current_slot > 0 and save_game(SaveManager.current_slot):
		hud.show_message(tr("Game saved"), 1.5)


## The open island whose port is close to the ship ("" = none).
func _port_near() -> String:
	var p := ship.global_position
	for id in GameState.ISLANDS:
		if not GameState.unlocked.has(id):
			continue
		var dock := GameState.dock_transform(id).origin
		if Vector2(dock.x - p.x, dock.z - p.z).length() < DOCK_DISTANCE:
			return id
	return ""


## Can the hull be at this point of the sea? ("" = yes, or the reason why not).
func _can_sail(p: Vector3) -> String:
	if not GameState.SEA_RECT.has_point(Vector2(p.x, p.z)):
		return "border"
	for id in GameState.ISLANDS:
		var d := GameState.island_center(id).distance_to(Vector2(p.x, p.z)) - float(_place(id).radius)
		if not GameState.unlocked.has(id) and d < STORM_MARGIN:
			return "locked:" + id
		if islands.has(id) and d < 60.0:
			var isl: IslandWorld = islands[id]
			if isl.covers(p.x, p.z) and isl.ground_height(p.x, p.z) > -1.4:
				return "land"
	return ""


func _on_ship_blocked(reason: String) -> void:
	if reason == "land":
		hud.show_message(tr("Watch out for the coast! Find the port to dock"), 2.0)
	elif reason == "border":
		hud.show_message(tr("Beyond here the sea is too dangerous: turn back"), 2.0)
	elif reason.begins_with("locked:"):
		var id := reason.substr(7)
		var before: String = GameState.ISLANDS[GameState.island_index(id) - 1]
		hud.show_message(tr("A storm surrounds %s. Complete %s first") % [tr(GameState.ISLAND_NAMES[id]), tr(GameState.ISLAND_NAMES[before])], 2.6)


# ------------------------------------------------------------------ sea, fog, compass and light
func _build_ocean() -> void:
	_ocean_mat = ShaderMaterial.new()
	_ocean_mat.shader = load(OCEAN_SHADER)
	var i := 0
	for id in GameState.ISLANDS:
		var place := _place(id)
		_ocean_mat.set_shader_parameter("shore%d" % i, load(place.shore))
		_ocean_mat.set_shader_parameter("rect%d" % i, Vector4(place.offset.x, place.offset.z, place.size, place.size))
		i += 1
	var plane := PlaneMesh.new()
	plane.size = Vector2(3000, 3000)
	plane.subdivide_width = 200
	plane.subdivide_depth = 200
	plane.material = _ocean_mat
	ocean.mesh = plane
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_beacon() -> void:
	_beacon = Node3D.new()
	_beacon.name = "Beacon"
	add_child(_beacon)
	for layer in [[6.0, 0.18], [2.2, 0.45]]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(1.0, 0.82, 0.35, float(layer[1]))
		m.disable_fog = true
		var cyl := CylinderMesh.new()
		cyl.top_radius = float(layer[0]) * 0.6
		cyl.bottom_radius = float(layer[0])
		cyl.height = 320.0
		cyl.radial_segments = 16
		cyl.cap_top = false
		cyl.cap_bottom = false
		cyl.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = 160.0
		_beacon.add_child(mi)
	_beacon.visible = false


func _update_sea(_delta: float) -> void:
	var cam := view_camera()
	if cam == null:
		return
	var c := cam.global_position
	# the sea follows the camera (on a grid, so the waves do not slide)
	ocean.global_position = Vector3(snappedf(c.x, 15.0), 0.0, snappedf(c.z, 15.0))
	# thick fog on the open sea
	var near: Array = GameState.nearest_island(c)
	var k := clampf((float(near[1]) - 80.0) / 260.0, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	world_environment.environment.fog_density = lerpf(_base_fog, SEA_FOG, k)
	# compass and light over the port of the destination
	var show := destination != "" and not finished
	var dock := GameState.dock_transform(destination).origin if destination != "" else Vector3.ZERO
	var to := Vector2(dock.x - c.x, dock.z - c.z)
	if show and current and current.island_id == destination and not ship.steering:
		show = false
	_beacon.visible = show
	if show:
		var far := cam.far * 0.85
		var dist := to.length()
		var s := 1.0
		var at := Vector2(dock.x, dock.z)
		if dist > far:
			s = far / dist
			at = Vector2(c.x, c.z) + to / dist * far
		_beacon.global_transform = Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3(at.x, 0.0, at.y))
		var fwd := -cam.global_basis.z
		var f2 := Vector2(fwd.x, fwd.z).normalized()
		var angle := f2.angle_to(to.normalized())
		hud.set_compass(true, angle, tr(GameState.ISLAND_NAMES[destination]), dist)
	else:
		hud.set_compass(false, 0.0, "", 0.0)


# ------------------------------------------------------------------ experience, music, boss
## An enemy fell: its experience goes to every player (doubled in co-op, GameState.give_xp()).
func award_xp(e: Node) -> void:
	var amount := give_xp(int(e.get("xp_reward")) if e.get("xp_reward") != null else 10)
	if is_instance_valid(e) and e is Node3D:
		FX.text(self, (e as Node3D).global_position + Vector3(0, 2.2, 0), "+%d XP" % amount, Color(0.6, 0.9, 1.0), 44)


## Experience for the players (enemies, recruits, missions). Returns what each one got.
func give_xp(amount: int) -> int:
	return GameState.give_xp(amount)


func _on_xp_changed(level: int, xp: int, needed: int, i: int) -> void:
	hud.set_xp(level, xp, needed, GameState.hero(i).skill_points, i)


func _on_leveled_up(level: int, i: int) -> void:
	var h := GameState.hero(i)
	var p := hero_node(i)
	p.set_max_health(h.max_health(), true)
	FX.level_up(self, p.global_position)
	FX.text(self, p.global_position + Vector3(0, 2.4, 0), tr("Level %d!") % level, Color(1, 0.85, 0.3), 64, 1.6)
	var shop := Preferences.event_text("shop", i == 1)
	if player2:
		hud.show_message(tr("%s reached level %d! %d skill point(s): open the shop (%s)") % [p.display_name, level, h.skill_points, shop], 3.0)
	else:
		hud.show_message(tr("You reached level %d! You have %d skill point(s): open the shop (%s)") % [level, h.skill_points, shop], 3.0)
	_on_skills_changed(i)


func _on_skills_changed(i: int) -> void:
	var h := GameState.hero(i)
	hud.set_xp(h.level, h.xp, h.xp_needed(), h.skill_points, i)


func _on_inventory_changed(i: int) -> void:
	var h := GameState.hero(i)
	hud.set_inventory(h.inventory, h.selected_slot, i)


## Chase music while a boss runs after Luffy.
func set_chase(on: bool) -> void:
	if on:
		_crossfade(chase_music, explore_music)
	else:
		_crossfade(explore_music, chase_music)


func _crossfade(to_player: AudioStreamPlayer, from_player: AudioStreamPlayer) -> void:
	if _music_tween:
		_music_tween.kill()
	if not to_player.playing:
		to_player.volume_db = -40.0
		to_player.play()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(to_player, "volume_db", -8.0, 1.0)
	_music_tween.tween_property(from_player, "volume_db", -40.0, 1.0)
	_music_tween.chain().tween_callback(from_player.stop)


## The mission of an island was completed.
func on_island_completed(isl: IslandWorld) -> void:
	if GameState.is_last_island(isl.island_id):
		_finish(true)
		return
	victory_sound.play()
	var nxt := GameState.next_island(isl.island_id)
	destination = nxt
	hud.show_banner(tr("Island complete!"), tr("Board the Going Merry and take the helm to sail to %s") % tr(GameState.ISLAND_NAMES[nxt]), 6.0)
	if SaveManager.current_slot > 0:
		save_game(SaveManager.current_slot)


func _on_player_died() -> void:
	if finished:
		return
	hud.show_message(tr("You were defeated!"), 1.5)
	defeat_timer.start()


func _on_defeat_timer_timeout() -> void:
	_finish(false)


func _finish(won: bool) -> void:
	finished = true
	player.controls_enabled = false
	touch_controls.game_running = false
	hud.hide_dialog()
	explore_music.stop()
	chase_music.stop()
	if won:
		victory_sound.play()
	else:
		defeat_sound.play()
	if won and SaveManager.current_slot > 0:
		SaveManager.write_slot(SaveManager.current_slot, collect_state(true))
	var boss_down: bool = current.boss != null and current.boss.call("is_defeated")
	end_screen.show_result(won, GameState.play_time, current._meat_taken(), current._meat_total(), boss_down)
	get_tree().paused = true


# ------------------------------------------------------------------ graphics
func _apply_graphics() -> void:
	GraphicsSettings.apply_world(world_environment.environment, sun, player.camera, current.chunks if current else null)
	_base_fog = world_environment.environment.fog_density
	ship.camera.far = player.camera.far
	var root := get_viewport()
	for vp in _split_viewports:
		vp.msaa_3d = root.msaa_3d
		vp.screen_space_aa = root.screen_space_aa
		vp.scaling_3d_mode = root.scaling_3d_mode
		vp.scaling_3d_scale = root.scaling_3d_scale
		vp.mesh_lod_threshold = root.mesh_lod_threshold
		vp.use_occlusion_culling = root.use_occlusion_culling
		var cam := vp.get_camera_3d()
		if cam:
			cam.far = player.camera.far
			cam.fov = player.camera.fov
	if player2:
		player2.camera.far = player.camera.far


# ------------------------------------------------------------------ saving
## Everything that is saved in a slot.
func collect_state(completed := false) -> Dictionary:
	for id in islands:
		GameState.islands[id] = (islands[id] as IslandWorld).collect_island()
	_store_health()
	var heroes := GameState.collect_heroes()
	for i in heroes.size():
		var p := hero_node(i)
		heroes[i].health = clampi(ceili(p.health), 1, int(p.max_health))
	return {
		"play_time": int(GameState.play_time),
		"completed": completed,
		"island": current.island_id,
		"voyage": GameState.collect(),
		"heroes": heroes,
		"islands": GameState.islands.duplicate(true),
	}


func save_game(slot: int) -> bool:
	if player.dead or finished:
		return false
	var ok := SaveManager.write_slot(slot, collect_state())
	if ok:
		SaveManager.current_slot = slot
	return ok


## Pause menu -> "Save game" -> a slot.
func _on_pause_menu_save_requested(slot: int) -> void:
	var ok := save_game(slot)
	pause_menu.show_saved(slot, ok)


# ------------------------------------------------------------------ ground
## The terrain collision only stops things from above: if Luffy ever ends under the island,
## he is put back on the ground.
func _keep_above_ground() -> void:
	if ship.steering or current == null:
		return
	var p := player.global_position
	# nobody swims out of the sea of the voyage
	var sea: Rect2 = GameState.SEA_RECT
	if not sea.has_point(Vector2(p.x, p.z)):
		var q := Vector2(clampf(p.x, sea.position.x + 1.0, sea.end.x - 1.0), clampf(p.z, sea.position.y + 1.0, sea.end.y - 1.0))
		player.global_position = Vector3(q.x, p.y, q.y)
	if not current.covers(p.x, p.z):
		return
	var g := current.ground_height(p.x, p.z)
	if p.y < g - 1.5:
		player.global_position = Vector3(p.x, g + 0.3, p.z)
		player.velocity = Vector3.ZERO
