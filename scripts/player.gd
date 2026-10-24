class_name Player
extends CharacterBody3D
## A playable character: Luffy (Gomu Gomu punch), Zoro (katana), Usopp (slingshot) or Nami.
## Walk, sprint, jump, swim and attack. Luffy can also eat food from the inventory (animation
## "eat", its method track calls _on_bite()) and use the skills learned in the skill shop
## (animations "skill_<id>", their method tracks call _on_skill_hit()). Who controls it (control):
##   PLAYER_ONE: keyboard + mouse (and a gamepad in single player), touch controls on phones.
##   PLAYER_TWO: local co-op, the gamepad of player 2 (actions "p2_*", see GameSession).
##   AI: a companion (CompanionAI writes ai_move / ai_run / ai_jump / ai_attack).
##   NONE: stands still (Zoro tied up before he joins the crew).
## Nodes used (see scenes/player/luffy.tscn and zoro.tscn):
##   Model, AnimationPlayer (library anim_library), CameraPivot/SpringArm3D/Camera3D, PunchHitbox,
##   HurtSound, JumpSound, SplashSound, SwingSound, PunchSound, InvulnerabilityTimer, HurtTimer,
##   AttackTimer. Optional: the weapon node (weapon_path), shown only while attacking.

signal health_changed(current: float, maximum: float)
signal died

enum Controller { PLAYER_ONE, PLAYER_TWO, AI, NONE }

@export var control: Controller = Controller.PLAYER_ONE
@export var display_name := "Luffy"
## Name of the animation library in the AnimationPlayer ("luffy", "zoro").
@export var anim_library := "luffy"
## Weapon node (Zoro's katana). Empty for Luffy.
@export var weapon_path: NodePath
## true: the weapon is always in the hand (except swimming); false: only while attacking.
@export var weapon_always_visible := false
## Turn of the model when it looks forward (a model made facing -Z needs PI).
@export var model_yaw := 0.0
## Usopp: the attack shoots a pellet with the slingshot instead of hitting what is in front.
@export var ranged_attack := false

@export var max_health := 100.0
@export var walk_speed := 3.2
@export var run_speed := 6.8
@export var jump_velocity := 7.5
@export var gravity := 22.0
@export var mouse_sensitivity := 0.003
@export var knockback_force := 9.0
## The Mixamo jump starts with a crouch: it is skipped so the animation matches the physics.
@export var jump_anim_start := 0.12
@export var jump_anim_speed := 1.15
@export_group("Swimming")
## Height of the sea surface (the Water node of the island).
@export var water_level := 0.0
@export var swim_speed := 3.0
@export var swim_sprint_speed := 4.8
## When the water is deeper than this (from the feet), Luffy starts swimming.
@export var swim_enter_depth := 1.15
## While swimming the feet float this far under the surface.
@export var swim_float_depth := 0.8
## Small jump to get out of the water onto low ground.
@export var swim_jump_velocity := 5.5
@export_group("Punch")
@export var punch_damage := 15.0
@export var punch_reach := 1.7
@export var attack_move_factor := 0.3

@onready var model: Node3D = $Model
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var punch_hitbox: Area3D = $PunchHitbox
@onready var hurt_sound: AudioStreamPlayer3D = $HurtSound
@onready var jump_sound: AudioStreamPlayer3D = $JumpSound
@onready var splash_sound: AudioStreamPlayer3D = $SplashSound
@onready var swing_sound: AudioStreamPlayer3D = $SwingSound
@onready var punch_sound: AudioStreamPlayer3D = $PunchSound
@onready var invulnerability_timer: Timer = $InvulnerabilityTimer
@onready var hurt_timer: Timer = $HurtTimer
@onready var attack_timer: Timer = $AttackTimer

var health := 100.0
var facing := Vector3.FORWARD
var knockback := Vector3.ZERO
var dead := false
var swimming := false
var controls_enabled := true
var _current_anim := ""
var _current_speed := 1.0
var _shake := 0.0
var _weapon: Node3D
## Written by CompanionAI when control == AI (direction in world space, 0..1 long).
var ai_move := Vector3.ZERO
var ai_run := false
var ai_jump := false
var ai_attack := false
## Eating food or doing a skill: the character does not move or attack meanwhile.
var eating := false
var skill_active := ""
var _busy_left := 0.0
var _eat_heal := 0.0
var _skill_damage := 0.0
var _skill := {}
var _skill_cd := {}
var _eat_sound: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("players")
	if control == Controller.PLAYER_ONE:
		add_to_group("player")
	if not weapon_path.is_empty():
		_weapon = get_node_or_null(weapon_path) as Node3D
	health = max_health
	health_changed.emit(health, max_health)
	_eat_sound = AudioStreamPlayer3D.new()
	_eat_sound.stream = load("res://assets/audio/pickup.wav")
	_eat_sound.pitch_scale = 1.5
	_eat_sound.volume_db = -6.0
	add_child(_eat_sound)
	_show_food("")
	_play("idle")


