class_name WorldMap
extends CanvasLayer
## The big map ("map": M / Select of the gamepad). It pauses the game and frees the mouse.
##   Sea chart: the whole sea with its islands. The cursor (mouse, or the left stick / D-pad / WASD)
##              picks an island; click / A / Enter opens it.
##   Island:    the picture of that island, big, with everything on it: food and items, the key,
##              enemies, bosses, people, checkpoints, the dock, the Going Merry and the crew.
##              Pointing at a thing shows its name. Wheel / triggers / +- zoom; drag, right stick
##              or the cursor at the border pan; Q / X sets the course of the voyage to it.
## Esc / B / right click goes back (island -> chart -> closed); "map" closes it at once.
## Made by World (world.gd), which also gives it `world`.

signal closed

const CURSOR_SPEED := 620.0
const PAN_SPEED := 0.9
const ZOOM_MIN := 1.0
const ZOOM_MAX := 4.0
const BG := Color(0.03, 0.06, 0.1, 0.92)
const DOCK_COLOR := Color(0.55, 0.38, 0.22)

var world: World
## "" = the sea chart; an island id = that island, big.
var island := ""
var _hover := ""
var _cursor := Vector2.ZERO
var _zoom := 1.0
var _pan := Vector2.ZERO
var _dragging := false
var _maps := {}
var _canvas: Control
var _title: Label
var _hint: Label
var _tip := ""
## World center and half side shown in `_area` (the square of the screen where the map is drawn).
var _c := Vector2.ZERO
var _r := 1.0
var _area := Rect2()


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	for id in GameState.ISLANDS:
		_maps[id] = load(GameState.ISLAND_PLACES[id].map)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)
	_title = Label.new()
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 12.0
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_constant_override("outline_size", 8)
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(_title)
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -38.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(_hint)


func is_open() -> bool:
	return visible


## Opens the sea chart with the cursor over the island where the player is.
func open() -> void:
	visible = true
	if world:
		world.hud.visible = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	island = ""
	_layout()
	var here := world.current.island_id if world and world.current else ""
	_cursor = _to_screen(GameState.island_center(here)) if here != "" else _area.get_center()
	Input.warp_mouse(_cursor)
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	_dragging = false
	if world:
		world.hud.visible = true
	get_tree().paused = false
	closed.emit()


func _open_island(id: String) -> void:
	if not GameState.unlocked.has(id):
		return
	# an island far away is loaded now to show what is on it (World frees it again when far)
	if world and not world.islands.has(id):
		world.load_island(id)
	island = id
	_zoom = 1.0
	_pan = Vector2.ZERO
	_layout()
	_cursor = _area.get_center()
	_refresh()


func _back() -> void:
	if island == "":
		close()
		return
	var id := island
	island = ""
	_layout()
	_cursor = _to_screen(GameState.island_center(id))
	_refresh()


# ------------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if not visible:
		return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("map") or (GameSession.coop and InputMap.has_action("p2_map") and event.is_action_pressed("p2_map")):
		close()
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_back()
	elif event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging and island != "":
			_pan -= mm.relative / _area.size.x * 2.0 * _r
			_clamp_pan()
		_cursor = mm.position
		_refresh()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact") or event.is_action_pressed("jump"):
		_select()
	elif event.is_action_pressed("use_item") and island != "":
		_set_course()
	elif island != "" and (event.is_action_pressed("next_item") or _key(event, [KEY_PLUS, KEY_KP_ADD, KEY_EQUAL])):
		_zoom_by(1.25)
	elif island != "" and (event.is_action_pressed("next_skill") or _key(event, [KEY_MINUS, KEY_KP_SUBTRACT])):
		_zoom_by(0.8)


func _key(event: InputEvent, keys: Array) -> bool:
	return event is InputEventKey and (event as InputEventKey).pressed and keys.has((event as InputEventKey).keycode)


func _mouse_button(mb: InputEventMouseButton) -> void:
	_cursor = mb.position
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
		_zoom_by(1.15, mb.position)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
		_zoom_by(1.0 / 1.15, mb.position)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_back()
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		if island == "":
			if mb.pressed:
				_select()
		else:
			_dragging = mb.pressed


func _select() -> void:
	if island == "" and _hover != "":
		_open_island(_hover)


