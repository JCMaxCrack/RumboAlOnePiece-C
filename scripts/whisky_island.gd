extends IslandWorld
## Third island, Whisky Peak (scenes/islands/whisky_peak.tscn). See IslandWorld for the shared part.
## A town at the foot of giant cactus-shaped rocks. Koby waits at the entrance of the town: Vice
## Admiral Garp (Luffy's grandfather!) arrived to take him to the Navy... by force. And Nami, the
## best navigator of East Blue, is in the town square: she would join a crew that brings her
## tangerines.
##   1. pick 5 tangerines from among the cactus rocks and give them to Nami: she joins the crew as
##      navigator at once (and fights Garp with Luffy);
##   2. defeat Garp, who waits on the plateau of the great cactus, north of the town. He is the
##      hardest boss of the voyage. It is the last island of this version: the voyage ends.

const ORANGES_FOR_NAMI := 5

var nami: Player
var oranges_given: bool:
	get:
		return flags.has("oranges_given")
	set(v):
		if v and not flags.has("oranges_given"):
			flags.append("oranges_given")


func _island_ready() -> void:
	boss = $Garp
	recruit_member = "nami"
	music = load("res://assets/audio/music_whisky_peak.wav")
	nami = recruit_node()
	if nami:
		nami.control = Player.Controller.NONE


func arrival_message(loaded: bool) -> void:
	if loaded:
		super(loaded)
	elif mission == Mission.NOT_GIVEN:
		hud.show_banner(tr("Whisky Peak"), tr("Koby is waiting for you at the town entrance"), 3.0)
	else:
		hud.show_message(tr("Whisky Peak"), 2.0)


func _interactables() -> Array:
	var out := super()
	if _nami_here():
		out.append([nami, 3.4, "Talk", _talk_to_nami])
	return out


func _nami_here() -> bool:
	return is_instance_valid(nami) and nami.get_parent() == self and not recruited


func _process(_delta: float) -> void:
	if _nami_here():
		var label := nami.get_node_or_null("PromptLabel") as Label3D
		if label:
			label.visible = not hud.is_dialog_open() and nami.global_position.distance_to(player.global_position) < 3.4


# ------------------------------------------------------------------ Koby, Nami and the mission
func _talk_to_koby() -> void:
	match mission:
		Mission.NOT_GIVEN:
			open_dialog("Koby", [
				"Luffy-san, bad news! Vice Admiral Garp of the Marines arrived in Whisky Peak... and he says he's your grandfather!",
				"He wants to drag you into the Marines with his fists. He's waiting for you on the great cactus plateau, north of the town.",
				"And in the square is Nami, the best navigator in the East Blue. Without her you'll never reach the Grand Line.",
				tr("She says she'll only join a crew that brings her %d tangerines from the trees among the cacti.") % ORANGES_FOR_NAMI,
				"Garp is very strong: recruit Nami first so she can help you, then defeat Garp!",
			], give_mission)
		Mission.ACTIVE:
			open_dialog("Koby", [_progress_line()])
		_:
			open_dialog("Koby", ["Amazing, Luffy-san! Someday you'll be the King of the Pirates."])


func _talk_to_nami() -> void:
	if mission == Mission.NOT_GIVEN:
		open_dialog("Nami", ["Hi. I'm Nami, the best navigator in the East Blue.", "A pirate? Hmm... talk to that Marine boy at the entrance first."])
		return
	if not oranges_given and GameState.party_take("orange", ORANGES_FOR_NAMI):
		oranges_given = true
		hud.show_message(tr("You gave Nami %d tangerines") % ORANGES_FOR_NAMI, 2.0)
		_update_mission_text()
	if oranges_given:
		open_dialog("Nami", [
			"My tangerines! All right, captain: from today I'm the navigator of the Straw Hat Pirates.",
			"Garp, the hero of the Marines? He's incredibly strong... but together we'll beat him! Let's go to the great cactus plateau.",
		], recruit)
	else:
		open_dialog("Nami", [tr("I still need tangerines: you have %d of %d. They grow among the cactus rocks.") % [GameState.party_count("orange"), ORANGES_FOR_NAMI]])


func _progress_line() -> String:
	if not recruited and not oranges_given:
		return tr("Look for the tangerines among the cactus rocks and take them to Nami, in the square.")
	if not recruited:
		return tr("Nami is waiting for you in the square!")
	return tr("Garp is waiting on the great cactus plateau, to the north. He throws cannonballs from far away!")


func _mission_text() -> String:
	if mission == Mission.NOT_GIVEN:
		return tr("Talk to Koby at the town entrance")
	if mission == Mission.DONE:
		return tr("Adventure complete!")
	var m := func(done: bool) -> String: return "[X]" if done else "[  ]"
	if GameSession.is_played("nami"):
		return "%s %s" % [m.call(boss.is_defeated()), tr("Defeat Vice Admiral Garp")]
	var have := mini(GameState.party_count("orange"), ORANGES_FOR_NAMI) if not oranges_given else ORANGES_FOR_NAMI
	return "%s %s\n%s %s\n%s %s" % [
		m.call(oranges_given or recruited), tr("Bring tangerines to Nami (%d/%d)") % [have, ORANGES_FOR_NAMI],
		m.call(recruited), tr("Recruit Nami"),
		m.call(boss.is_defeated()), tr("Defeat Vice Admiral Garp")]


func _mission_goals_done() -> bool:
	return boss.is_defeated() and recruited


func _on_item_taken(_item: Collectible) -> void:
	_update_mission_text()


func _on_boss_down() -> void:
	hud.show_message(tr("You defeated Vice Admiral Garp!") if recruited else tr("You defeated Garp! Now recruit Nami"), 2.5)