## Name of an input action for this player ("jump" for player 1, "p2_jump" for player 2).
func action(name: String) -> String:
	return "p2_" + name if control == Controller.PLAYER_TWO else name


## Player 1 or player 2 (only if its input actions exist: GameSession makes those of player 2).
func is_human() -> bool:
	if control == Controller.PLAYER_TWO:
		return InputMap.has_action("p2_jump")
	return control == Controller.PLAYER_ONE


func _unhandled_input(event: InputEvent) -> void:
	if control != Controller.PLAYER_ONE or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		look((event as InputEventMouseMotion).relative)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		attack()


## Rotates the camera (mouse, right stick or a finger on the touch screen).
func look(rel: Vector2) -> void:
	camera_pivot.rotation.y -= rel.x * mouse_sensitivity
	spring_arm.rotation.x = clampf(spring_arm.rotation.x - rel.y * mouse_sensitivity, -1.1, 0.35)


func _process(delta: float) -> void:
	if is_human():
		var stick := Input.get_vector(action("look_left"), action("look_right"), action("look_up"), action("look_down"))
		if stick.length() > 0.1:
			look(stick * 900.0 * delta)
	if _weapon:
		_weapon.visible = is_attacking() or (weapon_always_visible and not swimming)
	for id in _skill_cd:
		_skill_cd[id] = maxf(0.0, float(_skill_cd[id]) - delta)
	# blink while invulnerable (not while inflated with Gomu Gomu no Fusen)
	model.visible = invulnerability_timer.is_stopped() or skill_active == "fusen" or int(invulnerability_timer.time_left * 16.0) % 2 == 0
	if _shake > 0.0:
		camera.h_offset = randf_range(-1.0, 1.0) * _shake
		camera.v_offset = randf_range(-1.0, 1.0) * _shake
		_shake = move_toward(_shake, 0.0, delta * 1.6)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func _physics_process(delta: float) -> void:
	if _busy_left > 0.0:
		_busy_left -= delta
		if _busy_left <= 0.0:
			_end_busy()
	var can_move := controls_enabled and not dead and hurt_timer.is_stopped() and control != Controller.NONE and not is_busy()
	var move := Vector3.ZERO
	var running := false
	var jump_pressed := false
	if control == Controller.AI:
		move = Vector3(ai_move.x, 0, ai_move.z).limit_length(1.0) if can_move else Vector3.ZERO
		running = ai_run
		jump_pressed = can_move and ai_jump
		if can_move and ai_attack:
			attack()
		ai_jump = false
		ai_attack = false
	elif is_human():
		if can_move and Input.is_action_just_pressed(action("attack")):
			attack()
		var input := Input.get_vector(action("move_left"), action("move_right"), action("move_forward"), action("move_back")) if can_move else Vector2.ZERO
		var basis_y := camera_pivot.global_transform.basis
		var forward := Vector3(-basis_y.z.x, 0, -basis_y.z.z).normalized()
		var right := Vector3(basis_y.x.x, 0, basis_y.x.z).normalized()
		move = right * input.x + forward * -input.y
		if move.length() > 1.0:
			move = move.normalized()
		running = Input.is_action_pressed(action("sprint"))
		jump_pressed = can_move and Input.is_action_just_pressed(action("jump"))
	_update_swimming()
	var speed := run_speed if running else walk_speed
	if swimming:
		speed = swim_sprint_speed if running else swim_speed
	if is_attacking():
		speed *= attack_move_factor
	if move.length() > 0.05 and not is_attacking():
		facing = move.normalized()
	velocity.x = move.x * speed + knockback.x
	velocity.z = move.z * speed + knockback.z
	knockback = knockback.move_toward(Vector3.ZERO, 30.0 * delta)
	var float_y := water_level - swim_float_depth
	if swimming and global_position.y <= float_y + 0.05:
		# buoyancy: the body floats with the head out of the water
		velocity.y = lerpf(velocity.y, (float_y - global_position.y) * 4.0, clampf(6.0 * delta, 0.0, 1.0))
		if jump_pressed:
			velocity.y = swim_jump_velocity
			splash_sound.play()
	elif not is_on_floor():
		velocity.y -= gravity * delta
	elif jump_pressed:
		velocity.y = jump_velocity
		jump_sound.play()
		_play("jump", jump_anim_speed, jump_anim_start)
	move_and_slide()
	model.rotation.y = lerp_angle(model.rotation.y, atan2(facing.x, facing.z) + model_yaw, clampf(12.0 * delta, 0.0, 1.0))
	punch_hitbox.position = facing * punch_reach + Vector3(0, 1.1, 0)
	_update_animation(move, running)


