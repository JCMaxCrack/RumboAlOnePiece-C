class_name Ship
extends Node3D
## The Going Merry (scenes/props/going_merry.tscn, with this script in scenes/world.tscn).
## Moored in a port it is solid ground: the crew walks on its decks. At the helm (on the stern
## deck) Luffy takes the wheel and sails it in third person, like in How to Fish:
##   move_forward / move_back: more sail / brake (and slow backwards), move_left / move_right: turn,
##   sprint: full sail, look_*: turn the camera around the ship, interact: let go of the wheel.
## While sailing, the crew stays on the deck (their physics is paused and they move with the ship),
## the hull rocks with the waves (the same waves as the water shader) and leaves a wake of foam.
## The World decides where it can go (land, the border of the sea, islands not open yet) through
## the callable `can_sail`, and docks it in the ports: the ship moors alongside the pier and its
## gangway (hinged on the bulwark of the main deck, where its side walls leave a gap) goes down
## onto the pier; it is raised again when the ship leaves. A small ramp inside the bulwark goes
## down to the main deck.

signal helm_taken
signal helm_left
## The bow touched something it can not go through (reason: "land", "border", "locked:<island>").
signal blocked(reason: String)

## Where the wheel is and where the one who steers stands (ship coordinates).
const HELM := Vector3(0, 2.86, -6.6)
## Places on the deck for the rest of the crew while sailing.
const DECK_SPOTS := [Vector3(-1.4, 1.0, 1.2), Vector3(1.4, 1.0, 1.8), Vector3(0.0, 1.0, 3.2), Vector3(-1.2, 1.0, -0.4)]
## Height of the ship's origin over the sea.
const FLOAT_Y := 1.0
## Points of the hull that must stay in deep water (ship coordinates, x and z).
## Hinge of the gangway on the bulwark of the main deck (x is set by the side of the pier).
const GANGWAY_HINGE := Vector3(2.95, 1.1, 0.95)
const GANGWAY_LENGTH := 4.6
const HULL_PROBES := [Vector2(0, 9.0), Vector2(-2.6, 4.0), Vector2(2.6, 4.0), Vector2(-2.6, -6.0), Vector2(2.6, -6.0), Vector2(0, -8.5)]

@export var max_speed := 15.0
@export var boost_speed := 21.0
@export var reverse_speed := 3.5
@export var acceleration := 3.2
@export var brake := 6.0
@export var drag := 0.6
@export var turn_rate := 0.55
@export var camera_distance := 22.0
@export var mouse_sensitivity := 0.003

@onready var model: Node3D = $Model
@onready var collision: CollisionObject3D = $Collision

## Returns "" if the ship can be at that position, or why not (see `blocked`).
var can_sail: Callable
var steering := false
var driver: Player
var speed := 0.0
var heading := 0.0
var camera: Camera3D
var _passengers: Array = []  # [[Player, local position], ...]
var _model_base := Transform3D()
var _rig: Node3D
var _arm: SpringArm3D
var _orbit := Vector2(0.0, -0.3)
var _wake: CPUParticles3D
var _spray: CPUParticles3D
var _docking: Tween
var _blocked_wait := 0.0
var _settle := 0.0
var _gangway: Node3D
var _gangway_tween: Tween
var gangway_down := false


func _ready() -> void:
	process_physics_priority = 50
	add_to_group("minimap_ship")
	_model_base = model.transform
	heading = rotation.y
	var helm := Marker3D.new()
	helm.name = "Helm"
	add_child(helm)
	helm.position = HELM
	_build_camera()
	_build_wake()
	_build_gangway()


# ------------------------------------------------------------------ helm
func helm_position() -> Vector3:
	return global_transform * HELM


