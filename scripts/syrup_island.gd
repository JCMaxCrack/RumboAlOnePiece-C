extends IslandWorld
## Second island, Villa Syrup (scenes/islands/villa_syrup.tscn). See IslandWorld for the shared part.
## The Going Merry docks at the port of the south, where Koby waits for Luffy. Koby gives the
## mission: Usopp, a boy of the village, says that Klahadore, the butler of the mansion on the
## north plateau, is in fact Captain Kuro, who wants to attack the village. Nobody believes him.
##   1. take the key of the mansion from the crypt of the old graveyard of the east (skeletons!);
##   2. open the gate of the mansion's wall with it (interact at the gate);
##   3. defeat Captain Kuro, who patrols the halls inside the mansion (if he sees Luffy he chases him);
##   4. talk to Usopp, on the hill over the village: he joins the crew.
## Skeletons and evil mushrooms guard the graveyard, the forest and the roads.

@onready var gate: Node3D = $Mansion/Gate

var usopp: Player
var _gate_tween: Tween


func _island_ready() -> void:
	boss = $Kuro
	recruit_member = "usopp"
	music = load("res://assets/audio/music_villa_syrup.wav")
	usopp = recruit_node()
	if usopp:
		usopp.control = Player.Controller.NONE


func _apply_island_extra(_st: Dictionary) -> void:
	if gate_open():
		_set_gate_open(false)


func arrival_message(loaded: bool) -> void:
	if loaded:
		super(loaded)
	elif mission == Mission.NOT_GIVEN:
		hud.show_banner(tr("Syrup Village"), tr("Koby is waiting for you at the port"), 3.0)
	else:
		hud.show_message(tr("Syrup Village"), 2.0)


func gate_open() -> bool:
	return flags.has("gate_open")


func _interactables() -> Array:
	var out := super()
	if _usopp_here():
		out.append([usopp, 3.4, "Talk", _talk_to_usopp])
	if not gate_open():
		out.append([gate, 4.5, "Open the gate", _try_gate])
	return out


func _usopp_here() -> bool:
	return is_instance_valid(usopp) and usopp.get_parent() == self and not recruited


func _process(_delta: float) -> void:
	if _usopp_here():
		var label := usopp.get_node_or_null("PromptLabel") as Label3D
		if label:
			label.visible = not hud.is_dialog_open() and usopp.global_position.distance_to(player.global_position) < 3.4


# ------------------------------------------------------------------ Koby, Usopp and the mission
func _talk_to_koby() -> void:
	match mission:
		Mission.NOT_GIVEN:
			open_dialog("Koby", [
				"Luffy-san! I got here before you on a Marine ship. Listen, this village is in danger.",
				"A boy from here, Usopp, says that Klahadore, the butler of the north mansion, is really Captain Kuro.",
				"Nobody believes him because he always tells lies... but I think this time he's telling the truth.",
				"The mansion gate is locked. The key is in the crypt of the old east graveyard, full of skeletons.",
				"Your mission: get the key, go into the mansion and defeat Kuro. They say he walks its halls without a sound.",
				"Usopp lives on the west hill, above the village. He'll surely want to go with you once Kuro falls!",
			], give_mission)
		Mission.ACTIVE:
			open_dialog("Koby", [_progress_line()])
		_:
			open_dialog("Koby", ["The village is safe thanks to you, Luffy-san!", "The next island is Whisky Peak. Take the Going Merry's helm: I'll see you there!"])


func _talk_to_usopp() -> void:
	if mission == Mission.NOT_GIVEN:
		open_dialog("Usopp", [
			"Stop right there! I'm the great Captain Usopp, with 8000 men under my command!",
			"...Well, no. But you have to believe me: the mansion's butler is Captain Kuro! Talk to that Marine boy at the port.",
		])
	elif boss.is_defeated():
		open_dialog("Usopp", [
			"You did it! Kuro is defeated and the village is safe!",
			"I always wanted to be a brave warrior of the sea... Captain Luffy, the great Usopp joins your crew!",
		], recruit)
	else:
		open_dialog("Usopp", ["Kuro is still in the mansion! I... I'll guard the village from here. Be careful!"])


func _progress_line() -> String:
	if not collected_items.has("KeyChest"):
		return tr("The key is in the crypt of the old east graveyard. Watch out for the skeletons!")
	if not gate_open():
		return tr("You have the key! Use it on the mansion gate, on the north plateau.")
	if not boss.is_defeated():
		return tr("Kuro is inside the mansion. Search the halls and corridors... be careful!")
	return tr("Kuro has fallen! Usopp is waiting for you on the west hill.")


func _try_gate() -> void:
	if not GameState.party_take("key", 1):
		open_dialog(tr("Mansion gate"), ["The gate is locked."])
		return
	flags.append("gate_open")
	_set_gate_open(true)
	hud.show_message(tr("The mansion gate is open!"), 2.0)
	_update_mission_text()
	if SaveManager.current_slot > 0:
		save_game(SaveManager.current_slot)


func _set_gate_open(animate: bool) -> void:
	var left := gate.get_node("Left") as Node3D
	var right := gate.get_node("Right") as Node3D
	for body in gate.find_children("*", "CollisionShape3D", true, false):
		(body as CollisionShape3D).set_deferred("disabled", true)
	if _gate_tween:
		_gate_tween.kill()
	if animate:
		_gate_tween = create_tween().set_parallel(true)
		_gate_tween.tween_property(left, "rotation:y", deg_to_rad(-100), 1.2)
		_gate_tween.tween_property(right, "rotation:y", deg_to_rad(100), 1.2)
	else:
		left.rotation.y = deg_to_rad(-100)
		right.rotation.y = deg_to_rad(100)


func _mission_text() -> String:
	if mission == Mission.NOT_GIVEN:
		return tr("Talk to Koby at the port")
	if mission == Mission.DONE:
		return tr("Island complete!") + "\n" + tr("Take the Going Merry's helm and sail to Whisky Peak")
	var m := func(done: bool) -> String: return "[X]" if done else "[  ]"
	var text := "%s %s\n%s %s\n%s %s" % [
		m.call(collected_items.has("KeyChest")), tr("Find the key in the graveyard"),
		m.call(gate_open()), tr("Open the mansion gate"),
		m.call(boss.is_defeated()), tr("Defeat Captain Kuro in the mansion")]
	if not GameSession.is_played("usopp"):
		text += "\n%s %s" % [m.call(recruited), tr("Recruit Usopp on the hill")]
	return text


func _mission_goals_done() -> bool:
	return boss.is_defeated() and recruited


func _on_item_taken(item: Collectible) -> void:
	if item.item_id == "key":
		hud.show_message(tr("The mansion key! Use it on the gate on the north plateau"), 2.5)


func _on_boss_down() -> void:
	hud.show_message(tr("You defeated Captain Kuro! Go find Usopp on the hill"), 2.5)
