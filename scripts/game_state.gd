extends Node
## GameState (autoload, see project.godot): everything the crew carries from one island to another.
##   - the voyage: island being played, islands that can be visited and islands completed;
##   - the crew (Zoro, Usopp, Nami) that already joined;
##   - `heroes`: one HeroProgress per player (one in single player, two in co-op), each with its
##     own character, inventory (INVENTORY_SIZE slots; meat and tangerines stack), level and
##     experience (every full bar is a level and a skill point) and the skills of its character
##     learned in the skill shop. In co-op every enemy gives double XP to both players.
## The islands keep their own progress (mission, checkpoints, meat taken...) in `islands`.
## SaveManager writes all of it in the save slots (see collect() / restore()).

const ISLANDS := ["isla_inicio", "villa_syrup", "whisky_peak"]
## The voyage is one scene: the sea, the Going Merry, the crew and the interface. The islands are
## loaded into it (and freed again) while the ship gets close to them, at their place in the sea.
const WORLD_SCENE := "res://scenes/world.tscn"
const ISLAND_SCENES := {
	"isla_inicio": "res://scenes/islands/isla_inicio.tscn",
	"villa_syrup": "res://scenes/islands/villa_syrup.tscn",
	"whisky_peak": "res://scenes/islands/whisky_peak.tscn",
}
const ISLAND_NAMES := {"isla_inicio": "Clown Island", "villa_syrup": "Syrup Village", "whisky_peak": "Whisky Peak"}
const CREW := ["zoro", "usopp", "nami"]
## Where every island is in the sea and what the voyage needs to know about it without loading it:
##   offset: position of the island scene; size: side of its map (meters, from the offset);
##   center / radius: the land (in the island's own coordinates), for the fog and for loading it;
##   dock / dock_yaw: where the Going Merry is moored in its port (own coordinates), alongside the
##   pier; gangway_side: side of the ship where the pier is (1 = the ship's +x, -1 = -x);
##   gangway_drop: from the deck where the gangway is hinged down to the pier;
##   map / shore: picture for the minimap and foam mask for the sea.
const ISLAND_PLACES := {
	"isla_inicio": {"offset": Vector3(0, 0, 0), "size": 440.0, "center": Vector2(220, 220), "radius": 225.0,
		"dock": Vector3(298.32, 1.0, 156.4), "dock_yaw": 180.0, "gangway_side": 1.0, "gangway_drop": 0.9,
		"map": "res://assets/ui/minimap_island.png", "shore": "res://assets/generated/shore_mask.res"},
	"villa_syrup": {"offset": Vector3(700, 0, -1000), "size": 400.0, "center": Vector2(200, 190), "radius": 175.0,
		"dock": Vector3(208.4, 1.0, 373), "dock_yaw": 0.0, "gangway_side": -1.0, "gangway_drop": 0.35,
		"map": "res://assets/ui/minimap_villa_syrup.png", "shore": "res://assets/generated/villa_syrup_shore_mask.res"},
	"whisky_peak": {"offset": Vector3(1500, 0, -2000), "size": 400.0, "center": Vector2(200, 190), "radius": 170.0,
		"dock": Vector3(208.4, 1.0, 373), "dock_yaw": 0.0, "gangway_side": -1.0, "gangway_drop": 0.35,
		"map": "res://assets/ui/minimap_whisky_peak.png", "shore": "res://assets/generated/whisky_peak_shore_mask.res"},
}
## The sea that can be sailed (x, z): the Going Merry turns back at its border.
const SEA_RECT := Rect2(-500, -2600, 2900, 3400)

const INVENTORY_SIZE := 4
## id -> name, health it gives back when eaten (0 = it can not be eaten), how many fit in a slot.
const ITEMS := {
	"meat": {"name": "Meat", "heal": 35.0, "stack": 9, "color": Color(0.85, 0.42, 0.2)},
	"orange": {"name": "Tangerine", "heal": 15.0, "stack": 9, "color": Color(1.0, 0.6, 0.1)},
	"key": {"name": "Mansion key", "heal": 0.0, "stack": 1, "color": Color(0.95, 0.8, 0.3)},
}