## The one that takes the wheel and the crew that sails with him.
func take_helm(p: Player, crew: Array) -> void:
	if steering:
		return
	steering = true
	driver = p
	heading = rotation.y
	_passengers = [[p, HELM]]
	var i := 0
	for c in crew:
		var cp := c as Player
		if cp and cp != p and not cp.dead:
			_passengers.append([cp, DECK_SPOTS[i % DECK_SPOTS.size()]])
			i += 1
	for e in _passengers:
		var pl: Player = e[0]
		pl.set_physics_process(false)
		pl.velocity = Vector3.ZERO
		pl.controls_enabled = false
		pl._play("idle")
	_arm.add_excluded_object(collision.get_rid())
	_orbit = Vector2(0.0, -0.3)
	_rig.global_position = global_position
	_rig.rotation.y = heading + PI
	_place_passengers()
	helm_taken.emit()


## Lets go of the wheel: the ship stops and everyone can walk on the deck again.
func leave_helm() -> void:
	if not steering:
		return
	steering = false
	speed = 0.0
	_settle = 1.0
	_place_passengers()
	for e in _passengers:
		var pl: Player = e[0]
		pl.set_physics_process(true)
		pl.controls_enabled = true
		pl.velocity = Vector3.ZERO
	_passengers = []
	driver = null
	helm_left.emit()


## Glides into a port (world transform of the mooring), then lets go of the wheel.
func dock(target: Transform3D, on_done := Callable()) -> void:
	if _docking:
		_docking.kill()
	speed = 0.0
	var from_pos := global_position
	var from_yaw := heading
	var to_yaw := from_yaw + wrapf(target.basis.get_euler().y - from_yaw, -PI, PI)
	_docking = create_tween()
	_docking.tween_method(func(t: float) -> void:
		var k := t * t * (3.0 - 2.0 * t)
		heading = lerpf(from_yaw, to_yaw, k)
		var p := from_pos.lerp(target.origin, k)
		global_transform = Transform3D(Basis(Vector3.UP, heading), Vector3(p.x, FLOAT_Y, p.z))
		_place_passengers(), 0.0, 1.0, 3.0)
	_docking.tween_callback(func() -> void:
		_docking = null
		leave_helm()
		if on_done.is_valid():
			on_done.call())


func is_docking() -> bool:
	return _docking != null


## Puts the ship at once in a mooring (loading a game, arriving at an island).
func moor(target: Transform3D) -> void:
	heading = target.basis.get_euler().y
	global_transform = Transform3D(Basis(Vector3.UP, heading), Vector3(target.origin.x, FLOAT_Y, target.origin.z))
	speed = 0.0
	model.transform = _model_base


func forward() -> Vector3:
	return Vector3(sin(heading), 0.0, cos(heading))


func look(rel: Vector2) -> void:
	_orbit.x -= rel.x * mouse_sensitivity
	_orbit.y = clampf(_orbit.y - rel.y * mouse_sensitivity, -1.0, 0.1)


# ------------------------------------------------------------------ sailing
func _physics_process(delta: float) -> void:
	_blocked_wait = maxf(0.0, _blocked_wait - delta)
	if steering and not is_docking():
		_sail(delta)
	_rock(delta)
	if steering:
		_place_passengers()
	_update_wake()


func _process(delta: float) -> void:
	if not steering:
		return
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick.length() > 0.1:
		look(stick * 900.0 * delta)
	# the camera follows the ship from behind; the player can turn it around
	_rig.global_position = _rig.global_position.lerp(global_position + Vector3(0, 3.0, 0), clampf(8.0 * delta, 0.0, 1.0))
	var want := heading + PI + _orbit.x
	_rig.rotation.y = lerp_angle(_rig.rotation.y, want, clampf(2.5 * delta, 0.0, 1.0))
	_arm.rotation.x = _orbit.y
	if absf(speed) > 1.0 and not Input.is_action_pressed("look_left") and not Input.is_action_pressed("look_right"):
		_orbit.x = lerpf(_orbit.x, 0.0, clampf(0.4 * delta, 0.0, 1.0))