func _update_swimming() -> void:
	var depth := water_level - global_position.y
	if not swimming and depth > swim_enter_depth:
		swimming = true
		velocity.y *= 0.25
		splash_sound.play()
		if is_attacking():
			attack_timer.stop()
	elif swimming and depth < swim_float_depth - 0.1 and is_on_floor():
		swimming = false


func is_attacking() -> bool:
	return not attack_timer.is_stopped()


## Eating or doing a skill.
func is_busy() -> bool:
	return eating or skill_active != ""


## Gomu Gomu no... Pistol! The "attack" animation calls _on_punch_impact() when the arm is stretched.
func attack() -> void:
	if dead or swimming or is_attacking() or is_busy() or not controls_enabled or not hurt_timer.is_stopped():
		return
	attack_timer.start()
	swing_sound.play()
	_play("attack", 1.0, 0.0, true)


func _on_punch_impact() -> void:
	if skill_active != "":
		_on_skill_hit()
		return
	if ranged_attack:
		_shoot()
		return
	for body in punch_hitbox.get_overlapping_bodies():
		if body != self and body.has_method("receive_hit"):
			body.receive_hit(punch_damage, global_position)
			punch_sound.play()
			_shake = 0.08


func _update_animation(move: Vector3, running: bool) -> void:
	if dead or not hurt_timer.is_stopped() or is_attacking() or is_busy():
		return
	if swimming:
		var moving := move.length() > 0.1
		_play("swim", (1.25 if running else 1.0) if moving else 0.4)
	elif not is_on_floor():
		if _current_anim != "jump":
			_play("jump", jump_anim_speed, 0.45)
	elif move.length() > 0.1:
		_play("run" if running else "walk")
	else:
		_play("idle")


func _play(anim_name: String, speed: float = 1.0, from_time: float = 0.0, restart: bool = false) -> void:
	if anim_name == _current_anim and from_time == 0.0 and not restart:
		if not is_equal_approx(speed, _current_speed):
			_current_speed = speed
			anim.play(anim_library + "/" + anim_name, 0.15, speed)
		return
	_current_anim = anim_name
	_current_speed = speed
	anim.play(anim_library + "/" + anim_name, 0.15 if not restart else 0.05, speed)
	if from_time > 0.0:
		anim.seek(from_time, true)


## Gives back health (food, checkpoints, level ups).
func heal(amount: float) -> void:
	if dead:
		return
	health = minf(max_health, health + amount)
	health_changed.emit(health, max_health)


## Luffy's health grows with his level (GameState).
func set_max_health(value: float, refill := false) -> void:
	max_health = value
	health = max_health if refill else minf(health, max_health)
	health_changed.emit(health, max_health)


# ------------------------------------------------------------------ eating
func can_eat() -> bool:
	return not dead and not swimming and not is_attacking() and not is_busy() and hurt_timer.is_stopped() and is_on_floor()


## Eats something from the inventory: a short animation with three bites, every bite gives back a
## third of the health. Returns false if he can not eat now.
func eat(item_id: String, heal_amount: float) -> bool:
	if not can_eat():
		return false
	var full := anim_library + "/eat"
	if not anim.has_animation(full):
		heal(heal_amount)
		FX.heal(get_parent(), global_position + Vector3(0, 1.0, 0))
		return true
	eating = true
	_eat_heal = heal_amount / 3.0
	_show_food(item_id)
	_play("eat", 1.0, 0.0, true)
	_busy_left = anim.get_animation(full).length
	return true


## Called by the "eat" animation at every bite.
func _on_bite() -> void:
	if not eating:
		return
	heal(_eat_heal)
	_eat_sound.play()
	var mouth := global_position + Vector3(0, 1.45, 0) + facing * 0.25
	FX.crumbs(get_parent(), mouth)
	FX.heal(get_parent(), global_position + Vector3(0, 0.9, 0))