## Skills of every character (ids are unique among all of them). "island": index of the island
## where they appear in the shop (2 per island). "effect" says what the skill does (Player):
##   spin: hits all around; front: a strong hit in front; rapid: many hits in front; shield: no
##   damage for a while and pushes everyone away; wave: a shock wave in front; storm: hits all
##   around several times; shot: a projectile; spread: three projectiles.
const SKILLS := {
	"luffy": {
		"muchi": {"name": "Gomu Gomu no Muchi", "island": 0, "cost": 1, "cooldown": 4.0, "damage": 22.0, "effect": "spin", "radius": 3.3, "push": 8.0,
			"text": "Spinning kick: hits every enemy around you."},
		"bazooka": {"name": "Gomu Gomu no Bazooka", "island": 0, "cost": 2, "cooldown": 6.0, "damage": 40.0, "effect": "front", "radius": 1.9, "push": 18.0,
			"text": "Two-palm shove: big damage and sends the enemy flying."},
		"gatling": {"name": "Gomu Gomu no Gatling", "island": 1, "cost": 2, "cooldown": 7.0, "damage": 9.0, "effect": "rapid", "radius": 1.5, "push": 2.5,
			"text": "A rain of punches in front of you: many hits in a row."},
		"fusen": {"name": "Gomu Gomu no Fusen", "island": 1, "cost": 1, "cooldown": 10.0, "damage": 10.0, "effect": "shield", "radius": 3.6, "push": 13.0,
			"text": "You puff up like a balloon: nothing hurts you and you push enemies away."},
		"ono": {"name": "Gomu Gomu no Ono", "island": 2, "cost": 2, "cooldown": 8.0, "damage": 48.0, "effect": "wave", "radius": 2.8, "push": 10.0,
			"text": "Heel axe-drop: a shock wave in front of you."},
		"storm": {"name": "Gomu Gomu no Storm", "island": 2, "cost": 3, "cooldown": 14.0, "damage": 14.0, "effect": "storm", "radius": 4.2, "push": 6.0,
			"text": "A storm of punches in every direction."},
	},
	"zoro": {
		"onigiri": {"name": "Oni Giri", "island": 0, "cost": 1, "cooldown": 4.0, "damage": 26.0, "effect": "front", "radius": 1.9, "push": 14.0,
			"text": "Cross cut with the three swords: big damage in front of you."},
		"tatsumaki": {"name": "Tatsu Maki", "island": 0, "cost": 2, "cooldown": 7.0, "damage": 30.0, "effect": "spin", "radius": 3.6, "push": 12.0,
			"text": "A tornado of cuts that hits everyone around you."},
		"yakkodori": {"name": "Yakkodori", "island": 1, "cost": 1, "cooldown": 5.0, "damage": 34.0, "effect": "shot", "radius": 0.35, "push": 6.0,
			"text": "A flying cut: hits far-away enemies."},
		"rengoku": {"name": "Rengoku Oni Giri", "island": 1, "cost": 2, "cooldown": 7.0, "damage": 10.0, "effect": "rapid", "radius": 1.6, "push": 3.0,
			"text": "A flurry of cuts in front of you."},
		"sanjuroku": {"name": "Sanjuroku Pound Ho", "island": 2, "cost": 2, "cooldown": 8.0, "damage": 50.0, "effect": "wave", "radius": 2.9, "push": 11.0,
			"text": "A cannon blast of cutting air: a shock wave in front of you."},
		"ashura": {"name": "Asura", "island": 2, "cost": 3, "cooldown": 14.0, "damage": 16.0, "effect": "storm", "radius": 4.2, "push": 7.0,
			"text": "Nine swords: cuts in every direction."},
	},
	"usopp": {
		"namari": {"name": "Namari Boshi", "island": 0, "cost": 1, "cooldown": 3.0, "damage": 22.0, "effect": "shot", "radius": 0.2, "push": 5.0,
			"text": "A lead ball: big damage to a far-away enemy."},
		"pound": {"name": "Usopp Pound", "island": 0, "cost": 1, "cooldown": 5.0, "damage": 28.0, "effect": "front", "radius": 1.8, "push": 14.0,
			"text": "A five-ton hammer blow! (or so Usopp says)."},
		"kaen": {"name": "Kaen Boshi", "island": 1, "cost": 2, "cooldown": 6.0, "damage": 38.0, "effect": "shot", "radius": 0.3, "push": 8.0,
			"text": "A fire star that burns whoever it touches."},
		"tamago": {"name": "Tamago Boshi", "island": 1, "cost": 1, "cooldown": 6.0, "damage": 14.0, "effect": "spread", "radius": 0.2, "push": 4.0,
			"text": "Three rotten eggs at once: a fan of shots."},
		"kemuri": {"name": "Kemuri Boshi", "island": 2, "cost": 1, "cooldown": 10.0, "damage": 8.0, "effect": "shield", "radius": 3.4, "push": 12.0,
			"text": "A cloud of smoke: nothing hurts you and enemies back away."},
		"kayaku": {"name": "Kayaku Boshi", "island": 2, "cost": 3, "cooldown": 14.0, "damage": 18.0, "effect": "storm", "radius": 4.4, "push": 9.0,
			"text": "Gunpowder blasts all around you."},
	},
	"nami": {
		"cyclone": {"name": "Cyclone Tempo", "island": 0, "cost": 1, "cooldown": 4.0, "damage": 18.0, "effect": "front", "radius": 2.2, "push": 22.0,
			"text": "A cyclone from the Clima-Tact that blows enemies away."},
		"thunderbolt": {"name": "Thunderbolt Tempo", "island": 0, "cost": 2, "cooldown": 6.0, "damage": 34.0, "effect": "wave", "radius": 2.8, "push": 8.0,
			"text": "Lightning strikes in front of you."},
		"cool_ball": {"name": "Cool Ball", "island": 1, "cost": 1, "cooldown": 6.0, "damage": 12.0, "effect": "spread", "radius": 0.25, "push": 4.0,
			"text": "Three bubbles of cold air in a fan."},
		"mirage": {"name": "Mirage Tempo", "island": 1, "cost": 1, "cooldown": 10.0, "damage": 8.0, "effect": "shield", "radius": 3.4, "push": 12.0,
			"text": "A mirage: nothing hurts you and enemies get confused."},
		"heat_ball": {"name": "Heat Ball", "island": 2, "cost": 2, "cooldown": 7.0, "damage": 40.0, "effect": "shot", "radius": 0.35, "push": 8.0,
			"text": "A bubble of hot air that bursts on touch."},
		"thunder_lance": {"name": "Thunder Lance Tempo", "island": 2, "cost": 3, "cooldown": 14.0, "damage": 18.0, "effect": "storm", "radius": 4.2, "push": 6.0,
			"text": "Spears of lightning fall all around you."},
	},
}
## Health of every character at level 1 (it grows HEALTH_PER_LEVEL with every level).
const BASE_HEALTH := {"luffy": 100.0, "zoro": 120.0, "usopp": 90.0, "nami": 95.0}
const HEALTH_PER_LEVEL := 5.0
const MAX_LEVEL := 30