func _sail(delta: float) -> void:
	var can_move := driver != null and not get_tree().paused
	var throttle := Input.get_axis("move_back", "move_forward") if can_move else 0.0
	var steer := Input.get_axis("move_right", "move_left") if can_move else 0.0
	var top := boost_speed if Input.is_action_pressed("sprint") else max_speed
	if throttle > 0.0:
		speed = move_toward(speed, top * throttle, acceleration * delta)
	elif throttle < 0.0:
		speed = move_toward(speed, -reverse_speed, (brake if speed > 0.0 else acceleration * 0.5) * delta)
	else:
		speed = move_toward(speed, 0.0, drag * delta)
	if speed > top:
		speed = move_toward(speed, top, brake * delta)
	var grip := clampf(absf(speed) / 6.0, 0.25, 1.0)
	heading += steer * turn_rate * grip * signf(speed if absf(speed) > 0.1 else 1.0) * delta
	var next := global_position + forward() * speed * delta
	var why := _check(next, heading)
	if why != "":
		# bump: the ship stops and goes back a little
		speed = -speed * 0.25
		next = global_position
		if _blocked_wait <= 0.0:
			_blocked_wait = 2.0
			blocked.emit(why)
	global_transform = Transform3D(Basis(Vector3.UP, heading), Vector3(next.x, FLOAT_Y, next.z))


func _check(pos: Vector3, yaw: float) -> String:
	if not can_sail.is_valid():
		return ""
	var b := Basis(Vector3.UP, yaw)
	for probe in HULL_PROBES:
		var p: Vector3 = pos + b * Vector3(probe.x, 0, probe.y)
		var why: String = can_sail.call(p)
		if why != "":
			return why
	return ""


## Waves under the hull: the same function as the water shader (assets/shaders/ocean.gdshader).
static func wave_height(x: float, z: float, t: float) -> float:
	return sin(x * 0.18 + t * 1.1) * 0.22 + sin(z * 0.23 - t * 0.9 + x * 0.07) * 0.18 + sin((x + z) * 0.5 + t * 1.8) * 0.06


static func wave_time() -> float:
	return fmod(Time.get_ticks_msec() / 1000.0, 3600.0)


func _rock(delta: float) -> void:
	var moving := steering or _settle > 0.0
	_settle = maxf(0.0, _settle - delta * 0.5)
	if not moving:
		return
	var t := wave_time()
	var f := forward()
	var r := Vector3(f.z, 0, -f.x)
	var p := global_position
	var bow := wave_height(p.x + f.x * 7.0, p.z + f.z * 7.0, t)
	var stern := wave_height(p.x - f.x * 7.0, p.z - f.z * 7.0, t)
	var port := wave_height(p.x + r.x * 2.8, p.z + r.z * 2.8, t)
	var starboard := wave_height(p.x - r.x * 2.8, p.z - r.z * 2.8, t)
	var k := 1.0 if steering else _settle
	var pitch := atan2(stern - bow, 14.0) * 1.6 * k
	var roll := (atan2(starboard - port, 5.6) * 1.4 + speed * 0.002 * signf(Input.get_axis("move_right", "move_left"))) * k
	var lift := (bow + stern + port + starboard) * 0.25 * 0.8 * k
	var rock_xf := Transform3D(Basis.from_euler(Vector3(pitch, 0.0, roll)), Vector3(0, lift, 0))
	model.transform = rock_xf * _model_base


func _place_passengers() -> void:
	var xf := global_transform
	for e in _passengers:
		var pl: Player = e[0]
		if not is_instance_valid(pl):
			continue
		var local: Vector3 = e[1]
		pl.global_position = xf * local + Vector3(0, model.transform.origin.y, 0)
		pl.velocity = Vector3.ZERO
		if pl == driver:
			pl.facing = forward()
			pl.model.rotation.y = atan2(pl.facing.x, pl.facing.z) + pl.model_yaw


