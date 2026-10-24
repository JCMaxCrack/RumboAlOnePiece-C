class_name IslandWorld
extends Node3D
## One island of the voyage (scenes/islands/*.tscn). The world scene (World, scenes/world.tscn)
## loads it at its place in the sea when the Going Merry gets close and frees it again when it is
## far; its progress lives in GameState.islands, so nothing is lost. What every island has:
##   - Koby, who gives the mission of the island, and the crew member who can be recruited there;
##   - the boss of the island, the mini enemies, the pickups and the checkpoints;
##   - the port (ShipDock: where the Going Merry is moored).
## The player, the crew, the HUD, the menus and the ship belong to the World: an island reaches
## them through `world` (hud, player, open_dialog(), save_game()...).
## The scripts of each island extend this one and fill the virtual functions marked "island:".
## Nodes needed: Collectibles, Checkpoints, Island/TerrainBody/CollisionShape3D, MiniEnemies.
## Optional: Koby, ChunkManager, PlayerStart, ShipDock.

enum Mission { NOT_GIVEN, ACTIVE, DONE }

## Id of the island (GameState.ISLANDS, SaveManager.ISLAND_SPECS).
@export var island_id := "isla_inicio"
## Crew member that joins in this island ("" = none). Its node has the same name, capitalized.
@export var recruit_member := ""
## false when the scene itself connects the boss signals (the first island does).
@export var connect_boss_signals := true
## Music while exploring the island.
@export var music: AudioStream

@onready var collectibles: Node3D = $Collectibles
@onready var checkpoints: Node3D = $Checkpoints
@onready var chunks: ChunkManager = get_node_or_null("ChunkManager")
@onready var terrain_shape: CollisionShape3D = $Island/TerrainBody/CollisionShape3D
@onready var koby: Koby = get_node_or_null("Koby")

## The World that loaded this island (set before it enters the tree).
var world: World
var hud: HUD:
	get:
		return world.hud
var player: Player:
	get:
		return world.player
## The boss of the island (BuggyBoss or Boss), set by the island in _island_ready().
var boss: Node3D
var mission: int = Mission.NOT_GIVEN
## The crew member of this island already joined.
var recruited := false
## Names of the pickups already taken (they are saved).
var collected_items: Array = []
## Things that happened in the island that the island script needs to remember (they are saved,
## SaveManager.ISLAND_SPECS lists the valid ones), e.g. "gate_open".
var flags: Array = []
var current_checkpoint := ""
var activated_checkpoints: Array = []


func _ready() -> void:
	var first: Checkpoint = checkpoints.get_child(0)
	current_checkpoint = first.checkpoint_id
	activated_checkpoints = [current_checkpoint]
	_island_ready()
	var st: Dictionary = GameState.islands.get(island_id, {})
	if not st.is_empty():
		_apply_island(st)
	# a crew member that a player plays is with the crew from the start: nobody recruits him
	if GameSession.is_played(recruit_member):
		recruited = true
	# the crew member of the island travels with Luffy once he joins: this copy is not needed
	var npc := recruit_node()
	if npc and (GameState.has_crew(recruit_member) or GameSession.is_played(recruit_member)):
		remove_child(npc)
		npc.queue_free()
	_connect_nodes()
	_refresh_checkpoints()
	if koby:
		koby.set_mission_given(mission >= Mission.ACTIVE)
		koby.set_prompt(tr("Tap “Talk”") if world.touch_controls.active else "[%s] %s" % [Preferences.event_text("interact", false), tr("Talk")])
	if chunks:
		chunks.target = player
		chunks.load_around(player.global_position)
	GameState.islands[island_id] = collect_island()


## The node of the crew member that joins here (null if there is none or he already left with Luffy).
func recruit_node() -> Player:
	if recruit_member == "":
		return null
	return get_node_or_null(recruit_member.capitalize()) as Player


## This island is the one where Luffy is now (its mission is shown in the HUD).
func is_current() -> bool:
	return world != null and world.current == self


