class_name MiniEnemy
extends CharacterBody3D
## Small enemy of an island (not a boss). The same script is used by every mini enemy: each
## island only needs a scene with its own model and an animation library with the animations
## idle, walk, attack, hurt and death (see scenes/enemies/evil_mushroom.tscn).
##
## State machine:
##   WANDER -> walks to random points around the place where it was put (home), with pauses.
##   CHASE  -> a player (Luffy or Zoro) came closer than detect_radius: it goes after him.
##   ATTACK -> close enough: plays "attack"; the animation calls _on_attack_impact().
##   HURT   -> was hit: short stop and knockback.
##   DEAD   -> no health left: plays "death" and disappears.
## It never goes into the sea, and gives up the chase if the player swims or runs far from home.
## Nodes used: Model, AnimationPlayer, HealthBar (Back/Fill, only shown after the first hit),
## HitSound, AttackSound, DeathSound, AttackCooldown.

signal defeated(enemy: MiniEnemy)

enum State { WANDER, CHASE, ATTACK, HURT, DEAD }

@export var display_name := "Enemy"
@export var anim_library := "mushroom"
@export var max_health := 45.0
@export var damage := 12.0
@export var walk_speed := 1.4
@export var chase_speed := 3.6
@export var detect_radius := 9.0
## The chase ends if the player gets this far from the enemy's home.
@export var leash_radius := 22.0
@export var wander_radius := 7.0
@export var attack_range := 1.5
@export var gravity := 22.0
@export var knockback_strength := 5.0
## Experience that Luffy gets for defeating it.
@export var xp_reward := 12
## Pickup scene that it can leave when it is defeated (meat or tangerines) and the chance (0..1).
@export var drop_scene: PackedScene
@export var drop_chance := 0.35

@onready var model: Node3D = $Model
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var health_bar: Node3D = $HealthBar
@onready var health_fill: Node3D = $HealthBar/Fill
@onready var hit_sound: AudioStreamPlayer3D = $HitSound
@onready var attack_sound: AudioStreamPlayer3D = $AttackSound
@onready var death_sound: AudioStreamPlayer3D = $DeathSound
@onready var attack_cooldown: Timer = $AttackCooldown

var state: int = State.WANDER
var health := 45.0
var home := Vector3.ZERO
var target: Player
var facing := Vector3.FORWARD
var knockback := Vector3.ZERO
var _wander_goal := Vector3.ZERO
var _pause := 0.0
var _state_time := 0.0
var _flash := 0.0
var _flash_mat: StandardMaterial3D
var _meshes: Array = []
var _think := 0.0


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	home = global_position
	_wander_goal = home
	_pause = randf_range(0.5, 2.0)
	health_bar.visible = false
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.albedo_color = Color(1, 0.3, 0.25, 0.6)
	anim.animation_finished.connect(_on_animation_finished)
	_play("idle")


func is_defeated() -> bool:
	return state == State.DEAD


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


func _physics_process(delta: float) -> void:
	_state_time += delta
	var move := Vector3.ZERO
	match state:
		State.WANDER:
			move = _wander(delta)
			_think -= delta
			if _think <= 0.0:
				_think = 0.25
				var p := _closest_player(detect_radius)
				if p:
					target = p
					_set_state(State.CHASE)
		State.CHASE:
			if not _target_ok() or target.global_position.distance_to(home) > leash_radius:
				target = null
				_set_state(State.WANDER)
			else:
				var to := _flat(target.global_position - global_position)
				if to.length() <= attack_range and attack_cooldown.is_stopped():
					facing = to.normalized()
					_set_state(State.ATTACK)
					_play("attack", true)
					attack_sound.play()
				elif to.length() > attack_range * 0.8:
					move = to.normalized() * chase_speed
		State.HURT:
			if _state_time > 0.4:
				_set_state(State.CHASE if _target_ok() else State.WANDER)
		State.DEAD, State.ATTACK:
			pass
	# never walk into the sea: on the wet sand it turns back home
	if move.length() > 0.0 and global_position.y < 0.25:
		move = _flat(home - global_position).normalized() * walk_speed
		if state == State.CHASE:
			target = null
			_set_state(State.WANDER)
	velocity.x = move.x + knockback.x
	velocity.z = move.z + knockback.z
	knockback = knockback.move_toward(Vector3.ZERO, 18.0 * delta)
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()
	if move.length() > 0.1:
		facing = Vector3(move.x, 0, move.z).normalized()
	rotation.y = lerp_angle(rotation.y, atan2(facing.x, facing.z), clampf(8.0 * delta, 0.0, 1.0))
	if state == State.WANDER or state == State.CHASE:
		if move.length() > 0.1:
			_play("walk")
			anim.speed_scale = clampf(move.length() / walk_speed, 0.8, 2.2)
		else:
			_play("idle")
			anim.speed_scale = 1.0