# ------------------------------------------------------------------ gangway
func _build_gangway() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.34, 0.2)
	wood.roughness = 0.85
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.3, 0.2, 0.12)
	_gangway = Node3D.new()
	_gangway.name = "Gangway"
	add_child(_gangway)
	_gangway.position = GANGWAY_HINGE
	var body := StaticBody3D.new()
	body.collision_mask = 0
	_gangway.add_child(body)
	var plank := BoxMesh.new()
	plank.size = Vector3(GANGWAY_LENGTH, 0.16, 1.25)
	plank.material = wood
	var mi := MeshInstance3D.new()
	mi.mesh = plank
	mi.position = Vector3(GANGWAY_LENGTH / 2.0, -0.08, 0)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = plank.size
	cs.shape = box
	cs.position = mi.position
	body.add_child(cs)
	for z in [-0.6, 0.6]:
		var rail := BoxMesh.new()
		rail.size = Vector3(GANGWAY_LENGTH, 0.07, 0.07)
		rail.material = dark
		var r := MeshInstance3D.new()
		r.mesh = rail
		r.position = Vector3(GANGWAY_LENGTH / 2.0, 0.55, z)
		body.add_child(r)
		for k in 4:
			var post := BoxMesh.new()
			post.size = Vector3(0.06, 0.6, 0.06)
			post.material = dark
			var pm := MeshInstance3D.new()
			pm.mesh = post
			pm.position = Vector3(0.3 + k * (GANGWAY_LENGTH - 0.6) / 3.0, 0.25, z)
			body.add_child(pm)
	for k in 6:
		var slat := BoxMesh.new()
		slat.size = Vector3(0.08, 0.05, 1.25)
		slat.material = dark
		var sm := MeshInstance3D.new()
		sm.mesh = slat
		sm.position = Vector3(0.4 + k * (GANGWAY_LENGTH - 0.8) / 5.0, 0.02, 0)
		body.add_child(sm)
	_show_gangway(false)
	_gangway.position.y = GANGWAY_HINGE.y - GANGWAY_LENGTH * 0.95
	_gangway.rotation.z = PI / 2.0
	# ramps from the top of the bulwark down to the main deck, on both sides
	var inner := StaticBody3D.new()
	inner.name = "BoardingRamps"
	inner.collision_mask = 0
	add_child(inner)
	for side in [-1.0, 1.0]:
		var run := 1.9
		var rise := GANGWAY_HINGE.y
		var ang := atan2(rise, run)
		var length := sqrt(run * run + rise * rise)
		var ramp := BoxMesh.new()
		ramp.size = Vector3(length, 0.14, 1.2)
		ramp.material = wood
		var rm := MeshInstance3D.new()
		rm.mesh = ramp
		var center := Vector3(side * (GANGWAY_HINGE.x - 0.1 - run / 2.0), rise / 2.0 - 0.07, GANGWAY_HINGE.z)
		rm.transform = Transform3D(Basis(Vector3.BACK, side * ang), center)
		inner.add_child(rm)
		var rc := CollisionShape3D.new()
		var rb := BoxShape3D.new()
		rb.size = ramp.size
		rc.shape = rb
		rc.transform = rm.transform
		inner.add_child(rc)


## The gangway lies on the pier (side: where the pier is, drop: from the hinge to the pier) or is
## raised against the hull. animate = false puts it there at once.
func set_gangway(down: bool, side: float, drop: float, animate := true) -> void:
	gangway_down = down
	if _gangway_tween:
		_gangway_tween.kill()
	# stowed, the plank stands up against the bulwark and slides down into the hull out of sight;
	# deployed, it comes up again and swings down onto the pier (the hinge turned to the pier side)
	var lowered := -asin(clampf(drop / GANGWAY_LENGTH, 0.0, 0.9))
	var hidden_y := GANGWAY_HINGE.y - GANGWAY_LENGTH * 0.95
	if not animate:
		if down:
			_place_gangway(side)
		_gangway.position.y = GANGWAY_HINGE.y if down else hidden_y
		_gangway.rotation.z = lowered if down else PI / 2.0
		_show_gangway(down)
		return
	_gangway_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if down:
		if not _gangway.visible:
			_place_gangway(side)
			_gangway.rotation.z = PI / 2.0
			_gangway.position.y = hidden_y
			_show_gangway(true)
		_gangway_tween.tween_property(_gangway, "position:y", GANGWAY_HINGE.y, 0.8)
		_gangway_tween.tween_property(_gangway, "rotation:z", lowered, 1.2)
	else:
		_gangway_tween.tween_property(_gangway, "rotation:z", PI / 2.0, 1.0)
		_gangway_tween.tween_property(_gangway, "position:y", hidden_y, 0.8)
		_gangway_tween.tween_callback(_show_gangway.bind(false))