# ------------------------------------------------------------------ island: virtual functions
## island: find its nodes (boss, NPCs...). Called before anything else.
func _island_ready() -> void:
	pass


## island: [[node, radius, prompt, callable], ...] that can be used with "interact" right now.
func _interactables() -> Array:
	var out := []
	if koby and koby.player_near:
		out.append([koby, 99.0, "Talk", _talk_to_koby])
	return out


## island: what Koby says (the mission, how it goes, or that it is done).
func _talk_to_koby() -> void:
	pass


## island: text of the mission in the HUD.
func _mission_text() -> String:
	return ""


## island: are all the goals of the mission done?
func _mission_goals_done() -> bool:
	return false


## island: the boss was defeated (besides the shared part: music, HUD, XP).
func _on_boss_down() -> void:
	pass


## island: restore its own nodes from a saved progress (after the shared part).
func _apply_island_extra(_st: Dictionary) -> void:
	pass


## island: message when Luffy arrives (loaded: a saved game was just loaded).
func arrival_message(loaded: bool) -> void:
	if loaded:
		hud.show_message(tr("Game %d loaded") % SaveManager.current_slot, 2.0)
	else:
		hud.show_banner(tr(GameState.ISLAND_NAMES[island_id]), tr("Talk to Koby to get your mission") if mission == Mission.NOT_GIVEN else "", 3.0)


## island: something was picked up.
func _on_item_taken(_item: Collectible) -> void:
	pass


## The island became the current one: its mission and its boss go to the HUD.
func activate() -> void:
	_update_mission_text()
	_update_boss_hud()
	hud.set_count(_meat_taken(), _meat_total())
	if boss:
		hud.set_boss_name(tr(boss.get("display_name")))
		hud.set_boss_health(boss.get("health"), boss.get("max_health"))


func open_dialog(speaker: String, lines: Array, on_done := Callable()) -> void:
	world.open_dialog(speaker, lines, on_done)


func save_game(slot: int) -> bool:
	return world.save_game(slot)


# ------------------------------------------------------------------ mission
func _update_mission_text() -> void:
	if is_current():
		hud.set_mission(_mission_text())


## Koby gave the mission.
func give_mission() -> void:
	if mission != Mission.NOT_GIVEN:
		return
	mission = Mission.ACTIVE
	if koby:
		koby.set_mission_given(true)
	hud.show_message(tr("New mission!"), 1.5)
	_update_mission_text()
	_update_boss_hud()
	check_mission()


## The crew member of this island joins: he follows Luffy from now on (also to other islands).
func recruit() -> void:
	if recruited:
		return
	recruited = true
	GameState.add_crew(recruit_member)
	world.give_xp(30)
	var npc := recruit_node()
	if npc:
		world.adopt_crew(recruit_member, npc)
	hud.show_message(tr("%s joined the crew!") % tr(recruit_member.capitalize()), 2.0)
	_update_mission_text()
	check_mission()


## Checks the goals; when they are all done the island is completed.
func check_mission() -> void:
	if mission == Mission.ACTIVE and _mission_goals_done():
		mission = Mission.DONE
		GameState.complete_island(island_id)
		world.give_xp(50)
		_update_mission_text()
		world.on_island_completed(self)


# ------------------------------------------------------------------ enemies and boss
func _connect_nodes() -> void:
	for e in find_children("*", "", true, false):
		if not e.is_in_group("enemies"):
			continue
		if e is MiniEnemy:
			if not (e as MiniEnemy).defeated.is_connected(_on_mini_defeated):
				(e as MiniEnemy).defeated.connect(_on_mini_defeated)
		elif e != boss and e.has_signal("defeated"):
			e.connect("defeated", func(): world.award_xp(e))
	if boss and connect_boss_signals:
		boss.connect("state_changed", _on_boss_state_changed)
		boss.connect("defeated", _on_boss_defeated)
		if boss.has_signal("taunt"):
			boss.connect("taunt", func(t: String): hud.show_message(tr(t), 1.4))
	if boss:
		boss.connect("health_changed", func(c: float, m: float): if is_current(): hud.set_boss_health(c, m))
	for c in collectibles.get_children():
		var item := c as Collectible
		if item == null:
			continue
		if not item.collected.is_connected(_on_item_collected):
			item.collected.connect(_on_item_collected)
		item.rejected.connect(func(_i): hud.show_message(tr("Inventory full! Eat something to make room (Q)"), 1.6))
	for cp in checkpoints.get_children():
		var c2 := cp as Checkpoint
		if not c2.reached.is_connected(_on_checkpoint_reached):
			c2.reached.connect(_on_checkpoint_reached)


