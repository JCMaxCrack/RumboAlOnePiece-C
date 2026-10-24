class_name Minimap
extends Control
## Minimap of the HUD: a round map around the player it follows (`target`), north up. In co-op
## every player has his own (HUD.set_split). It draws the sea, the islands that are close (their
## pictures, GameState.ISLAND_PLACES), and on them: checkpoints (flag), pickups (diamond), the key,
## mini enemies (red), bosses (big red), people to talk to (blue), the Going Merry, the players
## (arrows) and the destination of the voyage (gold star; on the border when it is far).
## "map" (M / Select) opens the big map instead (WorldMap).
## The nodes are found by group: minimap_meat, minimap_key, enemies, minimap_ship, minimap_npc,
## checkpoints, players.

const COLORS := {
	"sea": Color(0.07, 0.27, 0.45), "meat": Color(1.0, 0.6, 0.15), "key": Color(1.0, 0.9, 0.3),
	"enemy": Color(0.95, 0.22, 0.2), "boss": Color(0.8, 0.05, 0.1), "ship": Color(0.62, 0.4, 0.2), "npc": Color(0.35, 0.7, 1.0),
	"checkpoint": Color(1.0, 0.85, 0.25), "p1": Color(1, 1, 1), "p2": Color(0.45, 1.0, 0.45), "goal": Color(1.0, 0.82, 0.3),
	"ring": Color(0.93, 0.78, 0.42), "paper": Color(0.86, 0.78, 0.6),
}
const LEGEND := [["meat", "Food"], ["key", "Key"], ["enemy", "Enemy"], ["boss", "Boss"], ["npc", "Character"],
	["checkpoint", "Checkpoint"], ["ship", "Going Merry"], ["goal", "Destination"]]
const SMALL_SIZE := 200.0
const CLIP_SHADER := """
shader_type canvas_item;
uniform vec2 center = vec2(100.0, 100.0);
uniform float radius = 100000.0;
varying vec2 local_pos;
void vertex() { local_pos = VERTEX; }
void fragment() { if (length(local_pos - center) > radius) { discard; } }
"""

## Meters from the player to the border of the small map.
@export var view_radius := 95.0
## The player it follows.
var target: Player
## Rectangle of the screen that belongs to this map (all of it, or a half in co-op).
var area := Rect2()
var _maps := {}
var _timer := 0.0
var _clip: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CLIP_SHADER
	_clip.shader = sh
	material = _clip
	for id in GameState.ISLANDS:
		_maps[id] = load(GameState.ISLAND_PLACES[id].map)
	get_viewport().size_changed.connect(_layout)
	_layout()


## Places the map in the top right corner of its area.
func _layout() -> void:
	var a := area if area.has_area() else get_viewport_rect()
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(a.end.x - SMALL_SIZE - 16.0, a.position.y + 16.0)
	size = Vector2(SMALL_SIZE, SMALL_SIZE)
	_clip.set_shader_parameter("center", size / 2.0)
	_clip.set_shader_parameter("radius", SMALL_SIZE / 2.0)
	queue_redraw()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.05
		queue_redraw()


func _follow() -> Vector3:
	if target and is_instance_valid(target):
		return target.global_position
	var players := get_tree().get_nodes_in_group("player")
	return (players[0] as Node3D).global_position if not players.is_empty() else Vector3.ZERO


# ------------------------------------------------------------------ drawing
## World position -> point in the map, and whether it is inside the visible area.
func _to_map(p: Vector3) -> Array:
	var rel := (Vector2(p.x, p.z) - _c) / _r
	var inside := rel.length() <= 0.97
	if not inside:
		rel = rel.normalized() * 0.86
	return [size / 2.0 + rel * size / 2.0, inside]


var _c := Vector2.ZERO
var _r := 1.0


func _draw() -> void:
	var p := _follow()
	_c = Vector2(p.x, p.z)
	_r = view_radius
	draw_circle(size / 2.0, size.x / 2.0, COLORS.sea)
	for id in GameState.ISLANDS:
		_draw_island(id)
	var icon := 5.0
	_draw_things(icon)
	_draw_ship(icon)
	_draw_goal(icon)
	_draw_players(icon)
	var r := size.x / 2.0
	draw_arc(size / 2.0, r - 3.0, 0.0, TAU, 64, Color(0.05, 0.07, 0.12, 0.9), 6.0, true)
	draw_arc(size / 2.0, r - 3.0, 0.0, TAU, 64, COLORS.ring, 3.0, true)
	var font := get_theme_default_font()
	draw_circle(Vector2(r, 11.0), 9.0, Color(0.05, 0.07, 0.12, 0.95))
	draw_string(font, Vector2(r - 5.5, 16.5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COLORS.ring)


func _draw_island(id: String) -> void:
	var place: Dictionary = GameState.ISLAND_PLACES[id]
	var tex: Texture2D = _maps[id]
	var world_rect := Rect2(Vector2(place.offset.x, place.offset.z), Vector2(place.size, place.size))
	var view := Rect2(_c - Vector2(_r, _r), Vector2(_r, _r) * 2.0)
	if not world_rect.intersects(view):
		return
	var a: Vector2 = size / 2.0 + (world_rect.position - _c) / _r * size / 2.0
	var s: Vector2 = world_rect.size / _r * size / 2.0
	var tint := Color(1, 1, 1) if GameState.unlocked.has(id) else Color(0.45, 0.45, 0.55)
	draw_texture_rect(tex, Rect2(a, s), false, tint)

func _draw_things(icon: float) -> void:
	for cp in get_tree().get_nodes_in_group("checkpoints"):
		var m: Array = _to_map((cp as Node3D).global_position)
		if m[1]:
			_flag(m[0], icon, COLORS.checkpoint)
	for n in get_tree().get_nodes_in_group("minimap_npc"):
		var nn := n as Node3D
		if nn.is_visible_in_tree():
			var m2: Array = _to_map(nn.global_position)
			if m2[1]:
				draw_circle(m2[0], icon * 0.95, COLORS.npc)
				draw_arc(m2[0], icon * 0.95, 0, TAU, 12, Color(0, 0, 0, 0.6), 1.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Node3D
		if en.has_method("is_defeated") and en.is_defeated():
			continue
		var m3: Array = _to_map(en.global_position)
		if not m3[1]:
			continue
		if en is BuggyBoss or en is Boss:
			draw_circle(m3[0], icon * 1.5, COLORS.boss)
			draw_circle(m3[0], icon * 0.6, Color.WHITE)
		else:
			draw_circle(m3[0], icon * 0.8, COLORS.enemy)
	for group in ["minimap_meat", "minimap_key"]:
		for item in get_tree().get_nodes_in_group(group):
			var it := item as Collectible
			if it == null or it.taken:
				continue
			var m4: Array = _to_map(it.global_position)
			if not m4[1]:
				continue
			var s := icon * (1.3 if group == "minimap_key" else 0.95)
			var pts := PackedVector2Array([m4[0] + Vector2(0, -s), m4[0] + Vector2(s, 0), m4[0] + Vector2(0, s), m4[0] + Vector2(-s, 0)])
			draw_colored_polygon(pts, COLORS.key if group == "minimap_key" else COLORS.meat)
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.6), 1.0)


