class_name HeroProgress
extends RefCounted
## What one playable character carries (GameState.heroes: one in single player, one per player in
## co-op): its inventory, its level and experience, and the skills of that character (Luffy's Gomu
## Gomu attacks, Zoro's sword styles... GameState.SKILLS) learned in the skill shop.

signal inventory_changed
signal xp_changed(level: int, xp: int, needed: int)
signal leveled_up(level: int)
signal skills_changed

## "luffy", "zoro", "usopp" or "nami" (GameSession.CHARACTERS).
var character := "luffy"
## GameState.INVENTORY_SIZE entries: {} (empty) or {"id": "meat", "count": 3}.
var inventory: Array = []
var selected_slot := 0
var level := 1
var xp := 0
var skill_points := 0
var skills: Array = []
var equipped := ""
## Health when the world scene was left (0 = full).
var health := 0.0


func _init(who := "luffy") -> void:
	character = who
	for i in GameState.INVENTORY_SIZE:
		inventory.append({})


# ------------------------------------------------------------------ inventory
func count_of(id: String) -> int:
	var n := 0
	for s in inventory:
		if s.get("id", "") == id:
			n += int(s.count)
	return n


## Puts an item in the inventory. Returns false if there is no room for it.
func add_item(id: String, amount: int = 1) -> bool:
	if not GameState.ITEMS.has(id) or not can_add(id, amount):
		return false
	var left := amount
	var stack: int = GameState.ITEMS[id].stack
	for s in inventory:
		if left > 0 and s.get("id", "") == id and int(s.count) < stack:
			var put := mini(left, stack - int(s.count))
			s.count = int(s.count) + put
			left -= put
	for i in inventory.size():
		if left > 0 and (inventory[i] as Dictionary).is_empty():
			var put := mini(left, stack)
			inventory[i] = {"id": id, "count": put}
			left -= put
	inventory_changed.emit()
	return true


func can_add(id: String, amount: int = 1) -> bool:
	var stack: int = GameState.ITEMS[id].stack
	var room := 0
	for s in inventory:
		if (s as Dictionary).is_empty():
			room += stack
		elif s.id == id:
			room += stack - int(s.count)
	return room >= amount


## Takes up to `amount` items out (eating, giving them away). Returns how many were taken.
func remove_item(id: String, amount: int = 1) -> int:
	var left := amount
	for i in range(inventory.size() - 1, -1, -1):
		var s: Dictionary = inventory[i]
		if left > 0 and s.get("id", "") == id:
			var take := mini(left, int(s.count))
			s.count = int(s.count) - take
			left -= take
			if int(s.count) <= 0:
				inventory[i] = {}
	inventory_changed.emit()
	return amount - left


func selected_item() -> String:
	return str((inventory[selected_slot] as Dictionary).get("id", ""))


func select_slot(i: int) -> void:
	selected_slot = posmod(i, GameState.INVENTORY_SIZE)
	inventory_changed.emit()


## Next slot with something in it (or simply the next one if they are all empty).
func select_next(dir: int = 1) -> void:
	for k in range(1, GameState.INVENTORY_SIZE + 1):
		var i := posmod(selected_slot + k * dir, GameState.INVENTORY_SIZE)
		if not (inventory[i] as Dictionary).is_empty():
			select_slot(i)
			return
	select_slot(selected_slot + dir)


# ------------------------------------------------------------------ experience
func xp_needed(lv: int = -1) -> int:
	return GameState.xp_for_level(level if lv < 0 else lv)


## Experience for defeating an enemy (or finishing a mission).
func add_xp(amount: int) -> void:
	if amount <= 0 or level >= GameState.MAX_LEVEL:
		return
	xp += amount
	var ups := 0
	while xp >= xp_needed() and level < GameState.MAX_LEVEL:
		xp -= xp_needed()
		level += 1
		skill_points += 1
		ups += 1
	if level >= GameState.MAX_LEVEL:
		xp = 0
	xp_changed.emit(level, xp, xp_needed())
	if ups > 0:
		leveled_up.emit(level)


## Health of this character at its level.
func max_health() -> float:
	return GameState.max_health(character, level)


# ------------------------------------------------------------------ skills
## The skills of this character: id -> spec.
func all_skills() -> Dictionary:
	return GameState.SKILLS[character]


## Skills that appear in the shop: 2 more for every island that was reached.
func shop_skills() -> Array:
	var out := []
	var reached := GameState.reached_index()
	var all := all_skills()
	for id in all:
		if int(all[id].island) <= reached:
			out.append(id)
	return out


func can_learn(id: String) -> bool:
	return all_skills().has(id) and not skills.has(id) and shop_skills().has(id) and skill_points >= int(all_skills()[id].cost)


func learn(id: String) -> bool:
	if not can_learn(id):
		return false
	skill_points -= int(all_skills()[id].cost)
	skills.append(id)
	if equipped == "":
		equipped = id
	skills_changed.emit()
	return true


func equip(id: String) -> void:
	if skills.has(id):
		equipped = id
		skills_changed.emit()


func equip_next() -> void:
	if skills.is_empty():
		return
	var i := skills.find(equipped)
	equipped = skills[(i + 1) % skills.size()]
	skills_changed.emit()


# ------------------------------------------------------------------ saving
func collect() -> Dictionary:
	var inv := []
	for s in inventory:
		inv.append([str((s as Dictionary).get("id", "")), int((s as Dictionary).get("count", 0))])
	return {"character": character, "level": level, "xp": xp, "points": skill_points, "skills": skills.duplicate(),
		"equipped": equipped, "inventory": inv, "health": int(ceilf(health))}


## Restores what collect() gave (the values were already validated by SaveManager).
func restore(d: Dictionary) -> void:
	character = str(d.character)
	level = int(d.level)
	xp = int(d.xp)
	skill_points = int(d.points)
	skills = (d.skills as Array).duplicate()
	equipped = str(d.equipped)
	health = float(d.health)
	for i in GameState.INVENTORY_SIZE:
		var e: Array = d.inventory[i]
		inventory[i] = {} if str(e[0]) == "" else {"id": str(e[0]), "count": int(e[1])}