func _on_mini_defeated(e: MiniEnemy) -> void:
	world.award_xp(e)


func _on_boss_state_changed(_new_state: int) -> void:
	if not is_node_ready() or not is_current():
		return
	hud.set_boss_state(tr(boss.call("state_text")) if boss.has_method("state_text") else "")
	if boss.call("is_defeated"):
		return
	var text: String = boss.call("state_text")
	var chasing := ["Chasing!", "He saw you!", "Attacking!", "Special attack!"].has(text)
	if chasing and not world.chase_music.playing:
		hud.show_message(tr("%s saw you!") % tr(boss.get("display_name")), 1.0)
		world.set_chase(true)
	elif not chasing and world.chase_music.playing and text == "Returning":
		hud.show_message(tr("You got away!"), 1.0)
		world.set_chase(false)
	_update_boss_hud()


func _on_boss_defeated() -> void:
	if not is_node_ready():
		return
	world.set_chase(false)
	world.award_xp(boss)
	hud.show_message(tr("You defeated %s!") % tr(boss.get("display_name")), 2.0)
	get_tree().create_timer(1.5).timeout.connect(_update_boss_hud)
	_update_mission_text()
	_on_boss_down()
	check_mission()


## The boss bar is shown while the mission is active, or while the boss is chasing.
func _update_boss_hud() -> void:
	if not is_inside_tree() or not is_current():
		return
	if boss == null:
		hud.set_boss_visible(false)
		return
	var fighting: bool = boss.has_method("state_text") and ["Chasing!", "He saw you!", "Attacking!", "Special attack!"].has(boss.call("state_text"))
	hud.set_boss_visible((mission == Mission.ACTIVE or fighting) and not boss.call("is_defeated"))


# ------------------------------------------------------------------ pickups
func _on_item_collected(item: Collectible) -> void:
	if not is_node_ready():
		return
	collected_items.append(str(item.name))
	hud.set_count(_meat_taken(), _meat_total())
	_update_mission_text()
	hud.show_message(tr("%s! Stored in the inventory (Q to eat)") % GameState.item_name(item.item_id) if GameState.ITEMS[item.item_id].heal > 0.0 else tr("%s!") % GameState.item_name(item.item_id), 1.4)
	_on_item_taken(item)
	check_mission()


func _meat_total() -> int:
	var n := 0
	for c in collectibles.get_children():
		# a taken pickup stays in the tree until its sound ends: it is already in _meat_taken()
		var item := c as Collectible
		if item and not item.taken and item.item_id == "meat":
			n += 1
	return n + _meat_taken()


func _meat_taken() -> int:
	var n := 0
	for name in collected_items:
		if str(name).begins_with("Meat"):
			n += 1
	return n


# ------------------------------------------------------------------ checkpoints and saving
func _on_checkpoint_reached(cp: Checkpoint) -> void:
	if world.finished or cp.checkpoint_id == current_checkpoint:
		return
	if not activated_checkpoints.has(cp.checkpoint_id):
		activated_checkpoints.append(cp.checkpoint_id)
	current_checkpoint = cp.checkpoint_id
	world.arrive_at(self)
	player.heal(player.max_health)
	cp.play_activate_sound()
	_refresh_checkpoints()
	var saved := SaveManager.current_slot > 0 and save_game(SaveManager.current_slot)
	hud.show_message(tr("Checkpoint: %s") % tr(cp.display_name) + ("  ·  " + tr("Game saved") if saved else ""), 2.0)