## The stick or the keys move the cursor (and pan at the border); the right stick pans; the
## triggers zoom.
func _process(delta: float) -> void:
	if not visible:
		return
	var move := _axis(["move_left", "move_right", "move_forward", "move_back"]) + _axis(["ui_left", "ui_right", "ui_up", "ui_down"])
	if move.length() > 1.0:
		move = move.normalized()
	var look := _axis(["look_left", "look_right", "look_up", "look_down"])
	var zoom := 0.0
	for d in Input.get_connected_joypads():
		zoom += Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT)
	var changed := false
	if move.length() > 0.15:
		_cursor += move * CURSOR_SPEED * delta
		if island != "":
			# pushing the cursor against the border pans the island
			var edge := Vector2.ZERO
			if _cursor.x < _area.position.x + 20.0 or _cursor.x > _area.end.x - 20.0:
				edge.x = signf(move.x)
			if _cursor.y < _area.position.y + 20.0 or _cursor.y > _area.end.y - 20.0:
				edge.y = signf(move.y)
			_pan += edge * PAN_SPEED * _r * delta
			_clamp_pan()
		_cursor = _cursor.clamp(_area.position + Vector2(4, 4), _area.end - Vector2(4, 4))
		changed = true
	if island != "" and look.length() > 0.2:
		_pan += look * PAN_SPEED * _r * delta
		_clamp_pan()
		changed = true
	if island != "" and absf(zoom) > 0.15:
		_zoom_by(1.0 + zoom * delta * 1.5)
		changed = true
	if changed:
		_refresh()


func _axis(actions: Array) -> Vector2:
	var v := Vector2.ZERO
	for i in 4:
		for prefix in ["", "p2_"]:
			var a: String = prefix + actions[i]
			if InputMap.has_action(a):
				var s := Input.get_action_strength(a)
				match i:
					0: v.x -= s
					1: v.x += s
					2: v.y -= s
					3: v.y += s
	return v


func _zoom_by(f: float, at := Vector2(-1, -1)) -> void:
	if island == "":
		return
	var anchor := at if at.x >= 0.0 else _area.get_center()
	var before := _to_world(anchor)
	_zoom = clampf(_zoom * f, ZOOM_MIN, ZOOM_MAX)
	_layout()
	# the point under the mouse stays under it
	_pan += before - _to_world(anchor)
	_clamp_pan()
	_refresh()


func _clamp_pan() -> void:
	var half: float = GameState.ISLAND_PLACES[island].size / 2.0
	var lim := maxf(0.0, half - _r * 0.7)
	_pan = _pan.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	_layout()


func _set_course() -> void:
	if world == null or island == "" or (world.current and world.current.island_id == island):
		return
	world.set_destination(island)
	_refresh()


# ------------------------------------------------------------------ layout
func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var side := minf(vs.x - 40.0, vs.y - 120.0)
	_area = Rect2((vs - Vector2(side, side)) / 2.0 + Vector2(0, 8), Vector2(side, side))
	if island == "":
		var sea: Rect2 = GameState.SEA_RECT
		_c = sea.get_center()
		_r = maxf(sea.size.x, sea.size.y) / 2.0 + 60.0
	else:
		var place: Dictionary = GameState.ISLAND_PLACES[island]
		var half: float = place.size / 2.0
		_c = Vector2(place.offset.x, place.offset.z) + Vector2(half, half) + _pan
		_r = half / _zoom


func _to_screen(w: Vector2) -> Vector2:
	return _area.get_center() + (w - _c) / _r * _area.size.x / 2.0


func _to_world(s: Vector2) -> Vector2:
	return _c + (s - _area.get_center()) / (_area.size.x / 2.0) * _r


func _refresh() -> void:
	if island == "":
		_hover = _island_at(_to_world(_cursor))
		_title.text = tr("Sea chart")
		_hint.text = tr("Choose an island: mouse or stick  ·  Click/A: view the island  ·  Esc/B/M: close")
	else:
		_title.text = tr(GameState.ISLAND_NAMES[island]) + ("  ✓" if GameState.completed.has(island) else "")
		var course := ""
		if world and not (world.current and world.current.island_id == island):
			course = "  ·  " + (tr("Course set") if world.destination == island else tr("Q/X: set course"))
		_hint.text = tr("Wheel/triggers: zoom  ·  Drag/right stick: move  ·  Esc/B: back  ·  M: close") + course
	_canvas.queue_redraw()