func _draw_ship(icon: float) -> void:
	var ship := get_tree().get_first_node_in_group("minimap_ship") as Node3D
	if ship == null:
		return
	var m: Array = _to_map(ship.global_position)
	var f := -ship.global_basis.z if not (ship is Ship) else (ship as Ship).forward()
	var a := atan2(f.x, -f.z)
	var s := icon * (1.9 if m[1] else 1.3)
	var hull := PackedVector2Array([Vector2(0, -s * 1.2), Vector2(s * 0.6, -s * 0.2), Vector2(s * 0.5, s), Vector2(-s * 0.5, s), Vector2(-s * 0.6, -s * 0.2)])
	for i in hull.size():
		hull[i] = m[0] + hull[i].rotated(a)
	draw_colored_polygon(hull, COLORS.ship)
	draw_polyline(hull + PackedVector2Array([hull[0]]), Color(1, 0.95, 0.85, 0.9), 1.5)


## The destination: a gold star over its port (on the border of the map when it is far).
func _draw_goal(icon: float) -> void:
	var world := get_tree().get_first_node_in_group("world") as World
	if world == null or world.destination == "":
		return
	var dock := GameState.dock_transform(world.destination).origin
	var m: Array = _to_map(dock)
	var s := icon * 1.7
	if m[1]:
		_star(m[0], s, COLORS.goal)
	else:
		var dir := (Vector2(dock.x, dock.z) - _c).normalized()
		var tip: Vector2 = m[0] + dir * s
		var side := dir.orthogonal() * s * 0.7
		draw_colored_polygon(PackedVector2Array([tip, m[0] - dir * s * 0.4 + side, m[0] - dir * s * 0.4 - side]), COLORS.goal)
		_star(m[0] - dir * s * 1.3, s * 0.6, COLORS.goal)


func _draw_players(icon: float) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		var pl := p as Player
		if pl == null or not pl.is_visible_in_tree():
			continue
		var m: Array = _to_map(pl.global_position)
		if not m[1]:
			continue
		if pl.control == Player.Controller.NONE:
			draw_circle(m[0], icon * 0.95, COLORS.npc)
			continue
		if pl.control == Player.Controller.AI:
			draw_circle(m[0], icon * 0.75, Color(0.85, 0.85, 0.95))
			continue
		var col: Color = COLORS.p1 if pl.control == Player.Controller.PLAYER_ONE else COLORS.p2
		_arrow(m[0], pl.facing, icon * (1.8 if pl == target else 1.4), col)


func _arrow(p: Vector2, dir: Vector3, s: float, col: Color) -> void:
	draw_arrow(self, p, dir, s, col)


func _flag(p: Vector2, s: float, col: Color) -> void:
	draw_flag(self, p, s, col)


func _star(p: Vector2, s: float, col: Color) -> void:
	draw_star(self, p, s, col)


# ------------------------------------------------------------------ icons (also used by WorldMap)
static func draw_arrow(ci: CanvasItem, p: Vector2, dir: Vector3, s: float, col: Color) -> void:
	var a := atan2(dir.x, -dir.z)
	var pts := PackedVector2Array([Vector2(0, -s), Vector2(s * 0.7, s * 0.8), Vector2(0, s * 0.35), Vector2(-s * 0.7, s * 0.8)])
	for i in pts.size():
		pts[i] = p + pts[i].rotated(a)
	ci.draw_colored_polygon(pts, col)
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.85), 1.5)


static func draw_flag(ci: CanvasItem, p: Vector2, s: float, col: Color) -> void:
	ci.draw_line(p + Vector2(0, s), p + Vector2(0, -s), Color(0.3, 0.2, 0.1), 1.5)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, -s * 0.6), p + Vector2(0, -s * 0.2)]), col)


static func draw_star(ci: CanvasItem, p: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var r := s if i % 2 == 0 else s * 0.45
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(p + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(pts, col)
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.3, 0.15, 0.0, 0.9), 1.5)


static func draw_diamond(ci: CanvasItem, p: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
	ci.draw_colored_polygon(pts, col)
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.6), 1.0)