func _refresh_checkpoints() -> void:
	for cp in checkpoints.get_children():
		var c := cp as Checkpoint
		c.set_active(activated_checkpoints.has(c.checkpoint_id), c.checkpoint_id == current_checkpoint)


func _find_checkpoint(id: String) -> Checkpoint:
	for cp in checkpoints.get_children():
		if (cp as Checkpoint).checkpoint_id == id:
			return cp
	return null


## Where Luffy appears in this island: the current checkpoint, or the start of the island.
func spawn_position() -> Vector3:
	var cp := _find_checkpoint(current_checkpoint)
	if cp and GameState.islands.has(island_id) and activated_checkpoints.size() > 1:
		return on_ground(cp.spawn_transform().origin)
	var start := get_node_or_null("PlayerStart") as Node3D
	var p := start.global_position if start else (checkpoints.get_child(0) as Checkpoint).spawn_transform().origin
	return on_ground(p)


## Progress of this island (SaveManager validates it, see _valid_island()).
func collect_island() -> Dictionary:
	return {
		"mission": mission,
		"checkpoint": current_checkpoint,
		"checkpoints": activated_checkpoints.duplicate(),
		"items": collected_items.duplicate(),
		"boss_health": ceili(boss.get("health")) if boss else 0,
		"boss_defeated": boss.call("is_defeated") if boss else true,
		"recruited": recruited,
		"flags": flags.duplicate(),
	}


## Restores the progress of the island.
func _apply_island(st: Dictionary) -> void:
	mission = int(st.mission)
	for n in st.items:
		var it := collectibles.get_node_or_null(NodePath(str(n)))
		if it:
			collectibles.remove_child(it)
			it.queue_free()
	collected_items = (st.items as Array).duplicate()
	if boss:
		boss.call("restore", float(st.boss_health))
	recruited = bool(st.recruited)
	flags = (st.get("flags", []) as Array).duplicate()
	activated_checkpoints = (st.checkpoints as Array).duplicate()
	current_checkpoint = str(st.checkpoint)
	_apply_island_extra(st)


# ------------------------------------------------------------------ ground
## Height of the terrain at a point, read from its collision height map (it does not need the
## physics engine, so it also works in the first frame after loading). Outside the island it
## gives the height of its sea floor border.
## highest = true uses the highest corner of the cell: the result is never under the ground.
func ground_height(x: float, z: float, highest := false) -> float:
	var hm := terrain_shape.shape as HeightMapShape3D
	var xf := terrain_shape.global_transform
	var local := xf.affine_inverse() * Vector3(x, 0.0, z)
	var fx := clampf(local.x + (hm.map_width - 1) / 2.0, 0.0, hm.map_width - 1.001)
	var fz := clampf(local.z + (hm.map_depth - 1) / 2.0, 0.0, hm.map_depth - 1.001)
	var i := int(fz) * hm.map_width + int(fx)
	var h00 := hm.map_data[i]
	var h10 := hm.map_data[i + 1]
	var h01 := hm.map_data[i + hm.map_width]
	var h11 := hm.map_data[i + hm.map_width + 1]
	var h: float
	if highest:
		h = maxf(maxf(h00, h10), maxf(h01, h11))
	else:
		var tx := fx - int(fx)
		var tz := fz - int(fz)
		h = lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
	return (xf * Vector3(local.x, h, local.z)).y


## Is the point over the height map of this island?
func covers(x: float, z: float) -> bool:
	var hm := terrain_shape.shape as HeightMapShape3D
	var local := terrain_shape.global_transform.affine_inverse() * Vector3(x, 0.0, z)
	return absf(local.x) < (hm.map_width - 1) / 2.0 and absf(local.z) < (hm.map_depth - 1) / 2.0


## A point moved up onto the ground if it is under it (respawn points on slopes).
func on_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, maxf(p.y, ground_height(p.x, p.z, true) + 0.15), p.z)
