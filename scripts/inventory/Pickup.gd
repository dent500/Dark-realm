## Pickup.gd
## Script for an interactive 3D loot object that can be picked up by the player.
extends StaticBody3D

@export var item_id: String = ""
@export var quantity: int = 1
@export var display_name: String = ""

var _mesh: MeshInstance3D
var _col: CollisionShape3D
var _time: float = 0.0
var _base_y: float = 0.0

func _ready() -> void:
	add_to_group("pickup")
	_setup_nodes()
	_apply_initial_hop()
	_base_y = position.y

func _setup_nodes() -> void:
	# ─── Collision ───
	collision_layer = 1
	collision_mask = 1
	_col = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 0.5
	_col.shape = sphere
	add_child(_col)
	
	# ─── Visuals ───
	_mesh = MeshInstance3D.new()
	var prism = PrismMesh.new() # Gem-like shape
	prism.size = Vector3(0.4, 0.4, 0.2)
	_mesh.mesh = prism
	
	# Material based on ID or Type
	var mat = StandardMaterial3D.new()
	mat.albedo_color = _get_color_for_item()
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 2.0
	_mesh.material_override = mat
	add_child(_mesh)
	
	# Look up display name if empty
	if display_name == "":
		var player = get_tree().get_first_node_in_group("player")
		if player:
			var inv = player.get_node_or_null("Inventory")
			if inv and inv.ITEM_DB.has(item_id):
				display_name = inv.ITEM_DB[item_id]["name"]
			else:
				display_name = item_id.replace("_", " ").capitalize()

func _get_color_for_item() -> Color:
	if "potion" in item_id or "herb" in item_id: return Color.SPRING_GREEN
	if "ore" in item_id or "ingot" in item_id: return Color.SLATE_GRAY
	if "sword" in item_id or "armor" in item_id: return Color.GOLD
	if "dark" in item_id or "essence" in item_id: return Color.PURPLE
	return Color.CYAN # Default

func _process(delta: float) -> void:
	_time += delta
	if _mesh:
		# Floating effect
		_mesh.position.y = sin(_time * 3.0) * 0.15
		# Spinning effect
		_mesh.rotation.y += delta * 2.0

func _apply_initial_hop() -> void:
	# "Pop" out when dropped
	var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var target_pos = position + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
	tw.tween_property(self, "position:x", target_pos.x, 0.6)
	tw.tween_property(self, "position:z", target_pos.z, 0.6)
	
	# Arching jump
	var tw_y = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_y.tween_property(self, "position:y", position.y + 1.2, 0.3)
	tw_y.set_ease(Tween.EASE_IN)
	tw_y.tween_property(self, "position:y", position.y, 0.3)

func interact(player: Node) -> void:
	if player.has_method("try_pickup"):
		var success = player.try_pickup({"id": item_id, "quantity": quantity})
		if success:
			# Play visual/sound feedback
			var hud = get_tree().get_first_node_in_group("hud")
			if hud and hud.has_method("show_pickup_toast"):
				hud.show_pickup_toast(display_name, quantity)
			
			AIDungeonMaster.narrate_custom("You found " + display_name + ". A valuable find in these dark woods.")
			queue_free()
