class_name Boss
extends CharacterBody3D
## Boss of an island (Kuro in Villa Syrup, Garp in Whisky Peak). Finite state machine:
##   PATROL  -> walks along the Marker3D of patrol_path (in order, pausing at each one).
##   ALERT   -> he saw a player (inside vision_range and vision_angle, and nothing in between:
##              a ray against the walls): he stops for a moment and roars.
##   CHASE   -> runs after him. If he loses him from view for lose_time, he goes back.
##   ATTACK  -> close enough: one of his attack animations; the animation calls _on_attack_hit().
##   SPECIAL -> his special move (special_kind):
##                "shakushi": Kuro disappears and appears behind the player with a claw storm;
##                "fist":     Garp jumps and hits the ground: a shock wave around the target;
##              and from far away Garp throws cannonballs (throw_range).
##   RETURN  -> goes back to the closest patrol point.
##   DEFEATED-> plays "death" and stays on the ground.
## Under rage_at of his health he gets angry: faster and with shorter waits. Kuro can also dodge
## hits (dodge_chance). Being hit always makes him chase the one who hit him.
## Nodes used: Model, AnimationPlayer (library anim_library: idle, walk, run, attack, attack2,
## special, hurt, death and, for Garp, throw), Eye (Marker3D at the height of his eyes),
## HealthBar (Back/Fill), RoarSound, SwingSound, HitSound, PunchSound.

signal state_changed(new_state: int)
signal health_changed(current: float, maximum: float)
signal defeated
## Short sentences the island shows in the HUD ("¡Ahora sí me enojé!").
signal taunt(text: String)

enum State { PATROL, ALERT, CHASE, ATTACK, SPECIAL, RETURN, DEFEATED }

const STATE_TEXT := {State.PATROL: "Patrolling", State.ALERT: "He saw you!", State.CHASE: "Chasing!", State.ATTACK: "Attacking!",
	State.SPECIAL: "Special attack!", State.RETURN: "Returning", State.DEFEATED: "Defeated"}

@export var display_name := "Kuro"
@export var anim_library := "kuro"
@export var patrol_path: NodePath
@export var max_health := 420.0
@export var walk_speed := 2.0
@export var chase_speed := 6.2
@export var damage := 18.0
@export var attack_range := 2.3
@export var attack_cooldown := 0.9
@export var vision_range := 16.0
@export var vision_angle := 70.0
@export var lose_time := 5.0
@export_enum("shakushi", "fist") var special_kind := "shakushi"
@export var special_cooldown := 8.0
@export var special_damage := 30.0
@export var special_radius := 3.5
## Garp: throws cannonballs at players farther than this (0 = never).
@export var throw_range := 0.0
@export var dodge_chance := 0.0
@export var rage_at := 0.5
@export var xp_reward := 150
@export var gravity := 22.0

@onready var model: Node3D = $Model
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var eye: Marker3D = $Eye
@onready var health_bar: Node3D = $HealthBar
@onready var health_fill: Node3D = $HealthBar/Fill
@onready var roar_sound: AudioStreamPlayer3D = $RoarSound
@onready var swing_sound: AudioStreamPlayer3D = $SwingSound
@onready var hit_sound: AudioStreamPlayer3D = $HitSound
@onready var punch_sound: AudioStreamPlayer3D = $PunchSound

var state: int = State.PATROL
var health := 420.0
var target: Player
var facing := Vector3.FORWARD
var knockback := Vector3.ZERO
var enraged := false
var _points: Array[Vector3] = []
var _point_index := 0
var _pause := 0.0
var _state_time := 0.0
var _think := 0.0
var _unseen := 0.0
var _attack_wait := 0.0
var _special_wait := 4.0
var _throw_wait := 3.0
var _flash := 0.0
var _flash_mat: StandardMaterial3D
var _meshes: Array = []
var _special_target := Vector3.ZERO
var _home := Vector3.ZERO


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("bosses")
	health = max_health
	_home = global_position
	var path := get_node_or_null(patrol_path)
	if path:
		for c in path.get_children():
			if c is Node3D:
				_points.append((c as Node3D).global_position)
	if _points.is_empty():
		_points.append(global_position)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.albedo_color = Color(1, 0.3, 0.25, 0.6)
	anim.animation_finished.connect(_on_animation_finished)
	health_bar.visible = false
	_play("idle")
	health_changed.emit(health, max_health)


