## Collectable.gd
## A glowing, bobbing world pickup. Attach as a child of any Node3D.
## Spawned procedurally by WorldBuilder. Auto-collects on player touch.
extends Area3D

# ─── Config ────────────────────────────────────────────────────────────────────
@export var item_id: String = "health_potion"
@export var quantity: int = 1
@export var glow_color: Color = Color(1.0, 0.8, 0.2)   # default gold glow
@export var bob_height: float = 0.25
@export var bob_speed: float = 2.0
@export var spin_speed: float = 1.2

# ─── Internal ──────────────────────────────────────────────────────────────────
var _mesh_root: Node3D
var _label: Label3D
var _spawn_y: float = 0.0
var _time: float = 0.0
var _collected: bool = false

# ─── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("collectable")
	collision_layer = 0
	collision_mask = 1   # detect player (layer 1)
	monitoring = true
	monitorable = false

	_spawn_y = global_position.y
	_build_visuals()

	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if _collected:
		return
	_time += delta
	# Bob up and down
	if _mesh_root:
		_mesh_root.position.y = sin(_time * bob_speed) * bob_height
		_mesh_root.rotate_y(spin_speed * delta)

# ─── Visual Construction ───────────────────────────────────────────────────────
func _build_visuals() -> void:
	_mesh_root = Node3D.new()
	add_child(_mesh_root)

	# Core gem / pickup mesh  — small faceted sphere
	var mi = MeshInstance3D.new()
	var sm = SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm

	var mat = StandardMaterial3D.new()
	mat.albedo_color = glow_color
	mat.emission_enabled = true
	mat.emission = glow_color
	mat.emission_energy_multiplier = 3.0
	mat.roughness = 0.1
	mat.metallic = 0.6
	mi.material_override = mat
	_mesh_root.add_child(mi)

	# Outer glow light
	var light = OmniLight3D.new()
	light.light_color = glow_color
	light.light_energy = 1.5
	light.omni_range = 2.5
	_mesh_root.add_child(light)

	# Floating item name label — hidden until player is close
	_label = Label3D.new()
	_label.text = _get_item_name()
	_label.font_size = 28
	_label.modulate = Color(1.0, 0.95, 0.7)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 0.7, 0)
	_label.no_depth_test = true
	_label.visible = false
	add_child(_label)

	# Collision sphere
	var col = CollisionShape3D.new()
	var sph = SphereShape3D.new()
	sph.radius = 0.8
	col.shape = sph
	add_child(col)

func _get_item_name() -> String:
	if Inventory != null:
		pass  # Will use item_id directly — avoids circular ref at build time
	# Map common IDs to readable names inline
	var names: Dictionary = {
		"health_potion": "Health Potion", "mana_crystal": "Mana Crystal",
		"iron_sword": "Iron Sword", "iron_shield": "Iron Shield",
		"leather_armor": "Leather Armor", "iron_axe": "Iron Axe",
		"wood": "Wood", "iron_ore": "Iron Ore", "herbs": "Healing Herbs",
		"wolf_pelt": "Wolf Pelt", "goblin_tooth": "Goblin Tooth",
		"cracked_locket": "Cracked Locket", "merchant_ledger": "Merchant Ledger",
		"dark_essence": "Dark Essence", "campfire_kit": "Campfire Kit",
		"steel_helmet": "Steel Helmet", "chainmail": "Chainmail",
		"iron_boots": "Iron Boots", "iron_gloves": "Iron Gloves",
		"ruby_ring": "Ruby Ring", "silver_amulet": "Silver Amulet",
	}
	return names.get(item_id, item_id.replace("_", " ").capitalize())

# ─── Proximity Label ───────────────────────────────────────────────────────────
func _on_body_entered(body: Node3D) -> void:
	if _collected:
		return
	if not body.is_in_group("player"):
		return
	_do_collect(body)

func _do_collect(player: Node3D) -> void:
	_collected = true

	# Try adding to inventory
	var inv = player.get_node_or_null("Inventory")
	var success = false
	if inv and inv.has_method("add_item"):
		success = inv.add_item(item_id, quantity)

	if success:
		_play_collect_flash()
		# Show pickup toast in HUD
		var hud = player.get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("show_pickup_toast"):
			hud.show_pickup_toast(_get_item_name(), quantity)
	queue_free()

func _play_collect_flash() -> void:
	# Quick scale-up burst before freeing
	var tween = create_tween()
	tween.tween_property(_mesh_root, "scale", Vector3(2.5, 2.5, 2.5), 0.1)
	tween.tween_property(_mesh_root, "modulate:a", 0.0, 0.15)