func _island_at(w: Vector2) -> String:
	for id in GameState.ISLANDS:
		var place: Dictionary = GameState.ISLAND_PLACES[id]
		if Rect2(Vector2(place.offset.x, place.offset.z), Vector2(place.size, place.size)).has_point(w):
			return id
	return ""


# ------------------------------------------------------------------ drawing
func _draw_map() -> void:
	var ci := _canvas
	ci.draw_rect(Rect2(Vector2.ZERO, ci.size), BG)
	ci.draw_rect(_area.grow(8.0), Minimap.COLORS.paper)
	ci.draw_rect(_area, Minimap.COLORS.sea)
	_tip = ""
	if island == "":
		_draw_sea()
	else:
		_draw_island()
	ci.draw_rect(_area, Minimap.COLORS.ring, false, 3.0)
	_draw_legend()
	_draw_cursor()


func _draw_sea() -> void:
	var ci := _canvas
	var font := ci.get_theme_default_font()
	var step := 200.0
	var x := floorf((_c.x - _r) / step) * step
	while x <= _c.x + _r:
		var sx := _to_screen(Vector2(x, 0)).x
		if sx > _area.position.x and sx < _area.end.x:
			ci.draw_line(Vector2(sx, _area.position.y), Vector2(sx, _area.end.y), Color(1, 1, 1, 0.06))
		x += step
	var z := floorf((_c.y - _r) / step) * step
	while z <= _c.y + _r:
		var sy := _to_screen(Vector2(0, z)).y
		if sy > _area.position.y and sy < _area.end.y:
			ci.draw_line(Vector2(_area.position.x, sy), Vector2(_area.end.x, sy), Color(1, 1, 1, 0.06))
		z += step
	for id in GameState.ISLANDS:
		var place: Dictionary = GameState.ISLAND_PLACES[id]
		var a := _to_screen(Vector2(place.offset.x, place.offset.z))
		var b := _to_screen(Vector2(place.offset.x, place.offset.z) + Vector2(place.size, place.size))
		var rect := Rect2(a, b - a)
		var open := GameState.unlocked.has(id)
		var lit: bool = id == _hover and open
		ci.draw_texture_rect(_maps[id], rect, false, Color(1, 1, 1) if open else Color(0.4, 0.4, 0.5))
		if lit:
			ci.draw_rect(rect.grow(3.0), Color(1.0, 0.85, 0.3), false, 3.0)
		var name := tr(GameState.ISLAND_NAMES[id]) if open else "???"
		if GameState.completed.has(id):
			name += "  ✓"
		var at := Vector2(rect.get_center().x - 110.0, rect.end.y + 20.0)
		ci.draw_string_outline(font, at, name, HORIZONTAL_ALIGNMENT_CENTER, 220.0, 17, 5, Color(0, 0, 0, 0.85))
		ci.draw_string(font, at, name, HORIZONTAL_ALIGNMENT_CENTER, 220.0, 17, Color(1.0, 0.9, 0.5) if lit else Color.WHITE)
		if id == _hover and not open:
			_tip = tr("You haven't discovered this island yet")
	_draw_ship(9.0)
	_draw_goal(9.0)
	_draw_players(9.0, false)


func _draw_island() -> void:
	var ci := _canvas
	var place: Dictionary = GameState.ISLAND_PLACES[island]
	var o := Vector2(place.offset.x, place.offset.z)
	var a := _to_screen(o)
	var b := _to_screen(o + Vector2(place.size, place.size))
	# only the part inside the frame: the texture is cut with its source rect
	var shown := Rect2(a, b - a).intersection(_area)
	if shown.has_area():
		var tex: Texture2D = _maps[island]
		var k := tex.get_size() / (b - a)
		ci.draw_texture_rect_region(tex, shown, Rect2((shown.position - a) * k, shown.size * k))
	var icon := 7.0 + 2.0 * _zoom
	var isl: IslandWorld = world.islands.get(island) if world else null
	if isl:
		_draw_things(isl, icon)
	_draw_dock(icon)
	_draw_ship(icon * 1.2)
	_draw_players(icon, true)
	if isl == null:
		var font := ci.get_theme_default_font()
		ci.draw_string_outline(font, _area.get_center() - Vector2(200, 0), tr("Get closer to the island to see what is on it"), HORIZONTAL_ALIGNMENT_CENTER, 400, 18, 5, Color.BLACK)
		ci.draw_string(font, _area.get_center() - Vector2(200, 0), tr("Get closer to the island to see what is on it"), HORIZONTAL_ALIGNMENT_CENTER, 400, 18, Color.WHITE)