func is_defeated() -> bool:
	return state == State.DEFEATED


func state_text() -> String:
	return STATE_TEXT[state]


# ------------------------------------------------------------------ damage
func receive_hit(amount: float, from_pos: Vector3) -> void:
	if state == State.DEFEATED:
		return
	if dodge_chance > 0.0 and state != State.ATTACK and state != State.SPECIAL and randf() < dodge_chance:
		_dodge(from_pos)
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	health_fill.scale.x = maxf(0.001, health / max_health)
	health_bar.visible = true
	hit_sound.play()
	for m in _meshes:
		(m as MeshInstance3D).material_overlay = _flash_mat
	_flash = 0.15
	if health <= 0.0:
		_defeat()
		return
	if not enraged and health <= max_health * rage_at:
		enraged = true
		taunt.emit("Now you made me angry!")
		roar_sound.play()
	# he always goes after the one who hit him
	var attacker := _closest_player(4.0, false)
	if attacker and (state == State.PATROL or state == State.RETURN or state == State.ALERT):
		target = attacker
		_set_state(State.CHASE)


func apply_knockback(v: Vector3) -> void:
	if state != State.DEFEATED:
		knockback = Vector3(v.x, 0.0, v.z) * 0.35


## Saved games: the boss keeps his health (0 = already defeated).
func restore(saved_health: float) -> void:
	health = clampf(saved_health, 0.0, max_health)
	health_fill.scale.x = maxf(0.001, health / max_health)
	health_changed.emit(health, max_health)
	enraged = health <= max_health * rage_at
	if health <= 0.0:
		_defeat(true)


func _defeat(silent := false) -> void:
	_set_state(State.DEFEATED)
	velocity = Vector3.ZERO
	collision_layer = 0
	health_bar.visible = false
	model.visible = true
	_play("death", true)
	if silent:
		anim.seek(anim.current_animation_length, true)
		return
	roar_sound.play()
	defeated.emit()


func _dodge(from_pos: Vector3) -> void:
	var away := global_position - from_pos
	away.y = 0.0
	var side := away.normalized().cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
	FX.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(0.1, 0.1, 0.12), 14, 3.0, 0.12, 0.0, 0.35)
	global_position += side * 2.2
	FX.text(get_parent(), global_position + Vector3(0, 2.4, 0), tr("Too slow!"), Color(0.8, 0.85, 1.0), 40)


# ------------------------------------------------------------------ states
func _set_state(s: int) -> void:
	if state == State.DEFEATED and s != State.DEFEATED:
		return
	var old := state
	state = s
	_state_time = 0.0
	if s == State.CHASE and old != State.CHASE and old != State.ATTACK and old != State.SPECIAL:
		roar_sound.play()
	state_changed.emit(s)


func _physics_process(delta: float) -> void:
	_state_time += delta
	_attack_wait -= delta
	_special_wait -= delta
	_throw_wait -= delta
	var speed_k := 1.25 if enraged else 1.0
	var move := Vector3.ZERO
	match state:
		State.DEFEATED:
			velocity = Vector3(0, velocity.y - gravity * delta if not is_on_floor() else 0.0, 0)
			move_and_slide()
			return
		State.PATROL:
			move = _patrol(delta)
			_look_for_players(delta)
		State.ALERT:
			if _target_ok():
				facing = _dir_to(target.global_position)
			if _state_time > 0.7:
				_set_state(State.CHASE)
		State.CHASE:
			move = _chase(delta, speed_k)
		State.RETURN:
			var p := _points[_point_index]
			if _flat(p - global_position).length() < 0.6:
				_set_state(State.PATROL)
			else:
				move = _dir_to(p) * walk_speed * 1.5
			_look_for_players(delta)
		State.ATTACK, State.SPECIAL:
			if _target_ok() and state == State.ATTACK and _state_time < 0.25:
				facing = _dir_to(target.global_position)
	velocity.x = move.x + knockback.x
	velocity.z = move.z + knockback.z
	knockback = knockback.move_toward(Vector3.ZERO, 20.0 * delta)
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()
	if move.length() > 0.1:
		facing = Vector3(move.x, 0, move.z).normalized()
	rotation.y = lerp_angle(rotation.y, atan2(facing.x, facing.z), clampf(10.0 * delta, 0.0, 1.0))
	if state == State.PATROL or state == State.CHASE or state == State.RETURN or state == State.ALERT:
		if move.length() > 3.5:
			_play("run")
		elif move.length() > 0.1:
			_play("walk")
		else:
			_play("idle")


