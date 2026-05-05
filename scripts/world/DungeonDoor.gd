## DungeonDoor.gd
## Attached to the DoorTrigger Area3D in world.tscn.
## Loads dungeon.tscn when the player walks through.
extends Area3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		PlayerData.dungeon_floor = 1
		PlayerData.current_zone = "Dungeon Floor 1"
		get_tree().change_scene_to_file("res://scenes/dungeon.tscn")
