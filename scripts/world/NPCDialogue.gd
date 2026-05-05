## NPCDialogue.gd
## Attach to any Node3D. Builds a procedural NPC mesh and handles dialogue.
## Each NPC shows their name only when the player is nearby.
extends StaticBody3D

# ─── Config ────────────────────────────────────────────────────────────────────
@export var npc_name: String = "Villager"
@export var npc_type: String = "villager"  # "villager" | "merchant" | "guard" | "sage"
@export var quest_to_give: String = ""
@export var dialogue_lines: Array[String] = [
	"Dark times have fallen upon us, traveller.",
	"The keep to the east crawls with goblins. They raid us nightly.",
	"Please... if you are strong, help us."
]

# ─── State ─────────────────────────────────────────────────────────────────────
var current_line: int = 0
var dialogue_active: bool = false
var player_nearby: bool = false

# ─── Visual ────────────────────────────────────────────────────────────────────
var _mesh_root: Node3D
var _name_label: Label3D
var _time: float = 0.0

# NPC appearance per type
const TYPE_COLORS = {
	"villager": {"body": Color(0.4, 0.35, 0.55), "skin": Color(0.85, 0.65, 0.45), "hair": Color(0.25, 0.15, 0.05)},
	"merchant": {"body": Color(0.55, 0.4, 0.1),  "skin": Color(0.9, 0.72, 0.52),  "hair": Color(0.5, 0.3, 0.05)},
	"guard":    {"body": Color(0.35, 0.38, 0.42), "skin": Color(0.8, 0.6, 0.42),   "hair": Color(0.1, 0.08, 0.06)},
	"sage":     {"body": Color(0.25, 0.2, 0.45),  "skin": Color(0.75, 0.7, 0.65),  "hair": Color(0.9, 0.9, 0.9)},
}

# ─── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("npc")
	_build_mesh()
	_build_interact_area()

func _process(delta: float) -> void:
	_time += delta
	# Gentle idle sway
	if _mesh_root:
		_mesh_root.rotation.z = sin(_time * 1.1) * 0.02
		_mesh_root.rotation.x = sin(_time * 0.7 + 0.5) * 0.015

# ─── Mesh Construction ─────────────────────────────────────────────────────────
func _build_mesh() -> void:
	_mesh_root = Node3D.new()
	add_child(_mesh_root)

	var colors = TYPE_COLORS.get(npc_type, TYPE_COLORS["villager"])
	var skin_mat = _mat(colors["skin"], 0.85)
	var body_mat = _mat(colors["body"], 0.9)
	var hair_mat = _mat(colors["hair"], 0.95)

	# Torso
	_add_box(_mesh_root, Vector3(0, 1.05, 0), Vector3(0.5, 0.6, 0.28), body_mat)
	# Hips
	_add_box(_mesh_root, Vector3(0, 0.68, 0), Vector3(0.45, 0.22, 0.26), body_mat)
	# Head
	_add_box(_mesh_root, Vector3(0, 1.55, 0), Vector3(0.35, 0.35, 0.32), skin_mat)
	# Hair
	_add_box(_mesh_root, Vector3(0, 1.75, 0), Vector3(0.37, 0.15, 0.34), hair_mat)

	# Left arm
	_add_box(_mesh_root, Vector3(-0.35, 1.0, 0), Vector3(0.15, 0.5, 0.15), skin_mat)
	# Right arm
	_add_box(_mesh_root, Vector3(0.35, 1.0, 0), Vector3(0.15, 0.5, 0.15), skin_mat)

	# Left leg
	_add_box(_mesh_root, Vector3(-0.14, 0.3, 0), Vector3(0.18, 0.55, 0.18), body_mat)
	# Right leg
	_add_box(_mesh_root, Vector3(0.14, 0.3, 0), Vector3(0.18, 0.55, 0.18), body_mat)

	# Guard: add a helmet
	if npc_type == "guard":
		_add_box(_mesh_root, Vector3(0, 1.85, 0), Vector3(0.4, 0.12, 0.4), _mat(Color(0.45, 0.48, 0.52), 0.6))
	# Sage: add a staff (thin vertical box)
	if npc_type == "sage":
		_add_box(_mesh_root, Vector3(0.45, 0.8, 0), Vector3(0.06, 1.3, 0.06), _mat(Color(0.35, 0.22, 0.1), 0.9))

	# Collision body (attached to self now)
	var col = CollisionShape3D.new()
	var caps = CapsuleShape3D.new()
	caps.radius = 0.35; caps.height = 1.8
	col.shape = caps
	col.position.y = 0.9
	add_child(col)

	# Name label — hidden by default, shown on proximity
	_name_label = Label3D.new()
	_name_label.text = npc_name
	_name_label.font_size = 40
	_name_label.modulate = Color(1.0, 0.95, 0.7)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.position = Vector3(0, 2.3, 0)
	_name_label.no_depth_test = true
	_name_label.visible = false
	add_child(_name_label)

	# Type tag below name
	var type_label = Label3D.new()
	type_label.text = "[" + npc_type.capitalize() + "]"
	type_label.font_size = 28
	type_label.modulate = Color(0.7, 0.7, 0.5, 0.85)
	type_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	type_label.position = Vector3(0, 2.0, 0)
	type_label.no_depth_test = true
	type_label.visible = false
	type_label.name = "TypeLabel"
	add_child(type_label)

func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m

func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)

# ─── Interact Area ─────────────────────────────────────────────────────────────
func _build_interact_area() -> void:
	var area = Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	var col = CollisionShape3D.new()
	var sph = SphereShape3D.new()
	sph.radius = 2.5
	col.shape = sph
	col.position.y = 1.0
	area.add_child(col)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)

# ─── Dialogue ──────────────────────────────────────────────────────────────────
func interact(_player: Node = null) -> void:
	if dialogue_active:
		_advance_dialogue()
	else:
		_start_dialogue()

func _start_dialogue() -> void:
	dialogue_active = true
	current_line = 0
	var p = get_tree().get_first_node_in_group("player")
	if p: p.set("is_interacting", true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_show_line()

func _advance_dialogue() -> void:
	current_line += 1
	if current_line >= dialogue_lines.size():
		_end_dialogue()
	else:
		_show_line()

func _show_line() -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		var line = "[%s]: %s" % [npc_name, dialogue_lines[current_line]]
		hud.show_interact_prompt(line)
	AIDungeonMaster.narrate_custom(
		"An NPC named " + npc_name + " speaks: '" + dialogue_lines[current_line] + "'"
	)

func _end_dialogue() -> void:
	dialogue_active = false
	var p = get_tree().get_first_node_in_group("player")
	if p: p.set("is_interacting", false)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.hide_interact_prompt()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if quest_to_give != "":
		QuestManager.start_quest(quest_to_give)
		quest_to_give = ""

# ─── Proximity ─────────────────────────────────────────────────────────────────
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_nearby = true
		# Show name labels
		if _name_label: _name_label.visible = true
		var tl = get_node_or_null("TypeLabel")
		if tl: tl.visible = true
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.show_interact_prompt("Talk to " + npc_name)

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_nearby = false
		if _name_label: _name_label.visible = false
		var tl = get_node_or_null("TypeLabel")
		if tl: tl.visible = false
		if not dialogue_active:
			var hud = get_tree().get_first_node_in_group("hud")
			if hud:
				hud.hide_interact_prompt()
