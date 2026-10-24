extends Node
## SaveManager (autoload, see project.godot): the save "database" of the game.
##
## It is a small NON-RELATIONAL (document) database stored in ONE JSON file:
##   user://saves/partidas.json
##   {
##     "database": "rumbo_al_one_piece",
##     "version": 1,
##     "slots": {
##       "1": { "data": { ...progress of that game... }, "signature": "9f3a..." },
##       "2": null,                      <- empty slot
##       "3": { ... }, "4": { ... }
##     }
##   }
## Every slot is one document (a JSON object, no tables or relations). The game can create a new
## game in a slot, overwrite (replace) a slot, read it and delete it. There are SLOT_COUNT slots.
##
## Security (so a player can not edit the file to skip the game):
##   1. Every document is signed with HMAC-SHA256. The key is built inside the game (it is not
##      written in the file) and mixed with the id of the device, so a save copied from another
##      computer/phone is not valid either. The slot number is part of what is signed, so a
##      document can not be moved to another slot.
##   2. When a slot is read, the signature is checked and every value is validated (types,
##      ranges, meat and checkpoint names that exist, coherence between values). If anything
##      fails, the slot is marked as TAMPERED: it is shown as "modificado" and can not be loaded.
##   3. Every number is saved as a whole number, so the signature does not depend on how a text
##      editor writes decimals: only a real change of a value breaks it.
##   4. The file is written to a temporary file first and then renamed, so a crash while saving
##      can not leave half a file.
## Note: like any game that saves on the player's device, someone who decompiles the game could
## find how the key is made; the signature stops editing the JSON by hand (the usual cheat).
##
## Version 4 document:
##   {"version": 4, "slot", "saved_at", "play_time", "completed": the whole voyage is finished,
##    "island": island being played,
##    "voyage": {"crew", "unlocked", "done"},
##    "heroes": one per player (2 = local co-op): [{"character", "level", "xp", "points", "skills",
##              "equipped", "inventory": [[id, count] x 4], "health"}, ...],
##    "islands": {"isla_inicio": {"mission", "checkpoint", "checkpoints", "items", "boss_health",
##                                "boss_defeated", "recruited", "flags"}, "villa_syrup": {...}, ...}}
## Documents of versions 1, 2 (only the first island) and 3 (one player) are still valid: they
## keep their own signature and are turned into version 4 when they are read (upgrade()).

enum SlotStatus { EMPTY, VALID, TAMPERED }

const SLOT_COUNT := 4
const FILE_PATH := "user://saves/partidas.json"
## 2 = Zoro added ("zoro": recruited). 3 = several islands, inventory, experience and skills.
## 4 = every player has his own character, inventory, experience and skills (co-op).
## Saves of older versions are still valid (see upgrade()).
const VERSION := 4
## Ids of the Checkpoint nodes of scenes/islands/isla_inicio.tscn (anything else in a save is rejected).
const CHECKPOINT_IDS := ["playa_sur", "entrada_crater", "muelle", "peninsula_oeste", "bosque_noroeste", "costa_este"]
const FIRST_CHECKPOINT := "playa_sur"
const MEAT_COUNT := 10
const PLAYER_MAX_HEALTH := 100.0
const BOSS_MAX_HEALTH := 150.0
## Every island: ids of its Checkpoint nodes (the first one is where the island starts), names of
## the pickups that can be taken (they are not put back when loading) and its boss' health.
const ISLAND_SPECS := {
	"isla_inicio": {"checkpoints": CHECKPOINT_IDS, "items": ["Meat1", "Meat2", "Meat3", "Meat4", "Meat5", "Meat6", "Meat7", "Meat8", "Meat9", "Meat10"], "boss_max": BOSS_MAX_HEALTH, "flags": []},
	"villa_syrup": {"checkpoints": ["puerto_syrup", "aldea_syrup", "colina_syrup", "jardin_mansion"],
		"items": ["Meat1", "Meat2", "Meat3", "Meat4", "Meat5", "Meat6", "Meat7", "Meat8", "Orange1", "Orange2", "Orange3", "KeyChest"], "boss_max": 420.0, "flags": ["gate_open"]},
	"whisky_peak": {"checkpoints": ["puerto_whisky", "arco_whisky", "plaza_whisky", "cactus_whisky"],
		"items": ["Meat1", "Meat2", "Meat3", "Meat4", "Meat5", "Meat6", "Meat7", "Meat8", "Orange1", "Orange2", "Orange3", "Orange4", "Orange5"], "boss_max": 720.0, "flags": ["oranges_given"]},
}
## Slot used by the game that is being played (0 = none, nothing is saved).
var current_slot := 0
## Progress to apply when scenes/world.tscn starts (filled by load_game()).
var _pending: Dictionary = {}


