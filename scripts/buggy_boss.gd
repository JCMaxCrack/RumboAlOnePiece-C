class_name BuggyBoss
extends CharacterBody3D
## Buggy (beta boss). Finite state machine:
##   PATROL -> walks between PatrolLeft and PatrolRight (Marker3D), pausing at each end.
##   CHASE  -> the player entered DetectionArea: runs toward him.
##   ATTACK -> the player is inside AttackArea: plays the "punch" animation; the
##             animation calls _on_punch_impact() at the moment the hand arrives.
##   RETURN -> the player left ChaseLimitArea for LoseTimer seconds (or jumped into the sea):
##             goes back to the patrol line.
##   DEFEATED -> Luffy's punches took all his health: plays "death" and stays on the ground.
## Nodes used (see scenes/enemies/buggy.tscn): AnimationPlayer, DetectionArea, ChaseLimitArea,
## AttackArea, PunchHitbox, PatrolPauseTimer, LoseTimer, AttackCooldown, StateLabel,
## DetectionRing, HealthBar (3D bar over his head) and the sound nodes.

enum State { PATROL, CHASE, ATTACK, RETURN, DEFEATED }

const STATE_TEXT := {State.PATROL: "Patrolling", State.CHASE: "Chasing!", State.ATTACK: "Attacking!", State.RETURN: "Returning", State.DEFEATED: "Defeated"}
const STATE_COLOR := {State.PATROL: Color(0.8, 0.95, 1.0), State.CHASE: Color(1, 0.45, 0.3), State.ATTACK: Color(1, 0.2, 0.2), State.RETURN: Color(1, 0.9, 0.4), State.DEFEATED: Color(0.6, 0.6, 0.6)}

signal state_changed(new_state: int)
signal health_changed(current: float, maximum: float)
signal defeated

@export var patrol_left: Marker3D
@export var patrol_right: Marker3D
@export var target: Player
@export var patrol_speed := 2.2
@export var chase_speed := 5.0   # slower than Luffy sprinting (6.8) so he can escape
@export var return_speed := 3.0
@export var punch_damage := 25.0
@export var max_health := 150.0
## Small push back when Luffy's punch hits him.
@export var hit_knockback := 4.0
@export var gravity := 22.0
@export var show_debug := true
## Experience that Luffy gets for defeating him.
@export var xp_reward := 80
@export var display_name := "Buggy the Clown"

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var detection_area: Area3D = $DetectionArea
@onready var chase_limit_area: Area3D = $ChaseLimitArea
@onready var attack_area: Area3D = $AttackArea
@onready var punch_hitbox: Area3D = $PunchHitbox
@onready var patrol_pause_timer: Timer = $PatrolPauseTimer
@onready var lose_timer: Timer = $LoseTimer
@onready var attack_cooldown: Timer = $AttackCooldown
@onready var state_label: Label3D = $StateLabel
@onready var detection_ring: MeshInstance3D = $DetectionRing
@onready var roar_sound: AudioStreamPlayer3D = $RoarSound
@onready var swing_sound: AudioStreamPlayer3D = $SwingSound
@onready var punch_sound: AudioStreamPlayer3D = $PunchSound
@onready var hit_sound: AudioStreamPlayer3D = $HitSound
@onready var health_bar: Node3D = $HealthBar
@onready var health_fill: Node3D = $HealthBar/Fill

var state: int = State.PATROL
var patrol_target: Marker3D
var facing := Vector3.RIGHT
var player_in_attack_range := false
var health := 150.0
var knockback := Vector3.ZERO
var _meshes: Array = []
var _flash_time := 0.0
var _flash_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	patrol_target = patrol_right
	for mi in $Model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.albedo_color = Color(1, 0.3, 0.25, 0.6)
	_set_state(State.PATROL)
	health_changed.emit(health, max_health)


func is_defeated() -> bool:
	return state == State.DEFEATED


