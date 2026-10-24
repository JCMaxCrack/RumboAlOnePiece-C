class_name CompanionAI
extends Node
## Brain of a crew member that plays by himself (Zoro in single player, after he joins).
## It is a child node of the character (a Player with control = AI) and writes its ai_* inputs:
##   - if an enemy (group "enemies") is close to him and to the leader, he goes to fight it;
##   - otherwise he follows the leader, running when he is far;
##   - if he is stuck in front of something, he jumps; if he is very far, he appears next to the
##     leader (for example after Luffy sails, swims far or a checkpoint is loaded).

@export var leader: Node3D
@export var follow_distance := 3.5
@export var run_distance := 9.0
@export var teleport_distance := 45.0
@export var fight_radius := 10.0
@export var attack_range := 1.9

var _body: Player
var _stuck := 0.0
var _last := Vector3.ZERO
var _running := false
var _following := false
## Place in the formation around the leader (World gives every companion a different one, so
## they do not walk on top of each other): 0 left-behind, 1 right-behind, 2 behind...
var slot := 0
const SLOTS := [Vector2(-1.8, -2.0), Vector2(1.8, -2.0), Vector2(0.0, -3.4), Vector2(-2.6, -3.6)]


func _ready() -> void:
	_body = get_parent() as Player


func _physics_process(delta: float) -> void:
	if _body == null or leader == null or _body.control != Player.Controller.AI or _body.dead:
		return
	var me := _body.global_position
	var to_leader := leader.global_position - me
	to_leader.y = 0.0
	if to_leader.length() > teleport_distance:
		_body.global_position = leader.global_position - _leader_forward() * 2.5 + Vector3(0, 0.5, 0)
		_body.velocity = Vector3.ZERO
		return
	var enemy := _closest_enemy()
	var goal := Vector3.ZERO
	# Usopp shoots from far away
	var reach := 10.0 if _body.ranged_attack else attack_range
	if enemy:
		var to_enemy := enemy.global_position - me
		to_enemy.y = 0.0
		if to_enemy.length() <= reach:
			_body.facing = to_enemy.normalized()
			_body.ai_attack = true
			if _body.ranged_attack and to_enemy.length() < 5.0:
				goal = -to_enemy
		else:
			goal = to_enemy
		_running = _hysteresis(_running, to_enemy.length(), 4.0, 2.5)
		_body.ai_run = _running
	else:
		# Goes to his place next to the leader. He starts following / running at the far distance
		# but only stops when he is really close, so the animations do not restart at the limit.
		var spot := _slot_position()
		var to_spot := spot - me
		to_spot.y = 0.0
		var d := to_spot.length()
		_following = _hysteresis(_following, d, 2.2, 0.7)
		_running = _hysteresis(_running, d, run_distance, 2.5) and _following
		if _following:
			goal = to_spot
		_body.ai_run = _running
	# keep a little space from the other characters
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("players"):
		var o := other as Node3D
		if o == _body:
			continue
		var away := me - o.global_position
		away.y = 0.0
		var dist := away.length()
		if dist < 1.3 and dist > 0.01:
			push += away / dist * (1.3 - dist)
	if goal.length() > 0.3:
		goal = goal.normalized() + push * 1.5
	elif push.length() > 0.15:
		goal = push
	_body.ai_move = goal.normalized() if goal.length() > 0.15 else Vector3.ZERO
	# stuck against a rock or a wall: jump
	var moved := Vector2(me.x - _last.x, me.z - _last.z).length()
	_last = me
	if _body.ai_move.length() > 0.5 and moved < 0.01 and _body.is_on_floor():
		_stuck += delta
		if _stuck > 0.4:
			_body.ai_jump = true
			_stuck = 0.0
	else:
		_stuck = 0.0


## On when value goes above `on_above`, off again only below `off_below`.
func _hysteresis(state: bool, value: float, on_above: float, off_below: float) -> bool:
	if state:
		return value > off_below
	return value > on_above


## Where this companion walks: his slot of the formation behind the leader.
func _slot_position() -> Vector3:
	var f := _leader_forward()
	f.y = 0.0
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	var r := Vector3(-f.z, 0.0, f.x)
	var off: Vector2 = SLOTS[slot % SLOTS.size()]
	return leader.global_position + r * off.x + f * off.y


func _leader_forward() -> Vector3:
	var p := leader as Player
	return p.facing if p else Vector3.FORWARD


func _closest_enemy() -> Node3D:
	var best: Node3D = null
	var best_d := fight_radius
	for e in get_tree().get_nodes_in_group("enemies"):
		var n := e as Node3D
		if n == null or not n.is_inside_tree() or (n.has_method("is_defeated") and n.is_defeated()):
			continue
		var d := n.global_position.distance_to(_body.global_position)
		if d < best_d and n.global_position.distance_to(leader.global_position) < fight_radius * 1.6:
			best = n
			best_d = d
	return best