## Point of the world inside the frame of the map (null when it is out of it).
func _at(p: Vector3) -> Variant:
	var s := _to_screen(Vector2(p.x, p.z))
	return s if _area.grow(-4.0).has_point(s) else null


func _near_cursor(s: Vector2, r: float, label: String) -> void:
	if label != "" and s.distance_to(_cursor) < maxf(r, 10.0):
		_tip = label


func _draw_things(isl: IslandWorld, icon: float) -> void:
	var ci := _canvas
	var tree := get_tree()
	for cp in tree.get_nodes_in_group("checkpoints"):
		if isl.is_ancestor_of(cp):
			var s: Variant = _at((cp as Node3D).global_position)
			if s != null:
				Minimap.draw_flag(ci, s, icon, Minimap.COLORS.checkpoint)
				_near_cursor(s, icon, tr("Checkpoint"))
	for group in ["minimap_meat", "minimap_key"]:
		for item in tree.get_nodes_in_group(group):
			var it := item as Collectible
			if it == null or it.taken or not isl.is_ancestor_of(it):
				continue
			var s2: Variant = _at(it.global_position)
			if s2 == null:
				continue
			var key: bool = group == "minimap_key"
			Minimap.draw_diamond(ci, s2, icon * (1.3 if key else 0.9), Minimap.COLORS.key if key else Minimap.COLORS.meat)
			_near_cursor(s2, icon, GameState.item_name(it.item_id))
	for n in tree.get_nodes_in_group("minimap_npc"):
		var nn := n as Node3D
		if nn.is_visible_in_tree() and isl.is_ancestor_of(nn):
			var s3: Variant = _at(nn.global_position)
			if s3 != null:
				ci.draw_circle(s3, icon, Minimap.COLORS.npc)
				ci.draw_arc(s3, icon, 0, TAU, 16, Color(0, 0, 0, 0.7), 1.5)
				_near_cursor(s3, icon, tr(nn.name))
	for e in tree.get_nodes_in_group("enemies"):
		var en := e as Node3D
		if not isl.is_ancestor_of(en) or (en.has_method("is_defeated") and en.is_defeated()):
			continue
		var s4: Variant = _at(en.global_position)
		if s4 == null:
			continue
		if en is BuggyBoss or en is Boss:
			ci.draw_circle(s4, icon * 1.6, Minimap.COLORS.boss)
			ci.draw_circle(s4, icon * 0.65, Color.WHITE)
			_near_cursor(s4, icon * 1.6, tr(en.get("display_name")))
		else:
			ci.draw_circle(s4, icon * 0.8, Minimap.COLORS.enemy)
			_near_cursor(s4, icon, tr("Enemy"))
	# people of the island that can join the crew (still not recruited)
	for p in tree.get_nodes_in_group("players"):
		var pl := p as Player
		if pl and pl.control == Player.Controller.NONE and pl.is_visible_in_tree() and isl.is_ancestor_of(pl):
			var s5: Variant = _at(pl.global_position)
			if s5 != null:
				ci.draw_circle(s5, icon, Minimap.COLORS.npc)
				ci.draw_arc(s5, icon, 0, TAU, 16, Color(1, 1, 1, 0.9), 1.5)
				_near_cursor(s5, icon, tr(pl.display_name))


func _draw_dock(icon: float) -> void:
	var s: Variant = _at(GameState.dock_transform(island).origin)
	if s == null:
		return
	_canvas.draw_rect(Rect2(s - Vector2(icon, icon * 0.5), Vector2(icon * 2.0, icon)), DOCK_COLOR)
	_canvas.draw_rect(Rect2(s - Vector2(icon, icon * 0.5), Vector2(icon * 2.0, icon)), Color(0, 0, 0, 0.7), false, 1.5)
	_near_cursor(s, icon, tr("Dock"))