func _place_gangway(side: float) -> void:
	_gangway.position = Vector3(side * GANGWAY_HINGE.x, GANGWAY_HINGE.y, GANGWAY_HINGE.z)
	_gangway.rotation.y = 0.0 if side > 0.0 else PI


func _show_gangway(on: bool) -> void:
	_gangway.visible = on
	for body in _gangway.find_children("*", "CollisionObject3D", true, false):
		(body as CollisionObject3D).process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


# ------------------------------------------------------------------ camera and wake
func _build_camera() -> void:
	_rig = Node3D.new()
	_rig.name = "CameraRig"
	_rig.top_level = true
	add_child(_rig)
	_arm = SpringArm3D.new()
	_arm.spring_length = camera_distance
	_arm.margin = 0.5
	_arm.collision_mask = 1
	_rig.add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 70.0
	_arm.add_child(camera)


func _build_wake() -> void:
	var foam := StandardMaterial3D.new()
	foam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	foam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foam.vertex_color_use_as_albedo = true
	foam.albedo_color = Color(1, 1, 1, 1)
	foam.cull_mode = BaseMaterial3D.CULL_DISABLED
	# a soft round spot of foam
	var spot := GradientTexture2D.new()
	spot.fill = GradientTexture2D.FILL_RADIAL
	spot.fill_from = Vector2(0.5, 0.5)
	spot.fill_to = Vector2(1.0, 0.5)
	spot.width = 64
	spot.height = 64
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	spot.gradient = fade
	foam.albedo_texture = spot
	var quad := PlaneMesh.new()
	quad.size = Vector2(2.4, 2.4)
	quad.material = foam
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.75))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.6))
	grow.add_point(Vector2(1, 2.6))
	_wake = CPUParticles3D.new()
	_wake.name = "Wake"
	_wake.mesh = quad
	_wake.amount = 220
	_wake.lifetime = 5.0
	_wake.local_coords = false
	_wake.emitting = false
	_wake.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_wake.emission_box_extents = Vector3(2.2, 0.0, 0.6)
	_wake.direction = Vector3(0, 0, -1)
	_wake.spread = 25.0
	_wake.gravity = Vector3.ZERO
	_wake.initial_velocity_min = 0.6
	_wake.initial_velocity_max = 1.6
	_wake.scale_amount_min = 1.2
	_wake.scale_amount_max = 2.4
	_wake.scale_amount_curve = grow
	_wake.color_ramp = ramp
	_wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wake)
	_wake.position = Vector3(0, -0.5, -7.8)
	var drop := SphereMesh.new()
	drop.radius = 0.12
	drop.height = 0.24
	drop.radial_segments = 6
	drop.rings = 3
	drop.material = foam
	_spray = CPUParticles3D.new()
	_spray.name = "BowSpray"
	_spray.mesh = drop
	_spray.amount = 60
	_spray.lifetime = 1.0
	_spray.local_coords = false
	_spray.emitting = false
	_spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_spray.emission_box_extents = Vector3(1.5, 0.1, 0.4)
	_spray.direction = Vector3(0, 1, 0.4)
	_spray.spread = 40.0
	_spray.gravity = Vector3(0, -9.8, 0)
	_spray.initial_velocity_min = 2.0
	_spray.initial_velocity_max = 4.5
	_spray.color_ramp = ramp
	_spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spray)
	_spray.position = Vector3(0, -0.4, 8.0)


func _update_wake() -> void:
	var s := absf(speed)
	_wake.emitting = steering and s > 1.5
	_wake.speed_scale = clampf(0.6 + s / 12.0, 0.6, 1.8)
	_spray.emitting = steering and speed > 7.0
	# the foam stays on the surface of the sea
	_wake.global_position.y = 0.42
	_spray.global_position.y = 0.6