var island := "isla_inicio"
var unlocked: Array = ["isla_inicio"]
var completed: Array = []
var crew: Array = []
## One HeroProgress per player.
var heroes: Array = []
## island id -> progress of that island (written and read by the island scripts).
var islands := {}
var play_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset()


## A new game.
func reset() -> void:
	island = "isla_inicio"
	unlocked = ["isla_inicio"]
	completed = []
	crew = []
	heroes = []
	for who in GameSession.characters:
		heroes.append(HeroProgress.new(who))
	islands = {}
	play_time = 0.0


## The progress of player `i` (0 or 1).
func hero(i: int = 0) -> HeroProgress:
	return heroes[i] if i < heroes.size() else heroes[0]


## The progress that belongs to a character on screen: player 2 has his own; the companions
## (and anything else) use player 1's.
func hero_of(p: Node) -> HeroProgress:
	if p is Player and (p as Player).control == Player.Controller.PLAYER_TWO and heroes.size() > 1:
		return heroes[1]
	return heroes[0]


## Items of the whole party (an item a mission asks for can be in the bag of either player).
func party_count(id: String) -> int:
	var n := 0
	for h in heroes:
		n += (h as HeroProgress).count_of(id)
	return n


## Takes items from the party (from `first` before the others). Returns false if there are not enough.
func party_take(id: String, amount: int, first: HeroProgress = null) -> bool:
	if party_count(id) < amount:
		return false
	var order := heroes.duplicate()
	if first:
		order.erase(first)
		order.push_front(first)
	var left := amount
	for h in order:
		left -= (h as HeroProgress).remove_item(id, left) if left > 0 else 0
	return true