# ------------------------------------------------------------------ public API
## Every slot: [{slot, status, data}] (data is empty unless the slot is VALID).
func list_slots() -> Array:
	var db := _read_db()
	var out := []
	for i in range(1, SLOT_COUNT + 1):
		out.append(_check_slot(db, i))
	return out


func read_slot(slot: int) -> Dictionary:
	return _check_slot(_read_db(), slot)


## Creates or replaces the document of a slot. Returns false if it could not be written.
func write_slot(slot: int, data: Dictionary) -> bool:
	if slot < 1 or slot > SLOT_COUNT:
		return false
	var doc := data.duplicate(true)
	doc["version"] = VERSION
	doc["slot"] = slot
	doc["saved_at"] = int(Time.get_unix_time_from_system())
	doc = _normalize(doc)
	if not _valid_v4(doc, slot):
		push_error("SaveManager: refusing to save invalid data %s" % doc)
		return false
	var db := _read_db()
	db["slots"][str(slot)] = {"data": doc, "signature": _sign(slot, doc)}
	return _write_db(db)


func delete_slot(slot: int) -> bool:
	var db := _read_db()
	db["slots"][str(slot)] = null
	if current_slot == slot:
		current_slot = 0
	return _write_db(db)


## "Nueva partida": the game starts from zero in this slot (world.gd saves it at once).
func start_new_game(slot: int) -> void:
	current_slot = slot
	_pending = {}
	GameState.reset()


## "Load": only valid slots of games that are not finished can be loaded. A co-op game (two
## heroes) needs a gamepad for player 2. The game mode and the characters come from the save; the
## voyage (GameState) is restored here; the world scene restores the rest with take_pending().
func load_game(slot: int) -> bool:
	var info := read_slot(slot)
	if info.status != SlotStatus.VALID or bool(info.data.get("completed", false)):
		return false
	var heroes: Array = info.data.heroes
	if heroes.size() > 1 and not GameSession.can_play_coop():
		return false
	GameSession.start(heroes.size() > 1)
	GameSession.characters = heroes.map(func(h): return str(h.character))
	current_slot = slot
	_pending = info.data
	GameState.restore(info.data.voyage, heroes, str(info.data.island), info.data.islands, float(info.data.play_time))
	return true


## Keeps a document for the next island scene (used when sailing to another island).
func set_pending(data: Dictionary) -> void:
	_pending = data