func _patrol(delta: float) -> Vector3:
	if _pause > 0.0:
		_pause -= delta
		return Vector3.ZERO
	var p := _points[_point_index]
	if _flat(p - global_position).length() < 0.5:
		_pause = randf_range(1.0, 2.2)
		_point_index = (_point_index + 1) % _points.size()
		return Vector3.ZERO
	return _dir_to(p) * walk_speed


func _chase(delta: float, k: float) -> Vector3:
	if not _target_ok():
		target = _closest_player(vision_range, true)
		if target == null:
			_set_state(State.RETURN)
		return Vector3.ZERO
	var to := _flat(target.global_position - global_position)
	var dist := to.length()
	# does he still see him?
	_think -= delta
	if _think <= 0.0:
		_think = 0.25
		if _can_see(target):
			_unseen = 0.0
		else:
			_unseen += 0.25
	if _unseen > lose_time:
		target = null
		_unseen = 0.0
		_set_state(State.RETURN)
		return Vector3.ZERO
	if _special_wait <= 0.0 and dist > 2.5 and dist < 12.0 and target.is_on_floor():
		_start_special()
		return Vector3.ZERO
	if throw_range > 0.0 and dist > throw_range and _throw_wait <= 0.0:
		_throw()
		return Vector3.ZERO
	if dist <= attack_range:
		facing = to.normalized()
		if _attack_wait <= 0.0:
			_start_attack()
		return Vector3.ZERO
	return to.normalized() * chase_speed * k


func _start_attack() -> void:
	_set_state(State.ATTACK)
	var options := ["attack"]
	if anim.has_animation(anim_library + "/attack2"):
		options.append("attack2")
	_play(options.pick_random(), true)
	swing_sound.play()


## Called by the attack animations when the blow arrives.
func _on_attack_hit() -> void:
	if state == State.SPECIAL:
		_on_special_hit()
		return
	if state != State.ATTACK or not _target_ok():
		return
	var to := _flat(target.global_position - global_position)
	if to.length() <= attack_range + 0.8 and to.normalized().dot(facing) > 0.2:
		target.receive_hit(damage * (1.2 if enraged else 1.0), global_position)
		punch_sound.play()


func _start_special() -> void:
	_set_state(State.SPECIAL)
	_special_wait = special_cooldown * (0.7 if enraged else 1.0)
	_special_target = target.global_position
	if special_kind == "shakushi":
		# Pasos sin sonido: he vanishes and appears behind the player
		FX.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(0.08, 0.08, 0.1), 24, 4.0, 0.15, 0.0, 0.4)
		model.visible = false
		var behind := target.global_position - target.facing * 2.0
		get_tree().create_timer(0.45).timeout.connect(func():
			if state != State.SPECIAL:
				return
			global_position = Vector3(behind.x, maxf(global_position.y, target.global_position.y) + 0.2, behind.z)
			model.visible = true
			FX.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(0.08, 0.08, 0.1), 24, 4.0, 0.15, 0.0, 0.4)
			if _target_ok():
				facing = _dir_to(target.global_position)
			taunt.emit("Shakushi!")
			_play("special", true))
	else:
		# Puño del amor: a warning ring where the player is, then the blow
		FX.ring(get_parent(), _special_target, special_radius, Color(1, 0.3, 0.2, 0.9), 0.9)
		taunt.emit("Fist of Love!")
		facing = _dir_to(_special_target)
		_play("special", true)
	swing_sound.play()