func _draw_ship(icon: float) -> void:
	var ship := get_tree().get_first_node_in_group("minimap_ship") as Ship
	if ship == null:
		return
	var s: Variant = _at(ship.global_position)
	if s == null:
		return
	var f := ship.forward()
	var a := atan2(f.x, -f.z)
	var hull := PackedVector2Array([Vector2(0, -icon * 1.3), Vector2(icon * 0.65, -icon * 0.2), Vector2(icon * 0.55, icon), Vector2(-icon * 0.55, icon), Vector2(-icon * 0.65, -icon * 0.2)])
	for i in hull.size():
		hull[i] = (s as Vector2) + hull[i].rotated(a)
	_canvas.draw_colored_polygon(hull, Minimap.COLORS.ship)
	_canvas.draw_polyline(hull + PackedVector2Array([hull[0]]), Color(1, 0.95, 0.85, 0.9), 1.5)
	_near_cursor(s, icon, "Going Merry")


func _draw_goal(icon: float) -> void:
	if world == null or world.destination == "":
		return
	var s: Variant = _at(GameState.dock_transform(world.destination).origin)
	if s != null:
		Minimap.draw_star(_canvas, s, icon * 1.6, Minimap.COLORS.goal)


func _draw_players(icon: float, crew: bool) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		var pl := p as Player
		if pl == null or not pl.is_visible_in_tree() or pl.control == Player.Controller.NONE:
			continue
		var s: Variant = _at(pl.global_position)
		if s == null:
			continue
		if pl.control == Player.Controller.AI:
			if crew:
				_canvas.draw_circle(s, icon * 0.75, Color(0.85, 0.85, 0.95))
				_near_cursor(s, icon, tr(pl.display_name))
			continue
		var col: Color = Minimap.COLORS.p1 if pl.control == Player.Controller.PLAYER_ONE else Minimap.COLORS.p2
		Minimap.draw_arrow(_canvas, s, pl.facing, icon * 1.7, col)
		_near_cursor(s, icon * 1.5, tr(pl.display_name))


func _draw_legend() -> void:
	var ci := _canvas
	var font := ci.get_theme_default_font()
	var items: Array = Minimap.LEGEND + [["dock", "Dock"], ["p1", "Player"]]
	var box := Rect2(_area.position + Vector2(10, 10), Vector2(180, items.size() * 20 + 12))
	if _area.position.x > box.size.x + 24.0:
		# beside the map when there is room, so it does not hide a corner of the island
		box.position = Vector2(_area.position.x - box.size.x - 16.0, _area.position.y)
	ci.draw_rect(box, Color(0, 0, 0, 0.6))
	var y := box.position.y + 6.0
	for item in items:
		ci.draw_circle(Vector2(box.position.x + 14, y + 10), 5, DOCK_COLOR if item[0] == "dock" else Minimap.COLORS[item[0]])
		ci.draw_string(font, Vector2(box.position.x + 26, y + 15), tr(item[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		y += 20.0


## The cursor (it also follows the mouse) and the name of what is under it.
func _draw_cursor() -> void:
	var ci := _canvas
	var c := _cursor
	var col := Color(1.0, 0.9, 0.4)
	ci.draw_arc(c, 11.0, 0, TAU, 24, Color(0, 0, 0, 0.8), 4.0)
	ci.draw_arc(c, 11.0, 0, TAU, 24, col, 2.0)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		ci.draw_line(c + d * 6.0, c + d * 16.0, col, 2.0)
	var label := _tip
	if label == "" and island == "" and _hover != "" and GameState.unlocked.has(_hover):
		label = tr(GameState.ISLAND_NAMES[_hover])
	if label == "":
		return
	var font := ci.get_theme_default_font()
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 16.0
	var at := c + Vector2(18, -30)
	if at.x + w > ci.size.x:
		at.x = c.x - 18 - w
	ci.draw_rect(Rect2(at, Vector2(w, 24)), Color(0, 0, 0, 0.8))
	ci.draw_string(font, at + Vector2(8, 17), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