## An older document as a version 4 one.
func upgrade(d: Dictionary) -> Dictionary:
	var version := int(d.get("version", VERSION))
	if version >= 4:
		return d
	if version == 3:
		var p: Dictionary = d.player
		return {
			"version": VERSION, "slot": d.slot, "saved_at": d.saved_at, "play_time": d.play_time,
			"completed": d.completed, "island": d.island,
			"voyage": {"crew": p.crew, "unlocked": p.unlocked, "done": p.done},
			"heroes": [{"character": "luffy", "level": p.level, "xp": p.xp, "points": p.points, "skills": p.skills,
				"equipped": p.equipped, "inventory": p.inventory, "health": d.health}],
			"islands": d.islands,
		}
	var zoro := bool(d.get("zoro", false))
	var inv := []
	for i in 4:
		inv.append(["", 0])
	var done := ["isla_inicio"] if bool(d.completed) else []
	return {
		"version": VERSION, "slot": d.slot, "saved_at": d.saved_at, "play_time": d.play_time,
		"completed": false, "island": "isla_inicio",
		"voyage": {"crew": ["zoro"] if zoro else [], "unlocked": ["isla_inicio", "villa_syrup"] if bool(d.completed) else ["isla_inicio"], "done": done},
		"heroes": [{"character": "luffy", "level": 1, "xp": 0, "points": 0, "skills": [], "equipped": "", "inventory": inv, "health": d.health}],
		"islands": {"isla_inicio": {"mission": 2 if bool(d.completed) else d.mission, "checkpoint": d.checkpoint, "checkpoints": d.checkpoints,
			"items": d.meat, "boss_health": d.boss_health, "boss_defeated": d.boss_defeated, "recruited": zoro, "flags": []}},
	}


## Called by game_world.gd when the level starts: the progress to restore (or {} for a new game).
func take_pending() -> Dictionary:
	var d := _pending
	_pending = {}
	return d


# ------------------------------------------------------------------ file
func _empty_db() -> Dictionary:
	var slots := {}
	for i in range(1, SLOT_COUNT + 1):
		slots[str(i)] = null
	return {"database": "rumbo_al_one_piece", "version": VERSION, "slots": slots}


func _read_db() -> Dictionary:
	if not FileAccess.file_exists(FILE_PATH):
		return _empty_db()
	var text := FileAccess.get_file_as_string(FILE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("slots")) != TYPE_DICTIONARY:
		# the file is not our JSON any more: every slot is shown as modified
		var broken := _empty_db()
		for i in range(1, SLOT_COUNT + 1):
			broken["slots"][str(i)] = {"data": {}, "signature": ""}
		return broken
	var db := _empty_db()
	for i in range(1, SLOT_COUNT + 1):
		db["slots"][str(i)] = parsed["slots"].get(str(i))
	return db


func _write_db(db: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(FILE_PATH.get_base_dir())
	var tmp := FILE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: can not write %s (%d)" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(_ints(db), "\t", true))
	f.close()
	return DirAccess.rename_absolute(tmp, FILE_PATH) == OK


## Writes 120 instead of 120.0 in the file (only to make it easier to read).
func _ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if v == floorf(v) else v
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = _ints(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(_ints(x))
			return a
	return v


# ------------------------------------------------------------------ security
func _check_slot(db: Dictionary, slot: int) -> Dictionary:
	var doc: Variant = db["slots"].get(str(slot))
	if doc == null:
		return {"slot": slot, "status": SlotStatus.EMPTY, "data": {}}
	var bad := {"slot": slot, "status": SlotStatus.TAMPERED, "data": {}}
	if typeof(doc) != TYPE_DICTIONARY or typeof(doc.get("data")) != TYPE_DICTIONARY or typeof(doc.get("signature")) != TYPE_STRING:
		return bad
	var data: Dictionary = doc["data"]
	if doc["signature"] != _sign(slot, data):
		return bad
	var version := int(data.get("version", 0)) if _is_number(data.get("version")) else 0
	if version >= 4:
		if not _valid_v4(data, slot):
			return bad
	elif version == 3:
		if not _valid_v3(data, slot):
			return bad
	elif not _valid_data(data, slot):
		return bad
	return {"slot": slot, "status": SlotStatus.VALID, "data": upgrade(data)}


## Same values as they will be after writing and reading the JSON (ints become floats, etc.).
func _normalize(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d, "", true, true))


func _key() -> PackedByteArray:
	# the key is not stored anywhere: it is built from pieces and the id of this device
	var pieces := PackedStringArray(["Gomu", "G0mu", "n0", "Mi", "R4mb0", "0n3", "P13c3", "%d" % (SLOT_COUNT * 7919)])
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("-".join(pieces) + "|" + OS.get_unique_id()).to_utf8_buffer())
	return ctx.finish()


