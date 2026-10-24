extends IslandWorld
## First island, "Clown Island" (scenes/islands/isla_inicio.tscn). See IslandWorld for what all
## the islands share.
## Koby gives Luffy the mission: defeat Buggy (in the volcano crater), collect all the meat of the
## island and recruit Zoro: he is tied to a post in the north-west forest and joins the crew if
## Luffy gives him 3 pieces of meat from the inventory. If a player plays Zoro (co-op), he is with
## the crew from the start. The Going Merry is moored at the dock of the north-east inlet; when
## the mission is done Luffy takes its wheel and sails to Villa Syrup.
## Signals of Buggy, the checkpoints and the meat are connected in the scene.

const MEAT_FOR_ZORO := 3
const KOBY_ZORO_LINE := "One more thing: in the northwest forest the Marines have a swordsman tied up, Roronoa Zoro. Recruit Zoro for your crew!"
const KOBY_COOP_LINE := "And how lucky that Zoro the swordsman already sails with you!"

var zoro: Player


func _island_ready() -> void:
	boss = $Buggy
	zoro = $Zoro
	connect_boss_signals = false
	recruit_member = "zoro"
	music = load("res://assets/audio/music_island.wav")
	zoro.control = Player.Controller.NONE
	boss.target = player
	# the old invisible ring around the island: now the sea is open (Luffy can swim back from the ship)
	var borders := get_node_or_null("Island/Borders") as CollisionObject3D
	if borders:
		borders.collision_layer = 0


func activate() -> void:
	super()
	hud.set_boss_state(tr(BuggyBoss.STATE_TEXT[boss.state]))


func arrival_message(loaded: bool) -> void:
	if loaded:
		super(loaded)
	elif mission == Mission.NOT_GIVEN:
		hud.show_message(tr("Talk to Koby!"), 2.5)
	else:
		hud.show_message(tr(GameState.ISLAND_NAMES[island_id]), 2.0)


func _interactables() -> Array:
	var out := super()
	if _zoro_near():
		out.append([zoro, 3.2, "Talk", _talk_to_zoro])
	return out


func _zoro_near() -> bool:
	return is_instance_valid(zoro) and zoro.get_parent() == self and not recruited \
		and zoro.global_position.distance_to(player.global_position) < 3.2


func _process(_delta: float) -> void:
	if is_instance_valid(zoro) and zoro.get_parent() == self:
		zoro.get_node("NameLabel").visible = not recruited
		zoro.get_node("PromptLabel").visible = _zoro_near() and not hud.is_dialog_open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug") and is_current():
		boss.set_debug_visible(not boss.show_debug)


# ------------------------------------------------------------------ Koby and the mission
func _talk_to_koby() -> void:
	var lines: Array = []
	match mission:
		Mission.NOT_GIVEN:
			lines = Array(koby.mission_lines)
			lines.append(KOBY_COOP_LINE if GameSession.is_played("zoro") else KOBY_ZORO_LINE)
		Mission.ACTIVE:
			lines = [_progress_line()]
		_:
			lines = ["You did it, Luffy-san! You're amazing!", "The Going Merry is waiting at the dock: take the helm and sail to Syrup Village. I'll see you there!"]
	open_dialog("Koby", lines, give_mission)


## Zoro, tied up: he joins the crew when Luffy gives him some meat.
func _talk_to_zoro() -> void:
	if GameState.party_count("meat") >= MEAT_FOR_ZORO:
		open_dialog("Zoro", ["Food at last! ...Fine, I'll join your crew.", "But listen: my dream is to be the greatest swordsman in the world. Don't you forget it, captain!"], _recruit_zoro)
	else:
		open_dialog("Zoro", ["And who are you? I'm Roronoa Zoro. The Marines tied me up here and I haven't eaten in days...",
			tr("Bring me %d pieces of meat and I'll join your crew. (You have %d)") % [MEAT_FOR_ZORO, GameState.party_count("meat")]])


func _recruit_zoro() -> void:
	if recruited or not GameState.party_take("meat", MEAT_FOR_ZORO):
		return
	zoro.get_node("NameLabel").visible = false
	zoro.get_node("PromptLabel").visible = false
	recruit()


func _progress_line() -> String:
	var missing := []
	if not boss.is_defeated():
		missing.append(tr("defeat Buggy in the crater"))
	if _meat_taken() < _meat_total():
		missing.append(tr("collect %d more meat") % (_meat_total() - _meat_taken()))
	if not recruited:
		missing.append(tr("recruit Zoro in the northwest forest"))
	return tr("Keep going, Luffy-san! You still need to ") + tr(" and ").join(missing) + "."


func _mission_text() -> String:
	if mission == Mission.NOT_GIVEN:
		return tr("Talk to Koby on the south beach")
	if mission == Mission.DONE:
		return tr("Island complete!") + "\n" + tr("Take the Going Merry's helm and sail to Syrup Village")
	var boss_mark := "[X]" if boss.is_defeated() else "[  ]"
	var meat_mark := "[X]" if _meat_taken() >= _meat_total() else "[  ]"
	var zoro_mark := "[X]" if recruited else "[  ]"
	var text := "%s %s\n%s %s" % [boss_mark, tr("Defeat Buggy the Clown"), meat_mark, tr("Collect the meat (%d/%d)") % [_meat_taken(), _meat_total()]]
	if not GameSession.is_played("zoro"):
		text += "\n%s %s" % [zoro_mark, tr("Recruit Zoro")]
	return text


func _mission_goals_done() -> bool:
	return boss.is_defeated() and _meat_taken() >= _meat_total() and recruited


# ------------------------------------------------------------------ signals of the scene
func _on_buggy_state_changed(new_state: int) -> void:
	if not is_node_ready() or not is_current():
		return
	hud.set_boss_state(tr(BuggyBoss.STATE_TEXT[new_state]))
	if world.finished or new_state == BuggyBoss.State.DEFEATED:
		return
	if new_state == BuggyBoss.State.CHASE:
		hud.show_message(tr("Buggy saw you!"), 1.0)
		world.set_chase(true)
	elif new_state == BuggyBoss.State.RETURN:
		hud.show_message(tr("You got away!"), 1.0)
		world.set_chase(false)


func _on_buggy_defeated() -> void:
	if not is_node_ready():
		return
	world.set_chase(false)
	world.award_xp(boss)
	_update_mission_text()
	# the bar shows Buggy's empty health for a moment and then goes away
	get_tree().create_timer(1.5).timeout.connect(_update_boss_hud)
	hud.show_message(tr("You defeated Buggy the Clown!"), 2.0)
	check_mission()


## Buggy's health bar: only while the mission is active and Buggy is still standing.
func _update_boss_hud() -> void:
	if is_inside_tree() and is_current():
		hud.set_boss_visible(mission == Mission.ACTIVE and not boss.is_defeated())


## Zoro is revived by World._on_crew_died (this old connection of the scene does nothing).
func _on_zoro_died() -> void:
	pass
