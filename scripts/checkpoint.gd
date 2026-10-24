class_name Checkpoint
extends Area3D
## Checkpoint of the island (scenes/props/checkpoint.tscn). When Luffy touches it, it becomes the
## place where he comes back after loading the game or losing, his health is filled and the game
## is saved in its slot (game_world.gd does the saving).
## Nodes used: Flag (its colour shows if it is active), Glow, NameLabel, SpawnPoint, ActivateSound.

signal reached(checkpoint: Checkpoint)

## Id saved in the JSON (it must be one of SaveManager.CHECKPOINT_IDS).
@export var checkpoint_id := "playa_sur"
@export var display_name := "South Beach"
@export var inactive_color := Color(0.75, 0.2, 0.15)
@export var active_color := Color(1.0, 0.82, 0.25)

@onready var flag: MeshInstance3D = $Flag
@onready var glow: OmniLight3D = $Glow
@onready var name_label: Label3D = $NameLabel
@onready var spawn_point: Marker3D = $SpawnPoint
@onready var activate_sound: AudioStreamPlayer3D = $ActivateSound

var activated := false
var _flag_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("checkpoints")
	name_label.text = display_name
	_flag_mat = StandardMaterial3D.new()
	_flag_mat.emission_enabled = true
	flag.material_override = _flag_mat
	set_active(false, false)


## activated: Luffy already touched it. current: it is the one where he will come back.
func set_active(on: bool, current: bool) -> void:
	activated = on
	_flag_mat.albedo_color = active_color if on else inactive_color
	_flag_mat.emission = active_color if current else Color.BLACK
	_flag_mat.emission_energy_multiplier = 0.8 if current else 0.0
	# the light is in the group "dynamic_lights": GraphicsSettings turns it on only if it is close
	glow.set_meta("wanted", current)
	glow.visible = current


func spawn_transform() -> Transform3D:
	return spawn_point.global_transform


func _on_body_entered(body: Node3D) -> void:
	if body is Player and not (body as Player).dead:
		reached.emit(self)


func play_activate_sound() -> void:
	activate_sound.play()