## Experience for everyone: in co-op it is doubled and both players get it.
func give_xp(amount: int) -> int:
	var each := amount * (2 if heroes.size() > 1 else 1)
	for h in heroes:
		(h as HeroProgress).add_xp(each)
	return each


func xp_for_level(lv: int) -> int:
	return 40 + 30 * (lv - 1)


func max_health(character: String, lv: int) -> float:
	return float(BASE_HEALTH.get(character, 100.0)) + HEALTH_PER_LEVEL * (lv - 1)


## Spec of a skill of any character ({} if it does not exist).
func skill_spec(id: String) -> Dictionary:
	for who in SKILLS:
		if (SKILLS[who] as Dictionary).has(id):
			return SKILLS[who][id]
	return {}


## Index of the farthest island reached (the skill shop shows 2 skills more for each one).
func reached_index() -> int:
	var reached := island_index()
	for id in unlocked:
		reached = maxi(reached, island_index(id))
	return reached


func island_index(id: String = "") -> int:
	return ISLANDS.find(island if id == "" else id)


func next_island(id: String = "") -> String:
	var i := island_index(id) + 1
	return ISLANDS[i] if i > 0 and i < ISLANDS.size() else ""


func has_crew(member: String) -> bool:
	return crew.has(member)


func add_crew(member: String) -> void:
	if not crew.has(member):
		crew.append(member)


## The mission of the island is done: the next island can be visited.
func complete_island(id: String) -> void:
	if not completed.has(id):
		completed.append(id)
	var nxt := next_island(id)
	if nxt != "" and not unlocked.has(nxt):
		unlocked.append(nxt)


func is_last_island(id: String) -> bool:
	return island_index(id) == ISLANDS.size() - 1


# ------------------------------------------------------------------ names
func item_name(id: String) -> String:
	return tr(ITEMS[id].name) if ITEMS.has(id) else ""


func skill_name(id: String) -> String:
	var spec := skill_spec(id)
	return tr(spec.name) if not spec.is_empty() else ""


# ------------------------------------------------------------------ saving
## The part of a save document that does not belong to one island.
func collect() -> Dictionary:
	return {"crew": crew.duplicate(), "unlocked": unlocked.duplicate(), "done": completed.duplicate()}


func collect_heroes() -> Array:
	return heroes.map(func(h): return (h as HeroProgress).collect())


## Restores what collect() and collect_heroes() gave (the values were already validated by SaveManager).
func restore(voyage: Dictionary, hero_data: Array, island_id: String, island_data: Dictionary, time: float) -> void:
	reset()
	island = island_id
	crew = (voyage.crew as Array).duplicate()
	unlocked = (voyage.unlocked as Array).duplicate()
	completed = (voyage.done as Array).duplicate()
	heroes = []
	for d in hero_data:
		var h := HeroProgress.new(str(d.character))
		h.restore(d)
		heroes.append(h)
	islands = island_data.duplicate(true)
	play_time = time


## Scene of an island (its content: it is loaded into the world scene).
func island_scene(id: String = "") -> String:
	return ISLAND_SCENES[island if id == "" else id]


## Center of an island in the world (x, z).
func island_center(id: String) -> Vector2:
	var p: Dictionary = ISLAND_PLACES[id]
	return Vector2(p.offset.x, p.offset.z) + p.center


## Where the Going Merry is moored in the port of an island (world transform).
func dock_transform(id: String) -> Transform3D:
	var p: Dictionary = ISLAND_PLACES[id]
	return Transform3D(Basis(Vector3.UP, deg_to_rad(p.dock_yaw)), p.offset + p.dock)


## The island whose land is closest to a point and how far from its shore (negative = on it).
func nearest_island(pos: Vector3) -> Array:
	var best := ""
	var best_d := INF
	for id in ISLANDS:
		var d := island_center(id).distance_to(Vector2(pos.x, pos.z)) - float(ISLAND_PLACES[id].radius)
		if d < best_d:
			best_d = d
			best = id
	return [best, best_d]
