class_name Collectible
extends Area3D
## Something that can be picked up (meat, tangerines, the key of the mansion...). It goes to the
## inventory (GameState): the food is eaten later from there to get health back.
## Nodes used (see scenes/items/meat.tscn): Visual, AnimationPlayer ("float"), PickupSound, CollisionShape3D.

signal collected(item: Collectible)
## The inventory had no room for it.
signal rejected(item: Collectible)

## Item of GameState.ITEMS that this pickup gives.
@export var item_id := "meat"
## Old setting of the meat (health it gave); the health now comes from GameState.ITEMS.
@export var heal_amount := 25.0

@onready var visual: Node3D = $Visual
@onready var pickup_sound: AudioStreamPlayer3D = $PickupSound

var taken := false
var _reject_cooldown := 0.0


func _ready() -> void:
	add_to_group("minimap_meat" if item_id != "key" else "minimap_key")


func _process(delta: float) -> void:
	_reject_cooldown = maxf(0.0, _reject_cooldown - delta)


func _on_body_entered(body: Node3D) -> void:
	if taken or not body is Player or (body as Player).dead:
		return
	# it goes to the bag of the player who touches it (companions fill player 1's)
	if not GameState.hero_of(body).add_item(item_id):
		if _reject_cooldown <= 0.0:
			_reject_cooldown = 2.0
			rejected.emit(self)
		return
	taken = true
	visual.visible = false
	set_deferred("monitoring", false)
	pickup_sound.play()
	collected.emit(self)
	if has_meta("dynamic"):
		FX.text(get_parent(), global_position + Vector3(0, 1.0, 0), "+" + GameState.item_name(item_id), Color(1, 0.9, 0.6), 40)


## A body that stays inside after the inventory was full can take it once there is room.
func retry() -> void:
	if taken:
		return
	for b in get_overlapping_bodies():
		_on_body_entered(b)


func _on_pickup_sound_finished() -> void:
	queue_free()