func _sign(slot: int, data: Dictionary) -> String:
	# each document is signed with its own version (old saves keep their valid signature)
	var message := "slot:%d|v%d|%s" % [slot, int(data.get("version", VERSION)), JSON.stringify(data, "", true, true)]
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, _key(), message.to_utf8_buffer()).hex_encode()


## Only whole numbers are accepted (see point 3 above).
func _is_number(v: Variant) -> bool:
	return (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and float(v) == floorf(float(v))


func _names_ok(list: Variant, valid: Array) -> bool:
	if typeof(list) != TYPE_ARRAY:
		return false
	var seen := {}
	for v in list:
		if typeof(v) != TYPE_STRING or not valid.has(v) or seen.has(v):
			return false
		seen[v] = true
	return true


## Validates every value of a save (even a correctly signed one must make sense).
func _valid_data(d: Dictionary, slot: int) -> bool:
	var meat_names := []
	for i in range(1, MEAT_COUNT + 1):
		meat_names.append("Meat%d" % i)
	var keys := ["version", "slot", "saved_at", "play_time", "health", "mission", "completed", "checkpoint", "checkpoints", "meat", "boss_health", "boss_defeated"]
	if d.get("version") is float and int(d.version) >= 2:
		keys.append("zoro")
	for k in keys:
		if not d.has(k):
			return false
	if d.size() != keys.size():
		return false
	if not _is_number(d.version) or int(d.version) < 1 or int(d.version) > VERSION or not _is_number(d.slot) or int(d.slot) != slot:
		return false
	if not _is_number(d.saved_at) or not _is_number(d.play_time) or float(d.play_time) < 0.0 or float(d.play_time) > 1.0e7:
		return false
	if not _is_number(d.health) or float(d.health) <= 0.0 or float(d.health) > PLAYER_MAX_HEALTH:
		return false
	if not _is_number(d.mission) or not [0, 1].has(int(d.mission)):
		return false
	if typeof(d.completed) != TYPE_BOOL or typeof(d.boss_defeated) != TYPE_BOOL:
		return false
	if typeof(d.checkpoint) != TYPE_STRING or not CHECKPOINT_IDS.has(d.checkpoint):
		return false
	if not _names_ok(d.checkpoints, CHECKPOINT_IDS) or not d.checkpoints.has(d.checkpoint) or not d.checkpoints.has(FIRST_CHECKPOINT):
		return false
	if not _names_ok(d.meat, meat_names):
		return false
	if not _is_number(d.boss_health) or float(d.boss_health) < 0.0 or float(d.boss_health) > BOSS_MAX_HEALTH:
		return false
	if d.boss_defeated != (float(d.boss_health) <= 0.0):
		return false
	# a finished game must really have everything done
	if d.has("zoro") and typeof(d.zoro) != TYPE_BOOL:
		return false
	if d.completed and (int(d.mission) != 1 or not d.boss_defeated or d.meat.size() != MEAT_COUNT or not d.get("zoro", true)):
		return false
	return true


## Validation of a version 3 document (several islands).
func _valid_v3(d: Dictionary, slot: int) -> bool:
	var keys := ["version", "slot", "saved_at", "play_time", "completed", "island", "health", "player", "islands"]
	for k in keys:
		if not d.has(k):
			return false
	if d.size() != keys.size():
		return false
	if not _is_number(d.version) or int(d.version) != 3 or not _is_number(d.slot) or int(d.slot) != slot:
		return false
	if not _is_number(d.saved_at) or not _is_number(d.play_time) or float(d.play_time) < 0.0 or float(d.play_time) > 1.0e7:
		return false
	if typeof(d.completed) != TYPE_BOOL or typeof(d.island) != TYPE_STRING or not ISLAND_SPECS.has(d.island):
		return false
	if typeof(d.player) != TYPE_DICTIONARY or typeof(d.islands) != TYPE_DICTIONARY:
		return false
	var p: Dictionary = d.player
	var pkeys := ["level", "xp", "points", "skills", "equipped", "inventory", "crew", "unlocked", "done"]
	for k in pkeys:
		if not p.has(k):
			return false
	if p.size() != pkeys.size():
		return false
	if not _is_number(p.level) or int(p.level) < 1 or int(p.level) > 30:
		return false
	if not _is_number(d.health) or float(d.health) <= 0.0 or float(d.health) > PLAYER_MAX_HEALTH + GameState.HEALTH_PER_LEVEL * (int(p.level) - 1):
		return false
	if not _valid_skills(p, "luffy") or not _valid_inventory(p.inventory):
		return false
	return _valid_voyage(d, p, [])


## Validation of a version 4 document (one hero per player).
func _valid_v4(d: Dictionary, slot: int) -> bool:
	var keys := ["version", "slot", "saved_at", "play_time", "completed", "island", "voyage", "heroes", "islands"]
	for k in keys:
		if not d.has(k):
			return false
	if d.size() != keys.size():
		return false
	if not _is_number(d.version) or int(d.version) != 4 or not _is_number(d.slot) or int(d.slot) != slot:
		return false
	if not _is_number(d.saved_at) or not _is_number(d.play_time) or float(d.play_time) < 0.0 or float(d.play_time) > 1.0e7:
		return false
	if typeof(d.completed) != TYPE_BOOL or typeof(d.island) != TYPE_STRING or not ISLAND_SPECS.has(d.island):
		return false
	if typeof(d.voyage) != TYPE_DICTIONARY or typeof(d.heroes) != TYPE_ARRAY or typeof(d.islands) != TYPE_DICTIONARY:
		return false
	var v: Dictionary = d.voyage
	if v.size() != 3 or not v.has("crew") or not v.has("unlocked") or not v.has("done"):
		return false
	# single player is always Luffy; in co-op two different characters
	var heroes: Array = d.heroes
	if heroes.size() < 1 or heroes.size() > 2:
		return false
	var played := []
	for h in heroes:
		if typeof(h) != TYPE_DICTIONARY or not _valid_hero(h):
			return false
		if played.has(h.character):
			return false
		played.append(h.character)
	if heroes.size() == 1 and played[0] != "luffy":
		return false
	return _valid_voyage(d, v, played)


func _valid_hero(h: Dictionary) -> bool:
	var keys := ["character", "level", "xp", "points", "skills", "equipped", "inventory", "health"]
	for k in keys:
		if not h.has(k):
			return false
	if h.size() != keys.size():
		return false
	if typeof(h.character) != TYPE_STRING or not GameSession.CHARACTERS.has(h.character):
		return false
	if not _is_number(h.level) or int(h.level) < 1 or int(h.level) > GameState.MAX_LEVEL:
		return false
	if not _is_number(h.health) or float(h.health) <= 0.0 or float(h.health) > GameState.max_health(h.character, int(h.level)):
		return false
	return _valid_skills(h, h.character) and _valid_inventory(h.inventory)


## Level, experience, skill points and skills of a hero (or of a version 3 player).
func _valid_skills(p: Dictionary, character: String) -> bool:
	if not _is_number(p.level) or int(p.level) < 1 or int(p.level) > GameState.MAX_LEVEL:
		return false
	if not _is_number(p.xp) or int(p.xp) < 0 or int(p.xp) >= GameState.xp_for_level(int(p.level)):
		return false
	if not _is_number(p.points) or int(p.points) < 0:
		return false
	var all: Dictionary = GameState.SKILLS[character]
	if not _names_ok(p.skills, all.keys()) or typeof(p.equipped) != TYPE_STRING:
		return false
	if p.equipped != "" and not p.skills.has(p.equipped):
		return false
	# the points spent plus the ones left can not be more than the levels won
	var spent := 0
	for sk in p.skills:
		spent += int(all[sk].cost)
	return spent + int(p.points) <= int(p.level) - 1


func _valid_inventory(inv: Variant) -> bool:
	if typeof(inv) != TYPE_ARRAY or inv.size() != GameState.INVENTORY_SIZE:
		return false
	for e in inv:
		if typeof(e) != TYPE_ARRAY or e.size() != 2 or typeof(e[0]) != TYPE_STRING or not _is_number(e[1]):
			return false
		if e[0] == "":
			if int(e[1]) != 0:
				return false
		elif not GameState.ITEMS.has(e[0]) or int(e[1]) < 1 or int(e[1]) > int(GameState.ITEMS[e[0]].stack):
			return false
	return true


## The voyage (crew, islands open and done) and the islands of a document. `played`: characters
## of the players (they are never part of the recruited crew).
func _valid_voyage(d: Dictionary, p: Dictionary, played: Array) -> bool:
	if not _names_ok(p.crew, GameState.CREW) or not _names_ok(p.unlocked, GameState.ISLANDS) or not _names_ok(p.done, GameState.ISLANDS):
		return false
	if not p.unlocked.has("isla_inicio") or not p.unlocked.has(d.island):
		return false
	# an island is only open if the one before it was completed
	for id in p.unlocked:
		var i: int = GameState.ISLANDS.find(id)
		if i > 0 and not p.done.has(GameState.ISLANDS[i - 1]):
			return false
	for id in p.done:
		if not p.unlocked.has(id):
			return false
	if d.completed and not p.done.has(GameState.ISLANDS[-1]):
		return false
	for id in d.islands:
		if not ISLAND_SPECS.has(id) or typeof(d.islands[id]) != TYPE_DICTIONARY or not _valid_island(id, d.islands[id]):
			return false
		if not p.unlocked.has(id):
			return false
	# the crew members come from the missions of their islands
	var recruiter := {"zoro": "isla_inicio", "usopp": "villa_syrup", "nami": "whisky_peak"}
	for c in p.crew:
		var isl: Dictionary = d.islands.get(recruiter[c], {})
		if played.has(c) or not bool(isl.get("recruited", false)):
			return false
	for id in p.done:
		var isl2: Dictionary = d.islands.get(id, {})
		if int(isl2.get("mission", 0)) != 2 or not bool(isl2.get("boss_defeated", false)):
			return false
	return true


func _valid_island(id: String, d: Dictionary) -> bool:
	var spec: Dictionary = ISLAND_SPECS[id]
	var keys := ["mission", "checkpoint", "checkpoints", "items", "boss_health", "boss_defeated", "recruited", "flags"]
	for k in keys:
		if not d.has(k):
			return false
	if d.size() != keys.size():
		return false
	if not _names_ok(d.flags, spec.flags):
		return false
	if not _is_number(d.mission) or not [0, 1, 2].has(int(d.mission)):
		return false
	var cps: Array = spec.checkpoints
	if typeof(d.checkpoint) != TYPE_STRING or not cps.has(d.checkpoint):
		return false
	if not _names_ok(d.checkpoints, cps) or not d.checkpoints.has(d.checkpoint) or not d.checkpoints.has(cps[0]):
		return false
	if not _names_ok(d.items, spec.items):
		return false
	if not _is_number(d.boss_health) or float(d.boss_health) < 0.0 or float(d.boss_health) > float(spec.boss_max):
		return false
	if typeof(d.boss_defeated) != TYPE_BOOL or typeof(d.recruited) != TYPE_BOOL:
		return false
	if d.boss_defeated != (float(d.boss_health) <= 0.0):
		return false
	if int(d.mission) == 2 and (not d.boss_defeated or not d.recruited):
		return false
	return true