func _show_food(item_id: String) -> void:
	var holder := get_node_or_null("FoodAttachment")
	if holder == null:
		return
	for c in holder.get_children():
		(c as Node3D).visible = c.name.to_lower() == item_id


# ------------------------------------------------------------------ skills
func skill_cooldown(id: String) -> float:
	return float(_skill_cd.get(id, 0.0))


func can_use_skill(id: String) -> bool:
	return not GameState.skill_spec(id).is_empty() and skill_cooldown(id) <= 0.0 and not dead and not swimming and not is_attacking() \
		and not is_busy() and hurt_timer.is_stopped() and controls_enabled


## A skill learned in the shop (GameState.SKILLS; `level`: of the player, it makes it stronger).
## Its animation "skill_<id>" (Luffy) or else "attack" calls _on_skill_hit().
func use_skill(id: String, level := 1) -> bool:
	if not can_use_skill(id):
		return false
	var spec := GameState.skill_spec(id)
	_skill_cd[id] = float(spec.cooldown)
	skill_active = id
	_skill = spec
	_skill_damage = float(spec.damage) * (1.0 + 0.06 * (level - 1))
	var anim_name := "skill_" + id
	var own := anim.has_animation(anim_library + "/" + anim_name)
	if not own:
		anim_name = "attack"
	_play(anim_name, 1.0, 0.0, true)
	_busy_left = anim.get_animation(anim_library + "/" + anim_name).length
	swing_sound.play()
	match str(spec.effect):
		"shield":
			invulnerability_timer.start(_busy_left + 0.6)
			var tw := create_tween()
			var base := model.scale
			if id == "fusen":
				tw.tween_property(model, "scale", Vector3(base.x * 1.7, base.y * 1.15, base.z * 1.7), 0.25).set_trans(Tween.TRANS_BACK)
				tw.tween_interval(maxf(0.1, _busy_left - 0.5))
				tw.tween_property(model, "scale", base, 0.25)
			else:
				FX.burst(get_parent(), global_position + Vector3(0, 1.0, 0), _skill_color(), 40, 2.5, 0.25, 0.5, 1.2)
		"spin", "storm":
			var turns := 1.0 if spec.effect == "spin" else 3.0
			var spin := create_tween()
			spin.tween_property(model, "rotation:y", model.rotation.y + TAU * turns, _busy_left * 0.8)
	if not own and (spec.effect == "rapid" or spec.effect == "storm"):
		# without its own animation the extra hits come one after the other
		_busy_left = maxf(_busy_left, 1.1)
		var hits := create_tween()
		for i in 5:
			hits.tween_interval(0.18)
			hits.tween_callback(_on_skill_hit)
	return true


func _skill_color() -> Color:
	match anim_library:
		"zoro": return Color(0.8, 0.95, 1.0, 0.8)
		"usopp": return Color(1.0, 0.65, 0.3, 0.8)
		"nami": return Color(0.55, 0.75, 1.0, 0.85)
	return Color(1, 0.8, 0.5, 0.8)


## Hit of the skill being done (the animations call it once or several times).
func _on_skill_hit() -> void:
	if skill_active == "" or _skill.is_empty():
		return
	var dmg := _skill_damage
	var r := float(_skill.radius)
	var push := float(_skill.push)
	var col := _skill_color()
	var front := global_position + facing * 1.6
	match str(_skill.effect):
		"spin":
			_area_hit(global_position, r, dmg, push)
			FX.ring(get_parent(), global_position, r, col)
		"front":
			_area_hit(front, r, dmg, push)
			FX.burst(get_parent(), front + Vector3(0, 1.1, 0), col, 24, 5.0, 0.12, 0.0, 0.4)
			_shake = 0.2
		"rapid":
			_area_hit(front, r, dmg, push)
			FX.burst(get_parent(), front + Vector3(randf_range(-0.4, 0.4), 1.1 + randf_range(-0.3, 0.3), 0), col, 6, 3.0, 0.07, 0.0, 0.25)
		"shield":
			_area_hit(global_position, r, dmg, push)
			FX.ring(get_parent(), global_position, r, col)
		"wave":
			var p := global_position + facing * 2.2
			_area_hit(p, r, dmg, push)
			FX.ring(get_parent(), p, r + 0.4, col)
			FX.burst(get_parent(), p, Color(0.7, 0.6, 0.45), 30, 5.0, 0.14, -12.0, 0.8)
			_shake = 0.3
		"storm":
			_area_hit(global_position, r, dmg, push)
			FX.ring(get_parent(), global_position, r, col)
		"shot":
			_fire(facing, dmg, r, col)
		"spread":
			for a in [-0.3, 0.0, 0.3]:
				_fire(facing.rotated(Vector3.UP, a), dmg, r, col)
	punch_sound.play()