func _on_special_hit() -> void:
	var center := global_position if special_kind == "shakushi" else _special_target
	FX.ring(get_parent(), center, special_radius, Color(1, 0.75, 0.4, 0.9), 0.5)
	FX.burst(get_parent(), center + Vector3(0, 0.3, 0), Color(0.7, 0.6, 0.5), 30, 5.0, 0.14, -12.0, 0.8)
	punch_sound.play()
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p and not p.dead and p.control != Player.Controller.NONE and _flat(p.global_position - center).length() < special_radius:
			p.receive_hit(special_damage * (1.2 if enraged else 1.0), center)


## Garp throws a cannonball (with his hand!) at a player far away.
func _throw() -> void:
	_throw_wait = 3.5 * (0.7 if enraged else 1.0)
	_set_state(State.ATTACK)
	facing = _dir_to(target.global_position)
	_play("throw" if anim.has_animation(anim_library + "/throw") else "attack", true)
	var aim := target.global_position
	get_tree().create_timer(0.45).timeout.connect(func():
		if state == State.DEFEATED:
			return
		var ball := CannonBall.new()
		get_parent().add_child(ball)
		ball.launch(global_position + Vector3(0, 2.2, 0) + facing * 0.6, aim, damage * 1.3))


func _on_animation_finished(anim_name: StringName) -> void:
	var n := str(anim_name).get_slice("/", 1)
	if state == State.ATTACK and (n == "attack" or n == "attack2" or n == "throw"):
		_attack_wait = attack_cooldown * (0.7 if enraged else 1.0)
		_set_state(State.CHASE)
	elif state == State.SPECIAL and n == "special":
		model.visible = true
		_attack_wait = attack_cooldown
		_set_state(State.CHASE)


# ------------------------------------------------------------------ vision
func _look_for_players(delta: float) -> void:
	_think -= delta
	if _think > 0.0:
		return
	_think = 0.2
	var p := _closest_player(vision_range, true)
	if p:
		target = p
		_set_state(State.ALERT)


## Closest player he can see (with see = false: just the closest one inside radius).
func _closest_player(radius: float, see: bool) -> Player:
	var best: Player = null
	var best_d := radius
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p == null or p.dead or p.control == Player.Controller.NONE:
			continue
		var d := p.global_position.distance_to(global_position)
		if d >= best_d:
			continue
		if see and not _can_see(p):
			continue
		best = p
		best_d = d
	return best


func _can_see(p: Player) -> bool:
	var to := p.global_position - global_position
	var d := to.length()
	if d > vision_range:
		return false
	# very close he notices him even from behind
	if d > 2.5 and _flat(to).normalized().dot(facing) < cos(deg_to_rad(vision_angle)):
		return false
	var q := PhysicsRayQueryParameters3D.create(eye.global_position, p.global_position + Vector3(0, 1.2, 0), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _target_ok() -> bool:
	return target != null and is_instance_valid(target) and not target.dead and target.control != Player.Controller.NONE


# ------------------------------------------------------------------ helpers
func _process(delta: float) -> void:
	if health_bar.visible:
		var cam := get_viewport().get_camera_3d()
		if cam:
			health_bar.global_basis = cam.global_basis
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			for m in _meshes:
				(m as MeshInstance3D).material_overlay = null


func _play(n: String, restart := false) -> void:
	var full := anim_library + "/" + n
	if not anim.has_animation(full):
		return
	if anim.current_animation == full and not restart:
		return
	anim.play(full, 0.15)
	if restart:
		anim.seek(0.0, true)


func _dir_to(p: Vector3) -> Vector3:
	var d := _flat(p - global_position)
	return d.normalized() if d.length() > 0.01 else facing


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