## Strong pushes of Luffy's skills (bosses only move a little).
func apply_knockback(v: Vector3) -> void:
	if state != State.DEFEATED:
		knockback = Vector3(v.x, 0.0, v.z) * 0.4


## Called by Luffy's punch.
func receive_hit(damage: float, from_pos: Vector3) -> void:
	if state == State.DEFEATED:
		return
	health = maxf(0.0, health - damage)
	health_changed.emit(health, max_health)
	health_fill.scale.x = maxf(0.001, health / max_health)
	hit_sound.play()
	for m in _meshes:
		(m as MeshInstance3D).material_overlay = _flash_mat
	_flash_time = 0.15
	var away := Vector3(global_position.x - from_pos.x, 0, global_position.z - from_pos.z)
	if away.length() > 0.05:
		knockback = away.normalized() * hit_knockback
	if health <= 0.0:
		_defeat()
	elif state == State.PATROL or state == State.RETURN:
		_set_state(State.CHASE)


## Used when a saved game is loaded: Buggy keeps the health he had (0 = already defeated).
func restore(saved_health: float) -> void:
	health = clampf(saved_health, 0.0, max_health)
	health_fill.scale.x = maxf(0.001, health / max_health)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_defeat(true)


func _defeat(silent := false) -> void:
	_set_state(State.DEFEATED)
	velocity = Vector3.ZERO
	player_in_attack_range = false
	lose_timer.stop()
	patrol_pause_timer.stop()
	for a in [detection_area, chase_limit_area, attack_area, punch_hitbox]:
		(a as Area3D).set_deferred("monitoring", false)
	collision_layer = 0
	health_bar.visible = false
	anim.play("buggy/death", 0.1)
	if silent:
		anim.seek(anim.current_animation_length, true)
		return
	roar_sound.play()
	defeated.emit()


func _process(delta: float) -> void:
	# the health bar always faces the camera
	var cam := get_viewport().get_camera_3d()
	if cam and health_bar.visible:
		health_bar.global_basis = cam.global_basis
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			for m in _meshes:
				(m as MeshInstance3D).material_overlay = null


func set_debug_visible(on: bool) -> void:
	show_debug = on
	state_label.visible = on
	detection_ring.visible = on


func _set_state(s: int) -> void:
	if state == State.DEFEATED and s != State.DEFEATED:
		return
	state = s
	state_label.text = STATE_TEXT[s]
	state_label.modulate = STATE_COLOR[s]
	match s:
		State.CHASE:
			roar_sound.play()
			lose_timer.stop()
		State.RETURN:
			lose_timer.stop()
	state_changed.emit(s)


func _player_ok() -> bool:
	return target != null and is_instance_valid(target) and not target.dead


# ------------------------------------------------------------------ signals (connected in the scene)
func _on_detection_area_body_entered(body: Node3D) -> void:
	# in co-op Buggy goes after whoever comes into his area first (Luffy or Zoro)
	if body is Player and (state == State.PATROL or state == State.RETURN) and not (body as Player).dead and (body as Player).control != Player.Controller.NONE:
		target = body
		_set_state(State.CHASE)


func _on_chase_limit_area_body_exited(body: Node3D) -> void:
	if body == target and is_inside_tree() and (state == State.CHASE or state == State.ATTACK):
		lose_timer.start()


func _on_chase_limit_area_body_entered(body: Node3D) -> void:
	if body == target:
		lose_timer.stop()


func _on_lose_timer_timeout() -> void:
	if state == State.CHASE:  # during ATTACK the end of the punch decides
		_set_state(State.RETURN)


func _on_attack_area_body_entered(body: Node3D) -> void:
	if body == target:
		player_in_attack_range = true


func _on_attack_area_body_exited(body: Node3D) -> void:
	if body == target:
		player_in_attack_range = false


func _on_patrol_pause_timer_timeout() -> void:
	patrol_target = patrol_left if patrol_target == patrol_right else patrol_right


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"buggy/punch" and state != State.DEFEATED:
		attack_cooldown.start()
		# if the player escaped while Buggy was punching, he gives up the chase
		var still_near := _player_ok() and chase_limit_area.overlaps_body(target)
		_set_state(State.CHASE if still_near else State.RETURN)