## A projectile of a skill (Zoro's flying cut, Usopp's stars, Nami's balls).
func _fire(dir: Vector3, damage: float, radius: float, color: Color) -> void:
	var pellet := Pellet.new()
	var muzzle := global_position + Vector3(0, 1.2, 0) + dir * 0.7
	pellet.direction = _aim_from(muzzle) if dir == facing else dir
	pellet.damage = damage
	pellet.radius = radius
	pellet.color = color
	pellet.speed = 22.0
	pellet.shooter = self
	get_parent().add_child(pellet)
	pellet.global_position = muzzle


## Hits every enemy inside a sphere (only those in front of him if cone_dot > -1).
func _area_hit(center: Vector3, radius: float, damage: float, push: float, cone_dot := -1.0) -> int:
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius
	q.shape = sph
	q.transform = Transform3D(Basis(), center + Vector3(0, 1.0, 0))
	q.collision_mask = punch_hitbox.collision_mask
	q.exclude = [get_rid()]
	var hits := 0
	var seen := {}
	for r in get_world_3d().direct_space_state.intersect_shape(q, 32):
		var b: Object = r.collider
		if b == null or seen.has(b) or not b.has_method("receive_hit"):
			continue
		seen[b] = true
		var to := (b as Node3D).global_position - global_position
		to.y = 0.0
		if cone_dot > -1.0 and to.length() > 0.3 and to.normalized().dot(facing) < cone_dot:
			continue
		b.receive_hit(damage, global_position)
		if b.has_method("apply_knockback") and to.length() > 0.01:
			b.apply_knockback(to.normalized() * push)
		hits += 1
	if hits > 0:
		_shake = maxf(_shake, 0.1)
	return hits


func _end_busy() -> void:
	_busy_left = 0.0
	eating = false
	skill_active = ""
	_skill = {}
	_show_food("")
	_current_anim = ""


# ------------------------------------------------------------------ Usopp's slingshot
func _shoot() -> void:
	var pellet := Pellet.new()
	var muzzle := global_position + Vector3(0, 1.3, 0) + facing * 0.6
	pellet.direction = _aim_from(muzzle)
	pellet.damage = punch_damage
	pellet.shooter = self
	get_parent().add_child(pellet)
	pellet.global_position = muzzle
	punch_sound.play()


## Usopp's aim: the closest enemy in front of him (also small ones, like the mushrooms), at the
## height of its body; straight ahead if there is none.
func _aim_from(muzzle: Vector3) -> Vector3:
	var best: Node3D = null
	var best_d := 22.0
	for e in get_tree().get_nodes_in_group("enemies"):
		var n := e as Node3D
		if n == null or (n.has_method("is_defeated") and n.is_defeated()):
			continue
		var to := n.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d < best_d and d > 0.1 and to.normalized().dot(facing) > 0.8:
			best = n
			best_d = d
	if best == null:
		return facing
	var height := 1.0 if best.is_in_group("bosses") else 0.55
	return (best.global_position + Vector3(0, height, 0) - muzzle).normalized()


## Called by Buggy and the mini enemies when their attack connects.
func receive_hit(damage: float, from_pos: Vector3) -> void:
	if dead or not invulnerability_timer.is_stopped():
		return
	health = maxf(0.0, health - damage)
	health_changed.emit(health, max_health)
	var away := Vector3(global_position.x - from_pos.x, 0, global_position.z - from_pos.z)
	if away.length() < 0.05:
		away = -facing
	knockback = away.normalized() * knockback_force
	velocity.y = 3.5
	hurt_sound.play()
	_shake = 0.18
	invulnerability_timer.start()
	attack_timer.stop()
	if is_busy():
		_end_busy()
	if health <= 0.0:
		dead = true
		_play("death" if anim.has_animation(anim_library + "/death") else "hurt")
		died.emit()
	else:
		hurt_timer.start()
		_current_anim = ""
		anim.play(anim_library + "/hurt", 0.1)


## Brings the character back (Zoro after falling in co-op or as a companion).
func revive(at: Vector3) -> void:
	dead = false
	health = max_health
	health_changed.emit(health, max_health)
	global_position = at
	velocity = Vector3.ZERO
	knockback = Vector3.ZERO
	swimming = false
	hurt_timer.stop()
	invulnerability_timer.start()
	_current_anim = ""
	_play("idle")