func _wander(delta: float) -> Vector3:
	if _pause > 0.0:
		_pause -= delta
		return Vector3.ZERO
	var to := _flat(_wander_goal - global_position)
	if to.length() < 0.5:
		_pause = randf_range(1.0, 3.0)
		var a := randf() * TAU
		_wander_goal = home + Vector3(cos(a), 0, sin(a)) * randf_range(1.5, wander_radius)
		return Vector3.ZERO
	return to.normalized() * walk_speed


func _closest_player(radius: float) -> Player:
	var best: Player = null
	var best_d := radius
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p == null or p.dead or p.swimming or p.control == Player.Controller.NONE:
			continue
		var d := p.global_position.distance_to(global_position)
		if d < best_d:
			best = p
			best_d = d
	return best


func _target_ok() -> bool:
	return target != null and is_instance_valid(target) and not target.dead and not target.swimming


## Called by the "attack" animation when the head hits.
func _on_attack_impact() -> void:
	if state != State.ATTACK or not _target_ok():
		return
	var to := _flat(target.global_position - global_position)
	if to.length() <= attack_range + 0.7 and to.normalized().dot(facing) > 0.3:
		target.receive_hit(damage, global_position)


## Strong pushes of Luffy's skills.
func apply_knockback(v: Vector3) -> void:
	if state != State.DEAD:
		knockback = Vector3(v.x, 0.0, v.z)


## Called by the attacks of Luffy and Zoro.
func receive_hit(amount: float, from_pos: Vector3) -> void:
	if state == State.DEAD:
		return
	health = maxf(0.0, health - amount)
	health_bar.visible = true
	health_fill.scale.x = maxf(0.001, health / max_health)
	hit_sound.play()
	for m in _meshes:
		(m as MeshInstance3D).material_overlay = _flash_mat
	_flash = 0.15
	var away := _flat(global_position - from_pos)
	if away.length() > 0.05:
		knockback = away.normalized() * knockback_strength
	if health <= 0.0:
		_die()
		return
	if target == null:
		target = _closest_player(leash_radius)
	_set_state(State.HURT)
	_play("hurt", true)


func _die() -> void:
	_set_state(State.DEAD)
	collision_layer = 0
	health_bar.visible = false
	death_sound.play()
	_play("death", true)
	defeated.emit(self)
	if drop_scene and randf() < drop_chance:
		var item := drop_scene.instantiate() as Node3D
		item.set_meta("dynamic", true)
		get_parent().add_child(item)
		item.global_position = global_position + Vector3(0, 0.6, 0)
	get_tree().create_timer(2.5).timeout.connect(queue_free)


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == StringName(anim_library + "/attack") and state == State.ATTACK:
		attack_cooldown.start()
		_set_state(State.CHASE)


func _set_state(s: int) -> void:
	state = s
	_state_time = 0.0


func _play(n: String, restart := false) -> void:
	var full := anim_library + "/" + n
	if anim.current_animation == full and not restart:
		return
	anim.speed_scale = 1.0
	anim.play(full, 0.15)
	if restart:
		anim.seek(0.0, true)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