## Called by the "punch" animation (method track) when the hand reaches its target.
func _on_punch_impact() -> void:
	if state != State.DEFEATED and _player_ok() and punch_hitbox.overlaps_body(target):
		target.receive_hit(punch_damage, global_position)
		punch_sound.play()


func _on_punch_start() -> void:
	swing_sound.play()


# ------------------------------------------------------------------ movement
func _physics_process(delta: float) -> void:
	var move := Vector3.ZERO
	if state == State.DEFEATED:
		velocity = Vector3(0, velocity.y - gravity * delta if not is_on_floor() else 0.0, 0)
		move_and_slide()
		return
	match state:
		State.PATROL:
			move = _patrol()
		State.CHASE:
			if not _player_ok() or target.swimming:
				_set_state(State.RETURN)
			elif player_in_attack_range and attack_cooldown.is_stopped():
				_set_state(State.ATTACK)
				facing = _dir_to(target.global_position)
				anim.play("buggy/punch")
			elif player_in_attack_range:
				facing = _dir_to(target.global_position)  # close enough: wait for the cooldown
			else:
				move = _dir_to(target.global_position) * chase_speed
		State.RETURN:
			var back := _closest_patrol_point()
			if _flat_distance(global_position, back) < 0.6:
				patrol_target = patrol_right if _flat_distance(global_position, patrol_left.global_position) < _flat_distance(global_position, patrol_right.global_position) else patrol_left
				_set_state(State.PATROL)
				for b in detection_area.get_overlapping_bodies():
					if b is Player and not (b as Player).dead and (b as Player).control != Player.Controller.NONE:
						target = b
				if _player_ok() and detection_area.overlaps_body(target):
					_set_state(State.CHASE)
			else:
				move = _dir_to(back) * return_speed
	velocity.x = move.x + knockback.x
	velocity.z = move.z + knockback.z
	knockback = knockback.move_toward(Vector3.ZERO, 20.0 * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	if move.length() > 0.1:
		facing = Vector3(move.x, 0, move.z).normalized()
	rotation.y = lerp_angle(rotation.y, atan2(facing.x, facing.z), clampf(10.0 * delta, 0.0, 1.0))
	_update_animation(move.length())


func _patrol() -> Vector3:
	if not patrol_pause_timer.is_stopped():
		return Vector3.ZERO
	if _flat_distance(global_position, patrol_target.global_position) < 0.4:
		patrol_pause_timer.start()
		return Vector3.ZERO
	return _dir_to(patrol_target.global_position) * patrol_speed


func _update_animation(speed: float) -> void:
	if state == State.ATTACK or state == State.DEFEATED:
		return
	var wanted := "buggy/idle"
	if speed > 3.5:
		wanted = "buggy/run"
	elif speed > 0.1:
		wanted = "buggy/walk"
	if anim.current_animation != wanted:
		anim.play(wanted, 0.2)


func _dir_to(p: Vector3) -> Vector3:
	var d := Vector3(p.x - global_position.x, 0, p.z - global_position.z)
	return d.normalized() if d.length() > 0.01 else Vector3.ZERO


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _closest_patrol_point() -> Vector3:
	var a := patrol_left.global_position
	var b := patrol_right.global_position
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var p := Vector2(global_position.x - a.x, global_position.z - a.z)
	var t := clampf(p.dot(ab) / ab.length_squared(), 0.0, 1.0)
	return Vector3(a.x + ab.x * t, global_position.y, a.z + ab.y * t)


## Puts Buggy back at the start of his patrol (used when the level restarts).
func reset_to(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	patrol_target = patrol_right
	lose_timer.stop()
	attack_cooldown.stop()
	player_in_attack_range = false
	anim.play("buggy/idle")
	_set_state(State.PATROL)
